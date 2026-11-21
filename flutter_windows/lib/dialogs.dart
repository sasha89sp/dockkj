import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:screen_retriever/screen_retriever.dart';

import 'docklets.dart';
import 'i18n.dart';
import 'ini_storage.dart';
import 'win32_bridge.dart';

// ============================================================================
// 1. RocketDock Dock Settings Dialog (All 6 Tabs + Multi-Dock 1..3)
// ============================================================================

class DockSettingsDialog extends StatefulWidget {
  final PortableIniStore store;
  final int activeDockId;
  final List<Display> displays;
  final VoidCallback onSaved;
  final VoidCallback onResetDefaults;
  final VoidCallback onFullReset;
  final VoidCallback onClose;

  const DockSettingsDialog({
    super.key,
    required this.store,
    required this.activeDockId,
    required this.displays,
    required this.onSaved,
    required this.onResetDefaults,
    required this.onFullReset,
    required this.onClose,
  });

  @override
  State<DockSettingsDialog> createState() => _DockSettingsDialogState();
}

class _DockSettingsDialogState extends State<DockSettingsDialog> {
  int _tab = 0;
  late int _editingDockId;
  late GlobalDockSettings _global;
  late Map<int, DockPanelConfig> _panels;
  late List<ExternalSkinInfo> _skins;

  DockPanelConfig get _cfg => _panels[_editingDockId]!;

  @override
  void initState() {
    super.initState();
    _editingDockId = widget.activeDockId.clamp(1, 3);
    _global = widget.store.global.copy();
    _panels = {
      1: (widget.store.panels[1] ?? DockPanelConfig.defaultFor(1)).copy(),
      2: (widget.store.panels[2] ?? DockPanelConfig.defaultFor(2)).copy(),
      3: (widget.store.panels[3] ?? DockPanelConfig.defaultFor(3)).copy(),
    };
    _skins = widget.store.scanExternalSkins();
  }

  Future<void> _saveAndClose() async {
    widget.store.global = _global;
    for (var id = 1; id <= 3; id++) {
      widget.store.panels[id] = _panels[id]!;
    }
    AppI18n.currentCode = _global.language;
    await Win32Bridge.setStartupEnabled(_global.launchWithWindows);
    await widget.store.save();
    widget.onSaved();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (Icons.tune_rounded, AppI18n.t('tab_general')),
      (Icons.apps_rounded, AppI18n.t('tab_icons')),
      (Icons.desktop_windows_rounded, AppI18n.t('tab_position')),
      (Icons.palette_rounded, AppI18n.t('tab_style')),
      (Icons.flash_on_rounded, AppI18n.t('tab_behavior')),
      (Icons.folder_special_rounded, AppI18n.t('tab_about')),
    ];

    return Container(
      width: 720,
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
          // Header with Dock 1 / 2 / 3 profile switcher
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                // Quick profile switcher for Multi-Dock (1..3)
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
                      for (var id = 1; id <= 3; id++)
                        GestureDetector(
                          onTap: () => setState(() => _editingDockId = id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _editingDockId == id
                                  ? const Color(0xFF0284C7)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Панель $id${id <= _global.dockCount ? '' : ' (выкл)'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _editingDockId == id
                                    ? Colors.white
                                    : (id <= _global.dockCount
                                        ? Colors.white70
                                        : Colors.white38),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                  splashRadius: 16,
                ),
              ],
            ),
          ),

          // Body: Left sidebar + Tab content
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 164,
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              decoration: BoxDecoration(
                                color: _tab == i
                                    ? const Color(0x330EA5E9)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _tab == i
                                      ? const Color(0x6638BDF8)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    tabs[i].$1,
                                    size: 16,
                                    color: _tab == i
                                        ? const Color(0xFF7DD3FC)
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
                      1 => _buildIconsTab(),
                      2 => _buildPositionTab(),
                      3 => _buildStyleTab(),
                      4 => _buildBehaviorTab(),
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
                  onPressed: () {
                    widget.onResetDefaults();
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
                  onPressed: widget.onClose,
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

  // ---- TAB 0: General + Multi-Dock ----
  Widget _buildGeneralTab() {
    final langs = AppI18n.availableLanguages();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Multi-Dock — количество независимых панелей'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final count in [1, 2, 3])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: count < 3 ? 8 : 0),
                  child: _choiceChip(
                    label: count == 1
                        ? '1 панель'
                        : count == 2
                            ? '2 панели'
                            : '3 панели',
                    selected: _global.dockCount == count,
                    onTap: () => setState(() => _global.dockCount = count),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Каждая панель работает в отдельном быстром процессе со своим краем экрана, монитором, скином и набором значков.',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 16),

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
            if (v != null) setState(() => _global.language = v);
          },
        ),
        const SizedBox(height: 14),

        _switchRow(
          AppI18n.t('start_with_windows'),
          'Портативный ярлык в shell:startup (без записи в реестр)',
          _global.launchWithWindows,
          (v) => setState(() => _global.launchWithWindows = v),
        ),
        _switchRow(
          AppI18n.t('portable_ini'),
          'Все настройки и ярлыки хранятся в Settings.ini рядом с aerodock.exe',
          _global.portableIni,
          (v) => setState(() => _global.portableIni = v),
        ),
        _switchRow(
          AppI18n.t('minimize_to_dock'),
          'Свёрнутые окна попадают в панель с живым превью (Ctrl+Alt+Shift — исключить навсегда, Ctrl — один раз)',
          _global.minimizeToDock,
          (v) => setState(() => _global.minimizeToDock = v),
        ),
        _switchRow(
          AppI18n.t('disable_min_anim'),
          'Мгновенное скрытие окна в док без задержки анимации Windows',
          _global.disableMinimizeAnimation,
          (v) => setState(() => _global.disableMinimizeAnimation = v),
        ),
        _switchRow(
          AppI18n.t('running_indicators'),
          'Светящаяся точка рядом с иконками запущенных программ',
          _global.showRunningIndicators,
          (v) => setState(() => _global.showRunningIndicators = v),
        ),
        _switchRow(
          AppI18n.t('open_running'),
          'При клике активировать уже открытое окно вместо запуска копии',
          _global.openRunningInstance,
          (v) => setState(() => _global.openRunningInstance = v),
        ),
        _switchRow(
          AppI18n.t('lock_items'),
          'Защита от случайного перемещения/удаления (удерживайте Ctrl для обхода)',
          _global.lockItems,
          (v) => setState(() => _global.lockItems = v),
        ),
      ],
    );
  }

  // ---- TAB 1: Icons ----
  Widget _buildIconsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Качество отрисовки при зуме (Панель $_editingDockId)'),
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
                    onTap: () => setState(() => _cfg.renderQuality = q.$1),
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
          (v) => setState(() => _cfg.iconOpacity = v),
        ),
        _switchRow(
          'Zoom Opaque (100% при наведении)',
          'Делать значок полностью непрозрачным во время увеличения',
          _cfg.zoomOpaque,
          (v) => setState(() => _cfg.zoomOpaque = v),
        ),
        _sliderRow(
          'Базовый размер иконок',
          '${_cfg.iconSize.round()} px',
          _cfg.iconSize,
          32,
          96,
          (v) => setState(() => _cfg.iconSize = v),
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
                    onTap: () => setState(() => _cfg.hoverEffect = h.$1),
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
          (v) => setState(() => _cfg.zoomScale = v),
        ),
        _sliderRow(
          'Ширина волны зума (Zoom Width)',
          '${_cfg.zoomWidth.toStringAsFixed(1)} ик.',
          _cfg.zoomWidth,
          1.0,
          6.0,
          (v) => setState(() => _cfg.zoomWidth = v),
        ),
        _sliderRow(
          'Длительность зума (Zoom Duration)',
          '${_cfg.zoomDurationMs} мс',
          _cfg.zoomDurationMs.toDouble(),
          60,
          400,
          (v) => setState(() => _cfg.zoomDurationMs = v.round()),
        ),
      ],
    );
  }

  // ---- TAB 2: Position ----
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
        _sectionTitle('Монитор (Панель $_editingDockId)'),
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
            if (v != null) setState(() => _cfg.monitorIndex = v);
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
                    onTap: () => setState(() => _cfg.position = pos.$1),
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
                    onTap: () => setState(() => _cfg.layer = layer.$1),
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
          (v) => setState(() => _cfg.centerOffset = v),
        ),
        _sliderRow(
          'Отступ от края (Edge Offset)',
          '${_cfg.edgeOffset.round()} px',
          _cfg.edgeOffset,
          0,
          64,
          (v) => setState(() => _cfg.edgeOffset = v),
        ),
      ],
    );
  }

  // ---- TAB 3: Style (Skins + Font + Shadow + Outline) ----
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
            Expanded(child: _sectionTitle('Тема / Скин (папка Skins/)')),
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
            if (v != null) setState(() => _cfg.theme = v);
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
          (v) => setState(() => _cfg.bgOpacity = v),
        ),
        _switchRow(
          'Эффект размытия Windows Acrylic',
          'Включить системное размытие стекла за подложкой',
          _cfg.useAcrylic,
          (v) => setState(() => _cfg.useAcrylic = v),
        ),
        _switchRow(
          'Показывать подписи иконок',
          'Отображать всплывающее имя ярлыка при наведении',
          _cfg.showLabels,
          (v) => setState(() => _cfg.showLabels = v),
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
                  if (v != null) setState(() => _cfg.labelFontFamily = v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _choiceChip(
                label: 'Жирный',
                selected: _cfg.labelBold,
                onTap: () => setState(() => _cfg.labelBold = !_cfg.labelBold),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _choiceChip(
                label: 'Курсив',
                selected: _cfg.labelItalic,
                onTap: () => setState(() => _cfg.labelItalic = !_cfg.labelItalic),
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
          (v) => setState(() => _cfg.labelFontSize = v),
        ),
        _colorRow('Цвет текста', _cfg.labelColor, swatchHexes, (c) => setState(() => _cfg.labelColor = c)),
        _colorRow('Цвет тени', _cfg.labelShadowColor, swatchHexes, (c) => setState(() => _cfg.labelShadowColor = c)),
        _sliderRow(
          'Прозрачность тени',
          '${_cfg.labelShadowOpacity.round()}%',
          _cfg.labelShadowOpacity,
          0,
          100,
          (v) => setState(() => _cfg.labelShadowOpacity = v),
        ),
        _colorRow('Цвет обводки', _cfg.labelOutlineColor, swatchHexes, (c) => setState(() => _cfg.labelOutlineColor = c)),
        _sliderRow(
          'Прозрачность обводки',
          '${_cfg.labelOutlineOpacity.round()}%',
          _cfg.labelOutlineOpacity,
          0,
          100,
          (v) => setState(() => _cfg.labelOutlineOpacity = v),
        ),
      ],
    );
  }

  // ---- TAB 4: Behavior ----
  Widget _buildBehaviorTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Эффект привлечения внимания (клик / мигание окна)'),
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
                    onTap: () => setState(() => _cfg.clickEffect = ef.$1),
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
          (v) => setState(() => _cfg.autoHide = v),
        ),
        _sliderRow(
          'Длительность скрытия/появления',
          '${_cfg.autoHideDurationMs} мс',
          _cfg.autoHideDurationMs.toDouble(),
          60,
          1000,
          (v) => setState(() => _cfg.autoHideDurationMs = v.round()),
        ),
        _sliderRow(
          'Задержка автоскрытия',
          '${_cfg.autoHideDelayMs} мс',
          _cfg.autoHideDelayMs.toDouble(),
          0,
          2000,
          (v) => setState(() => _cfg.autoHideDelayMs = v.round()),
        ),
        const SizedBox(height: 10),

        _switchRow(
          'Всплытие поверх окон при наведении (Popup on Mouseover)',
          'Временно поднимать панель со слоем «Обычный»/«Под окнами», когда курсор у края экрана',
          _cfg.popupOnMouseover,
          (v) => setState(() => _cfg.popupOnMouseover = v),
        ),
        _sliderRow(
          'Задержка всплытия поверх окон',
          '${_cfg.popupDelayMs} мс',
          _cfg.popupDelayMs.toDouble(),
          0,
          2000,
          (v) => setState(() => _cfg.popupDelayMs = v.round()),
        ),
      ],
    );
  }

  // ---- TAB 5: About, Portable Folders & Reset ----
  Widget _buildAboutDefaultsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('AeroDock Portable v3.0 (Flutter + Native Win32)'),
        const SizedBox(height: 6),
        Text(
          'Портативная папка: ${widget.store.portableDir.path}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF7DD3FC)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _folderBtn('Settings.ini', widget.store.iniFile.path),
            _folderBtn('Skins/', widget.store.skinsDir.path),
            _folderBtn('Icons/', widget.store.iconsDir.path),
            _folderBtn('Docklets/', widget.store.dockletsDir.path),
            _folderBtn('Languages/', widget.store.languagesDir.path),
          ],
        ),
        const SizedBox(height: 18),
        _sectionTitle('Горячие клавиши'),
        const SizedBox(height: 6),
        const Text(
          '• Ctrl + Alt + R — полностью скрыть/показать все панели (с остановкой отрисовки)\n'
          '• Ctrl + перетаскивание — переместить или удалить значок при включённой блокировке\n'
          '• Ctrl + Alt + Shift при сворачивании окна — навсегда исключить окно из дока\n'
          '• Ctrl при сворачивании окна — однократно свернуть в панель задач Windows',
          style: TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.5),
        ),
        const SizedBox(height: 18),
        _sectionTitle('Сброс настроек'),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () {
                widget.onResetDefaults();
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
              onPressed: () {
                widget.onFullReset();
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
      onPressed: () => Win32Bridge.shellExecute(target: path),
      icon: const Icon(Icons.folder_open_rounded, size: 14, color: Color(0xFF38BDF8)),
      label: Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

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

  InputDecoration _inputDeco() => InputDecoration(
        isDense: true,
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
    if (_selectedFolderIdx < 2) return; // Protect default Icons/ and cache/
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
      width: 720,
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
                // Left column: RocketDock Icon Folders (+ / -) & Icon Grid Browser
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
                      // Preview & Normal / Alt state toggle
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

                      // Icon folders list (+ / -)
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

                      // Visual PNG/ICO browser grid
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

                // Right column: Target, Start In, Arguments, Run Mode, Open Running, Popup Menu
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
    final startOffset = firstDay.weekday - 1; // Monday = 0
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
