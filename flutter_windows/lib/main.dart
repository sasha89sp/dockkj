import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path/path.dart' as p;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'dialogs.dart';
import 'docklets.dart';
import 'i18n.dart';
import 'ini_storage.dart';
import 'win32_bridge.dart';

extension _SafeIterable<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await acrylic.Window.initialize();

  var dockId = 1;
  for (final arg in args) {
    if (arg.startsWith('--dock=')) {
      dockId = int.tryParse(arg.substring(7))?.clamp(1, 3) ?? 1;
    }
  }

  if (dockId == 1) {
    await hotKeyManager.unregisterAll();
  }

  final store = await PortableIniStore.load();
  AppI18n.loadExternalLanguages(store.languagesDir);
  AppI18n.currentCode = store.global.language;
  store.global.launchWithWindows = Win32Bridge.isStartupEnabled();

  // Clean stale IPC flags on primary startup
  if (dockId == 1) {
    for (final name in ['.aerodock_quit', '.aerodock_hidden']) {
      final f = File(p.join(store.portableDir.path, name));
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  final cfg = store.panels[dockId] ?? DockPanelConfig.defaultFor(dockId);

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
    await windowManager.setAlwaysOnTop(cfg.layer == 'top');
    await acrylic.Window.setEffect(
      effect: cfg.useAcrylic
          ? acrylic.WindowEffect.acrylic
          : acrylic.WindowEffect.transparent,
      color: cfg.useAcrylic ? const Color(0x550F172A) : const Color(0x00000000),
    );
    await windowManager.show();
  });

  runApp(AeroDockApp(store: store, dockId: dockId));
}

class AeroDockApp extends StatelessWidget {
  final PortableIniStore store;
  final int dockId;

  const AeroDockApp({super.key, required this.store, required this.dockId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AeroDock Portable #$dockId',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0EA5E9),
          brightness: Brightness.dark,
        ),
      ),
      home: DockShellPage(store: store, dockId: dockId),
    );
  }
}

class _MinimizedWindowEntry {
  final int hwnd;
  String title;
  final String exePath;
  final String processName;
  String? iconPngPath;
  Uint8List? thumbnailPng;

  _MinimizedWindowEntry({
    required this.hwnd,
    required this.title,
    required this.exePath,
    required this.processName,
    this.iconPngPath,
    this.thumbnailPng,
  });
}

enum _ActiveOverlay { none, settings, iconSettings, stack, calendar }

class DockShellPage extends StatefulWidget {
  final PortableIniStore store;
  final int dockId;

  const DockShellPage({super.key, required this.store, required this.dockId});

  @override
  State<DockShellPage> createState() => _DockShellPageState();
}

class _DockShellPageState extends State<DockShellPage>
    with TrayListener, WindowListener {
  // Sibling dock processes (owned by Dock #1)
  final Map<int, Process> _childDocks = {};

  // Hover / Animation state
  int? _hoveredSlotIndex;
  String? _bouncingKey;
  bool _isDraggingFile = false;
  bool _isAutoHidden = false;
  bool _isPopupRaised = false;
  bool _suspended = false; // Ctrl+Alt+R complete suspend/hide
  int _ownHwnd = 0;

  // Overlay dialogs
  _ActiveOverlay _overlay = _ActiveOverlay.none;
  DockItemModel? _editingItem;
  String _editorDefaultType = 'file';
  DockItemModel? _openStackItem;
  List<FolderEntryInfo> _stackEntries = [];

  // Live system state (polled natively via zero-lag Win32 FFI)
  DateTime _now = DateTime.now();
  BatteryInfo _battery = const BatteryInfo(percent: 100, acOnline: true, charging: false, hasBattery: false);
  SysStatsInfo _sysStats = const SysStatsInfo(cpuPercent: 0, ramPercent: 0, usedGb: 0, totalGb: 0);
  RecycleBinInfo _recycleBin = const RecycleBinInfo(itemCount: 0, sizeBytes: 0);
  List<Display> _displays = [];
  List<ExternalSkinInfo> _externalSkins = [];
  List<ExternalDockletInfo> _externalDocklets = [];

  // Running processes & Minimized Windows in Dock
  Set<String> _runningProcesses = {};
  List<Win32WindowInfo> _openWindows = [];
  final List<_MinimizedWindowEntry> _minimizedWindows = [];
  final Set<int> _onceExcludedHwnds = {};
  final Set<int> _hiddenByDockHwnds = {};

  // Timers
  Timer? _clockTimer;
  Timer? _winPollTimer;
  Timer? _syncTimer;
  Timer? _edgeHoverTimer;
  Timer? _autoHideDelayTimer;
  Timer? _popupDelayTimer;

  // RocketDock global hotkey: Ctrl+Alt+R (completely hide/show + suspend rendering)
  final HotKey _toggleHotKey = HotKey(
    key: PhysicalKeyboardKey.keyR,
    modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );

  int get _dockId => widget.dockId;
  bool get _isPrimary => _dockId == 1;
  DockPanelConfig get _cfg =>
      widget.store.panels[_dockId] ?? DockPanelConfig.defaultFor(_dockId);
  List<DockItemModel> get _items =>
      widget.store.dockItems.putIfAbsent(_dockId, () => PortableIniStore.defaultItemsFor(_dockId));
  bool get _isHorizontal => _cfg.position == 'bottom' || _cfg.position == 'top';

  File get _quitSignalFile => File(p.join(widget.store.portableDir.path, '.aerodock_quit'));
  File get _hiddenSignalFile => File(p.join(widget.store.portableDir.path, '.aerodock_hidden'));

  @override
  void initState() {
    super.initState();
    _isAutoHidden = _cfg.autoHide;
    windowManager.addListener(this);
    if (_isPrimary) {
      trayManager.addListener(this);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _ownHwnd = Win32Bridge.findOwnWindowHandle();
      _externalSkins = widget.store.scanExternalSkins();
      _externalDocklets = widget.store.scanExternalDocklets();
      await _refreshDisplays();
      if (_isPrimary) {
        await _initSystemTray();
        await _registerGlobalHotKey();
        await _reconcileSiblingDocks();
      }
      _extractMissingIcons();
      _applyLayerAndAcrylic();
      await _syncWindowGeometry();
      _pollWindowsAndSystem();
    });

    // 1-second timer for Clock, Battery, SysStats, Recycle Bin
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_suspended || !mounted) return;
      final now = DateTime.now();
      final bat = Win32Bridge.getBatteryStatus();
      final stats = Win32Bridge.getCpuRamStats();
      final bin = Win32Bridge.queryRecycleBin();
      setState(() {
        _now = now;
        _battery = bat;
        _sysStats = stats;
        _recycleBin = bin;
      });
    });

    // 600ms zero-overhead native Win32 EnumWindows poll
    _winPollTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (_suspended || !mounted) return;
      _pollWindowsAndSystem();
    });

    // 400ms IPC + Settings.ini hot-sync across Dock 1 / Dock 2 / Dock 3
    _syncTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      _checkMultiDockSync();
    });

    // 120ms lightweight cursor edge check for AutoHide & Popup on Mouseover
    _edgeHoverTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (_suspended || !mounted) return;
      _checkCursorEdgeHover();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _winPollTimer?.cancel();
    _syncTimer?.cancel();
    _edgeHoverTimer?.cancel();
    _autoHideDelayTimer?.cancel();
    _popupDelayTimer?.cancel();
    windowManager.removeListener(this);
    if (_isPrimary) {
      trayManager.removeListener(this);
      hotKeyManager.unregisterAll();
      _restoreAllHiddenWindows();
      _killAllChildDocks();
    }
    super.dispose();
  }

  // ============================================================================
  // Multi-Dock Orchestration (1, 2, or 3 independent docks)
  // ============================================================================

  Future<void> _reconcileSiblingDocks() async {
    if (!_isPrimary) return;
    final desired = widget.store.global.dockCount.clamp(1, 3);
    final exe = Platform.resolvedExecutable;

    for (var id = 2; id <= 3; id++) {
      final shouldRun = id <= desired;
      final running = _childDocks[id];
      if (shouldRun && running == null) {
        try {
          final proc = await Process.start(
            exe,
            ['--dock=$id'],
            mode: ProcessStartMode.normal,
          );
          _childDocks[id] = proc;
          proc.exitCode.then((_) {
            _childDocks.remove(id);
          });
        } catch (_) {}
      } else if (!shouldRun && running != null) {
        try {
          running.kill();
        } catch (_) {}
        _childDocks.remove(id);
      }
    }
  }

  void _killAllChildDocks() {
    for (final proc in _childDocks.values) {
      try {
        proc.kill();
      } catch (_) {}
    }
    _childDocks.clear();
  }

  Future<void> _checkMultiDockSync() async {
    if (_quitSignalFile.existsSync()) {
      await _exitSingleInstance();
      return;
    }

    // Sync Ctrl+Alt+R suspend/hide across all panels
    final shouldSuspend = _hiddenSignalFile.existsSync();
    if (shouldSuspend != _suspended) {
      _suspended = shouldSuspend;
      if (_suspended) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        _applyLayerAndAcrylic();
        await _syncWindowGeometry();
      }
      if (mounted) setState(() {});
    }

    if (await widget.store.hasExternalChanges()) {
      await widget.store.reloadFromDisk();
      AppI18n.currentCode = widget.store.global.language;
      _externalSkins = widget.store.scanExternalSkins();
      _externalDocklets = widget.store.scanExternalDocklets();
      if (_isPrimary) {
        await _reconcileSiblingDocks();
      }
      if (_dockId > widget.store.global.dockCount && !_isPrimary) {
        await _exitSingleInstance();
        return;
      }
      _applyLayerAndAcrylic();
      await _syncWindowGeometry();
      if (mounted) setState(() {});
    }
  }

  Future<void> _quitAllDocks() async {
    try {
      await _quitSignalFile.writeAsString('quit', flush: true);
    } catch (_) {}
    _restoreAllHiddenWindows();
    _killAllChildDocks();
    await _exitSingleInstance();
  }

  Future<void> _exitSingleInstance() async {
    if (_isPrimary) {
      _restoreAllHiddenWindows();
      await hotKeyManager.unregisterAll();
      await trayManager.destroy();
    }
    await windowManager.destroy();
    exit(0);
  }

  // ============================================================================
  // System Tray & Global Hotkey (Ctrl+Alt+R)
  // ============================================================================

  Future<void> _initSystemTray() async {
    try {
      await trayManager.setIcon('assets/app_icon.ico');
      await trayManager.setToolTip('AeroDock Portable (${widget.store.global.dockCount} пана.) · Ctrl+Alt+R');
      await _rebuildTrayMenu();
    } catch (_) {}
  }

  Future<void> _rebuildTrayMenu() async {
    try {
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'toggle', label: AppI18n.t('show_hide_hotkey')),
            MenuItem(key: 'settings', label: '${AppI18n.t('dock_settings')}…'),
            MenuItem.separator(),
            MenuItem(key: 'docks_1', label: '1 панель${widget.store.global.dockCount == 1 ? ' ✓' : ''}'),
            MenuItem(key: 'docks_2', label: '2 панели${widget.store.global.dockCount == 2 ? ' ✓' : ''}'),
            MenuItem(key: 'docks_3', label: '3 панели${widget.store.global.dockCount == 3 ? ' ✓' : ''}'),
            MenuItem.separator(),
            MenuItem(key: 'open_dir', label: 'Открыть папку AeroDock'),
            MenuItem(key: 'quit', label: AppI18n.t('quit')),
          ],
        ),
      );
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() => _toggleGlobalSuspend();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'toggle':
        await _toggleGlobalSuspend();
        break;
      case 'settings':
        if (_suspended) await _toggleGlobalSuspend();
        await _openOverlay(_ActiveOverlay.settings);
        break;
      case 'docks_1':
      case 'docks_2':
      case 'docks_3':
        final count = int.parse(menuItem.key!.split('_').last);
        widget.store.global.dockCount = count;
        await widget.store.save();
        await _reconcileSiblingDocks();
        await _rebuildTrayMenu();
        break;
      case 'open_dir':
        Win32Bridge.shellExecute(target: widget.store.portableDir.path);
        break;
      case 'quit':
        await _quitAllDocks();
        break;
    }
  }

  Future<void> _registerGlobalHotKey() async {
    try {
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        _toggleHotKey,
        keyDownHandler: (_) => _toggleGlobalSuspend(),
      );
    } catch (_) {}
  }

  /// Ctrl+Alt+R: completely hide/show ALL dock panels & pause rendering/polling.
  Future<void> _toggleGlobalSuspend() async {
    final nextSuspended = !_suspended;
    if (nextSuspended) {
      try {
        await _hiddenSignalFile.writeAsString('1', flush: true);
      } catch (_) {}
    } else {
      try {
        if (_hiddenSignalFile.existsSync()) _hiddenSignalFile.deleteSync();
      } catch (_) {}
    }
    _suspended = nextSuspended;
    if (_suspended) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      _applyLayerAndAcrylic();
      await _syncWindowGeometry();
    }
    if (mounted) setState(() {});
  }

  // ============================================================================
  // Native Win32 Running Apps + Minimize Windows to Dock + Live Aero Previews
  // ============================================================================

  void _pollWindowsAndSystem() {
    final windows = Win32Bridge.enumerateWindows(includeHiddenHwnds: _hiddenByDockHwnds);
    _openWindows = windows;

    final running = <String>{};
    for (final w in windows) {
      if (w.processName.isNotEmpty) running.add(w.processName);
    }

    var minListChanged = false;

    // Only Dock #1 captures minimized windows into the dock
    if (_isPrimary) {
      // Remove dead or restored windows from minimized tray
      for (var i = _minimizedWindows.length - 1; i >= 0; i--) {
        final entry = _minimizedWindows[i];
        if (!Win32Bridge.isWindowAlive(entry.hwnd)) {
          _hiddenByDockHwnds.remove(entry.hwnd);
          _minimizedWindows.removeAt(i);
          minListChanged = true;
          continue;
        }
        final live = windows.where((w) => w.hwnd == entry.hwnd).firstOrNull;
        if (live != null && live.isVisible && !live.isMinimized) {
          _hiddenByDockHwnds.remove(entry.hwnd);
          _minimizedWindows.removeAt(i);
          minListChanged = true;
        } else if (live != null) {
          entry.title = live.title;
        }
      }

      if (widget.store.global.minimizeToDock) {
        final ctrlAltShift = Win32Bridge.isCtrlAltShiftPressed();
        final ctrlOnly = Win32Bridge.isCtrlPressed() && !ctrlAltShift;

        for (final w in windows) {
          if (!w.isMinimized) {
            _onceExcludedHwnds.remove(w.hwnd);
            continue;
          }
          if (_hiddenByDockHwnds.contains(w.hwnd)) continue;
          if (_onceExcludedHwnds.contains(w.hwnd)) continue;
          if (widget.store.global.excludedWindows.contains(w.processName)) continue;

          // RocketDock exclusion shortcuts while minimizing!
          if (ctrlAltShift && w.processName.isNotEmpty) {
            widget.store.global.excludedWindows.add(w.processName);
            widget.store.save();
            continue;
          }
          if (ctrlOnly) {
            _onceExcludedHwnds.add(w.hwnd);
            continue;
          }

          // Capture live thumbnail before hiding from taskbar
          final thumb = Win32Bridge.captureWindowThumbnailPng(w.hwnd);
          final ico = w.exePath.isNotEmpty
              ? Win32Bridge.extractIconToPng(w.exePath, widget.store.iconsCacheDir)
              : null;

          Win32Bridge.hideWindowFromTaskbar(w.hwnd);
          _hiddenByDockHwnds.add(w.hwnd);
          _minimizedWindows.add(
            _MinimizedWindowEntry(
              hwnd: w.hwnd,
              title: w.title,
              exePath: w.exePath,
              processName: w.processName,
              iconPngPath: ico,
              thumbnailPng: thumb,
            ),
          );
          minListChanged = true;
        }
      } else if (_minimizedWindows.isNotEmpty) {
        _restoreAllHiddenWindows();
        minListChanged = true;
      }
    }

    if (mounted &&
        (minListChanged ||
            running.length != _runningProcesses.length ||
            !running.containsAll(_runningProcesses))) {
      setState(() {
        _runningProcesses = running;
      });
      if (minListChanged) {
        _syncWindowGeometry();
      }
    }
  }

  void _restoreAllHiddenWindows() {
    for (final entry in List<_MinimizedWindowEntry>.from(_minimizedWindows)) {
      if (Win32Bridge.isWindowAlive(entry.hwnd)) {
        Win32Bridge.restoreAndFocusWindow(entry.hwnd);
      }
    }
    _minimizedWindows.clear();
    _hiddenByDockHwnds.clear();
  }

  void _restoreMinimizedEntry(_MinimizedWindowEntry entry) {
    _hiddenByDockHwnds.remove(entry.hwnd);
    _minimizedWindows.removeWhere((e) => e.hwnd == entry.hwnd);
    Win32Bridge.restoreAndFocusWindow(entry.hwnd);
    setState(() {});
    _syncWindowGeometry();
  }

  void _closeMinimizedEntry(_MinimizedWindowEntry entry) {
    _hiddenByDockHwnds.remove(entry.hwnd);
    _minimizedWindows.removeWhere((e) => e.hwnd == entry.hwnd);
    Win32Bridge.closeWindow(entry.hwnd);
    setState(() {});
    _syncWindowGeometry();
  }

  // ============================================================================
  // Monitors (including "Monitor *" virtual screen), Layering & Window Geometry
  // ============================================================================

  Future<void> _refreshDisplays() async {
    try {
      _displays = await screenRetriever.getAllDisplays();
    } catch (_) {}
  }

  Future<Rect> _getTargetScreenRect() async {
    if (_cfg.monitorIndex == -1) {
      // RocketDock "Monitor *" (all monitors as one virtual desktop)
      final v = Win32Bridge.getVirtualScreenRect();
      return Rect.fromLTWH(v.left, v.top, v.width, v.height);
    }
    if (_displays.isEmpty) await _refreshDisplays();
    if (_displays.isNotEmpty) {
      final idx = _cfg.monitorIndex.clamp(0, _displays.length - 1);
      final d = _displays[idx];
      final pos = d.visiblePosition ?? Offset.zero;
      return Rect.fromLTWH(pos.dx, pos.dy, d.size.width, d.size.height);
    }
    final primary = await screenRetriever.getPrimaryDisplay();
    return Rect.fromLTWH(0, 0, primary.size.width, primary.size.height);
  }

  void _applyLayerAndAcrylic() {
    if (_ownHwnd == 0) _ownHwnd = Win32Bridge.findOwnWindowHandle();
    final effectiveLayer = _isPopupRaised ? 'top' : _cfg.layer;
    windowManager.setAlwaysOnTop(effectiveLayer == 'top');
    Win32Bridge.setWindowLayer(_ownHwnd, effectiveLayer);
    acrylic.Window.setEffect(
      effect: _cfg.useAcrylic
          ? acrylic.WindowEffect.acrylic
          : acrylic.WindowEffect.transparent,
      color: _cfg.useAcrylic ? const Color(0x550F172A) : const Color(0x00000000),
    );
  }

  Future<void> _syncWindowGeometry() async {
    if (_suspended) return;
    final screen = await _getTargetScreenRect();

    // If an overlay dialog/popover is open, expand & center cleanly on screen
    if (_overlay != _ActiveOverlay.none) {
      final w = switch (_overlay) {
        _ActiveOverlay.settings => 760.0,
        _ActiveOverlay.iconSettings => 760.0,
        _ActiveOverlay.stack => 560.0,
        _ActiveOverlay.calendar => 340.0,
        _ => 760.0,
      };
      final h = switch (_overlay) {
        _ActiveOverlay.settings => 560.0,
        _ActiveOverlay.iconSettings => 560.0,
        _ActiveOverlay.stack => 410.0,
        _ActiveOverlay.calendar => 340.0,
        _ => 560.0,
      };
      final left = screen.left + (screen.width - w) / 2;
      final top = screen.top + (screen.height - h) / 2;
      await windowManager.setSize(Size(w, h));
      await windowManager.setPosition(Offset(left, top));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
      return;
    }

    final totalSlots = _items.length + (_isPrimary ? _minimizedWindows.length : 0);
    final baseIcon = _cfg.iconSize;
    final maxIcon = baseIcon * (_cfg.hoverEffect == 'none' ? 1.0 : _cfg.zoomScale);
    final mainLen = math.max(
      240.0,
      totalSlots * (baseIcon + 14) + maxIcon * 1.6 + 64,
    );
    // Reserve headroom for zoomed icons + labels + minimized window Aero preview card
    final hasMinimized = _isPrimary && _minimizedWindows.isNotEmpty;
    final crossLen = math.max(
      maxIcon + (_cfg.showLabels ? 52 : 24) + (hasMinimized ? 130 : 0),
      138.0,
    );

    final bool collapsed = _cfg.autoHide && _isAutoHidden;
    final double winW;
    final double winH;
    if (_isHorizontal) {
      winW = math.min(screen.width - 16, mainLen);
      winH = collapsed ? 10.0 : math.min(screen.height - 24, crossLen);
    } else {
      winW = collapsed ? 10.0 : math.min(screen.width - 24, crossLen + 110);
      winH = math.min(screen.height - 16, mainLen);
    }

    final centerShiftX = (screen.width * (_cfg.centerOffset / 100));
    final centerShiftY = (screen.height * (_cfg.centerOffset / 100));
    final edge = collapsed ? 0.0 : _cfg.edgeOffset;

    double x;
    double y;
    switch (_cfg.position) {
      case 'top':
        x = screen.left + (screen.width - winW) / 2 + centerShiftX;
        y = screen.top + edge;
        break;
      case 'left':
        x = screen.left + edge;
        y = screen.top + (screen.height - winH) / 2 + centerShiftY;
        break;
      case 'right':
        x = screen.right - winW - edge;
        y = screen.top + (screen.height - winH) / 2 + centerShiftY;
        break;
      case 'bottom':
      default:
        x = screen.left + (screen.width - winW) / 2 + centerShiftX;
        y = screen.bottom - winH - edge;
        break;
    }

    x = x.clamp(screen.left, math.max(screen.left, screen.right - winW));
    y = y.clamp(screen.top, math.max(screen.top, screen.bottom - winH));

    await windowManager.setSize(Size(winW, winH));
    await windowManager.setPosition(Offset(x, y));
    _applyLayerAndAcrylic();
  }

  /// AutoHide wake-up + Popup on Mouseover edge trigger via low-latency GetCursorPos.
  Future<void> _checkCursorEdgeHover() async {
    if (_overlay != _ActiveOverlay.none) return;
    if (!_cfg.autoHide && (!_cfg.popupOnMouseover || _cfg.layer == 'top')) return;

    final cursor = Win32Bridge.getCursorPos();
    final screen = await _getTargetScreenRect();
    const hotZone = 6.0;

    final atEdge = switch (_cfg.position) {
      'top' => cursor.y <= screen.top + hotZone &&
          cursor.x >= screen.left &&
          cursor.x <= screen.right,
      'left' => cursor.x <= screen.left + hotZone &&
          cursor.y >= screen.top &&
          cursor.y <= screen.bottom,
      'right' => cursor.x >= screen.right - hotZone &&
          cursor.y >= screen.top &&
          cursor.y <= screen.bottom,
      _ => cursor.y >= screen.bottom - hotZone &&
          cursor.x >= screen.left &&
          cursor.x <= screen.right,
    };

    if (atEdge) {
      if (_cfg.autoHide && _isAutoHidden) {
        _autoHideDelayTimer?.cancel();
        setState(() => _isAutoHidden = false);
        await _syncWindowGeometry();
      }
      if (_cfg.popupOnMouseover && _cfg.layer != 'top' && !_isPopupRaised) {
        _popupDelayTimer ??= Timer(Duration(milliseconds: _cfg.popupDelayMs), () {
          _popupDelayTimer = null;
          if (!mounted) return;
          setState(() => _isPopupRaised = true);
          _applyLayerAndAcrylic();
        });
      }
    } else {
      _popupDelayTimer?.cancel();
      _popupDelayTimer = null;
    }
  }

  void _extractMissingIcons() {
    var changed = false;
    for (final item in _items) {
      if ((item.type == 'file' || item.type == 'path' || item.type == 'blank') &&
          item.target.isNotEmpty &&
          (item.iconPath == null || !File(item.iconPath!).existsSync())) {
        final png = Win32Bridge.extractIconToPng(item.target, widget.store.iconsCacheDir);
        if (png != null) {
          item.iconPath = png;
          changed = true;
        }
      }
    }
    if (changed && mounted) {
      setState(() {});
      widget.store.save();
    }
  }

  // ============================================================================
  // Item Activation (Open Running, Run Mode, Start In, Args, Docklets, Actions)
  // ============================================================================

  void _triggerClickEffect(String key) {
    if (_cfg.clickEffect == 'none') return;
    setState(() => _bouncingKey = key);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _bouncingKey == key) {
        setState(() => _bouncingKey = null);
      }
    });
  }

  Future<void> _activateItem(DockItemModel item) async {
    _triggerClickEffect(item.id);

    switch (item.type) {
      case 'separator':
        return;
      case 'dock_settings':
        await _openOverlay(_ActiveOverlay.settings);
        return;
      case 'quit':
        await _quitAllDocks();
        return;
      case 'recycle_bin':
        Win32Bridge.shellExecute(target: 'shell:RecycleBinFolder');
        return;
      case 'docklet_clock':
        Win32Bridge.shellExecute(target: 'timedate.cpl');
        return;
      case 'docklet_battery':
        Win32Bridge.shellExecute(target: 'powercfg.cpl');
        return;
      case 'docklet_sysstats':
        Win32Bridge.shellExecute(target: 'taskmgr.exe');
        return;
      case 'docklet_calendar':
        await _openOverlay(_ActiveOverlay.calendar);
        return;
      case 'docklet_stack':
        if (item.target.isNotEmpty && Directory(item.target).existsSync()) {
          _openStackItem = item;
          _stackEntries = await Win32Bridge.listDirectoryContents(
            item.target,
            iconsCacheDir: widget.store.iconsCacheDir,
          );
          await _openOverlay(_ActiveOverlay.stack);
        } else {
          Win32Bridge.shellExecute(target: item.target);
        }
        return;
      default:
        break;
    }

    if (item.target.isEmpty) {
      _editingItem = item;
      await _openOverlay(_ActiveOverlay.iconSettings);
      return;
    }

    // URL target
    if (item.target.startsWith('http://') || item.target.startsWith('https://')) {
      final uri = Uri.tryParse(item.target);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // RocketDock "Open Running" (Global / Always / Never)
    final shouldOpenRunning = item.openRunning == 'always' ||
        (item.openRunning == 'global' && widget.store.global.openRunningInstance);

    if (shouldOpenRunning) {
      final exeName = item.executableName;
      if (exeName != null) {
        // First check minimized-in-dock windows
        final minMatch = _minimizedWindows
            .where((m) => m.processName == exeName)
            .firstOrNull;
        if (minMatch != null) {
          _restoreMinimizedEntry(minMatch);
          return;
        }
        // Then check open visible windows
        final openMatch = _openWindows
            .where((w) => w.processName == exeName)
            .firstOrNull;
        if (openMatch != null) {
          Win32Bridge.restoreAndFocusWindow(openMatch.hwnd);
          return;
        }
      }
    }

    Win32Bridge.shellExecute(
      target: item.target,
      args: item.args,
      startIn: item.startIn,
      runMode: item.runMode,
    );
  }

  // ============================================================================
  // Drag-n-Drop from Windows (Add to Dock OR Drop ONTO App / Folder / Recycle Bin)
  // ============================================================================

  Future<void> _handleExternalDrop(DropDoneDetails details) async {
    setState(() => _isDraggingFile = false);
    final paths = details.files.map((f) => f.path).where((s) => s.isNotEmpty).toList();
    if (paths.isEmpty) return;

    // Check if files were dropped directly onto an existing dock icon!
    if (_hoveredSlotIndex != null &&
        _hoveredSlotIndex! >= 0 &&
        _hoveredSlotIndex! < _items.length) {
      final targetItem = _items[_hoveredSlotIndex!];
      if (targetItem.type == 'recycle_bin') {
        Win32Bridge.sendFilesToRecycleBin(paths);
        _triggerClickEffect(targetItem.id);
        setState(() => _recycleBin = Win32Bridge.queryRecycleBin());
        return;
      }
      if ((targetItem.type == 'path' || targetItem.type == 'docklet_stack') &&
          targetItem.target.isNotEmpty &&
          Directory(targetItem.target).existsSync()) {
        await Win32Bridge.copyFilesToFolder(paths, targetItem.target);
        _triggerClickEffect(targetItem.id);
        return;
      }
      if (targetItem.type == 'file' && targetItem.target.isNotEmpty) {
        final quoted = paths.map((e) => '"$e"').join(' ');
        final fullArgs =
            targetItem.args.isEmpty ? quoted : '${targetItem.args} $quoted';
        Win32Bridge.shellExecute(
          target: targetItem.target,
          args: fullArgs,
          startIn: targetItem.startIn,
          runMode: targetItem.runMode,
        );
        _triggerClickEffect(targetItem.id);
        return;
      }
    }

    // Otherwise add dropped files/folders as new dock shortcuts
    for (final filePath in paths) {
      final isDir = FileSystemEntity.isDirectorySync(filePath);
      final name = isDir
          ? p.basename(filePath)
          : p.basenameWithoutExtension(filePath);
      final png = Win32Bridge.extractIconToPng(filePath, widget.store.iconsCacheDir);
      _items.add(
        DockItemModel(
          id: 'drop_${DateTime.now().microsecondsSinceEpoch}',
          type: isDir ? 'path' : 'file',
          title: name.isEmpty ? filePath : name,
          target: filePath,
          startIn: isDir ? filePath : p.dirname(filePath),
          iconKey: isDir ? 'folder-blue' : 'rocket',
          color: isDir ? '#2563EB' : '#0284C7',
          iconPath: png,
        ),
      );
    }

    await widget.store.save();
    setState(() {});
    await _syncWindowGeometry();
  }

  // ============================================================================
  // Overlay Open / Close
  // ============================================================================

  Future<void> _openOverlay(_ActiveOverlay next) async {
    setState(() {
      _overlay = next;
      _isAutoHidden = false;
    });
    await _syncWindowGeometry();
  }

  Future<void> _closeOverlay() async {
    setState(() {
      _overlay = _ActiveOverlay.none;
      _editingItem = null;
      _openStackItem = null;
    });
    await _syncWindowGeometry();
  }

  // ============================================================================
  // RocketDock Right-Click Context Menus (Dock & Item & Minimized Window)
  // ============================================================================

  Future<void> _showDockContextMenu(
    Offset globalPos, {
    DockItemModel? item,
    _MinimizedWindowEntry? minWin,
  }) async {
    final entries = <PopupMenuEntry<String>>[];

    // 1. Minimized Window specific actions
    if (minWin != null) {
      entries.addAll([
        PopupMenuItem(value: 'win_open', child: Text(AppI18n.t('open_window'))),
        PopupMenuItem(
          value: 'win_close',
          child: Text(AppI18n.t('close_window'), style: const TextStyle(color: Color(0xFFFB7185))),
        ),
        const PopupMenuDivider(),
      ]);
    }

    // 2. Item specific actions
    if (item != null) {
      if (item.type != 'separator') {
        entries.add(PopupMenuItem(value: 'item_edit', child: Text('${AppI18n.t('icon_settings')}…')));
      }
      if (item.type == 'recycle_bin' && item.popupMenu) {
        entries.add(
          PopupMenuItem(
            value: 'empty_bin',
            child: Text('${AppI18n.t('empty_recycle_bin')} (${_recycleBin.itemCount})'),
          ),
        );
      }
      entries.add(
        PopupMenuItem(
          value: 'item_delete',
          child: Text(AppI18n.t('delete_item'), style: const TextStyle(color: Color(0xFFFB7185))),
        ),
      );
      entries.add(const PopupMenuDivider());
    }

    // 3. RocketDock "Add Item" actions
    entries.addAll([
      PopupMenuItem(value: 'add_file', child: Text('＋ ${AppI18n.t('add_file')}')),
      PopupMenuItem(value: 'add_path', child: Text('＋ ${AppI18n.t('add_path')}')),
      PopupMenuItem(value: 'add_blank', child: Text('＋ ${AppI18n.t('add_blank')}')),
      PopupMenuItem(value: 'add_separator', child: Text('＋ ${AppI18n.t('add_separator')}')),
      PopupMenuItem(value: 'add_recycle', child: Text('＋ ${AppI18n.t('add_recycle_bin')}')),
      PopupMenuItem(value: 'add_settings_ico', child: Text('＋ ${AppI18n.t('add_dock_settings')}')),
      PopupMenuItem(value: 'add_quit_ico', child: Text('＋ ${AppI18n.t('add_quit')}')),
      const PopupMenuDivider(),
      PopupMenuItem(value: 'add_dk_clock', child: Text('🧩 ${AppI18n.t('docklet_clock')}')),
      PopupMenuItem(value: 'add_dk_battery', child: Text('🧩 ${AppI18n.t('docklet_battery')}')),
      PopupMenuItem(value: 'add_dk_sysstats', child: Text('🧩 ${AppI18n.t('docklet_sysstats')}')),
      PopupMenuItem(value: 'add_dk_calendar', child: Text('🧩 ${AppI18n.t('docklet_calendar')}')),
      PopupMenuItem(value: 'add_dk_stack', child: Text('🧩 ${AppI18n.t('docklet_stack')}')),
      for (final ext in _externalDocklets)
        PopupMenuItem(value: 'add_dk_ext:${ext.id}', child: Text('🧩 ${ext.name} (Docklets/)')),
      const PopupMenuDivider(),
      PopupMenuItem(value: 'pos_bottom', child: Text('${AppI18n.t('pos_bottom')}${_cfg.position == 'bottom' ? ' ✓' : ''}')),
      PopupMenuItem(value: 'pos_top', child: Text('${AppI18n.t('pos_top')}${_cfg.position == 'top' ? ' ✓' : ''}')),
      PopupMenuItem(value: 'pos_left', child: Text('${AppI18n.t('pos_left')}${_cfg.position == 'left' ? ' ✓' : ''}')),
      PopupMenuItem(value: 'pos_right', child: Text('${AppI18n.t('pos_right')}${_cfg.position == 'right' ? ' ✓' : ''}')),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'toggle_lock',
        child: Text('${AppI18n.t('lock_items')}${widget.store.global.lockItems ? ' ✓' : ''}'),
      ),
      PopupMenuItem(
        value: 'toggle_autohide',
        child: Text('${AppI18n.t('auto_hide')}${_cfg.autoHide ? ' ✓' : ''}'),
      ),
      PopupMenuItem(value: 'docks_cycle', child: Text('${AppI18n.t('multi_dock')}: ${widget.store.global.dockCount} → ${(widget.store.global.dockCount % 3) + 1}')),
      const PopupMenuDivider(),
      PopupMenuItem(value: 'open_settings', child: Text('⚙ ${AppI18n.t('dock_settings')}…')),
      PopupMenuItem(value: 'quit', child: Text('⏻ ${AppI18n.t('quit')}')),
    ]);

    final choice = await showMenu<String>(
      context: context,
      color: const Color(0xF50F172A),
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      items: entries,
    );
    if (choice == null) return;

    switch (choice) {
      case 'win_open':
        if (minWin != null) _restoreMinimizedEntry(minWin);
        break;
      case 'win_close':
        if (minWin != null) _closeMinimizedEntry(minWin);
        break;
      case 'item_edit':
        if (item != null) {
          _editingItem = item;
          await _openOverlay(_ActiveOverlay.iconSettings);
        }
        break;
      case 'empty_bin':
        Win32Bridge.emptyRecycleBin(silent: false);
        setState(() => _recycleBin = Win32Bridge.queryRecycleBin());
        break;
      case 'item_delete':
        if (item != null) {
          _items.removeWhere((e) => e.id == item.id);
          await widget.store.save();
          setState(() {});
          await _syncWindowGeometry();
        }
        break;
      case 'add_file':
        final res = await FilePicker.platform.pickFiles();
        if (res != null && res.files.single.path != null) {
          final path = res.files.single.path!;
          final png = Win32Bridge.extractIconToPng(path, widget.store.iconsCacheDir);
          _items.add(DockItemModel(
            id: 'file_${DateTime.now().millisecondsSinceEpoch}',
            type: 'file',
            title: p.basenameWithoutExtension(path),
            target: path,
            startIn: p.dirname(path),
            iconPath: png,
          ));
          await widget.store.save();
          setState(() {});
          await _syncWindowGeometry();
        }
        break;
      case 'add_path':
        final dir = await FilePicker.platform.getDirectoryPath();
        if (dir != null) {
          _items.add(DockItemModel(
            id: 'path_${DateTime.now().millisecondsSinceEpoch}',
            type: 'path',
            title: p.basename(dir),
            target: dir,
            iconKey: 'folder-blue',
            color: '#2563EB',
          ));
          await widget.store.save();
          setState(() {});
          await _syncWindowGeometry();
        }
        break;
      case 'add_blank':
        _editingItem = null;
        _editorDefaultType = 'blank';
        await _openOverlay(_ActiveOverlay.iconSettings);
        break;
      case 'add_separator':
        _items.add(DockItemModel(
          id: 'sep_${DateTime.now().millisecondsSinceEpoch}',
          type: 'separator',
          title: 'Разделитель',
        ));
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_recycle':
        _items.add(DockItemModel(
          id: 'bin_${DateTime.now().millisecondsSinceEpoch}',
          type: 'recycle_bin',
          title: 'Корзина',
          target: 'shell:RecycleBinFolder',
          iconKey: 'trash',
        ));
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_settings_ico':
        _items.add(DockItemModel(
          id: 'cfg_${DateTime.now().millisecondsSinceEpoch}',
          type: 'dock_settings',
          title: AppI18n.t('dock_settings'),
          iconKey: 'settings',
          color: '#475569',
        ));
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_quit_ico':
        _items.add(DockItemModel(
          id: 'quit_${DateTime.now().millisecondsSinceEpoch}',
          type: 'quit',
          title: 'Выход',
          iconKey: 'power',
          color: '#E11D48',
        ));
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_dk_clock':
        _items.add(DockItemModel(
          id: 'dk_clk_${DateTime.now().millisecondsSinceEpoch}',
          type: 'docklet_clock',
          title: 'Часы',
          iconKey: 'clock',
        ));
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_dk_battery':
        _items.add(DockItemModel(
          id: 'dk_bat_${DateTime.now().millisecondsSinceEpoch}',
          type: 'docklet_battery',
          title: 'Батарея',
          iconKey: 'star',
        ));
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_dk_sysstats':
        _items.add(DockItemModel(
          id: 'dk_sys_${DateTime.now().millisecondsSinceEpoch}',
          type: 'docklet_sysstats',
          title: 'CPU / RAM',
          iconKey: 'terminal',
        ));
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_dk_calendar':
        _items.add(DockItemModel(
          id: 'dk_cal_${DateTime.now().millisecondsSinceEpoch}',
          type: 'docklet_calendar',
          title: 'Календарь',
          iconKey: 'book',
        ));
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_dk_stack':
        final dir = await FilePicker.platform.getDirectoryPath();
        if (dir != null) {
          _items.add(DockItemModel(
            id: 'dk_stk_${DateTime.now().millisecondsSinceEpoch}',
            type: 'docklet_stack',
            title: p.basename(dir),
            target: dir,
            iconKey: 'folder-emerald',
            color: '#059669',
          ));
          await widget.store.save();
          setState(() {});
          await _syncWindowGeometry();
        }
        break;
      case 'pos_bottom':
      case 'pos_top':
      case 'pos_left':
      case 'pos_right':
        _cfg.position = choice.substring(4);
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'toggle_lock':
        widget.store.global.lockItems = !widget.store.global.lockItems;
        await widget.store.save();
        setState(() {});
        break;
      case 'toggle_autohide':
        _cfg.autoHide = !_cfg.autoHide;
        _isAutoHidden = false;
        await widget.store.save();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'docks_cycle':
        widget.store.global.dockCount = (widget.store.global.dockCount % 3) + 1;
        await widget.store.save();
        if (_isPrimary) {
          await _reconcileSiblingDocks();
          await _rebuildTrayMenu();
        }
        setState(() {});
        break;
      case 'open_settings':
        await _openOverlay(_ActiveOverlay.settings);
        break;
      case 'quit':
        await _quitAllDocks();
        break;
      default:
        if (choice.startsWith('add_dk_ext:')) {
          final id = choice.substring(11);
          final ext = _externalDocklets.where((e) => e.id == id).firstOrNull;
          if (ext != null) {
            _items.add(DockItemModel(
              id: 'dk_ext_${DateTime.now().millisecondsSinceEpoch}',
              type: 'docklet_external',
              title: ext.name,
              target: ext.targetCommand ?? ext.folderPath,
              iconPath: ext.iconPath,
              iconKey: 'rocket',
            ));
            await widget.store.save();
            setState(() {});
            await _syncWindowGeometry();
          }
        }
        break;
    }
  }

  // ============================================================================
  // Zoom Wave Math & Theme / Skin Decoration
  // ============================================================================

  double _scaleForSlot(int index) {
    if (_cfg.hoverEffect == 'none' || _hoveredSlotIndex == null) return 1.0;
    final dist = (index - _hoveredSlotIndex!).abs().toDouble();
    final span = math.max(1.0, _cfg.zoomWidth);
    if (dist > span) return 1.0;
    final wave = (math.cos((dist / span) * math.pi) + 1) / 2;
    return 1.0 + (_cfg.zoomScale - 1.0) * wave;
  }

  BoxDecoration _resolveDockSurface() {
    final alpha = (_cfg.bgOpacity / 100.0).clamp(0.0, 1.0);
    if (_cfg.theme.startsWith('skin:')) {
      final skin = _externalSkins.where((s) => s.id == _cfg.theme).firstOrNull;
      if (skin != null && File(skin.imagePath).existsSync()) {
        return BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          image: DecorationImage(
            image: FileImage(File(skin.imagePath)),
            fit: BoxFit.fill,
            opacity: alpha,
          ),
        );
      }
    }

    switch (_cfg.theme) {
      case 'crystal':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.24 * alpha),
              const Color(0xFF0F172A).withValues(alpha: 0.64 * alpha),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.34 * alpha)),
        );
      case 'graphite':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF0F172A).withValues(alpha: 0.92 * alpha),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16 * alpha)),
        );
      case 'silk':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFFF8FAFC).withValues(alpha: 0.80 * alpha),
          border: Border.all(color: Colors.white.withValues(alpha: 0.88 * alpha)),
        );
      case 'minimal':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF0F172A).withValues(alpha: 0.44 * alpha),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14 * alpha)),
        );
      case 'retro':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF94A3B8).withValues(alpha: alpha),
              const Color(0xFF475569).withValues(alpha: alpha),
              const Color(0xFF1E293B).withValues(alpha: alpha),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.44 * alpha)),
        );
      case 'aero3d':
      default:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFE2E8F0).withValues(alpha: 0.30 * alpha),
              const Color(0xFF1E293B).withValues(alpha: 0.64 * alpha),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.40 * alpha)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42 * alpha),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        );
    }
  }

  Widget _buildStyledLabel(String text) {
    final textColor = parseHexColor(_cfg.labelColor, Colors.white);
    final shadowColor = parseHexColor(_cfg.labelShadowColor, Colors.black)
        .withValues(alpha: (_cfg.labelShadowOpacity / 100).clamp(0.0, 1.0));
    final outlineColor = parseHexColor(_cfg.labelOutlineColor, const Color(0xFF0F172A))
        .withValues(alpha: (_cfg.labelOutlineOpacity / 100).clamp(0.0, 1.0));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: outlineColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(color: shadowColor, blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: _cfg.labelFontFamily,
          fontSize: _cfg.labelFontSize,
          fontWeight: _cfg.labelBold ? FontWeight.w700 : FontWeight.w500,
          fontStyle: _cfg.labelItalic ? FontStyle.italic : FontStyle.normal,
          color: textColor,
          shadows: [
            Shadow(color: shadowColor, blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // Main Build
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    if (_suspended) return const SizedBox.shrink();

    // 1. Built-in RocketDock Overlays (Settings, Icon Settings, Live Stack, Calendar)
    if (_overlay != _ActiveOverlay.none) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: switch (_overlay) {
            _ActiveOverlay.settings => DockSettingsDialog(
                store: widget.store,
                activeDockId: _dockId,
                displays: _displays,
                onSaved: () async {
                  _externalSkins = widget.store.scanExternalSkins();
                  if (_isPrimary) {
                    await _reconcileSiblingDocks();
                    await _rebuildTrayMenu();
                  }
                  _applyLayerAndAcrylic();
                  if (mounted) setState(() {});
                },
                onResetDefaults: () async {
                  await widget.store.resetSettingsToDefaultsOnly();
                  _applyLayerAndAcrylic();
                  if (mounted) setState(() {});
                },
                onFullReset: () async {
                  await widget.store.fullReset();
                  if (_isPrimary) await _reconcileSiblingDocks();
                  _applyLayerAndAcrylic();
                  if (mounted) setState(() {});
                },
                onClose: _closeOverlay,
              ),
            _ActiveOverlay.iconSettings => IconSettingsDialog(
                store: widget.store,
                initialItem: _editingItem,
                defaultType: _editorDefaultType,
                onSave: (saved) async {
                  final idx = _items.indexWhere((e) => e.id == saved.id);
                  if (idx >= 0) {
                    _items[idx] = saved;
                  } else {
                    _items.add(saved);
                  }
                  await widget.store.save();
                  await _closeOverlay();
                },
                onClose: _closeOverlay,
              ),
            _ActiveOverlay.stack => LiveStackPopover(
                title: _openStackItem?.title ?? 'Папка',
                folderPath: _openStackItem?.target ?? '',
                entries: _stackEntries,
                onOpenEntry: (entry) {
                  Win32Bridge.shellExecute(target: entry.path);
                  _closeOverlay();
                },
                onOpenFolderInExplorer: () {
                  if (_openStackItem != null) {
                    Win32Bridge.shellExecute(target: _openStackItem!.target);
                  }
                  _closeOverlay();
                },
                onClose: _closeOverlay,
              ),
            _ActiveOverlay.calendar => CalendarPopover(
                now: _now,
                onClose: _closeOverlay,
              ),
            _ => const SizedBox.shrink(),
          },
        ),
      );
    }

    // 2. Auto-hidden thin edge trigger strip
    if (_cfg.autoHide && _isAutoHidden) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: MouseRegion(
          onEnter: (_) async {
            _autoHideDelayTimer?.cancel();
            setState(() => _isAutoHidden = false);
            await _syncWindowGeometry();
          },
          child: Container(
            color: const Color(0x01000000),
            alignment: Alignment.center,
            child: Container(
              width: _isHorizontal ? 100 : 3,
              height: _isHorizontal ? 3 : 100,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      );
    }

    // 3. Active Dock Bar
    final hoveredMinWin = (_isPrimary &&
            _hoveredSlotIndex != null &&
            _hoveredSlotIndex! >= _items.length &&
            (_hoveredSlotIndex! - _items.length) < _minimizedWindows.length)
        ? _minimizedWindows[_hoveredSlotIndex! - _items.length]
        : null;

    final hoveredItem = (_hoveredSlotIndex != null &&
            _hoveredSlotIndex! >= 0 &&
            _hoveredSlotIndex! < _items.length)
        ? _items[_hoveredSlotIndex!]
        : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingFile = true),
        onDragExited: (_) => setState(() => _isDraggingFile = false),
        onDragDone: _handleExternalDrop,
        child: MouseRegion(
          onExit: (_) {
            setState(() {
              _hoveredSlotIndex = null;
            });
            if (_isPopupRaised) {
              setState(() => _isPopupRaised = false);
              _applyLayerAndAcrylic();
            }
            if (_cfg.autoHide) {
              _autoHideDelayTimer?.cancel();
              _autoHideDelayTimer = Timer(
                Duration(milliseconds: _cfg.autoHideDelayMs),
                () async {
                  if (!mounted || _overlay != _ActiveOverlay.none) return;
                  setState(() => _isAutoHidden = true);
                  await _syncWindowGeometry();
                },
              );
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Live Aero Thumbnail Preview for hovered minimized window
                if (hoveredMinWin != null)
                  Align(
                    alignment: _cfg.position == 'top'
                        ? Alignment.bottomCenter
                        : Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: MinimizedWindowPreviewCard(
                        title: hoveredMinWin.title,
                        thumbnailPng: hoveredMinWin.thumbnailPng,
                      ),
                    ),
                  )
                // Hover Label for regular items & docklets
                else if (_cfg.showLabels &&
                    hoveredItem != null &&
                    hoveredItem.type != 'separator')
                  Align(
                    alignment: switch (_cfg.position) {
                      'top' => Alignment.bottomCenter,
                      'left' => Alignment.centerRight,
                      'right' => Alignment.centerLeft,
                      _ => Alignment.topCenter,
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: _buildStyledLabel(_resolveHoverTitle(hoveredItem)),
                    ),
                  ),

                // Main Dock Container aligned to its screen edge
                Align(
                  alignment: switch (_cfg.position) {
                    'top' => Alignment.topCenter,
                    'left' => Alignment.centerLeft,
                    'right' => Alignment.centerRight,
                    _ => Alignment.bottomCenter,
                  },
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: _cfg.autoHideDurationMs),
                    padding: EdgeInsets.symmetric(
                      horizontal: _isHorizontal ? 14 : 8,
                      vertical: _isHorizontal ? 8 : 14,
                    ),
                    decoration: _resolveDockSurface().copyWith(
                      border: _isDraggingFile
                          ? Border.all(color: const Color(0xFF38BDF8), width: 2)
                          : null,
                    ),
                    child: _buildDockItemsAxis(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _resolveHoverTitle(DockItemModel item) {
    switch (item.type) {
      case 'recycle_bin':
        return _recycleBin.itemCount == 0
            ? '${item.title} (${AppI18n.t('recycle_empty')})'
            : '${item.title} (${_recycleBin.itemCount})';
      case 'docklet_battery':
        return _battery.hasBattery
            ? '${item.title}: ${_battery.percent}%${_battery.acOnline ? ' (Сеть)' : ''}'
            : '${item.title}: От сети (AC)';
      case 'docklet_sysstats':
        return 'CPU ${_sysStats.cpuPercent}% · RAM ${_sysStats.ramPercent}% (${_sysStats.usedGb.toStringAsFixed(1)}/${_sysStats.totalGb.toStringAsFixed(1)} ГБ)';
      case 'docklet_clock':
        return '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')}';
      default:
        return item.title;
    }
  }

  Widget _buildDockItemsAxis() {
    final children = <Widget>[];

    // Regular items & docklets
    for (var i = 0; i < _items.length; i++) {
      children.add(_buildRegularSlot(i, _items[i]));
    }

    // Minimized windows section on Dock #1
    if (_isPrimary && _minimizedWindows.isNotEmpty) {
      children.add(_buildDividerVisual());
      for (var j = 0; j < _minimizedWindows.length; j++) {
        children.add(_buildMinimizedWindowSlot(_items.length + j, j, _minimizedWindows[j]));
      }
    }

    if (_isHorizontal) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: _cfg.position == 'top'
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: children,
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: _cfg.position == 'left'
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: children,
      ),
    );
  }

  Widget _buildDividerVisual() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: _isHorizontal ? 6 : 2,
        vertical: _isHorizontal ? 4 : 6,
      ),
      width: _isHorizontal ? 1.5 : _cfg.iconSize * 0.72,
      height: _isHorizontal ? _cfg.iconSize * 0.72 : 1.5,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildRegularSlot(int index, DockItemModel item) {
    if (item.type == 'separator') {
      return GestureDetector(
        onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition, item: item),
        child: _buildDividerVisual(),
      );
    }

    final scale = _scaleForSlot(index);
    final size = _cfg.iconSize * scale;
    final isHovered = _hoveredSlotIndex == index;
    final isBouncing = _bouncingKey == item.id;
    final exe = item.executableName;
    final isRunning = widget.store.global.showRunningIndicators &&
        exe != null &&
        _runningProcesses.contains(exe);

    final effectiveOpacity = (isHovered && _cfg.zoomOpaque)
        ? 1.0
        : (_cfg.iconOpacity / 100.0).clamp(0.2, 1.0);

    final iconVisual = _renderItemArt(item, size);

    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hoveredSlotIndex = index),
      child: GestureDetector(
        onTap: () => _activateItem(item),
        onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition, item: item),
        child: Opacity(
          opacity: effectiveOpacity,
          child: AnimatedContainer(
            duration: Duration(milliseconds: _cfg.zoomDurationMs),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.symmetric(
              horizontal: _isHorizontal ? 4 : 0,
              vertical: _isHorizontal ? 0 : 4,
            ),
            transform: Matrix4.translationValues(
              0,
              isBouncing && _cfg.clickEffect == 'bounce' ? -12 : 0,
              0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: isBouncing && _cfg.clickEffect == 'pulse' ? 1.14 : 1.0,
                  duration: const Duration(milliseconds: 180),
                  child: DecoratedBox(
                    decoration: isBouncing && _cfg.clickEffect == 'glow'
                        ? BoxDecoration(
                            borderRadius: BorderRadius.circular(size * 0.26),
                            boxShadow: const [
                              BoxShadow(color: Color(0xCC38BDF8), blurRadius: 18, spreadRadius: 2),
                            ],
                          )
                        : const BoxDecoration(),
                    child: iconVisual,
                  ),
                ),
                if (isRunning)
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF38BDF8),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0xAA38BDF8), blurRadius: 6)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Drag-to-reorder + Drag-off-to-remove (Lock Items bypassed by holding Ctrl!)
    return DragTarget<int>(
      onAcceptWithDetails: (details) async {
        final from = details.data;
        if (from == index || from < 0 || from >= _items.length) return;
        final moved = _items.removeAt(from);
        _items.insert(index, moved);
        await widget.store.save();
        setState(() {});
      },
      builder: (context, _, __) {
        return Draggable<int>(
          data: index,
          maxSimultaneousDrags:
              (!widget.store.global.lockItems || Win32Bridge.isCtrlPressed()) ? 1 : 0,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.85, child: _renderItemArt(item, _cfg.iconSize)),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: tile),
          onDragEnd: (details) async {
            // Dragged far off the dock -> remove item (RocketDock poof behavior!)
            if (!details.wasAccepted &&
                (!widget.store.global.lockItems || Win32Bridge.isCtrlPressed())) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final origin = box.localToGlobal(Offset.zero);
                final delta = (details.offset - origin).distance;
                if (delta > _cfg.iconSize * 1.9) {
                  _items.removeWhere((e) => e.id == item.id);
                  await widget.store.save();
                  setState(() {});
                  await _syncWindowGeometry();
                }
              }
            }
          },
          child: tile,
        );
      },
    );
  }

  Widget _buildMinimizedWindowSlot(int slotIndex, int minIdx, _MinimizedWindowEntry entry) {
    final scale = _scaleForSlot(slotIndex);
    final size = _cfg.iconSize * scale;

    final tile = MouseRegion(
      onEnter: (_) {
        setState(() => _hoveredSlotIndex = slotIndex);
        // Refresh live thumbnail on hover
        final fresh = Win32Bridge.captureWindowThumbnailPng(entry.hwnd);
        if (fresh != null && mounted) {
          setState(() => entry.thumbnailPng = fresh);
        }
      },
      child: GestureDetector(
        onTap: () => _restoreMinimizedEntry(entry),
        onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition, minWin: entry),
        child: AnimatedContainer(
          duration: Duration(milliseconds: _cfg.zoomDurationMs),
          margin: EdgeInsets.symmetric(
            horizontal: _isHorizontal ? 4 : 0,
            vertical: _isHorizontal ? 0 : 4,
          ),
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.20),
            color: const Color(0xCC1E293B),
            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.7), width: 1.4),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (entry.thumbnailPng != null)
                Image.memory(
                  entry.thumbnailPng!,
                  fit: BoxFit.cover,
                  filterQuality: _cfg.filterQuality,
                  gaplessPlayback: true,
                )
              else
                const Icon(Icons.web_asset_rounded, color: Colors.white54),
              if (entry.iconPngPath != null && File(entry.iconPngPath!).existsSync())
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: size * 0.36,
                    height: size * 0.36,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xDD0F172A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Image.file(File(entry.iconPngPath!), fit: BoxFit.contain),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // Allow reordering minimized windows in the dock
    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        if (!details.data.startsWith('min:')) return;
        final from = int.tryParse(details.data.substring(4));
        if (from == null || from == minIdx || from < 0 || from >= _minimizedWindows.length) return;
        setState(() {
          final moved = _minimizedWindows.removeAt(from);
          _minimizedWindows.insert(minIdx, moved);
        });
      },
      builder: (_, __, ___) => Draggable<String>(
        data: 'min:$minIdx',
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.8, child: SizedBox(width: _cfg.iconSize, height: _cfg.iconSize, child: tile)),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: tile),
        child: tile,
      ),
    );
  }

  Widget _renderItemArt(DockItemModel item, double size) {
    switch (item.type) {
      case 'docklet_clock':
        return ClockDockletIcon(now: _now, size: size);
      case 'docklet_battery':
        return BatteryDockletIcon(info: _battery, size: size);
      case 'docklet_sysstats':
        return SysStatsDockletIcon(stats: _sysStats, size: size);
      case 'docklet_calendar':
        return CalendarDockletIcon(now: _now, size: size);
      case 'recycle_bin':
        return RecycleBinDockletIcon(
          info: _recycleBin,
          item: item,
          size: size,
          quality: _cfg.filterQuality,
        );
      default:
        break;
    }

    if (item.iconPath != null && File(item.iconPath!).existsSync()) {
      return Image.file(
        File(item.iconPath!),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: _cfg.filterQuality,
      );
    }

    return DockGlyphTile(
      iconKey: item.iconKey,
      color: parseHexColor(item.color),
      size: size,
    );
  }
}
