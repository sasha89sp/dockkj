/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Download,
  EyeOff,
  FolderPlus,
  Image,
  Lock,
  Minus,
  Monitor,
  Pencil,
  Plus,
  Search,
  SeparatorVertical,
  Settings,
  Trash2,
} from 'lucide-react';
import { ContextMenu, ContextMenuEntry } from './components/ContextMenu';
import { DesktopWindow } from './components/DesktopWindow';
import { DockBar } from './components/DockBar';
import { SpotlightModal } from './components/SpotlightModal';
import { CalculatorApp } from './components/apps/CalculatorApp';
import { ClockApp } from './components/apps/ClockApp';
import { DockSettingsApp } from './components/apps/DockSettingsApp';
import { ItemEditorModal } from './components/apps/ItemEditorModal';
import { LauncherApp } from './components/apps/LauncherApp';
import { NotesApp } from './components/apps/NotesApp';
import { TrashApp } from './components/apps/TrashApp';
import { WindowsPortableApp } from './components/apps/WindowsPortableApp';
import { WindowsPresetApp } from './utils/windowsPortableGenerator';
import {
  DEFAULT_DOCK_ITEMS,
  DEFAULT_DOCK_SETTINGS,
  DEFAULT_NOTES,
  DEFAULT_WINDOWS,
  WALLPAPERS,
} from './data/defaults';
import {
  BuiltInAppId,
  DesktopWindowState,
  DockItem,
  DockItemType,
  DockSettings,
  NoteEntry,
  PoofParticle,
} from './types/dock';

const STORAGE_KEYS = {
  items: 'aerodock_items_v1',
  settings: 'aerodock_settings_v1',
  trash: 'aerodock_trash_v1',
  notes: 'aerodock_notes_v1',
};

function loadStored<T>(key: string, fallback: T): T {
  try {
    const raw = window.localStorage.getItem(key);
    if (!raw) return fallback;
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

export default function App() {
  const [items, setItems] = useState<DockItem[]>(() => {
    const stored = loadStored<DockItem[]>(STORAGE_KEYS.items, DEFAULT_DOCK_ITEMS);
    // Ensure Windows Portable icon exists for users migrating from earlier session
    if (!stored.some((i) => i.appId === 'portable')) {
      const portableItem = DEFAULT_DOCK_ITEMS.find((i) => i.appId === 'portable');
      if (portableItem) {
        const settingsIdx = stored.findIndex((i) => i.appId === 'settings');
        const next = [...stored];
        if (settingsIdx >= 0) next.splice(settingsIdx, 0, portableItem);
        else next.push(portableItem);
        return next;
      }
    }
    return stored;
  });
  const [settings, setSettings] = useState<DockSettings>(() => ({
    ...DEFAULT_DOCK_SETTINGS,
    ...loadStored<Partial<DockSettings>>(STORAGE_KEYS.settings, {}),
  }));
  const [deletedItems, setDeletedItems] = useState<DockItem[]>(() =>
    loadStored(STORAGE_KEYS.trash, [])
  );
  const [notes, setNotes] = useState<NoteEntry[]>(() =>
    loadStored(STORAGE_KEYS.notes, DEFAULT_NOTES)
  );

  const [windows, setWindows] = useState<Record<BuiltInAppId, DesktopWindowState>>(
    () => DEFAULT_WINDOWS
  );
  const [topZ, setTopZ] = useState(32);
  const [focusedApp, setFocusedApp] = useState<BuiltInAppId | null>('portable');
  const [winToast, setWinToast] = useState<{ title: string; path: string } | null>(null);

  const [bouncingId, setBouncingId] = useState<string | null>(null);
  const [poofs, setPoofs] = useState<PoofParticle[]>([]);
  const [wallpaperFailed, setWallpaperFailed] = useState(false);

  // Modals & Menus
  const [editorState, setEditorState] = useState<{
    open: boolean;
    item?: DockItem | null;
    defaultType?: DockItemType;
  }>({ open: false });
  const [spotlightOpen, setSpotlightOpen] = useState(false);
  const [contextMenu, setContextMenu] = useState<{
    x: number;
    y: number;
    title?: string;
    entries: ContextMenuEntry[];
  } | null>(null);

  // Live desktop clock
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(id);
  }, []);

  // Persist to localStorage
  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEYS.items, JSON.stringify(items));
    } catch {
      // Storage quota exceeded; ignore silently
    }
  }, [items]);

  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEYS.settings, JSON.stringify(settings));
    } catch {
      // Storage quota exceeded
    }
  }, [settings]);

  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEYS.trash, JSON.stringify(deletedItems));
    } catch {
      // ignore
    }
  }, [deletedItems]);

  useEffect(() => {
    try {
      window.localStorage.setItem(STORAGE_KEYS.notes, JSON.stringify(notes));
    } catch {
      // ignore
    }
  }, [notes]);

  // Global keyboard shortcut Ctrl+K / Cmd+K for Spotlight Quick Launch
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setSpotlightOpen((prev) => !prev);
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  const currentWallpaper = useMemo(() => {
    if (settings.wallpaperId === 'custom' && settings.customWallpaper) {
      return {
        id: 'custom',
        name: 'Пользовательские обои',
        subtitle: '',
        url: settings.customWallpaper,
        fallbackGradient: 'linear-gradient(135deg, #0f172a 0%, #1e293b 100%)',
      };
    }
    return WALLPAPERS.find((w) => w.id === settings.wallpaperId) ?? WALLPAPERS[0];
  }, [settings.wallpaperId, settings.customWallpaper]);

  useEffect(() => {
    setWallpaperFailed(false);
  }, [currentWallpaper.url]);

  const updateSettings = useCallback((patch: Partial<DockSettings>) => {
    setSettings((prev) => ({ ...prev, ...patch }));
  }, []);

  const focusWindow = useCallback(
    (appId: BuiltInAppId) => {
      setTopZ((prevZ) => {
        const nextZ = prevZ + 1;
        setWindows((prev) => ({
          ...prev,
          [appId]: { ...prev[appId], zIndex: nextZ, isMinimized: false, isOpen: true },
        }));
        return nextZ;
      });
      setFocusedApp(appId);
    },
    []
  );

  const openOrToggleApp = useCallback(
    (appId: BuiltInAppId) => {
      const win = windows[appId];
      if (win.isOpen && !win.isMinimized && focusedApp === appId) {
        // Clicking the currently focused app minimizes it cleanly (classic dock behavior)
        setWindows((prev) => ({
          ...prev,
          [appId]: { ...prev[appId], isMinimized: true },
        }));
        setFocusedApp(null);
      } else {
        focusWindow(appId);
      }
    },
    [windows, focusedApp, focusWindow]
  );

  const closeWindow = useCallback((appId: BuiltInAppId) => {
    setWindows((prev) => ({
      ...prev,
      [appId]: { ...prev[appId], isOpen: false, isMinimized: false },
    }));
    setFocusedApp((prev) => (prev === appId ? null : prev));
  }, []);

  const minimizeWindow = useCallback((appId: BuiltInAppId) => {
    setWindows((prev) => ({
      ...prev,
      [appId]: { ...prev[appId], isMinimized: true },
    }));
    setFocusedApp((prev) => (prev === appId ? null : prev));
  }, []);

  const minimizeAllWindows = useCallback(() => {
    setWindows((prev) => {
      const next = { ...prev };
      (Object.keys(next) as BuiltInAppId[]).forEach((key) => {
        if (next[key].isOpen) {
          next[key] = { ...next[key], isMinimized: true };
        }
      });
      return next;
    });
    setFocusedApp(null);
  }, []);

  const moveWindow = useCallback((appId: BuiltInAppId, x: number, y: number) => {
    setWindows((prev) => ({
      ...prev,
      [appId]: { ...prev[appId], x, y },
    }));
  }, []);

  const triggerBounce = useCallback((itemId: string) => {
    setBouncingId(itemId);
    window.setTimeout(() => {
      setBouncingId((curr) => (curr === itemId ? null : curr));
    }, 640);
  }, []);

  const handleActivateItem = useCallback(
    (item: DockItem) => {
      triggerBounce(item.id);
      if ((item.type === 'app' || item.type === 'trash') && item.appId) {
        openOrToggleApp(item.appId);
      } else if (item.type === 'winapp' && item.winPath) {
        setWinToast({
          title: item.title,
          path: item.winArgs ? `${item.winPath} ${item.winArgs}` : item.winPath,
        });
      }
    },
    [triggerBounce, openOrToggleApp]
  );

  const handleAddWindowsPreset = useCallback((preset: WindowsPresetApp) => {
    setItems((prev) => {
      const exists = prev.some(
        (i) =>
          i.type === 'winapp' &&
          i.winPath?.toLowerCase() === preset.winPath.toLowerCase() &&
          (i.winArgs || '').toLowerCase() === (preset.winArgs || '').toLowerCase()
      );
      if (exists) return prev;
      const newItem: DockItem = {
        id: `win-${preset.id}-${Date.now()}`,
        type: 'winapp',
        title: preset.title,
        winPath: preset.winPath,
        winArgs: preset.winArgs,
        iconKey: preset.iconKey,
        color: preset.color,
      };
      const portableIdx = prev.findIndex((i) => i.appId === 'portable');
      if (portableIdx > 0) {
        const copy = [...prev];
        copy.splice(portableIdx, 0, newItem);
        return copy;
      }
      return [...prev, newItem];
    });
  }, []);

  const handleReorderItems = useCallback((fromIndex: number, toIndex: number) => {
    setItems((prev) => {
      const copy = [...prev];
      const [moved] = copy.splice(fromIndex, 1);
      copy.splice(toIndex, 0, moved);
      return copy;
    });
  }, []);

  const spawnPoof = useCallback((x: number, y: number) => {
    const id = `poof-${Date.now()}-${Math.random()}`;
    setPoofs((prev) => [...prev, { id, x, y }]);
    window.setTimeout(() => {
      setPoofs((prev) => prev.filter((p) => p.id !== id));
    }, 460);
  }, []);

  const handleRemoveItem = useCallback(
    (item: DockItem, coords?: { x: number; y: number }) => {
      if (item.type === 'trash' || item.appId === 'settings') return;
      setItems((prev) => prev.filter((i) => i.id !== item.id));
      setDeletedItems((prev) => [item, ...prev]);
      if (coords) {
        spawnPoof(coords.x, coords.y);
      }
    },
    [spawnPoof]
  );

  const handleAddSeparator = useCallback(() => {
    setItems((prev) => {
      const sep: DockItem = {
        id: `sep-${Date.now()}`,
        type: 'separator',
        title: 'Разделитель',
        iconKey: 'star',
        color: '#64748b',
      };
      // Insert right before Settings/Trash pair if present
      const settingsIdx = prev.findIndex((i) => i.appId === 'settings');
      if (settingsIdx > 0) {
        const next = [...prev];
        next.splice(settingsIdx, 0, sep);
        return next;
      }
      return [...prev, sep];
    });
  }, []);

  const handleSaveItem = useCallback((saved: DockItem) => {
    setItems((prev) => {
      const exists = prev.some((i) => i.id === saved.id);
      if (exists) {
        return prev.map((i) => (i.id === saved.id ? saved : i));
      }
      const settingsIdx = prev.findIndex((i) => i.appId === 'settings');
      if (settingsIdx > 0) {
        const next = [...prev];
        next.splice(settingsIdx, 0, saved);
        return next;
      }
      return [...prev, saved];
    });
    setEditorState({ open: false });
  }, []);

  const handleRestoreFromTrash = useCallback((id: string) => {
    setDeletedItems((prev) => {
      const target = prev.find((i) => i.id === id);
      if (target) {
        setItems((curr) => {
          if (curr.some((x) => x.id === target.id)) return curr;
          const settingsIdx = curr.findIndex((i) => i.appId === 'settings');
          if (settingsIdx > 0) {
            const copy = [...curr];
            copy.splice(settingsIdx, 0, target);
            return copy;
          }
          return [...curr, target];
        });
      }
      return prev.filter((i) => i.id !== id);
    });
  }, []);

  const handleCycleWallpaper = useCallback(() => {
    const idx = WALLPAPERS.findIndex((w) => w.id === settings.wallpaperId);
    const next = WALLPAPERS[(idx + 1) % WALLPAPERS.length];
    updateSettings({ wallpaperId: next.id });
  }, [settings.wallpaperId, updateSettings]);

  const handleExportConfig = useCallback(() => {
    const payload = {
      version: 1,
      exportedAt: new Date().toISOString(),
      settings,
      items,
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'aerodock-profile.json';
    a.click();
    URL.revokeObjectURL(url);
  }, [settings, items]);

  const handleImportConfig = useCallback((jsonText: string) => {
    try {
      const parsed = JSON.parse(jsonText) as {
        settings?: Partial<DockSettings>;
        items?: DockItem[];
      };
      if (parsed.settings && typeof parsed.settings === 'object') {
        setSettings((prev) => ({ ...prev, ...parsed.settings }));
      }
      if (Array.isArray(parsed.items) && parsed.items.length > 0) {
        setItems(parsed.items);
      }
      return { ok: true, message: 'Профиль успешно импортирован' };
    } catch {
      return { ok: false, message: 'Не удалось прочитать JSON-файл конфигурации' };
    }
  }, []);

  const handleResetDefaults = useCallback(() => {
    setItems(DEFAULT_DOCK_ITEMS);
    setSettings(DEFAULT_DOCK_SETTINGS);
    setDeletedItems([]);
  }, []);

  // Context Menu builders
  const openItemContextMenu = useCallback(
    (e: React.MouseEvent, item: DockItem) => {
      const entries: ContextMenuEntry[] = [];

      if (item.type !== 'separator') {
        entries.push({
          id: 'edit',
          label: 'Настроить значок…',
          icon: <Pencil className="w-3.5 h-3.5" />,
          onSelect: () => setEditorState({ open: true, item }),
        });
      }

      entries.push(
        {
          id: 'add-link',
          label: 'Добавить ярлык…',
          icon: <Plus className="w-3.5 h-3.5" />,
          dividerBefore: entries.length > 0,
          onSelect: () => setEditorState({ open: true, item: null, defaultType: 'link' }),
        },
        {
          id: 'add-winapp',
          label: 'Добавить программу Windows (.exe)…',
          icon: <Monitor className="w-3.5 h-3.5" />,
          onSelect: () => setEditorState({ open: true, item: null, defaultType: 'winapp' }),
        },
        {
          id: 'add-stack',
          label: 'Добавить папку (Стек)…',
          icon: <FolderPlus className="w-3.5 h-3.5" />,
          onSelect: () => setEditorState({ open: true, item: null, defaultType: 'stack' }),
        },
        {
          id: 'add-sep',
          label: 'Добавить разделитель',
          icon: <SeparatorVertical className="w-3.5 h-3.5" />,
          onSelect: handleAddSeparator,
        },
        {
          id: 'portable-win',
          label: 'Скачать Windows Portable…',
          icon: <Download className="w-3.5 h-3.5" />,
          dividerBefore: true,
          onSelect: () => focusWindow('portable'),
        },
        {
          id: 'lock',
          label: 'Закрепить значки',
          icon: <Lock className="w-3.5 h-3.5" />,
          checked: settings.lockIcons,
          onSelect: () => updateSettings({ lockIcons: !settings.lockIcons }),
        },
        {
          id: 'autohide',
          label: 'Автоскрытие панели',
          icon: <EyeOff className="w-3.5 h-3.5" />,
          checked: settings.autoHide,
          onSelect: () => updateSettings({ autoHide: !settings.autoHide }),
        },
        {
          id: 'dock-settings',
          label: 'Настройки панели…',
          icon: <Settings className="w-3.5 h-3.5" />,
          onSelect: () => focusWindow('settings'),
        }
      );

      if (item.type !== 'trash' && item.appId !== 'settings') {
        entries.push({
          id: 'remove',
          label: 'Удалить с панели',
          icon: <Trash2 className="w-3.5 h-3.5" />,
          danger: true,
          dividerBefore: true,
          onSelect: () => handleRemoveItem(item, { x: e.clientX, y: e.clientY }),
        });
      }

      setContextMenu({
        x: e.clientX,
        y: e.clientY,
        title: item.title,
        entries,
      });
    },
    [
      handleAddSeparator,
      settings.lockIcons,
      settings.autoHide,
      updateSettings,
      focusWindow,
      handleRemoveItem,
    ]
  );

  const openDockContextMenu = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      e.stopPropagation();
      setContextMenu({
        x: e.clientX,
        y: e.clientY,
        title: 'Панель AeroDock',
        entries: [
          {
            id: 'add-link',
            label: 'Добавить ярлык…',
            icon: <Plus className="w-3.5 h-3.5" />,
            onSelect: () => setEditorState({ open: true, item: null, defaultType: 'link' }),
          },
          {
            id: 'add-stack',
            label: 'Добавить папку (Стек)…',
            icon: <FolderPlus className="w-3.5 h-3.5" />,
            onSelect: () => setEditorState({ open: true, item: null, defaultType: 'stack' }),
          },
          {
            id: 'add-sep',
            label: 'Добавить разделитель',
            icon: <SeparatorVertical className="w-3.5 h-3.5" />,
            onSelect: handleAddSeparator,
          },
          {
            id: 'lock',
            label: 'Закрепить значки',
            icon: <Lock className="w-3.5 h-3.5" />,
            checked: settings.lockIcons,
            dividerBefore: true,
            onSelect: () => updateSettings({ lockIcons: !settings.lockIcons }),
          },
          {
            id: 'autohide',
            label: 'Автоскрытие панели',
            icon: <EyeOff className="w-3.5 h-3.5" />,
            checked: settings.autoHide,
            onSelect: () => updateSettings({ autoHide: !settings.autoHide }),
          },
          {
            id: 'settings',
            label: 'Настройки панели…',
            icon: <Settings className="w-3.5 h-3.5" />,
            dividerBefore: true,
            onSelect: () => focusWindow('settings'),
          },
        ],
      });
    },
    [handleAddSeparator, settings.lockIcons, settings.autoHide, updateSettings, focusWindow]
  );

  const openDesktopContextMenu = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      setContextMenu({
        x: e.clientX,
        y: e.clientY,
        title: 'Рабочий стол',
        entries: [
          {
            id: 'new-shortcut',
            label: 'Добавить ярлык на панель…',
            icon: <Plus className="w-3.5 h-3.5" />,
            onSelect: () => setEditorState({ open: true, item: null, defaultType: 'link' }),
          },
          {
            id: 'spotlight',
            label: 'Быстрый поиск',
            icon: <Search className="w-3.5 h-3.5" />,
            shortcut: 'Ctrl+K',
            onSelect: () => setSpotlightOpen(true),
          },
          {
            id: 'next-wp',
            label: 'Следующие обои',
            icon: <Image className="w-3.5 h-3.5" />,
            dividerBefore: true,
            onSelect: handleCycleWallpaper,
          },
          {
            id: 'min-all',
            label: 'Свернуть все окна',
            icon: <Minus className="w-3.5 h-3.5" />,
            onSelect: minimizeAllWindows,
          },
          {
            id: 'dock-cfg',
            label: 'Настройки панели…',
            icon: <Settings className="w-3.5 h-3.5" />,
            dividerBefore: true,
            onSelect: () => focusWindow('settings'),
          },
        ],
      });
    },
    [handleCycleWallpaper, minimizeAllWindows, focusWindow]
  );

  const openAppIds = useMemo(
    () =>
      (Object.keys(windows) as BuiltInAppId[]).filter((id) => windows[id].isOpen),
    [windows]
  );

  const anyVisibleWindow = useMemo(
    () =>
      (Object.keys(windows) as BuiltInAppId[]).some(
        (id) => windows[id].isOpen && !windows[id].isMinimized
      ),
    [windows]
  );

  return (
    <div
      onContextMenu={openDesktopContextMenu}
      className="relative w-screen h-screen overflow-hidden bg-slate-950 text-slate-100"
      style={{ background: currentWallpaper.fallbackGradient }}
    >
      {/* Full-bleed Curated Wallpaper */}
      {!wallpaperFailed && (
        <img
          src={currentWallpaper.url}
          alt={currentWallpaper.name}
          referrerPolicy="no-referrer"
          onError={() => setWallpaperFailed(true)}
          className="pointer-events-none absolute inset-0 w-full h-full object-cover select-none transition-opacity duration-500"
        />
      )}

      {/* Subtle atmospheric contrast scrim */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 bg-gradient-to-b from-slate-950/45 via-transparent to-slate-950/55"
      />

      {/* Top Bar (Strict 3-zone contract: Brand — 4 concise links — 1 primary CTA) */}
      <header className="relative z-40 h-11 px-6 flex items-center justify-between gap-8 bg-slate-950/45 backdrop-blur-xl border-b border-white/10">
        {/* Zone 1: Single-line Brand Title */}
        <button
          type="button"
          onClick={minimizeAllWindows}
          className="font-display text-sm font-bold tracking-tight text-white whitespace-nowrap shrink-0 cursor-pointer"
        >
          AeroDock
        </button>

        {/* Zone 2: 4 concise single-line text nav controls */}
        <nav className="hidden sm:flex items-center gap-6 text-xs font-medium text-slate-200/90">
          <button
            type="button"
            onClick={() => focusWindow('launcher')}
            className="hover:text-white hover:underline underline-offset-4 transition-colors whitespace-nowrap shrink-0 cursor-pointer"
          >
            Каталог
          </button>
          <button
            type="button"
            onClick={() => setSpotlightOpen(true)}
            className="hover:text-white hover:underline underline-offset-4 transition-colors whitespace-nowrap shrink-0 cursor-pointer"
          >
            Поиск
          </button>
          <button
            type="button"
            onClick={() => focusWindow('settings')}
            className="hover:text-white hover:underline underline-offset-4 transition-colors whitespace-nowrap shrink-0 cursor-pointer"
          >
            Настройки
          </button>
          <button
            type="button"
            onClick={() => focusWindow('portable')}
            className="hover:text-white hover:underline underline-offset-4 transition-colors whitespace-nowrap shrink-0 cursor-pointer"
          >
            Windows Portable
          </button>
        </nav>

        {/* Zone 3: 1 primary action */}
        <div className="shrink-0">
          <button
            type="button"
            onClick={() => setEditorState({ open: true, item: null, defaultType: 'link' })}
            className="px-3.5 py-1.5 rounded-lg bg-white/14 hover:bg-white/22 border border-white/15 text-xs font-medium text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer"
          >
            Добавить ярлык
          </button>
        </div>
      </header>

      {/* Desktop Ambient Centerpiece Clock (optional in Settings) */}
      {settings.showDesktopClock && (
        <main
          className={`pointer-events-none absolute inset-x-0 top-[15vh] flex flex-col items-center text-center px-6 transition-opacity duration-300 ${
            anyVisibleWindow ? 'opacity-25' : 'opacity-100'
          }`}
        >
          <div className="font-mono text-6xl sm:text-7xl font-semibold tracking-tight text-white drop-shadow-[0_6px_28px_rgba(0,0,0,0.55)]">
            {now.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' })}
          </div>
          <p className="mt-2 text-sm sm:text-base font-medium text-slate-100/90 capitalize drop-shadow-[0_2px_12px_rgba(0,0,0,0.65)]">
            {now.toLocaleDateString('ru-RU', {
              weekday: 'long',
              day: 'numeric',
              month: 'long',
            })}
          </p>
          <p className="mt-5 text-xs text-slate-200/75 drop-shadow-[0_2px_8px_rgba(0,0,0,0.75)]">
            ПКМ по панели или рабочему столу для настройки · Ctrl+K для быстрого запуска
          </p>
        </main>
      )}

      {/* Draggable Built-In Application Windows */}
      <DesktopWindow
        win={windows.portable}
        isFocused={focusedApp === 'portable'}
        onFocus={() => focusWindow('portable')}
        onMove={(x, y) => moveWindow('portable', x, y)}
        onMinimize={() => minimizeWindow('portable')}
        onClose={() => closeWindow('portable')}
      >
        <WindowsPortableApp
          items={items}
          settings={settings}
          onAddWindowsPreset={handleAddWindowsPreset}
          onOpenCustomWinAppModal={() =>
            setEditorState({ open: true, item: null, defaultType: 'winapp' })
          }
        />
      </DesktopWindow>

      <DesktopWindow
        win={windows.settings}
        isFocused={focusedApp === 'settings'}
        onFocus={() => focusWindow('settings')}
        onMove={(x, y) => moveWindow('settings', x, y)}
        onMinimize={() => minimizeWindow('settings')}
        onClose={() => closeWindow('settings')}
      >
        <DockSettingsApp
          settings={settings}
          onUpdateSettings={updateSettings}
          onExportConfig={handleExportConfig}
          onImportConfig={handleImportConfig}
          onResetDefaults={handleResetDefaults}
        />
      </DesktopWindow>

      <DesktopWindow
        win={windows.launcher}
        isFocused={focusedApp === 'launcher'}
        onFocus={() => focusWindow('launcher')}
        onMove={(x, y) => moveWindow('launcher', x, y)}
        onMinimize={() => minimizeWindow('launcher')}
        onClose={() => closeWindow('launcher')}
      >
        <LauncherApp
          items={items}
          onActivateItem={handleActivateItem}
          onAddNewItem={() => setEditorState({ open: true, item: null, defaultType: 'link' })}
        />
      </DesktopWindow>

      <DesktopWindow
        win={windows.notes}
        isFocused={focusedApp === 'notes'}
        onFocus={() => focusWindow('notes')}
        onMove={(x, y) => moveWindow('notes', x, y)}
        onMinimize={() => minimizeWindow('notes')}
        onClose={() => closeWindow('notes')}
      >
        <NotesApp notes={notes} onChangeNotes={setNotes} />
      </DesktopWindow>

      <DesktopWindow
        win={windows.calculator}
        isFocused={focusedApp === 'calculator'}
        onFocus={() => focusWindow('calculator')}
        onMove={(x, y) => moveWindow('calculator', x, y)}
        onMinimize={() => minimizeWindow('calculator')}
        onClose={() => closeWindow('calculator')}
      >
        <CalculatorApp />
      </DesktopWindow>

      <DesktopWindow
        win={windows.clock}
        isFocused={focusedApp === 'clock'}
        onFocus={() => focusWindow('clock')}
        onMove={(x, y) => moveWindow('clock', x, y)}
        onMinimize={() => minimizeWindow('clock')}
        onClose={() => closeWindow('clock')}
      >
        <ClockApp />
      </DesktopWindow>

      <DesktopWindow
        win={windows.trash}
        isFocused={focusedApp === 'trash'}
        onFocus={() => focusWindow('trash')}
        onMove={(x, y) => moveWindow('trash', x, y)}
        onMinimize={() => minimizeWindow('trash')}
        onClose={() => closeWindow('trash')}
      >
        <TrashApp
          deletedItems={deletedItems}
          onRestoreItem={handleRestoreFromTrash}
          onEmptyTrash={() => setDeletedItems([])}
        />
      </DesktopWindow>

      {/* Poof cloud effect when dragging icons off the dock */}
      {poofs.map((poof) => (
        <div
          key={poof.id}
          aria-hidden="true"
          style={{ left: poof.x - 32, top: poof.y - 32 }}
          className="pointer-events-none fixed z-[130] w-16 h-16 animate-poof"
        >
          <svg viewBox="0 0 64 64" className="w-full h-full">
            <circle cx="24" cy="28" r="12" fill="rgba(241,245,249,0.75)" />
            <circle cx="38" cy="24" r="14" fill="rgba(226,232,240,0.8)" />
            <circle cx="42" cy="38" r="11" fill="rgba(248,250,252,0.7)" />
            <circle cx="26" cy="40" r="12" fill="rgba(226,232,240,0.75)" />
          </svg>
        </div>
      ))}

      {/* Notice when clicking a native Windows .exe shortcut inside browser preview */}
      {winToast && (
        <div className="fixed top-14 right-5 z-[95] w-80 rounded-xl bg-slate-900/95 border border-white/15 shadow-2xl backdrop-blur-xl p-3.5 text-xs">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="font-semibold text-white truncate">
                Ярлык Windows: {winToast.title}
              </div>
              <div className="font-mono text-[11px] text-sky-300 truncate mt-0.5">
                {winToast.path}
              </div>
              <p className="text-slate-400 mt-1.5 leading-snug">
                В браузере локальные .exe заблокированы — запустится напрямую в портативной версии Windows.
              </p>
            </div>
            <button
              type="button"
              onClick={() => setWinToast(null)}
              className="text-slate-400 hover:text-white shrink-0"
              aria-label="Закрыть уведомление"
            >
              ×
            </button>
          </div>
          <div className="mt-2.5 flex items-center justify-end gap-2">
            <button
              type="button"
              onClick={() => {
                setWinToast(null);
                focusWindow('portable');
              }}
              className="px-3 py-1.5 rounded-lg bg-sky-500 hover:bg-sky-400 text-slate-950 font-semibold transition-colors cursor-pointer"
            >
              Открыть Windows Portable
            </button>
          </div>
        </div>
      )}

      {/* Main RocketDock-style DockBar */}
      <DockBar
        items={items}
        settings={settings}
        openAppIds={openAppIds}
        trashCount={deletedItems.length}
        bouncingId={bouncingId}
        onActivateItem={handleActivateItem}
        onReorderItems={handleReorderItems}
        onRemoveItemByDrag={(item, x, y) => handleRemoveItem(item, { x, y })}
        onItemContextMenu={openItemContextMenu}
        onDockContextMenu={openDockContextMenu}
        onEditItem={(item) => setEditorState({ open: true, item })}
      />

      {/* Context Menu */}
      {contextMenu && (
        <ContextMenu
          x={contextMenu.x}
          y={contextMenu.y}
          title={contextMenu.title}
          entries={contextMenu.entries}
          onClose={() => setContextMenu(null)}
        />
      )}

      {/* Add / Edit Dock Item Modal */}
      {editorState.open && (
        <ItemEditorModal
          initialItem={editorState.item}
          defaultType={editorState.defaultType}
          onSave={handleSaveItem}
          onClose={() => setEditorState({ open: false })}
        />
      )}

      {/* Ctrl+K Quick Search Modal */}
      {spotlightOpen && (
        <SpotlightModal
          items={items}
          onActivateItem={handleActivateItem}
          onClose={() => setSpotlightOpen(false)}
        />
      )}
    </div>
  );
}
