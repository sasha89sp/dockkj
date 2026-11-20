import { DockItem, DockSettings } from '../types/dock';
import { generateAeroDockIcoBytes } from './icoGenerator';
import { buildPortableConfigObject } from './windowsPortableGenerator';
import { buildZipArchive } from './zipBuilder';

export function buildFlutterPubspecYaml(): string {
  return `name: aerodock
description: Портативная док-панель для Windows в стиле RocketDock на Flutter.
publish_to: 'none'
version: 2.0.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  window_manager: ^0.4.3
  flutter_acrylic: ^1.1.4
  screen_retriever: ^0.2.0
  tray_manager: ^0.2.4
  hotkey_manager: ^0.2.3
  desktop_drop: ^0.5.0
  file_picker: ^8.1.4
  url_launcher: ^6.3.1
  path: ^1.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/app_icon.ico
`;
}

export function buildFlutterModelsDart(): string {
  return `import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class DockSettingsModel {
  String position; // bottom | top | left | right
  String theme; // crystal | aero3d | graphite | silk | minimal | retro
  double iconSize;
  double zoomScale;
  double opacity;
  double edgeOffset;
  bool autoHide;
  bool lockIcons;
  bool topmost;
  bool showLabels;
  bool showRunningIndicators;
  int displayIndex;
  bool useAcrylic;
  bool launchWithWindows;
  bool hotkeyEnabled;

  DockSettingsModel({
    this.position = 'bottom',
    this.theme = 'aero3d',
    this.iconSize = 54,
    this.zoomScale = 1.55,
    this.opacity = 82,
    this.edgeOffset = 10,
    this.autoHide = false,
    this.lockIcons = false,
    this.topmost = true,
    this.showLabels = true,
    this.showRunningIndicators = true,
    this.displayIndex = 0,
    this.useAcrylic = false,
    this.launchWithWindows = false,
    this.hotkeyEnabled = true,
  });

  factory DockSettingsModel.fromJson(Map<String, dynamic> json) {
    return DockSettingsModel(
      position: (json['position'] as String?) ?? 'bottom',
      theme: (json['theme'] as String?) ?? 'aero3d',
      iconSize: ((json['iconSize'] as num?) ?? 54).toDouble().clamp(36, 76),
      zoomScale: ((json['zoomScale'] as num?) ?? 1.55).toDouble().clamp(1.0, 2.0),
      opacity: ((json['opacity'] as num?) ?? 82).toDouble().clamp(25, 100),
      edgeOffset: ((json['edgeOffset'] as num?) ?? 10).toDouble().clamp(0, 48),
      autoHide: (json['autoHide'] as bool?) ?? false,
      lockIcons: (json['lockIcons'] as bool?) ?? false,
      topmost: (json['topmost'] as bool?) ?? true,
      showLabels: (json['showLabels'] as bool?) ?? true,
      showRunningIndicators: (json['showRunningIndicators'] as bool?) ?? true,
      displayIndex: ((json['displayIndex'] as num?) ?? 0).toInt(),
      useAcrylic: (json['useAcrylic'] as bool?) ?? false,
      launchWithWindows: (json['launchWithWindows'] as bool?) ?? false,
      hotkeyEnabled: (json['hotkeyEnabled'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'position': position,
        'theme': theme,
        'iconSize': iconSize.round(),
        'zoomScale': double.parse(zoomScale.toStringAsFixed(2)),
        'opacity': opacity.round(),
        'edgeOffset': edgeOffset.round(),
        'autoHide': autoHide,
        'lockIcons': lockIcons,
        'topmost': topmost,
        'showLabels': showLabels,
        'showRunningIndicators': showRunningIndicators,
        'displayIndex': displayIndex,
        'useAcrylic': useAcrylic,
        'launchWithWindows': launchWithWindows,
        'hotkeyEnabled': hotkeyEnabled,
      };
}

class StackLinkModel {
  final String id;
  String title;
  String target;
  String color;
  String badge;

  StackLinkModel({
    required this.id,
    required this.title,
    required this.target,
    this.color = '#0284c7',
    this.badge = 'LN',
  });

  factory StackLinkModel.fromJson(Map<String, dynamic> json) {
    return StackLinkModel(
      id: (json['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: (json['title'] as String?) ?? 'Ссылка',
      target: (json['target'] as String?) ?? '',
      color: (json['color'] as String?) ?? '#0284c7',
      badge: (json['badge'] as String?) ?? 'LN',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'target': target,
        'color': color,
        'badge': badge,
      };
}

class DockItemModel {
  final String id;
  String type; // app | url | stack | separator
  String title;
  String target;
  String args;
  String color;
  String badge;
  String? iconFile; // relative filename inside portable icons/ folder
  List<StackLinkModel> stackItems;

  DockItemModel({
    required this.id,
    required this.type,
    required this.title,
    required this.target,
    this.args = '',
    this.color = '#0284c7',
    this.badge = 'AD',
    this.iconFile,
    List<StackLinkModel>? stackItems,
  }) : stackItems = stackItems ?? [];

  factory DockItemModel.fromJson(Map<String, dynamic> json) {
    final rawStack = (json['stackItems'] as List<dynamic>?) ?? const [];
    return DockItemModel(
      id: (json['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      type: (json['type'] as String?) ?? 'app',
      title: (json['title'] as String?) ?? 'Ярлык',
      target: (json['target'] as String?) ?? '',
      args: (json['args'] as String?) ?? '',
      color: (json['color'] as String?) ?? '#0284c7',
      badge: (json['badge'] as String?) ?? 'AD',
      iconFile: json['iconFile'] as String?,
      stackItems: rawStack
          .whereType<Map<String, dynamic>>()
          .map(StackLinkModel.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'target': target,
        'args': args,
        'color': color,
        'badge': badge,
        if (iconFile != null && iconFile!.isNotEmpty) 'iconFile': iconFile,
        if (type == 'stack') 'stackItems': stackItems.map((e) => e.toJson()).toList(),
      };
}

/// Portable storage next to aerodock.exe (zero Registry / AppData writes).
class PortableConfigStore {
  final Directory portableDir;
  final File configFile;
  final Directory iconsDir;
  DockSettingsModel settings;
  List<DockItemModel> items;

  PortableConfigStore({
    required this.portableDir,
    required this.configFile,
    required this.iconsDir,
    required this.settings,
    required this.items,
  });

  static Directory resolvePortableDir() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    if (File(p.join(exeDir.path, 'aerodock-config.json')).existsSync()) {
      return exeDir;
    }
    if (File(p.join(Directory.current.path, 'aerodock-config.json')).existsSync()) {
      return Directory.current;
    }
    return exeDir;
  }

  File? resolveIconFile(DockItemModel item) {
    if (item.iconFile == null || item.iconFile!.isEmpty) return null;
    final f = File(p.join(iconsDir.path, item.iconFile!));
    return f.existsSync() ? f : null;
  }

  static Future<PortableConfigStore> load() async {
    final dir = resolvePortableDir();
    final file = File(p.join(dir.path, 'aerodock-config.json'));
    final icons = Directory(p.join(dir.path, 'icons'));
    if (!await icons.exists()) {
      await icons.create(recursive: true);
    }

    if (await file.exists()) {
      try {
        var raw = await file.readAsString();
        if (raw.startsWith('\\uFEFF')) raw = raw.substring(1);
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final settings = DockSettingsModel.fromJson(
          (decoded['settings'] as Map<String, dynamic>?) ?? const {},
        );
        final itemsRaw = (decoded['items'] as List<dynamic>?) ?? const [];
        final items = itemsRaw
            .whereType<Map<String, dynamic>>()
            .map(DockItemModel.fromJson)
            .toList();
        return PortableConfigStore(
          portableDir: dir,
          configFile: file,
          iconsDir: icons,
          settings: settings,
          items: items,
        );
      } catch (_) {}
    }

    return PortableConfigStore(
      portableDir: dir,
      configFile: file,
      iconsDir: icons,
      settings: DockSettingsModel(),
      items: [
        DockItemModel(id: 'exp', type: 'app', title: 'Проводник', target: 'explorer.exe', color: '#d97706', badge: 'ПР'),
        DockItemModel(id: 'not', type: 'app', title: 'Блокнот', target: 'notepad.exe', color: '#0284c7', badge: 'БЛ'),
        DockItemModel(id: 'clc', type: 'app', title: 'Калькулятор', target: 'calc.exe', color: '#334155', badge: 'КЛ'),
        DockItemModel(id: 'dl', type: 'stack', title: 'Загрузки', target: '%USERPROFILE%\\\\Downloads', color: '#d97706', badge: 'ЗГ'),
        DockItemModel(id: 'sep', type: 'separator', title: 'Разделитель', target: '', color: '#64748b', badge: '|'),
        DockItemModel(id: 'bin', type: 'app', title: 'Корзина', target: 'explorer.exe', args: 'shell:RecycleBinFolder', color: '#64748b', badge: 'КР'),
      ],
    );
  }

  Future<void> save() async {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'portable': true,
      'settings': settings.toJson(),
      'items': items.map((e) => e.toJson()).toList(),
    });
    await configFile.writeAsString(payload, flush: true);
  }
}
`;
}

export function buildFlutterWindowsServicesDart(): string {
  return `import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

class FolderEntryInfo {
  final String name;
  final String fullPath;
  final bool isDirectory;

  const FolderEntryInfo({
    required this.name,
    required this.fullPath,
    required this.isDirectory,
  });
}

class WindowsServices {
  /// Expands Windows environment variables like %USERPROFILE%, %APPDATA%, %LOCALAPPDATA%.
  static String expandEnv(String raw) {
    return raw.replaceAllMapped(
      RegExp(r'%([^%]+)%'),
      (m) => Platform.environment[m.group(1)!] ?? m.group(0)!,
    );
  }

  /// Extracts the lowercase .exe filename for matching against Windows tasklist.
  static String? extractProcessExeName(String target) {
    final expanded = expandEnv(target).trim();
    if (expanded.isEmpty ||
        expanded.startsWith('http://') ||
        expanded.startsWith('https://') ||
        expanded.startsWith('ms-')) {
      return null;
    }
    final base = p.basename(expanded).toLowerCase();
    if (base.endsWith('.exe')) return base;
    return null;
  }

  /// Queries running Windows processes via tasklist (lightweight, zero external deps).
  static Future<Set<String>> queryRunningProcesses() async {
    try {
      final res = await Process.run(
        'tasklist',
        ['/FO', 'CSV', '/NH'],
        runInShell: false,
      );
      if (res.exitCode != 0) return const {};
      final lines = res.stdout.toString().split(RegExp(r'\\r?\\n'));
      final names = <String>{};
      for (final line in lines) {
        if (line.isEmpty) continue;
        final firstQuoteEnd = line.indexOf('"', 1);
        if (line.startsWith('"') && firstQuoteEnd > 1) {
          names.add(line.substring(1, firstQuoteEnd).toLowerCase());
        }
      }
      return names;
    } catch (_) {
      return const {};
    }
  }

  /// Extracts a real native Windows icon from .exe / .lnk into portable icons/<id>.png.
  static Future<String?> extractNativeIconPng({
    required String target,
    required Directory iconsDir,
    required String itemId,
  }) async {
    final expanded = expandEnv(target).trim();
    if (expanded.isEmpty ||
        expanded.startsWith('http://') ||
        expanded.startsWith('https://') ||
        expanded.startsWith('ms-')) {
      return null;
    }

    final safeId = itemId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final fileName = '\$safeId.png';
    final outPath = p.join(iconsDir.path, fileName);

    final escTarget = expanded.replaceAll("'", "''");
    final escOut = outPath.replaceAll("'", "''");

    final ps = '''
Add-Type -AssemblyName System.Drawing
\\\$t = '\$escTarget'
if (\\\$t.ToLower().EndsWith('.lnk') -and (Test-Path \\\$t)) {
  \\\$sh = New-Object -ComObject WScript.Shell
  \\\$sc = \\\$sh.CreateShortcut(\\\$t)
  if (\\\$sc.TargetPath) { \\\$t = \\\$sc.TargetPath }
}
if (-not (Test-Path \\\$t -PathType Leaf)) {
  \\\$cmd = Get-Command \\\$t -ErrorAction SilentlyContinue
  if (\\\$cmd -and \\\$cmd.Source) { \\\$t = \\\$cmd.Source }
}
if (Test-Path \\\$t -PathType Leaf) {
  \\\$ico = [System.Drawing.Icon]::ExtractAssociatedIcon(\\\$t)
  if (\\\$ico) {
    \\\$bmp = \\\$ico.ToBitmap()
    \\\$bmp.Save('\$escOut', [System.Drawing.Imaging.ImageFormat]::Png)
    \\\$bmp.Dispose()
    \\\$ico.Dispose()
  }
}
''';

    try {
      await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', ps],
        runInShell: false,
      );
      if (await File(outPath).exists()) {
        return fileName;
      }
    } catch (_) {}
    return null;
  }

  /// Launches a URL, folder, .exe, or protocol URI cleanly.
  static Future<void> launchTarget({
    required String type,
    required String target,
    String args = '',
  }) async {
    final trimmed = target.trim();
    if (trimmed.isEmpty) return;

    if (type == 'url' || trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final resolved = expandEnv(trimmed);
    final argList = args.trim().isEmpty ? <String>[] : args.trim().split(RegExp(r'\\s+'));

    try {
      if (Directory(resolved).existsSync()) {
        await Process.start('explorer.exe', [resolved], mode: ProcessStartMode.detached);
        return;
      }
      if (resolved.contains(':') && !resolved.contains('\\\\')) {
        // Windows protocol URI (e.g. ms-settings:, ms-clock:)
        await Process.start('cmd', ['/c', 'start', '', resolved], runInShell: true, mode: ProcessStartMode.detached);
        return;
      }
      await Process.start(
        resolved,
        argList,
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      await Process.start(
        'cmd',
        ['/c', 'start', '', resolved, ...argList],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
    }
  }

  /// Lists real files & subfolders inside a Windows directory for Live Folder Stacks.
  static List<FolderEntryInfo> listDirectoryEntries(String rawDirPath, {int limit = 24}) {
    final resolved = expandEnv(rawDirPath).trim();
    if (resolved.isEmpty) return const [];
    final dir = Directory(resolved);
    if (!dir.existsSync()) return const [];
    try {
      final entities = dir.listSync(followLinks: false);
      final dirs = <FolderEntryInfo>[];
      final files = <FolderEntryInfo>[];
      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('.') || name.toLowerCase() == 'desktop.ini') continue;
        final isDir = e is Directory;
        final info = FolderEntryInfo(name: name, fullPath: e.path, isDirectory: isDir);
        if (isDir) {
          dirs.add(info);
        } else {
          files.add(info);
        }
      }
      dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return [...dirs, ...files].take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  static File _startupLinkFile() {
    final appData = Platform.environment['APPDATA'] ?? '';
    return File(p.join(appData, 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup', 'AeroDock Portable.lnk'));
  }

  static bool isStartupEnabled() {
    try {
      return _startupLinkFile().existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Creates or removes a Windows Startup shortcut in shell:startup (no admin rights required).
  static Future<bool> setStartupEnabled(bool enable) async {
    final lnk = _startupLinkFile();
    try {
      if (!enable) {
        if (await lnk.exists()) await lnk.delete();
        return false;
      }
      final exe = Platform.resolvedExecutable.replaceAll("'", "''");
      final workDir = File(Platform.resolvedExecutable).parent.path.replaceAll("'", "''");
      final lnkPath = lnk.path.replaceAll("'", "''");
      final ps = '''
\\\$sh = New-Object -ComObject WScript.Shell
\\\$sc = \\\$sh.CreateShortcut('\$lnkPath')
\\\$sc.TargetPath = '\$exe'
\\\$sc.WorkingDirectory = '\$workDir'
\\\$sc.Description = 'AeroDock Portable'
\\\$sc.Save()
''';
      await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', ps],
        runInShell: false,
      );
      return await lnk.exists();
    } catch (_) {
      return false;
    }
  }
}
`;
}

export function buildFlutterDialogsDart(): string {
  return `import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:screen_retriever/screen_retriever.dart';

import 'models.dart';
import 'windows_services.dart';

const kDockSwatches = [
  '#0284c7',
  '#4f46e5',
  '#059669',
  '#d97706',
  '#e11d48',
  '#334155',
  '#0d9488',
  '#7c3aed',
];

const kDockThemeOptions = <Map<String, String>>[
  {'id': 'aero3d', 'label': 'Аэро 3D'},
  {'id': 'crystal', 'label': 'Кристалл'},
  {'id': 'graphite', 'label': 'Графит'},
  {'id': 'silk', 'label': 'Светлый шёлк'},
  {'id': 'minimal', 'label': 'Минимал'},
  {'id': 'retro', 'label': 'Ретро Металл'},
];

Color parseHexColor(String hex, [double opacity = 1.0]) {
  final cleaned = hex.replaceFirst('#', '');
  final value =
      int.tryParse(cleaned.length == 6 ? 'FF\$cleaned' : cleaned, radix: 16) ?? 0xFF0284C7;
  return Color(value).withOpacity(opacity.clamp(0.0, 1.0));
}

/// Built-in Settings panel rendered inside aerodock.exe.
class DockSettingsPanel extends StatefulWidget {
  final DockSettingsModel settings;
  final List<Display> displays;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  final Future<void> Function(bool enabled) onToggleStartup;
  final Future<void> Function(bool enabled) onToggleHotkey;
  final Future<void> Function(bool useAcrylic) onToggleAcrylic;

  const DockSettingsPanel({
    super.key,
    required this.settings,
    required this.displays,
    required this.onChanged,
    required this.onClose,
    required this.onToggleStartup,
    required this.onToggleHotkey,
    required this.onToggleAcrylic,
  });

  @override
  State<DockSettingsPanel> createState() => _DockSettingsPanelState();
}

class _DockSettingsPanelState extends State<DockSettingsPanel> {
  DockSettingsModel get s => widget.settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF20F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 28)],
      ),
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF020617).withOpacity(0.65),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                const Text(
                  'Настройки AeroDock Portable',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                  tooltip: 'Закрыть',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Text('Расположение и монитор', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final pair in [
                      ['bottom', 'Снизу'],
                      ['top', 'Сверху'],
                      ['left', 'Слева'],
                      ['right', 'Справа'],
                    ])
                      ChoiceChip(
                        label: Text(pair[1]),
                        selected: s.position == pair[0],
                        onSelected: (_) {
                          setState(() => s.position = pair[0]);
                          widget.onChanged();
                        },
                      ),
                  ],
                ),
                if (widget.displays.length > 1) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Монитор:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: s.displayIndex.clamp(0, widget.displays.length - 1),
                        dropdownColor: const Color(0xFF0F172A),
                        items: List.generate(widget.displays.length, (i) {
                          final d = widget.displays[i];
                          return DropdownMenuItem(
                            value: i,
                            child: Text(
                              'Экран \${i + 1} (\${d.size.width.round()}×\${d.size.height.round()})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        }),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => s.displayIndex = val);
                            widget.onChanged();
                          }
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Тема оформления', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in kDockThemeOptions)
                      ChoiceChip(
                        label: Text(t['label']!),
                        selected: s.theme == t['id'],
                        onSelected: (_) {
                          setState(() => s.theme = t['id']!);
                          widget.onChanged();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _sliderRow('Размер значков', '\${s.iconSize.round()} px', s.iconSize, 36, 76, (v) {
                  setState(() => s.iconSize = v);
                  widget.onChanged();
                }),
                _sliderRow('Увеличение при наведении', '\${(s.zoomScale * 100).round()}%', s.zoomScale, 1.0, 2.0, (v) {
                  setState(() => s.zoomScale = v);
                  widget.onChanged();
                }),
                _sliderRow('Прозрачность панели', '\${s.opacity.round()}%', s.opacity, 25, 100, (v) {
                  setState(() => s.opacity = v);
                  widget.onChanged();
                }),
                _sliderRow('Отступ от края экрана', '\${s.edgeOffset.round()} px', s.edgeOffset, 0, 48, (v) {
                  setState(() => s.edgeOffset = v);
                  widget.onChanged();
                }),
                const Divider(height: 24, color: Colors.white12),
                SwitchListTile(
                  dense: true,
                  title: const Text('Системное размытие Acrylic (Windows 10/11)', style: TextStyle(fontSize: 12)),
                  value: s.useAcrylic,
                  onChanged: (v) async {
                    setState(() => s.useAcrylic = v);
                    await widget.onToggleAcrylic(v);
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Автоскрытие панели у края экрана', style: TextStyle(fontSize: 12)),
                  value: s.autoHide,
                  onChanged: (v) {
                    setState(() => s.autoHide = v);
                    widget.onChanged();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Закрепить значки (отключить перетаскивание)', style: TextStyle(fontSize: 12)),
                  value: s.lockIcons,
                  onChanged: (v) {
                    setState(() => s.lockIcons = v);
                    widget.onChanged();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Индикатор запущенных программ Windows', style: TextStyle(fontSize: 12)),
                  value: s.showRunningIndicators,
                  onChanged: (v) {
                    setState(() => s.showRunningIndicators = v);
                    widget.onChanged();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Глобальная клавиша Alt+Space (показать/скрыть)', style: TextStyle(fontSize: 12)),
                  value: s.hotkeyEnabled,
                  onChanged: (v) async {
                    setState(() => s.hotkeyEnabled = v);
                    await widget.onToggleHotkey(v);
                  },
                ),
                SwitchListTile(
                  dense: true,
                  title: const Text('Запускать вместе с Windows (shell:startup)', style: TextStyle(fontSize: 12)),
                  value: s.launchWithWindows,
                  onChanged: (v) async {
                    await widget.onToggleStartup(v);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow(
    String label,
    String valueText,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text(valueText, style: const TextStyle(fontSize: 12, color: Color(0xFF38BDF8))),
          ],
        ),
        Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}

/// Built-in Item Properties Editor inside aerodock.exe (add/edit .exe, URL, Stack, custom PNG icon).
class ItemPropertiesPanel extends StatefulWidget {
  final DockItemModel? initialItem;
  final String defaultType;
  final Directory iconsDir;
  final void Function(DockItemModel item) onSave;
  final VoidCallback onClose;

  const ItemPropertiesPanel({
    super.key,
    this.initialItem,
    this.defaultType = 'app',
    required this.iconsDir,
    required this.onSave,
    required this.onClose,
  });

  @override
  State<ItemPropertiesPanel> createState() => _ItemPropertiesPanelState();
}

class _ItemPropertiesPanelState extends State<ItemPropertiesPanel> {
  late String _type;
  late TextEditingController _titleCtrl;
  late TextEditingController _targetCtrl;
  late TextEditingController _argsCtrl;
  late String _color;
  String? _iconFile;
  late List<StackLinkModel> _stackItems;
  final _subTitleCtrl = TextEditingController();
  final _subUrlCtrl = TextEditingController(text: 'https://');

  @override
  void initState() {
    super.initState();
    final itm = widget.initialItem;
    _type = itm?.type ?? widget.defaultType;
    _titleCtrl = TextEditingController(text: itm?.title ?? '');
    _targetCtrl = TextEditingController(text: itm?.target ?? (_type == 'url' ? 'https://' : ''));
    _argsCtrl = TextEditingController(text: itm?.args ?? '');
    _color = itm?.color ?? '#0284c7';
    _iconFile = itm?.iconFile;
    _stackItems = List.of(itm?.stackItems ?? []);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _targetCtrl.dispose();
    _argsCtrl.dispose();
    _subTitleCtrl.dispose();
    _subUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExeOrFolder() async {
    if (_type == 'stack') {
      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Выберите папку для стека');
      if (dir != null) {
        setState(() {
          _targetCtrl.text = dir;
          if (_titleCtrl.text.trim().isEmpty) _titleCtrl.text = p.basename(dir);
        });
      }
      return;
    }
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите программу (.exe) или ярлык',
      type: FileType.custom,
      allowedExtensions: ['exe', 'lnk', 'bat', 'cmd'],
    );
    final chosen = res?.files.single.path;
    if (chosen != null) {
      setState(() {
        _targetCtrl.text = chosen;
        if (_titleCtrl.text.trim().isEmpty) {
          _titleCtrl.text = p.basenameWithoutExtension(chosen);
        }
      });
    }
  }

  Future<void> _pickCustomPng() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите значок (.png / .jpg / .ico)',
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'ico', 'webp'],
    );
    final src = res?.files.single.path;
    if (src == null) return;
    final ext = p.extension(src);
    final name = 'custom_\${DateTime.now().millisecondsSinceEpoch}\$ext';
    final dest = File(p.join(widget.iconsDir.path, name));
    await File(src).copy(dest.path);
    setState(() => _iconFile = name);
  }

  Future<void> _extractIconNow() async {
    final id = widget.initialItem?.id ?? 'item_\${DateTime.now().millisecondsSinceEpoch}';
    final extracted = await WindowsServices.extractNativeIconPng(
      target: _targetCtrl.text,
      iconsDir: widget.iconsDir,
      itemId: id,
    );
    if (extracted != null && mounted) {
      setState(() => _iconFile = extracted);
    }
  }

  void _submit() {
    final title = _titleCtrl.text.trim().isEmpty ? 'Ярлык' : _titleCtrl.text.trim();
    final target = _targetCtrl.text.trim();
    final badge = title.length >= 2 ? title.substring(0, 2).toUpperCase() : title.toUpperCase();
    widget.onSave(
      DockItemModel(
        id: widget.initialItem?.id ?? 'item-\${DateTime.now().millisecondsSinceEpoch}',
        type: _type,
        title: title,
        target: target,
        args: _argsCtrl.text.trim(),
        color: _color,
        badge: badge,
        iconFile: _iconFile,
        stackItems: _type == 'stack' ? _stackItems : const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconPreviewFile =
        (_iconFile != null && _iconFile!.isNotEmpty) ? File(p.join(widget.iconsDir.path, _iconFile!)) : null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF50F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.16)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 28)],
      ),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF020617).withOpacity(0.65),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              children: [
                Text(
                  widget.initialItem == null ? 'Новый значок на панели' : 'Свойства значка',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final pair in [
                      ['app', 'Программа Windows'],
                      ['url', 'Веб-ссылка (URL)'],
                      ['stack', 'Стек (Папка / Ссылки)'],
                    ])
                      ChoiceChip(
                        label: Text(pair[1], style: const TextStyle(fontSize: 12)),
                        selected: _type == pair[0],
                        onSelected: (_) => setState(() => _type = pair[0]),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: parseHexColor(_color),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: (iconPreviewFile != null && iconPreviewFile.existsSync())
                          ? Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.file(iconPreviewFile, fit: BoxFit.contain),
                            )
                          : Center(
                              child: Text(
                                _titleCtrl.text.trim().isEmpty
                                    ? 'AD'
                                    : _titleCtrl.text.trim().substring(0, _titleCtrl.text.trim().length >= 2 ? 2 : 1).toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickCustomPng,
                            icon: const Icon(Icons.image_outlined, size: 15),
                            label: const Text('Свой PNG/ICO', style: TextStyle(fontSize: 12)),
                          ),
                          if (_type == 'app')
                            OutlinedButton.icon(
                              onPressed: _extractIconNow,
                              icon: const Icon(Icons.auto_fix_high, size: 15),
                              label: const Text('Взять из .exe', style: TextStyle(fontSize: 12)),
                            ),
                          if (_iconFile != null)
                            TextButton(
                              onPressed: () => setState(() => _iconFile = null),
                              child: const Text('Сбросить', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Название значка', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _targetCtrl,
                        decoration: InputDecoration(
                          labelText: _type == 'url'
                              ? 'URL адрес (https://...)'
                              : _type == 'stack'
                                  ? 'Путь к папке Windows (необязательно для группы ссылок)'
                                  : 'Путь к .exe или папке Windows',
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_type != 'url') ...[
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: _pickExeOrFolder, child: const Text('Обзор…')),
                    ],
                  ],
                ),
                if (_type == 'app') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _argsCtrl,
                    decoration: const InputDecoration(labelText: 'Аргументы запуска (необязательно)', isDense: true),
                  ),
                ],
                if (_type == 'stack') ...[
                  const SizedBox(height: 14),
                  Text('Ссылки внутри стека (\${_stackItems.length})', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(height: 6),
                  for (var i = 0; i < _stackItems.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_stackItems[i].title, style: const TextStyle(fontSize: 12)),
                      subtitle: Text(_stackItems[i].target, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                        onPressed: () => setState(() => _stackItems.removeAt(i)),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _subTitleCtrl,
                          decoration: const InputDecoration(hintText: 'Название', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _subUrlCtrl,
                          decoration: const InputDecoration(hintText: 'https://...', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: () {
                          final t = _subTitleCtrl.text.trim();
                          final u = _subUrlCtrl.text.trim();
                          if (t.isEmpty || u.isEmpty) return;
                          setState(() {
                            _stackItems.add(StackLinkModel(
                              id: 'st-\${DateTime.now().millisecondsSinceEpoch}',
                              title: t,
                              target: u,
                              badge: t.substring(0, t.length >= 2 ? 2 : 1).toUpperCase(),
                            ));
                            _subTitleCtrl.clear();
                            _subUrlCtrl.text = 'https://';
                          });
                        },
                        icon: const Icon(Icons.add_circle, color: Color(0xFF38BDF8)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final hex in kDockSwatches)
                      GestureDetector(
                        onTap: () => setState(() => _color = hex),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: parseHexColor(hex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == hex ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: widget.onClose, child: const Text('Отмена')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _submit, child: const Text('Сохранить')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live Stack Popover showing real Windows folder files OR nested link group.
class LiveStackPopover extends StatelessWidget {
  final DockItemModel item;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  const LiveStackPopover({
    super.key,
    required this.item,
    required this.onClose,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isRealFolder = item.target.trim().isNotEmpty;
    final folderEntries = isRealFolder
        ? WindowsServices.listDirectoryEntries(item.target, limit: 24)
        : const <FolderEntryInfo>[];

    return Container(
      width: 310,
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: const Color(0xF00F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 24)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 15, color: Colors.white70),
                  tooltip: 'Настроить стек',
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Flexible(
            child: isRealFolder
                ? (folderEntries.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Папка пуста или не найдена', style: TextStyle(fontSize: 12, color: Colors.white54)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: folderEntries.length,
                        itemBuilder: (_, idx) {
                          final entry = folderEntries[idx];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              entry.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                              size: 18,
                              color: entry.isDirectory ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
                            ),
                            title: Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                            onTap: () async {
                              onClose();
                              await WindowsServices.launchTarget(type: 'app', target: entry.fullPath);
                            },
                          );
                        },
                      ))
                : (item.stackItems.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('В стеке пока нет ссылок', style: TextStyle(fontSize: 12, color: Colors.white54)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: item.stackItems.length,
                        itemBuilder: (_, idx) {
                          final link = item.stackItems[idx];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 13,
                              backgroundColor: parseHexColor(link.color),
                              child: Text(link.badge, style: const TextStyle(fontSize: 10, color: Colors.white)),
                            ),
                            title: Text(link.title, style: const TextStyle(fontSize: 12, color: Colors.white)),
                            subtitle: Text(
                              link.target,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: Colors.white54),
                            ),
                            onTap: () async {
                              onClose();
                              await WindowsServices.launchTarget(type: 'url', target: link.target);
                            },
                          );
                        },
                      )),
          ),
          if (isRealFolder)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    onClose();
                    await WindowsServices.launchTarget(type: 'app', target: item.target);
                  },
                  icon: const Icon(Icons.folder_open, size: 15),
                  label: const Text('Открыть в Проводнике', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
`;
}

export function buildFlutterMainDart(): string {
  return `import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path/path.dart' as p;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'dialogs.dart';
import 'models.dart';
import 'windows_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await acrylic.Window.initialize();
  await hotKeyManager.unregisterAll();

  final store = await PortableConfigStore.load();
  store.settings.launchWithWindows = WindowsServices.isStartupEnabled();

  const windowOptions = WindowOptions(
    size: Size(760, 140),
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(store.settings.topmost);
    await acrylic.Window.setEffect(
      effect: store.settings.useAcrylic
          ? acrylic.WindowEffect.acrylic
          : acrylic.WindowEffect.transparent,
      color: store.settings.useAcrylic
          ? const Color(0x550F172A)
          : const Color(0x00000000),
    );
    await windowManager.show();
  });

  runApp(AeroDockFlutterApp(initialStore: store));
}

class AeroDockFlutterApp extends StatelessWidget {
  final PortableConfigStore initialStore;

  const AeroDockFlutterApp({super.key, required this.initialStore});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AeroDock Portable',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0EA5E9),
          brightness: Brightness.dark,
        ),
      ),
      home: DockShellPage(store: initialStore),
    );
  }
}

enum _ActiveOverlay { none, settings, itemEditor, stack }

class DockShellPage extends StatefulWidget {
  final PortableConfigStore store;

  const DockShellPage({super.key, required this.store});

  @override
  State<DockShellPage> createState() => _DockShellPageState();
}

class _DockShellPageState extends State<DockShellPage> with TrayListener, WindowListener {
  double? _pointerAxis;
  int? _hoveredIndex;
  String? _bouncingId;
  bool _isDraggingFile = false;
  bool _isAutoHidden = false;

  _ActiveOverlay _overlay = _ActiveOverlay.none;
  DockItemModel? _editingItem;
  String _editorDefaultType = 'app';
  DockItemModel? _openStackItem;

  List<Display> _displays = [];
  Set<String> _runningProcesses = {};
  Timer? _processPollTimer;

  final HotKey _toggleHotKey = HotKey(
    key: PhysicalKeyboardKey.space,
    modifiers: [HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );

  DockSettingsModel get _settings => widget.store.settings;
  List<DockItemModel> get _items => widget.store.items;
  bool get _isHorizontal =>
      _settings.position == 'bottom' || _settings.position == 'top';

  @override
  void initState() {
    super.initState();
    _isAutoHidden = _settings.autoHide;
    trayManager.addListener(this);
    windowManager.addListener(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initSystemTray();
      await _applyHotkey(_settings.hotkeyEnabled);
      await _refreshDisplays();
      await _syncWindowGeometry();
      _extractMissingNativeIcons();
      _refreshRunningProcesses();
    });

    _processPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshRunningProcesses(),
    );
  }

  @override
  void dispose() {
    _processPollTimer?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    hotKeyManager.unregisterAll();
    super.dispose();
  }

  Future<void> _initSystemTray() async {
    try {
      await trayManager.setIcon('assets/app_icon.ico');
      await trayManager.setToolTip('AeroDock Portable (Alt+Space)');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'toggle', label: 'Показать / Скрыть (Alt+Space)'),
            MenuItem(key: 'settings', label: 'Настройки панели…'),
            MenuItem.separator(),
            MenuItem(key: 'add_exe', label: 'Добавить программу (.exe)…'),
            MenuItem(key: 'add_url', label: 'Добавить веб-ссылку…'),
            MenuItem(key: 'open_dir', label: 'Открыть папку AeroDock'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: 'Выход из AeroDock'),
          ],
        ),
      );
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() {
    _toggleDockVisibility();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle':
        _toggleDockVisibility();
        break;
      case 'settings':
        _openOverlay(_ActiveOverlay.settings);
        break;
      case 'add_exe':
        _addProgramFromPicker();
        break;
      case 'add_url':
        _editingItem = null;
        _editorDefaultType = 'url';
        _openOverlay(_ActiveOverlay.itemEditor);
        break;
      case 'open_dir':
        WindowsServices.launchTarget(type: 'app', target: widget.store.portableDir.path);
        break;
      case 'exit':
        _exitApp();
        break;
    }
  }

  Future<void> _applyHotkey(bool enabled) async {
    try {
      await hotKeyManager.unregisterAll();
      if (enabled) {
        await hotKeyManager.register(
          _toggleHotKey,
          keyDownHandler: (_) => _toggleDockVisibility(),
        );
      }
    } catch (_) {}
  }

  Future<void> _toggleDockVisibility() async {
    final visible = await windowManager.isVisible();
    if (!visible) {
      await windowManager.show();
      await windowManager.focus();
      setState(() => _isAutoHidden = false);
      await _syncWindowGeometry();
    } else if (_settings.autoHide) {
      setState(() => _isAutoHidden = !_isAutoHidden);
      await _syncWindowGeometry();
      if (!_isAutoHidden) await windowManager.focus();
    } else if (_overlay != _ActiveOverlay.none) {
      await _closeOverlay();
    } else {
      await windowManager.hide();
    }
  }

  Future<void> _refreshDisplays() async {
    try {
      final list = await screenRetriever.getAllDisplays();
      if (mounted) {
        setState(() => _displays = list);
      }
    } catch (_) {}
  }

  Future<Display> _getActiveDisplay() async {
    if (_displays.isEmpty) {
      await _refreshDisplays();
    }
    if (_displays.isNotEmpty) {
      final idx = _settings.displayIndex.clamp(0, _displays.length - 1);
      return _displays[idx];
    }
    return await screenRetriever.getPrimaryDisplay();
  }

  Future<void> _extractMissingNativeIcons() async {
    var changed = false;
    for (final item in _items) {
      if (item.type == 'app' && (item.iconFile == null || item.iconFile!.isEmpty)) {
        final png = await WindowsServices.extractNativeIconPng(
          target: item.target,
          iconsDir: widget.store.iconsDir,
          itemId: item.id,
        );
        if (png != null) {
          item.iconFile = png;
          changed = true;
        }
      }
    }
    if (changed && mounted) {
      setState(() {});
      await widget.store.save();
    }
  }

  Future<void> _refreshRunningProcesses() async {
    if (!_settings.showRunningIndicators) return;
    final set = await WindowsServices.queryRunningProcesses();
    if (mounted) {
      setState(() => _runningProcesses = set);
    }
  }

  bool _isItemRunning(DockItemModel item) {
    if (!_settings.showRunningIndicators || item.type != 'app') return false;
    final exe = WindowsServices.extractProcessExeName(item.target);
    if (exe == null || exe == 'explorer.exe') return false;
    return _runningProcesses.contains(exe);
  }

  Future<void> _openOverlay(_ActiveOverlay mode) async {
    await _refreshDisplays();
    setState(() {
      _overlay = mode;
      _isAutoHidden = false;
    });
    await windowManager.show();
    await _syncWindowGeometry();
    await windowManager.focus();
  }

  Future<void> _closeOverlay() async {
    setState(() {
      _overlay = _ActiveOverlay.none;
      _openStackItem = null;
      _editingItem = null;
    });
    await _syncWindowGeometry();
  }

  Future<void> _syncWindowGeometry() async {
    final display = await _getActiveDisplay();
    final workSize = display.visibleSize ?? display.size;
    final workPos = display.visiblePosition ?? Offset.zero;

    if (_overlay == _ActiveOverlay.settings || _overlay == _ActiveOverlay.itemEditor) {
      const w = 640.0;
      const h = 540.0;
      final left = workPos.dx + (workSize.width - w) / 2;
      final top = workPos.dy + (workSize.height - h) / 2;
      await windowManager.setBounds(Rect.fromLTWH(left, top, w, h));
      return;
    }

    final base = _settings.iconSize;
    final maxIcon = base * _settings.zoomScale;
    final itemCount = _items.where((i) => i.type != 'separator').length;
    final sepCount = _items.where((i) => i.type == 'separator').length;

    final stackOpen = _overlay == _ActiveOverlay.stack;
    final mainSpan = math.max(
      stackOpen ? 360.0 : 240.0,
      itemCount * (base + 14) + sepCount * 18 + maxIcon * 1.15 + 56,
    );
    final crossSpan = (stackOpen ? 390.0 : 0.0) + maxIcon + 58;

    final winWidth = _isHorizontal
        ? math.min(mainSpan, workSize.width - 20)
        : math.min(crossSpan, workSize.width - 20);
    final winHeight = _isHorizontal
        ? math.min(crossSpan, workSize.height - 20)
        : math.min(mainSpan, workSize.height - 20);

    final hideShift =
        (_settings.autoHide && _isAutoHidden && !stackOpen) ? (crossSpan - 10) : 0.0;
    final edge = _settings.edgeOffset;

    double left;
    double top;
    switch (_settings.position) {
      case 'top':
        left = workPos.dx + (workSize.width - winWidth) / 2;
        top = workPos.dy + edge - hideShift;
        break;
      case 'left':
        left = workPos.dx + edge - hideShift;
        top = workPos.dy + (workSize.height - winHeight) / 2;
        break;
      case 'right':
        left = workPos.dx + workSize.width - winWidth - edge + hideShift;
        top = workPos.dy + (workSize.height - winHeight) / 2;
        break;
      default:
        left = workPos.dx + (workSize.width - winWidth) / 2;
        top = workPos.dy + workSize.height - winHeight - edge + hideShift;
        break;
    }

    await windowManager.setBounds(Rect.fromLTWH(left, top, winWidth, winHeight));
  }

  double _computeScaleForIndex(int index, double itemCenter) {
    if (_pointerAxis == null) return 1.0;
    final radius = _settings.iconSize * 2.4;
    final dist = (_pointerAxis! - itemCenter).abs();
    if (dist >= radius) return 1.0;
    final ratio = math.cos((dist / radius) * (math.pi / 2));
    return 1.0 + (_settings.zoomScale - 1.0) * math.pow(ratio, 1.35);
  }

  Future<void> _onTapItem(DockItemModel item) async {
    setState(() => _bouncingId = item.id);
    Future.delayed(const Duration(milliseconds: 380), () {
      if (mounted && _bouncingId == item.id) {
        setState(() => _bouncingId = null);
      }
    });

    if (item.type == 'stack') {
      if (_overlay == _ActiveOverlay.stack && _openStackItem?.id == item.id) {
        await _closeOverlay();
      } else {
        _openStackItem = item;
        await _openOverlay(_ActiveOverlay.stack);
      }
      return;
    }

    await WindowsServices.launchTarget(
      type: item.type,
      target: item.target,
      args: item.args,
    );
    Future.delayed(const Duration(milliseconds: 900), _refreshRunningProcesses);
  }

  Future<void> _addProgramFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите программу (.exe) или ярлык',
      type: FileType.custom,
      allowedExtensions: ['exe', 'lnk', 'bat', 'cmd'],
    );
    final chosen = result?.files.single.path;
    if (chosen != null) {
      await _appendDroppedPath(chosen);
    }
  }

  Future<void> _addFolderStackFromPicker() async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Выберите папку (откроется как живой стек на доке)',
    );
    if (dirPath == null) return;
    final title = p.basename(dirPath).isNotEmpty ? p.basename(dirPath) : dirPath;
    final badge = title.length >= 2 ? title.substring(0, 2).toUpperCase() : title.toUpperCase();
    setState(() {
      _items.add(DockItemModel(
        id: 'stack-\${DateTime.now().millisecondsSinceEpoch}',
        type: 'stack',
        title: title,
        target: dirPath,
        color: '#d97706',
        badge: badge,
      ));
    });
    await widget.store.save();
    await _syncWindowGeometry();
  }

  Future<void> _appendDroppedPath(String path) async {
    final isDir = Directory(path).existsSync();
    final name = p.basenameWithoutExtension(path).isNotEmpty
        ? p.basenameWithoutExtension(path)
        : p.basename(path);
    final badge = name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
    final id = 'win-\${DateTime.now().millisecondsSinceEpoch}';

    final iconFile = isDir
        ? null
        : await WindowsServices.extractNativeIconPng(
            target: path,
            iconsDir: widget.store.iconsDir,
            itemId: id,
          );

    setState(() {
      _items.add(DockItemModel(
        id: id,
        type: isDir ? 'stack' : 'app',
        title: name,
        target: path,
        color: isDir ? '#d97706' : '#0284c7',
        badge: badge,
        iconFile: iconFile,
      ));
    });
    await widget.store.save();
    await _syncWindowGeometry();
  }

  Future<void> _exitApp() async {
    await hotKeyManager.unregisterAll();
    await trayManager.destroy();
    await windowManager.close();
    exit(0);
  }

  Future<void> _showDockContextMenu(Offset globalPos, int? itemIndex) async {
    final entries = <PopupMenuEntry<String>>[];

    if (itemIndex != null) {
      final itm = _items[itemIndex];
      if (itm.type != 'separator') {
        entries.add(PopupMenuItem(value: 'open', child: Text('Открыть: \${itm.title}')));
        entries.add(const PopupMenuItem(value: 'edit', child: Text('Свойства значка…')));
      }
      entries.add(const PopupMenuItem(value: 'delete', child: Text('Удалить с панели')));
      entries.add(const PopupMenuDivider());
    }

    entries.addAll([
      const PopupMenuItem(value: 'add_exe', child: Text('Добавить программу (.exe)…')),
      const PopupMenuItem(value: 'add_url', child: Text('Добавить веб-ссылку…')),
      const PopupMenuItem(value: 'add_stack', child: Text('Добавить папку-стек…')),
      const PopupMenuItem(value: 'add_sep', child: Text('Добавить разделитель')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'settings', child: Text('Настройки панели…')),
      CheckedPopupMenuItem(value: 'toggle_autohide', checked: _settings.autoHide, child: const Text('Автоскрытие')),
      CheckedPopupMenuItem(value: 'toggle_lock', checked: _settings.lockIcons, child: const Text('Закрепить значки')),
      const PopupMenuItem(value: 'open_dir', child: Text('Открыть папку AeroDock')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'exit', child: Text('Выход')),
    ]);

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      items: entries,
    );
    if (choice == null) return;

    switch (choice) {
      case 'open':
        if (itemIndex != null) await _onTapItem(_items[itemIndex]);
        break;
      case 'edit':
        if (itemIndex != null) {
          _editingItem = _items[itemIndex];
          _openOverlay(_ActiveOverlay.itemEditor);
        }
        break;
      case 'delete':
        if (itemIndex != null) {
          setState(() => _items.removeAt(itemIndex));
          await widget.store.save();
          await _syncWindowGeometry();
        }
        break;
      case 'add_exe':
        await _addProgramFromPicker();
        break;
      case 'add_url':
        _editingItem = null;
        _editorDefaultType = 'url';
        await _openOverlay(_ActiveOverlay.itemEditor);
        break;
      case 'add_stack':
        await _addFolderStackFromPicker();
        break;
      case 'add_sep':
        setState(() {
          _items.add(DockItemModel(
            id: 'sep-\${DateTime.now().millisecondsSinceEpoch}',
            type: 'separator',
            title: 'Разделитель',
            target: '',
            color: '#64748b',
            badge: '|',
          ));
        });
        await widget.store.save();
        await _syncWindowGeometry();
        break;
      case 'settings':
        await _openOverlay(_ActiveOverlay.settings);
        break;
      case 'toggle_autohide':
        setState(() {
          _settings.autoHide = !_settings.autoHide;
          _isAutoHidden = false;
        });
        await widget.store.save();
        await _syncWindowGeometry();
        break;
      case 'toggle_lock':
        setState(() => _settings.lockIcons = !_settings.lockIcons);
        await widget.store.save();
        break;
      case 'open_dir':
        await WindowsServices.launchTarget(type: 'app', target: widget.store.portableDir.path);
        break;
      case 'exit':
        await _exitApp();
        break;
    }
  }

  BoxDecoration _buildShelfDecoration() {
    final alpha = (_settings.opacity / 100.0).clamp(0.25, 1.0);
    switch (_settings.theme) {
      case 'silk':
        return BoxDecoration(
          color: Colors.white.withOpacity(0.84 * alpha),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.92)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.24), blurRadius: 18)],
        );
      case 'graphite':
        return BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.92 * alpha),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF94A3B8).withOpacity(0.25)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
        );
      case 'retro':
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFCBD5E1).withOpacity(0.9 * alpha),
              const Color(0xFF475569).withOpacity(0.95 * alpha),
              const Color(0xFF1E293B).withOpacity(0.96 * alpha),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.45)),
        );
      case 'minimal':
        return BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.48 * alpha),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        );
      default:
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(0.24 * alpha),
              const Color(0xFF0F172A).withOpacity(0.68 * alpha),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isDraggingFile
                ? const Color(0xFF38BDF8)
                : Colors.white.withOpacity(0.36 * alpha),
            width: _isDraggingFile ? 2 : 1,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 20)],
        );
    }
  }

  Widget _buildIconTile(DockItemModel item, double visualSize, int idx) {
    final iconFile = widget.store.resolveIconFile(item);
    final isRunning = _isItemRunning(item);
    final isLight = _settings.theme == 'silk';

    final core = Container(
      width: visualSize,
      height: visualSize,
      decoration: BoxDecoration(
        gradient: iconFile != null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  parseHexColor(item.color),
                  Color.lerp(parseHexColor(item.color), const Color(0xFF020617), 0.38)!,
                ],
              ),
        color: iconFile != null ? const Color(0x550F172A) : null,
        borderRadius: BorderRadius.circular(visualSize * 0.24),
        border: Border.all(
          color: _hoveredIndex == idx
              ? Colors.white.withOpacity(0.75)
              : Colors.white.withOpacity(0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.38),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: iconFile != null
          ? Padding(
              padding: EdgeInsets.all(visualSize * 0.12),
              child: Image.file(iconFile, fit: BoxFit.contain, filterQuality: FilterQuality.high),
            )
          : Center(
              child: item.type == 'stack'
                  ? Icon(Icons.folder_rounded, color: Colors.white, size: visualSize * 0.56)
                  : Text(
                      item.badge,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: math.max(12, visualSize * 0.30),
                      ),
                    ),
            ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        core,
        if (isRunning)
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFF0F172A) : const Color(0xFF7DD3FC),
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Color(0xAA7DD3FC), blurRadius: 6)],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_overlay == _ActiveOverlay.settings) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: DockSettingsPanel(
            settings: _settings,
            displays: _displays,
            onChanged: () async {
              setState(() {});
              await widget.store.save();
              await _syncWindowGeometry();
            },
            onClose: _closeOverlay,
            onToggleStartup: (enabled) async {
              final res = await WindowsServices.setStartupEnabled(enabled);
              _settings.launchWithWindows = res;
              await widget.store.save();
            },
            onToggleHotkey: (enabled) async {
              await _applyHotkey(enabled);
              await widget.store.save();
            },
            onToggleAcrylic: (useAcrylic) async {
              await acrylic.Window.setEffect(
                effect: useAcrylic
                    ? acrylic.WindowEffect.acrylic
                    : acrylic.WindowEffect.transparent,
                color: useAcrylic ? const Color(0x550F172A) : const Color(0x00000000),
              );
              await widget.store.save();
            },
          ),
        ),
      );
    }

    if (_overlay == _ActiveOverlay.itemEditor) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: ItemPropertiesPanel(
            initialItem: _editingItem,
            defaultType: _editorDefaultType,
            iconsDir: widget.store.iconsDir,
            onClose: _closeOverlay,
            onSave: (saved) async {
              final idx = _items.indexWhere((i) => i.id == saved.id);
              setState(() {
                if (idx >= 0) {
                  _items[idx] = saved;
                } else {
                  _items.add(saved);
                }
              });
              await widget.store.save();
              await _closeOverlay();
              _extractMissingNativeIcons();
            },
          ),
        ),
      );
    }

    final base = _settings.iconSize;
    final align = _settings.position == 'bottom'
        ? Alignment.bottomCenter
        : _settings.position == 'top'
            ? Alignment.topCenter
            : _settings.position == 'left'
                ? Alignment.centerLeft
                : Alignment.centerRight;

    final dockWidget = Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _buildShelfDecoration(),
      child: Flex(
        direction: _isHorizontal ? Axis.horizontal : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: _settings.position == 'bottom'
            ? CrossAxisAlignment.end
            : _settings.position == 'top'
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
        children: List.generate(_items.length, (idx) {
          final item = _items[idx];
          if (item.type == 'separator') {
            return GestureDetector(
              onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition, idx),
              child: Container(
                margin: EdgeInsets.symmetric(
                  horizontal: _isHorizontal ? 6 : 2,
                  vertical: _isHorizontal ? 2 : 6,
                ),
                width: _isHorizontal ? 1.5 : base * 0.65,
                height: _isHorizontal ? base * 0.65 : 1.5,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.32),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }

          final approxCenter = 22.0 + idx * (base + 12) + base / 2;
          final scale = _computeScaleForIndex(idx, approxCenter);
          final visualSize = base * scale;
          final isBouncing = _bouncingId == item.id;
          final lift = ((scale - 1.0) * 14) + (isBouncing ? 14 : 0);

          final offset = _settings.position == 'bottom'
              ? Offset(0, -lift)
              : _settings.position == 'top'
                  ? Offset(0, lift)
                  : _settings.position == 'left'
                      ? Offset(lift, 0)
                      : Offset(-lift, 0);

          final tile = MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hoveredIndex = idx),
            child: GestureDetector(
              onTap: () => _onTapItem(item),
              onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition, idx),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(offset.dx, offset.dy, 0),
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: _buildIconTile(item, visualSize, idx),
              ),
            ),
          );

          final interactiveTile = _settings.lockIcons
              ? tile
              : DragTarget<int>(
                  onAcceptWithDetails: (details) async {
                    final from = details.data;
                    if (from == idx) return;
                    setState(() {
                      final moved = _items.removeAt(from);
                      _items.insert(idx, moved);
                    });
                    await widget.store.save();
                  },
                  builder: (context, candidate, _) {
                    return Draggable<int>(
                      data: idx,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Opacity(
                          opacity: 0.85,
                          child: _buildIconTile(item, base * 1.1, idx),
                        ),
                      ),
                      childWhenDragging: Opacity(opacity: 0.35, child: tile),
                      child: candidate.isNotEmpty
                          ? Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF38BDF8), width: 2),
                              ),
                              child: tile,
                            )
                          : tile,
                    );
                  },
                );

          return _settings.showLabels
              ? Tooltip(
                  message: item.title,
                  waitDuration: const Duration(milliseconds: 120),
                  child: interactiveTile,
                )
              : interactiveTile;
        }),
      ),
    );

    final stackPopover = (_overlay == _ActiveOverlay.stack && _openStackItem != null)
        ? Padding(
            padding: const EdgeInsets.all(8),
            child: LiveStackPopover(
              item: _openStackItem!,
              onClose: _closeOverlay,
              onEdit: () {
                _editingItem = _openStackItem;
                _openOverlay(_ActiveOverlay.itemEditor);
              },
            ),
          )
        : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingFile = true),
        onDragExited: (_) => setState(() => _isDraggingFile = false),
        onDragDone: (details) async {
          setState(() => _isDraggingFile = false);
          for (final file in details.files) {
            await _appendDroppedPath(file.path);
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            if (_settings.autoHide && _isAutoHidden) {
              setState(() => _isAutoHidden = false);
              _syncWindowGeometry();
            }
          },
          onHover: (ev) {
            setState(() {
              _pointerAxis = _isHorizontal ? ev.localPosition.dx : ev.localPosition.dy;
            });
          },
          onExit: (_) {
            setState(() {
              _pointerAxis = null;
              _hoveredIndex = null;
            });
            if (_settings.autoHide && !_isAutoHidden && _overlay == _ActiveOverlay.none) {
              setState(() => _isAutoHidden = true);
              _syncWindowGeometry();
            }
          },
          child: GestureDetector(
            onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition, null),
            child: Align(
              alignment: align,
              child: stackPopover == null
                  ? dockWidget
                  : (_isHorizontal
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _settings.position == 'bottom'
                              ? [stackPopover, dockWidget]
                              : [dockWidget, stackPopover],
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: _settings.position == 'right'
                              ? [stackPopover, dockWidget]
                              : [dockWidget, stackPopover],
                        )),
            ),
          ),
        ),
      ),
    );
  }
}
`;
}

export function buildFlutterPortableBatScript(): string {
  return `@echo off\r\n` +
    `chcp 65001 >nul\r\n` +
    `setlocal\r\n\r\n` +
    `echo ======================================================\r\n` +
    `echo   Сборка портативной версии AeroDock (Flutter Windows)\r\n` +
    `echo ======================================================\r\n\r\n` +
    `where flutter >nul 2>nul\r\n` +
    `if errorlevel 1 (\r\n` +
    `  echo [ОШИБКА] Flutter SDK не найден в PATH.\r\n` +
    `  echo Установите Flutter или соберите в облаке через GitHub Actions.\r\n` +
    `  pause\r\n` +
    `  exit /b 1\r\n` +
    `)\r\n\r\n` +
    `if not exist "windows" (\r\n` +
    `  echo [1/5] Инициализация Windows-раннера Flutter...\r\n` +
    `  call flutter create --platforms=windows --project-name aerodock .\r\n` +
    `  if errorlevel 1 ( pause & exit /b 1 )\r\n` +
    `)\r\n\r\n` +
    `if exist "assets\\app_icon.ico" (\r\n` +
    `  echo [2/5] Установка фирменной иконки aerodock.exe...\r\n` +
    `  copy /Y "assets\\app_icon.ico" "windows\\runner\\resources\\app_icon.ico" >nul\r\n` +
    `)\r\n\r\n` +
    `echo [3/5] Загрузка зависимостей (pub get)...\r\n` +
    `call flutter pub get\r\n` +
    `if errorlevel 1 ( pause & exit /b 1 )\r\n\r\n` +
    `echo [4/5] Компиляция Release-версии под Windows x64...\r\n` +
    `call flutter build windows --release\r\n` +
    `if errorlevel 1 ( pause & exit /b 1 )\r\n\r\n` +
    `echo [5/5] Упаковка портативной папки AeroDock-Portable-EXE...\r\n` +
    `if exist "AeroDock-Portable-EXE" rmdir /s /q "AeroDock-Portable-EXE"\r\n` +
    `mkdir "AeroDock-Portable-EXE"\r\n` +
    `xcopy /E /I /Y "build\\windows\\x64\\runner\\Release\\*" "AeroDock-Portable-EXE\\" >nul\r\n` +
    `copy /Y "aerodock-config.json" "AeroDock-Portable-EXE\\aerodock-config.json" >nul\r\n\r\n` +
    `echo.\r\n` +
    `echo Готово! Портативная версия собрана в папке: AeroDock-Portable-EXE\r\n` +
    `explorer "AeroDock-Portable-EXE"\r\n` +
    `pause\r\n`;
}

export function buildGitHubActionsWorkflowYaml(): string {
  return `name: Build AeroDock Windows Portable

on:
  push:
    branches: [ main, master ]
    tags: [ 'v*' ]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build-windows:
    runs-on: windows-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Flutter (3.29.3 stable)
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.29.3'
          channel: 'stable'
          cache: true

      - name: Enable Windows Desktop, init runner & apply custom .ico
        shell: pwsh
        run: |
          flutter config --enable-windows-desktop
          if (-not (Test-Path "windows")) {
            flutter create --platforms=windows --project-name aerodock .
          }
          if (Test-Path "test/widget_test.dart") {
            Remove-Item -Force "test/widget_test.dart"
          }
          if (Test-Path "assets/app_icon.ico") {
            Copy-Item -Force "assets/app_icon.ico" "windows/runner/resources/app_icon.ico"
          }

      - name: Install dependencies
        run: flutter pub get

      - name: Build Windows Release (.exe)
        run: flutter build windows --release

      - name: Package Portable ZIP
        shell: pwsh
        run: |
          New-Item -ItemType Directory -Force -Path "dist/AeroDock-Portable" | Out-Null
          Copy-Item -Recurse -Force "build/windows/x64/runner/Release/*" "dist/AeroDock-Portable/"
          if (Test-Path "aerodock-config.json") {
            Copy-Item -Force "aerodock-config.json" "dist/AeroDock-Portable/aerodock-config.json"
          }
          Compress-Archive -Path "dist/AeroDock-Portable/*" -DestinationPath "dist/AeroDock-Windows-Portable-x64.zip" -Force

      - name: Upload Portable Artifact
        uses: actions/upload-artifact@v4
        with:
          name: AeroDock-Windows-Portable-x64
          path: dist/AeroDock-Windows-Portable-x64.zip
          retention-days: 30

      - name: Publish GitHub Release (on tag v*)
        if: startsWith(github.ref, 'refs/tags/v')
        shell: pwsh
        env:
          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}
        run: |
          $tag = "\${{ github.ref_name }}"
          gh release create $tag "dist/AeroDock-Windows-Portable-x64.zip" \`
            --title "AeroDock Portable $tag" \`
            --notes "Портативная сборка AeroDock на Flutter для Windows x64. Распакуйте и запустите aerodock.exe."
`;
}

export function buildFlutterGitignore(): string {
  return `.dart_tool/\r\n` +
    `.packages\r\n` +
    `build/\r\n` +
    `dist/\r\n` +
    `AeroDock-Portable-EXE/\r\n` +
    `icons/\r\n` +
    `.flutter-plugins\r\n` +
    `.flutter-plugins-dependencies\r\n`;
}

export function buildFlutterReadmeRu(): string {
  return `=======================================================\r\n` +
    `  AeroDock Portable v2 — Flutter для Windows (GitHub CI)\r\n` +
    `=======================================================\r\n\r\n` +
    `Полноценная нативная док-панель в стиле RocketDock на Flutter Desktop.\r\n` +
    `Полностью портативна: все настройки (aerodock-config.json) и извлечённые\r\n` +
    `значки (папка icons/) хранятся строго рядом с aerodock.exe.\r\n\r\n` +
    `ВКЛЮЧЁННЫЕ ВОЗМОЖНОСТИ:\r\n` +
    `1. Настоящая прозрачность окна и эффект Acrylic (flutter_acrylic)\r\n` +
    `2. Автоизвлечение родных иконок .exe/.lnk в icons/ + выбор своих PNG/ICO\r\n` +
    `3. Встроенные окна «Настройки панели» и «Свойства значка» внутри aerodock.exe\r\n` +
    `4. Иконка в системном трее, выбор монитора и автозагрузка (shell:startup)\r\n` +
    `5. Индикаторы запущенных программ Windows и перетаскивание иконок мышью\r\n` +
    `6. Живые стеки реальных папок Windows (например, Загрузки) и групп ссылок\r\n` +
    `7. Глобальная клавиша Alt+Space и фирменная иконка aerodock.exe\r\n\r\n` +
    `СБОРКА В ОБЛАКЕ НА GITHUB ACTIONS (БЕЗ FLUTTER НА ПК):\r\n` +
    `1. Создайте репозиторий на github.com и загрузите все файлы (включая .github).\r\n` +
    `2. Откройте Actions -> "Build AeroDock Windows Portable".\r\n` +
    `3. Скачайте готовый артефакт AeroDock-Windows-Portable-x64.zip и запустите aerodock.exe.\r\n` +
    `   При пуше тега (git tag v2.0.0 && git push --tags) сборка также появится в Releases.\r\n\r\n` +
    `ЛОКАЛЬНАЯ СБОРКА:\r\n` +
    `Запустите build-portable.bat (требуется Flutter SDK + Visual Studio C++).\r\n`;
}

export function downloadFlutterWindowsProjectZip(items: DockItem[], settings: DockSettings) {
  const configObj = buildPortableConfigObject(items, settings);
  const configJson = JSON.stringify(configObj, null, 2);
  const icoBytes = generateAeroDockIcoBytes();

  const blob = buildZipArchive([
    {
      name: 'AeroDock-Flutter-Windows/.github/workflows/build-windows-portable.yml',
      content: buildGitHubActionsWorkflowYaml(),
    },
    {
      name: 'AeroDock-Flutter-Windows/.gitignore',
      content: buildFlutterGitignore(),
    },
    {
      name: 'AeroDock-Flutter-Windows/pubspec.yaml',
      content: buildFlutterPubspecYaml(),
    },
    {
      name: 'AeroDock-Flutter-Windows/assets/app_icon.ico',
      content: icoBytes,
    },
    {
      name: 'AeroDock-Flutter-Windows/lib/main.dart',
      content: buildFlutterMainDart(),
    },
    {
      name: 'AeroDock-Flutter-Windows/lib/models.dart',
      content: buildFlutterModelsDart(),
    },
    {
      name: 'AeroDock-Flutter-Windows/lib/windows_services.dart',
      content: buildFlutterWindowsServicesDart(),
    },
    {
      name: 'AeroDock-Flutter-Windows/lib/dialogs.dart',
      content: buildFlutterDialogsDart(),
    },
    {
      name: 'AeroDock-Flutter-Windows/aerodock-config.json',
      content: configJson,
      withUtf8Bom: true,
    },
    {
      name: 'AeroDock-Flutter-Windows/build-portable.bat',
      content: buildFlutterPortableBatScript(),
    },
    {
      name: 'AeroDock-Flutter-Windows/README-FLUTTER-RU.txt',
      content: buildFlutterReadmeRu(),
      withUtf8Bom: true,
    },
  ]);

  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'AeroDock-Flutter-Windows.zip';
  a.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1500);
}
