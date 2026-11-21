import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ini_storage.dart';
import 'win32_bridge.dart';

class DevDeployEvent {
  final DevAppRule rule;
  final String archiveName;
  final String appDir;
  final String? exePath;
  final bool wasUpgrade;
  final String? backupDir;
  final int preservedConfigCount;
  final String? warning;

  const DevDeployEvent({
    required this.rule,
    required this.archiveName,
    required this.appDir,
    required this.exePath,
    required this.wasUpgrade,
    required this.backupDir,
    required this.preservedConfigCount,
    this.warning,
  });
}

/// Watches the Windows Downloads folder for GitHub release archives matching user rules,
/// automatically backs up previous versions, unpacks new versions over old ones while
/// preserving user settings/config files, and pins/updates the icon on Dock #4 ("Разработка").
class DevArchiveWatcher {
  final PortableIniStore store;
  final void Function(DevDeployEvent event) onDeployed;

  Timer? _timer;
  bool _busy = false;

  // Stability tracking so we never unpack half-downloaded browser archives
  final Map<String, ({int size, DateTime seenAt})> _pendingSizes = {};

  static const Set<String> _archiveExts = {'.zip', '.7z', '.tar', '.gz', '.tgz', '.rar'};
  static const Set<String> _ignoredTempExts = {
    '.crdownload',
    '.part',
    '.tmp',
    '.opdownload',
    '.download',
  };

  DevArchiveWatcher({required this.store, required this.onDeployed});

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => scanOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<int> scanOnce() async {
    if (_busy) return 0;
    final dev = store.devSettings;
    if (dev.rules.isEmpty) return 0;

    final watchDir = Directory(dev.watchFolder);
    if (!watchDir.existsSync()) return 0;

    _busy = true;
    var deployedCount = 0;
    try {
      final entities = watchDir.listSync(followLinks: false);
      // Sort oldest-to-newest so if multiple versions exist, the newest ends up installed last
      final files = entities.whereType<File>().toList();
      files.sort((a, b) {
        try {
          return a.lastModifiedSync().compareTo(b.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      for (final file in files) {
        final fileName = p.basename(file.path);
        final lowerName = fileName.toLowerCase();
        final ext = p.extension(lowerName);
        if (_ignoredTempExts.contains(ext)) continue;
        if (!_archiveExts.contains(ext)) continue;

        final rule = _matchRule(lowerName, dev.rules);
        if (rule == null) continue;

        FileStat stat;
        try {
          stat = file.statSync();
        } catch (_) {
          continue;
        }
        if (stat.size <= 0) continue;

        final sig = '$fileName|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
        if (dev.processedSignatures.contains(sig)) continue;

        // Wait until file size is stable for >= 1.5s and readable without lock
        final prev = _pendingSizes[file.path];
        final now = DateTime.now();
        if (prev == null || prev.size != stat.size) {
          _pendingSizes[file.path] = (size: stat.size, seenAt: now);
          continue;
        }
        if (now.difference(prev.seenAt).inMilliseconds < 1500) {
          continue;
        }
        if (!_canReadExclusively(file)) continue;

        _pendingSizes.remove(file.path);
        final event = await deployArchive(file, rule);
        if (event != null) {
          dev.processedSignatures.insert(0, sig);
          if (dev.processedSignatures.length > 120) {
            dev.processedSignatures = dev.processedSignatures.sublist(0, 120);
          }
          await store.save();
          onDeployed(event);
          deployedCount++;
        }
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
    return deployedCount;
  }

  DevAppRule? _matchRule(String lowerFileName, List<DevAppRule> rules) {
    // Prefer longest matching prefix first
    final sorted = List<DevAppRule>.from(rules)
      ..sort((a, b) => b.archivePrefix.length.compareTo(a.archivePrefix.length));
    for (final r in sorted) {
      final prefix = r.archivePrefix.trim().toLowerCase();
      if (prefix.isEmpty) continue;
      if (lowerFileName.startsWith(prefix)) return r;
    }
    return null;
  }

  bool _canReadExclusively(File f) {
    try {
      final raf = f.openSync(mode: FileMode.read);
      raf.closeSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  String _safeFolderName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return cleaned.isEmpty ? 'DevApp' : cleaned;
  }

  Directory appDirectoryFor(DevAppRule rule) =>
      Directory(p.join(store.devSettings.appsRootFolder, _safeFolderName(rule.name)));

  Directory backupsDirectoryFor(DevAppRule rule) => Directory(
        p.join(store.devSettings.appsRootFolder, '_backups', _safeFolderName(rule.name)),
      );

  /// Deploy or upgrade [archiveFile] according to [rule]:
  /// 1. Extract to temp staging folder (auto-unwrapping single root folder).
  /// 2. If app folder already exists: back up previous version to _backups/<App>/<timestamp>
  ///    and snapshot all settings/config files (.ini, .json, .cfg, .db, custom patterns).
  /// 3. Overlay new files over existing folder & restore preserved settings!
  /// 4. Locate main .exe, extract 128px HD icon, and pin/update icon on Dock #4 ("Разработка").
  Future<DevDeployEvent?> deployArchive(File archiveFile, DevAppRule rule) async {
    final rootDir = Directory(store.devSettings.appsRootFolder);
    if (!rootDir.existsSync()) rootDir.createSync(recursive: true);

    final staging = Directory(
      p.join(rootDir.path, '_staging_${DateTime.now().millisecondsSinceEpoch}'),
    );
    await staging.create(recursive: true);

    try {
      final extracted = await _extractArchive(archiveFile.path, staging.path);
      if (!extracted) return null;

      // Auto-unwrap if archive contains a single top-level directory
      final sourceDir = _unwrapSingleDirectory(staging);

      final appDir = appDirectoryFor(rule);
      final wasUpgrade = appDir.existsSync() && appDir.listSync().isNotEmpty;
      String? backupPath;
      final savedConfigs = <String, List<int>>{};

      if (wasUpgrade) {
        // 1. Save full backup of previous version
        if (rule.keepBackup) {
          final backupsRoot = backupsDirectoryFor(rule);
          if (!backupsRoot.existsSync()) backupsRoot.createSync(recursive: true);
          final ts = _timestampTag(DateTime.now());
          final backupDir = Directory(p.join(backupsRoot.path, 'v${rule.versionCount}_$ts'));
          await _copyDirectory(appDir, backupDir);
          backupPath = backupDir.path;
          _pruneOldBackups(backupsRoot, store.devSettings.maxBackupsPerApp);
        }

        // 2. Snapshot user settings & config files to migrate over the new version
        if (rule.preserveSettings) {
          final preserveExts = store.devSettings.defaultPreserveExts
              .split(',')
              .map((e) => e.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toSet();
          final customNames = rule.preservePatterns
              .split(',')
              .map((e) => e.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toSet();

          await _snapshotConfigs(appDir, appDir.path, preserveExts, customNames, savedConfigs);
        }
      } else {
        await appDir.create(recursive: true);
      }

      // 3. Unpack / overlay new version over appDir
      final lockedFiles = <String>[];
      await _copyDirectory(sourceDir, appDir, lockedFiles: lockedFiles);

      // 4. Restore preserved settings/config files so user config is kept intact!
      var restoredCount = 0;
      for (final entry in savedConfigs.entries) {
        try {
          final dest = File(p.join(appDir.path, entry.key));
          await dest.parent.create(recursive: true);
          await dest.writeAsBytes(entry.value, flush: true);
          restoredCount++;
        } catch (_) {}
      }

      // 5. Optionally archive the downloaded zip
      if (store.devSettings.moveArchiveToStorage) {
        try {
          final archStore = Directory(p.join(rootDir.path, '_archives'));
          if (!archStore.existsSync()) archStore.createSync(recursive: true);
          await archiveFile.rename(p.join(archStore.path, p.basename(archiveFile.path)));
        } catch (_) {}
      }

      // 6. Find main .exe & extract crisp 128px HD icon
      final exePath = _findMainExecutable(appDir, rule);
      final iconPng = exePath != null
          ? Win32Bridge.extractIconToPng(exePath, store.iconsCacheDir)
          : null;

      // 7. Update rule metadata & upsert icon on Dock #4 ("Разработка")
      rule.lastArchiveName = p.basename(archiveFile.path);
      rule.lastUpdated = _timestampReadable(DateTime.now());
      rule.versionCount += 1;

      final devItems = store.dockItems.putIfAbsent(4, () => PortableIniStore.defaultItemsFor(4));
      final existingIdx = devItems.indexWhere((i) => i.devRuleId == rule.id);
      final target = exePath ?? appDir.path;
      final item = DockItemModel(
        id: existingIdx >= 0 ? devItems[existingIdx].id : 'devapp_${rule.id}',
        type: exePath != null ? 'file' : 'path',
        title: rule.name,
        target: target,
        startIn: appDir.path,
        iconKey: exePath != null ? 'rocket' : 'folder-emerald',
        color: '#7C3AED',
        iconPath: iconPng,
        devRuleId: rule.id,
      );

      if (existingIdx >= 0) {
        // Keep custom user-picked icon if they explicitly chose one outside cache
        final prevIcon = devItems[existingIdx].iconPath;
        if (safeFileExists(prevIcon) &&
            !prevIcon!.startsWith(store.iconsCacheDir.path)) {
          item.iconPath = prevIcon;
        }
        devItems[existingIdx] = item;
      } else {
        devItems.add(item);
      }

      // Ensure Dev panel is enabled so user immediately sees their app!
      store.global.devDockEnabled = true;
      await store.save();

      return DevDeployEvent(
        rule: rule,
        archiveName: p.basename(archiveFile.path),
        appDir: appDir.path,
        exePath: exePath,
        wasUpgrade: wasUpgrade,
        backupDir: backupPath,
        preservedConfigCount: restoredCount,
        warning: lockedFiles.isEmpty
            ? null
            : 'Некоторые файлы были заняты (${lockedFiles.length}). Закройте программу и повторите.',
      );
    } finally {
      try {
        if (staging.existsSync()) staging.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Roll back a Dev App to its most recent saved backup in 1 click!
  Future<String?> rollbackLatestBackup(DevAppRule rule) async {
    final backupsRoot = backupsDirectoryFor(rule);
    if (!backupsRoot.existsSync()) return null;
    final dirs = backupsRoot.listSync().whereType<Directory>().toList();
    if (dirs.isEmpty) return null;
    dirs.sort((a, b) => b.path.compareTo(a.path));
    final latest = dirs.first;
    final appDir = appDirectoryFor(rule);
    await _copyDirectory(latest, appDir);
    return p.basename(latest.path);
  }

  Future<bool> _extractArchive(String archivePath, String destDir) async {
    // 1. Native Windows bsdtar (Windows 10 1803+ & Windows 11): super fast, supports zip/tar/7z/rar!
    try {
      final res = await Process.run('tar.exe', ['-xf', archivePath, '-C', destDir]);
      if (res.exitCode == 0 && Directory(destDir).listSync().isNotEmpty) {
        return true;
      }
    } catch (_) {}

    // 2. Fallback: PowerShell Expand-Archive for standard .zip
    if (p.extension(archivePath).toLowerCase() == '.zip') {
      try {
        final escSrc = archivePath.replaceAll("'", "''");
        final escDst = destDir.replaceAll("'", "''");
        final res = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            "Expand-Archive -LiteralPath '$escSrc' -DestinationPath '$escDst' -Force",
          ],
        );
        if (res.exitCode == 0 && Directory(destDir).listSync().isNotEmpty) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Directory _unwrapSingleDirectory(Directory dir) {
    final entries = dir
        .listSync(followLinks: false)
        .where((e) => !p.basename(e.path).startsWith('__MACOSX'))
        .toList();
    if (entries.length == 1 && entries.first is Directory) {
      return entries.first as Directory;
    }
    return dir;
  }

  Future<void> _snapshotConfigs(
    Directory dir,
    String rootPath,
    Set<String> exts,
    Set<String> customNames,
    Map<String, List<int>> out,
  ) async {
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: rootPath);
        final lowerName = p.basename(entity.path).toLowerCase();
        final ext = p.extension(lowerName);
        // Skip huge binary/cache files (>5MB) and Flutter framework assets
        if (rel.toLowerCase().startsWith(r'data\flutter_assets')) continue;
        final isMatch = exts.contains(ext) ||
            customNames.any((pat) => lowerName == pat || lowerName.contains(pat));
        if (!isMatch) continue;
        try {
          if (await entity.length() <= 5 * 1024 * 1024) {
            out[rel] = await entity.readAsBytes();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _copyDirectory(
    Directory src,
    Directory dst, {
    List<String>? lockedFiles,
  }) async {
    if (!await dst.exists()) await dst.create(recursive: true);
    await for (final entity in src.list(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      final targetPath = p.join(dst.path, name);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath), lockedFiles: lockedFiles);
      } else if (entity is File) {
        try {
          await entity.copy(targetPath);
        } catch (_) {
          lockedFiles?.add(name);
        }
      }
    }
  }

  void _pruneOldBackups(Directory backupsRoot, int maxKeep) {
    try {
      final dirs = backupsRoot.listSync().whereType<Directory>().toList();
      if (dirs.length <= maxKeep) return;
      dirs.sort((a, b) => b.path.compareTo(a.path));
      for (var i = maxKeep; i < dirs.length; i++) {
        try {
          dirs[i].deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  String? _findMainExecutable(Directory appDir, DevAppRule rule) {
    final hint = rule.exeHint.trim().toLowerCase();
    final exes = <File>[];

    try {
      for (final entity in appDir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (p.extension(entity.path).toLowerCase() != '.exe') continue;
        final base = p.basename(entity.path).toLowerCase();
        if (hint.isNotEmpty && base == hint) return entity.path;
        if (base.contains('unins') || base.contains('crash') || base.contains('update')) {
          continue;
        }
        exes.add(entity);
      }
    } catch (_) {}

    if (exes.isEmpty) return null;

    // Prefer root-level .exe matching rule name or prefix, then largest root .exe
    final nameKey = rule.name.toLowerCase().replaceAll(' ', '');
    final prefixKey = rule.archivePrefix.toLowerCase().split(RegExp(r'[-_\s]')).first;

    exes.sort((a, b) {
      final aDepth = p.split(p.relative(a.path, from: appDir.path)).length;
      final bDepth = p.split(p.relative(b.path, from: appDir.path)).length;
      if (aDepth != bDepth) return aDepth.compareTo(bDepth);

      final aBase = p.basenameWithoutExtension(a.path).toLowerCase();
      final bBase = p.basenameWithoutExtension(b.path).toLowerCase();
      final aMatch = (aBase.contains(nameKey) || (prefixKey.length >= 3 && aBase.contains(prefixKey))) ? 0 : 1;
      final bMatch = (bBase.contains(nameKey) || (prefixKey.length >= 3 && bBase.contains(prefixKey))) ? 0 : 1;
      if (aMatch != bMatch) return aMatch.compareTo(bMatch);

      return b.lengthSync().compareTo(a.lengthSync());
    });

    return exes.first.path;
  }

  static String _timestampTag(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}_${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}${d.second.toString().padLeft(2, '0')}';

  static String _timestampReadable(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
