import React from 'react';
import { RotateCcw, Trash2 } from 'lucide-react';
import { DockItem } from '../../types/dock';
import { AppIconArt } from '../AppIconArt';

interface TrashAppProps {
  deletedItems: DockItem[];
  onRestoreItem: (id: string) => void;
  onEmptyTrash: () => void;
}

export const TrashApp: React.FC<TrashAppProps> = ({
  deletedItems,
  onRestoreItem,
  onEmptyTrash,
}) => {
  return (
    <div className="h-full flex flex-col text-slate-100">
      <div className="px-4 py-3 border-b border-white/10 flex items-center justify-between bg-slate-900/50">
        <div className="text-xs text-slate-300">
          Удалённые значки: <span className="font-mono text-white">{deletedItems.length}</span>
        </div>
        <button
          type="button"
          disabled={deletedItems.length === 0}
          onClick={onEmptyTrash}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-rose-500/20 hover:bg-rose-500/30 disabled:opacity-40 disabled:pointer-events-none border border-rose-400/30 text-rose-200 text-xs font-medium transition-colors cursor-pointer"
        >
          <Trash2 className="w-3.5 h-3.5" />
          Очистить корзину
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-4">
        {deletedItems.length === 0 ? (
          <div className="h-full flex flex-col items-center justify-center text-center text-xs text-slate-400 py-12">
            Корзина пуста. Перетащите любой значок далеко за пределы панели, чтобы удалить его сюда.
          </div>
        ) : (
          <div className="space-y-2">
            {deletedItems.map((item) => (
              <div
                key={item.id}
                className="flex items-center justify-between gap-3 p-3 rounded-xl bg-slate-900/60 border border-white/8"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className="w-9 h-9 shrink-0">
                    <AppIconArt
                      iconKey={item.iconKey}
                      color={item.color}
                      customImage={item.customImage}
                      title={item.title}
                    />
                  </div>
                  <div className="min-w-0">
                    <div className="text-xs font-semibold text-white truncate">{item.title}</div>
                    <div className="text-[11px] text-slate-400 truncate font-mono">
                      {item.url || item.winPath || item.type}
                    </div>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => onRestoreItem(item.id)}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/15 text-xs font-medium text-white shrink-0 transition-colors cursor-pointer"
                >
                  <RotateCcw className="w-3.5 h-3.5" />
                  Вернуть
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
