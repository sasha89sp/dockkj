import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'dev_watcher.dart';
import 'docklets.dart';
import 'i18n.dart';
import 'ini_storage.dart';
import 'win32_bridge.dart';

// ============================================================================
// 1. RocketDock Dock Settings Dialog (8 Tabs + Multi-Dock 1..3 + Dev Panel + RD 1.3.5 Import)
// ============================================================================

class DockSettingsDialog extends StatefulWidget {
  final PortableIniStore store;
  final int activeDockId;
  final int initialTab;
  final List<Display> displays;
  final DevArchiveWatcher? devWatcher;
  final bool isStandaloneWindow;
  final VoidCallback onSaved;
  final FutureOr<void> Function() onResetDefaults;
  final FutureOr<void> Function() onFullReset;
  final VoidCallback onClose;

  const DockSettingsDialog({
    super.key,
    required this.store,
    required this.activeDockId,
    this.initialTab = 0,
    required this.displays,
    this.devWatcher,
    this.isStandaloneWindow = false,
    required this.onSaved,
    required this.onResetDefaults,
    required this.onFullReset,
    required this.onClose,
  });

  @override
  State<DockSettingsDialog> createState() => _DockSettingsDialogState();
}

class _DockSettingsDialogState extends State<DockSettingsDialog> {
  late int _tab;
  late int _editingDockId;
  late GlobalDockSettings _global;
  late DevDockSettings _dev;
  late BackupSettings _backup;
  late Map<int, DockPanelConfig> _panels;
  late List<ExternalSkinInfo> _skins;
  List<BackupEntry> _backups = [];

  // Live preview & Cancel rollback snapshot
  String? _initialIniSnapshot;
  Timer? _liveSaveTimer;
  bool _liveDirty = false;
  bool _applyingLive = false;
  bool _pendingLive = false;

  // RocketDock 1.3.5 / AeroDock INI import state
  int _rdImportTargetDock = 1;
  bool _rdImportVisuals = true;
  bool _rdImportReplace = true;
  String? _statusBanner;
  bool _statusIsError = false;

  // Dev Panel & Backup controllers + add-rule form
  late TextEditingController _watchFolderCtrl;
  late TextEditingController _appsRootCtrl;
  late TextEditingController _preserveExtsCtrl;
  late TextEditingController _backupFolderCtrl;

  bool _showAddRuleForm = false;
  final TextEditingController _ruleNameCtrl = TextEditingController();
  final TextEditingController _rulePrefixCtrl = TextEditingController();
  final TextEditingController _ruleExeCtrl = TextEditingController();
  final TextEditingController _rulePatternsCtrl = TextEditingController();
  bool _ruleKeepBackup = true;
  bool _rulePreserveSettings = true;

  DockPanelConfig get _cfg => _panels[_editingDockId]!;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 7);
    _editingDockId = widget.activeDockId.clamp(1, 4);
    _rdImportTargetDock = widget.activeDockId.clamp(1, 4);
    _global = widget.store.global.copy();
    _dev = widget.store.devSettings.copy();
    _backup = widget.store.backupSettings.copy();
    _panels = {
      1: (widget.store.panels[1] ?? DockPanelConfig.defaultFor(1)).copy(),
      2: (widget.store.panels[2] ?? DockPanelConfig.defaultFor(2)).copy(),
      3: (widget.store.panels[3] ?? DockPanelConfig.defaultFor(3)).copy(),
      4: (widget.store.panels[4] ?? DockPanelConfig.defaultFor(4)).copy(),
    };
    _skins = widget.store.scanExternalSkins();
    _backups = widget.store.listBackups();

    try {
      if (widget.store.iniFile.existsSync()) {
        _initialIniSnapshot = widget.store.iniFile.readAsStringSync();
      }
    } catch (_) {}

    _watchFolderCtrl = TextEditingController(text: _dev.watchFolder);
    _appsRootCtrl = TextEditingController(text: _dev.appsRootFolder);
    _preserveExtsCtrl = TextEditingController(text: _dev.defaultPreserveExts);
    _backupFolderCtrl = TextEditingController(text: _backup.backupFolder);
  }

  @override
  void dispose() {
    _liveSaveTimer?.cancel();
    _watchFolderCtrl.dispose();
    _appsRootCtrl.dispose();
    _preserveExtsCtrl.dispose();
    _backupFolderCtrl.dispose();
    _ruleNameCtrl.dispose();
    _rulePrefixCtrl.dispose();
    _ruleExeCtrl.dispose();
    _rulePatternsCtrl.dispose();
    super.dispose();
  }

  void _syncTextControllersToDraft() {
    if (_watchFolderCtrl.text.trim().isNotEmpty) {
      _dev.watchFolder = _watchFolderCtrl.text.trim();
    }
    if (_appsRootCtrl.text.trim().isNotEmpty) {
      _dev.appsRootFolder = _appsRootCtrl.text.trim();
    }
    if (_preserveExtsCtrl.text.trim().isNotEmpty) {
      _dev.defaultPreserveExts = _preserveExtsCtrl.text.trim();
    }
    if (_backupFolderCtrl.text.trim().isNotEmpty) {
      _backup.backupFolder = _backupFolderCtrl.text.trim();
    }
  }

  /// Debounced real-time apply so all open docks visually update while dragging sliders/buttons!
  void _scheduleLiveApply({bool immediate = false}) {
    _liveDirty = true;
    _liveSaveTimer?.cancel();
    if (immediate) {
      _applyLiveNow();
    } else {
      _liveSaveTimer = Timer(const Duration(milliseconds: 80), _applyLiveNow);
    }
  }

  Future<void> _applyLiveNow() async {
    if (_applyingLive) {
      _pendingLive = true;
      return;
    }
    _applyingLive = true;
    try {
      _syncTextControllersToDraft();
      widget.store.global = _global.copy();
      widget.store.devSettings = _dev.copy();
      widget.store.backupSettings = _backup.copy();
      for (var id = 1; id <= 4; id++) {
        widget.store.panels[id] = _panels[id]!.copy();
      }
      AppI18n.currentCode = _global.language;
      await widget.store.save(skipProfileSync: true, preserveDiskItems: true);
      widget.onSaved();
    } finally {
      _applyingLive = false;
      if (_pendingLive) {
        _pendingLive = false;
        _applyLiveNow();
      }
    }
  }

  Future<void> _persistDraftToStore() async {
    _liveSaveTimer?.cancel();
    _pendingLive = false;
    // Wait for any in-flight live preview write to finish cleanly first
    var guard = 0;
    while (_applyingLive && guard < 40) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      guard++;
    }
    _syncTextControllersToDraft();
    widget.store.global = _global.copy();
    widget.store.devSettings = _dev.copy();
    widget.store.backupSettings = _backup.copy();
    for (var id = 1; id <= 4; id++) {
      widget.store.panels[id] = _panels[id]!.copy();
    }
    AppI18n.currentCode = _global.language;
    await Win32Bridge.setStartupEnabled(_global.launchWithWindows);
    await widget.store.save(preserveDiskItems: true);
    widget.onSaved();
  }

  Future<void> _saveAndClose() async {
    await _persistDraftToStore();
    _liveDirty = false;
    widget.onClose();
  }

  Future<void> _cancelAndRevert() async {
    _liveSaveTimer?.cancel();
    _pendingLive = false;
    var guard = 0;
    while (_applyingLive && guard < 40) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      guard++;
    }
    if (_liveDirty && _initialIniSnapshot != null) {
      try {
        await widget.store.iniFile.writeAsString(_initialIniSnapshot!, flush: true);
        await widget.store.reloadFromDisk();
        await widget.store.save();
        widget.onSaved();
      } catch (_) {}
    }
    widget.onClose();
  }

  Future<void> _createBackupNow() async {
    await _persistDraftToStore();
    final created = await widget.store.createBackup(tag: 'manual');
    if (!mounted) return;
    setState(() {
      _backup = widget.store.backupSettings.copy();
      _backups = widget.store.listBackups();
    });
    if (created != null) {
      _setBanner('Бэкап создан: ${created.name} (${(created.sizeBytes / 1024).ceil()} КБ)');
    } else {
      _setBanner('Не удалось создать бэкап. Проверьте права доступа к папке бэкапов.', isError: true);
    }
  }

  Future<void> _restoreBackup(BackupEntry entry) async {
    final ok = await widget.store.restoreBackup(entry.path);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _global = widget.store.global.copy();
        _dev = widget.store.devSettings.copy();
        _backup = widget.store.backupSettings.copy();
        _watchFolderCtrl.text = _dev.watchFolder;
        _appsRootCtrl.text = _dev.appsRootFolder;
        _preserveExtsCtrl.text = _dev.defaultPreserveExts;
        _backupFolderCtrl.text = _backup.backupFolder;
        for (var id = 1; id <= 4; id++) {
          _panels[id] = (widget.store.panels[id] ?? DockPanelConfig.defaultFor(id)).copy();
        }
        _backups = widget.store.listBackups();
        _liveDirty = false;
      });
      try {
        _initialIniSnapshot = widget.store.iniFile.readAsStringSync();
      } catch (_) {}
      widget.onSaved();
      _setBanner('Настройки и значки восстановлены из бэкапа: ${entry.name}');
    } else {
      _setBanner('Не удалось восстановить бэкап ${entry.name}.', isError: true);
    }
  }

  void _setBanner(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusBanner = message;
      _statusIsError = isError;
    });
  }

  Future<void> _importRocketDock135() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите Settings.ini (RocketDock 1.3.5 или AeroDock)',
      type: FileType.custom,
      allowedExtensions: ['ini', 'reg'],
    );
    if (res == null || res.files.single.path == null) return;

    _liveSaveTimer?.cancel();
    final importRes = await widget.store.importRocketDock135Ini(
      File(res.files.single.path!),
      targetDockId: _rdImportTargetDock,
      importVisualSettings: _rdImportVisuals,
      replaceExistingItems: _rdImportReplace,
    );

    // Refresh ALL local drafts & text controllers from the newly imported store!
    if (!mounted) return;
    setState(() {
      _global = widget.store.global.copy();
      _dev = widget.store.devSettings.copy();
      _backup = widget.store.backupSettings.copy();
      _watchFolderCtrl.text = _dev.watchFolder;
      _appsRootCtrl.text = _dev.appsRootFolder;
      _preserveExtsCtrl.text = _dev.defaultPreserveExts;
      _backupFolderCtrl.text = _backup.backupFolder;
      for (var id = 1; id <= 4; id++) {
        _panels[id] = (widget.store.panels[id] ?? DockPanelConfig.defaultFor(id)).copy();
      }
      if (importRes.ok) {
        _backups = widget.store.listBackups();
      }
      _statusBanner = importRes.message;
      _statusIsError = !importRes.ok;
    });
    if (importRes.ok) {
      try {
        _initialIniSnapshot = widget.store.iniFile.readAsStringSync();
      } catch (_) {}
      _liveDirty = false;
      widget.onSaved();
    }
  }

  Future<void> _addDevRule() async {
    final prefix = _rulePrefixCtrl.text.trim();
    if (prefix.isEmpty) {
      _setBanner('Укажите начало названия архива (например: AeroDock-Windows или MyApp-v).', isError: true);
      return;
    }
    final name = _ruleNameCtrl.text.trim().isEmpty ? prefix : _ruleNameCtrl.text.trim();
    final rule = DevAppRule(
      id: 'rule_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      archivePrefix: prefix,
      exeHint: _ruleExeCtrl.text.trim(),
      preservePatterns: _rulePatternsCtrl.text.trim(),
      preserveSettings: _rulePreserveSettings,
      keepBackup: _ruleKeepBackup,
    );
    setState(() {
      _dev.rules.add(rule);
      _global.devDockEnabled = true;
      _showAddRuleForm = false;
      _ruleNameCtrl.clear();
      _rulePrefixCtrl.clear();
      _ruleExeCtrl.clear();
      _rulePatternsCtrl.clear();
      _ruleKeepBackup = true;
      _rulePreserveSettings = true;
    });
    await _persistDraftToStore();
    _setBanner('Правило «$name» (префикс: $prefix*) добавлено! Скачивайте архив с GitHub — он установится сам.');
  }

  Future<void> _manualDeployForRule(DevAppRule rule) async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Выберите архив для «${rule.name}»',
      type: FileType.custom,
      allowedExtensions: ['zip', '7z', 'tar', 'gz', 'tgz', 'rar'],
    );
    if (res == null || res.files.single.path == null) return;
    await _persistDraftToStore();
    final watcher = widget.devWatcher ??
        DevArchiveWatcher(store: widget.store, onDeployed: (_) {});
    final storeRule = widget.store.devSettings.rules
        .cast<DevAppRule?>()
        .firstWhere((r) => r?.id == rule.id, orElse: () => null);
    if (storeRule == null) return;

    final ev = await watcher.deployArchive(File(res.files.single.path!), storeRule);
    if (ev == null) {
      _setBanner('Не удалось распаковать архив. Проверьте формат файла (.zip / .7z / .tar.gz).', isError: true);
      return;
    }
    setState(() {
      _dev = widget.store.devSettings.copy();
      _global = widget.store.global.copy();
    });
    widget.onSaved();
    final extra = ev.wasUpgrade
        ? ' (обновлено, бэкап сохранён, настроек перенесено: ${ev.preservedConfigCount})'
        : ' (установлено и добавлено в панель «Разработка»)';
    _setBanner('Готово: ${ev.rule.name}$extra');
  }

  Future<void> _rollbackRule(DevAppRule rule) async {
    await _persistDraftToStore();
    final watcher = widget.devWatcher ??
        DevArchiveWatcher(store: widget.store, onDeployed: (_) {});
    final restored = await watcher.rollbackLatestBackup(rule);
    if (restored == null) {
      _setBanner('Для «${rule.name}» пока нет сохранённых бэкапов старых версий.', isError: true);
    } else {
      _setBanner('«${rule.name}» успешно откачено к сохранённой версии: $restored');
    }
  }

  Future<void> _scanDownloadsNow() async {
    await _persistDraftToStore();
    final watcher = widget.devWatcher ??
        DevArchiveWatcher(store: widget.store, onDeployed: (_) {});
    final count = await watcher.scanOnce();
    setState(() {
      _dev = widget.store.devSettings.copy();
      _global = widget.store.global.copy();
    });
    if (count > 0) {
      widget.onSaved();
      _setBanner('Найдено и установлено новых архивов: $count!');
    } else {
      _setBanner('Новых архивов по правилам в папке загрузок сейчас не найдено.');
    }
  }

  String _dockShortLabel(int id) => switch (id) {
        1 => 'Панель 1',
        2 => 'Панель 2',
        3 => 'Панель 3',
        4 => 'Разработка',
        _ => 'Панель $id',
      };

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (Icons.tune_rounded, AppI18n.t('tab_general')),
      (Icons.view_quilt_rounded, 'Панели (1–3)'),
      (Icons.code_rounded, 'Разработка'),
      (Icons.apps_rounded, AppI18n.t('tab_icons')),
      (Icons.desktop_windows_rounded, AppI18n.t('tab_position')),
      (Icons.palette_rounded, AppI18n.t('tab_style')),
      (Icons.flash_on_rounded, AppI18n.t('tab_behavior')),
      (Icons.backup_rounded, 'Бэкап и сброс'),
    ];

    return Container(
      width: 790,
      height: 580,
      decoration: BoxDecoration(
        color: const Color(0xF70F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(color: Color(0xB3000000), blurRadius: 32, offset: Offset(0, 14)),
        ],
      ),
      child: Column(
        children: [
          // Header with Dock 1 / 2 / 3 / Разработка profile switcher (draggable when standalone)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: widget.isStandaloneWindow
                ? (_) => windowManager.startDragging()
                : null,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.rocket_launch_rounded, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    AppI18n.t('dock_settings'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x2210B981),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x5534D399)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 7, color: Color(0xFF34D399)),
                        SizedBox(width: 5),
                        Text(
                          'Живой предпросмотр',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF6EE7B7)),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var id = 1; id <= 4; id++)
                          GestureDetector(
                            onTap: () => setState(() => _editingDockId = id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: _editingDockId == id
                                    ? (id == 4
                                        ? const Color(0xFF7C3AED)
                                        : const Color(0xFF0284C7))
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(right: 5),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _global.isDockEnabled(id)
                                          ? (id == 4
                                              ? const Color(0xFFC4B5FD)
                                              : const Color(0xFF34D399))
                                          : Colors.white24,
                                    ),
                                  ),
                                  Text(
                                    _dockShortLabel(id),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _editingDockId == id
                                          ? Colors.white
                                          : (_global.isDockEnabled(id)
                                              ? Colors.white70
                                              : Colors.white38),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Сохранить и закрыть',
                    onPressed: _saveAndClose,
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                    splashRadius: 16,
                  ),
                ],
              ),
            ),
          ),

          // Optional feedback banner (for RocketDock INI import / Dev watcher results)
          if (_statusBanner != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: _statusIsError
                  ? const Color(0x55BE123C)
                  : const Color(0x44059669),
              child: Row(
                children: [
                  Icon(
                    _statusIsError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                    size: 16,
                    color: _statusIsError ? const Color(0xFFFDA4AF) : const Color(0xFF6EE7B7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusBanner!,
                      style: const TextStyle(fontSize: 11.5, color: Colors.white),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _statusBanner = null),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),

          // Body: Left sidebar + Tab content
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 170,
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0x18FFFFFF))),
                    color: Color(0x40020617),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() => _tab = i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8.5),
                              decoration: BoxDecoration(
                                color: _tab == i
                                    ? (i == 2
                                        ? const Color(0x337C3AED)
                                        : const Color(0x330EA5E9))
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _tab == i
                                      ? (i == 2
                                          ? const Color(0x88A78BFA)
                                          : const Color(0x6638BDF8))
                                      : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    tabs[i].$1,
                                    size: 16,
                                    color: _tab == i
                                        ? (i == 2
                                            ? const Color(0xFFC4B5FD)
                                            : const Color(0xFF7DD3FC))
                                        : Colors.white60,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tabs[i].$2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: _tab == i ? Colors.white : Colors.white70,
                                      ),
                                    ),
                                  ),
                                  if (i == 2 && _dev.rules.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0x557C3AED),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${_dev.rules.length}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFDDD6FE),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: switch (_tab) {
                      0 => _buildGeneralTab(),
                      1 => _buildPanelsTab(),
                      2 => _buildDevPanelTab(),
                      3 => _buildIconsTab(),
                      4 => _buildPositionTab(),
                      5 => _buildStyleTab(),
                      6 => _buildBehaviorTab(),
                      _ => _buildAboutDefaultsTab(),
                    },
                  ),
                ),
              ],
            ),
          ),

          // Footer buttons
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await widget.onResetDefaults();
                    widget.onClose();
                  },
                  icon: const Icon(Icons.restore_rounded, size: 16, color: Colors.white70),
                  label: Text(
                    AppI18n.t('defaults'),
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _cancelAndRevert,
                  child: Text(
                    AppI18n.t('cancel'),
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveAndClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA5E9),
                    foregroundColor: const Color(0xFF020617),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    AppI18n.t('save'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- TAB 0: General + RocketDock 1.3.5 INI Importer ----
  Widget _buildGeneralTab() {
    final langs = AppI18n.availableLanguages();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Prominent RocketDock 1.3.5 Settings.ini Import Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x280284C7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x6638BDF8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.file_upload_rounded, size: 17, color: Color(0xFF38BDF8)),
                  SizedBox(width: 7),
                  Text(
                    'Импорт Settings.ini (RocketDock 1.3.5 и AeroDock)',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              const Text(
                'Для Settings.ini AeroDock — переносит СРАЗУ ВСЕ 4 панели, их расположение, настройки и иконки. Для оригинального RocketDock 1.3.5 (.ini / .reg, UTF-16 / Windows-1251) — переносит ярлыки, иконки и положение в выбранную панель. Также можно перетащить .ini прямо на панель.',
                style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Импортировать в:', style: TextStyle(fontSize: 11.5, color: Colors.white70)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 155,
                    child: DropdownButtonFormField<int>(
                      value: _rdImportTargetDock,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(fontSize: 11.5, color: Colors.white),
                      decoration: _inputDeco(),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Панель 1 (Основная)')),
                        DropdownMenuItem(value: 2, child: Text('Панель 2 (Справа)')),
                        DropdownMenuItem(value: 3, child: Text('Панель 3 (Сверху)')),
                        DropdownMenuItem(value: 4, child: Text('Разработка (Слева)')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _rdImportTargetDock = v);
                      },
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _importRocketDock135,
                    icon: const Icon(Icons.folder_open_rounded, size: 15),
                    label: const Text('Выбрать .ini файл…', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF020617),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _rdImportVisuals,
                      activeColor: const Color(0xFF38BDF8),
                      title: const Text('Импортировать позицию и размер', style: TextStyle(fontSize: 11, color: Colors.white70)),
                      onChanged: (v) => setState(() => _rdImportVisuals = v ?? true),
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _rdImportReplace,
                      activeColor: const Color(0xFF38BDF8),
                      title: const Text('Заменить текущие значки панели', style: TextStyle(fontSize: 11, color: Colors.white70)),
                      onChanged: (v) => setState(() => _rdImportReplace = v ?? true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _sectionTitle(AppI18n.t('language')),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: langs.containsKey(_global.language) ? _global.language : 'ru',
          dropdownColor: const Color(0xFF1E293B),
          style: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: _inputDeco(),
          items: langs.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})')))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _global.language = v);
              _scheduleLiveApply(immediate: true);
            }
          },
        ),
        const SizedBox(height: 14),

        _switchRow(
          AppI18n.t('start_with_windows'),
          'Портативный ярлык в shell:startup (без записи в реестр)',
          _global.launchWithWindows,
          (v) {
            setState(() => _global.launchWithWindows = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _switchRow(
          AppI18n.t('portable_ini'),
          'Все настройки и ярлыки хранятся в Settings.ini рядом с aerodock.exe',
          _global.portableIni,
          (v) {
            setState(() => _global.portableIni = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _switchRow(
          AppI18n.t('minimize_to_dock'),
          'Свёрнутые окна попадают в панель (Ctrl+Alt+Shift — исключить навсегда, Ctrl — один раз)',
          _global.minimizeToDock,
          (v) {
            setState(() => _global.minimizeToDock = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _switchRow(
          AppI18n.t('disable_min_anim'),
          'Мгновенное скрытие окна в док без задержки анимации Windows',
          _global.disableMinimizeAnimation,
          (v) {
            setState(() => _global.disableMinimizeAnimation = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _switchRow(
          AppI18n.t('running_indicators'),
          'Светящаяся точка рядом с иконками запущенных программ',
          _global.showRunningIndicators,
          (v) {
            setState(() => _global.showRunningIndicators = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _switchRow(
          AppI18n.t('open_running'),
          'При клике активировать уже открытое окно вместо запуска копии',
          _global.openRunningInstance,
          (v) {
            setState(() => _global.openRunningInstance = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _switchRow(
          AppI18n.t('lock_items'),
          'Защита от случайного перемещения/удаления (удерживайте Ctrl для обхода)',
          _global.lockItems,
          (v) {
            setState(() => _global.lockItems = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
      ],
    );
  }

  // ---- TAB 1: Dedicated Multi-Dock Control (Panel 1, Panel 2, Panel 3, Dev Panel) ----
  Widget _buildPanelsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Управление дополнительными панелями (Multi-Dock)'),
        const SizedBox(height: 4),
        const Text(
          'Включайте и отключайте каждую панель по отдельности. После нажатия «Сохранить» включённые панели мгновенно появятся у выбранного края экрана (также их можно включать через ПКМ по панели или иконку в трее).',
          style: TextStyle(fontSize: 11, color: Colors.white60, height: 1.35),
        ),
        const SizedBox(height: 14),
        _buildPanelToggleCard(
          dockId: 1,
          title: 'Панель 1 — Основная',
          subtitle: 'Главная панель с ярлыками программ и системными значками (всегда включена).',
          enabled: true,
          canToggle: false,
          accent: const Color(0xFF38BDF8),
          onToggle: (_) {},
        ),
        _buildPanelToggleCard(
          dockId: 2,
          title: 'Панель 2 — Дополнительная',
          subtitle: 'Отдельная панель (по умолчанию справа) с часами, CPU/RAM, батареей и Загрузками.',
          enabled: _global.dock2Enabled,
          canToggle: true,
          accent: const Color(0xFF34D399),
          onToggle: (v) {
            setState(() => _global.dock2Enabled = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _buildPanelToggleCard(
          dockId: 3,
          title: 'Панель 3 — Дополнительная',
          subtitle: 'Третья независимая панель (по умолчанию сверху) для сайтов, игр или рабочих папок.',
          enabled: _global.dock3Enabled,
          canToggle: true,
          accent: const Color(0xFFFBBF24),
          onToggle: (v) {
            setState(() => _global.dock3Enabled = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _buildPanelToggleCard(
          dockId: 4,
          title: 'Панель «Разработка» — GitHub авто-установка',
          subtitle: 'Перехватывает скачанные с GitHub архивы, сохраняет бэкапы старых версий, переносит настройки и обновляет значки.',
          enabled: _global.devDockEnabled,
          canToggle: true,
          accent: const Color(0xFFA78BFA),
          onToggle: (v) {
            setState(() => _global.devDockEnabled = v);
            _scheduleLiveApply(immediate: true);
          },
          extraActionLabel: 'Правила GitHub →',
          onExtraAction: () => setState(() => _tab = 2),
        ),
      ],
    );
  }

  Widget _buildPanelToggleCard({
    required int dockId,
    required String title,
    required String subtitle,
    required bool enabled,
    required bool canToggle,
    required Color accent,
    required ValueChanged<bool> onToggle,
    String? extraActionLabel,
    VoidCallback? onExtraAction,
  }) {
    final panel = _panels[dockId]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? accent.withValues(alpha: 0.12) : const Color(0x331E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? accent.withValues(alpha: 0.55) : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled ? accent : Colors.white24,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.white60)),
                  ],
                ),
              ),
              if (canToggle)
                Switch(
                  value: enabled,
                  onChanged: onToggle,
                  activeColor: accent,
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Активна', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: accent)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Край:', style: TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(width: 8),
              for (final pos in [('bottom', 'Снизу'), ('top', 'Сверху'), ('left', 'Слева'), ('right', 'Справа')])
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      setState(() => panel.position = pos.$1);
                      _scheduleLiveApply(immediate: true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: panel.position == pos.$1
                            ? accent.withValues(alpha: 0.28)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: panel.position == pos.$1 ? accent : Colors.white12,
                        ),
                      ),
                      child: Text(
                        pos.$2,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: panel.position == pos.$1 ? Colors.white : Colors.white60,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (extraActionLabel != null && onExtraAction != null)
                TextButton(
                  onPressed: onExtraAction,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                  child: Text(extraActionLabel, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w700)),
                ),
              TextButton(
                onPressed: () => setState(() {
                  _editingDockId = dockId;
                  _tab = 5; // Jump to Style for this panel
                }),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                ),
                child: const Text('Стиль', style: TextStyle(fontSize: 11, color: Color(0xFF7DD3FC))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- TAB 2: Dev Panel ("Разработка" — GitHub Archive Interceptor & Safe Auto-Updater) ----
  Widget _buildDevPanelTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _switchRow(
          'Включить панель «Разработка» и перехват архивов GitHub',
          'Отслеживает загрузки, создаёт папку программы, распаковывает архив, сохраняет старые версии и переносит настройки',
          _global.devDockEnabled,
          (v) {
            setState(() => _global.devDockEnabled = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        const SizedBox(height: 8),

        // Folders configuration
        _fieldLabel('Папка загрузок браузера (откуда перехватывать архивы)'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _watchFolderCtrl,
                style: const TextStyle(fontSize: 11.5, color: Colors.white),
                decoration: _inputDeco(hint: r'C:\Users\...\Downloads'),
              ),
            ),
            const SizedBox(width: 6),
            _smallBtn('Обзор…', () async {
              final d = await FilePicker.platform.getDirectoryPath();
              if (d != null) setState(() => _watchFolderCtrl.text = d);
            }),
          ],
        ),
        const SizedBox(height: 10),

        _fieldLabel('Корневая папка для распаковки программ (и бэкапов _backups)'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _appsRootCtrl,
                style: const TextStyle(fontSize: 11.5, color: Colors.white),
                decoration: _inputDeco(hint: r'...\DevApps'),
              ),
            ),
            const SizedBox(width: 6),
            _smallBtn('Обзор…', () async {
              final d = await FilePicker.platform.getDirectoryPath();
              if (d != null) setState(() => _appsRootCtrl.text = d);
            }),
            const SizedBox(width: 4),
            _smallBtn('Открыть', () {
              final dir = Directory(_appsRootCtrl.text.trim());
              if (!dir.existsSync()) dir.createSync(recursive: true);
              Win32Bridge.shellExecute(target: dir.path);
            }),
          ],
        ),
        const SizedBox(height: 10),

        _fieldLabel('Расширения файлов настроек, переносимых при обновлении поверх старой версии'),
        TextField(
          controller: _preserveExtsCtrl,
          style: const TextStyle(fontSize: 11.5, color: Colors.white),
          decoration: _inputDeco(hint: '.ini,.json,.cfg,.conf,.xml,.yaml,.db,.sqlite,.env'),
        ),
        const SizedBox(height: 10),

        _sliderRow(
          'Макс. сохранённых бэкапов старых версий на программу',
          '${_dev.maxBackupsPerApp} шт.',
          _dev.maxBackupsPerApp.toDouble(),
          1,
          20,
          (v) {
            setState(() => _dev.maxBackupsPerApp = v.round());
            _scheduleLiveApply();
          },
        ),
        _switchRow(
          'Перемещать обработанные архивы в DevApps\\_archives',
          'Очищать папку Downloads после успешной распаковки (выкл — оставить копию в Downloads)',
          _dev.moveArchiveToStorage,
          (v) {
            setState(() => _dev.moveArchiveToStorage = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        const SizedBox(height: 8),

        // Rules header + actions
        Row(
          children: [
            Expanded(
              child: _sectionTitle('Правила перехвата приложений (${_dev.rules.length})'),
            ),
            OutlinedButton.icon(
              onPressed: _scanDownloadsNow,
              icon: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF7DD3FC)),
              label: const Text('Проверить сейчас', style: TextStyle(fontSize: 11, color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: () => setState(() => _showAddRuleForm = !_showAddRuleForm),
              icon: Icon(_showAddRuleForm ? Icons.close_rounded : Icons.add_rounded, size: 15),
              label: Text(_showAddRuleForm ? 'Скрыть форму' : 'Добавить правило', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Add-rule inline card
        if (_showAddRuleForm)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x2A7C3AED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x88A78BFA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Новое правило перехвата GitHub-архива',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDDD6FE)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('Начало названия архива * (префикс)'),
                          TextField(
                            controller: _rulePrefixCtrl,
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                            decoration: _inputDeco(hint: 'Например: MyApp-Windows или dock-portable'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('Название на панели «Разработка»'),
                          TextField(
                            controller: _ruleNameCtrl,
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                            decoration: _inputDeco(hint: 'Например: MyApp'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('Главный .exe (пусто = автопоиск)'),
                          TextField(
                            controller: _ruleExeCtrl,
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                            decoration: _inputDeco(hint: 'Например: myapp.exe'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel('Доп. файлы настроек (через запятую)'),
                          TextField(
                            controller: _rulePatternsCtrl,
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                            decoration: _inputDeco(hint: 'settings.txt, user.dat'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _ruleKeepBackup,
                        activeColor: const Color(0xFFA78BFA),
                        title: const Text('Сохранять старую версию в _backups', style: TextStyle(fontSize: 11, color: Colors.white)),
                        onChanged: (v) => setState(() => _ruleKeepBackup = v ?? true),
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _rulePreserveSettings,
                        activeColor: const Color(0xFFA78BFA),
                        title: const Text('Переносить настройки при обновлении', style: TextStyle(fontSize: 11, color: Colors.white)),
                        onChanged: (v) => setState(() => _rulePreserveSettings = v ?? true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _addDevRule,
                    icon: const Icon(Icons.check_rounded, size: 15),
                    label: const Text('Сохранить правило', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA78BFA),
                      foregroundColor: const Color(0xFF020617),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Rules list
        if (_dev.rules.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x281E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: const Text(
              'Правил пока нет. Нажмите «Добавить правило», введите начало имени архива (например, "MyTool-win") — и каждый раз, когда вы скачиваете новый релиз с GitHub в Downloads, AeroDock сам сохранит прошлую версию в _backups, распакует новую поверх, перенесёт настройки и выведет значок в панель «Разработка»!',
              style: TextStyle(fontSize: 11, color: Colors.white60, height: 1.4),
            ),
          )
        else
          for (var i = 0; i < _dev.rules.length; i++) _buildDevRuleCard(_dev.rules[i], i),
      ],
    );
  }

  Widget _buildDevRuleCard(DevAppRule rule, int index) {
    final watcher = widget.devWatcher ??
        DevArchiveWatcher(store: widget.store, onDeployed: (_) {});
    final appDir = watcher.appDirectoryFor(rule);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0x381E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.archive_rounded, size: 16, color: Color(0xFFC4B5FD)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  rule.name,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x337C3AED),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x66A78BFA)),
                ),
                child: Text(
                  '${rule.archivePrefix}*',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFDDD6FE)),
                ),
              ),
              if (rule.versionCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x33059669),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'v${rule.versionCount}',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            rule.lastArchiveName.isNotEmpty
                ? 'Последний архив: ${rule.lastArchiveName} (${rule.lastUpdated})'
                : 'Ожидает скачивания архива с префиксом «${rule.archivePrefix}» в Downloads',
            style: const TextStyle(fontSize: 10.5, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _smallBtn('Распаковать архив…', () => _manualDeployForRule(rule)),
              _smallBtn('Папка', () {
                if (!appDir.existsSync()) appDir.createSync(recursive: true);
                Win32Bridge.shellExecute(target: appDir.path);
              }),
              _smallBtn('Откатить бэкап', () => _rollbackRule(rule)),
              _smallBtn('Удалить', () {
                setState(() => _dev.rules.removeAt(index));
              }, danger: true),
            ],
          ),
        ],
      ),
    );
  }

  // ---- TAB 3: Icons (with Real-Time Live Preview) ----
  Widget _buildIconsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Качество отрисовки при зуме (${_dockShortLabel(_editingDockId)})'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final q in [('low', 'Быстрое'), ('medium', 'Среднее'), ('high', 'Высокое')])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _choiceChip(
                    label: q.$2,
                    selected: _cfg.renderQuality == q.$1,
                    onTap: () {
                      setState(() => _cfg.renderQuality = q.$1);
                      _scheduleLiveApply(immediate: true);
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _sliderRow(
          'Прозрачность значков (Opacity)',
          '${_cfg.iconOpacity.round()}%',
          _cfg.iconOpacity,
          20,
          100,
          (v) {
            setState(() => _cfg.iconOpacity = v);
            _scheduleLiveApply();
          },
        ),
        _switchRow(
          'Zoom Opaque (100% при наведении)',
          'Делать значок полностью непрозрачным во время увеличения',
          _cfg.zoomOpaque,
          (v) {
            setState(() => _cfg.zoomOpaque = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _sliderRow(
          'Базовый размер иконок',
          '${_cfg.iconSize.round()} px',
          _cfg.iconSize,
          32,
          96,
          (v) {
            setState(() => _cfg.iconSize = v);
            _scheduleLiveApply();
          },
        ),
        const SizedBox(height: 8),
        _sectionTitle('Эффект при наведении (Hover Effect)'),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final h in [('bubble', 'Волна (Bubble)'), ('lift', 'Подъём'), ('none', 'Нет')])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _choiceChip(
                    label: h.$2,
                    selected: _cfg.hoverEffect == h.$1,
                    onTap: () {
                      setState(() => _cfg.hoverEffect = h.$1);
                      _scheduleLiveApply(immediate: true);
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _sliderRow(
          'Величина увеличения (Zoom)',
          '${_cfg.zoomScale.toStringAsFixed(2)}×',
          _cfg.zoomScale,
          1.0,
          2.2,
          (v) {
            setState(() => _cfg.zoomScale = v);
            _scheduleLiveApply();
          },
        ),
        _sliderRow(
          'Ширина волны зума (Zoom Width)',
          '${_cfg.zoomWidth.toStringAsFixed(1)} ик.',
          _cfg.zoomWidth,
          1.0,
          6.0,
          (v) {
            setState(() => _cfg.zoomWidth = v);
            _scheduleLiveApply();
          },
        ),
        _sliderRow(
          'Длительность зума (Zoom Duration)',
          '${_cfg.zoomDurationMs} мс',
          _cfg.zoomDurationMs.toDouble(),
          60,
          400,
          (v) {
            setState(() => _cfg.zoomDurationMs = v.round());
            _scheduleLiveApply();
          },
        ),
      ],
    );
  }

  // ---- TAB 4: Position (with Real-Time Live Preview) ----
  Widget _buildPositionTab() {
    final monitorOptions = <DropdownMenuItem<int>>[
      DropdownMenuItem(value: -1, child: Text(AppI18n.t('monitor_all'))),
      for (var i = 0; i < (widget.displays.isEmpty ? 1 : widget.displays.length); i++)
        DropdownMenuItem(
          value: i,
          child: Text(
            widget.displays.isEmpty
                ? 'Монитор 1 (Основной)'
                : 'Монитор ${i + 1} (${widget.displays[i].size.width.round()}×${widget.displays[i].size.height.round()})',
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Монитор (${_dockShortLabel(_editingDockId)})'),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          value: monitorOptions.any((m) => m.value == _cfg.monitorIndex)
              ? _cfg.monitorIndex
              : 0,
          dropdownColor: const Color(0xFF1E293B),
          style: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: _inputDeco(),
          items: monitorOptions,
          onChanged: (v) {
            if (v != null) {
              setState(() => _cfg.monitorIndex = v);
              _scheduleLiveApply(immediate: true);
            }
          },
        ),
        const SizedBox(height: 16),

        _sectionTitle(AppI18n.t('screen_position')),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final pos in [
              ('bottom', AppI18n.t('pos_bottom')),
              ('top', AppI18n.t('pos_top')),
              ('left', AppI18n.t('pos_left')),
              ('right', AppI18n.t('pos_right')),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _choiceChip(
                    label: pos.$2,
                    selected: _cfg.position == pos.$1,
                    onTap: () {
                      setState(() => _cfg.position = pos.$1);
                      _scheduleLiveApply(immediate: true);
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        _sectionTitle(AppI18n.t('panel_layer')),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final layer in [
              ('top', AppI18n.t('layer_top')),
              ('normal', AppI18n.t('layer_normal')),
              ('bottom', AppI18n.t('layer_bottom')),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _choiceChip(
                    label: layer.$2,
                    selected: _cfg.layer == layer.$1,
                    onTap: () {
                      setState(() => _cfg.layer = layer.$1);
                      _scheduleLiveApply(immediate: true);
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        _sliderRow(
          'Центрирование (Centering)',
          '${_cfg.centerOffset.round()}%',
          _cfg.centerOffset,
          -40,
          40,
          (v) {
            setState(() => _cfg.centerOffset = v);
            _scheduleLiveApply();
          },
        ),
        _sliderRow(
          'Отступ от края (Edge Offset)',
          '${_cfg.edgeOffset.round()} px',
          _cfg.edgeOffset,
          0,
          64,
          (v) {
            setState(() => _cfg.edgeOffset = v);
            _scheduleLiveApply();
          },
        ),
      ],
    );
  }

  // ---- TAB 5: Style (Skins + Font + Shadow + Outline with Live Preview) ----
  Widget _buildStyleTab() {
    final builtInThemes = [
      ('aero3d', 'Аэро 3D Полка'),
      ('crystal', 'Кристалл (Vista)'),
      ('graphite', 'Графит'),
      ('silk', 'Светлый шёлк'),
      ('minimal', 'Минимал'),
      ('retro', 'Ретро Металл'),
    ];
    final allThemeItems = <DropdownMenuItem<String>>[
      for (final t in builtInThemes) DropdownMenuItem(value: t.$1, child: Text(t.$2)),
      for (final s in _skins) DropdownMenuItem(value: s.id, child: Text(s.name)),
    ];

    final fontFamilies = ['Segoe UI', 'Arial', 'Calibri', 'Consolas', 'Tahoma', 'Verdana'];
    final swatchHexes = [
      '#FFFFFF', '#000000', '#38BDF8', '#FDE047', '#34D399', '#FB7185', '#CBD5E1', '#0F172A'
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle('Тема / Скин (${_dockShortLabel(_editingDockId)})')),
            TextButton.icon(
              onPressed: () {
                Win32Bridge.shellExecute(target: widget.store.skinsDir.path);
              },
              icon: const Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFF38BDF8)),
              label: const Text('Открыть Skins/', style: TextStyle(fontSize: 11, color: Color(0xFF38BDF8))),
            ),
          ],
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: allThemeItems.any((e) => e.value == _cfg.theme) ? _cfg.theme : 'aero3d',
          dropdownColor: const Color(0xFF1E293B),
          style: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: _inputDeco(),
          items: allThemeItems,
          onChanged: (v) {
            if (v != null) {
              setState(() => _cfg.theme = v);
              _scheduleLiveApply(immediate: true);
            }
          },
        ),
        const SizedBox(height: 4),
        const Text(
          'Поддерживаются скины RocketDock, ObjectDock, MobyDock, RK Launcher и Y\'z Dock (папка с background.ini + PNG в Skins/).',
          style: TextStyle(fontSize: 10.5, color: Colors.white54),
        ),
        const SizedBox(height: 12),

        _sliderRow(
          'Прозрачность фона панели',
          '${_cfg.bgOpacity.round()}%',
          _cfg.bgOpacity,
          0,
          100,
          (v) {
            setState(() => _cfg.bgOpacity = v);
            _scheduleLiveApply();
          },
        ),
        _switchRow(
          'Эффект размытия Windows Acrylic',
          'Включить системное размытие стекла за подложкой',
          _cfg.useAcrylic,
          (v) {
            setState(() => _cfg.useAcrylic = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _switchRow(
          'Показывать подписи иконок',
          'Отображать всплывающее имя ярлыка при наведении',
          _cfg.showLabels,
          (v) {
            setState(() => _cfg.showLabels = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        const SizedBox(height: 10),

        _sectionTitle('Шрифт, цвет, тень и обводка подписей'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: fontFamilies.contains(_cfg.labelFontFamily)
                    ? _cfg.labelFontFamily
                    : 'Segoe UI',
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: _inputDeco(),
                items: fontFamilies
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _cfg.labelFontFamily = v);
                    _scheduleLiveApply(immediate: true);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _choiceChip(
                label: 'Жирный',
                selected: _cfg.labelBold,
                onTap: () {
                  setState(() => _cfg.labelBold = !_cfg.labelBold);
                  _scheduleLiveApply(immediate: true);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _choiceChip(
                label: 'Курсив',
                selected: _cfg.labelItalic,
                onTap: () {
                  setState(() => _cfg.labelItalic = !_cfg.labelItalic);
                  _scheduleLiveApply(immediate: true);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _sliderRow(
          'Размер шрифта подписи',
          '${_cfg.labelFontSize.round()} pt',
          _cfg.labelFontSize,
          9,
          24,
          (v) {
            setState(() => _cfg.labelFontSize = v);
            _scheduleLiveApply();
          },
        ),
        _colorRow('Цвет текста', _cfg.labelColor, swatchHexes, (c) {
          setState(() => _cfg.labelColor = c);
          _scheduleLiveApply(immediate: true);
        }),
        _colorRow('Цвет тени', _cfg.labelShadowColor, swatchHexes, (c) {
          setState(() => _cfg.labelShadowColor = c);
          _scheduleLiveApply(immediate: true);
        }),
        _sliderRow(
          'Прозрачность тени',
          '${_cfg.labelShadowOpacity.round()}%',
          _cfg.labelShadowOpacity,
          0,
          100,
          (v) {
            setState(() => _cfg.labelShadowOpacity = v);
            _scheduleLiveApply();
          },
        ),
        _colorRow('Цвет обводки', _cfg.labelOutlineColor, swatchHexes, (c) {
          setState(() => _cfg.labelOutlineColor = c);
          _scheduleLiveApply(immediate: true);
        }),
        _sliderRow(
          'Прозрачность обводки',
          '${_cfg.labelOutlineOpacity.round()}%',
          _cfg.labelOutlineOpacity,
          0,
          100,
          (v) {
            setState(() => _cfg.labelOutlineOpacity = v);
            _scheduleLiveApply();
          },
        ),
      ],
    );
  }

  // ---- TAB 6: Behavior (with Live Preview) ----
  Widget _buildBehaviorTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Эффект привлечения внимания (${_dockShortLabel(_editingDockId)})'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final ef in [
              ('bounce', 'Прыжок'),
              ('pulse', 'Импульс'),
              ('glow', 'Свечение'),
              ('none', 'Нет'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _choiceChip(
                    label: ef.$2,
                    selected: _cfg.clickEffect == ef.$1,
                    onTap: () {
                      setState(() => _cfg.clickEffect = ef.$1);
                      _scheduleLiveApply(immediate: true);
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        _switchRow(
          'Автоскрытие панели (AutoHide)',
          'Скрывать панель у края экрана и показывать при подведении курсора',
          _cfg.autoHide,
          (v) {
            setState(() => _cfg.autoHide = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _sliderRow(
          'Длительность скрытия/появления',
          '${_cfg.autoHideDurationMs} мс',
          _cfg.autoHideDurationMs.toDouble(),
          60,
          1000,
          (v) {
            setState(() => _cfg.autoHideDurationMs = v.round());
            _scheduleLiveApply();
          },
        ),
        _sliderRow(
          'Задержка автоскрытия',
          '${_cfg.autoHideDelayMs} мс',
          _cfg.autoHideDelayMs.toDouble(),
          0,
          2000,
          (v) {
            setState(() => _cfg.autoHideDelayMs = v.round());
            _scheduleLiveApply();
          },
        ),
        const SizedBox(height: 10),

        _switchRow(
          'Всплытие поверх окон при наведении (Popup on Mouseover)',
          'Временно поднимать панель со слоем «Обычный»/«Под окнами», когда курсор у края экрана',
          _cfg.popupOnMouseover,
          (v) {
            setState(() => _cfg.popupOnMouseover = v);
            _scheduleLiveApply(immediate: true);
          },
        ),
        _sliderRow(
          'Задержка всплытия поверх окон',
          '${_cfg.popupDelayMs} мс',
          _cfg.popupDelayMs.toDouble(),
          0,
          2000,
          (v) {
            setState(() => _cfg.popupDelayMs = v.round());
            _scheduleLiveApply();
          },
        ),
      ],
    );
  }

  // ---- TAB 7: Auto-Backup, Seamless Upgrade & Reset ----
  Widget _buildAboutDefaultsTab() {
    String fmtDate(DateTime dt) =>
        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Seamless upgrade + Auto-backup card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x2210B981),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x6634D399)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_rounded, size: 17, color: Color(0xFF34D399)),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Бэкапы и сохранение настроек при обновлении',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _createBackupNow,
                    icon: const Icon(Icons.save_alt_rounded, size: 14),
                    label: const Text('Создать бэкап сейчас', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF020617),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _switchRow(
                'Автоперенос настроек при копировании новой версии в новую папку',
                'Зеркалирует Settings.ini и иконки в профиль Windows — новая версия в новой папке подхватит всё сама!',
                _backup.autoSyncProfile,
                (v) {
                  setState(() => _backup.autoSyncProfile = v);
                  _scheduleLiveApply(immediate: true);
                },
              ),
              _switchRow(
                'Автоматический бэкап программы',
                'Сохраняет резервные копии Settings.ini, пользовательских иконок и языков (также перед импортом и сбросом)',
                _backup.autoBackupEnabled,
                (v) {
                  setState(() => _backup.autoBackupEnabled = v);
                  _scheduleLiveApply(immediate: true);
                },
              ),
              const SizedBox(height: 6),
              _fieldLabel('Периодичность автобэкапа'),
              Row(
                children: [
                  for (final opt in [(0, 'При запуске'), (24, 'Раз в день'), (168, 'Раз в неделю')])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _choiceChip(
                          label: opt.$2,
                          selected: _backup.autoBackupIntervalHours == opt.$1,
                          onTap: () {
                            setState(() => _backup.autoBackupIntervalHours = opt.$1);
                            _scheduleLiveApply(immediate: true);
                          },
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _sliderRow(
                'Хранить последних бэкапов',
                '${_backup.maxAutoBackups} шт.',
                _backup.maxAutoBackups.toDouble(),
                2,
                30,
                (v) {
                  setState(() => _backup.maxAutoBackups = v.round());
                  _scheduleLiveApply();
                },
              ),
              _fieldLabel('Папка для хранения бэкапов'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _backupFolderCtrl,
                      style: const TextStyle(fontSize: 11.5, color: Colors.white),
                      decoration: _inputDeco(hint: r'C:\Users\...\Documents\AeroDock-Backups'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _smallBtn('Обзор…', () async {
                    final d = await FilePicker.platform.getDirectoryPath();
                    if (d != null) {
                      setState(() {
                        _backupFolderCtrl.text = d;
                        _backup.backupFolder = d;
                        widget.store.backupSettings.backupFolder = d;
                        _backups = widget.store.listBackups();
                      });
                      _scheduleLiveApply(immediate: true);
                    }
                  }),
                  const SizedBox(width: 4),
                  _smallBtn('Открыть', () {
                    final dir = Directory(_backupFolderCtrl.text.trim());
                    if (!dir.existsSync()) dir.createSync(recursive: true);
                    Win32Bridge.shellExecute(target: dir.path);
                  }),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Saved Backups List (1-click Restore)
        Row(
          children: [
            Expanded(child: _sectionTitle('Сохранённые бэкапы (${_backups.length})')),
            TextButton.icon(
              onPressed: () {
                widget.store.backupSettings.backupFolder = _backupFolderCtrl.text.trim();
                setState(() => _backups = widget.store.listBackups());
              },
              icon: const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF7DD3FC)),
              label: const Text('Обновить список', style: TextStyle(fontSize: 11, color: Color(0xFF7DD3FC))),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_backups.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0x281E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: const Text(
              'Бэкапов пока нет. Нажмите «Создать бэкап сейчас» или дождитесь автоматического сохранения.',
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
          )
        else
          for (final b in _backups.take(8))
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x331E293B),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 15, color: Color(0xFF34D399)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        Text(
                          '${fmtDate(b.createdAt)} · ${(b.sizeBytes / 1024).ceil()} КБ',
                          style: const TextStyle(fontSize: 10, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  _smallBtn('Восстановить', () => _restoreBackup(b)),
                ],
              ),
            ),

        const SizedBox(height: 16),
        _sectionTitle('AeroDock Portable v3.6 — Портативные папки'),
        const SizedBox(height: 4),
        Text(
          'Текущая папка: ${widget.store.portableDir.path}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF7DD3FC)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _folderBtn('Settings.ini', widget.store.iniFile.path),
            _folderBtn('Skins/', widget.store.skinsDir.path),
            _folderBtn('Icons/', widget.store.iconsDir.path),
            _folderBtn('Docklets/', widget.store.dockletsDir.path),
            _folderBtn('Languages/', widget.store.languagesDir.path),
            _folderBtn('DevApps/', _dev.appsRootFolder),
            _folderBtn('Бэкапы/', _backup.backupFolder),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle('Горячие клавиши'),
        const SizedBox(height: 6),
        const Text(
          '• Ctrl + Alt + R — полностью скрыть/показать все панели\n'
          '• Ctrl + перетаскивание — переместить или удалить значок при включённой блокировке\n'
          '• Ctrl + Alt + Shift при сворачивании окна — навсегда исключить окно из дока\n'
          '• Ctrl при сворачивании окна — однократно свернуть в панель задач Windows\n'
          '• Drag-n-drop файла Settings.ini (RocketDock 1.3.5 или AeroDock) на панель — импорт',
          style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.45),
        ),
        const SizedBox(height: 16),
        _sectionTitle('Сброс настроек (автоматически создаёт бэкап перед сбросом)'),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () async {
                await widget.store.createBackup(tag: 'pre_reset');
                await widget.onResetDefaults();
                widget.onClose();
              },
              icon: const Icon(Icons.restore_rounded, size: 15),
              label: const Text('По умолчанию (без удаления значков)', style: TextStyle(fontSize: 11.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () async {
                await widget.store.createBackup(tag: 'pre_full_reset');
                await widget.onFullReset();
                widget.onClose();
              },
              icon: const Icon(Icons.delete_forever_rounded, size: 15),
              label: const Text('Полный сброс', style: TextStyle(fontSize: 11.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9F1239),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _folderBtn(String label, String path) {
    return OutlinedButton.icon(
      onPressed: () {
        if (!path.toLowerCase().endsWith('.ini')) {
          final d = Directory(path);
          if (!d.existsSync()) d.createSync(recursive: true);
        }
        Win32Bridge.shellExecute(target: path);
      },
      icon: const Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFF38BDF8)),
      label: Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _smallBtn(String label, VoidCallback onTap, {bool danger = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: danger ? const Color(0x33E11D48) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: danger ? const Color(0x66FB7185) : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: danger ? const Color(0xFFFDA4AF) : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
      );

  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0x330EA5E9) : const Color(0x331E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF38BDF8) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? const Color(0xFFBAE6FD) : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _switchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x331E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: const Color(0xFF38BDF8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderRow(
    String label,
    String valueLabel,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
              Text(
                valueLabel,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7DD3FC),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              activeColor: const Color(0xFF38BDF8),
              inactiveColor: Colors.white12,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorRow(
    String label,
    String currentHex,
    List<String> swatches,
    ValueChanged<String> onSelect,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
          ),
          for (final hex in swatches)
            GestureDetector(
              onTap: () => onSelect(hex),
              child: Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: parseHexColor(hex),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: currentHex.toUpperCase() == hex.toUpperCase()
                        ? const Color(0xFF38BDF8)
                        : Colors.white30,
                    width: currentHex.toUpperCase() == hex.toUpperCase() ? 2.2 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco({String? hint}) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: Colors.white30),
        filled: true,
        fillColor: const Color(0x66020617),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
      );
}

// ============================================================================
// 2. RocketDock Icon Settings Dialog (Target, Start In, Args, Run, Icon Folders)
// ============================================================================

class IconSettingsDialog extends StatefulWidget {
  final PortableIniStore store;
  final DockItemModel? initialItem;
  final String defaultType;
  final ValueChanged<DockItemModel> onSave;
  final VoidCallback onClose;

  const IconSettingsDialog({
    super.key,
    required this.store,
    this.initialItem,
    this.defaultType = 'file',
    required this.onSave,
    required this.onClose,
  });

  @override
  State<IconSettingsDialog> createState() => _IconSettingsDialogState();
}

class _IconSettingsDialogState extends State<IconSettingsDialog> {
  late String _type;
  late TextEditingController _titleCtrl;
  late TextEditingController _targetCtrl;
  late TextEditingController _startInCtrl;
  late TextEditingController _argsCtrl;
  late String _runMode;
  late String _openRunning;
  late bool _popupMenu;
  late String _iconKey;
  late String _color;
  String? _iconPath;
  String? _iconPathAlt;
  bool _editingAltState = false;

  late List<String> _iconFolders;
  int _selectedFolderIdx = 0;

  @override
  void initState() {
    super.initState();
    final it = widget.initialItem;
    _type = it?.type ?? widget.defaultType;
    _titleCtrl = TextEditingController(text: it?.title ?? '');
    _targetCtrl = TextEditingController(text: it?.target ?? '');
    _startInCtrl = TextEditingController(text: it?.startIn ?? '');
    _argsCtrl = TextEditingController(text: it?.args ?? '');
    _runMode = it?.runMode ?? 'normal';
    _openRunning = it?.openRunning ?? 'global';
    _popupMenu = it?.popupMenu ?? true;
    _iconKey = it?.iconKey ?? 'rocket';
    _color = it?.color ?? '#0284C7';
    _iconPath = it?.iconPath;
    _iconPathAlt = it?.iconPathAlt;

    _iconFolders = [
      widget.store.iconsDir.path,
      widget.store.iconsCacheDir.path,
      ...widget.store.global.iconFolders,
    ];
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _targetCtrl.dispose();
    _startInCtrl.dispose();
    _argsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTargetFile() async {
    final res = await FilePicker.platform.pickFiles();
    if (res == null || res.files.single.path == null) return;
    final path = res.files.single.path!;
    final extracted = Win32Bridge.extractIconToPng(path, widget.store.iconsCacheDir);
    setState(() {
      _targetCtrl.text = path;
      if (_startInCtrl.text.trim().isEmpty) {
        _startInCtrl.text = p.dirname(path);
      }
      if (_titleCtrl.text.trim().isEmpty) {
        _titleCtrl.text = p.basenameWithoutExtension(path);
      }
      if (extracted != null) _iconPath = extracted;
    });
  }

  Future<void> _pickFolder(TextEditingController target) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    setState(() {
      target.text = path;
      if (target == _targetCtrl && _titleCtrl.text.trim().isEmpty) {
        _titleCtrl.text = p.basename(path);
      }
    });
  }

  Future<void> _addIconFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || _iconFolders.contains(dir)) return;
    setState(() {
      _iconFolders.add(dir);
      _selectedFolderIdx = _iconFolders.length - 1;
      widget.store.global.iconFolders.add(dir);
    });
    await widget.store.save();
  }

  Future<void> _removeSelectedIconFolder() async {
    if (_selectedFolderIdx < 2) return;
    final removed = _iconFolders.removeAt(_selectedFolderIdx);
    widget.store.global.iconFolders.remove(removed);
    setState(() => _selectedFolderIdx = 0);
    await widget.store.save();
  }

  Future<void> _pickCustomIconFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'ico', 'jpg', 'jpeg', 'webp'],
    );
    if (res == null || res.files.single.path == null) return;
    setState(() {
      if (_editingAltState) {
        _iconPathAlt = res.files.single.path!;
      } else {
        _iconPath = res.files.single.path!;
      }
    });
  }

  void _submit() {
    final saved = DockItemModel(
      id: widget.initialItem?.id ?? 'item_${DateTime.now().millisecondsSinceEpoch}',
      type: _type,
      title: _titleCtrl.text.trim().isEmpty ? 'Без названия' : _titleCtrl.text.trim(),
      target: _targetCtrl.text.trim(),
      startIn: _startInCtrl.text.trim(),
      args: _argsCtrl.text.trim(),
      runMode: _runMode,
      openRunning: _openRunning,
      popupMenu: _popupMenu,
      iconKey: _iconKey,
      color: _color,
      iconPath: _iconPath,
      iconPathAlt: _iconPathAlt,
      devRuleId: widget.initialItem?.devRuleId,
    );
    widget.onSave(saved);
  }

  @override
  Widget build(BuildContext context) {
    final activeFolder =
        _iconFolders.isNotEmpty ? _iconFolders[_selectedFolderIdx.clamp(0, _iconFolders.length - 1)] : '';
    final folderIcons = widget.store.listIconsInFolder(activeFolder);
    final activeCustomPath = _editingAltState ? _iconPathAlt : _iconPath;

    return Container(
      width: 740,
      height: 520,
      decoration: BoxDecoration(
        color: const Color(0xF50F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(color: Color(0xB3000000), blurRadius: 32, offset: Offset(0, 14)),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF))),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_rounded, color: Color(0xFF38BDF8), size: 17),
                const SizedBox(width: 8),
                Text(
                  AppI18n.t('icon_settings'),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                  splashRadius: 16,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 268,
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0x18FFFFFF))),
                    color: Color(0x40020617),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: activeCustomPath != null && File(activeCustomPath).existsSync()
                                ? Image.file(File(activeCustomPath), fit: BoxFit.contain)
                                : DockGlyphTile(
                                    iconKey: _iconKey,
                                    color: parseHexColor(_color),
                                    size: 50,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_type == 'recycle_bin')
                                  Row(
                                    children: [
                                      _miniBtn('Пустая', !_editingAltState, () => setState(() => _editingAltState = false)),
                                      const SizedBox(width: 4),
                                      _miniBtn('Полная', _editingAltState, () => setState(() => _editingAltState = true)),
                                    ],
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _miniBtn('Файл PNG/ICO', false, _pickCustomIconFile),
                                    const SizedBox(width: 4),
                                    _miniBtn('Сброс', false, () {
                                      setState(() {
                                        if (_editingAltState) {
                                          _iconPathAlt = null;
                                        } else {
                                          _iconPath = null;
                                        }
                                      });
                                    }),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('Папки иконок', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70)),
                          const Spacer(),
                          _miniBtn('+', false, _addIconFolder),
                          const SizedBox(width: 4),
                          _miniBtn('−', false, _removeSelectedIconFolder),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 66,
                        child: ListView.builder(
                          itemCount: _iconFolders.length,
                          itemBuilder: (_, idx) {
                            final sel = idx == _selectedFolderIdx;
                            return InkWell(
                              onTap: () => setState(() => _selectedFolderIdx = idx),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: sel ? const Color(0x330EA5E9) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  p.basename(_iconFolders[idx]),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: sel ? const Color(0xFF7DD3FC) : Colors.white70,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: folderIcons.isEmpty
                            ? const Center(
                                child: Text(
                                  'Положите .png или .ico в папку Icons/ — они сразу появятся здесь.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 10.5, color: Colors.white38),
                                ),
                              )
                            : GridView.builder(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 6,
                                ),
                                itemCount: folderIcons.length,
                                itemBuilder: (_, i) {
                                  final file = folderIcons[i];
                                  final selected = activeCustomPath == file.path;
                                  return InkWell(
                                    onTap: () => setState(() {
                                      if (_editingAltState) {
                                        _iconPathAlt = file.path;
                                      } else {
                                        _iconPath = file.path;
                                      }
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: selected ? const Color(0x440EA5E9) : Colors.white10,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: selected ? const Color(0xFF38BDF8) : Colors.transparent,
                                        ),
                                      ),
                                      child: Image.file(file, fit: BoxFit.contain),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Имя (подпись при наведении)'),
                        _textInput(_titleCtrl, 'Например: Проводник или GitHub'),
                        const SizedBox(height: 10),
                        _fieldLabel('Target (путь к файлу, папке или URL)'),
                        Row(
                          children: [
                            Expanded(child: _textInput(_targetCtrl, r'C:\Program Files\...\app.exe')),
                            const SizedBox(width: 6),
                            _miniBtn('Файл…', false, _pickTargetFile),
                            const SizedBox(width: 4),
                            _miniBtn('Папка…', false, () => _pickFolder(_targetCtrl)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _fieldLabel('Start In (рабочая папка)'),
                        Row(
                          children: [
                            Expanded(child: _textInput(_startInCtrl, r'C:\Users\...')),
                            const SizedBox(width: 6),
                            _miniBtn('Обзор…', false, () => _pickFolder(_startInCtrl)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _fieldLabel('Arguments (параметры запуска)'),
                        _textInput(_argsCtrl, '--incognito /k ...'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldLabel('Run (режим окна)'),
                                  DropdownButtonFormField<String>(
                                    value: _runMode,
                                    dropdownColor: const Color(0xFF1E293B),
                                    style: const TextStyle(fontSize: 12, color: Colors.white),
                                    decoration: _inputDeco(),
                                    items: const [
                                      DropdownMenuItem(value: 'normal', child: Text('Обычное окно')),
                                      DropdownMenuItem(value: 'minimized', child: Text('Свёрнутое')),
                                      DropdownMenuItem(value: 'maximized', child: Text('Развёрнутое')),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) setState(() => _runMode = v);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldLabel('Open Running'),
                                  DropdownButtonFormField<String>(
                                    value: _openRunning,
                                    dropdownColor: const Color(0xFF1E293B),
                                    style: const TextStyle(fontSize: 12, color: Colors.white),
                                    decoration: _inputDeco(),
                                    items: const [
                                      DropdownMenuItem(value: 'global', child: Text('Global (как в доке)')),
                                      DropdownMenuItem(value: 'always', child: Text('Always (переключаться)')),
                                      DropdownMenuItem(value: 'never', child: Text('Never (новый экземпляр)')),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) setState(() => _openRunning = v);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _popupMenu,
                          activeColor: const Color(0xFF38BDF8),
                          title: const Text(
                            'Popup Menu (спец. действия в контекстном меню)',
                            style: TextStyle(fontSize: 12, color: Colors.white),
                          ),
                          onChanged: (v) => setState(() => _popupMenu = v ?? true),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onClose,
                  child: Text(AppI18n.t('cancel'), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA5E9),
                    foregroundColor: const Color(0xFF020617),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    AppI18n.t('save'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
      );

  Widget _textInput(TextEditingController ctrl, String hint) => TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: _inputDeco(hint: hint),
      );

  Widget _miniBtn(String text, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF0284C7) : Colors.white10,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      );

  InputDecoration _inputDeco({String? hint}) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11.5, color: Colors.white30),
        filled: true,
        fillColor: const Color(0x66020617),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
      );
}

// ============================================================================
// 3. Live Stack Docklet Popover (Real Windows Folder Grid)
// ============================================================================

class LiveStackPopover extends StatelessWidget {
  final String title;
  final String folderPath;
  final List<FolderEntryInfo> entries;
  final ValueChanged<FolderEntryInfo> onOpenEntry;
  final VoidCallback onOpenFolderInExplorer;
  final VoidCallback onClose;

  const LiveStackPopover({
    super.key,
    required this.title,
    required this.folderPath,
    required this.entries,
    required this.onOpenEntry,
    required this.onOpenFolderInExplorer,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 520,
      height: 370,
      decoration: BoxDecoration(
        color: const Color(0xF20F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(color: Color(0xB3000000), blurRadius: 28, offset: Offset(0, 12)),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x18FFFFFF))),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: onOpenFolderInExplorer,
                  child: const Text('Открыть в Проводнике', style: TextStyle(fontSize: 11, color: Color(0xFF7DD3FC))),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 17, color: Colors.white70),
                  splashRadius: 16,
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'Папка пуста или не найдена:\n$folderPath',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 0.96,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final entry = entries[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onOpenEntry(entry),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (entry.iconPngPath != null && File(entry.iconPngPath!).existsSync())
                                Image.file(
                                  File(entry.iconPngPath!),
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.contain,
                                )
                              else
                                Icon(
                                  entry.isDirectory
                                      ? Icons.folder_rounded
                                      : Icons.insert_drive_file_rounded,
                                  color: entry.isDirectory
                                      ? const Color(0xFFFBBF24)
                                      : const Color(0xFF94A3B8),
                                  size: 34,
                                ),
                              const SizedBox(height: 6),
                              Text(
                                entry.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 10.5, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. Calendar Docklet Popover
// ============================================================================

class CalendarPopover extends StatelessWidget {
  final DateTime now;
  final VoidCallback onClose;

  const CalendarPopover({super.key, required this.now, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final startOffset = firstDay.weekday - 1;
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xF20F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(color: Color(0xB3000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: Color(0xFFFB7185), size: 18),
              const SizedBox(width: 8),
              Text(
                '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
                splashRadius: 14,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final d in weekdays)
                Expanded(
                  child: Center(
                    child: Text(d, style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: startOffset + daysInMonth,
            itemBuilder: (_, idx) {
              if (idx < startOffset) return const SizedBox.shrink();
              final day = idx - startOffset + 1;
              final isToday = day == now.day;
              return Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday ? const Color(0xFFE11D48) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isToday ? Colors.white : Colors.white70,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
