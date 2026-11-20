import React, { useMemo, useState } from 'react';
import { ArrowUpRight, Plus, Search } from 'lucide-react';
import { DockItem } from '../../types/dock';
import { AppIconArt } from '../AppIconArt';

interface LauncherAppProps {
  items: DockItem[];
  onActivateItem: (item: DockItem) => void;
  onAddNewItem: () => void;
}

type CategoryFilter = 'all' | 'app' | 'winapp' | 'link' | 'stack';

export const LauncherApp: React.FC<LauncherAppProps> = ({
  items,
  onActivateItem,
  onAddNewItem,
}) => {
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<CategoryFilter>('all');

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items.filter((item) => {
      if (item.type === 'separator') return false;
      if (filter !== 'all') {
        if (filter === 'app' && item.type !== 'app' && item.type !== 'trash') return false;
        if (filter !== 'app' && item.type !== filter) return false;
      }
      if (!q) return true;
      return (
        item.title.toLowerCase().includes(q) ||
        (item.url || '').toLowerCase().includes(q) ||
        (item.winPath || '').toLowerCase().includes(q)
      );
    });
  }, [items, query, filter]);

  const categories: { id: CategoryFilter; label: string }[] = [
    { id: 'all', label: 'Все' },
    { id: 'app', label: 'Приложения' },
    { id: 'winapp', label: 'Windows .exe' },
    { id: 'stack', label: 'Стеки' },
    { id: 'link', label: 'Веб-ярлыки' },
  ];

  return (
    <div className="h-full flex flex-col text-slate-100">
      <div className="p-4 border-b border-white/10 space-y-3 bg-slate-900/50">
        <div className="flex items-center gap-2.5">
          <div className="relative flex-1">
            <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Фильтр по названию или пути…"
              className="w-full pl-9 pr-3 py-2 rounded-xl bg-slate-950/70 border border-white/10 text-xs text-white placeholder:text-slate-500 focus:outline-none focus:border-sky-400/50"
            />
          </div>
          <button
            type="button"
            onClick={onAddNewItem}
            className="flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-sky-500 hover:bg-sky-400 text-slate-950 text-xs font-semibold transition-colors shrink-0 cursor-pointer"
          >
            <Plus className="w-3.5 h-3.5" />
            Добавить
          </button>
        </div>

        <div className="flex items-center gap-1.5 overflow-x-auto">
          {categories.map((cat) => (
            <button
              key={cat.id}
              type="button"
              onClick={() => setFilter(cat.id)}
              className={`px-3 py-1 rounded-lg text-xs font-medium transition-colors whitespace-nowrap cursor-pointer ${
                filter === cat.id
                  ? 'bg-white/15 text-white'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-white/5'
              }`}
            >
              {cat.label}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4">
        {filtered.length === 0 ? (
          <div className="h-full flex flex-col items-center justify-center text-center text-xs text-slate-400 py-12">
            Ярлыки в этой категории пока не найдены.
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
            {filtered.map((item) => {
              const cardClass =
                'group flex flex-col items-center text-center p-3.5 rounded-xl bg-slate-900/55 hover:bg-slate-800/75 border border-white/8 hover:border-white/20 transition-all cursor-pointer';

              const body = (
                <>
                  <div className="w-12 h-12 mb-2.5 group-hover:scale-105 transition-transform">
                    <AppIconArt
                      iconKey={item.iconKey}
                      color={item.color}
                      customImage={item.customImage}
                      title={item.title}
                    />
                  </div>
                  <div className="text-xs font-medium text-slate-100 line-clamp-1 w-full">
                    {item.title}
                  </div>
                  <div className="text-[10px] text-slate-400 mt-0.5 line-clamp-1 w-full flex items-center justify-center gap-0.5">
                    {item.type === 'winapp'
                      ? item.winPath || 'Windows'
                      : item.type === 'stack'
                      ? `${item.stackItems?.length ?? 0} элем.`
                      : item.type === 'link'
                      ? 'Веб-ссылка'
                      : 'Встроенное'}
                    {item.type === 'link' && <ArrowUpRight className="w-2.5 h-2.5 shrink-0" />}
                  </div>
                </>
              );

              if (item.type === 'link' && item.url) {
                return (
                  <a
                    key={item.id}
                    href={item.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    onClick={() => onActivateItem(item)}
                    className={cardClass}
                  >
                    {body}
                  </a>
                );
              }

              return (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => onActivateItem(item)}
                  className={cardClass}
                >
                  {body}
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
