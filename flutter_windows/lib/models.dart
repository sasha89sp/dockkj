import 'dart:convert';
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
        if (raw.startsWith('\uFEFF')) raw = raw.substring(1);
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
        DockItemModel(id: 'dl', type: 'stack', title: 'Загрузки', target: '%USERPROFILE%\\Downloads', color: '#d97706', badge: 'ЗГ'),
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
