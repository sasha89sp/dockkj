import 'dart:async';
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
        id: 'stack-${DateTime.now().millisecondsSinceEpoch}',
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
    final id = 'win-${DateTime.now().millisecondsSinceEpoch}';

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
        entries.add(PopupMenuItem(value: 'open', child: Text('Открыть: ${itm.title}')));
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
            id: 'sep-${DateTime.now().millisecondsSinceEpoch}',
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
