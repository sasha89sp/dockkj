import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import 'ini_storage.dart';
import 'win32_bridge.dart';

// ============================================================================
// Live Diagnostics & Performance Profiler (STRICT ZERO-OVERHEAD WHEN OFF!)
// ============================================================================

class OpStat {
  final String name;
  int calls;
  double totalMs;
  double maxMs;
  double lastMs;

  OpStat({
    required this.name,
    this.calls = 0,
    this.totalMs = 0,
    this.maxMs = 0,
    this.lastMs = 0,
  });

  double get avgMs => calls > 0 ? totalMs / calls : 0.0;

  Map<String, dynamic> toJson() => {
        'name': name,
        'calls': calls,
        'totalMs': double.parse(totalMs.toStringAsFixed(2)),
        'avgMs': double.parse(avgMs.toStringAsFixed(2)),
        'maxMs': double.parse(maxMs.toStringAsFixed(2)),
        'lastMs': double.parse(lastMs.toStringAsFixed(2)),
      };

  static OpStat fromJson(Map<String, dynamic> j) => OpStat(
        name: (j['name'] ?? '').toString(),
        calls: (j['calls'] as num?)?.toInt() ?? 0,
        totalMs: (j['totalMs'] as num?)?.toDouble() ?? 0,
        maxMs: (j['maxMs'] as num?)?.toDouble() ?? 0,
        lastMs: (j['lastMs'] as num?)?.toDouble() ?? 0,
      );
}

class ProcessDebugSnapshot {
  final String processTag;
  final int dockId;
  final int pid;
  final DateTime timestamp;
  final double cpuPercent;
  final double workingSetMb;
  final double privateBytesMb;
  final int gdiObjects;
  final int userObjects;
  final int handleCount;
  final double avgBuildMs;
  final double avgRasterMs;
  final double maxFrameMs;
  final int jankFrames;
  final int framesPerSec;
  final int itemCount;
  final String position;
  final List<OpStat> ops;

  const ProcessDebugSnapshot({
    required this.processTag,
    required this.dockId,
    required this.pid,
    required this.timestamp,
    required this.cpuPercent,
    required this.workingSetMb,
    required this.privateBytesMb,
    required this.gdiObjects,
    required this.userObjects,
    required this.handleCount,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.maxFrameMs,
    required this.jankFrames,
    required this.framesPerSec,
    required this.itemCount,
    required this.position,
    required this.ops,
  });

  String get displayLabel => switch (dockId) {
        1 => 'Панель 1 (Основная)',
        2 => 'Панель 2',
        3 => 'Панель 3',
        4 => 'Разработка',
        0 => 'Окно настроек',
        -1 => 'Окно отладки',
        _ => processTag,
      };

  Map<String, dynamic> toJson() => {
        'tag': processTag,
        'dockId': dockId,
        'pid': pid,
        'ts': timestamp.millisecondsSinceEpoch,
        'cpu': double.parse(cpuPercent.toStringAsFixed(2)),
        'ramMb': double.parse(workingSetMb.toStringAsFixed(1)),
        'privMb': double.parse(privateBytesMb.toStringAsFixed(1)),
        'gdi': gdiObjects,
        'user': userObjects,
        'handles': handleCount,
        'buildMs': double.parse(avgBuildMs.toStringAsFixed(2)),
        'rasterMs': double.parse(avgRasterMs.toStringAsFixed(2)),
        'maxFrameMs': double.parse(maxFrameMs.toStringAsFixed(2)),
        'jank': jankFrames,
        'fps': framesPerSec,
        'items': itemCount,
        'pos': position,
        'ops': ops.map((o) => o.toJson()).toList(),
      };

  static ProcessDebugSnapshot? fromJson(Map<String, dynamic> j) {
    try {
      final opsRaw = (j['ops'] as List?) ?? const [];
      return ProcessDebugSnapshot(
        processTag: (j['tag'] ?? 'dock').toString(),
        dockId: (j['dockId'] as num?)?.toInt() ?? 1,
        pid: (j['pid'] as num?)?.toInt() ?? 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch((j['ts'] as num?)?.toInt() ?? 0),
        cpuPercent: (j['cpu'] as num?)?.toDouble() ?? 0,
        workingSetMb: (j['ramMb'] as num?)?.toDouble() ?? 0,
        privateBytesMb: (j['privMb'] as num?)?.toDouble() ?? 0,
        gdiObjects: (j['gdi'] as num?)?.toInt() ?? 0,
        userObjects: (j['user'] as num?)?.toInt() ?? 0,
        handleCount: (j['handles'] as num?)?.toInt() ?? 0,
        avgBuildMs: (j['buildMs'] as num?)?.toDouble() ?? 0,
        avgRasterMs: (j['rasterMs'] as num?)?.toDouble() ?? 0,
        maxFrameMs: (j['maxFrameMs'] as num?)?.toDouble() ?? 0,
        jankFrames: (j['jank'] as num?)?.toInt() ?? 0,
        framesPerSec: (j['fps'] as num?)?.toInt() ?? 0,
        itemCount: (j['items'] as num?)?.toInt() ?? 0,
        position: (j['pos'] ?? '').toString(),
        ops: opsRaw
            .whereType<Map>()
            .map((m) => OpStat.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

class DebugLogEntry {
  final String time;
  final String level; // INFO | WARN | ERR | PERF | IMPORT
  final String proc;
  final String tag;
  final String message;

  const DebugLogEntry({
    required this.time,
    required this.level,
    required this.proc,
    required this.tag,
    required this.message,
  });

  static DebugLogEntry? parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    try {
      final m = jsonDecode(trimmed);
      if (m is Map) {
        return DebugLogEntry(
          time: (m['t'] ?? '').toString(),
          level: (m['lvl'] ?? 'INFO').toString(),
          proc: (m['p'] ?? '').toString(),
          tag: (m['tag'] ?? '').toString(),
          message: (m['msg'] ?? '').toString(),
        );
      }
    } catch (_) {}
    return DebugLogEntry(
      time: '',
      level: 'INFO',
      proc: '',
      tag: 'raw',
      message: trimmed,
    );
  }
}

class DebugMonitor {
  DebugMonitor._();

  static bool _enabled = false;
  static Directory? _portableDir;
  static String _processTag = 'dock1';
  static int _dockId = 1;
  static int Function()? _itemCountProvider;
  static String Function()? _positionProvider;

  static Timer? _publishTimer;
  static bool _timingsRegistered = false;

  // Per-operation rolling metrics (in-memory, ONLY updated when _enabled == true)
  static final Map<String, OpStat> _ops = {};

  // Frame timing rolling window (ONLY updated when _enabled == true)
  static double _buildSumMs = 0;
  static double _rasterSumMs = 0;
  static double _maxFrameMs = 0;
  static int _frameSamples = 0;
  static int _jankCount = 0;
  static int _framesThisSec = 0;

  static bool get enabled => _enabled;

  static Directory resolveDebugDir(Directory portableDir) =>
      Directory(p.join(portableDir.path, 'Debug'));

  static File _metricsFile(Directory portableDir, String tag) =>
      File(p.join(portableDir.path, 'Debug', 'metrics_$tag.json'));

  static File _eventsFile(Directory portableDir) =>
      File(p.join(portableDir.path, 'Debug', 'events.log'));

  /// Toggle live debug telemetry & logging ON or OFF.
  /// When OFF: cancels timer, removes frame timings callback, and writes ZERO files!
  static void configure({
    required bool enabled,
    required Directory portableDir,
    required String processTag,
    required int dockId,
    int Function()? itemCountProvider,
    String Function()? positionProvider,
  }) {
    _portableDir = portableDir;
    _processTag = processTag;
    _dockId = dockId;
    if (itemCountProvider != null) _itemCountProvider = itemCountProvider;
    if (positionProvider != null) _positionProvider = positionProvider;

    if (enabled == _enabled) return;
    _enabled = enabled;

    if (_enabled) {
      _startActiveProfiling();
      log('INFO', 'system', 'Режим отладки включён ($processTag, PID=${Win32Bridge.currentPid})');
    } else {
      _stopActiveProfiling();
    }
  }

  static void _startActiveProfiling() {
    final dir = _portableDir;
    if (dir != null) {
      try {
        final dbg = resolveDebugDir(dir);
        if (!dbg.existsSync()) dbg.createSync(recursive: true);
      } catch (_) {}
    }

    if (!_timingsRegistered) {
      try {
        SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
        _timingsRegistered = true;
      } catch (_) {}
    }

    // Prime Win32 process CPU baseline
    Win32Bridge.getOwnProcessMetrics();

    _publishTimer?.cancel();
    _publishTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_enabled) return;
      _publishSnapshot();
    });
    // Publish initial snapshot immediately
    _publishSnapshot();
  }

  static void _stopActiveProfiling() {
    _publishTimer?.cancel();
    _publishTimer = null;

    if (_timingsRegistered) {
      try {
        SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
      } catch (_) {}
      _timingsRegistered = false;
    }

    _ops.clear();
    _buildSumMs = 0;
    _rasterSumMs = 0;
    _maxFrameMs = 0;
    _frameSamples = 0;
    _jankCount = 0;
    _framesThisSec = 0;

    // Remove this process's stale metrics file so closed/disabled monitors stay clean
    final dir = _portableDir;
    if (dir != null) {
      try {
        final f = _metricsFile(dir, _processTag);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  static void dispose() {
    _enabled = false;
    _stopActiveProfiling();
  }

  static void _onFrameTimings(List<FrameTiming> timings) {
    if (!_enabled) return;
    for (final t in timings) {
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
      final totalMs = buildMs + rasterMs;
      _buildSumMs += buildMs;
      _rasterSumMs += rasterMs;
      if (totalMs > _maxFrameMs) _maxFrameMs = totalMs;
      _frameSamples++;
      _framesThisSec++;
      if (totalMs > 20.0) {
        _jankCount++;
      }
    }
  }

  /// Zero-overhead synchronous profiler wrapper.
  static T traceSync<T>(String opName, T Function() fn, {double warnThresholdMs = 20.0}) {
    if (!_enabled) return fn();
    final sw = Stopwatch()..start();
    try {
      return fn();
    } finally {
      sw.stop();
      _recordOp(opName, sw.elapsedMicroseconds / 1000.0, warnThresholdMs: warnThresholdMs);
    }
  }

  /// Zero-overhead asynchronous profiler wrapper.
  static Future<T> traceAsync<T>(
    String opName,
    Future<T> Function() fn, {
    double warnThresholdMs = 40.0,
  }) async {
    if (!_enabled) return fn();
    final sw = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      sw.stop();
      _recordOp(opName, sw.elapsedMicroseconds / 1000.0, warnThresholdMs: warnThresholdMs);
    }
  }

  static void _recordOp(String opName, double ms, {double warnThresholdMs = 25.0}) {
    final stat = _ops.putIfAbsent(opName, () => OpStat(name: opName));
    stat.calls++;
    stat.totalMs += ms;
    stat.lastMs = ms;
    if (ms > stat.maxMs) stat.maxMs = ms;
    if (ms >= warnThresholdMs) {
      log(
        'PERF',
        opName,
        'Медленная операция $opName: ${ms.toStringAsFixed(1)} мс (порог ${warnThresholdMs.toStringAsFixed(0)} мс)',
      );
    }
  }

  /// Append a structured log line ONLY when debug mode is enabled.
  static void log(String level, String tag, String message) {
    if (!_enabled) return;
    final dir = _portableDir;
    if (dir == null) return;
    try {
      final dbgDir = resolveDebugDir(dir);
      if (!dbgDir.existsSync()) dbgDir.createSync(recursive: true);
      final f = _eventsFile(dir);

      // Trim file if it exceeds ~110 KB so it never bloats portable folder
      if (f.existsSync() && f.lengthSync() > 110 * 1024) {
        final lines = f.readAsLinesSync();
        final keep = lines.length > 220 ? lines.sublist(lines.length - 220) : lines;
        f.writeAsStringSync('${keep.join('\n')}\n', flush: false);
      }

      final now = DateTime.now();
      final ts =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${(now.millisecond ~/ 10).toString().padLeft(2, '0')}';
      final line = jsonEncode({
        't': ts,
        'lvl': level,
        'p': _processTag,
        'tag': tag,
        'msg': message,
      });
      f.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  static void _publishSnapshot() {
    final dir = _portableDir;
    if (dir == null) return;
    try {
      final m = Win32Bridge.getOwnProcessMetrics();
      final avgBuild = _frameSamples > 0 ? _buildSumMs / _frameSamples : 0.0;
      final avgRaster = _frameSamples > 0 ? _rasterSumMs / _frameSamples : 0.0;
      final fps = _framesThisSec;
      _framesThisSec = 0;

      // Reset rolling frame sums periodically so averages reflect recent performance
      if (_frameSamples > 120) {
        _buildSumMs = avgBuild * 20;
        _rasterSumMs = avgRaster * 20;
        _frameSamples = 20;
      }

      final sortedOps = _ops.values.toList()
        ..sort((a, b) => b.totalMs.compareTo(a.totalMs));

      final snap = ProcessDebugSnapshot(
        processTag: _processTag,
        dockId: _dockId,
        pid: m.pid,
        timestamp: DateTime.now(),
        cpuPercent: m.cpuPercent,
        workingSetMb: m.workingSetMb,
        privateBytesMb: m.privateBytesMb,
        gdiObjects: m.gdiObjects,
        userObjects: m.userObjects,
        handleCount: m.handleCount,
        avgBuildMs: avgBuild,
        avgRasterMs: avgRaster,
        maxFrameMs: _maxFrameMs,
        jankFrames: _jankCount,
        framesPerSec: fps,
        itemCount: _itemCountProvider?.call() ?? 0,
        position: _positionProvider?.call() ?? '',
        ops: sortedOps.take(14).toList(),
      );

      final dbgDir = resolveDebugDir(dir);
      if (!dbgDir.existsSync()) dbgDir.createSync(recursive: true);
      final target = _metricsFile(dir, _processTag);
      final tmp = File('${target.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(snap.toJson()), flush: true);
      try {
        tmp.renameSync(target.path);
      } catch (_) {
        target.writeAsStringSync(jsonEncode(snap.toJson()), flush: true);
        if (tmp.existsSync()) tmp.deleteSync();
      }
    } catch (_) {}
  }

  /// Read live snapshots from ALL currently active AeroDock processes (Dock 1..4 + Settings).
  static List<ProcessDebugSnapshot> readAllProcessSnapshots(Directory portableDir) {
    final result = <ProcessDebugSnapshot>[];
    try {
      final dbgDir = resolveDebugDir(portableDir);
      if (!dbgDir.existsSync()) return result;
      final now = DateTime.now();
      for (final entity in dbgDir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('metrics_') || !name.endsWith('.json')) continue;
        try {
          final raw = entity.readAsStringSync();
          if (raw.trim().isEmpty) continue;
          final map = jsonDecode(raw);
          if (map is Map<String, dynamic>) {
            final snap = ProcessDebugSnapshot.fromJson(map);
            if (snap != null && now.difference(snap.timestamp).inSeconds <= 6) {
              result.add(snap);
            }
          }
        } catch (_) {}
      }
      result.sort((a, b) => a.dockId.compareTo(b.dockId));
    } catch (_) {}
    return result;
  }

  static List<DebugLogEntry> readRecentLogs(Directory portableDir, {int maxLines = 180}) {
    final result = <DebugLogEntry>[];
    try {
      final f = _eventsFile(portableDir);
      if (!f.existsSync()) return result;
      final lines = f.readAsLinesSync();
      final slice = lines.length > maxLines ? lines.sublist(lines.length - maxLines) : lines;
      for (final ln in slice.reversed) {
        final parsed = DebugLogEntry.parseLine(ln);
        if (parsed != null) result.add(parsed);
      }
    } catch (_) {}
    return result;
  }

  static void clearLogs(Directory portableDir) {
    try {
      final f = _eventsFile(portableDir);
      if (f.existsSync()) f.writeAsStringSync('', flush: true);
      final errLog = File(p.join(portableDir.path, 'aerodock_error.log'));
      if (errLog.existsSync()) errLog.writeAsStringSync('', flush: true);
    } catch (_) {}
  }

  /// Automatically diagnose bottlenecks & problems across all running panels.
  static List<String> detectBottlenecks(
    List<ProcessDebugSnapshot> procs,
    List<DebugLogEntry> logs,
  ) {
    final issues = <String>[];
    final totalCpu = procs.fold<double>(0, (s, p) => s + p.cpuPercent);
    final totalRam = procs.fold<double>(0, (s, p) => s + p.workingSetMb);

    if (totalCpu > 6.0) {
      final top = procs.reduce((a, b) => a.cpuPercent >= b.cpuPercent ? a : b);
      issues.add(
        'Повышенная нагрузка CPU (${totalCpu.toStringAsFixed(1)}%). Больше всего грузит: ${top.displayLabel} (${top.cpuPercent.toStringAsFixed(1)}%).',
      );
    }
    if (totalRam > 260) {
      issues.add(
        'Высокое потребление RAM (${totalRam.toStringAsFixed(0)} МБ суммарно по ${procs.length} процессам). Отключите ненужные панели в «Панели (1–3)».',
      );
    }
    for (final proc in procs) {
      if (proc.gdiObjects > 350) {
        issues.add('${proc.displayLabel}: много GDI-объектов (${proc.gdiObjects}) — возможна утечка иконок.');
      }
      if (proc.jankFrames > 5) {
        issues.add(
          '${proc.displayLabel}: зафиксировано ${proc.jankFrames} просадок кадров (макс ${proc.maxFrameMs.toStringAsFixed(1)} мс).',
        );
      }
      for (final op in proc.ops) {
        if (op.avgMs > 12.0 && op.calls >= 3) {
          issues.add(
            '${proc.displayLabel}: медленная подсистема «${op.name}» (ср. ${op.avgMs.toStringAsFixed(1)} мс, макс ${op.maxMs.toStringAsFixed(1)} мс).',
          );
        }
      }
    }

    final recentErrs = logs.where((l) => l.level == 'ERR').length;
    if (recentErrs > 0) {
      issues.add('Зафиксировано ошибок в журнале: $recentErrs (откройте фильтр «Проблемы» ниже).');
    }

    return issues;
  }

  /// Build a compact plain-text diagnostic report for copying & pasting into support/chat.
  static String buildClipboardReport(Directory portableDir, PortableIniStore store) {
    final procs = readAllProcessSnapshots(portableDir);
    final logs = readRecentLogs(portableDir, maxLines: 50);
    final sys = Win32Bridge.getCpuRamStats();
    final sb = StringBuffer()
      ..writeln('=== AeroDock Portable v3.6 — Диагностический отчёт ===')
      ..writeln('Время: ${DateTime.now().toIso8601String()}')
      ..writeln('Система: CPU ${sys.cpuPercent}%, RAM ${sys.ramPercent}% (${sys.usedGb.toStringAsFixed(1)}/${sys.totalGb.toStringAsFixed(1)} ГБ)')
      ..writeln('Папка: ${portableDir.path}')
      ..writeln('Панели включены: D1=1, D2=${store.global.dock2Enabled ? 1 : 0}, D3=${store.global.dock3Enabled ? 1 : 0}, Dev=${store.global.devDockEnabled ? 1 : 0}')
      ..writeln('');

    for (var id = 1; id <= 4; id++) {
      final cfg = store.panels[id];
      final items = store.dockItems[id] ?? const [];
      sb.writeln(
        'Config Dock$id: pos=${cfg?.position}, size=${cfg?.iconSize.round()}px, theme=${cfg?.theme}, items=${items.length} [${items.take(6).map((e) => e.title).join(", ")}]',
      );
    }

    sb.writeln('\n--- Активные процессы (${procs.length}) ---');
    for (final pr in procs) {
      sb.writeln(
        '${pr.displayLabel} (PID ${pr.pid}, pos=${pr.position}, items=${pr.itemCount}): CPU=${pr.cpuPercent.toStringAsFixed(1)}%, RAM=${pr.workingSetMb.toStringAsFixed(1)}MB, GDI=${pr.gdiObjects}, Handles=${pr.handleCount}, Build=${pr.avgBuildMs.toStringAsFixed(1)}ms, Raster=${pr.avgRasterMs.toStringAsFixed(1)}ms, Jank=${pr.jankFrames}',
      );
      for (final op in pr.ops.take(6)) {
        sb.writeln(
          '   op ${op.name}: calls=${op.calls}, avg=${op.avgMs.toStringAsFixed(2)}ms, max=${op.maxMs.toStringAsFixed(2)}ms',
        );
      }
    }

    final issues = detectBottlenecks(procs, logs);
    if (issues.isNotEmpty) {
      sb.writeln('\n--- Обнаруженные проблемы ---');
      for (final iss in issues) {
        sb.writeln('! $iss');
      }
    }

    if (logs.isNotEmpty) {
      sb.writeln('\n--- Последние события (${math.min(30, logs.length)}) ---');
      for (final l in logs.take(30)) {
        sb.writeln('[${l.time}][${l.level}][${l.proc}/${l.tag}] ${l.message}');
      }
    }
    return sb.toString();
  }
}
