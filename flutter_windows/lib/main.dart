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
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'dev_watcher.dart';
import 'dialogs.dart';
import 'docklets.dart';
import 'i18n.dart';
import 'ini_storage.dart';
import 'win32_bridge.dart';

extension _SafeIterable<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

void _logRuntimeError(Object error, StackTrace? stack) {
  try {
    final dir = PortableIniStore.resolvePortableDir();
    final logFile = File(p.join(dir.path, 'aerodock_error.log'));
    final ts = DateTime.now().toIso8601String();
    logFile.writeAsStringSync(
      '[$ts] $error\n${stack ?? ''}\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    _logRuntimeError(details.exception, details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    _logRuntimeError(error, stack);
    return true;
  };

  try {
    await _bootstrapAeroDock(args);
  } catch (e, st) {
    _logRuntimeError(e, st);
  }
}

Future<void> _bootstrapAeroDock(List<String> args) async {
  try {
    await windowManager.ensureInitialized();
  } catch (e, st) {
    _logRuntimeError(e, st);
  }

  try {
    await acrylic.Window.initialize();
  } catch (e, st) {
    _logRuntimeError(e, st);
  }

  var dockId = 1;
  var isSettingsWindow = false;
  var settingsTab = 0;

  for (final arg in args) {
    if (arg == '--settings') {
      isSettingsWindow = true;
    } else if (arg.startsWith('--dock=')) {
      dockId = int.tryParse(arg.substring(7))?.clamp(1, 4) ?? 1;
    } else if (arg.startsWith('--tab=')) {
      settingsTab = int.tryParse(arg.substring(6))?.clamp(0, 7) ?? 0;
    }
  }

  // Dedicated standalone Settings window so ALL docks stay visible for Live Preview!
  if (isSettingsWindow) {
    final store = await PortableIniStore.load(allowAutoMigrate: false);
    AppI18n.loadExternalLanguages(store.languagesDir);
    AppI18n.currentCode = store.global.language;
    try {
      store.global.launchWithWindows = Win32Bridge.isStartupEnabled();
    } catch (_) {}

    var displays = <Display>[];
    try {
      displays = await screenRetriever.getAllDisplays();
    } catch (_) {}

    const settingsOpts = WindowOptions(
      size: Size(810, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
    );

    runApp(
      SettingsWindowApp(
        store: store,
        activeDockId: dockId,
        initialTab: settingsTab,
        displays: displays,
      ),
    );

    unawaited(
      windowManager.waitUntilReadyToShow(settingsOpts, () async {
        try {
          await windowManager.setAsFrameless();
        } catch (_) {}
        try {
          await windowManager.setHasShadow(false);
        } catch (_) {}
        try {
          await windowManager.setBackgroundColor(Colors.transparent);
        } catch (_) {}
        try {
          await windowManager.setResizable(false);
        } catch (_) {}
        try {
          await windowManager.setAlwaysOnTop(true);
        } catch (_) {}
        try {
          await windowManager.center();
        } catch (_) {}
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
        try {
          await acrylic.Window.setEffect(
            effect: acrylic.WindowEffect.transparent,
            color: const Color(0x00000000),
          );
        } catch (_) {}
      }),
    );
    return;
  }

  if (dockId == 1) {
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
  }

  final store = await PortableIniStore.load(allowAutoMigrate: dockId == 1);
  AppI18n.loadExternalLanguages(store.languagesDir);
  AppI18n.currentCode = store.global.language;
  try {
    store.global.launchWithWindows = Win32Bridge.isStartupEnabled();
  } catch (_) {}

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
    size: Size(760, 150),
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  // Start Flutter widget tree FIRST so waitUntilReadyToShow can never deadlock!
  runApp(AeroDockApp(store: store, dockId: dockId));

  unawaited(
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      try {
        await windowManager.setAsFrameless();
      } catch (_) {}
      try {
        await windowManager.setHasShadow(false);
      } catch (_) {}
      try {
        await windowManager.setBackgroundColor(Colors.transparent);
      } catch (_) {}
      try {
        await windowManager.setResizable(false);
      } catch (_) {}
      try {
        await windowManager.setAlwaysOnTop(cfg.layer == 'top');
      } catch (_) {}
      try {
        await windowManager.show();
      } catch (_) {}
      try {
        await acrylic.Window.setEffect(
          effect: cfg.useAcrylic
              ? acrylic.WindowEffect.acrylic
              : acrylic.WindowEffect.transparent,
          color: cfg.useAcrylic ? const Color(0x550F172A) : const Color(0x00000000),
        );
      } catch (_) {}
    }),
  );
}

class SettingsWindowApp extends StatelessWidget {
  final PortableIniStore store;
  final int activeDockId;
  final int initialTab;
  final List<Display> displays;

  const SettingsWindowApp({
    super.key,
    required this.store,
    required this.activeDockId,
    required this.initialTab,
    required this.displays,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Настройки AeroDock',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0EA5E9),
          brightness: Brightness.dark,
        ),
      ),
      home: _StandaloneSettingsHost(
        store: store,
        activeDockId: activeDockId,
        initialTab: initialTab,
        displays: displays,
      ),
    );
  }
}

class _StandaloneSettingsHost extends StatefulWidget {
  final PortableIniStore store;
  final int activeDockId;
  final int initialTab;
  final List<Display> displays;

  const _StandaloneSettingsHost({
    required this.store,
    required this.activeDockId,
    required this.initialTab,
    required this.displays,
  });

  @override
  State<_StandaloneSettingsHost> createState() => _StandaloneSettingsHostState();
}

class _StandaloneSettingsHostState extends State<_StandaloneSettingsHost> {
  Timer? _quitWatchTimer;

  @override
  void initState() {
    super.initState();
    final quitFile = File(p.join(widget.store.portableDir.path, '.aerodock_quit'));
    _quitWatchTimer = Timer.periodic(const Duration(milliseconds: 450), (_) async {
      if (quitFile.existsSync()) {
        await windowManager.destroy();
        exit(0);
      }
    });

    // Visibility watchdog so the standalone Settings window can never stay hidden
    Future<void>.delayed(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      try {
        if (!await windowManager.isVisible()) {
          await windowManager.show();
          await windowManager.focus();
        }
        final hwnd = Win32Bridge.findOwnWindowHandle();
        if (hwnd != 0 && !Win32Bridge.isWindowVisible(hwnd)) {
          Win32Bridge.ensureWindowVisible(hwnd, activate: true);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _quitWatchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: DockSettingsDialog(
          store: widget.store,
          activeDockId: widget.activeDockId,
          initialTab: widget.initialTab,
          displays: widget.displays,
          isStandaloneWindow: true,
          onSaved: () {},
          onResetDefaults: () async {
            await widget.store.resetSettingsToDefaultsOnly();
          },
          onFullReset: () async {
            await widget.store.fullReset();
          },
          onClose: () async {
            await windowManager.destroy();
            exit(0);
          },
        ),
      ),
    );
  }
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
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
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

  _MinimizedWindowEntry({
    required this.hwnd,
    required this.title,
    required this.exePath,
    required this.processName,
    this.iconPngPath,
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
  // Sibling dock processes (owned by Dock #1) + standalone Settings window process
  final Map<int, Process> _childDocks = {};
  Process? _settingsProcess;
  bool _syncInFlight = false;

  // Ultra-fast ValueNotifiers — ZERO full-tree setState() during idle or hover!
  final ValueNotifier<double?> _hoverAxisNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<DateTime> _nowNotifier = ValueNotifier<DateTime>(DateTime.now());
  final ValueNotifier<BatteryInfo> _batteryNotifier = ValueNotifier<BatteryInfo>(
    const BatteryInfo(percent: 100, acOnline: true, charging: false, hasBattery: false),
  );
  final ValueNotifier<SysStatsInfo> _sysStatsNotifier = ValueNotifier<SysStatsInfo>(
    const SysStatsInfo(cpuPercent: 0, ramPercent: 0, usedGb: 0, totalGb: 0),
  );
  final ValueNotifier<RecycleBinInfo> _recycleBinNotifier = ValueNotifier<RecycleBinInfo>(
    const RecycleBinInfo(itemCount: 0, sizeBytes: 0),
  );
  final ValueNotifier<Set<String>> _runningProcsNotifier = ValueNotifier<Set<String>>({});

  String? _bouncingKey;
  bool _isDraggingFile = false;
  bool _isAutoHidden = false;
  bool _isPopupRaised = false;
  bool _suspended = false;
  int _ownHwnd = 0;
  bool? _lastAppliedUseAcrylic;

  // Guaranteed physical Win32 work area + logical DIP work area + exact DPI scale factor
  Rect _cachedPhysicalWorkRect = const Rect.fromLTWH(0, 0, 1920, 1040);
  Rect _cachedScreenRect = const Rect.fromLTWH(0, 0, 1920, 1040);
  double _displayScaleFactor = 1.0;
  List<Display> _displays = [];
  List<ExternalSkinInfo> _externalSkins = [];
  List<ExternalDockletInfo> _externalDocklets = [];

  // Overlay dialogs
  _ActiveOverlay _overlay = _ActiveOverlay.none;
  int _settingsInitialTab = 0;
  DockItemModel? _editingItem;
  String _editorDefaultType = 'file';
  DockItemModel? _openStackItem;
  List<FolderEntryInfo> _stackEntries = [];

  // Dev Panel ("Разработка") GitHub archive watcher & transient toast banner
  DevArchiveWatcher? _devWatcher;
  String? _toastMessage;
  Timer? _toastTimer;

  // Minimized Windows (baseline prevents hijacking background windows on startup)
  List<Win32WindowInfo> _openWindows = [];
  final List<_MinimizedWindowEntry> _minimizedWindows = [];
  final Set<int> _baselineMinimizedHwnds = {};
  final Set<int> _onceExcludedHwnds = {};
  final Set<int> _hiddenByDockHwnds = {};
  bool _baselineCaptured = false;

  // Lightweight, demand-driven timers
  Timer? _clockTimer;
  Timer? _statsTimer;
  Timer? _recycleTimer;
  Timer? _winPollTimer;
  Timer? _syncTimer;
  Timer? _edgeHoverTimer;
  Timer? _autoHideDelayTimer;
  Timer? _popupDelayTimer;

  // RocketDock global hotkey: Ctrl+Alt+R (completely hide/show + pause all polling)
  final HotKey _toggleHotKey = HotKey(
    key: PhysicalKeyboardKey.keyR,
    modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );

  int get _dockId => widget.dockId;
  bool get _isPrimary => _dockId == 1;
  DockPanelConfig get _cfg =>
      widget.store.panels[_dockId] ?? DockPanelConfig.defaultFor(_dockId);
  List<DockItemModel> get _items => widget.store.dockItems
      .putIfAbsent(_dockId, () => PortableIniStore.defaultItemsFor(_dockId));
  bool get _isHorizontal => _cfg.position == 'bottom' || _cfg.position == 'top';

  File get _quitSignalFile => File(p.join(widget.store.portableDir.path, '.aerodock_quit'));
  File get _hiddenSignalFile => File(p.join(widget.store.portableDir.path, '.aerodock_hidden'));

  // Adaptive no-clip slot sizing: automatically fits all icons inside screen width/height
  // so changing edge (top/left/right/bottom) or increasing icon size NEVER hides icons!
  double get _fitScaleRatio {
    final regularCount = _items.where((e) => e.type != 'separator').length +
        (_isPrimary ? _minimizedWindows.length : 0);
    if (regularCount <= 0) return 1.0;
    final sepCount = _items.where((e) => e.type == 'separator').length +
        (_isPrimary && _minimizedWindows.isNotEmpty ? 1 : 0);
    final availMain = math.max(
      200.0,
      (_isHorizontal ? _cachedScreenRect.width : _cachedScreenRect.height) - 76.0,
    );
    final desiredMain = regularCount * (_cfg.iconSize + 12.0) + sepCount * 14.0;
    if (desiredMain <= availMain) return 1.0;
    return (availMain / desiredMain).clamp(0.42, 1.0);
  }

  double get _effectiveIconSize => (_cfg.iconSize * _fitScaleRatio).clamp(24.0, _cfg.iconSize);
  double get _slotStride => _effectiveIconSize + (12.0 * _fitScaleRatio).clamp(4.0, 12.0);
  double get _sepStride => (14.0 * _fitScaleRatio).clamp(6.0, 14.0);

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
      await _refreshDisplaysAndWorkArea();
      if (_isPrimary) {
        await _initSystemTray();
        await _registerGlobalHotKey();
        await _reconcileSiblingDocks();
        _initDevWatcher();
        if (widget.store.migratedFromPreviousVersion) {
          _showToast('Настройки и иконки автоматически перенесены из предыдущей версии!');
        }
        // Delay auto-backup slightly so initial multi-dock startup never races on Settings.ini
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (mounted) unawaited(widget.store.runAutoBackupIfDue());
        });
      }
      _extractMissingIcons();
      await _syncWindowGeometry();
      await _ensureDockVisible();
      _pollWindowsAndRunning();
      _pollStatsNow();
      _pollRecycleBinNow();

      // Safety visibility & geometry check after window_manager/flutter_acrylic finish attaching
      Future<void>.delayed(const Duration(milliseconds: 550), () async {
        if (!mounted || _suspended) return;
        await _refreshDisplaysAndWorkArea();
        await _syncWindowGeometry();
        await _ensureDockVisible();
      });
    });

    // 1. Clock ticks ONLY update _nowNotifier (no full-tree rebuild!)
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_suspended || !mounted) return;
      final hasClock = _overlay == _ActiveOverlay.calendar ||
          _items.any((e) => e.type == 'docklet_clock' || e.type == 'docklet_calendar');
      if (hasClock) {
        _nowNotifier.value = DateTime.now();
      }
    });

    // 2. Battery & SysStats poll every 2.5s ONLY if those docklets exist on this dock
    _statsTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (_suspended || !mounted) return;
      _pollStatsNow();
    });

    // 3. Recycle Bin polls every 5s ONLY if recycle_bin exists on this dock
    _recycleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_suspended || !mounted) return;
      _pollRecycleBinNow();
    });

    // 4. Running indicators & Minimize-to-dock poll every 1.4s via PID-cached Win32 FFI (<0.15ms)
    _winPollTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (_suspended || !mounted) return;
      if (widget.store.global.showRunningIndicators ||
          (_isPrimary && widget.store.global.minimizeToDock)) {
        _pollWindowsAndRunning();
      }
    });

    // 5. Ultra-fast Live Settings & Multi-Dock INI sync every 220ms (mtime check < 0.05ms!)
    _syncTimer = Timer.periodic(const Duration(milliseconds: 220), (_) {
      _checkMultiDockSync();
    });

    // 6. AutoHide / Popup edge hover check ONLY when needed (uses cached rect, 0 IPC!)
    _edgeHoverTimer = Timer.periodic(const Duration(milliseconds: 140), (_) {
      if (_suspended || !mounted) return;
      _checkCursorEdgeHover();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _statsTimer?.cancel();
    _recycleTimer?.cancel();
    _winPollTimer?.cancel();
    _syncTimer?.cancel();
    _edgeHoverTimer?.cancel();
    _autoHideDelayTimer?.cancel();
    _popupDelayTimer?.cancel();
    _toastTimer?.cancel();
    _devWatcher?.stop();
    _hoverAxisNotifier.dispose();
    _nowNotifier.dispose();
    _batteryNotifier.dispose();
    _sysStatsNotifier.dispose();
    _recycleBinNotifier.dispose();
    _runningProcsNotifier.dispose();
    windowManager.removeListener(this);
    if (_isPrimary) {
      trayManager.removeListener(this);
      hotKeyManager.unregisterAll();
      _restoreAllHiddenWindows();
      _killAllChildDocks();
    }
    super.dispose();
  }

  void _initDevWatcher() {
    if (!_isPrimary) return;
    _devWatcher ??= DevArchiveWatcher(
      store: widget.store,
      onDeployed: (event) async {
        await _reconcileSiblingDocks();
        await _rebuildTrayMenu();
        final verb = event.wasUpgrade ? 'Обновлено' : 'Установлено';
        final cfgNote = event.wasUpgrade && event.preservedConfigCount > 0
            ? ' · настроек перенесено: ${event.preservedConfigCount}'
            : '';
        _showToast('Разработка: $verb «${event.rule.name}» (v${event.rule.versionCount})$cfgNote');
        if (mounted) setState(() {});
      },
    );
    _reconcileDevWatcher();
  }

  void _reconcileDevWatcher() {
    if (!_isPrimary || _devWatcher == null) return;
    if (!_suspended && widget.store.global.devDockEnabled) {
      _devWatcher!.start();
    } else {
      _devWatcher!.stop();
    }
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() => _toastMessage = msg);
    _toastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _pollStatsNow() {
    if (_items.any((e) => e.type == 'docklet_battery')) {
      final bat = Win32Bridge.getBatteryStatus();
      if (bat != _batteryNotifier.value) _batteryNotifier.value = bat;
    }
    if (_items.any((e) => e.type == 'docklet_sysstats')) {
      final st = Win32Bridge.getCpuRamStats();
      if (st != _sysStatsNotifier.value) _sysStatsNotifier.value = st;
    }
  }

  void _pollRecycleBinNow() {
    if (_items.any((e) => e.type == 'recycle_bin')) {
      final info = Win32Bridge.queryRecycleBin();
      if (info != _recycleBinNotifier.value) _recycleBinNotifier.value = info;
    }
  }

  // ============================================================================
  // Multi-Dock Orchestration (Docks 1, 2, 3 + Dock 4 "Разработка")
  // ============================================================================

  Future<void> _reconcileSiblingDocks() async {
    if (!_isPrimary) return;
    final exe = Platform.resolvedExecutable;

    for (var id = 2; id <= 4; id++) {
      final shouldRun = widget.store.global.isDockEnabled(id);
      final running = _childDocks[id];
      if (shouldRun && running == null) {
        try {
          final proc = await Process.start(exe, ['--dock=$id']);
          _childDocks[id] = proc;
          proc.exitCode.then((_) => _childDocks.remove(id));
        } catch (_) {}
      } else if (!shouldRun && running != null) {
        try {
          running.kill();
        } catch (_) {}
        _childDocks.remove(id);
      }
    }
    _reconcileDevWatcher();
  }

  void _killAllChildDocks() {
    for (final proc in _childDocks.values) {
      try {
        proc.kill();
      } catch (_) {}
    }
    _childDocks.clear();
    if (_settingsProcess != null) {
      try {
        _settingsProcess!.kill();
      } catch (_) {}
      _settingsProcess = null;
    }
  }

  Future<void> _checkMultiDockSync() async {
    if (_syncInFlight) return;
    _syncInFlight = true;
    try {
      if (_quitSignalFile.existsSync()) {
        await _exitSingleInstance();
        return;
      }

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
        _reconcileDevWatcher();
        if (mounted) setState(() {});
      }

      // ALWAYS watch Settings.ini so the standalone Live Settings window updates EVERY dock in real time!
      if (await widget.store.hasExternalChanges()) {
        await widget.store.reloadFromDisk();
        AppI18n.currentCode = widget.store.global.language;
        _externalSkins = widget.store.scanExternalSkins();
        _externalDocklets = widget.store.scanExternalDocklets();
        if (!_cfg.autoHide) _isAutoHidden = false;
        await _refreshDisplaysAndWorkArea();
        if (_isPrimary) {
          await _reconcileSiblingDocks();
          await _rebuildTrayMenu();
        }
        if (!_isPrimary && !widget.store.global.isDockEnabled(_dockId)) {
          await _exitSingleInstance();
          return;
        }
        _extractMissingIcons();
        if (mounted) setState(() {});
        _applyLayerAndAcrylic();
        await _syncWindowGeometry();
        await _ensureDockVisible();
      }
    } catch (e, st) {
      _logRuntimeError(e, st);
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> _quitAllDocks() async {
    try {
      await _quitSignalFile.writeAsString('quit', flush: true);
    } catch (_) {}
    _devWatcher?.stop();
    _restoreAllHiddenWindows();
    _killAllChildDocks();
    await _exitSingleInstance();
  }

  Future<void> _exitSingleInstance() async {
    if (_isPrimary) {
      _devWatcher?.stop();
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
      await trayManager.setToolTip('AeroDock Portable · Ctrl+Alt+R');
      await _rebuildTrayMenu();
    } catch (_) {}
  }

  Future<void> _rebuildTrayMenu() async {
    try {
      final g = widget.store.global;
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'toggle', label: AppI18n.t('show_hide_hotkey')),
            MenuItem(key: 'settings', label: '${AppI18n.t('dock_settings')}…'),
            MenuItem(key: 'settings_panels', label: 'Управление панелями (1–3)…'),
            MenuItem(key: 'settings_dev', label: 'Панель «Разработка» (GitHub)…'),
            MenuItem(key: 'settings_backup', label: 'Бэкапы и восстановление…'),
            MenuItem(key: 'backup_now', label: 'Создать бэкап сейчас'),
            MenuItem(key: 'import_rd135', label: 'Импорт Settings.ini (RocketDock 1.3.5 / AeroDock)…'),
            MenuItem.separator(),
            MenuItem(key: 'toggle_dock2', label: 'Панель 2 (Справа)${g.dock2Enabled ? ' ✓' : ''}'),
            MenuItem(key: 'toggle_dock3', label: 'Панель 3 (Сверху)${g.dock3Enabled ? ' ✓' : ''}'),
            MenuItem(key: 'toggle_dock4', label: 'Панель «Разработка» (Слева)${g.devDockEnabled ? ' ✓' : ''}'),
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
        await _openSettingsTab(0);
        break;
      case 'settings_panels':
        if (_suspended) await _toggleGlobalSuspend();
        await _openSettingsTab(1);
        break;
      case 'settings_dev':
        if (_suspended) await _toggleGlobalSuspend();
        await _openSettingsTab(2);
        break;
      case 'settings_backup':
        if (_suspended) await _toggleGlobalSuspend();
        await _openSettingsTab(7);
        break;
      case 'backup_now':
        final b = await widget.store.createBackup(tag: 'manual');
        _showToast(b != null ? 'Бэкап создан: ${b.name}' : 'Не удалось создать бэкап');
        break;
      case 'import_rd135':
        if (_suspended) await _toggleGlobalSuspend();
        await _importRocketDock135ViaPicker();
        break;
      case 'toggle_dock2':
        await widget.store.saveGlobalChange((g) => g.dock2Enabled = !g.dock2Enabled);
        await _reconcileSiblingDocks();
        await _rebuildTrayMenu();
        break;
      case 'toggle_dock3':
        await widget.store.saveGlobalChange((g) => g.dock3Enabled = !g.dock3Enabled);
        await _reconcileSiblingDocks();
        await _rebuildTrayMenu();
        break;
      case 'toggle_dock4':
        await widget.store.saveGlobalChange((g) => g.devDockEnabled = !g.devDockEnabled);
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
    _reconcileDevWatcher();
    if (mounted) setState(() {});
  }

  // ============================================================================
  // Ultra-Fast Running Indicators + Clean Minimize-to-Dock (Zero Startup Hijack!)
  // ============================================================================

  void _pollWindowsAndRunning() {
    final windows = Win32Bridge.enumerateWindows(includeHiddenHwnds: _hiddenByDockHwnds);
    _openWindows = windows;

    final running = <String>{};
    for (final w in windows) {
      if (w.processName.isNotEmpty) running.add(w.processName);
    }

    // Only update running indicator notifier when changed!
    final prev = _runningProcsNotifier.value;
    if (running.length != prev.length || !running.containsAll(prev)) {
      _runningProcsNotifier.value = running;
    }

    // Record baseline already-minimized windows on first poll so we never hijack them
    if (!_baselineCaptured) {
      _baselineCaptured = true;
      for (final w in windows) {
        if (w.isMinimized) _baselineMinimizedHwnds.add(w.hwnd);
      }
      return;
    }

    if (!_isPrimary) return;

    var minListChanged = false;

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
          _baselineMinimizedHwnds.remove(w.hwnd);
          _onceExcludedHwnds.remove(w.hwnd);
          continue;
        }
        if (_baselineMinimizedHwnds.contains(w.hwnd)) continue;
        if (_hiddenByDockHwnds.contains(w.hwnd)) continue;
        if (_onceExcludedHwnds.contains(w.hwnd)) continue;
        if (widget.store.global.excludedWindows.contains(w.processName)) continue;

        if (ctrlAltShift && w.processName.isNotEmpty) {
          final procName = w.processName;
          widget.store.global.excludedWindows.add(procName);
          unawaited(widget.store.saveGlobalChange((g) {
            if (!g.excludedWindows.contains(procName)) {
              g.excludedWindows.add(procName);
            }
          }));
          continue;
        }
        if (ctrlOnly) {
          _onceExcludedHwnds.add(w.hwnd);
          continue;
        }

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
          ),
        );
        minListChanged = true;
      }
    } else if (_minimizedWindows.isNotEmpty) {
      _restoreAllHiddenWindows();
      minListChanged = true;
    }

    if (minListChanged && mounted) {
      setState(() {});
      _syncWindowGeometry();
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
  // 100% Exact Physical-Win32 + Logical-DIP Positioning (Never Off-Screen at ANY DPI!)
  // ============================================================================

  double _resolveCurrentDpr({double monitorScaleFallback = 1.0}) {
    if (_ownHwnd == 0) _ownHwnd = Win32Bridge.findOwnWindowHandle();
    final winScale = Win32Bridge.getWindowScaleFactor(_ownHwnd, fallback: 0);
    if (winScale >= 0.75) return winScale;
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty && views.first.devicePixelRatio >= 0.75) {
        return views.first.devicePixelRatio.clamp(0.75, 4.0);
      }
    } catch (_) {}
    return monitorScaleFallback.clamp(0.75, 4.0);
  }

  Future<void> _ensureDockVisible() async {
    if (_suspended) return;
    if (_ownHwnd == 0) _ownHwnd = Win32Bridge.findOwnWindowHandle();
    try {
      if (!await windowManager.isVisible()) {
        await windowManager.show();
      }
    } catch (_) {}
    if (_ownHwnd != 0 && !Win32Bridge.isWindowVisible(_ownHwnd)) {
      Win32Bridge.ensureWindowVisible(_ownHwnd, activate: _overlay != _ActiveOverlay.none);
    }
  }

  Future<void> _refreshDisplaysAndWorkArea() async {
    try {
      _displays = await screenRetriever.getAllDisplays();
    } catch (_) {}

    // Always read GUARANTEED physical pixel bounds directly from Win32 EnumDisplayMonitors!
    // This completely eliminates screen_retriever 0.2.0 physical-vs-logical DPI mismatches
    // that previously pushed bottom/right docks below the monitor at 125%/150%/200% scaling.
    final monitors = Win32Bridge.enumerateMonitors();
    if (monitors.isNotEmpty) {
      if (_cfg.monitorIndex == -1) {
        var minL = double.infinity;
        var minT = double.infinity;
        var maxR = double.negativeInfinity;
        var maxB = double.negativeInfinity;
        for (final m in monitors) {
          minL = math.min(minL, m.workRect.left);
          minT = math.min(minT, m.workRect.top);
          maxR = math.max(maxR, m.workRect.right);
          maxB = math.max(maxB, m.workRect.bottom);
        }
        final dpr = _resolveCurrentDpr(monitorScaleFallback: monitors.first.scaleFactor);
        _displayScaleFactor = dpr;
        if (minL.isFinite && maxR > minL && maxB > minT) {
          _cachedPhysicalWorkRect = Rect.fromLTRB(minL, minT, maxR, maxB);
          _cachedScreenRect = Rect.fromLTRB(minL / dpr, minT / dpr, maxR / dpr, maxB / dpr);
          return;
        }
      } else {
        final idx = _cfg.monitorIndex.clamp(0, monitors.length - 1);
        final m = monitors[idx];
        final dpr = m.scaleFactor >= 0.75
            ? m.scaleFactor
            : _resolveCurrentDpr(monitorScaleFallback: 1.0);
        _displayScaleFactor = dpr;
        _cachedPhysicalWorkRect = Rect.fromLTWH(
          m.workRect.left,
          m.workRect.top,
          m.workRect.width,
          m.workRect.height,
        );
        _cachedScreenRect = Rect.fromLTWH(
          m.workRect.left / dpr,
          m.workRect.top / dpr,
          m.workRect.width / dpr,
          m.workRect.height / dpr,
        );
        return;
      }
    }

    // Fallback to Win32 SPI_GETWORKAREA converted via exact DPR
    final dpr = _resolveCurrentDpr();
    _displayScaleFactor = dpr;
    final work = Win32Bridge.getPrimaryWorkArea();
    if (work != null) {
      _cachedPhysicalWorkRect = Rect.fromLTWH(work.left, work.top, work.width, work.height);
      _cachedScreenRect = Rect.fromLTWH(
        work.left / dpr,
        work.top / dpr,
        work.width / dpr,
        work.height / dpr,
      );
    }
  }

  void _applyLayerAndAcrylic({bool forceAcrylic = false}) {
    if (_ownHwnd == 0) _ownHwnd = Win32Bridge.findOwnWindowHandle();
    final effectiveLayer = _isPopupRaised ? 'top' : _cfg.layer;
    try {
      windowManager.setAlwaysOnTop(effectiveLayer == 'top');
    } catch (_) {}
    Win32Bridge.setWindowLayer(_ownHwnd, effectiveLayer);

    // Only touch flutter_acrylic when the setting actually changes — repeated calls during
    // resize/move can corrupt the transparent DWM composition surface on Windows 11!
    if (forceAcrylic || _lastAppliedUseAcrylic != _cfg.useAcrylic) {
      _lastAppliedUseAcrylic = _cfg.useAcrylic;
      unawaited(() async {
        try {
          await acrylic.Window.setEffect(
            effect: _cfg.useAcrylic
                ? acrylic.WindowEffect.acrylic
                : acrylic.WindowEffect.transparent,
            color: _cfg.useAcrylic ? const Color(0x550F172A) : const Color(0x00000000),
          );
        } catch (_) {}
      }());
    }
  }

  double _computeItemsMainSpan() {
    var total = 0.0;
    for (final it in _items) {
      total += it.type == 'separator' ? _sepStride : _slotStride;
    }
    if (_isPrimary && _minimizedWindows.isNotEmpty) {
      total += _sepStride + _minimizedWindows.length * _slotStride;
    }
    return total;
  }

  Future<void> _syncWindowGeometry() async {
    if (_suspended) return;
    if (_ownHwnd == 0) _ownHwnd = Win32Bridge.findOwnWindowHandle();

    final screen = _cachedScreenRect;
    final physScreen = _cachedPhysicalWorkRect;
    final dpr = _displayScaleFactor.clamp(0.75, 4.0);

    if (_overlay != _ActiveOverlay.none) {
      final w = switch (_overlay) {
        _ActiveOverlay.settings => 810.0,
        _ActiveOverlay.iconSettings => 770.0,
        _ActiveOverlay.stack => 560.0,
        _ActiveOverlay.calendar => 340.0,
        _ => 810.0,
      };
      final h = switch (_overlay) {
        _ActiveOverlay.settings => 600.0,
        _ActiveOverlay.iconSettings => 560.0,
        _ActiveOverlay.stack => 410.0,
        _ActiveOverlay.calendar => 340.0,
        _ => 600.0,
      };
      final clampedW = math.min(w, math.max(320.0, screen.width - 24));
      final clampedH = math.min(h, math.max(280.0, screen.height - 24));
      final left = screen.left + (screen.width - clampedW) / 2;
      final top = screen.top + (screen.height - clampedH) / 2;
      try {
        await windowManager.setSize(Size(clampedW, clampedH));
        await windowManager.setPosition(Offset(left, top));
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
      return;
    }

    final baseIcon = _effectiveIconSize;
    final maxIcon = baseIcon * (_cfg.hoverEffect == 'none' ? 1.0 : _cfg.zoomScale);
    final zoomPad = math.max(36.0, (maxIcon - baseIcon) * 1.3 + 48.0);
    // Main length fits ALL icons cleanly with zoom headroom and never clips!
    final mainLen = math.max(220.0, _computeItemsMainSpan() + zoomPad);
    // Cross length leaves generous room for zoomed icons + floating label!
    final crossLen = math.max(maxIcon + (_cfg.showLabels ? 58 : 28) + 22, 138.0);

    final bool collapsed = _cfg.autoHide && _isAutoHidden;
    final double winW;
    final double winH;
    if (_isHorizontal) {
      winW = math.min(math.max(220.0, screen.width - 8), mainLen);
      winH = collapsed ? 8.0 : math.min(math.max(110.0, screen.height - 16), crossLen);
    } else {
      winW = collapsed ? 8.0 : math.min(math.max(140.0, screen.width - 16), crossLen + 110);
      winH = math.min(math.max(220.0, screen.height - 8), mainLen);
    }

    final centerShiftX = screen.width * (_cfg.centerOffset / 100);
    final centerShiftY = screen.height * (_cfg.centerOffset / 100);
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

    // Apply logical size & position via window_manager
    try {
      await windowManager.setSize(Size(winW, winH));
      await windowManager.setPosition(Offset(x, y));
    } catch (_) {}

    // Physical-pixel verification & snap: guarantees the HWND sits 100% INSIDE the monitor's
    // real Win32 work area even on 125%/150%/200% DPI or mixed-DPI multi-monitor setups!
    if (_ownHwnd != 0) {
      final maxW = math.max(8, physScreen.width.round());
      final maxH = math.max(8, physScreen.height.round());
      final physW = (winW * dpr).round().clamp(8, maxW);
      final physH = (winH * dpr).round().clamp(8, maxH);
      final maxPhysX = math.max(physScreen.left.round(), physScreen.right.round() - physW);
      final maxPhysY = math.max(physScreen.top.round(), physScreen.bottom.round() - physH);
      final targetPhysX = (x * dpr).round().clamp(physScreen.left.round(), maxPhysX);
      final targetPhysY = (y * dpr).round().clamp(physScreen.top.round(), maxPhysY);

      final actual = Win32Bridge.getWindowRect(_ownHwnd);
      final drifted = actual == null ||
          (actual.left - targetPhysX).abs() > 4 ||
          (actual.top - targetPhysY).abs() > 4 ||
          (actual.width - physW).abs() > 6 ||
          (actual.height - physH).abs() > 6;
      if (drifted) {
        final effectiveLayer = _isPopupRaised ? 'top' : _cfg.layer;
        Win32Bridge.setWindowBoundsPhysical(
          _ownHwnd,
          left: targetPhysX,
          top: targetPhysY,
          width: physW,
          height: physH,
          layer: effectiveLayer,
          show: true,
        );
      }
    }

    _applyLayerAndAcrylic();
  }

  /// Zero-IPC edge hover detector comparing raw physical GetCursorPos directly against physical Win32 rcWork!
  void _checkCursorEdgeHover() {
    if (_overlay != _ActiveOverlay.none) return;
    if (!_cfg.autoHide && (!_cfg.popupOnMouseover || _cfg.layer == 'top')) return;

    final rawCursor = Win32Bridge.getCursorPos();
    final cx = rawCursor.x.toDouble();
    final cy = rawCursor.y.toDouble();
    final screen = _cachedPhysicalWorkRect;
    final hotZone = 10.0 * _displayScaleFactor;

    final atEdge = switch (_cfg.position) {
      'top' => cy <= screen.top + hotZone &&
          cx >= screen.left &&
          cx <= screen.right,
      'left' => cx <= screen.left + hotZone &&
          cy >= screen.top &&
          cy <= screen.bottom,
      'right' => cx >= screen.right - hotZone &&
          cy >= screen.top &&
          cy <= screen.bottom,
      _ => cy >= screen.bottom - hotZone &&
          cx >= screen.left &&
          cx <= screen.right,
    };

    if (atEdge) {
      if (_cfg.autoHide && _isAutoHidden) {
        _autoHideDelayTimer?.cancel();
        setState(() => _isAutoHidden = false);
        _syncWindowGeometry();
      }
      if (_cfg.popupOnMouseover && _cfg.layer != 'top' && !_isPopupRaised) {
        _popupDelayTimer ??= Timer(Duration(milliseconds: _cfg.popupDelayMs), () {
          _popupDelayTimer = null;
          if (!mounted) return;
          _isPopupRaised = true;
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
          item.target.isNotEmpty) {
        // Re-extract if missing OR if still pointing to an old blurry 32px ico_* cache file
        final needsUpgrade = item.iconPath == null ||
            !safeFileExists(item.iconPath) ||
            p.basename(item.iconPath!).startsWith('ico_');
        if (needsUpgrade) {
          final png = Win32Bridge.extractIconToPng(item.target, widget.store.iconsCacheDir);
          if (png != item.iconPath) {
            item.iconPath = png;
            changed = true;
          }
        }
      }
    }
    if (changed && mounted) {
      setState(() {});
      // Never overwrite Settings.ini while standalone Settings window is open,
      // and always merge ONLY this dock's items so panel positions are never clobbered!
      if (_settingsProcess == null) {
        unawaited(widget.store.saveDockItemsOnly(_dockId, skipProfileSync: true));
      }
    }
  }

  // ============================================================================
  // Activation & Drag-n-Drop
  // ============================================================================

  void _triggerClickEffect(String key) {
    if (_cfg.clickEffect == 'none') return;
    setState(() => _bouncingKey = key);
    Future.delayed(const Duration(milliseconds: 420), () {
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
        await _openSettingsTab(0);
        return;
      case 'dev_settings':
        await _openSettingsTab(2);
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
        if (safeDirExists(item.target)) {
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

    if (item.target.startsWith('http://') || item.target.startsWith('https://')) {
      final uri = Uri.tryParse(item.target);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final shouldOpenRunning = item.openRunning == 'always' ||
        (item.openRunning == 'global' && widget.store.global.openRunningInstance);

    if (shouldOpenRunning) {
      final exeName = item.executableName;
      if (exeName != null) {
        final minMatch = _minimizedWindows.where((m) => m.processName == exeName).firstOrNull;
        if (minMatch != null) {
          _restoreMinimizedEntry(minMatch);
          return;
        }
        final openMatch = _openWindows.where((w) => w.processName == exeName).firstOrNull;
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

  /// Find which regular item index sits under local axis coordinate [axisPos].
  int? _hitTestItemIndex(double? axisPos) {
    if (axisPos == null) return null;
    var cursor = 0.0;
    for (var i = 0; i < _items.length; i++) {
      final w = _items[i].type == 'separator' ? _sepStride : _slotStride;
      if (axisPos >= cursor && axisPos <= cursor + w) {
        return _items[i].type == 'separator' ? null : i;
      }
      cursor += w;
    }
    return null;
  }

  Future<void> _importRocketDock135ViaPicker() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите Settings.ini (RocketDock 1.3.5 или AeroDock)',
      type: FileType.custom,
      allowedExtensions: ['ini', 'reg'],
    );
    if (res == null || res.files.single.path == null) return;
    final importRes = await widget.store.importRocketDock135Ini(
      File(res.files.single.path!),
      targetDockId: _dockId,
    );
    AppI18n.currentCode = widget.store.global.language;
    _externalSkins = widget.store.scanExternalSkins();
    await _refreshDisplaysAndWorkArea();
    if (_isPrimary) {
      await _reconcileSiblingDocks();
      await _rebuildTrayMenu();
    }
    _extractMissingIcons();
    if (mounted) setState(() {});
    _applyLayerAndAcrylic();
    await _syncWindowGeometry();
    _showToast(importRes.message);
  }

  Future<void> _handleExternalDrop(DropDoneDetails details) async {
    setState(() => _isDraggingFile = false);
    final paths = details.files.map((f) => f.path).where((s) => s.isNotEmpty).toList();
    if (paths.isEmpty) return;

    // Auto-import RocketDock 1.3.5 OR AeroDock Settings.ini if dropped directly onto the dock!
    final firstExt = p.extension(paths.first).toLowerCase();
    if (paths.length == 1 && (firstExt == '.ini' || firstExt == '.reg')) {
      try {
        final iniFile = File(paths.first);
        final sections = PortableIniStore.parseIniText(
          decodeWindowsIniBytes(await iniFile.readAsBytes()),
        );
        if (PortableIniStore.isRocketDock135Ini(sections) ||
            PortableIniStore.isAeroDockIni(sections)) {
          final importRes = await widget.store.importRocketDock135Ini(
            iniFile,
            targetDockId: _dockId,
          );
          AppI18n.currentCode = widget.store.global.language;
          _externalSkins = widget.store.scanExternalSkins();
          await _refreshDisplaysAndWorkArea();
          if (_isPrimary) {
            await _reconcileSiblingDocks();
            await _rebuildTrayMenu();
          }
          _extractMissingIcons();
          if (mounted) setState(() {});
          _applyLayerAndAcrylic();
          await _syncWindowGeometry();
          _showToast(importRes.message);
          return;
        }
      } catch (_) {}
    }

    final hoveredIdx = _hitTestItemIndex(_hoverAxisNotifier.value);
    if (hoveredIdx != null && hoveredIdx >= 0 && hoveredIdx < _items.length) {
      final targetItem = _items[hoveredIdx];
      if (targetItem.type == 'recycle_bin') {
        Win32Bridge.sendFilesToRecycleBin(paths);
        _triggerClickEffect(targetItem.id);
        _pollRecycleBinNow();
        return;
      }
      if ((targetItem.type == 'path' || targetItem.type == 'docklet_stack') &&
          safeDirExists(targetItem.target)) {
        await Win32Bridge.copyFilesToFolder(paths, targetItem.target);
        _triggerClickEffect(targetItem.id);
        return;
      }
      if (targetItem.type == 'file' && targetItem.target.isNotEmpty) {
        final quoted = paths.map((e) => '"$e"').join(' ');
        final fullArgs = targetItem.args.isEmpty ? quoted : '${targetItem.args} $quoted';
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

    for (final filePath in paths) {
      final isDir = safeIsDirectory(filePath);
      final name = isDir ? p.basename(filePath) : p.basenameWithoutExtension(filePath);
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

    await widget.store.saveDockItemsOnly(_dockId);
    setState(() {});
    await _syncWindowGeometry();
  }

  /// Open Settings in a dedicated standalone floating window so ALL docks stay visible on screen
  /// and update visually in real time as the user adjusts size, edge, theme, or zoom!
  Future<void> _openSettingsTab(int tab) async {
    try {
      // Never overwrite Settings.ini with potentially stale memory before launching --settings!
      if (await widget.store.hasExternalChanges()) {
        await widget.store.reloadFromDisk();
      }
      if (_settingsProcess != null) {
        try {
          _settingsProcess!.kill();
        } catch (_) {}
        _settingsProcess = null;
      }
      final proc = await Process.start(
        Platform.resolvedExecutable,
        ['--settings', '--dock=$_dockId', '--tab=$tab'],
      );
      _settingsProcess = proc;
      proc.exitCode.then((_) {
        if (_settingsProcess == proc) _settingsProcess = null;
      });
    } catch (_) {
      // Fallback to in-window overlay only if process launch fails
      _settingsInitialTab = tab;
      await _openOverlay(_ActiveOverlay.settings);
    }
  }

  Future<void> _openOverlay(_ActiveOverlay next) async {
    _hoverAxisNotifier.value = null;
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
    await _refreshDisplaysAndWorkArea();
    await _syncWindowGeometry();
  }

  // ============================================================================
  // Context Menus
  // ============================================================================

  Future<void> _showDockContextMenu(
    Offset globalPos, {
    DockItemModel? item,
    _MinimizedWindowEntry? minWin,
  }) async {
    final entries = <PopupMenuEntry<String>>[];

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

    if (item != null) {
      if (item.type != 'separator') {
        entries.add(PopupMenuItem(value: 'item_edit', child: Text('${AppI18n.t('icon_settings')}…')));
      }
      if (item.devRuleId != null) {
        entries.addAll(const [
          PopupMenuItem(value: 'dev_open_app_dir', child: Text('📂 Открыть папку программы')),
          PopupMenuItem(value: 'dev_open_backups', child: Text('🗂 Открыть бэкапы (старые версии)')),
          PopupMenuItem(value: 'dev_rollback', child: Text('⏪ Откатить к прошлой версии')),
          PopupMenuItem(value: 'open_dev_settings', child: Text('⚙ Правила «Разработка»…')),
        ]);
      }
      if (item.type == 'recycle_bin' && item.popupMenu) {
        entries.add(
          PopupMenuItem(
            value: 'empty_bin',
            child: Text('${AppI18n.t('empty_recycle_bin')} (${_recycleBinNotifier.value.itemCount})'),
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

    final g = widget.store.global;
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
        value: 'toggle_dock2',
        child: Text('🖥 Панель 2 (Справа)${g.dock2Enabled ? ' ✓' : ''}'),
      ),
      PopupMenuItem(
        value: 'toggle_dock3',
        child: Text('🖥 Панель 3 (Сверху)${g.dock3Enabled ? ' ✓' : ''}'),
      ),
      PopupMenuItem(
        value: 'toggle_dock4',
        child: Text('⚡ Панель «Разработка» (Слева)${g.devDockEnabled ? ' ✓' : ''}'),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'import_rd135',
        child: const Text('📥 Импорт Settings.ini (RocketDock 1.3.5 / AeroDock)…'),
      ),
      PopupMenuItem(
        value: 'open_dev_settings',
        child: const Text('⚙ Правила «Разработка» (GitHub)…'),
      ),
      PopupMenuItem(
        value: 'open_backup_settings',
        child: const Text('💾 Бэкапы и восстановление…'),
      ),
      PopupMenuItem(
        value: 'toggle_lock',
        child: Text('${AppI18n.t('lock_items')}${g.lockItems ? ' ✓' : ''}'),
      ),
      PopupMenuItem(
        value: 'toggle_autohide',
        child: Text('${AppI18n.t('auto_hide')}${_cfg.autoHide ? ' ✓' : ''}'),
      ),
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
        _pollRecycleBinNow();
        break;
      case 'item_delete':
        if (item != null) {
          _items.removeWhere((e) => e.id == item.id);
          await widget.store.saveDockItemsOnly(_dockId);
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
          await widget.store.saveDockItemsOnly(_dockId);
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
          await widget.store.saveDockItemsOnly(_dockId);
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
        await widget.store.saveDockItemsOnly(_dockId);
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
        await widget.store.saveDockItemsOnly(_dockId);
        _pollRecycleBinNow();
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
        await widget.store.saveDockItemsOnly(_dockId);
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
        await widget.store.saveDockItemsOnly(_dockId);
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_dk_clock':
        _items.add(DockItemModel(id: 'dk_clk_${DateTime.now().millisecondsSinceEpoch}', type: 'docklet_clock', title: 'Часы', iconKey: 'clock'));
        await widget.store.saveDockItemsOnly(_dockId);
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_dk_battery':
        _items.add(DockItemModel(id: 'dk_bat_${DateTime.now().millisecondsSinceEpoch}', type: 'docklet_battery', title: 'Батарея', iconKey: 'star'));
        await widget.store.saveDockItemsOnly(_dockId);
        _pollStatsNow();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_dk_sysstats':
        _items.add(DockItemModel(id: 'dk_sys_${DateTime.now().millisecondsSinceEpoch}', type: 'docklet_sysstats', title: 'CPU / RAM', iconKey: 'terminal'));
        await widget.store.saveDockItemsOnly(_dockId);
        _pollStatsNow();
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'add_dk_calendar':
        _items.add(DockItemModel(id: 'dk_cal_${DateTime.now().millisecondsSinceEpoch}', type: 'docklet_calendar', title: 'Календарь', iconKey: 'book'));
        await widget.store.saveDockItemsOnly(_dockId);
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
          await widget.store.saveDockItemsOnly(_dockId);
          setState(() {});
          await _syncWindowGeometry();
        }
        break;
      case 'pos_bottom':
      case 'pos_top':
      case 'pos_left':
      case 'pos_right':
        _cfg.position = choice.substring(4);
        await widget.store.savePanelConfigOnly(_dockId);
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'toggle_lock':
        await widget.store.saveGlobalChange((g) => g.lockItems = !g.lockItems);
        setState(() {});
        break;
      case 'toggle_autohide':
        _cfg.autoHide = !_cfg.autoHide;
        _isAutoHidden = false;
        await widget.store.savePanelConfigOnly(_dockId);
        setState(() {});
        await _syncWindowGeometry();
        break;
      case 'dev_open_app_dir':
        if (item?.devRuleId != null) {
          final rule = widget.store.devSettings.rules
              .where((r) => r.id == item!.devRuleId)
              .firstOrNull;
          if (rule != null) {
            final watcher = _devWatcher ?? DevArchiveWatcher(store: widget.store, onDeployed: (_) {});
            final dir = watcher.appDirectoryFor(rule);
            if (!dir.existsSync()) dir.createSync(recursive: true);
            Win32Bridge.shellExecute(target: dir.path);
          }
        }
        break;
      case 'dev_open_backups':
        if (item?.devRuleId != null) {
          final rule = widget.store.devSettings.rules
              .where((r) => r.id == item!.devRuleId)
              .firstOrNull;
          if (rule != null) {
            final watcher = _devWatcher ?? DevArchiveWatcher(store: widget.store, onDeployed: (_) {});
            final dir = watcher.backupsDirectoryFor(rule);
            if (!dir.existsSync()) dir.createSync(recursive: true);
            Win32Bridge.shellExecute(target: dir.path);
          }
        }
        break;
      case 'dev_rollback':
        if (item?.devRuleId != null) {
          final rule = widget.store.devSettings.rules
              .where((r) => r.id == item!.devRuleId)
              .firstOrNull;
          if (rule != null) {
            final watcher = _devWatcher ?? DevArchiveWatcher(store: widget.store, onDeployed: (_) {});
            final restored = await watcher.rollbackLatestBackup(rule);
            _showToast(
              restored != null
                  ? 'Откат «${rule.name}» выполнен: $restored'
                  : 'Для «${rule.name}» пока нет сохранённых бэкапов.',
            );
          }
        }
        break;
      case 'toggle_dock2':
        await widget.store.saveGlobalChange((g) => g.dock2Enabled = !g.dock2Enabled);
        if (_isPrimary) {
          await _reconcileSiblingDocks();
          await _rebuildTrayMenu();
        }
        setState(() {});
        break;
      case 'toggle_dock3':
        await widget.store.saveGlobalChange((g) => g.dock3Enabled = !g.dock3Enabled);
        if (_isPrimary) {
          await _reconcileSiblingDocks();
          await _rebuildTrayMenu();
        }
        setState(() {});
        break;
      case 'toggle_dock4':
        await widget.store.saveGlobalChange((g) => g.devDockEnabled = !g.devDockEnabled);
        if (_isPrimary) {
          await _reconcileSiblingDocks();
          await _rebuildTrayMenu();
        }
        setState(() {});
        break;
      case 'import_rd135':
        await _importRocketDock135ViaPicker();
        break;
      case 'open_dev_settings':
        await _openSettingsTab(2);
        break;
      case 'open_backup_settings':
        await _openSettingsTab(7);
        break;
      case 'open_settings':
        await _openSettingsTab(0);
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
            await widget.store.saveDockItemsOnly(_dockId);
            setState(() {});
            await _syncWindowGeometry();
          }
        }
        break;
    }
  }

  // ============================================================================
  // Theme / Skin Shelf Decoration & Label Builder
  // ============================================================================

  BoxDecoration _resolveDockSurface() {
    final alpha = (_cfg.bgOpacity / 100.0).clamp(0.0, 1.0);
    if (_cfg.theme.startsWith('skin:')) {
      final skin = _externalSkins.where((s) => s.id == _cfg.theme).firstOrNull;
      if (skin != null && safeFileExists(skin.imagePath)) {
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
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.28 * alpha),
              const Color(0xFF0F172A).withValues(alpha: 0.62 * alpha),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.36 * alpha)),
        );
      case 'graphite':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF0F172A).withValues(alpha: 0.90 * alpha),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16 * alpha)),
        );
      case 'silk':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFFF8FAFC).withValues(alpha: 0.82 * alpha),
          border: Border.all(color: Colors.white.withValues(alpha: 0.90 * alpha)),
        );
      case 'minimal':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF0F172A).withValues(alpha: 0.42 * alpha),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14 * alpha)),
        );
      case 'retro':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF94A3B8).withValues(alpha: alpha),
              const Color(0xFF475569).withValues(alpha: alpha),
              const Color(0xFF1E293B).withValues(alpha: alpha),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.45 * alpha)),
        );
      case 'aero3d':
      default:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFE2E8F0).withValues(alpha: 0.28 * alpha),
              const Color(0xFF1E293B).withValues(alpha: 0.68 * alpha),
              const Color(0xFF020617).withValues(alpha: 0.78 * alpha),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.34 * alpha)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.44 * alpha),
              blurRadius: 16,
              offset: const Offset(0, 6),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: outlineColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
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
        ),
      ),
    );
  }

  String _resolveHoverTitle(DockItemModel item) {
    switch (item.type) {
      case 'recycle_bin':
        final cnt = _recycleBinNotifier.value.itemCount;
        return cnt == 0
            ? '${item.title} (${AppI18n.t('recycle_empty')})'
            : '${item.title} ($cnt)';
      case 'docklet_battery':
        final b = _batteryNotifier.value;
        return b.hasBattery
            ? '${item.title}: ${b.percent}%${b.acOnline ? ' (Сеть)' : ''}'
            : '${item.title}: От сети (AC)';
      case 'docklet_sysstats':
        final s = _sysStatsNotifier.value;
        return 'CPU ${s.cpuPercent}% · RAM ${s.ramPercent}% (${s.usedGb.toStringAsFixed(1)}/${s.totalGb.toStringAsFixed(1)} ГБ)';
      case 'docklet_clock':
        final n = _nowNotifier.value;
        return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}:${n.second.toString().padLeft(2, '0')}';
      default:
        return item.title;
    }
  }

  // ============================================================================
  // Main Build (GPU-Accelerated 60fps Wave Zoom, Zero Layout Reflow, Zero Clipping!)
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    if (_suspended) return const SizedBox.shrink();

    if (_overlay != _ActiveOverlay.none) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: switch (_overlay) {
            _ActiveOverlay.settings => DockSettingsDialog(
                store: widget.store,
                activeDockId: _dockId,
                initialTab: _settingsInitialTab,
                displays: _displays,
                devWatcher: _devWatcher,
                onSaved: () async {
                  _externalSkins = widget.store.scanExternalSkins();
                  await _refreshDisplaysAndWorkArea();
                  if (_isPrimary) {
                    await _reconcileSiblingDocks();
                    await _rebuildTrayMenu();
                  }
                  _extractMissingIcons();
                  _applyLayerAndAcrylic();
                  if (mounted) setState(() {});
                },
                onResetDefaults: () async {
                  await widget.store.resetSettingsToDefaultsOnly();
                  await _refreshDisplaysAndWorkArea();
                  _applyLayerAndAcrylic();
                  if (mounted) setState(() {});
                },
                onFullReset: () async {
                  await widget.store.fullReset();
                  await _refreshDisplaysAndWorkArea();
                  if (_isPrimary) {
                    await _reconcileSiblingDocks();
                    await _rebuildTrayMenu();
                  }
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
                  await widget.store.saveDockItemsOnly(_dockId);
                  _pollStatsNow();
                  _pollRecycleBinNow();
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
            _ActiveOverlay.calendar => ValueListenableBuilder<DateTime>(
                valueListenable: _nowNotifier,
                builder: (_, now, __) => CalendarPopover(now: now, onClose: _closeOverlay),
              ),
            _ => const SizedBox.shrink(),
          },
        ),
      );
    }

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
              width: _isHorizontal ? 96 : 3,
              height: _isHorizontal ? 3 : 96,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingFile = true),
        onDragExited: (_) => setState(() => _isDraggingFile = false),
        onDragDone: _handleExternalDrop,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition),
          child: RepaintBoundary(
            child: ValueListenableBuilder<double?>(
              valueListenable: _hoverAxisNotifier,
              builder: (context, hoverAxis, _) => _buildDockScene(hoverAxis),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDockScene(double? hoverAxis) {
    final slotCenters = <double>[];
    var cursor = 0.0;
    for (final it in _items) {
      final w = it.type == 'separator' ? _sepStride : _slotStride;
      slotCenters.add(cursor + w / 2);
      cursor += w;
    }
    if (_isPrimary && _minimizedWindows.isNotEmpty) {
      cursor += _sepStride;
      for (var j = 0; j < _minimizedWindows.length; j++) {
        slotCenters.add(cursor + _slotStride / 2);
        cursor += _slotStride;
      }
    }
    final stripLength = cursor;

    // Determine hovered label text
    String? hoveredLabel;
    if (_cfg.showLabels && hoverAxis != null) {
      final idx = _hitTestItemIndex(hoverAxis);
      if (idx != null) {
        hoveredLabel = _resolveHoverTitle(_items[idx]);
      } else if (_isPrimary && _minimizedWindows.isNotEmpty) {
        final minStart = stripLength - _minimizedWindows.length * _slotStride;
        if (hoverAxis >= minStart && hoverAxis <= stripLength) {
          final mIdx = ((hoverAxis - minStart) ~/ _slotStride)
              .clamp(0, _minimizedWindows.length - 1);
          hoveredLabel = _minimizedWindows[mIdx].title;
        }
      }
    }

    final shelfCross = _effectiveIconSize * 0.72 + 12;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        // Floating hover label or Dev/Import toast (always cleanly above shelf)
        if (_toastMessage != null || hoveredLabel != null)
          Align(
            alignment: switch (_cfg.position) {
              'top' => Alignment.bottomCenter,
              'left' => Alignment.centerRight,
              'right' => Alignment.centerLeft,
              _ => Alignment.topCenter,
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: _toastMessage != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xEE4C1D95),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xCCA78BFA)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x88000000), blurRadius: 10, offset: Offset(0, 3)),
                        ],
                      ),
                      child: Text(
                        _toastMessage!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : _buildStyledLabel(hoveredLabel!),
            ),
          ),

        // RocketDock 3D Shelf + Icons Strip aligned cleanly to screen edge
        Align(
          alignment: switch (_cfg.position) {
            'top' => Alignment.topCenter,
            'left' => Alignment.centerLeft,
            'right' => Alignment.centerRight,
            _ => Alignment.bottomCenter,
          },
          child: MouseRegion(
            onHover: (e) {
              final raw = _isHorizontal ? e.localPosition.dx : e.localPosition.dy;
              final adjusted = raw - 18.0; // matches outer padding
              if (_hoverAxisNotifier.value != adjusted) {
                _hoverAxisNotifier.value = adjusted;
              }
            },
            onExit: (_) {
              _hoverAxisNotifier.value = null;
              if (_isPopupRaised) {
                _isPopupRaised = false;
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
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _isHorizontal ? 18 : 6,
                vertical: _isHorizontal ? 6 : 18,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: switch (_cfg.position) {
                  'top' => Alignment.topCenter,
                  'left' => Alignment.centerLeft,
                  'right' => Alignment.centerRight,
                  _ => Alignment.bottomCenter,
                },
                children: [
                  // Sleek RocketDock Aero glass shelf behind lower 72% of icons
                  Positioned(
                    left: _isHorizontal ? -10 : (_cfg.position == 'left' ? 0 : null),
                    right: _isHorizontal ? -10 : (_cfg.position == 'right' ? 0 : null),
                    top: !_isHorizontal ? -10 : (_cfg.position == 'top' ? 0 : null),
                    bottom: !_isHorizontal ? -10 : (_cfg.position == 'bottom' ? 0 : null),
                    width: _isHorizontal ? null : shelfCross,
                    height: _isHorizontal ? shelfCross : null,
                    child: DecoratedBox(
                      decoration: _resolveDockSurface().copyWith(
                        border: _isDraggingFile
                            ? Border.all(color: const Color(0xFF38BDF8), width: 2)
                            : null,
                      ),
                    ),
                  ),

                  // Icons strip (zero layout reflow on hover — pure GPU Transform!)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: _isHorizontal ? 96 : 0,
                      minHeight: _isHorizontal ? 0 : 96,
                    ),
                    child: _buildIconsAxis(hoverAxis, slotCenters),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _waveFactor(double? hoverAxis, double slotCenter) {
    if (hoverAxis == null || _cfg.hoverEffect == 'none') return 0.0;
    final radiusPx = math.max(1.0, _cfg.zoomWidth) * _slotStride;
    final dist = (hoverAxis - slotCenter).abs();
    if (dist >= radiusPx) return 0.0;
    return (math.cos((dist / radiusPx) * math.pi) + 1.0) * 0.5;
  }

  Widget _buildIconsAxis(double? hoverAxis, List<double> slotCenters) {
    final children = <Widget>[];
    for (var i = 0; i < _items.length; i++) {
      final wave = _waveFactor(hoverAxis, slotCenters[i]);
      children.add(_buildRegularSlot(i, _items[i], wave));
    }

    if (_isPrimary && _minimizedWindows.isNotEmpty) {
      children.add(_buildDividerVisual());
      for (var j = 0; j < _minimizedWindows.length; j++) {
        final wave = _waveFactor(hoverAxis, slotCenters[_items.length + j]);
        children.add(_buildMinimizedWindowSlot(j, _minimizedWindows[j], wave));
      }
    }

    if (_isHorizontal) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: _cfg.position == 'bottom' ? 8 : 0,
          top: _cfg.position == 'top' ? 8 : 0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: _cfg.position == 'top'
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: children,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: _cfg.position == 'left' ? 8 : 0,
        right: _cfg.position == 'right' ? 8 : 0,
      ),
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
    final base = _effectiveIconSize;
    return SizedBox(
      width: _isHorizontal ? _sepStride : base,
      height: _isHorizontal ? base : _sepStride,
      child: Center(
        child: Container(
          width: _isHorizontal ? 1.5 : base * 0.65,
          height: _isHorizontal ? base * 0.65 : 1.5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Alignment get _zoomAnchor => switch (_cfg.position) {
        'top' => Alignment.topCenter,
        'left' => Alignment.centerLeft,
        'right' => Alignment.centerRight,
        _ => Alignment.bottomCenter,
      };

  Widget _buildRunningDot(String? exe) {
    final showDot = widget.store.global.showRunningIndicators && exe != null;
    return SizedBox(
      width: _isHorizontal ? null : 7,
      height: _isHorizontal ? 7 : null,
      child: showDot
          ? ValueListenableBuilder<Set<String>>(
              valueListenable: _runningProcsNotifier,
              builder: (_, running, __) {
                if (!running.contains(exe)) return const SizedBox.shrink();
                return Center(
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFF38BDF8),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0xCC38BDF8), blurRadius: 5)],
                    ),
                  ),
                );
              },
            )
          : null,
    );
  }

  Widget _alignSlotWithEdge(Widget iconArt, Widget indicator) {
    switch (_cfg.position) {
      case 'top':
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [indicator, iconArt],
        );
      case 'left':
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [indicator, iconArt],
        );
      case 'right':
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [iconArt, indicator],
        );
      case 'bottom':
      default:
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [iconArt, indicator],
        );
    }
  }

  Widget _buildRegularSlot(int index, DockItemModel item, double wave) {
    if (item.type == 'separator') {
      return GestureDetector(
        onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition, item: item),
        child: _buildDividerVisual(),
      );
    }

    final base = _effectiveIconSize;
    final scale = _cfg.hoverEffect == 'bubble'
        ? 1.0 + (_cfg.zoomScale - 1.0) * wave
        : 1.0;
    final liftPx = _cfg.hoverEffect == 'none' ? 0.0 : wave * (base * 0.16);
    final isBouncing = _bouncingKey == item.id;
    final bounceOffset = isBouncing && _cfg.clickEffect == 'bounce' ? -10.0 : 0.0;

    final dx = switch (_cfg.position) {
      'left' => liftPx,
      'right' => -liftPx,
      _ => 0.0,
    };
    final dy = switch (_cfg.position) {
      'top' => liftPx - bounceOffset,
      'bottom' => -liftPx + bounceOffset,
      _ => bounceOffset,
    };

    final effectiveOpacity = (wave > 0.2 && _cfg.zoomOpaque)
        ? 1.0
        : (_cfg.iconOpacity / 100.0).clamp(0.2, 1.0);

    final exe = item.executableName;

    final art = Opacity(
      opacity: effectiveOpacity,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Transform.scale(
          scale: scale * (isBouncing && _cfg.clickEffect == 'pulse' ? 1.12 : 1.0),
          alignment: _zoomAnchor,
          child: _renderItemArt(item, base),
        ),
      ),
    );

    final tile = SizedBox(
      width: _isHorizontal ? _slotStride : base + 10,
      height: _isHorizontal ? base + 10 : _slotStride,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _activateItem(item),
        onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition, item: item),
        child: _alignSlotWithEdge(art, _buildRunningDot(exe)),
      ),
    );

    return DragTarget<int>(
      onAcceptWithDetails: (details) async {
        final from = details.data;
        if (from == index || from < 0 || from >= _items.length) return;
        final moved = _items.removeAt(from);
        _items.insert(index, moved);
        await widget.store.saveDockItemsOnly(_dockId);
        setState(() {});
      },
      builder: (context, _, __) {
        return Draggable<int>(
          data: index,
          maxSimultaneousDrags:
              (!widget.store.global.lockItems || Win32Bridge.isCtrlPressed()) ? 1 : 0,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.85, child: _renderItemArt(item, base)),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: tile),
          onDragEnd: (details) async {
            if (!details.wasAccepted &&
                (!widget.store.global.lockItems || Win32Bridge.isCtrlPressed())) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final origin = box.localToGlobal(Offset.zero);
                if ((details.offset - origin).distance > base * 1.9) {
                  _items.removeWhere((e) => e.id == item.id);
                  await widget.store.saveDockItemsOnly(_dockId);
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

  Widget _buildMinimizedWindowSlot(int minIdx, _MinimizedWindowEntry entry, double wave) {
    final base = _effectiveIconSize;
    final scale = _cfg.hoverEffect == 'bubble'
        ? 1.0 + (_cfg.zoomScale - 1.0) * wave
        : 1.0;
    final liftPx = _cfg.hoverEffect == 'none' ? 0.0 : wave * (base * 0.16);

    final dx = switch (_cfg.position) {
      'left' => liftPx,
      'right' => -liftPx,
      _ => 0.0,
    };
    final dy = switch (_cfg.position) {
      'top' => liftPx,
      'bottom' => -liftPx,
      _ => 0.0,
    };

    final iconWidget = SizedBox(
      width: base,
      height: base,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (safeFileExists(entry.iconPngPath))
            Image(
              image: ResizeImage(FileImage(File(entry.iconPngPath!)), width: 160),
              width: base,
              height: base,
              fit: BoxFit.contain,
              filterQuality: _cfg.filterQuality,
              gaplessPlayback: true,
            )
          else
            DockGlyphTile(
              iconKey: 'windows',
              color: const Color(0xFF0284C7),
              size: base,
            ),
          // Clean subtle minimized badge
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF0EA5E9),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: const Icon(Icons.minimize_rounded, size: 9, color: Colors.white),
            ),
          ),
        ],
      ),
    );

    final transformed = Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.scale(
        scale: scale,
        alignment: _zoomAnchor,
        child: iconWidget,
      ),
    );

    final tile = SizedBox(
      width: _isHorizontal ? _slotStride : base + 10,
      height: _isHorizontal ? base + 10 : _slotStride,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _restoreMinimizedEntry(entry),
        onSecondaryTapDown: (d) => _showDockContextMenu(d.globalPosition, minWin: entry),
        child: _alignSlotWithEdge(
          transformed,
          SizedBox(width: _isHorizontal ? null : 7, height: _isHorizontal ? 7 : null),
        ),
      ),
    );

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
        feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.85, child: iconWidget)),
        childWhenDragging: Opacity(opacity: 0.25, child: tile),
        child: tile,
      ),
    );
  }

  Widget _renderItemArt(DockItemModel item, double size) {
    switch (item.type) {
      case 'docklet_clock':
        return ValueListenableBuilder<DateTime>(
          valueListenable: _nowNotifier,
          builder: (_, now, __) => ClockDockletIcon(now: now, size: size),
        );
      case 'docklet_battery':
        return ValueListenableBuilder<BatteryInfo>(
          valueListenable: _batteryNotifier,
          builder: (_, info, __) => BatteryDockletIcon(info: info, size: size),
        );
      case 'docklet_sysstats':
        return ValueListenableBuilder<SysStatsInfo>(
          valueListenable: _sysStatsNotifier,
          builder: (_, stats, __) => SysStatsDockletIcon(stats: stats, size: size),
        );
      case 'docklet_calendar':
        return ValueListenableBuilder<DateTime>(
          valueListenable: _nowNotifier,
          builder: (_, now, __) => CalendarDockletIcon(now: now, size: size),
        );
      case 'recycle_bin':
        return ValueListenableBuilder<RecycleBinInfo>(
          valueListenable: _recycleBinNotifier,
          builder: (_, info, __) => RecycleBinDockletIcon(
            info: info,
            item: item,
            size: size,
            quality: _cfg.filterQuality,
          ),
        );
      default:
        break;
    }

    if (safeFileExists(item.iconPath)) {
      return Image(
        image: ResizeImage(FileImage(File(item.iconPath!)), width: 160),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: _cfg.filterQuality,
        gaplessPlayback: true,
      );
    }

    return DockGlyphTile(
      iconKey: item.iconKey,
      color: parseHexColor(item.color),
      size: size,
    );
  }
}
