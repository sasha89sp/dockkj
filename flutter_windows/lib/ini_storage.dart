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
  if (bytes.isEmpty) return '';
  String clean(String s) => s.replaceAll('\uFEFF', '').replaceAll('\x00', '');

  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    // UTF-16LE with BOM (common in RocketDock 1.3.5)
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return clean(String.fromCharCodes(units));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    // UTF-16BE with BOM
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return clean(String.fromCharCodes(units));
  }
  // Detect BOM-less UTF-16LE (common when edited/exported on Windows: ASCII chars have 0x00 in odd positions)
  if (bytes.length >= 8) {
    var oddZeros = 0;
    final sample = bytes.length < 80 ? bytes.length : 80;
    for (var i = 1; i < sample; i += 2) {
      if (bytes[i] == 0) oddZeros++;
    }
    if (oddZeros >= (sample ~/ 4)) {
      final units = <int>[];
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        units.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return clean(String.fromCharCodes(units));
    }
  }
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return clean(utf8.decode(bytes.sublist(3), allowMalformed: true));
  }
  try {
    return clean(utf8.decode(bytes, allowMalformed: false));
  } catch (_) {
    // Fallback to Windows-1251 (Cyrillic ANSI)
    final units = List<int>.generate(
      bytes.length,
      (i) => bytes[i] < 0x80 ? bytes[i] : _cp1251High[bytes[i] - 0x80],
    );
    return clean(String.fromCharCodes(units));
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
// Auto-Backup & Seamless Upgrade Profile Sync Settings
// ============================================================================

class BackupSettings {
  bool autoBackupEnabled;
  int autoBackupIntervalHours; // 0 = every launch, 24 = daily, 168 = weekly
  int maxAutoBackups;
  String backupFolder;
  bool autoSyncProfile; // Automatically preserve settings when copying new version to a new folder
  String lastBackupIso;

  BackupSettings({
    this.autoBackupEnabled = true,
    this.autoBackupIntervalHours = 24,
    this.maxAutoBackups = 10,
    required this.backupFolder,
    this.autoSyncProfile = true,
    this.lastBackupIso = '',
  });

  BackupSettings copy() => BackupSettings(
        autoBackupEnabled: autoBackupEnabled,
        autoBackupIntervalHours: autoBackupIntervalHours,
        maxAutoBackups: maxAutoBackups,
        backupFolder: backupFolder,
        autoSyncProfile: autoSyncProfile,
        lastBackupIso: lastBackupIso,
      );

  static BackupSettings defaults() {
    final userProfile = Platform.environment['USERPROFILE'] ?? r'C:\Users';
    return BackupSettings(
      backupFolder: p.join(userProfile, 'Documents', 'AeroDock-Backups'),
    );
  }
}

class BackupEntry {
  final String name;
  final String path;
  final DateTime createdAt;
  final int sizeBytes;

  const BackupEntry({
    required this.name,
    required this.path,
    required this.createdAt,
    required this.sizeBytes,
  });
}

// ============================================================================
// Windows-Safe Filesystem Helpers (Prevents OS Error 123 on URLs / shell: / ::)
// ============================================================================

/// Returns true if [raw] is a URL, Windows shell URI, CLSID, or contains characters
/// illegal in a Windows filesystem path (which cause `File.existsSync()` to throw errno 123!).
bool isNonFileScheme(String? raw) {
  if (raw == null) return true;
  final s = raw.trim();
  if (s.isEmpty) return true;
  final lower = s.toLowerCase();
  if (lower.contains('://') ||
      lower.startsWith('shell:') ||
      lower.startsWith('mailto:') ||
      lower.startsWith('ms-') ||
      lower.startsWith('::')) {
    return true;
  }
  final check = s.startsWith(r'\\?\') ? s.substring(4) : s;
  final firstColon = check.indexOf(':');
  if (firstColon >= 0) {
    // Only a Windows drive letter (`C:\...` or `C:/...`) may contain `:` at index 1
    final isAsciiLetter = check.isNotEmpty &&
        ((check.codeUnitAt(0) >= 65 && check.codeUnitAt(0) <= 90) ||
            (check.codeUnitAt(0) >= 97 && check.codeUnitAt(0) <= 122));
    if (firstColon != 1 || !isAsciiLetter) return true;
    if (check.indexOf(':', 2) >= 0) return true;
  }
  for (var i = 0; i < check.length; i++) {
    final c = check.codeUnitAt(i);
    // Reject control chars and Windows-illegal filename chars: < > " | ? *
    if (c < 32 || c == 60 || c == 62 || c == 34 || c == 124 || c == 63 || c == 42) {
      return true;
    }
  }
  return false;
}

/// Windows-safe `File(path).existsSync()` that NEVER throws `FileSystemException (errno 123)`.
bool safeFileExists(String? path) {
  if (isNonFileScheme(path)) return false;
  try {
    return File(path!.trim()).existsSync();
  } catch (_) {
    return false;
  }
}

/// Windows-safe `Directory(path).existsSync()` that NEVER throws `FileSystemException (errno 123)`.
bool safeDirExists(String? path) {
  if (isNonFileScheme(path)) return false;
  try {
    return Directory(path!.trim()).existsSync();
  } catch (_) {
    return false;
  }
}

/// Windows-safe `FileSystemEntity.isDirectorySync(path)` that NEVER throws on URLs/shell: URIs.
bool safeIsDirectory(String? path) {
  if (isNonFileScheme(path)) return false;
  try {
    return FileSystemEntity.isDirectorySync(path!.trim());
  } catch (_) {
    return false;
  }
}

// ============================================================================
// Portable Settings.ini Store + RocketDock 1.3.5 Importer + Auto-Backup
// ============================================================================

class PortableIniStore {
  static const String _appDirToken = r'$APP_DIR$';

  final Directory portableDir;
  final File iniFile;
  final Directory skinsDir;
  final Directory iconsDir;
  final Directory iconsCacheDir;
  final Directory languagesDir;
  final Directory dockletsDir;

  GlobalDockSettings global;
  DevDockSettings devSettings;
  BackupSettings backupSettings;
  final Map<int, DockPanelConfig> panels;
  final Map<int, List<DockItemModel>> dockItems;

  DateTime? lastLoadedModified;
  String? _lastContentSignature;
  int _revision = 0;
  bool migratedFromPreviousVersion = false;

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
    required this.backupSettings,
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

  static Directory resolveProfileSyncDir() {
    final localAppData = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        r'C:\Users';
    return Directory(p.join(localAppData, 'AeroDockPortable', 'ProfileSync'));
  }

  /// Convert any path inside portableDir to `$APP_DIR$\...` so copying/moving folder preserves everything!
  String toPortablePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return '';
    final base = portableDir.path;
    if (trimmed.toLowerCase() == base.toLowerCase()) return _appDirToken;
    final prefix = base.endsWith(r'\') || base.endsWith('/') ? base : '$base\\';
    if (trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      final rel = trimmed.substring(prefix.length);
      return '$_appDirToken\\$rel';
    }
    return trimmed;
  }

  /// Expand `$APP_DIR$\...` (and auto-repair stale AeroDock portable paths copied from an older folder).
  String fromPortablePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith(_appDirToken)) {
      final rest = trimmed.substring(_appDirToken.length).replaceFirst(RegExp(r'^[\\/]+'), '');
      return rest.isEmpty ? portableDir.path : p.join(portableDir.path, rest);
    }
    // Never touch the filesystem for URLs (https://...), shell: URIs, or CLSIDs —
    // on Windows, File('https://...').existsSync() throws FileSystemException (errno = 123)!
    if (isNonFileScheme(trimmed)) return trimmed;

    // If user copied Settings.ini from an old AeroDock folder, auto-remap DevApps / Icons / Skins if missing at old path
    if (!safeFileExists(trimmed) && !safeDirExists(trimmed)) {
      final lower = trimmed.toLowerCase();
      for (final sub in [r'\icons\', r'\skins\', r'\docklets\', r'\languages\', r'\devapps']) {
        final idx = lower.indexOf(sub);
        if (idx >= 0) {
          final rel = trimmed.substring(idx + 1);
          final candidate = p.join(portableDir.path, rel);
          if (sub == r'\devapps' || safeFileExists(candidate) || safeDirExists(candidate)) {
            return candidate;
          }
        }
      }
    }
    return trimmed;
  }

  static Future<PortableIniStore> load({bool allowAutoMigrate = true}) async {
    final dir = resolvePortableDir();
    final iniFile = File(p.join(dir.path, 'Settings.ini'));
    final skinsDir = Directory(p.join(dir.path, 'Skins'));
    final iconsDir = Directory(p.join(dir.path, 'Icons'));
    final iconsCacheDir = Directory(p.join(iconsDir.path, 'cache'));
    final languagesDir = Directory(p.join(dir.path, 'Languages'));
    final dockletsDir = Directory(p.join(dir.path, 'Docklets'));

    for (final d in [skinsDir, iconsDir, iconsCacheDir, languagesDir, dockletsDir]) {
      try {
        if (!d.existsSync()) d.createSync(recursive: true);
      } catch (_) {}
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
      backupSettings: BackupSettings.defaults(),
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

    try {
      if (await iniFile.exists()) {
        await store.reloadFromDisk();
      } else if (allowAutoMigrate && await store._tryRestoreFromProfileSync()) {
        store.migratedFromPreviousVersion = true;
        await store.reloadFromDisk();
        await store.save();
      } else {
        await store.save();
      }
    } catch (_) {
      // Never block window creation if Settings.ini is temporarily locked or folder is read-only
    }
    return store;
  }

  Future<bool> _tryRestoreFromProfileSync() async {
    try {
      final syncDir = resolveProfileSyncDir();
      final syncIni = File(p.join(syncDir.path, 'Settings.ini'));
      if (!syncIni.existsSync()) return false;
      await syncIni.copy(iniFile.path);
      final syncIcons = Directory(p.join(syncDir.path, 'Icons'));
      if (syncIcons.existsSync()) {
        await _copyDirFiles(syncIcons, iconsDir, skipSubdir: 'cache');
      }
      final syncLangs = Directory(p.join(syncDir.path, 'Languages'));
      if (syncLangs.existsSync()) {
        await _copyDirFiles(syncLangs, languagesDir);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _syncToUserProfile() async {
    if (!backupSettings.autoSyncProfile) return;
    try {
      final syncDir = resolveProfileSyncDir();
      if (!syncDir.existsSync()) syncDir.createSync(recursive: true);
      if (iniFile.existsSync()) {
        await iniFile.copy(p.join(syncDir.path, 'Settings.ini'));
      }
      if (iconsDir.existsSync()) {
        await _copyDirFiles(iconsDir, Directory(p.join(syncDir.path, 'Icons')), skipSubdir: 'cache');
      }
      if (languagesDir.existsSync()) {
        await _copyDirFiles(languagesDir, Directory(p.join(syncDir.path, 'Languages')));
      }
    } catch (_) {}
  }

  /// Create a full timestamped backup of Settings.ini + custom Icons + Languages.
  Future<BackupEntry?> createBackup({String tag = 'manual'}) async {
    try {
      final root = Directory(backupSettings.backupFolder);
      if (!root.existsSync()) root.createSync(recursive: true);
      final now = DateTime.now();
      final stamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final folderName = 'Backup_${stamp}_$tag';
      final dst = Directory(p.join(root.path, folderName));
      await dst.create(recursive: true);

      if (iniFile.existsSync()) {
        await iniFile.copy(p.join(dst.path, 'Settings.ini'));
      }
      if (iconsDir.existsSync()) {
        await _copyDirFiles(iconsDir, Directory(p.join(dst.path, 'Icons')), skipSubdir: 'cache');
      }
      if (languagesDir.existsSync()) {
        await _copyDirFiles(languagesDir, Directory(p.join(dst.path, 'Languages')));
      }

      // Reload latest settings & items from disk before recording LastBackupIso
      // so delayed auto-backup can NEVER overwrite panel positions with stale memory!
      await reloadFromDisk();
      backupSettings.lastBackupIso = now.toIso8601String();
      _pruneBackups(root, backupSettings.maxAutoBackups);
      await save(skipProfileSync: true);

      return BackupEntry(
        name: folderName,
        path: dst.path,
        createdAt: now,
        sizeBytes: _dirSizeBytes(dst),
      );
    } catch (_) {
      return null;
    }
  }

  /// Run automatic backup on launch if enabled and due according to interval.
  Future<BackupEntry?> runAutoBackupIfDue() async {
    if (!backupSettings.autoBackupEnabled) return null;
    final intervalHours = backupSettings.autoBackupIntervalHours;
    if (intervalHours > 0 && backupSettings.lastBackupIso.isNotEmpty) {
      final last = DateTime.tryParse(backupSettings.lastBackupIso);
      if (last != null && DateTime.now().difference(last).inHours < intervalHours) {
        return null;
      }
    }
    return createBackup(tag: 'auto');
  }

  List<BackupEntry> listBackups() {
    final result = <BackupEntry>[];
    try {
      final root = Directory(backupSettings.backupFolder);
      if (!root.existsSync()) return result;
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final ini = File(p.join(entity.path, 'Settings.ini'));
        if (!ini.existsSync()) continue;
        final stat = ini.statSync();
        result.add(
          BackupEntry(
            name: p.basename(entity.path),
            path: entity.path,
            createdAt: stat.modified,
            sizeBytes: _dirSizeBytes(entity),
          ),
        );
      }
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {}
    return result;
  }

  Future<bool> restoreBackup(String backupDirPath) async {
    try {
      final srcDir = Directory(backupDirPath);
      final srcIni = File(p.join(srcDir.path, 'Settings.ini'));
      if (!srcIni.existsSync()) return false;
      await srcIni.copy(iniFile.path);
      final srcIcons = Directory(p.join(srcDir.path, 'Icons'));
      if (srcIcons.existsSync()) {
        await _copyDirFiles(srcIcons, iconsDir, skipSubdir: 'cache');
      }
      final srcLangs = Directory(p.join(srcDir.path, 'Languages'));
      if (srcLangs.existsSync()) {
        await _copyDirFiles(srcLangs, languagesDir);
      }
      await reloadFromDisk();
      await save();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _copyDirFiles(
    Directory src,
    Directory dst, {
    String? skipSubdir,
  }) async {
    if (!src.existsSync()) return;
    if (!dst.existsSync()) await dst.create(recursive: true);
    await for (final entity in src.list(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      if (skipSubdir != null && name.toLowerCase() == skipSubdir.toLowerCase()) continue;
      final destPath = p.join(dst.path, name);
      if (entity is Directory) {
        await _copyDirFiles(entity, Directory(destPath));
      } else if (entity is File) {
        try {
          if (await entity.length() <= 10 * 1024 * 1024) {
            await entity.copy(destPath);
          }
        } catch (_) {}
      }
    }
  }

  static void _pruneBackups(Directory root, int maxKeep) {
    try {
      final dirs = root
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => File(p.join(d.path, 'Settings.ini')).existsSync())
          .toList();
      if (dirs.length <= maxKeep) return;
      dirs.sort((a, b) => b.path.compareTo(a.path));
      for (var i = maxKeep; i < dirs.length; i++) {
        try {
          dirs[i].deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  static int _dirSizeBytes(Directory dir) {
    var total = 0;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) total += e.lengthSync();
      }
    } catch (_) {}
    return total;
  }

  static String _computeBytesSignature(List<int> bytes) {
    // Fast 32-bit FNV-1a + exact length — immune to Windows 1-second mtime granularity!
    var hash = 0x811C9DC5;
    for (var i = 0; i < bytes.length; i++) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${bytes.length}:$hash';
  }

  Future<bool> hasExternalChanges() async {
    try {
      if (!await iniFile.exists()) return false;
      final bytes = await iniFile.readAsBytes();
      if (bytes.isEmpty) return false;
      final sig = _computeBytesSignature(bytes);
      return _lastContentSignature == null || sig != _lastContentSignature;
    } catch (_) {
      return false;
    }
  }

  static String _unquoteIniValue(String raw) {
    final s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s
          .substring(1, s.length - 1)
          .replaceAll(r'\\', r'\')
          .replaceAll(r'\"', '"');
    }
    if (s.toLowerCase().startsWith('dword:')) {
      final parsed = int.tryParse(s.substring(6).trim(), radix: 16);
      if (parsed != null) return parsed.toString();
    }
    return s;
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
      var k = line.substring(0, idx).trim();
      if (k.length >= 2 && k.startsWith('"') && k.endsWith('"')) {
        k = k.substring(1, k.length - 1);
      }
      final v = _unquoteIniValue(line.substring(idx + 1));
      sections[currentSection]![k] = v;
    }
    return sections;
  }

  /// Detect if an INI file is an original RocketDock 1.3.5 Settings.ini (or AeroDock Settings.ini).
  static bool isRocketDock135Ini(Map<String, Map<String, String>> sections) {
    for (final entry in sections.entries) {
      final lower = entry.key.toLowerCase();
      if (lower == 'rocketdock' ||
          lower == 'rocketdock-settings' ||
          lower == r'software\rocketdock' ||
          lower == r'rocketdock\icons' ||
          lower == r'software\rocketdock\icons' ||
          lower == 'icons' ||
          lower.startsWith('rocketdock') ||
          lower.startsWith('icon') ||
          lower.startsWith('item')) {
        return true;
      }
      // Also detect by RocketDock-style keys like "0-Title", "0-Command", "IconMin"
      for (final k in entry.value.keys) {
        final kl = k.toLowerCase();
        if (kl == '0-title' || kl == '0-command' || kl == '0-filename' || kl == 'iconmin') {
          return true;
        }
      }
    }
    return false;
  }

  static bool isAeroDockIni(Map<String, Map<String, String>> sections) {
    return sections.containsKey('Dock1') || sections.containsKey('Dock1-Items');
  }

  /// Resolve an icon path from an imported INI and copy external icon files into portable Icons/
  /// so imported icons NEVER disappear if the old folder is moved or deleted.
  String? _importIconAsset(String? raw, String sourceBaseDir) {
    if (raw == null || raw.trim().isEmpty) return null;
    final cleaned = raw.replaceAll('"', '').trim();
    if (cleaned.isEmpty) return null;
    if (!cleaned.startsWith(_appDirToken) && isNonFileScheme(cleaned)) return null;

    final expanded = fromPortablePath(cleaned);
    final baseName = p.basename(expanded);
    final candidates = <String>[
      expanded,
      cleaned,
      p.join(sourceBaseDir, cleaned),
      p.join(sourceBaseDir, 'Icons', cleaned),
      p.join(sourceBaseDir, 'Icons', baseName),
      p.join(sourceBaseDir, 'Icons', 'cache', baseName),
      p.join(iconsDir.path, baseName),
      p.join(iconsDir.path, 'imported', baseName),
      p.join(iconsCacheDir.path, baseName),
      p.join(r'C:\Program Files (x86)\RocketDock', cleaned),
      p.join(r'C:\Program Files (x86)\RocketDock\Icons', cleaned),
      p.join(r'C:\Program Files (x86)\RocketDock\Icons', baseName),
      p.join(r'C:\Program Files\RocketDock', cleaned),
      p.join(r'C:\Program Files\RocketDock\Icons', cleaned),
      p.join(r'C:\Program Files\RocketDock\Icons', baseName),
    ];

    File? found;
    for (final c in candidates) {
      if (safeFileExists(c)) {
        found = File(c.trim());
        break;
      }
    }
    if (found == null) return null;

    // Already inside our current portable directory -> keep directly
    final ownPrefix = '${portableDir.path.toLowerCase()}\\';
    if (found.path.toLowerCase().startsWith(ownPrefix)) {
      return found.path;
    }

    // Copy external icon into our portable Icons/imported or Icons/cache directory
    try {
      final isCacheIcon = baseName.toLowerCase().startsWith('hd128_') ||
          baseName.toLowerCase().startsWith('ico_');
      final dstDir = isCacheIcon
          ? iconsCacheDir
          : Directory(p.join(iconsDir.path, 'imported'));
      if (!dstDir.existsSync()) dstDir.createSync(recursive: true);
      final dstFile = File(p.join(dstDir.path, baseName));
      if (!dstFile.existsSync()) {
        found.copySync(dstFile.path);
      }
      return dstFile.path;
    } catch (_) {
      return found.path;
    }
  }

  List<DockItemModel> _parseAeroDockItemsSection(
    int dockId,
    Map<String, String> itemsSec, {
    String? sourceBaseDir,
  }) {
    final count = _int(itemsSec['Count'], 0);
    final list = <DockItemModel>[];
    for (var i = 0; i < count; i++) {
      try {
        final prefix = 'Item$i';
        final type = itemsSec['$prefix.Type'];
        if (type == null || type.isEmpty) continue;
        final rawIcon = _emptyToNull(itemsSec['$prefix.IconPath']);
        final rawAlt = _emptyToNull(itemsSec['$prefix.IconPathAlt']);
        final resolvedIcon = sourceBaseDir != null
            ? _importIconAsset(rawIcon, sourceBaseDir)
            : (rawIcon != null ? fromPortablePath(rawIcon) : null);
        final resolvedAlt = sourceBaseDir != null
            ? _importIconAsset(rawAlt, sourceBaseDir)
            : (rawAlt != null ? fromPortablePath(rawAlt) : null);
        list.add(
          DockItemModel(
            id: itemsSec['$prefix.Id'] ?? 'd${dockId}_$i',
            type: type,
            title: itemsSec['$prefix.Title'] ?? '',
            target: fromPortablePath(itemsSec['$prefix.Target'] ?? ''),
            startIn: fromPortablePath(itemsSec['$prefix.StartIn'] ?? ''),
            args: itemsSec['$prefix.Args'] ?? '',
            runMode: itemsSec['$prefix.RunMode'] ?? 'normal',
            openRunning: itemsSec['$prefix.OpenRunning'] ?? 'global',
            popupMenu: _bool(itemsSec['$prefix.PopupMenu'], true),
            iconKey: itemsSec['$prefix.IconKey'] ?? 'rocket',
            color: itemsSec['$prefix.Color'] ?? '#0284C7',
            iconPath: resolvedIcon,
            iconPathAlt: resolvedAlt,
            devRuleId: _emptyToNull(itemsSec['$prefix.DevRuleId']),
          ),
        );
      } catch (_) {
        // Never allow a single malformed item to abort loading the dock or other panels
      }
    }
    return list;
  }

  /// Import an original RocketDock 1.3.5 Settings.ini (ALL real formats + .reg exports!)
  /// OR an AeroDock Settings.ini (transfers ALL 4 panels, positions, enabled states, DevRules, and icons!).
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
      final baseDir = sourceFile.parent.path;

      // Safety backup before importing
      if (backupSettings.autoBackupEnabled && iniFile.existsSync()) {
        await createBackup(tag: 'pre_import');
      }

      // ------------------------------------------------------------------
      // CASE 1: AeroDock Settings.ini -> Full Multi-Panel Profile Transfer!
      // Transfers General flags (Dock2/3/Dev enabled), ALL 4 panel positions & styles,
      // ALL 4 panel icon lists (copying icons into portable Icons/), and DevRules!
      // ------------------------------------------------------------------
      if (isAeroDockIni(sections)) {
        // Also copy any custom icons from sourceFolder/Icons if present
        try {
          final srcIconsDir = Directory(p.join(baseDir, 'Icons'));
          if (srcIconsDir.existsSync() &&
              srcIconsDir.path.toLowerCase() != iconsDir.path.toLowerCase()) {
            await _copyDirFiles(srcIconsDir, iconsDir);
          }
        } catch (_) {}

        final g = sections['General'];
        if (g != null && importVisualSettings) {
          final legacyDockCount = _int(g['DockCount'], 1);
          global = GlobalDockSettings(
            language: g['Language'] ?? global.language,
            launchWithWindows: global.launchWithWindows,
            portableIni: _bool(g['PortableIni'], global.portableIni),
            minimizeToDock: _bool(g['MinimizeToDock'], global.minimizeToDock),
            disableMinimizeAnimation:
                _bool(g['DisableMinimizeAnimation'], global.disableMinimizeAnimation),
            showRunningIndicators:
                _bool(g['ShowRunningIndicators'], global.showRunningIndicators),
            openRunningInstance:
                _bool(g['OpenRunningInstance'], global.openRunningInstance),
            lockItems: _bool(g['LockItems'], global.lockItems),
            dock2Enabled: g.containsKey('Dock2Enabled')
                ? _bool(g['Dock2Enabled'], global.dock2Enabled)
                : legacyDockCount >= 2,
            dock3Enabled: g.containsKey('Dock3Enabled')
                ? _bool(g['Dock3Enabled'], global.dock3Enabled)
                : legacyDockCount >= 3,
            devDockEnabled: _bool(g['DevDockEnabled'], global.devDockEnabled),
            excludedWindows: _list(g['ExcludedWindows']),
            iconFolders: _list(g['IconFolders']).map(fromPortablePath).toList(),
          );
        }

        // Import DevDock & DevRules if present
        final devSec = sections['DevDock'];
        final rulesSec = sections['DevRules'];
        if (devSec != null || rulesSec != null) {
          final devDef = DevDockSettings.defaults(portableDir);
          final loadedRules = <DevAppRule>[];
          if (rulesSec != null) {
            final ruleCount = _int(rulesSec['Count'], 0);
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
          }
          devSettings = DevDockSettings(
            watchFolder: (devSec?['WatchFolder'] ?? '').isNotEmpty
                ? fromPortablePath(devSec!['WatchFolder']!)
                : devDef.watchFolder,
            appsRootFolder: (devSec?['AppsRootFolder'] ?? '').isNotEmpty
                ? fromPortablePath(devSec!['AppsRootFolder']!)
                : devDef.appsRootFolder,
            maxBackupsPerApp: _int(devSec?['MaxBackupsPerApp'], devSettings.maxBackupsPerApp).clamp(1, 30),
            defaultPreserveExts: (devSec?['DefaultPreserveExts'] ?? '').isNotEmpty
                ? devSec!['DefaultPreserveExts']!
                : devDef.defaultPreserveExts,
            moveArchiveToStorage:
                _bool(devSec?['MoveArchiveToStorage'], devSettings.moveArchiveToStorage),
            rules: loadedRules.isNotEmpty ? loadedRules : devSettings.rules,
            processedSignatures: _list(devSec?['ProcessedSignatures']),
          );
        }

        var importedPanelsCount = 0;
        var importedItemsTotal = 0;
        for (var id = 1; id <= 4; id++) {
          final pSec = sections['Dock$id'];
          if (pSec != null) {
            importedPanelsCount++;
            if (importVisualSettings) {
              panels[id] = _parsePanelSection(id, pSec);
            }
          }

          final iSec = sections['Dock$id-Items'];
          if (iSec != null) {
            final parsedItems = _parseAeroDockItemsSection(id, iSec, sourceBaseDir: baseDir);
            importedItemsTotal += parsedItems.length;
            if (replaceExistingItems) {
              dockItems[id] = parsedItems;
            } else {
              dockItems.putIfAbsent(id, () => []).addAll(parsedItems);
            }
          }
        }

        await save();
        return RocketDockImportResult(
          ok: true,
          importedItems: importedItemsTotal,
          importedSettings: importVisualSettings && importedPanelsCount > 0,
          message:
              'Профиль AeroDock перенесён: $importedPanelsCount панелей, $importedItemsTotal значков, расположение и иконки сохранены!',
        );
      }

      // ------------------------------------------------------------------
      // CASE 2: Original RocketDock 1.3.5 (and ObjectDock/RK/Y'z Dock / .reg export)
      // Real RocketDock 1.3.5 stores settings in [RocketDock] / [Software\RocketDock] /
      // [HKEY_CURRENT_USER\Software\RocketDock], and icons either in the same section OR in
      // [RocketDock\Icons] / [Software\RocketDock\Icons] / [Icons] / [Icon0..N] / [Icons\0..N]!
      // ------------------------------------------------------------------
      Map<String, String>? rdMain;
      final rdIconMaps = <Map<String, String>>[];
      final perIconSections = <Map<String, String>>[];

      bool hasIndexedIconKeys(Map<String, String> map) {
        return map.keys.any((k) {
          final dash = k.indexOf('-');
          if (dash > 0 && int.tryParse(k.substring(0, dash)) != null) return true;
          final m = RegExp(r'^(title|command|target|filename|icon|isseparator)(\d+)$',
                  caseSensitive: false)
              .firstMatch(k);
          return m != null;
        });
      }

      for (final entry in sections.entries) {
        final lower = entry.key.toLowerCase();
        final map = entry.value;
        final indexed = hasIndexedIconKeys(map);

        if (lower == 'rocketdock' ||
            lower == 'rocketdock-settings' ||
            lower == r'software\rocketdock' ||
            lower.endsWith(r'\software\rocketdock') ||
            lower == 'settings' ||
            lower == 'dock') {
          rdMain ??= map;
          if (indexed) rdIconMaps.add(map);
        } else if (lower == r'rocketdock\icons' ||
            lower == r'software\rocketdock\icons' ||
            lower.endsWith(r'\software\rocketdock\icons') ||
            lower == 'rocketdock-icons' ||
            lower == 'icons' ||
            lower.endsWith(r'\icons')) {
          rdIconMaps.add(map);
        } else if (RegExp(r'(^|\\)(rocketdock[-_\\]?icon|icon|item)\d+$').hasMatch(lower) ||
            RegExp(r'\\icons\\\d+$').hasMatch(lower)) {
          perIconSections.add(map);
        } else if (indexed) {
          rdIconMaps.add(map);
        }
      }

      if (rdMain == null && rdIconMaps.isEmpty && perIconSections.isEmpty) {
        return const RocketDockImportResult(
          ok: false,
          importedItems: 0,
          importedSettings: false,
          message:
              'Не удалось распознать формат INI (проверьте, что файл содержит секции [RocketDock], [Software\\RocketDock], [Icons] или [Dock1]).',
        );
      }

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
        if (iconMin != null && iconMin >= 16 && iconMin <= 128) {
          panel.iconSize = iconMin.clamp(32, 96);
          if (iconMax != null && iconMax >= iconMin) {
            panel.zoomScale = (iconMax / iconMin).clamp(1.0, 2.2);
          }
        }

        final iconOp = double.tryParse(getCI('IconOpacity') ?? '');
        if (iconOp != null) {
          panel.iconOpacity = (iconOp > 100 ? (iconOp / 255.0) * 100.0 : iconOp).clamp(20, 100);
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

        final hOff = double.tryParse(getCI('HOffset') ?? getCI('CenterOffset') ?? '');
        if (hOff != null) {
          panel.centerOffset = (hOff.abs() > 40 ? (hOff / 20.0) : hOff).clamp(-40, 40);
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

        final disableLabels = getCI('DisableLabels');
        final showLabels = getCI('ShowLabels');
        if (disableLabels != null) {
          panel.showLabels = disableLabels != '1';
        } else if (showLabels != null) {
          panel.showLabels = showLabels == '1';
        }

        final fontName = getCI('FontName');
        if (fontName != null && fontName.isNotEmpty) panel.labelFontFamily = fontName;

        final fontSize = double.tryParse(getCI('FontSize') ?? '');
        if (fontSize != null && fontSize >= 8 && fontSize <= 28) {
          panel.labelFontSize = fontSize.clamp(9, 24);
        }

        final themeName = getCI('Theme');
        if (themeName != null && themeName.isNotEmpty) {
          try {
            final localSkinPath = p.join(skinsDir.path, themeName);
            if (!safeDirExists(localSkinPath)) {
              // Try copying matching skin from source RocketDock/Skins/<Theme>
              final srcSkinPath = p.join(baseDir, 'Skins', themeName);
              if (safeDirExists(srcSkinPath)) {
                await _copyDirFiles(Directory(srcSkinPath), Directory(localSkinPath));
              }
            }
            if (safeDirExists(localSkinPath)) {
              panel.theme = 'skin:$themeName';
            }
          } catch (_) {}
        }

        panels[targetDockId] = panel;
        settingsImported = true;
      }

      DockItemModel buildRdItem({
        required int idx,
        required bool isSep,
        required String rdType,
        required String title,
        required String cmd,
        required String args,
        required String workDir,
        required String? fileName,
        required String? fileName2,
        required String showCmd,
        required String openRunRaw,
        required bool useCtx,
      }) {
        final cmdLower = cmd.toLowerCase();
        String type;
        String resolvedTarget = cmd;
        String iconKey = 'rocket';
        String color = '#0284C7';

        if (isSep || rdType == '1' || cmdLower == '[separator]') {
          type = 'separator';
        } else if (cmdLower == '[settings]' ||
            cmdLower.contains('dock settings') ||
            (rdType == '3' && cmdLower.isEmpty)) {
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
        } else if (cmdLower.contains('20d04fe0-3aea-1069-a2d8-08002b30309d')) {
          type = 'file';
          resolvedTarget = 'explorer.exe';
          args = args.isEmpty ? 'shell:MyComputerFolder' : args;
          iconKey = 'folder-blue';
          color = '#2563EB';
        } else if (cmdLower.contains('clock')) {
          type = 'docklet_clock';
          iconKey = 'clock';
        } else if (cmdLower.startsWith('http://') || cmdLower.startsWith('https://')) {
          type = 'blank';
          iconKey = 'globe';
        } else if (cmd.isNotEmpty && safeIsDirectory(cmd)) {
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

        return DockItemModel(
          id: 'rd135_${DateTime.now().millisecondsSinceEpoch}_$idx',
          type: type,
          title: title.isEmpty
              ? (type == 'separator' ? 'Разделитель' : p.basenameWithoutExtension(cmd))
              : title,
          target: resolvedTarget,
          startIn: workDir,
          args: args,
          runMode: runMode,
          openRunning: openRunning,
          popupMenu: useCtx,
          iconKey: iconKey,
          color: color,
          iconPath: _importIconAsset(fileName, baseDir),
          iconPathAlt: _importIconAsset(fileName2, baseDir),
        );
      }

      final importedList = <DockItemModel>[];

      // Parse indexed icon keys (`0-Title`/`0-Command`/`0-FileName` AND `Title0`/`Command0`/`FileName0`)
      for (final rdIcons in rdIconMaps) {
        final indices = <int>{};
        for (final key in rdIcons.keys) {
          final dash = key.indexOf('-');
          if (dash > 0) {
            final idx = int.tryParse(key.substring(0, dash));
            if (idx != null) {
              indices.add(idx);
              continue;
            }
          }
          final m = RegExp(r'^(?:title|command|target|filename|icon|isseparator)(\d+)$',
                  caseSensitive: false)
              .firstMatch(key);
          if (m != null) {
            final idx = int.tryParse(m.group(1)!);
            if (idx != null) indices.add(idx);
          }
        }
        final sorted = indices.toList()..sort();

        String? iconVal(int i, String field) {
          final wantedDash = '$i-${field.toLowerCase()}';
          final wantedSuffix = '${field.toLowerCase()}$i';
          for (final e in rdIcons.entries) {
            final kl = e.key.toLowerCase();
            if (kl == wantedDash || kl == wantedSuffix) return e.value;
          }
          return null;
        }

        for (final idx in sorted) {
          importedList.add(
            buildRdItem(
              idx: idx,
              isSep: iconVal(idx, 'IsSeparator') == '1',
              rdType: iconVal(idx, 'Type') ?? '0',
              title: iconVal(idx, 'Title') ?? iconVal(idx, 'Name') ?? '',
              cmd: iconVal(idx, 'Command') ?? iconVal(idx, 'Target') ?? iconVal(idx, 'Link') ?? '',
              args: iconVal(idx, 'Arguments') ?? iconVal(idx, 'Args') ?? '',
              workDir: iconVal(idx, 'WorkingDirectory') ?? iconVal(idx, 'StartIn') ?? '',
              fileName: iconVal(idx, 'FileName') ?? iconVal(idx, 'Icon') ?? iconVal(idx, 'Image'),
              fileName2: iconVal(idx, 'FileName2'),
              showCmd: iconVal(idx, 'ShowCmd') ?? '1',
              openRunRaw: iconVal(idx, 'OpenRunning') ?? '0',
              useCtx: iconVal(idx, 'UseContext') != '0',
            ),
          );
        }
      }

      // Also parse per-icon sections (`[Icon0]`, `[Item0]`, `[Software\RocketDock\Icons\0]`, etc.)
      for (var i = 0; i < perIconSections.length; i++) {
        final sec = perIconSections[i];
        String? val(String field) {
          final fl = field.toLowerCase();
          for (final e in sec.entries) {
            if (e.key.toLowerCase() == fl) return e.value;
          }
          return null;
        }

        importedList.add(
          buildRdItem(
            idx: 1000 + i,
            isSep: val('IsSeparator') == '1',
            rdType: val('Type') ?? '0',
            title: val('Title') ?? val('Name') ?? '',
            cmd: val('Command') ?? val('Target') ?? val('Link') ?? '',
            args: val('Arguments') ?? val('Args') ?? '',
            workDir: val('WorkingDirectory') ?? val('StartIn') ?? '',
            fileName: val('FileName') ?? val('Icon') ?? val('Image'),
            fileName2: val('FileName2'),
            showCmd: val('ShowCmd') ?? '1',
            openRunRaw: val('OpenRunning') ?? '0',
            useCtx: val('UseContext') != '0',
          ),
        );
      }

      if (importedList.isNotEmpty) {
        if (replaceExistingItems) {
          dockItems[targetDockId] = importedList;
        } else {
          dockItems.putIfAbsent(targetDockId, () => []).addAll(importedList);
        }
      }
      if (targetDockId == 2) global.dock2Enabled = true;
      if (targetDockId == 3) global.dock3Enabled = true;
      if (targetDockId == 4) global.devDockEnabled = true;

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

  DockPanelConfig _parsePanelSection(int id, Map<String, String> s) {
    final def = DockPanelConfig.defaultFor(id);
    return DockPanelConfig(
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

  Future<void> reloadFromDisk() async {
    if (!await iniFile.exists()) return;
    List<int>? bytes;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        bytes = await iniFile.readAsBytes();
        break;
      } catch (_) {
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 45));
        }
      }
    }
    if (bytes == null || bytes.isEmpty) return;
    final text = decodeWindowsIniBytes(bytes);
    final sections = parseIniText(text);

    // If the user literally replaced Settings.ini with a RocketDock 1.3.5 Settings.ini!
    if (isRocketDock135Ini(sections) && !isAeroDockIni(sections)) {
      await importRocketDock135Ini(iniFile, targetDockId: 1);
      return;
    }

    final g = sections['General'] ?? {};
    _revision = _int(g['Revision'], _revision);
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
      iconFolders: _list(g['IconFolders']).map(fromPortablePath).toList(),
    );

    // Load Backup & Upgrade Profile Sync settings
    final bSec = sections['Backup'] ?? {};
    final bDef = BackupSettings.defaults();
    backupSettings = BackupSettings(
      autoBackupEnabled: _bool(bSec['AutoBackupEnabled'], bDef.autoBackupEnabled),
      autoBackupIntervalHours: _int(bSec['AutoBackupIntervalHours'], bDef.autoBackupIntervalHours).clamp(0, 720),
      maxAutoBackups: _int(bSec['MaxAutoBackups'], bDef.maxAutoBackups).clamp(2, 50),
      backupFolder: (bSec['BackupFolder'] ?? '').isNotEmpty
          ? fromPortablePath(bSec['BackupFolder']!)
          : bDef.backupFolder,
      autoSyncProfile: _bool(bSec['AutoSyncProfile'], bDef.autoSyncProfile),
      lastBackupIso: bSec['LastBackupIso'] ?? '',
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
          ? fromPortablePath(devSec['WatchFolder']!)
          : devDef.watchFolder,
      appsRootFolder: (devSec['AppsRootFolder'] ?? '').isNotEmpty
          ? fromPortablePath(devSec['AppsRootFolder']!)
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
      if (s != null) {
        panels[id] = _parsePanelSection(id, s);
      }

      final itemsSec = sections['Dock$id-Items'];
      if (itemsSec != null) {
        dockItems[id] = _parseAeroDockItemsSection(id, itemsSec);
      }
    }

    _lastContentSignature = _computeBytesSignature(bytes);
    try {
      lastLoadedModified = await iniFile.lastModified();
    } catch (_) {}
  }

  /// Safely persist ONLY the items list of [dockId] without overwriting panel positions
  /// or settings that may have been updated concurrently by the Settings window or another dock!
  Future<void> saveDockItemsOnly(int dockId, {bool skipProfileSync = false}) async {
    final myItems = List<DockItemModel>.from(dockItems[dockId] ?? const []);
    await reloadFromDisk();
    dockItems[dockId] = myItems;
    await save(skipProfileSync: skipProfileSync);
  }

  /// Safely persist ONLY the panel configuration of [dockId] without clobbering sibling docks!
  Future<void> savePanelConfigOnly(int dockId, {bool skipProfileSync = false}) async {
    final myCfg = panels[dockId]?.copy();
    if (myCfg == null) return;
    await reloadFromDisk();
    panels[dockId] = myCfg;
    await save(skipProfileSync: skipProfileSync);
  }

  /// Safely mutate a global flag on top of the latest disk Settings.ini without clobbering panels!
  Future<void> saveGlobalChange(
    void Function(GlobalDockSettings g) mutate, {
    bool skipProfileSync = false,
  }) async {
    await reloadFromDisk();
    mutate(global);
    await save(skipProfileSync: skipProfileSync);
  }

  Future<void> save({bool skipProfileSync = false, bool preserveDiskItems = false}) async {
    // When saving from the Settings window, preserve any icons added/reordered on docks in parallel
    if (preserveDiskItems && await iniFile.exists()) {
      try {
        final diskBytes = await iniFile.readAsBytes();
        if (diskBytes.isNotEmpty) {
          final diskSections = parseIniText(decodeWindowsIniBytes(diskBytes));
          final diskRev = _int(diskSections['General']?['Revision'], 0);
          if (diskRev > _revision) _revision = diskRev;
          for (var id = 1; id <= 4; id++) {
            final iSec = diskSections['Dock$id-Items'];
            if (iSec != null) {
              dockItems[id] = _parseAeroDockItemsSection(id, iSec);
            }
          }
        }
      } catch (_) {}
    }

    _revision++;
    final sb = StringBuffer()
      ..writeln('; AeroDock Portable v3.6 — Settings.ini (UTF-8, RocketDock 1.3.5 Import + Live Preview + Auto-Backup)')
      ..writeln('[General]')
      ..writeln('Revision=$_revision')
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
      ..writeln('IconFolders=${global.iconFolders.map(toPortablePath).join('|')}')
      ..writeln('')
      ..writeln('[Backup]')
      ..writeln('AutoBackupEnabled=${backupSettings.autoBackupEnabled ? 1 : 0}')
      ..writeln('AutoBackupIntervalHours=${backupSettings.autoBackupIntervalHours}')
      ..writeln('MaxAutoBackups=${backupSettings.maxAutoBackups}')
      ..writeln('BackupFolder=${_sanitizeIniVal(toPortablePath(backupSettings.backupFolder))}')
      ..writeln('AutoSyncProfile=${backupSettings.autoSyncProfile ? 1 : 0}')
      ..writeln('LastBackupIso=${_sanitizeIniVal(backupSettings.lastBackupIso)}')
      ..writeln('')
      ..writeln('[DevDock]')
      ..writeln('WatchFolder=${_sanitizeIniVal(toPortablePath(devSettings.watchFolder))}')
      ..writeln('AppsRootFolder=${_sanitizeIniVal(toPortablePath(devSettings.appsRootFolder))}')
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
          ..writeln('$pre.Target=${_sanitizeIniVal(toPortablePath(it.target))}')
          ..writeln('$pre.StartIn=${_sanitizeIniVal(toPortablePath(it.startIn))}')
          ..writeln('$pre.Args=${_sanitizeIniVal(it.args)}')
          ..writeln('$pre.RunMode=${it.runMode}')
          ..writeln('$pre.OpenRunning=${it.openRunning}')
          ..writeln('$pre.PopupMenu=${it.popupMenu ? 1 : 0}')
          ..writeln('$pre.IconKey=${it.iconKey}')
          ..writeln('$pre.Color=${it.color}')
          ..writeln('$pre.IconPath=${_sanitizeIniVal(toPortablePath(it.iconPath ?? ''))}')
          ..writeln('$pre.IconPathAlt=${_sanitizeIniVal(toPortablePath(it.iconPathAlt ?? ''))}')
          ..writeln('$pre.DevRuleId=${_sanitizeIniVal(it.devRuleId ?? '')}');
      }
      sb.writeln('');
    }

    final bytes = utf8.encode(sb.toString());
    final tmpFile = File('${iniFile.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}');
    var written = false;

    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await tmpFile.writeAsBytes(bytes, flush: true);
        try {
          await tmpFile.rename(iniFile.path);
        } catch (_) {
          // On Windows, rename over an open/locked file can fail; fall back to direct atomic-ish copy
          await iniFile.writeAsBytes(bytes, flush: true);
          if (tmpFile.existsSync()) {
            try {
              tmpFile.deleteSync();
            } catch (_) {}
          }
        }
        _lastContentSignature = _computeBytesSignature(bytes);
        try {
          lastLoadedModified = await iniFile.lastModified();
        } catch (_) {}
        written = true;
        break;
      } catch (_) {
        if (attempt < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 55));
        }
      }
    }
    if (!written && tmpFile.existsSync()) {
      try {
        tmpFile.deleteSync();
      } catch (_) {}
    }

    if (!skipProfileSync) {
      await _syncToUserProfile();
    }
  }

  Future<void> resetSettingsToDefaultsOnly() async {
    if (backupSettings.autoBackupEnabled && iniFile.existsSync()) {
      await createBackup(tag: 'pre_reset');
    }
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
    if (backupSettings.autoBackupEnabled && iniFile.existsSync()) {
      await createBackup(tag: 'pre_full_reset');
    }
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
