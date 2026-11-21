import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

// ============================================================================
// Pure Dart Windows-1251 (CP1251) + UTF-16LE + UTF-8 Decoder for RocketDock 1.3.5 INI
// ============================================================================

const List<int> _cp1251High = [
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021,
  0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
  0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
  0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
  0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
  0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
  0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
  0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
  0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
  0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
  0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
  0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
];

String decodeWindowsIniBytes(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    // UTF-16LE with BOM (common in RocketDock 1.3.5)
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    // UTF-16BE with BOM
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } catch (_) {
    // Fallback to Windows-1251 (Cyrillic ANSI)
    final units = List<int>.generate(
      bytes.length,
      (i) => bytes[i] < 0x80 ? bytes[i] : _cp1251High[bytes[i] - 0x80],
    );
    return String.fromCharCodes(units);
  }
}

// ============================================================================
// Skins & Docklets Discovery Models
// ============================================================================

class ExternalSkinInfo {
  final String id;
  final String name;
  final String imagePath;
  final double leftMargin;
  final double rightMargin;
  final double topMargin;
  final double bottomMargin;

  const ExternalSkinInfo({
    required this.id,
    required this.name,
    required this.imagePath,
    this.leftMargin = 16,
    this.rightMargin = 16,
    this.topMargin = 10,
    this.bottomMargin = 10,
  });
}

class ExternalDockletInfo {
  final String id;
  final String name;
  final String folderPath;
  final String? dllPath;
  final String? iconPath;
  final String? targetCommand;

  const ExternalDockletInfo({
    required this.id,
    required this.name,
    required this.folderPath,
    this.dllPath,
    this.iconPath,
    this.targetCommand,
  });
}

// ============================================================================
// Dev Panel ("Разработка") Auto-Intercept Rule & Settings
// ============================================================================

class DevAppRule {
  String id;
  String name; // Display name & subfolder name inside DevApps
  String archivePrefix; // Starting part of downloaded GitHub archive name
  String exeHint; // Optional main .exe filename (e.g. myapp.exe)
  String preservePatterns; // Extra settings filenames/patterns to migrate on upgrade
  bool preserveSettings;
  bool keepBackup;
  String lastArchiveName;
  String lastUpdated;
  int versionCount;

  DevAppRule({
    required this.id,
    required this.name,
    required this.archivePrefix,
    this.exeHint = '',
    this.preservePatterns = '',
    this.preserveSettings = true,
    this.keepBackup = true,
    this.lastArchiveName = '',
    this.lastUpdated = '',
    this.versionCount = 0,
  });

  DevAppRule copy() => DevAppRule(
        id: id,
        name: name,
        archivePrefix: archivePrefix,
        exeHint: exeHint,
        preservePatterns: preservePatterns,
        preserveSettings: preserveSettings,
        keepBackup: keepBackup,
        lastArchiveName: lastArchiveName,
        lastUpdated: lastUpdated,
        versionCount: versionCount,
      );
}

class DevDockSettings {
  String watchFolder; // e.g. C:\Users\...\Downloads
  String appsRootFolder; // e.g. <AeroDockDir>\DevApps
  int maxBackupsPerApp;
  String defaultPreserveExts; // .ini,.json,.cfg,.conf,.xml,.yaml,.yml,.db,.sqlite,.env
  bool moveArchiveToStorage;
  List<DevAppRule> rules;
  List<String> processedSignatures; // fileName|size|mtime

  DevDockSettings({
    required this.watchFolder,
    required this.appsRootFolder,
    this.maxBackupsPerApp = 5,
    this.defaultPreserveExts = '.ini,.json,.cfg,.conf,.xml,.yaml,.yml,.toml,.db,.sqlite,.sqlite3,.env,.dat',
    this.moveArchiveToStorage = false,
    List<DevAppRule>? rules,
    List<String>? processedSignatures,
  })  : rules = rules ?? [],
        processedSignatures = processedSignatures ?? [];

  DevDockSettings copy() => DevDockSettings(
        watchFolder: watchFolder,
        appsRootFolder: appsRootFolder,
        maxBackupsPerApp: maxBackupsPerApp,
        defaultPreserveExts: defaultPreserveExts,
        moveArchiveToStorage: moveArchiveToStorage,
        rules: rules.map((r) => r.copy()).toList(),
        processedSignatures: List<String>.from(processedSignatures),
      );

  static DevDockSettings defaults(Directory portableDir) {
    final userProfile = Platform.environment['USERPROFILE'] ?? r'C:\Users';
    return DevDockSettings(
      watchFolder: p.join(userProfile, 'Downloads'),
      appsRootFolder: p.join(portableDir.path, 'DevApps'),
      rules: [],
    );
  }
}

// ============================================================================
// Global & Per-Dock Configuration (Docks 1, 2, 3 + Dock 4 "Разработка")
// ============================================================================

class GlobalDockSettings {
  String language;
  bool launchWithWindows;
  bool portableIni;
  bool minimizeToDock;
  bool disableMinimizeAnimation;
  bool showRunningIndicators;
  bool openRunningInstance;
  bool lockItems;

  // Individual toggles for additional docks!
  bool dock2Enabled;
  bool dock3Enabled;
  bool devDockEnabled; // Dock #4 — "Разработка"

  List<String> excludedWindows;
  List<String> iconFolders;

  GlobalDockSettings({
    this.language = 'ru',
    this.launchWithWindows = false,
    this.portableIni = true,
    this.minimizeToDock = false,
    this.disableMinimizeAnimation = false,
    this.showRunningIndicators = true,
    this.openRunningInstance = true,
    this.lockItems = false,
    this.dock2Enabled = false,
    this.dock3Enabled = false,
    this.devDockEnabled = true,
    List<String>? excludedWindows,
    List<String>? iconFolders,
  })  : excludedWindows = excludedWindows ?? [],
        iconFolders = iconFolders ?? [];

  bool isDockEnabled(int dockId) => switch (dockId) {
        1 => true,
        2 => dock2Enabled,
        3 => dock3Enabled,
        4 => devDockEnabled,
        _ => false,
      };

  int get activeDockCount =>
      1 + (dock2Enabled ? 1 : 0) + (dock3Enabled ? 1 : 0) + (devDockEnabled ? 1 : 0);

  GlobalDockSettings copy() => GlobalDockSettings(
        language: language,
        launchWithWindows: launchWithWindows,
        portableIni: portableIni,
        minimizeToDock: minimizeToDock,
        disableMinimizeAnimation: disableMinimizeAnimation,
        showRunningIndicators: showRunningIndicators,
        openRunningInstance: openRunningInstance,
        lockItems: lockItems,
        dock2Enabled: dock2Enabled,
        dock3Enabled: dock3Enabled,
        devDockEnabled: devDockEnabled,
        excludedWindows: List<String>.from(excludedWindows),
        iconFolders: List<String>.from(iconFolders),
      );

  static GlobalDockSettings defaults() => GlobalDockSettings();
}

class DockPanelConfig {
  int dockId; // 1, 2, 3, or 4 ("Разработка")
  String name;

  String position; // 'bottom' | 'top' | 'left' | 'right'
  int monitorIndex; // -1 = Monitor *, 0..N
  String layer; // 'top' | 'normal' | 'bottom'
  double centerOffset;
  double edgeOffset;

  String renderQuality; // 'low' | 'medium' | 'high'
  double iconOpacity;
  bool zoomOpaque;
  double iconSize;
  String hoverEffect; // 'bubble' | 'lift' | 'none'
  double zoomScale;
  double zoomWidth;
  int zoomDurationMs;

  String theme;
  double bgOpacity;
  bool useAcrylic;
  bool showLabels;
  String labelFontFamily;
  double labelFontSize;
  bool labelBold;
  bool labelItalic;
  String labelColor;
  String labelShadowColor;
  double labelShadowOpacity;
  String labelOutlineColor;
  double labelOutlineOpacity;

  String clickEffect; // 'bounce' | 'pulse' | 'glow' | 'none'
  bool autoHide;
  int autoHideDurationMs;
  int autoHideDelayMs;
  bool popupOnMouseover;
  int popupDelayMs;

  DockPanelConfig({
    required this.dockId,
    required this.name,
    this.position = 'bottom',
    this.monitorIndex = 0,
    this.layer = 'top',
    this.centerOffset = 0,
    this.edgeOffset = 8,
    this.renderQuality = 'high',
    this.iconOpacity = 100,
    this.zoomOpaque = true,
    this.iconSize = 52,
    this.hoverEffect = 'bubble',
    this.zoomScale = 1.45,
    this.zoomWidth = 2.4,
    this.zoomDurationMs = 95,
    this.theme = 'aero3d',
    this.bgOpacity = 82,
    this.useAcrylic = false,
    this.showLabels = true,
    this.labelFontFamily = 'Segoe UI',
    this.labelFontSize = 12,
    this.labelBold = true,
    this.labelItalic = false,
    this.labelColor = '#FFFFFF',
    this.labelShadowColor = '#000000',
    this.labelShadowOpacity = 80,
    this.labelOutlineColor = '#0F172A',
    this.labelOutlineOpacity = 70,
    this.clickEffect = 'bounce',
    this.autoHide = false,
    this.autoHideDurationMs = 160,
    this.autoHideDelayMs = 250,
    this.popupOnMouseover = true,
    this.popupDelayMs = 180,
  });

  static DockPanelConfig defaultFor(int dockId) {
    switch (dockId) {
      case 2:
        return DockPanelConfig(
          dockId: 2,
          name: 'Панель 2 (Справа)',
          position: 'right',
          iconSize: 48,
          zoomScale: 1.4,
          theme: 'crystal',
        );
      case 3:
        return DockPanelConfig(
          dockId: 3,
          name: 'Панель 3 (Сверху)',
          position: 'top',
          iconSize: 44,
          zoomScale: 1.38,
          theme: 'graphite',
        );
      case 4:
        return DockPanelConfig(
          dockId: 4,
          name: 'Разработка',
          position: 'left',
          iconSize: 48,
          zoomScale: 1.42,
          theme: 'graphite',
          bgOpacity: 88,
        );
      case 1:
      default:
        return DockPanelConfig(
          dockId: 1,
          name: 'Панель 1 (Основная)',
          position: 'bottom',
          iconSize: 52,
          zoomScale: 1.45,
          theme: 'aero3d',
        );
    }
  }

  FilterQuality get filterQuality => switch (renderQuality) {
        'low' => FilterQuality.low,
        'medium' => FilterQuality.medium,
        _ => FilterQuality.high,
      };

  DockPanelConfig copy() => DockPanelConfig(
        dockId: dockId,
        name: name,
        position: position,
        monitorIndex: monitorIndex,
        layer: layer,
        centerOffset: centerOffset,
        edgeOffset: edgeOffset,
        renderQuality: renderQuality,
        iconOpacity: iconOpacity,
        zoomOpaque: zoomOpaque,
        iconSize: iconSize,
        hoverEffect: hoverEffect,
        zoomScale: zoomScale,
        zoomWidth: zoomWidth,
        zoomDurationMs: zoomDurationMs,
        theme: theme,
        bgOpacity: bgOpacity,
        useAcrylic: useAcrylic,
        showLabels: showLabels,
        labelFontFamily: labelFontFamily,
        labelFontSize: labelFontSize,
        labelBold: labelBold,
        labelItalic: labelItalic,
        labelColor: labelColor,
        labelShadowColor: labelShadowColor,
        labelShadowOpacity: labelShadowOpacity,
        labelOutlineColor: labelOutlineColor,
        labelOutlineOpacity: labelOutlineOpacity,
        clickEffect: clickEffect,
        autoHide: autoHide,
        autoHideDurationMs: autoHideDurationMs,
        autoHideDelayMs: autoHideDelayMs,
        popupOnMouseover: popupOnMouseover,
        popupDelayMs: popupDelayMs,
      );
}

class DockItemModel {
  String id;
  String type;
  String title;
  String target;
  String startIn;
  String args;
  String runMode; // 'normal' | 'minimized' | 'maximized'
  String openRunning; // 'global' | 'always' | 'never'
  bool popupMenu;
  String iconKey;
  String color;
  String? iconPath;
  String? iconPathAlt;
  String? devRuleId; // Linked DevAppRule id (for items on Dock #4 "Разработка")

  DockItemModel({
    required this.id,
    required this.type,
    required this.title,
    this.target = '',
    this.startIn = '',
    this.args = '',
    this.runMode = 'normal',
    this.openRunning = 'global',
    this.popupMenu = true,
    this.iconKey = 'rocket',
    this.color = '#0284C7',
    this.iconPath,
    this.iconPathAlt,
    this.devRuleId,
  });

  String? get executableName {
    if (target.isEmpty) return null;
    if (target.startsWith('http://') || target.startsWith('https://')) return null;
    final clean = target.replaceAll('"', '').trim();
    final base = p.basenameWithoutExtension(clean).toLowerCase();
    return base.isEmpty ? null : base;
  }

  DockItemModel copy() => DockItemModel(
        id: id,
        type: type,
        title: title,
        target: target,
        startIn: startIn,
        args: args,
        runMode: runMode,
        openRunning: openRunning,
        popupMenu: popupMenu,
        iconKey: iconKey,
        color: color,
        iconPath: iconPath,
        iconPathAlt: iconPathAlt,
        devRuleId: devRuleId,
      );
}

class RocketDockImportResult {
  final bool ok;
  final int importedItems;
  final bool importedSettings;
  final String message;

  const RocketDockImportResult({
    required this.ok,
    required this.importedItems,
    required this.importedSettings,
    required this.message,
  });
}

// ============================================================================
// Portable Settings.ini Store + RocketDock 1.3.5 Importer
// ============================================================================

class PortableIniStore {
  final Directory portableDir;
  final File iniFile;
  final Directory skinsDir;
  final Directory iconsDir;
  final Directory iconsCacheDir;
  final Directory languagesDir;
  final Directory dockletsDir;

  GlobalDockSettings global;
  DevDockSettings devSettings;
  final Map<int, DockPanelConfig> panels;
  final Map<int, List<DockItemModel>> dockItems;

  DateTime? lastLoadedModified;

  PortableIniStore({
    required this.portableDir,
    required this.iniFile,
    required this.skinsDir,
    required this.iconsDir,
    required this.iconsCacheDir,
    required this.languagesDir,
    required this.dockletsDir,
    required this.global,
    required this.devSettings,
    required this.panels,
    required this.dockItems,
    this.lastLoadedModified,
  });

  static Directory resolvePortableDir() {
    try {
      final exe = File(Platform.resolvedExecutable);
      if (exe.existsSync()) return exe.parent;
    } catch (_) {}
    return Directory.current;
  }

  static Future<PortableIniStore> load() async {
    final dir = resolvePortableDir();
    final iniFile = File(p.join(dir.path, 'Settings.ini'));
    final skinsDir = Directory(p.join(dir.path, 'Skins'));
    final iconsDir = Directory(p.join(dir.path, 'Icons'));
    final iconsCacheDir = Directory(p.join(iconsDir.path, 'cache'));
    final languagesDir = Directory(p.join(dir.path, 'Languages'));
    final dockletsDir = Directory(p.join(dir.path, 'Docklets'));

    for (final d in [skinsDir, iconsDir, iconsCacheDir, languagesDir, dockletsDir]) {
      if (!d.existsSync()) d.createSync(recursive: true);
    }

    final store = PortableIniStore(
      portableDir: dir,
      iniFile: iniFile,
      skinsDir: skinsDir,
      iconsDir: iconsDir,
      iconsCacheDir: iconsCacheDir,
      languagesDir: languagesDir,
      dockletsDir: dockletsDir,
      global: GlobalDockSettings.defaults(),
      devSettings: DevDockSettings.defaults(dir),
      panels: {
        1: DockPanelConfig.defaultFor(1),
        2: DockPanelConfig.defaultFor(2),
        3: DockPanelConfig.defaultFor(3),
        4: DockPanelConfig.defaultFor(4),
      },
      dockItems: {
        1: defaultItemsFor(1),
        2: defaultItemsFor(2),
        3: defaultItemsFor(3),
        4: defaultItemsFor(4),
      },
    );

    if (await iniFile.exists()) {
      await store.reloadFromDisk();
    } else {
      await store.save();
    }
    return store;
  }

  Future<bool> hasExternalChanges() async {
    try {
      if (!await iniFile.exists()) return false;
      final mod = await iniFile.lastModified();
      return lastLoadedModified == null || mod.isAfter(lastLoadedModified!);
    } catch (_) {
      return false;
    }
  }

  static Map<String, Map<String, String>> parseIniText(String text) {
    final sections = <String, Map<String, String>>{};
    var currentSection = '';
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        currentSection = line.substring(1, line.length - 1).trim();
        sections.putIfAbsent(currentSection, () => {});
        continue;
      }
      final idx = line.indexOf('=');
      if (idx <= 0 || currentSection.isEmpty) continue;
      final k = line.substring(0, idx).trim();
      final v = line.substring(idx + 1).trim();
      sections[currentSection]![k] = v;
    }
    return sections;
  }

  /// Detect if an INI file is an original RocketDock 1.3.5 Settings.ini file.
  static bool isRocketDock135Ini(Map<String, Map<String, String>> sections) {
    for (final sec in sections.keys) {
      final lower = sec.toLowerCase();
      if (lower == 'rocketdock' ||
          lower == r'software\rocketdock' ||
          lower == r'rocketdock\icons' ||
          lower == r'software\rocketdock\icons' ||
          lower == 'icons') {
        return true;
      }
    }
    return false;
  }

  /// Import an original RocketDock 1.3.5 Settings.ini file into [targetDockId] (1..4).
  /// Supports UTF-16LE, UTF-8, and Cyrillic ANSI (CP1251) encodings!
  Future<RocketDockImportResult> importRocketDock135Ini(
    File sourceFile, {
    required int targetDockId,
    bool importVisualSettings = true,
    bool replaceExistingItems = true,
  }) async {
    try {
      final bytes = await sourceFile.readAsBytes();
      final text = decodeWindowsIniBytes(bytes);
      final sections = parseIniText(text);

      // Find RocketDock main settings section
      Map<String, String>? rdMain;
      Map<String, String>? rdIcons;
      for (final entry in sections.entries) {
        final lower = entry.key.toLowerCase();
        if (lower == 'rocketdock' || lower == r'software\rocketdock') {
          rdMain = entry.value;
        } else if (lower == r'rocketdock\icons' ||
            lower == r'software\rocketdock\icons' ||
            lower == 'icons') {
          rdIcons = entry.value;
        }
      }

      if (rdMain == null && rdIcons == null) {
        return const RocketDockImportResult(
          ok: false,
          importedItems: 0,
          importedSettings: false,
          message: 'Файл не похож на Settings.ini из RocketDock 1.3.5 (не найдены секции [RocketDock] / [Software\\RocketDock\\Icons]).',
        );
      }

      final baseDir = sourceFile.parent.path;
      final panel = panels[targetDockId] ?? DockPanelConfig.defaultFor(targetDockId);
      var settingsImported = false;

      if (importVisualSettings && rdMain != null) {
        String? getCI(String key) {
          final kl = key.toLowerCase();
          for (final e in rdMain!.entries) {
            if (e.key.toLowerCase() == kl) return e.value;
          }
          return null;
        }

        final side = getCI('Side') ?? getCI('Position');
        if (side != null) {
          panel.position = switch (side.toLowerCase()) {
            '0' || 'top' => 'top',
            '1' || 'bottom' => 'bottom',
            '2' || 'left' => 'left',
            '3' || 'right' => 'right',
            _ => panel.position,
          };
        }

        final iconMin = double.tryParse(getCI('IconMin') ?? '');
        final iconMax = double.tryParse(getCI('IconMax') ?? '');
        if (iconMin != null && iconMin >= 24 && iconMin <= 128) {
          panel.iconSize = iconMin.clamp(32, 96);
          if (iconMax != null && iconMax >= iconMin) {
            panel.zoomScale = (iconMax / iconMin).clamp(1.0, 2.2);
          }
        }

        final zoomWidth = double.tryParse(getCI('ZoomWidth') ?? '');
        if (zoomWidth != null) panel.zoomWidth = zoomWidth.clamp(1.0, 6.0);

        final zoomDur = int.tryParse(getCI('ZoomDuration') ?? '');
        if (zoomDur != null) panel.zoomDurationMs = zoomDur.clamp(60, 400);

        final zOrder = getCI('zOrderMode');
        if (zOrder != null) {
          panel.layer = switch (zOrder) {
            '1' => 'top',
            '2' => 'bottom',
            _ => 'normal',
          };
        }

        final edgeOff = double.tryParse(getCI('EdgeOffset') ?? getCI('VOffset') ?? '');
        if (edgeOff != null) panel.edgeOffset = edgeOff.abs().clamp(0, 64);

        final mon = int.tryParse(getCI('Monitor') ?? '');
        if (mon != null) panel.monitorIndex = mon;

        final autoHide = getCI('AutoHide');
        if (autoHide != null) panel.autoHide = autoHide == '1';

        final autoHideDur = int.tryParse(getCI('AutoHideDuration') ?? '');
        if (autoHideDur != null) panel.autoHideDurationMs = autoHideDur.clamp(60, 1000);

        final autoHideDelay = int.tryParse(getCI('AutoHideDelay') ?? '');
        if (autoHideDelay != null) panel.autoHideDelayMs = autoHideDelay.clamp(0, 2000);

        final popup = getCI('PopupOnMouseover');
        if (popup != null) panel.popupOnMouseover = popup == '1';

        final lock = getCI('LockIcons');
        if (lock != null) global.lockItems = lock == '1';

        final minWin = getCI('MinimizeWindows');
        if (minWin != null) global.minimizeToDock = minWin == '1';

        final runInd = getCI('RunningIndicators');
        if (runInd != null) global.showRunningIndicators = runInd == '1';

        final openRun = getCI('OpenRunning');
        if (openRun != null) global.openRunningInstance = openRun == '1';

        final opRaw = double.tryParse(getCI('Opacity') ?? getCI('ThemeOpacity') ?? '');
        if (opRaw != null) {
          panel.bgOpacity = (opRaw > 100 ? (opRaw / 255.0) * 100.0 : opRaw).clamp(0, 100);
        }

        final showLabels = getCI('ShowLabels') ?? getCI('DisableLabels');
        if (getCI('DisableLabels') != null) {
          panel.showLabels = getCI('DisableLabels') != '1';
        } else if (showLabels != null) {
          panel.showLabels = showLabels == '1';
        }

        final fontName = getCI('FontName');
        if (fontName != null && fontName.isNotEmpty) panel.labelFontFamily = fontName;

        final fontSize = double.tryParse(getCI('FontSize') ?? '');
        if (fontSize != null && fontSize >= 8 && fontSize <= 28) {
          panel.labelFontSize = fontSize.clamp(9, 24);
        }

        // If the RocketDock skin folder exists in Skins/, link it automatically
        final themeName = getCI('Theme');
        if (themeName != null && themeName.isNotEmpty) {
          final localSkin = Directory(p.join(skinsDir.path, themeName));
          if (localSkin.existsSync()) {
            panel.theme = 'skin:$themeName';
          }
        }

        panels[targetDockId] = panel;
        settingsImported = true;
      }

      // Parse RocketDock 1.3.5 Icons (0-Title, 0-Command, 0-FileName, 0-Arguments, 0-WorkingDirectory...)
      final importedList = <DockItemModel>[];
      if (rdIcons != null) {
        final indices = <int>{};
        for (final key in rdIcons.keys) {
          final dash = key.indexOf('-');
          if (dash > 0) {
            final idx = int.tryParse(key.substring(0, dash));
            if (idx != null) indices.add(idx);
          }
        }
        final sorted = indices.toList()..sort();

        String? iconVal(int i, String field) {
          final wanted = '$i-${field.toLowerCase()}';
          for (final e in rdIcons!.entries) {
            if (e.key.toLowerCase() == wanted) return e.value;
          }
          return null;
        }

        String? resolveRdIconPath(String? raw) {
          if (raw == null || raw.trim().isEmpty) return null;
          final cleaned = raw.replaceAll('"', '').trim();
          if (File(cleaned).existsSync()) return cleaned;
          final relToSource = p.join(baseDir, cleaned);
          if (File(relToSource).existsSync()) return relToSource;
          final relToIcons = p.join(iconsDir.path, p.basename(cleaned));
          if (File(relToIcons).existsSync()) return relToIcons;
          return null;
        }

        for (final idx in sorted) {
          final isSep = iconVal(idx, 'IsSeparator') == '1';
          final title = iconVal(idx, 'Title') ?? '';
          final cmd = iconVal(idx, 'Command') ?? iconVal(idx, 'Target') ?? '';
          final args = iconVal(idx, 'Arguments') ?? '';
          final workDir = iconVal(idx, 'WorkingDirectory') ?? iconVal(idx, 'StartIn') ?? '';
          final fileName = iconVal(idx, 'FileName') ?? iconVal(idx, 'Icon') ?? iconVal(idx, 'Image');
          final fileName2 = iconVal(idx, 'FileName2');
          final showCmd = iconVal(idx, 'ShowCmd') ?? '1';
          final openRunRaw = iconVal(idx, 'OpenRunning') ?? '0';
          final useCtx = iconVal(idx, 'UseContext') != '0';

          final cmdLower = cmd.toLowerCase();
          String type;
          String resolvedTarget = cmd;
          String iconKey = 'rocket';
          String color = '#0284C7';

          if (isSep || cmdLower == '[separator]') {
            type = 'separator';
          } else if (cmdLower == '[settings]' || cmdLower.contains('dock settings')) {
            type = 'dock_settings';
            iconKey = 'settings';
            color = '#475569';
          } else if (cmdLower == '[quit]') {
            type = 'quit';
            iconKey = 'power';
            color = '#E11D48';
          } else if (cmdLower.contains('645ff040-5081-101b-9f08-00aa002f954e') ||
              cmdLower == '[recyclebin]' ||
              cmdLower.contains('recyclebin')) {
            type = 'recycle_bin';
            resolvedTarget = 'shell:RecycleBinFolder';
            iconKey = 'trash';
            color = '#64748B';
          } else if (cmdLower.contains('clock')) {
            type = 'docklet_clock';
            iconKey = 'clock';
          } else if (cmdLower.startsWith('http://') || cmdLower.startsWith('https://')) {
            type = 'blank';
            iconKey = 'globe';
          } else if (cmd.isNotEmpty && FileSystemEntity.isDirectorySync(cmd)) {
            type = 'path';
            iconKey = 'folder-blue';
            color = '#2563EB';
          } else if (cmd.isNotEmpty) {
            type = 'file';
          } else {
            type = 'blank';
          }

          final runMode = switch (showCmd) {
            '2' || '7' => 'minimized',
            '3' => 'maximized',
            _ => 'normal',
          };
          final openRunning = switch (openRunRaw) {
            '1' => 'always',
            '2' => 'never',
            _ => 'global',
          };

          importedList.add(
            DockItemModel(
              id: 'rd135_${DateTime.now().millisecondsSinceEpoch}_$idx',
              type: type,
              title: title.isEmpty ? (type == 'separator' ? 'Разделитель' : p.basenameWithoutExtension(cmd)) : title,
              target: resolvedTarget,
              startIn: workDir,
              args: args,
              runMode: runMode,
              openRunning: openRunning,
              popupMenu: useCtx,
              iconKey: iconKey,
              color: color,
              iconPath: resolveRdIconPath(fileName),
              iconPathAlt: resolveRdIconPath(fileName2),
            ),
          );
        }
      }

      if (importedList.isNotEmpty) {
        if (replaceExistingItems) {
          dockItems[targetDockId] = importedList;
        } else {
          dockItems.putIfAbsent(targetDockId, () => []).addAll(importedList);
        }
      }

      await save();
      return RocketDockImportResult(
        ok: true,
        importedItems: importedList.length,
        importedSettings: settingsImported,
        message: 'Импортировано из RocketDock 1.3.5: ${importedList.length} значков в Панель $targetDockId.',
      );
    } catch (e) {
      return RocketDockImportResult(
        ok: false,
        importedItems: 0,
        importedSettings: false,
        message: 'Ошибка импорта INI: $e',
      );
    }
  }

  Future<void> reloadFromDisk() async {
    if (!await iniFile.exists()) return;
    final bytes = await iniFile.readAsBytes();
    final text = decodeWindowsIniBytes(bytes);
    final sections = parseIniText(text);

    // If the user literally replaced Settings.ini with a RocketDock 1.3.5 Settings.ini!
    if (isRocketDock135Ini(sections) && !sections.containsKey('Dock1')) {
      await importRocketDock135Ini(iniFile, targetDockId: 1);
      return;
    }

    final g = sections['General'] ?? {};
    final legacyDockCount = _int(g['DockCount'], 1);
    global = GlobalDockSettings(
      language: g['Language'] ?? 'ru',
      launchWithWindows: _bool(g['LaunchWithWindows'], false),
      portableIni: _bool(g['PortableIni'], true),
      minimizeToDock: _bool(g['MinimizeToDock'], false),
      disableMinimizeAnimation: _bool(g['DisableMinimizeAnimation'], false),
      showRunningIndicators: _bool(g['ShowRunningIndicators'], true),
      openRunningInstance: _bool(g['OpenRunningInstance'], true),
      lockItems: _bool(g['LockItems'], false),
      dock2Enabled: g.containsKey('Dock2Enabled')
          ? _bool(g['Dock2Enabled'], false)
          : legacyDockCount >= 2,
      dock3Enabled: g.containsKey('Dock3Enabled')
          ? _bool(g['Dock3Enabled'], false)
          : legacyDockCount >= 3,
      devDockEnabled: _bool(g['DevDockEnabled'], true),
      excludedWindows: _list(g['ExcludedWindows']),
      iconFolders: _list(g['IconFolders']),
    );

    // Load DevDock settings & rules
    final devSec = sections['DevDock'] ?? {};
    final devDef = DevDockSettings.defaults(portableDir);
    final rulesSec = sections['DevRules'] ?? {};
    final ruleCount = _int(rulesSec['Count'], 0);
    final loadedRules = <DevAppRule>[];
    for (var i = 0; i < ruleCount; i++) {
      final pre = 'Rule$i';
      final prefix = rulesSec['$pre.Prefix'] ?? '';
      if (prefix.isEmpty) continue;
      loadedRules.add(
        DevAppRule(
          id: rulesSec['$pre.Id'] ?? 'rule_$i',
          name: rulesSec['$pre.Name'] ?? prefix,
          archivePrefix: prefix,
          exeHint: rulesSec['$pre.ExeHint'] ?? '',
          preservePatterns: rulesSec['$pre.PreservePatterns'] ?? '',
          preserveSettings: _bool(rulesSec['$pre.PreserveSettings'], true),
          keepBackup: _bool(rulesSec['$pre.KeepBackup'], true),
          lastArchiveName: rulesSec['$pre.LastArchive'] ?? '',
          lastUpdated: rulesSec['$pre.LastUpdated'] ?? '',
          versionCount: _int(rulesSec['$pre.VersionCount'], 0),
        ),
      );
    }

    devSettings = DevDockSettings(
      watchFolder: (devSec['WatchFolder'] ?? '').isNotEmpty
          ? devSec['WatchFolder']!
          : devDef.watchFolder,
      appsRootFolder: (devSec['AppsRootFolder'] ?? '').isNotEmpty
          ? devSec['AppsRootFolder']!
          : devDef.appsRootFolder,
      maxBackupsPerApp: _int(devSec['MaxBackupsPerApp'], 5).clamp(1, 30),
      defaultPreserveExts: (devSec['DefaultPreserveExts'] ?? '').isNotEmpty
          ? devSec['DefaultPreserveExts']!
          : devDef.defaultPreserveExts,
      moveArchiveToStorage: _bool(devSec['MoveArchiveToStorage'], false),
      rules: loadedRules,
      processedSignatures: _list(devSec['ProcessedSignatures']),
    );

    for (var id = 1; id <= 4; id++) {
      final s = sections['Dock$id'];
      final def = DockPanelConfig.defaultFor(id);
      if (s != null) {
        panels[id] = DockPanelConfig(
          dockId: id,
          name: s['Name'] ?? def.name,
          position: s['Position'] ?? def.position,
          monitorIndex: _int(s['Monitor'], def.monitorIndex),
          layer: s['Layer'] ?? def.layer,
          centerOffset: _double(s['CenterOffset'], def.centerOffset).clamp(-40, 40),
          edgeOffset: _double(s['EdgeOffset'], def.edgeOffset).clamp(0, 64),
          renderQuality: s['RenderQuality'] ?? def.renderQuality,
          iconOpacity: _double(s['IconOpacity'], def.iconOpacity).clamp(20, 100),
          zoomOpaque: _bool(s['ZoomOpaque'], def.zoomOpaque),
          iconSize: _double(s['IconSize'], def.iconSize).clamp(32, 96),
          hoverEffect: s['HoverEffect'] ?? def.hoverEffect,
          zoomScale: _double(s['ZoomScale'], def.zoomScale).clamp(1.0, 2.2),
          zoomWidth: _double(s['ZoomWidth'], def.zoomWidth).clamp(1.0, 6.0),
          zoomDurationMs: _int(s['ZoomDurationMs'], def.zoomDurationMs).clamp(60, 400),
          theme: s['Theme'] ?? def.theme,
          bgOpacity: _double(s['BgOpacity'], def.bgOpacity).clamp(0, 100),
          useAcrylic: _bool(s['UseAcrylic'], def.useAcrylic),
          showLabels: _bool(s['ShowLabels'], def.showLabels),
          labelFontFamily: s['LabelFontFamily'] ?? def.labelFontFamily,
          labelFontSize: _double(s['LabelFontSize'], def.labelFontSize).clamp(9, 24),
          labelBold: _bool(s['LabelBold'], def.labelBold),
          labelItalic: _bool(s['LabelItalic'], def.labelItalic),
          labelColor: s['LabelColor'] ?? def.labelColor,
          labelShadowColor: s['LabelShadowColor'] ?? def.labelShadowColor,
          labelShadowOpacity: _double(s['LabelShadowOpacity'], def.labelShadowOpacity).clamp(0, 100),
          labelOutlineColor: s['LabelOutlineColor'] ?? def.labelOutlineColor,
          labelOutlineOpacity: _double(s['LabelOutlineOpacity'], def.labelOutlineOpacity).clamp(0, 100),
          clickEffect: s['ClickEffect'] ?? def.clickEffect,
          autoHide: _bool(s['AutoHide'], def.autoHide),
          autoHideDurationMs: _int(s['AutoHideDurationMs'], def.autoHideDurationMs).clamp(60, 1000),
          autoHideDelayMs: _int(s['AutoHideDelayMs'], def.autoHideDelayMs).clamp(0, 2000),
          popupOnMouseover: _bool(s['PopupOnMouseover'], def.popupOnMouseover),
          popupDelayMs: _int(s['PopupDelayMs'], def.popupDelayMs).clamp(0, 2000),
        );
      }

      final itemsSec = sections['Dock$id-Items'];
      if (itemsSec != null) {
        final count = _int(itemsSec['Count'], 0);
        final list = <DockItemModel>[];
        for (var i = 0; i < count; i++) {
          final prefix = 'Item$i';
          final type = itemsSec['$prefix.Type'];
          if (type == null || type.isEmpty) continue;
          list.add(
            DockItemModel(
              id: itemsSec['$prefix.Id'] ?? 'd${id}_$i',
              type: type,
              title: itemsSec['$prefix.Title'] ?? '',
              target: itemsSec['$prefix.Target'] ?? '',
              startIn: itemsSec['$prefix.StartIn'] ?? '',
              args: itemsSec['$prefix.Args'] ?? '',
              runMode: itemsSec['$prefix.RunMode'] ?? 'normal',
              openRunning: itemsSec['$prefix.OpenRunning'] ?? 'global',
              popupMenu: _bool(itemsSec['$prefix.PopupMenu'], true),
              iconKey: itemsSec['$prefix.IconKey'] ?? 'rocket',
              color: itemsSec['$prefix.Color'] ?? '#0284C7',
              iconPath: _emptyToNull(itemsSec['$prefix.IconPath']),
              iconPathAlt: _emptyToNull(itemsSec['$prefix.IconPathAlt']),
              devRuleId: _emptyToNull(itemsSec['$prefix.DevRuleId']),
            ),
          );
        }
        dockItems[id] = list;
      }
    }

    lastLoadedModified = await iniFile.lastModified();
  }

  Future<void> save() async {
    final sb = StringBuffer()
      ..writeln('; AeroDock Portable v3.5 — Settings.ini (UTF-8, RocketDock 1.3.5 Import + Dev Panel)')
      ..writeln('[General]')
      ..writeln('Language=${global.language}')
      ..writeln('LaunchWithWindows=${global.launchWithWindows ? 1 : 0}')
      ..writeln('PortableIni=${global.portableIni ? 1 : 0}')
      ..writeln('MinimizeToDock=${global.minimizeToDock ? 1 : 0}')
      ..writeln('DisableMinimizeAnimation=${global.disableMinimizeAnimation ? 1 : 0}')
      ..writeln('ShowRunningIndicators=${global.showRunningIndicators ? 1 : 0}')
      ..writeln('OpenRunningInstance=${global.openRunningInstance ? 1 : 0}')
      ..writeln('LockItems=${global.lockItems ? 1 : 0}')
      ..writeln('Dock2Enabled=${global.dock2Enabled ? 1 : 0}')
      ..writeln('Dock3Enabled=${global.dock3Enabled ? 1 : 0}')
      ..writeln('DevDockEnabled=${global.devDockEnabled ? 1 : 0}')
      ..writeln('ExcludedWindows=${global.excludedWindows.join('|')}')
      ..writeln('IconFolders=${global.iconFolders.join('|')}')
      ..writeln('')
      ..writeln('[DevDock]')
      ..writeln('WatchFolder=${_sanitizeIniVal(devSettings.watchFolder)}')
      ..writeln('AppsRootFolder=${_sanitizeIniVal(devSettings.appsRootFolder)}')
      ..writeln('MaxBackupsPerApp=${devSettings.maxBackupsPerApp}')
      ..writeln('DefaultPreserveExts=${_sanitizeIniVal(devSettings.defaultPreserveExts)}')
      ..writeln('MoveArchiveToStorage=${devSettings.moveArchiveToStorage ? 1 : 0}')
      ..writeln('ProcessedSignatures=${devSettings.processedSignatures.take(120).join('|')}')
      ..writeln('')
      ..writeln('[DevRules]')
      ..writeln('Count=${devSettings.rules.length}');

    for (var i = 0; i < devSettings.rules.length; i++) {
      final r = devSettings.rules[i];
      final pre = 'Rule$i';
      sb
        ..writeln('$pre.Id=${r.id}')
        ..writeln('$pre.Name=${_sanitizeIniVal(r.name)}')
        ..writeln('$pre.Prefix=${_sanitizeIniVal(r.archivePrefix)}')
        ..writeln('$pre.ExeHint=${_sanitizeIniVal(r.exeHint)}')
        ..writeln('$pre.PreservePatterns=${_sanitizeIniVal(r.preservePatterns)}')
        ..writeln('$pre.PreserveSettings=${r.preserveSettings ? 1 : 0}')
        ..writeln('$pre.KeepBackup=${r.keepBackup ? 1 : 0}')
        ..writeln('$pre.LastArchive=${_sanitizeIniVal(r.lastArchiveName)}')
        ..writeln('$pre.LastUpdated=${_sanitizeIniVal(r.lastUpdated)}')
        ..writeln('$pre.VersionCount=${r.versionCount}');
    }
    sb.writeln('');

    for (var id = 1; id <= 4; id++) {
      final cfg = panels[id] ?? DockPanelConfig.defaultFor(id);
      sb
        ..writeln('[Dock$id]')
        ..writeln('Name=${cfg.name}')
        ..writeln('Position=${cfg.position}')
        ..writeln('Monitor=${cfg.monitorIndex}')
        ..writeln('Layer=${cfg.layer}')
        ..writeln('CenterOffset=${cfg.centerOffset.toStringAsFixed(1)}')
        ..writeln('EdgeOffset=${cfg.edgeOffset.toStringAsFixed(0)}')
        ..writeln('RenderQuality=${cfg.renderQuality}')
        ..writeln('IconOpacity=${cfg.iconOpacity.toStringAsFixed(0)}')
        ..writeln('ZoomOpaque=${cfg.zoomOpaque ? 1 : 0}')
        ..writeln('IconSize=${cfg.iconSize.toStringAsFixed(0)}')
        ..writeln('HoverEffect=${cfg.hoverEffect}')
        ..writeln('ZoomScale=${cfg.zoomScale.toStringAsFixed(2)}')
        ..writeln('ZoomWidth=${cfg.zoomWidth.toStringAsFixed(1)}')
        ..writeln('ZoomDurationMs=${cfg.zoomDurationMs}')
        ..writeln('Theme=${cfg.theme}')
        ..writeln('BgOpacity=${cfg.bgOpacity.toStringAsFixed(0)}')
        ..writeln('UseAcrylic=${cfg.useAcrylic ? 1 : 0}')
        ..writeln('ShowLabels=${cfg.showLabels ? 1 : 0}')
        ..writeln('LabelFontFamily=${cfg.labelFontFamily}')
        ..writeln('LabelFontSize=${cfg.labelFontSize.toStringAsFixed(0)}')
        ..writeln('LabelBold=${cfg.labelBold ? 1 : 0}')
        ..writeln('LabelItalic=${cfg.labelItalic ? 1 : 0}')
        ..writeln('LabelColor=${cfg.labelColor}')
        ..writeln('LabelShadowColor=${cfg.labelShadowColor}')
        ..writeln('LabelShadowOpacity=${cfg.labelShadowOpacity.toStringAsFixed(0)}')
        ..writeln('LabelOutlineColor=${cfg.labelOutlineColor}')
        ..writeln('LabelOutlineOpacity=${cfg.labelOutlineOpacity.toStringAsFixed(0)}')
        ..writeln('ClickEffect=${cfg.clickEffect}')
        ..writeln('AutoHide=${cfg.autoHide ? 1 : 0}')
        ..writeln('AutoHideDurationMs=${cfg.autoHideDurationMs}')
        ..writeln('AutoHideDelayMs=${cfg.autoHideDelayMs}')
        ..writeln('PopupOnMouseover=${cfg.popupOnMouseover ? 1 : 0}')
        ..writeln('PopupDelayMs=${cfg.popupDelayMs}')
        ..writeln('');

      final items = dockItems[id] ?? const [];
      sb
        ..writeln('[Dock$id-Items]')
        ..writeln('Count=${items.length}');
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        final pre = 'Item$i';
        sb
          ..writeln('$pre.Id=${it.id}')
          ..writeln('$pre.Type=${it.type}')
          ..writeln('$pre.Title=${_sanitizeIniVal(it.title)}')
          ..writeln('$pre.Target=${_sanitizeIniVal(it.target)}')
          ..writeln('$pre.StartIn=${_sanitizeIniVal(it.startIn)}')
          ..writeln('$pre.Args=${_sanitizeIniVal(it.args)}')
          ..writeln('$pre.RunMode=${it.runMode}')
          ..writeln('$pre.OpenRunning=${it.openRunning}')
          ..writeln('$pre.PopupMenu=${it.popupMenu ? 1 : 0}')
          ..writeln('$pre.IconKey=${it.iconKey}')
          ..writeln('$pre.Color=${it.color}')
          ..writeln('$pre.IconPath=${_sanitizeIniVal(it.iconPath ?? '')}')
          ..writeln('$pre.IconPathAlt=${_sanitizeIniVal(it.iconPathAlt ?? '')}')
          ..writeln('$pre.DevRuleId=${_sanitizeIniVal(it.devRuleId ?? '')}');
      }
      sb.writeln('');
    }

    await iniFile.writeAsString(sb.toString(), flush: true);
    lastLoadedModified = await iniFile.lastModified();
  }

  Future<void> resetSettingsToDefaultsOnly() async {
    final keepD2 = global.dock2Enabled;
    final keepD3 = global.dock3Enabled;
    final keepDev = global.devDockEnabled;
    global = GlobalDockSettings.defaults()
      ..dock2Enabled = keepD2
      ..dock3Enabled = keepD3
      ..devDockEnabled = keepDev;
    for (var id = 1; id <= 4; id++) {
      panels[id] = DockPanelConfig.defaultFor(id);
    }
    await save();
  }

  Future<void> fullReset() async {
    if (await iniFile.exists()) {
      await iniFile.delete();
    }
    global = GlobalDockSettings.defaults();
    devSettings = DevDockSettings.defaults(portableDir);
    for (var id = 1; id <= 4; id++) {
      panels[id] = DockPanelConfig.defaultFor(id);
      dockItems[id] = defaultItemsFor(id);
    }
    await save();
  }

  List<ExternalSkinInfo> scanExternalSkins() {
    final result = <ExternalSkinInfo>[];
    try {
      if (!skinsDir.existsSync()) return result;
      for (final entity in skinsDir.listSync()) {
        if (entity is! Directory) continue;
        final folderName = p.basename(entity.path);
        File? ini;
        for (final candidate in ['background.ini', 'theme.ini', 'skin.ini']) {
          final f = File(p.join(entity.path, candidate));
          if (f.existsSync()) {
            ini = f;
            break;
          }
        }
        String? imgName;
        var name = folderName;
        double left = 16, right = 16, top = 10, bottom = 10;

        if (ini != null) {
          for (final raw in const LineSplitter().convert(decodeWindowsIniBytes(ini.readAsBytesSync()))) {
            final line = raw.trim();
            final idx = line.indexOf('=');
            if (idx <= 0) continue;
            final k = line.substring(0, idx).trim().toLowerCase();
            final v = line.substring(idx + 1).trim();
            if (k == 'name' && v.isNotEmpty) name = v;
            if (k == 'image' || k == 'background' || k == 'file') imgName = v;
            if (k == 'leftmargin' || k == 'outside-left') left = double.tryParse(v) ?? left;
            if (k == 'rightmargin' || k == 'outside-right') right = double.tryParse(v) ?? right;
            if (k == 'topmargin' || k == 'outside-top') top = double.tryParse(v) ?? top;
            if (k == 'bottommargin' || k == 'outside-bottom') bottom = double.tryParse(v) ?? bottom;
          }
        }

        File? imgFile;
        if (imgName != null && imgName.isNotEmpty) {
          final f = File(p.join(entity.path, imgName));
          if (f.existsSync()) imgFile = f;
        }
        if (imgFile == null) {
          for (final child in entity.listSync()) {
            if (child is File && p.extension(child.path).toLowerCase() == '.png') {
              imgFile = child;
              break;
            }
          }
        }

        if (imgFile != null) {
          result.add(
            ExternalSkinInfo(
              id: 'skin:$folderName',
              name: '$name (Skin)',
              imagePath: imgFile.path,
              leftMargin: left,
              rightMargin: right,
              topMargin: top,
              bottomMargin: bottom,
            ),
          );
        }
      }
    } catch (_) {}
    return result;
  }

  List<ExternalDockletInfo> scanExternalDocklets() {
    final result = <ExternalDockletInfo>[];
    try {
      if (!dockletsDir.existsSync()) return result;
      for (final entity in dockletsDir.listSync()) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        String? dll;
        String? icon;
        String? cmd;
        for (final child in entity.listSync()) {
          if (child is! File) continue;
          final ext = p.extension(child.path).toLowerCase();
          if (ext == '.dll') dll ??= child.path;
          if (ext == '.png' || ext == '.ico') icon ??= child.path;
          if (ext == '.exe' || ext == '.bat') cmd ??= child.path;
        }
        result.add(
          ExternalDockletInfo(
            id: 'ext_$name',
            name: name,
            folderPath: entity.path,
            dllPath: dll,
            iconPath: icon,
            targetCommand: cmd ?? entity.path,
          ),
        );
      }
    } catch (_) {}
    return result;
  }

  List<File> listIconsInFolder(String folderPath) {
    final result = <File>[];
    try {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) return result;
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final ext = p.extension(e.path).toLowerCase();
        if (ext == '.png' || ext == '.ico' || ext == '.jpg' || ext == '.webp') {
          result.add(e);
        }
      }
      result.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    } catch (_) {}
    return result;
  }

  static List<DockItemModel> defaultItemsFor(int dockId) {
    final userProfile = Platform.environment['USERPROFILE'] ?? r'C:\Users';
    if (dockId == 2) {
      return [
        DockItemModel(id: 'd2_clock', type: 'docklet_clock', title: 'Часы', iconKey: 'clock', color: '#0F172A'),
        DockItemModel(id: 'd2_sysstats', type: 'docklet_sysstats', title: 'CPU / RAM', iconKey: 'terminal', color: '#0284C7'),
        DockItemModel(id: 'd2_battery', type: 'docklet_battery', title: 'Батарея', iconKey: 'star', color: '#059669'),
        DockItemModel(id: 'd2_calendar', type: 'docklet_calendar', title: 'Календарь', iconKey: 'book', color: '#E11D48'),
        DockItemModel(id: 'd2_sep', type: 'separator', title: 'Разделитель'),
        DockItemModel(id: 'd2_downloads', type: 'docklet_stack', title: 'Загрузки', target: p.join(userProfile, 'Downloads'), iconKey: 'folder-emerald', color: '#059669'),
      ];
    }
    if (dockId == 3) {
      return [
        DockItemModel(id: 'd3_gh', type: 'blank', title: 'GitHub', target: 'https://github.com', iconKey: 'code', color: '#1E293B'),
        DockItemModel(id: 'd3_yt', type: 'blank', title: 'YouTube', target: 'https://www.youtube.com', iconKey: 'video', color: '#DC2626'),
        DockItemModel(id: 'd3_search', type: 'blank', title: 'Поиск', target: 'https://www.google.com', iconKey: 'globe', color: '#0284C7'),
      ];
    }
    if (dockId == 4) {
      // Панель «Разработка» — управление правилами перехвата + папка DevApps
      return [
        DockItemModel(
          id: 'dev_settings_btn',
          type: 'dev_settings',
          title: 'Разработка: правила перехвата GitHub',
          iconKey: 'code',
          color: '#7C3AED',
        ),
        DockItemModel(
          id: 'dev_folder_btn',
          type: 'path',
          title: 'Папка DevApps',
          target: p.join(resolvePortableDir().path, 'DevApps'),
          iconKey: 'folder-emerald',
          color: '#059669',
        ),
        DockItemModel(id: 'dev_sep', type: 'separator', title: 'Разделитель'),
      ];
    }
    return [
      DockItemModel(id: 'd1_explorer', type: 'file', title: 'Проводник', target: 'explorer.exe', iconKey: 'folder-blue', color: '#2563EB'),
      DockItemModel(id: 'd1_notepad', type: 'file', title: 'Блокнот', target: 'notepad.exe', iconKey: 'notes', color: '#D97706'),
      DockItemModel(id: 'd1_calc', type: 'file', title: 'Калькулятор', target: 'calc.exe', iconKey: 'calculator', color: '#334155'),
      DockItemModel(id: 'd1_cmd', type: 'file', title: 'Терминал', target: 'cmd.exe', iconKey: 'terminal', color: '#0F172A'),
      DockItemModel(id: 'd1_sep1', type: 'separator', title: 'Разделитель'),
      DockItemModel(id: 'd1_clock', type: 'docklet_clock', title: 'Часы', iconKey: 'clock', color: '#0F172A'),
      DockItemModel(id: 'd1_sep2', type: 'separator', title: 'Разделитель'),
      DockItemModel(id: 'd1_settings', type: 'dock_settings', title: 'Настройки панели', iconKey: 'settings', color: '#475569'),
      DockItemModel(id: 'd1_recycle', type: 'recycle_bin', title: 'Корзина', target: 'shell:RecycleBinFolder', iconKey: 'trash', color: '#64748B'),
      DockItemModel(id: 'd1_quit', type: 'quit', title: 'Выход', iconKey: 'power', color: '#E11D48'),
    ];
  }

  static bool _bool(String? v, bool fallback) {
    if (v == null) return fallback;
    return v == '1' || v.toLowerCase() == 'true';
  }

  static int _int(String? v, int fallback) => int.tryParse(v ?? '') ?? fallback;

  static double _double(String? v, double fallback) => double.tryParse(v ?? '') ?? fallback;

  static List<String> _list(String? v) {
    if (v == null || v.trim().isEmpty) return [];
    return v.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static String? _emptyToNull(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  static String _sanitizeIniVal(String v) => v.replaceAll('\r', '').replaceAll('\n', ' ');
}

Color parseHexColor(String hex, [Color fallback = const Color(0xFF0284C7)]) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length == 6) {
    final val = int.tryParse('FF$cleaned', radix: 16);
    if (val != null) return Color(val);
  }
  if (cleaned.length == 8) {
    final val = int.tryParse(cleaned, radix: 16);
    if (val != null) return Color(val);
  }
  return fallback;
}
