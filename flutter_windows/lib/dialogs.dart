import 'dart:io';
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
      int.tryParse(cleaned.length == 6 ? 'FF$cleaned' : cleaned, radix: 16) ?? 0xFF0284C7;
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
                              'Экран ${i + 1} (${d.size.width.round()}×${d.size.height.round()})',
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
                _sliderRow('Размер значков', '${s.iconSize.round()} px', s.iconSize, 36, 76, (v) {
                  setState(() => s.iconSize = v);
                  widget.onChanged();
                }),
                _sliderRow('Увеличение при наведении', '${(s.zoomScale * 100).round()}%', s.zoomScale, 1.0, 2.0, (v) {
                  setState(() => s.zoomScale = v);
                  widget.onChanged();
                }),
                _sliderRow('Прозрачность панели', '${s.opacity.round()}%', s.opacity, 25, 100, (v) {
                  setState(() => s.opacity = v);
                  widget.onChanged();
                }),
                _sliderRow('Отступ от края экрана', '${s.edgeOffset.round()} px', s.edgeOffset, 0, 48, (v) {
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
    final name = 'custom_${DateTime.now().millisecondsSinceEpoch}$ext';
    final dest = File(p.join(widget.iconsDir.path, name));
    await File(src).copy(dest.path);
    setState(() => _iconFile = name);
  }

  Future<void> _extractIconNow() async {
    final id = widget.initialItem?.id ?? 'item_${DateTime.now().millisecondsSinceEpoch}';
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
        id: widget.initialItem?.id ?? 'item-${DateTime.now().millisecondsSinceEpoch}',
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
                  Text('Ссылки внутри стека (${_stackItems.length})', style: const TextStyle(fontSize: 12, color: Colors.white70)),
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
                              id: 'st-${DateTime.now().millisecondsSinceEpoch}',
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
