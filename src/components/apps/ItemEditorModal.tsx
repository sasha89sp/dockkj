import React, { useRef, useState } from 'react';
import { Plus, Trash2, Upload, X } from 'lucide-react';
import { ICON_COLORS, ICON_GALLERY } from '../../data/defaults';
import { DockItem, DockItemType, IconGlyphKey, StackEntry } from '../../types/dock';
import { AppIconArt } from '../AppIconArt';

interface ItemEditorModalProps {
  initialItem?: DockItem | null;
  defaultType?: DockItemType;
  onSave: (item: DockItem) => void;
  onClose: () => void;
}

export const ItemEditorModal: React.FC<ItemEditorModalProps> = ({
  initialItem,
  defaultType = 'link',
  onSave,
  onClose,
}) => {
  const isEditing = Boolean(initialItem);
  const [type, setType] = useState<DockItemType>(initialItem?.type ?? defaultType);
  const [title, setTitle] = useState(initialItem?.title ?? '');
  const [url, setUrl] = useState(initialItem?.url ?? 'https://');
  const [winPath, setWinPath] = useState(initialItem?.winPath ?? 'C:\\Windows\\notepad.exe');
  const [winArgs, setWinArgs] = useState(initialItem?.winArgs ?? '');
  const [iconKey, setIconKey] = useState<IconGlyphKey>(
    initialItem?.iconKey ??
      (defaultType === 'stack'
        ? 'folder-blue'
        : defaultType === 'winapp'
          ? 'windows'
          : 'globe')
  );
  const [color, setColor] = useState(initialItem?.color ?? '#0284c7');
  const [customImage, setCustomImage] = useState<string | undefined>(initialItem?.customImage);
  const [stackItems, setStackItems] = useState<StackEntry[]>(
    initialItem?.stackItems ?? [
      { id: `st-${Date.now()}`, title: 'Документация', url: 'https://developer.mozilla.org', iconKey: 'book', color: '#2563eb' },
    ]
  );

  // New stack sub-item draft
  const [newSubTitle, setNewSubTitle] = useState('');
  const [newSubUrl, setNewSubUrl] = useState('https://');
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === 'string') {
        setCustomImage(reader.result);
      }
    };
    reader.readAsDataURL(file);
  };

  const handleAddStackEntry = () => {
    const cleanTitle = newSubTitle.trim();
    const cleanUrl = newSubUrl.trim();
    if (!cleanTitle || !cleanUrl) return;
    const normalizedUrl = /^https?:\/\//i.test(cleanUrl) ? cleanUrl : `https://${cleanUrl}`;
    setStackItems((prev) => [
      ...prev,
      {
        id: `st-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
        title: cleanTitle,
        url: normalizedUrl,
        iconKey: 'globe',
        color: ICON_COLORS[prev.length % ICON_COLORS.length].value,
      },
    ]);
    setNewSubTitle('');
    setNewSubUrl('https://');
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const finalTitle =
      title.trim() ||
      (type === 'stack'
        ? 'Новая папка'
        : type === 'winapp'
          ? 'Программа Windows'
          : 'Новый ярлык');
    const cleanUrl = url.trim();
    const normalizedUrl =
      type === 'link'
        ? /^https?:\/\//i.test(cleanUrl)
          ? cleanUrl
          : `https://${cleanUrl}`
        : undefined;

    onSave({
      id: initialItem?.id ?? `item-${Date.now()}`,
      type,
      appId: initialItem?.appId,
      title: finalTitle,
      url: normalizedUrl,
      winPath: type === 'winapp' ? winPath.trim() : undefined,
      winArgs: type === 'winapp' && winArgs.trim() ? winArgs.trim() : undefined,
      iconKey,
      color,
      customImage,
      stackItems: type === 'stack' ? stackItems : undefined,
    });
  };

  const isBuiltInApp = initialItem?.type === 'app' || initialItem?.type === 'trash';

  return (
    <div
      className="fixed inset-0 z-[110] bg-slate-950/65 backdrop-blur-sm flex items-center justify-center p-4"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-xl rounded-2xl bg-slate-900 border border-white/15 shadow-2xl overflow-hidden flex flex-col max-h-[88vh]"
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-white/10 bg-slate-950/50">
          <h2 className="text-base font-semibold text-white">
            {isEditing ? 'Настройка значка' : 'Добавить элемент на панель'}
          </h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Закрыть"
            className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-400 hover:text-white hover:bg-white/10"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-5 overflow-y-auto dock-scroll space-y-5">
          {/* Type Switcher (for new items) */}
          {!isBuiltInApp && (
            <div className="flex items-center gap-1.5 p-1 rounded-xl bg-slate-950/70 border border-white/10">
              <button
                type="button"
                onClick={() => {
                  setType('link');
                  if (iconKey.startsWith('folder-')) setIconKey('globe');
                }}
                className={`flex-1 py-2 px-2.5 rounded-lg text-xs font-semibold transition-colors whitespace-nowrap ${
                  type === 'link'
                    ? 'bg-sky-500 text-slate-950'
                    : 'text-slate-300 hover:text-white'
                }`}
              >
                Веб-ссылка
              </button>
              <button
                type="button"
                onClick={() => {
                  setType('winapp');
                  if (iconKey === 'globe') setIconKey('windows');
                }}
                className={`flex-1 py-2 px-2.5 rounded-lg text-xs font-semibold transition-colors whitespace-nowrap ${
                  type === 'winapp'
                    ? 'bg-sky-500 text-slate-950'
                    : 'text-slate-300 hover:text-white'
                }`}
              >
                Windows (.exe / папка)
              </button>
              <button
                type="button"
                onClick={() => {
                  setType('stack');
                  if (!iconKey.startsWith('folder-')) setIconKey('folder-blue');
                }}
                className={`flex-1 py-2 px-2.5 rounded-lg text-xs font-semibold transition-colors whitespace-nowrap ${
                  type === 'stack'
                    ? 'bg-sky-500 text-slate-950'
                    : 'text-slate-300 hover:text-white'
                }`}
              >
                Папка (Стек)
              </button>
            </div>
          )}

          {/* Live Preview + Title / URL / WinPath */}
          <div className="flex items-start gap-4">
            <div className="shrink-0 flex flex-col items-center gap-2">
              <div className="w-16 h-16">
                <AppIconArt
                  iconKey={iconKey}
                  color={color}
                  customImage={customImage}
                  title={title || 'Предпросмотр'}
                />
              </div>
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                className="flex items-center gap-1 text-[11px] font-medium text-sky-400 hover:text-sky-300"
              >
                <Upload className="w-3 h-3" />
                Свой PNG
              </button>
              {customImage && (
                <button
                  type="button"
                  onClick={() => setCustomImage(undefined)}
                  className="text-[11px] text-rose-400 hover:text-rose-300"
                >
                  Убрать фото
                </button>
              )}
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                onChange={handleImageUpload}
                className="hidden"
              />
            </div>

            <div className="flex-1 space-y-3">
              <div>
                <label className="block text-xs font-medium text-slate-300 mb-1">Название</label>
                <input
                  type="text"
                  required
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder={
                    type === 'stack'
                      ? 'Например: Инструменты'
                      : type === 'winapp'
                        ? 'Например: Total Commander'
                        : 'Например: Telegram Web'
                  }
                  className="w-full px-3 py-2 rounded-xl bg-slate-950/70 border border-white/12 text-sm text-white placeholder:text-slate-500 focus:outline-none focus:border-sky-400"
                />
              </div>

              {type === 'link' && (
                <div>
                  <label className="block text-xs font-medium text-slate-300 mb-1">
                    Адрес ссылки (URL)
                  </label>
                  <input
                    type="text"
                    required
                    value={url}
                    onChange={(e) => setUrl(e.target.value)}
                    placeholder="https://example.com"
                    className="w-full px-3 py-2 rounded-xl bg-slate-950/70 border border-white/12 text-sm font-mono text-white placeholder:text-slate-500 focus:outline-none focus:border-sky-400"
                  />
                </div>
              )}

              {type === 'winapp' && (
                <>
                  <div>
                    <label className="block text-xs font-medium text-slate-300 mb-1">
                      Путь к программе или папке Windows
                    </label>
                    <input
                      type="text"
                      required
                      value={winPath}
                      onChange={(e) => setWinPath(e.target.value)}
                      placeholder="C:\Program Files\App\app.exe или notepad.exe"
                      className="w-full px-3 py-2 rounded-xl bg-slate-950/70 border border-white/12 text-xs font-mono text-white placeholder:text-slate-500 focus:outline-none focus:border-sky-400"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-slate-300 mb-1">
                      Аргументы запуска (необязательно)
                    </label>
                    <input
                      type="text"
                      value={winArgs}
                      onChange={(e) => setWinArgs(e.target.value)}
                      placeholder="--incognito или путь к файлу"
                      className="w-full px-3 py-2 rounded-xl bg-slate-950/70 border border-white/12 text-xs font-mono text-white placeholder:text-slate-500 focus:outline-none focus:border-sky-400"
                    />
                  </div>
                </>
              )}
            </div>
          </div>

          {/* Stack Contents Editor */}
          {type === 'stack' && (
            <div className="space-y-3 pt-2 border-t border-white/10">
              <div className="text-xs font-semibold text-slate-200">
                Содержимое стека ({stackItems.length})
              </div>

              <div className="space-y-1.5 max-h-36 overflow-y-auto dock-scroll">
                {stackItems.map((entry) => (
                  <div
                    key={entry.id}
                    className="flex items-center justify-between gap-2 px-3 py-1.5 rounded-xl bg-slate-950/50 border border-white/8"
                  >
                    <div className="min-w-0">
                      <div className="text-xs font-medium text-slate-100 truncate">{entry.title}</div>
                      <div className="text-[11px] font-mono text-slate-400 truncate">{entry.url}</div>
                    </div>
                    <button
                      type="button"
                      onClick={() =>
                        setStackItems((prev) => prev.filter((item) => item.id !== entry.id))
                      }
                      aria-label="Удалить ссылку из стека"
                      className="p-1.5 rounded-lg text-slate-400 hover:text-rose-400 hover:bg-rose-500/10"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                ))}
              </div>

              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={newSubTitle}
                  onChange={(e) => setNewSubTitle(e.target.value)}
                  placeholder="Название ссылки"
                  className="w-36 px-2.5 py-1.5 rounded-lg bg-slate-950/70 border border-white/12 text-xs text-white placeholder:text-slate-500 focus:outline-none focus:border-sky-400"
                />
                <input
                  type="text"
                  value={newSubUrl}
                  onChange={(e) => setNewSubUrl(e.target.value)}
                  placeholder="https://..."
                  className="flex-1 px-2.5 py-1.5 rounded-lg bg-slate-950/70 border border-white/12 text-xs font-mono text-white placeholder:text-slate-500 focus:outline-none focus:border-sky-400"
                />
                <button
                  type="button"
                  onClick={handleAddStackEntry}
                  className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/15 text-xs font-medium text-white whitespace-nowrap"
                >
                  <Plus className="w-3.5 h-3.5" />
                  Добавить
                </button>
              </div>
            </div>
          )}

          {/* Color Palette */}
          {!customImage && (
            <div>
              <div className="text-xs font-medium text-slate-300 mb-2">Цвет подложки значка</div>
              <div className="flex items-center gap-2 flex-wrap">
                {ICON_COLORS.map((swatch) => (
                  <button
                    key={swatch.value}
                    type="button"
                    title={swatch.label}
                    onClick={() => setColor(swatch.value)}
                    className={`w-7 h-7 rounded-full transition-transform ${
                      color === swatch.value
                        ? 'scale-110 ring-2 ring-white ring-offset-2 ring-offset-slate-900'
                        : 'hover:scale-105'
                    }`}
                    style={{ backgroundColor: swatch.value }}
                  />
                ))}
              </div>
            </div>
          )}

          {/* Icon Gallery */}
          {!customImage && (
            <div>
              <div className="text-xs font-medium text-slate-300 mb-2">Галерея значков</div>
              <div className="grid grid-cols-6 sm:grid-cols-8 gap-2">
                {ICON_GALLERY.map((item) => {
                  const selected = iconKey === item.key;
                  return (
                    <button
                      key={item.key}
                      type="button"
                      title={item.label}
                      onClick={() => setIconKey(item.key)}
                      className={`p-1.5 rounded-xl flex items-center justify-center transition-all border ${
                        selected
                          ? 'bg-sky-500/20 border-sky-400 scale-105'
                          : 'bg-slate-950/40 border-white/5 hover:border-white/20'
                      }`}
                    >
                      <div className="w-9 h-9">
                        <AppIconArt iconKey={item.key} color={color} />
                      </div>
                    </button>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-2.5 px-5 py-3.5 border-t border-white/10 bg-slate-950/50">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-xl text-xs font-medium text-slate-300 hover:text-white hover:bg-white/8 transition-colors"
          >
            Отмена
          </button>
          <button
            type="submit"
            className="px-4 py-2 rounded-xl text-xs font-semibold bg-sky-500 hover:bg-sky-400 text-slate-950 transition-colors"
          >
            {isEditing ? 'Сохранить изменения' : 'Добавить на панель'}
          </button>
        </div>
      </form>
    </div>
  );
};
