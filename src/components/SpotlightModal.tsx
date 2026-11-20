import React, { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowUpRight, Search, X } from 'lucide-react';
import { DockItem } from '../types/dock';
import { AppIconArt } from './AppIconArt';

interface SpotlightModalProps {
  items: DockItem[];
  onActivateItem: (item: DockItem) => void;
  onClose: () => void;
}

export const SpotlightModal: React.FC<SpotlightModalProps> = ({
  items,
  onActivateItem,
  onClose,
}) => {
  const [query, setQuery] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const searchable = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = items.filter((item) => item.type !== 'separator');
    if (!q) return list;
    return list.filter((item) => {
      const target = (item.url || item.winPath || '').toLowerCase();
      return item.title.toLowerCase().includes(q) || target.includes(q);
    });
  }, [items, query]);

  useEffect(() => {
    setActiveIndex(0);
  }, [query]);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onClose();
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        setActiveIndex((prev) => (searchable.length ? (prev + 1) % searchable.length : 0));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setActiveIndex((prev) =>
          searchable.length ? (prev - 1 + searchable.length) % searchable.length : 0
        );
      } else if (e.key === 'Enter' && searchable[activeIndex]) {
        e.preventDefault();
        const chosen = searchable[activeIndex];
        onActivateItem(chosen);
        onClose();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [searchable, activeIndex, onActivateItem, onClose]);

  const getTypeLabel = (item: DockItem) => {
    switch (item.type) {
      case 'app':
        return 'Приложение';
      case 'winapp':
        return 'Windows .exe';
      case 'stack':
        return `Стек (${item.stackItems?.length ?? 0})`;
      case 'trash':
        return 'Система';
      default:
        return 'Ссылка';
    }
  };

  return (
    <div
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
      className="fixed inset-0 z-[120] bg-slate-950/60 backdrop-blur-sm flex items-start justify-center pt-[14vh] px-4"
    >
      <div className="w-full max-w-xl rounded-2xl bg-slate-900/95 border border-white/15 shadow-[0_24px_80px_rgba(0,0,0,0.7)] overflow-hidden">
        <div className="flex items-center gap-3 px-4 py-3.5 border-b border-white/10">
          <Search className="w-4 h-4 text-slate-400 shrink-0" />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Поиск ярлыков, программ и стеков…"
            className="flex-1 bg-transparent text-sm text-white placeholder:text-slate-500 focus:outline-none"
          />
          <button
            type="button"
            onClick={onClose}
            aria-label="Закрыть поиск"
            className="p-1 rounded-lg text-slate-400 hover:text-white hover:bg-white/10 transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="max-h-80 overflow-y-auto py-2">
          {searchable.length === 0 ? (
            <div className="px-4 py-8 text-center text-xs text-slate-400">
              Ничего не найдено по запросу «{query}»
            </div>
          ) : (
            searchable.map((item, idx) => {
              const isSelected = idx === activeIndex;
              const rowClass = `w-full px-4 py-2.5 flex items-center gap-3 text-left transition-colors cursor-pointer ${
                isSelected ? 'bg-sky-500/20 text-white' : 'text-slate-200 hover:bg-white/5'
              }`;

              const inner = (
                <>
                  <div className="w-8 h-8 shrink-0">
                    <AppIconArt
                      iconKey={item.iconKey}
                      color={item.color}
                      customImage={item.customImage}
                      title={item.title}
                    />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium truncate">{item.title}</div>
                    <div className="text-[11px] text-slate-400 truncate font-mono">
                      {item.url || item.winPath || getTypeLabel(item)}
                    </div>
                  </div>
                  <span className="text-[11px] text-slate-400 shrink-0 flex items-center gap-1">
                    {getTypeLabel(item)}
                    {item.type === 'link' && <ArrowUpRight className="w-3 h-3" />}
                  </span>
                </>
              );

              if (item.type === 'link' && item.url) {
                return (
                  <a
                    key={item.id}
                    href={item.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    onMouseEnter={() => setActiveIndex(idx)}
                    onClick={() => {
                      onActivateItem(item);
                      onClose();
                    }}
                    className={rowClass}
                  >
                    {inner}
                  </a>
                );
              }

              return (
                <button
                  key={item.id}
                  type="button"
                  onMouseEnter={() => setActiveIndex(idx)}
                  onClick={() => {
                    onActivateItem(item);
                    onClose();
                  }}
                  className={rowClass}
                >
                  {inner}
                </button>
              );
            })
          )}
        </div>

        <div className="px-4 py-2 border-t border-white/10 flex items-center justify-between text-[11px] text-slate-500">
          <span>↑↓ навигация · Enter запуск</span>
          <span>Esc закрыть</span>
        </div>
      </div>
    </div>
  );
};
