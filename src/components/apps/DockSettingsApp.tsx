import React, { useRef, useState } from 'react';
import {
  Download,
  Image as ImageIcon,
  Layers,
  Monitor,
  Palette,
  RotateCcw,
  Sliders,
  Upload,
} from 'lucide-react';
import { DOCK_THEMES, WALLPAPERS } from '../../data/defaults';
import {
  DockPosition,
  DockSettings,
  HoverEffect,
  LaunchAnimation,
} from '../../types/dock';

interface DockSettingsAppProps {
  settings: DockSettings;
  onUpdateSettings: (patch: Partial<DockSettings>) => void;
  onExportConfig: () => void;
  onImportConfig: (jsonText: string) => { ok: boolean; message: string };
  onResetDefaults: () => void;
}

type SettingsTab = 'general' | 'icons' | 'position' | 'style' | 'wallpaper';

export const DockSettingsApp: React.FC<DockSettingsAppProps> = ({
  settings,
  onUpdateSettings,
  onExportConfig,
  onImportConfig,
  onResetDefaults,
}) => {
  const [tab, setTab] = useState<SettingsTab>('general');
  const [statusMsg, setStatusMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const importInputRef = useRef<HTMLInputElement>(null);
  const wpInputRef = useRef<HTMLInputElement>(null);

  const tabs: { id: SettingsTab; label: string; icon: React.ReactNode }[] = [
    { id: 'general', label: 'Общие', icon: <Sliders className="w-4 h-4" /> },
    { id: 'icons', label: 'Значки', icon: <Layers className="w-4 h-4" /> },
    { id: 'position', label: 'Положение', icon: <Monitor className="w-4 h-4" /> },
    { id: 'style', label: 'Стиль', icon: <Palette className="w-4 h-4" /> },
    { id: 'wallpaper', label: 'Обои', icon: <ImageIcon className="w-4 h-4" /> },
  ];

  const handleImportFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const res = onImportConfig(String(reader.result || ''));
      setStatusMsg({ ok: res.ok, text: res.message });
    };
    reader.readAsText(file);
    e.target.value = '';
  };

  const handleWallpaperUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      onUpdateSettings({
        wallpaperId: 'custom',
        customWallpaper: String(reader.result || ''),
      });
    };
    reader.readAsDataURL(file);
    e.target.value = '';
  };

  return (
    <div className="h-full flex text-slate-100">
      {/* Sidebar navigation */}
      <aside className="w-48 shrink-0 border-r border-white/10 bg-slate-900/50 p-3 flex flex-col justify-between">
        <div className="space-y-1">
          {tabs.map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={() => setTab(item.id)}
              className={`w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-xs font-medium transition-colors cursor-pointer ${
                tab === item.id
                  ? 'bg-sky-500/20 text-sky-200 border border-sky-400/25'
                  : 'text-slate-300 hover:bg-white/5 hover:text-white border border-transparent'
              }`}
            >
              {item.icon}
              <span>{item.label}</span>
            </button>
          ))}
        </div>

        <div className="pt-3 border-t border-white/10 space-y-1.5">
          <button
            type="button"
            onClick={onExportConfig}
            className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-xs text-slate-300 hover:text-white hover:bg-white/5 transition-colors cursor-pointer"
          >
            <Download className="w-3.5 h-3.5" />
            Экспорт JSON
          </button>
          <button
            type="button"
            onClick={() => importInputRef.current?.click()}
            className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-xs text-slate-300 hover:text-white hover:bg-white/5 transition-colors cursor-pointer"
          >
            <Upload className="w-3.5 h-3.5" />
            Импорт JSON
          </button>
          <button
            type="button"
            onClick={() => {
              onResetDefaults();
              setStatusMsg({ ok: true, text: 'Настройки сброшены по умолчанию' });
            }}
            className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-xs text-rose-300 hover:text-rose-200 hover:bg-rose-500/10 transition-colors cursor-pointer"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            Сбросить всё
          </button>
          <input
            ref={importInputRef}
            type="file"
            accept="application/json"
            onChange={handleImportFile}
            className="hidden"
          />
        </div>
      </aside>

      {/* Main settings panel */}
      <div className="flex-1 overflow-y-auto p-6 space-y-6">
        {statusMsg && (
          <div
            className={`px-3.5 py-2.5 rounded-xl text-xs border ${
              statusMsg.ok
                ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-200'
                : 'bg-rose-500/10 border-rose-500/30 text-rose-200'
            }`}
          >
            {statusMsg.text}
          </div>
        )}

        {tab === 'general' && (
          <div className="space-y-5">
            <div>
              <h3 className="font-display text-base font-semibold text-white">Общие параметры</h3>
              <p className="text-xs text-slate-400 mt-1">
                Управление поведением панели, подписями и защитой значков.
              </p>
            </div>

            <div className="space-y-3">
              {[
                {
                  label: 'Автоскрытие панели',
                  desc: 'Скрывать док у края экрана, пока курсор не приблизится к границе.',
                  checked: settings.autoHide,
                  onChange: (v: boolean) => onUpdateSettings({ autoHide: v }),
                },
                {
                  label: 'Закрепить значки',
                  desc: 'Запретить случайное перетаскивание и удаление ярлыков с панели.',
                  checked: settings.lockIcons,
                  onChange: (v: boolean) => onUpdateSettings({ lockIcons: v }),
                },
                {
                  label: 'Подписи при наведении',
                  desc: 'Показывать всплывающее название ярлыка над активным значком.',
                  checked: settings.showLabels,
                  onChange: (v: boolean) => onUpdateSettings({ showLabels: v }),
                },
                {
                  label: 'Отражение значков',
                  desc: 'Зеркальный блик на нижней стеклянной полке (для нижнего расположения).',
                  checked: settings.showReflections,
                  onChange: (v: boolean) => onUpdateSettings({ showReflections: v }),
                },
                {
                  label: 'Часы на рабочем столе',
                  desc: 'Показывать крупные часы и дату по центру рабочего стола.',
                  checked: settings.showDesktopClock,
                  onChange: (v: boolean) => onUpdateSettings({ showDesktopClock: v }),
                },
              ].map((toggle) => (
                <label
                  key={toggle.label}
                  className="flex items-start justify-between gap-4 p-3.5 rounded-xl bg-slate-900/60 border border-white/8 cursor-pointer hover:border-white/15 transition-colors"
                >
                  <div>
                    <div className="text-sm font-medium text-white">{toggle.label}</div>
                    <div className="text-xs text-slate-400 mt-0.5">{toggle.desc}</div>
                  </div>
                  <input
                    type="checkbox"
                    checked={toggle.checked}
                    onChange={(e) => toggle.onChange(e.target.checked)}
                    className="mt-1 h-4 w-4 accent-sky-500 cursor-pointer"
                  />
                </label>
              ))}
            </div>
          </div>
        )}

        {tab === 'icons' && (
          <div className="space-y-5">
            <div>
              <h3 className="font-display text-base font-semibold text-white">
                Размер и увеличение значков
              </h3>
              <p className="text-xs text-slate-400 mt-1">
                Настройте волновой эффект увеличения (Bubble Zoom) как в классическом RocketDock.
              </p>
            </div>

            <div className="space-y-4">
              <div className="p-4 rounded-xl bg-slate-900/60 border border-white/8 space-y-3">
                <div className="flex justify-between text-xs">
                  <span className="text-slate-200 font-medium">Базовый размер значков</span>
                  <span className="font-mono text-sky-300">{settings.iconSize} px</span>
                </div>
                <input
                  type="range"
                  min={38}
                  max={76}
                  value={settings.iconSize}
                  onChange={(e) => onUpdateSettings({ iconSize: Number(e.target.value) })}
                  className="w-full accent-sky-500"
                />
              </div>

              <div className="p-4 rounded-xl bg-slate-900/60 border border-white/8 space-y-3">
                <div className="flex justify-between text-xs">
                  <span className="text-slate-200 font-medium">Коэффициент увеличения</span>
                  <span className="font-mono text-sky-300">{settings.zoomScale.toFixed(2)}×</span>
                </div>
                <input
                  type="range"
                  min={1}
                  max={2}
                  step={0.05}
                  value={settings.zoomScale}
                  onChange={(e) => onUpdateSettings({ zoomScale: Number(e.target.value) })}
                  className="w-full accent-sky-500"
                />
              </div>

              <div className="p-4 rounded-xl bg-slate-900/60 border border-white/8 space-y-3">
                <div className="flex justify-between text-xs">
                  <span className="text-slate-200 font-medium">Радиус волны увеличения</span>
                  <span className="font-mono text-sky-300">{settings.zoomSpan.toFixed(1)} значка</span>
                </div>
                <input
                  type="range"
                  min={1}
                  max={4}
                  step={0.5}
                  value={settings.zoomSpan}
                  onChange={(e) => onUpdateSettings({ zoomSpan: Number(e.target.value) })}
                  className="w-full accent-sky-500"
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="p-4 rounded-xl bg-slate-900/60 border border-white/8 space-y-2.5">
                  <div className="text-xs font-medium text-slate-200">Эффект наведения</div>
                  <div className="flex flex-col gap-1.5">
                    {(
                      [
                        ['bubble', 'Волна (Bubble)'],
                        ['lift', 'Подъём вверх'],
                        ['none', 'Без увеличения'],
                      ] as [HoverEffect, string][]
                    ).map(([id, label]) => (
                      <button
                        key={id}
                        type="button"
                        onClick={() => onUpdateSettings({ hoverEffect: id })}
                        className={`px-3 py-1.5 rounded-lg text-xs text-left border transition-colors cursor-pointer ${
                          settings.hoverEffect === id
                            ? 'bg-sky-500/20 border-sky-400/40 text-sky-200'
                            : 'bg-slate-950/50 border-white/10 text-slate-300 hover:border-white/20'
                        }`}
                      >
                        {label}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="p-4 rounded-xl bg-slate-900/60 border border-white/8 space-y-2.5">
                  <div className="text-xs font-medium text-slate-200">Анимация запуска</div>
                  <div className="flex flex-col gap-1.5">
                    {(
                      [
                        ['bounce', 'Прыжок (Bounce)'],
                        ['pulse', 'Импульс'],
                        ['none', 'Отключена'],
                      ] as [LaunchAnimation, string][]
                    ).map(([id, label]) => (
                      <button
                        key={id}
                        type="button"
                        onClick={() => onUpdateSettings({ launchAnimation: id })}
                        className={`px-3 py-1.5 rounded-lg text-xs text-left border transition-colors cursor-pointer ${
                          settings.launchAnimation === id
                            ? 'bg-sky-500/20 border-sky-400/40 text-sky-200'
                            : 'bg-slate-950/50 border-white/10 text-slate-300 hover:border-white/20'
                        }`}
                      >
                        {label}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {tab === 'position' && (
          <div className="space-y-5">
            <div>
              <h3 className="font-display text-base font-semibold text-white">
                Расположение на экране
              </h3>
              <p className="text-xs text-slate-400 mt-1">
                Закрепите панель у любой из четырёх сторон экрана и задайте точные отступы.
              </p>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
              {(
                [
                  ['bottom', 'Снизу'],
                  ['top', 'Сверху'],
                  ['left', 'Слева'],
                  ['right', 'Справа'],
                ] as [DockPosition, string][]
              ).map(([pos, label]) => (
                <button
                  key={pos}
                  type="button"
                  onClick={() => onUpdateSettings({ position: pos })}
                  className={`py-3 rounded-xl text-xs font-semibold border transition-colors cursor-pointer ${
                    settings.position === pos
                      ? 'bg-sky-500/20 border-sky-400/40 text-sky-200'
                      : 'bg-slate-900/60 border-white/10 text-slate-300 hover:border-white/20'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>

            <div className="p-4 rounded-xl bg-slate-900/60 border border-white/8 space-y-3">
              <div className="flex justify-between text-xs">
                <span className="text-slate-200 font-medium">Отступ от края экрана</span>
                <span className="font-mono text-sky-300">{settings.edgeOffset} px</span>
              </div>
              <input
                type="range"
                min={0}
                max={48}
                value={settings.edgeOffset}
                onChange={(e) => onUpdateSettings({ edgeOffset: Number(e.target.value) })}
                className="w-full accent-sky-500"
              />
            </div>

            <div className="p-4 rounded-xl bg-slate-900/60 border border-white/8 space-y-3">
              <div className="flex justify-between text-xs">
                <span className="text-slate-200 font-medium">Смещение от центра</span>
                <span className="font-mono text-sky-300">{settings.centerOffset}%</span>
              </div>
              <input
                type="range"
                min={-35}
                max={35}
                value={settings.centerOffset}
                onChange={(e) => onUpdateSettings({ centerOffset: Number(e.target.value) })}
                className="w-full accent-sky-500"
              />
            </div>
          </div>
        )}

        {tab === 'style' && (
          <div className="space-y-5">
            <div>
              <h3 className="font-display text-base font-semibold text-white">Тема оформления</h3>
              <p className="text-xs text-slate-400 mt-1">
                6 встроенных скинов панели — синхронизируются с портативной версией для Windows.
              </p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {DOCK_THEMES.map((theme) => {
                const active = settings.theme === theme.id;
                return (
                  <button
                    key={theme.id}
                    type="button"
                    onClick={() => onUpdateSettings({ theme: theme.id })}
                    className={`p-3.5 rounded-xl text-left border transition-all cursor-pointer ${
                      active
                        ? 'bg-sky-500/15 border-sky-400/45'
                        : 'bg-slate-900/60 border-white/10 hover:border-white/25'
                    }`}
                  >
                    <div
                      className="h-9 rounded-lg mb-2.5 border"
                      style={{
                        background: theme.previewBg,
                        borderColor: theme.previewBorder,
                      }}
                    />
                    <div className="text-xs font-semibold text-white">{theme.name}</div>
                    <div className="text-[11px] text-slate-400 mt-0.5 leading-snug">
                      {theme.description}
                    </div>
                  </button>
                );
              })}
            </div>

            <div className="p-4 rounded-xl bg-slate-900/60 border border-white/8 space-y-3">
              <div className="flex justify-between text-xs">
                <span className="text-slate-200 font-medium">Непрозрачность подложки</span>
                <span className="font-mono text-sky-300">{settings.opacity}%</span>
              </div>
              <input
                type="range"
                min={25}
                max={100}
                value={settings.opacity}
                onChange={(e) => onUpdateSettings({ opacity: Number(e.target.value) })}
                className="w-full accent-sky-500"
              />
            </div>
          </div>
        )}

        {tab === 'wallpaper' && (
          <div className="space-y-5">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h3 className="font-display text-base font-semibold text-white">
                  Обои рабочего стола
                </h3>
                <p className="text-xs text-slate-400 mt-1">
                  Выберите фон для предпросмотра прозрачности панели или загрузите свой.
                </p>
              </div>
              <button
                type="button"
                onClick={() => wpInputRef.current?.click()}
                className="px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/15 border border-white/15 text-xs font-medium text-white shrink-0 cursor-pointer"
              >
                Загрузить файл
              </button>
              <input
                ref={wpInputRef}
                type="file"
                accept="image/*"
                onChange={handleWallpaperUpload}
                className="hidden"
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              {WALLPAPERS.map((wp) => {
                const active = settings.wallpaperId === wp.id;
                return (
                  <button
                    key={wp.id}
                    type="button"
                    onClick={() => onUpdateSettings({ wallpaperId: wp.id })}
                    className={`group rounded-xl overflow-hidden text-left border transition-all cursor-pointer ${
                      active
                        ? 'border-sky-400 ring-2 ring-sky-400/30'
                        : 'border-white/10 hover:border-white/25'
                    }`}
                  >
                    <div
                      className="h-28 w-full relative overflow-hidden"
                      style={{ background: wp.fallbackGradient }}
                    >
                      <img
                        src={wp.url}
                        alt={wp.name}
                        referrerPolicy="no-referrer"
                        className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                      />
                    </div>
                    <div className="p-2.5 bg-slate-900/90">
                      <div className="text-xs font-semibold text-white">{wp.name}</div>
                      <div className="text-[11px] text-slate-400">{wp.subtitle}</div>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
