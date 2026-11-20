import React, { useEffect, useRef } from 'react';

export interface ContextMenuEntry {
  id: string;
  label: string;
  icon?: React.ReactNode;
  shortcut?: string;
  danger?: boolean;
  checked?: boolean;
  dividerBefore?: boolean;
  onSelect: () => void;
}

interface ContextMenuProps {
  x: number;
  y: number;
  title?: string;
  entries: ContextMenuEntry[];
  onClose: () => void;
}

export const ContextMenu: React.FC<ContextMenuProps> = ({
  x,
  y,
  title,
  entries,
  onClose,
}) => {
  const menuRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    const handlePointer = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKey);
    window.addEventListener('mousedown', handlePointer);
    return () => {
      window.removeEventListener('keydown', handleKey);
      window.removeEventListener('mousedown', handlePointer);
    };
  }, [onClose]);

  // Clamp coordinates so menu never overflows viewport edges
  const menuWidth = 236;
  const estimatedHeight = entries.length * 36 + (title ? 34 : 14);
  const clampedX = Math.min(x, Math.max(8, window.innerWidth - menuWidth - 12));
  const clampedY = Math.min(y, Math.max(8, window.innerHeight - estimatedHeight - 12));

  return (
    <div
      ref={menuRef}
      role="menu"
      style={{ left: clampedX, top: clampedY, width: menuWidth }}
      className="fixed z-[100] rounded-xl bg-slate-900/95 text-slate-100 border border-white/15 shadow-2xl backdrop-blur-xl py-1.5"
    >
      {title && (
        <div className="px-3 py-1.5 text-[11px] font-medium text-slate-400 truncate border-b border-white/10 mb-1">
          {title}
        </div>
      )}
      {entries.map((entry) => (
        <React.Fragment key={entry.id}>
          {entry.dividerBefore && <div className="my-1 border-t border-white/10" />}
          <button
            type="button"
            role="menuitem"
            onClick={() => {
              entry.onSelect();
              onClose();
            }}
            className={`w-full flex items-center justify-between gap-2 px-3 py-1.5 text-left text-xs font-medium transition-colors ${
              entry.danger
                ? 'text-rose-400 hover:bg-rose-500/15 hover:text-rose-300'
                : 'text-slate-200 hover:bg-sky-500/20 hover:text-white'
            }`}
          >
            <span className="flex items-center gap-2 min-w-0 truncate">
              {entry.icon && <span className="w-3.5 h-3.5 shrink-0 opacity-80">{entry.icon}</span>}
              <span className="truncate">{entry.label}</span>
            </span>
            {entry.checked !== undefined ? (
              <span className="text-[11px] font-mono text-sky-400 shrink-0">
                {entry.checked ? 'Вкл' : 'Выкл'}
              </span>
            ) : entry.shortcut ? (
              <span className="text-[11px] font-mono text-slate-500 shrink-0">{entry.shortcut}</span>
            ) : null}
          </button>
        </React.Fragment>
      ))}
    </div>
  );
};
