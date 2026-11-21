import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Compatible skin loaded from portable Skins/<Name>/ (RocketDock, ObjectDock,
/// MobyDock, RK Launcher, Y'z Dock background.ini + PNG image).
class ExternalSkinInfo {
  final String id; // 'skin:<folderName>'
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

/// ObjectDock-format docklet discovered inside portable Docklets/ folder.
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

/// Global settings shared across all 1..3 dock panels.
class GlobalDockSettings {
  String language;
  bool launchWithWindows;
  bool portableIni;
  bool minimizeToDock;
  bool disableMinimizeAnimation;
  bool showRunningIndicators;
  bool openRunningInstance;
  bool lockItems;
  int dockCount; // 1, 2, or 3 independent docks
  List<String> excludedWindows; // Process names permanently excluded via Ctrl+Alt+Shift
  List<String> iconFolders; // User-managed custom icon folders (+ / -)

  GlobalDockSettings({
    this.language = 'ru',
    this.launchWithWindows = false,
    this.portableIni = true,
    this.minimizeToDock = true,
    this.disableMinimizeAnimation = false,
    this.showRunningIndicators = true,
    this.openRunningInstance = true,
    this.lockItems = false,
    this.dockCount = 2,
    List<String>? excludedWindows,
    List<String>? iconFolders,
  })  : excludedWindows = excludedWindows ?? [],
        iconFolders = iconFolders ?? [];

  GlobalDockSettings copy() => GlobalDockSettings(
        language: language,
        launchWithWindows: launchWithWindows,
        portableIni: portableIni,
        minimizeToDock: minimizeToDock,
        disableMinimizeAnimation: disableMinimizeAnimation,
        showRunningIndicators: showRunningIndicators,
        openRunningInstance: openRunningInstance,
        lockItems: lockItems,
        dockCount: dockCount,
        excludedWindows: List<String>.from(excludedWindows),
        iconFolders: List<String>.from(iconFolders),
      );

  static GlobalDockSettings defaults() => GlobalDockSettings();
}

/// Per-dock configuration (Dock 1, Dock 2, Dock 3 each have independent settings).
class DockPanelConfig {
  int dockId; // 1, 2, or 3
  String name;

  // Position
  String position; // 'bottom' | 'top' | 'left' | 'right'
  int monitorIndex; // -1 = Monitor * (all displays combined), 0..N = specific monitor
  String layer; // 'top' | 'normal' | 'bottom'
  double centerOffset; // -40..40 %
  double edgeOffset; // 0..64 px

  // Icons
  String renderQuality; // 'low' | 'medium' | 'high'
  double iconOpacity; // 20..100 %
  bool zoomOpaque; // Become 100% opaque while hovered/zoomed
  double iconSize; // 32..96 px
  String hoverEffect; // 'bubble' | 'lift' | 'none'
  double zoomScale; // 1.0..2.2
  double zoomWidth; // 1..6 neighbor icons
  int zoomDurationMs; // 60..400 ms

  // Style
  String theme; // 'crystal' | 'aero3d' | 'graphite' | 'silk' | 'minimal' | 'retro' | 'skin:<name>'
  double bgOpacity; // 0..100 %
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

  // Behavior
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
    this.edgeOffset = 10,
    this.renderQuality = 'high',
    this.iconOpacity = 100,
    this.zoomOpaque = true,
    this.iconSize = 54,
    this.hoverEffect = 'bubble',
    this.zoomScale = 1.55,
    this.zoomWidth = 2.5,
    this.zoomDurationMs = 110,
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
    this.autoHideDurationMs = 180,
    this.autoHideDelayMs = 250,
    this.popupOnMouseover = true,
    this.popupDelayMs = 180,
  });

  static DockPanelConfig defaultFor(int dockId) {
    switch (dockId) {
      case 2:
        return DockPanelConfig(
          dockId: 2,
          name: 'Панель 2 (Боковая)',
          position: 'right',
          iconSize: 48,
          zoomScale: 1.45,
          theme: 'crystal',
          autoHide: false,
        );
      case 3:
        return DockPanelConfig(
          dockId: 3,
          name: 'Панель 3 (Верхняя)',
          position: 'top',
          iconSize: 44,
          zoomScale: 1.4,
          theme: 'graphite',
          autoHide: true,
        );
      case 1:
      default:
        return DockPanelConfig(
          dockId: 1,
          name: 'Панель 1 (Основная)',
          position: 'bottom',
          iconSize: 54,
          zoomScale: 1.55,
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

/// Complete RocketDock item / docklet model.
/// Supported [type] values:
///   'file', 'path', 'blank', 'separator', 'recycle_bin', 'dock_settings', 'quit',
///   'docklet_clock', 'docklet_battery', 'docklet_sysstats', 'docklet_calendar',
///   'docklet_stack', 'docklet_external'
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
  String? iconPath; // Custom or extracted PNG/ICO (Normal state)
  String? iconPathAlt; // Alt state (e.g. Full Recycle Bin)

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
      );
}

/// Full portable Settings.ini repository right next to aerodock.exe.
class PortableIniStore {
  final Directory portableDir;
  final File iniFile;
  final Directory skinsDir;
  final Directory iconsDir;
  final Directory iconsCacheDir;
  final Directory languagesDir;
  final Directory dockletsDir;

  GlobalDockSettings global;
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
      panels: {
        1: DockPanelConfig.defaultFor(1),
        2: DockPanelConfig.defaultFor(2),
        3: DockPanelConfig.defaultFor(3),
      },
      dockItems: {
        1: defaultItemsFor(1),
        2: defaultItemsFor(2),
        3: defaultItemsFor(3),
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

  Future<void> reloadFromDisk() async {
    if (!await iniFile.exists()) return;
    final lines = await iniFile.readAsLines();
    final sections = <String, Map<String, String>>{};
    var currentSection = '';

    for (final raw in lines) {
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

    final g = sections['General'] ?? {};
    global = GlobalDockSettings(
      language: g['Language'] ?? 'ru',
      launchWithWindows: _bool(g['LaunchWithWindows'], false),
      portableIni: _bool(g['PortableIni'], true),
      minimizeToDock: _bool(g['MinimizeToDock'], true),
      disableMinimizeAnimation: _bool(g['DisableMinimizeAnimation'], false),
      showRunningIndicators: _bool(g['ShowRunningIndicators'], true),
      openRunningInstance: _bool(g['OpenRunningInstance'], true),
      lockItems: _bool(g['LockItems'], false),
      dockCount: _int(g['DockCount'], 2).clamp(1, 3),
      excludedWindows: _list(g['ExcludedWindows']),
      iconFolders: _list(g['IconFolders']),
    );

    for (var id = 1; id <= 3; id++) {
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
      ..writeln('; AeroDock Portable v3.0 — Settings.ini (UTF-8, RocketDock compatible)')
      ..writeln('[General]')
      ..writeln('Language=${global.language}')
      ..writeln('LaunchWithWindows=${global.launchWithWindows ? 1 : 0}')
      ..writeln('PortableIni=${global.portableIni ? 1 : 0}')
      ..writeln('MinimizeToDock=${global.minimizeToDock ? 1 : 0}')
      ..writeln('DisableMinimizeAnimation=${global.disableMinimizeAnimation ? 1 : 0}')
      ..writeln('ShowRunningIndicators=${global.showRunningIndicators ? 1 : 0}')
      ..writeln('OpenRunningInstance=${global.openRunningInstance ? 1 : 0}')
      ..writeln('LockItems=${global.lockItems ? 1 : 0}')
      ..writeln('DockCount=${global.dockCount}')
      ..writeln('ExcludedWindows=${global.excludedWindows.join('|')}')
      ..writeln('IconFolders=${global.iconFolders.join('|')}')
      ..writeln('');

    for (var id = 1; id <= 3; id++) {
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
          ..writeln('$pre.IconPathAlt=${_sanitizeIniVal(it.iconPathAlt ?? '')}');
      }
      sb.writeln('');
    }

    await iniFile.writeAsString(sb.toString(), flush: true);
    lastLoadedModified = await iniFile.lastModified();
  }

  /// RocketDock "Defaults": resets settings ONLY, keeping all dock items untouched.
  Future<void> resetSettingsToDefaultsOnly() async {
    final keepCount = global.dockCount;
    global = GlobalDockSettings.defaults()..dockCount = keepCount;
    panels[1] = DockPanelConfig.defaultFor(1);
    panels[2] = DockPanelConfig.defaultFor(2);
    panels[3] = DockPanelConfig.defaultFor(3);
    await save();
  }

  /// Full reset: deletes Settings.ini and restores default items and settings.
  Future<void> fullReset() async {
    if (await iniFile.exists()) {
      await iniFile.delete();
    }
    global = GlobalDockSettings.defaults();
    for (var id = 1; id <= 3; id++) {
      panels[id] = DockPanelConfig.defaultFor(id);
      dockItems[id] = defaultItemsFor(id);
    }
    await save();
  }

  /// Scan portable Skins/ directory for RocketDock / ObjectDock / MobyDock / RK Launcher / Y'z Dock skins.
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
          for (final raw in ini.readAsLinesSync()) {
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

  /// Scan portable Docklets/ directory for ObjectDock-format docklets.
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

  /// List all PNG/ICO files inside a given icon directory.
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
      // Dock 2 (Side dock): Docklets + Quick Folders
      return [
        DockItemModel(
          id: 'd2_clock',
          type: 'docklet_clock',
          title: 'Часы',
          iconKey: 'clock',
          color: '#0F172A',
        ),
        DockItemModel(
          id: 'd2_sysstats',
          type: 'docklet_sysstats',
          title: 'CPU / RAM',
          iconKey: 'terminal',
          color: '#0284C7',
        ),
        DockItemModel(
          id: 'd2_battery',
          type: 'docklet_battery',
          title: 'Батарея',
          iconKey: 'star',
          color: '#059669',
        ),
        DockItemModel(
          id: 'd2_calendar',
          type: 'docklet_calendar',
          title: 'Календарь',
          iconKey: 'book',
          color: '#E11D48',
        ),
        DockItemModel(id: 'd2_sep', type: 'separator', title: 'Разделитель'),
        DockItemModel(
          id: 'd2_downloads',
          type: 'docklet_stack',
          title: 'Загрузки',
          target: p.join(userProfile, 'Downloads'),
          iconKey: 'folder-emerald',
          color: '#059669',
        ),
        DockItemModel(
          id: 'd2_docs',
          type: 'docklet_stack',
          title: 'Документы',
          target: p.join(userProfile, 'Documents'),
          iconKey: 'folder-blue',
          color: '#2563EB',
        ),
      ];
    }
    if (dockId == 3) {
      // Dock 3 (Top dock): Web & Dev shortcuts
      return [
        DockItemModel(
          id: 'd3_gh',
          type: 'blank',
          title: 'GitHub',
          target: 'https://github.com',
          iconKey: 'code',
          color: '#1E293B',
        ),
        DockItemModel(
          id: 'd3_yt',
          type: 'blank',
          title: 'YouTube',
          target: 'https://www.youtube.com',
          iconKey: 'video',
          color: '#DC2626',
        ),
        DockItemModel(
          id: 'd3_search',
          type: 'blank',
          title: 'Поиск',
          target: 'https://www.google.com',
          iconKey: 'globe',
          color: '#0284C7',
        ),
      ];
    }
    // Dock 1 (Primary bottom RocketDock)
    return [
      DockItemModel(
        id: 'd1_explorer',
        type: 'file',
        title: 'Проводник',
        target: 'explorer.exe',
        iconKey: 'folder-blue',
        color: '#2563EB',
      ),
      DockItemModel(
        id: 'd1_notepad',
        type: 'file',
        title: 'Блокнот',
        target: 'notepad.exe',
        iconKey: 'notes',
        color: '#D97706',
      ),
      DockItemModel(
        id: 'd1_calc',
        type: 'file',
        title: 'Калькулятор',
        target: 'calc.exe',
        iconKey: 'calculator',
        color: '#334155',
      ),
      DockItemModel(
        id: 'd1_cmd',
        type: 'file',
        title: 'Терминал',
        target: 'cmd.exe',
        iconKey: 'terminal',
        color: '#0F172A',
      ),
      DockItemModel(id: 'd1_sep1', type: 'separator', title: 'Разделитель'),
      DockItemModel(
        id: 'd1_desktop',
        type: 'docklet_stack',
        title: 'Рабочий стол',
        target: p.join(userProfile, 'Desktop'),
        iconKey: 'folder-amber',
        color: '#D97706',
      ),
      DockItemModel(
        id: 'd1_clock',
        type: 'docklet_clock',
        title: 'Часы',
        iconKey: 'clock',
        color: '#0F172A',
      ),
      DockItemModel(id: 'd1_sep2', type: 'separator', title: 'Разделитель'),
      DockItemModel(
        id: 'd1_settings',
        type: 'dock_settings',
        title: 'Настройки панели',
        iconKey: 'settings',
        color: '#475569',
      ),
      DockItemModel(
        id: 'd1_recycle',
        type: 'recycle_bin',
        title: 'Корзина',
        target: 'shell:RecycleBinFolder',
        iconKey: 'trash',
        color: '#64748B',
      ),
      DockItemModel(
        id: 'd1_quit',
        type: 'quit',
        title: 'Выход',
        iconKey: 'power',
        color: '#E11D48',
      ),
    ];
  }

  static bool _bool(String? v, bool fallback) {
    if (v == null) return fallback;
    return v == '1' || v.toLowerCase() == 'true';
  }

  static int _int(String? v, int fallback) => int.tryParse(v ?? '') ?? fallback;

  static double _double(String? v, double fallback) =>
      double.tryParse(v ?? '') ?? fallback;

  static List<String> _list(String? v) {
    if (v == null || v.trim().isEmpty) return [];
    return v.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static String? _emptyToNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();

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
