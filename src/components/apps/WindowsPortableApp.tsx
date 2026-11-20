import React, { useMemo, useState } from 'react';
import {
  Check,
  Code2,
  Copy,
  Download,
  FileCode2,
  FolderArchive,
  HardDriveDownload,
  Plus,
} from 'lucide-react';
import { DOCK_THEMES } from '../../data/defaults';
import { DockItem, DockSettings } from '../../types/dock';
import {
  buildFlutterDialogsDart,
  buildFlutterMainDart,
  buildFlutterModelsDart,
  buildFlutterPubspecYaml,
  buildFlutterWindowsServicesDart,
  buildGitHubActionsWorkflowYaml,
  downloadFlutterWindowsProjectZip,
} from '../../utils/flutterPortableGenerator';
import {
  WINDOWS_PRESET_APPS,
  WindowsPresetApp,
  buildPortableConfigObject,
  downloadPortableConfigOnly,
  downloadWindowsPortableZip,
} from '../../utils/windowsPortableGenerator';
import { AppIconArt } from '../AppIconArt';

interface WindowsPortableAppProps {
  items: DockItem[];
  settings: DockSettings;
  onAddWindowsPreset: (preset: WindowsPresetApp) => void;
  onOpenCustomWinAppModal: () => void;
}

type BuildTarget = 'flutter' | 'wpf';
type PresetCategory = 'all' | 'system' | 'tools' | 'apps';
type CodePreviewFile =
  | 'build-windows-portable.yml'
  | 'main.dart'
  | 'windows_services.dart'
  | 'dialogs.dart'
  | 'models.dart'
  | 'pubspec.yaml'
  | 'aerodock-config.json';

const POSITION_LABELS: Record<DockSettings['position'], string> = {
  bottom: 'Снизу',
  top: 'Сверху',
  left: 'Слева',
  right: 'Справа',
};

const FLUTTER_ARCHIVE_FILES = [
  {
    name: '.github/workflows/build-windows-portable.yml',
    role: 'GitHub Actions: сборка aerodock.exe на windows-latest + установка app_icon.ico + Release',
  },
  {
    name: 'lib/main.dart',
    role: 'Прозрачность flutter_acrylic, трей, Alt+Space, мультимониторность, Drag-and-Drop сортировка',
  },
  {
    name: 'lib/windows_services.dart',
    role: 'Извлечение родных иконок .exe/.lnk в icons/, tasklist индикаторы, автозагрузка, чтение папок',
  },
  {
    name: 'lib/dialogs.dart',
    role: 'Встроенные окна «Настройки панели», «Свойства значка» и живые стеки-папки',
  },
  {
    name: 'lib/models.dart',
    role: 'Портативное хранение aerodock-config.json и icons/ строго рядом с aerodock.exe',
  },
  {
    name: 'assets/app_icon.ico',
    role: 'Фирменный значок 32-bit RGBA для aerodock.exe и системного трея Windows',
  },
  {
    name: 'pubspec.yaml · build-portable.bat · aerodock-config.json',
    role: 'Зависимости Flutter, скрипт локальной сборки и ваша текущая конфигурация',
  },
];

const WPF_ARCHIVE_FILES = [
  {
    name: 'AeroDock-Start.vbs',
    role: 'Тихий запуск без чёрного окна консоли',
  },
  {
    name: 'AeroDock-Start.bat',
    role: 'Альтернативный запуск через командную строку',
  },
  {
    name: 'AeroDock.ps1',
    role: 'Нативная WPF-панель Windows без установки и компиляции',
  },
  {
    name: 'aerodock-config.json',
    role: 'Ваши текущие ярлыки, положение, тема и размер значков',
  },
  {
    name: 'README-RU.txt',
    role: 'Инструкция по запуску с флешки и автозагрузке',
  },
];

export const WindowsPortableApp: React.FC<WindowsPortableAppProps> = ({
  items,
  settings,
  onAddWindowsPreset,
  onOpenCustomWinAppModal,
}) => {
  const [target, setTarget] = useState<BuildTarget>('flutter');
  const [category, setCategory] = useState<PresetCategory>('all');
  const [previewFile, setPreviewFile] = useState<CodePreviewFile>('build-windows-portable.yml');
  const [copied, setCopied] = useState(false);
  const [downloadedNotice, setDownloadedNotice] = useState<string | null>(null);

  const portablePreview = useMemo(
    () => buildPortableConfigObject(items, settings),
    [items, settings]
  );

  const themeName = useMemo(
    () => DOCK_THEMES.find((t) => t.id === settings.theme)?.name ?? settings.theme,
    [settings.theme]
  );

  const filteredPresets = useMemo(() => {
    if (category === 'all') return WINDOWS_PRESET_APPS;
    return WINDOWS_PRESET_APPS.filter((p) => p.category === category);
  }, [category]);

  const pinnedPaths = useMemo(
    () =>
      new Set(
        items
          .filter((i) => i.type === 'winapp' && i.winPath)
          .map((i) => `${i.winPath?.toLowerCase()}|${(i.winArgs || '').toLowerCase()}`)
      ),
    [items]
  );

  const previewCodeContent = useMemo(() => {
    switch (previewFile) {
      case 'build-windows-portable.yml':
        return buildGitHubActionsWorkflowYaml();
      case 'main.dart':
        return buildFlutterMainDart();
      case 'windows_services.dart':
        return buildFlutterWindowsServicesDart();
      case 'dialogs.dart':
        return buildFlutterDialogsDart();
      case 'models.dart':
        return buildFlutterModelsDart();
      case 'pubspec.yaml':
        return buildFlutterPubspecYaml();
      case 'aerodock-config.json':
        return JSON.stringify(portablePreview, null, 2);
    }
  }, [previewFile, portablePreview]);

  const handleDownloadPrimary = () => {
    if (target === 'flutter') {
      downloadFlutterWindowsProjectZip(items, settings);
      setDownloadedNotice(
        'Полный проект AeroDock-Flutter-Windows.zip v2 скачан (включая flutter_acrylic, родные иконки .exe, трей, Alt+Space, живые стеки, app_icon.ico и GitHub Actions CI).'
      );
    } else {
      downloadWindowsPortableZip(items, settings);
      setDownloadedNotice(
        'Архив AeroDock-Windows-Portable.zip скачан. Распакуйте в любую папку и запустите AeroDock-Start.vbs.'
      );
    }
  };

  const handleDownloadConfig = () => {
    downloadPortableConfigOnly(items, settings);
    setDownloadedNotice(
      'Файл aerodock-config.json скачан. Положите его рядом с aerodock.exe (или AeroDock.ps1).'
    );
  };

  const handleCopyCode = async () => {
    try {
      await navigator.clipboard.writeText(previewCodeContent);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      // Clipboard API unavailable
    }
  };

  const shortcutsCount = portablePreview.items.filter((i) => i.type !== 'separator').length;
  const archiveFiles = target === 'flutter' ? FLUTTER_ARCHIVE_FILES : WPF_ARCHIVE_FILES;

  return (
    <div className="h-full flex flex-col bg-slate-900 text-slate-100">
      {/* Header Download Banner */}
      <div className="px-6 py-4 border-b border-white/10 bg-slate-950/60 space-y-3.5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          {/* Mode Switcher: Flutter vs Zero-Compile WPF */}
          <div className="flex items-center gap-1 p-1 rounded-xl bg-slate-900 border border-white/10">
            <button
              type="button"
              onClick={() => {
                setTarget('flutter');
                setDownloadedNotice(null);
              }}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-colors whitespace-nowrap cursor-pointer ${
                target === 'flutter'
                  ? 'bg-sky-500 text-slate-950'
                  : 'text-slate-300 hover:text-white'
              }`}
            >
              Flutter Windows (.exe)
            </button>
            <button
              type="button"
              onClick={() => {
                setTarget('wpf');
                setDownloadedNotice(null);
              }}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-colors whitespace-nowrap cursor-pointer ${
                target === 'wpf'
                  ? 'bg-sky-500 text-slate-950'
                  : 'text-slate-300 hover:text-white'
              }`}
            >
              Без компиляции (WPF)
            </button>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <button
              type="button"
              onClick={handleDownloadConfig}
              className="flex items-center gap-1.5 px-3 py-2 rounded-xl bg-white/8 hover:bg-white/14 border border-white/10 text-xs font-medium text-slate-200 transition-colors whitespace-nowrap cursor-pointer"
            >
              <FileCode2 className="w-3.5 h-3.5" />
              <span>Конфиг JSON</span>
            </button>
            <button
              type="button"
              onClick={handleDownloadPrimary}
              className="flex items-center gap-2 px-4 py-2 rounded-xl bg-sky-500 hover:bg-sky-400 text-slate-950 text-xs font-semibold transition-colors whitespace-nowrap cursor-pointer shadow-lg shadow-sky-500/20"
            >
              <Download className="w-4 h-4" />
              <span>
                {target === 'flutter'
                  ? 'Скачать Flutter-проект (ZIP)'
                  : 'Скачать WPF Portable (ZIP)'}
              </span>
            </button>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2 text-xs text-slate-400">
          <span className="text-slate-200 font-medium">
            {target === 'flutter'
              ? 'Портативный Flutter Desktop для Windows x64'
              : 'Мгновенный запуск на Windows 10 / 11 через .NET WPF'}
          </span>
          <span aria-hidden="true">·</span>
          <span className="font-mono text-slate-300">{shortcutsCount} ярлыков</span>
          <span aria-hidden="true">·</span>
          <span>{POSITION_LABELS[settings.position]}</span>
          <span aria-hidden="true">·</span>
          <span>{themeName}</span>
          <span aria-hidden="true">·</span>
          <span className="font-mono text-slate-300">{settings.iconSize}px</span>
        </div>
      </div>

      {/* Scrollable Body */}
      <div className="flex-1 overflow-y-auto dock-scroll p-6 space-y-6">
        {downloadedNotice && (
          <div className="px-4 py-3 rounded-xl bg-emerald-500/15 border border-emerald-400/30 text-xs text-emerald-200 flex items-center justify-between gap-3">
            <span>{downloadedNotice}</span>
            <button
              type="button"
              onClick={() => setDownloadedNotice(null)}
              className="text-emerald-300 hover:text-white shrink-0"
            >
              Скрыть
            </button>
          </div>
        )}

        {/* Flutter Code Preview Section */}
        {target === 'flutter' && (
          <section className="space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-2">
                <Code2 className="w-4 h-4 text-sky-400" />
                <h4 className="text-sm font-semibold text-white">
                  01. Исходный код Flutter-проекта (готов к сборке)
                </h4>
              </div>
              <button
                type="button"
                onClick={handleCopyCode}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/8 hover:bg-white/14 text-xs font-medium text-slate-200 transition-colors cursor-pointer"
              >
                {copied ? (
                  <>
                    <Check className="w-3.5 h-3.5 text-emerald-400" />
                    <span>Скопировано</span>
                  </>
                ) : (
                  <>
                    <Copy className="w-3.5 h-3.5" />
                    <span>Копировать файл</span>
                  </>
                )}
              </button>
            </div>

            <div className="rounded-xl border border-white/10 bg-slate-950/80 overflow-hidden">
              <div className="flex items-center gap-1 px-2.5 py-2 border-b border-white/10 bg-slate-950 overflow-x-auto">
                {(
                  [
                    'build-windows-portable.yml',
                    'main.dart',
                    'windows_services.dart',
                    'dialogs.dart',
                    'models.dart',
                    'pubspec.yaml',
                    'aerodock-config.json',
                  ] as CodePreviewFile[]
                ).map((file) => (
                  <button
                    key={file}
                    type="button"
                    onClick={() => {
                      setPreviewFile(file);
                      setCopied(false);
                    }}
                    className={`px-3 py-1 rounded-lg font-mono text-xs transition-colors whitespace-nowrap cursor-pointer ${
                      previewFile === file
                        ? 'bg-sky-500/20 text-sky-300 border border-sky-400/30'
                        : 'text-slate-400 hover:text-white border border-transparent'
                    }`}
                  >
                    {file}
                  </button>
                ))}
              </div>
              <pre className="p-4 text-[11px] font-mono text-slate-300 leading-relaxed max-h-60 overflow-auto dock-scroll select-text">
                <code>{previewCodeContent}</code>
              </pre>
            </div>
          </section>
        )}

        {/* Add Native Windows Executables before exporting */}
        <section className="space-y-3.5">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h4 className="text-sm font-semibold text-white">
                {target === 'flutter' ? '02.' : '01.'} Программы Windows (.exe) для включения в сборку
              </h4>
              <p className="text-xs text-slate-400 mt-0.5">
                Добавленные программы автоматически попадут в{' '}
                <span className="font-mono text-slate-300">aerodock-config.json</span> внутри архива.
              </p>
            </div>
            <button
              type="button"
              onClick={onOpenCustomWinAppModal}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-white/8 hover:bg-white/14 border border-white/10 text-xs font-medium text-white transition-colors whitespace-nowrap cursor-pointer"
            >
              <Plus className="w-3.5 h-3.5" />
              <span>Свой путь .exe / папка</span>
            </button>
          </div>

          <div className="flex items-center gap-1 p-1 rounded-xl bg-slate-950/70 border border-white/10 w-fit">
            {(
              [
                { id: 'all', label: 'Все' },
                { id: 'system', label: 'Система' },
                { id: 'tools', label: 'Утилиты' },
                { id: 'apps', label: 'Программы' },
              ] as { id: PresetCategory; label: string }[]
            ).map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setCategory(tab.id)}
                className={`px-3 py-1 rounded-lg text-xs font-medium transition-colors whitespace-nowrap cursor-pointer ${
                  category === tab.id
                    ? 'bg-sky-500 text-slate-950 font-semibold'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
            {filteredPresets.map((preset) => {
              const key = `${preset.winPath.toLowerCase()}|${(preset.winArgs || '').toLowerCase()}`;
              const isAdded = pinnedPaths.has(key);
              return (
                <button
                  key={preset.id}
                  type="button"
                  disabled={isAdded}
                  onClick={() => onAddWindowsPreset(preset)}
                  className={`flex items-center gap-3 p-2.5 rounded-xl border text-left transition-colors ${
                    isAdded
                      ? 'bg-emerald-500/10 border-emerald-400/25 cursor-default'
                      : 'bg-slate-950/45 border-white/8 hover:border-sky-400/40 hover:bg-white/5 cursor-pointer'
                  }`}
                >
                  <div className="w-9 h-9 shrink-0">
                    <AppIconArt iconKey={preset.iconKey} color={preset.color} title={preset.title} />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="text-xs font-medium text-slate-100 truncate">
                      {preset.title}
                    </div>
                    <div className="text-[11px] font-mono text-slate-400 truncate">
                      {preset.winPath}
                    </div>
                  </div>
                  {isAdded ? (
                    <Check className="w-4 h-4 text-emerald-400 shrink-0" />
                  ) : (
                    <Plus className="w-4 h-4 text-slate-500 shrink-0" />
                  )}
                </button>
              );
            })}
          </div>
        </section>

        {/* Archive Contents & Build Guide */}
        <section className="grid grid-cols-1 md:grid-cols-2 gap-5 pt-4 border-t border-white/10">
          <div>
            <div className="flex items-center gap-2 text-sm font-semibold text-white mb-3">
              <FolderArchive className="w-4 h-4 text-sky-400" />
              <span>Содержимое архива</span>
            </div>
            <div className="divide-y divide-white/8 border-t border-b border-white/8">
              {archiveFiles.map((file) => (
                <div key={file.name} className="py-2.5">
                  <div className="text-xs font-mono text-sky-300">{file.name}</div>
                  <div className="text-xs text-slate-400 mt-0.5">{file.role}</div>
                </div>
              ))}
            </div>
          </div>

          <div>
            <div className="flex items-center gap-2 text-sm font-semibold text-white mb-3">
              <HardDriveDownload className="w-4 h-4 text-sky-400" />
              <span>
                {target === 'flutter'
                  ? 'Облачная сборка .exe на GitHub Actions'
                  : 'Запуск без компиляции'}
              </span>
            </div>

            {target === 'flutter' ? (
              <ol className="space-y-3 text-xs text-slate-300 leading-relaxed">
                <li className="flex gap-2.5">
                  <span className="font-mono text-sky-400 shrink-0">1.</span>
                  <span>
                    Скачайте <span className="font-mono text-slate-100">AeroDock-Flutter-Windows.zip</span> и загрузите файлы (вместе с папкой <span className="font-mono text-slate-100">.github</span>) в новый репозиторий на GitHub.
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="font-mono text-sky-400 shrink-0">2.</span>
                  <span>
                    Откройте вкладку <span className="font-mono text-slate-100">Actions → Build AeroDock Windows Portable</span>: GitHub сам соберёт <span className="font-mono text-slate-100">aerodock.exe</span> на <span className="font-mono text-slate-100">windows-latest</span> без установки Flutter на ваш ПК.
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="font-mono text-sky-400 shrink-0">3.</span>
                  <span>
                    Скачайте готовый артефакт <span className="font-mono text-slate-100">AeroDock-Windows-Portable-x64</span> (или создайте тег <span className="font-mono text-slate-100">v1.0.0</span> для автопубликации в <span className="font-mono text-slate-100">Releases</span>).
                  </span>
                </li>
              </ol>
            ) : (
              <ol className="space-y-3 text-xs text-slate-300 leading-relaxed">
                <li className="flex gap-2.5">
                  <span className="font-mono text-sky-400 shrink-0">1.</span>
                  <span>
                    Распакуйте <span className="font-mono text-slate-100">AeroDock-Windows-Portable.zip</span> в любую папку или на USB-флешку.
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="font-mono text-sky-400 shrink-0">2.</span>
                  <span>
                    Запустите <span className="font-mono text-slate-100">AeroDock-Start.vbs</span> — прозрачная WPF-панель сразу откроется поверх рабочего стола.
                  </span>
                </li>
                <li className="flex gap-2.5">
                  <span className="font-mono text-sky-400 shrink-0">3.</span>
                  <span>
                    Перетаскивайте любые <span className="font-mono text-slate-100">.exe</span>, ярлыки и папки из Проводника прямо на панель.
                  </span>
                </li>
              </ol>
            )}
          </div>
        </section>
      </div>
    </div>
  );
};
