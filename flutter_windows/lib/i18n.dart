import 'dart:io';

import 'package:path/path.dart' as p;

/// Multilingual manager with external Languages/*.ini support (RocketDock style).
class AppI18n {
  AppI18n._();

  static String currentCode = 'ru';
  static final Map<String, Map<String, String>> _externalLangs = {};
  static final Map<String, String> _externalLangNames = {};

  static const Map<String, String> builtInLanguageNames = {
    'ru': 'Русский',
    'en': 'English',
    'uk': 'Українська',
    'de': 'Deutsch',
    'es': 'Español',
    'fr': 'Français',
  };

  static const Map<String, Map<String, String>> _builtIn = {
    'ru': {
      'dock_settings': 'Настройки панели',
      'icon_settings': 'Настройки значка',
      'add_item': 'Добавить элемент',
      'add_file': 'Файл…',
      'add_path': 'Папка (Path)…',
      'add_blank': 'Пустой значок (Blank Icon)',
      'add_separator': 'Разделитель',
      'add_recycle_bin': 'Корзина (Recycle Bin)',
      'add_dock_settings': 'Настройки дока',
      'add_quit': 'Кнопка выхода (Quit)',
      'docklets': 'Доклеты',
      'docklet_clock': 'Часы (Clock)',
      'docklet_battery': 'Батарея (Battery)',
      'docklet_sysstats': 'Монитор CPU / RAM (SysStats)',
      'docklet_calendar': 'Календарь (Calendar)',
      'docklet_stack': 'Стек-папка (Stack Docklet)',
      'delete_item': 'Удалить элемент',
      'open_window': 'Открыть окно',
      'close_window': 'Закрыть окно',
      'empty_recycle_bin': 'Очистить корзину',
      'screen_position': 'Позиция на экране',
      'monitor': 'Монитор',
      'monitor_all': 'Monitor * (все экраны)',
      'panel_layer': 'Слой отображения',
      'layer_top': 'Поверх всех окон',
      'layer_normal': 'Обычный',
      'layer_bottom': 'Всегда под окнами',
      'lock_items': 'Закрепить значки (Ctrl для обхода)',
      'auto_hide': 'Автоскрытие',
      'multi_dock': 'Панели (Multi-Dock)',
      'quit': 'Выход из AeroDock',
      'tab_general': 'Общие',
      'tab_icons': 'Иконки',
      'tab_position': 'Позиция',
      'tab_style': 'Стиль',
      'tab_behavior': 'Поведение',
      'tab_about': 'Сброс и папки',
      'save': 'Сохранить',
      'cancel': 'Отмена',
      'defaults': 'По умолчанию',
      'full_reset': 'Полный сброс (удалить Settings.ini)',
      'pos_bottom': 'Снизу',
      'pos_top': 'Сверху',
      'pos_left': 'Слева',
      'pos_right': 'Справа',
      'language': 'Язык интерфейса',
      'start_with_windows': 'Автозапуск при старте Windows',
      'portable_ini': 'Портативный режим (Settings.ini)',
      'minimize_to_dock': 'Сворачивать окна прямо в док',
      'disable_min_anim': 'Отключить анимацию сворачивания',
      'running_indicators': 'Индикаторы запущенных приложений',
      'open_running': 'Переходить к уже запущенному окну',
      'dock_count': 'Количество панелей (1–3)',
      'editing_dock': 'Настраиваемая панель',
      'show_hide_hotkey': 'Скрыть/показать все панели (Ctrl+Alt+R)',
      'recycle_empty': 'Корзина пуста',
      'recycle_items': 'Объектов в корзине',
    },
    'en': {
      'dock_settings': 'Dock Settings',
      'icon_settings': 'Icon Settings',
      'add_item': 'Add Item',
      'add_file': 'File…',
      'add_path': 'Path (Folder)…',
      'add_blank': 'Blank Icon',
      'add_separator': 'Separator',
      'add_recycle_bin': 'Recycle Bin',
      'add_dock_settings': 'Dock Settings',
      'add_quit': 'Quit',
      'docklets': 'Docklets',
      'docklet_clock': 'Clock Docklet',
      'docklet_battery': 'Battery Docklet',
      'docklet_sysstats': 'SysStats (CPU / RAM)',
      'docklet_calendar': 'Calendar Docklet',
      'docklet_stack': 'Stack Docklet',
      'delete_item': 'Delete Item',
      'open_window': 'Open Window',
      'close_window': 'Close Window',
      'empty_recycle_bin': 'Empty Recycle Bin',
      'screen_position': 'Screen Position',
      'monitor': 'Monitor',
      'monitor_all': 'Monitor * (All Displays)',
      'panel_layer': 'Layering',
      'layer_top': 'Always on Top',
      'layer_normal': 'Normal',
      'layer_bottom': 'Always on Bottom',
      'lock_items': 'Lock Items (hold Ctrl to bypass)',
      'auto_hide': 'Auto-Hide',
      'multi_dock': 'Multi-Dock Panels',
      'quit': 'Quit AeroDock',
      'tab_general': 'General',
      'tab_icons': 'Icons',
      'tab_position': 'Position',
      'tab_style': 'Style',
      'tab_behavior': 'Behavior',
      'tab_about': 'Defaults & Folders',
      'save': 'Save',
      'cancel': 'Cancel',
      'defaults': 'Defaults',
      'full_reset': 'Full Reset (Delete Settings.ini)',
      'pos_bottom': 'Bottom',
      'pos_top': 'Top',
      'pos_left': 'Left',
      'pos_right': 'Right',
      'language': 'Language',
      'start_with_windows': 'Run at Startup',
      'portable_ini': 'Store Settings in Portable INI (Settings.ini)',
      'minimize_to_dock': 'Minimize Windows to the Dock',
      'disable_min_anim': 'Disable Minimize Animation',
      'running_indicators': 'Running Application Indicators',
      'open_running': 'Open Running Application Instance',
      'dock_count': 'Number of Docks (1–3)',
      'editing_dock': 'Active Dock Profile',
      'show_hide_hotkey': 'Show/Hide All Docks (Ctrl+Alt+R)',
      'recycle_empty': 'Recycle Bin is empty',
      'recycle_items': 'Items in Recycle Bin',
    },
    'uk': {
      'dock_settings': 'Налаштування панелі',
      'icon_settings': 'Налаштування значка',
      'add_item': 'Додати елемент',
      'delete_item': 'Видалити елемент',
      'open_window': 'Відкрити вікно',
      'close_window': 'Закрити вікно',
      'empty_recycle_bin': 'Очистити кошик',
      'lock_items': 'Закріпити значки',
      'auto_hide': 'Автоприховування',
      'quit': 'Вихід з AeroDock',
      'save': 'Зберегти',
      'cancel': 'Скасувати',
      'defaults': 'За замовчуванням',
    },
    'de': {
      'dock_settings': 'Dock-Einstellungen',
      'icon_settings': 'Symbol-Einstellungen',
      'add_item': 'Element hinzufügen',
      'delete_item': 'Element entfernen',
      'open_window': 'Fenster öffnen',
      'close_window': 'Fenster schließen',
      'empty_recycle_bin': 'Papierkorb leeren',
      'lock_items': 'Symbole sperren',
      'auto_hide': 'Automatisch ausblenden',
      'quit': 'AeroDock beenden',
      'save': 'Speichern',
      'cancel': 'Abbrechen',
      'defaults': 'Standardwerte',
    },
    'es': {
      'dock_settings': 'Opciones del Dock',
      'icon_settings': 'Opciones del icono',
      'add_item': 'Añadir elemento',
      'delete_item': 'Eliminar elemento',
      'open_window': 'Abrir ventana',
      'close_window': 'Cerrar ventana',
      'empty_recycle_bin': 'Vaciar Papelera',
      'lock_items': 'Bloquear iconos',
      'auto_hide': 'Ocultar automáticamente',
      'quit': 'Salir de AeroDock',
      'save': 'Guardar',
      'cancel': 'Cancelar',
      'defaults': 'Predeterminados',
    },
    'fr': {
      'dock_settings': 'Paramètres du Dock',
      'icon_settings': 'Propriétés de l’icône',
      'add_item': 'Ajouter un élément',
      'delete_item': 'Supprimer l’élément',
      'open_window': 'Ouvrir la fenêtre',
      'close_window': 'Fermer la fenêtre',
      'empty_recycle_bin': 'Vider la Corbeille',
      'lock_items': 'Verrouiller les icônes',
      'auto_hide': 'Masquage automatique',
      'quit': 'Quitter AeroDock',
      'save': 'Enregistrer',
      'cancel': 'Annuler',
      'defaults': 'Par défaut',
    },
  };

  /// Load any custom *.ini language files placed in the portable Languages/ folder.
  static void loadExternalLanguages(Directory langDir) {
    _externalLangs.clear();
    _externalLangNames.clear();
    try {
      if (!langDir.existsSync()) {
        langDir.createSync(recursive: true);
        _writeLanguageTemplate(langDir, 'ru', 'Русский');
        _writeLanguageTemplate(langDir, 'en', 'English');
      }
      for (final entity in langDir.listSync()) {
        if (entity is! File) continue;
        if (p.extension(entity.path).toLowerCase() != '.ini') continue;
        final code = p.basenameWithoutExtension(entity.path).toLowerCase();
        final map = <String, String>{};
        var displayName = code.toUpperCase();
        for (final rawLine in entity.readAsLinesSync()) {
          final line = rawLine.trim();
          if (line.isEmpty || line.startsWith(';') || line.startsWith('#') || line.startsWith('[')) {
            continue;
          }
          final idx = line.indexOf('=');
          if (idx <= 0) continue;
          final k = line.substring(0, idx).trim();
          final v = line.substring(idx + 1).trim();
          if (k == 'LanguageName') {
            displayName = v;
          } else {
            map[k] = v;
          }
        }
        if (map.isNotEmpty) {
          _externalLangs[code] = map;
          _externalLangNames[code] = displayName;
        }
      }
    } catch (_) {}
  }

  static void _writeLanguageTemplate(Directory dir, String code, String name) {
    final file = File(p.join(dir.path, '$code.ini'));
    if (file.existsSync()) return;
    final dict = _builtIn[code] ?? _builtIn['en']!;
    final sb = StringBuffer()
      ..writeln('; AeroDock Language File ($name)')
      ..writeln('[Info]')
      ..writeln('LanguageName=$name')
      ..writeln('')
      ..writeln('[Strings]');
    dict.forEach((k, v) => sb.writeln('$k=$v'));
    file.writeAsStringSync(sb.toString(), flush: true);
  }

  static Map<String, String> availableLanguages() {
    final all = <String, String>{...builtInLanguageNames};
    _externalLangNames.forEach((k, v) {
      all[k] = v;
    });
    return all;
  }

  static String t(String key) {
    final ext = _externalLangs[currentCode]?[key];
    if (ext != null && ext.isNotEmpty) return ext;
    final native = _builtIn[currentCode]?[key];
    if (native != null && native.isNotEmpty) return native;
    return _builtIn['ru']?[key] ?? _builtIn['en']?[key] ?? key;
  }
}
