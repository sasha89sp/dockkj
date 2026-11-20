import React, { useEffect, useRef, useState } from 'react';
import { Minus, X } from 'lucide-react';
import { DesktopWindowState } from '../types/dock';

interface DesktopWindowProps {
  win: DesktopWindowState;
  isFocused: boolean;
  onFocus: () => void;
  onMove: (x: number, y: number) => void;
  onMinimize: () => void;
  onClose: () => void;
  children: React.ReactNode;
}

export const DesktopWindow: React.FC<DesktopWindowProps> = ({
  win,
  isFocused,
  onFocus,
  onMove,
  onMinimize,
  onClose,
  children,
}) => {
  const [dragging, setDragging] = useState(false);
  const dragOffset = useRef({ dx: 0, dy: 0 });

  useEffect(() => {
    if (!dragging) return;

    const handleMouseMove = (e: MouseEvent) => {
      const nextX = Math.max(8, Math.min(window.innerWidth - 220, e.clientX - dragOffset.current.dx));
      const nextY = Math.max(48, Math.min(window.innerHeight - 80, e.clientY - dragOffset.current.dy));
      onMove(nextX, nextY);
    };

    const handleMouseUp = () => {
      setDragging(false);
    };

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [dragging, onMove]);

  if (!win.isOpen || win.isMinimized) return null;

  const maxW = typeof window !== 'undefined' ? window.innerWidth - 24 : win.width;
  const maxH = typeof window !== 'undefined' ? window.innerHeight - 120 : win.height;
  const clampedWidth = Math.min(win.width, Math.max(300, maxW));
  const clampedHeight = Math.min(win.height, Math.max(300, maxH));
  const clampedLeft =
    typeof window !== 'undefined'
      ? Math.max(12, Math.min(win.x, window.innerWidth - clampedWidth - 12))
      : win.x;
  const clampedTop =
    typeof window !== 'undefined'
      ? Math.max(52, Math.min(win.y, window.innerHeight - clampedHeight - 64))
      : win.y;

  const startDrag = (e: React.MouseEvent) => {
    if ((e.target as HTMLElement).closest('button')) return;
    onFocus();
    dragOffset.current = {
      dx: e.clientX - clampedLeft,
      dy: e.clientY - clampedTop,
    };
    setDragging(true);
  };

  return (
    <section
      onMouseDown={onFocus}
      style={{
        left: clampedLeft,
        top: clampedTop,
        width: clampedWidth,
        height: clampedHeight,
        zIndex: win.zIndex,
      }}
      className={`fixed flex flex-col rounded-2xl overflow-hidden bg-slate-950/90 backdrop-blur-2xl border transition-shadow ${
        isFocused
          ? 'border-white/22 shadow-[0_24px_70px_rgba(0,0,0,0.65)]'
          : 'border-white/10 shadow-[0_14px_40px_rgba(0,0,0,0.45)]'
      }`}
    >
      {/* Window Titlebar */}
      <div
        onMouseDown={startDrag}
        className={`h-11 px-4 flex items-center justify-between gap-3 shrink-0 select-none border-b border-white/10 ${
          dragging ? 'cursor-grabbing' : 'cursor-grab'
        } ${isFocused ? 'bg-slate-900/90' : 'bg-slate-900/60'}`}
      >
        <div className="flex items-center gap-2 min-w-0">
          <h2 className="font-display text-xs font-semibold tracking-tight text-slate-100 truncate">
            {win.title}
          </h2>
        </div>

        <div className="flex items-center gap-1.5 shrink-0">
          <button
            type="button"
            onClick={onMinimize}
            title="Свернуть"
            aria-label="Свернуть окно"
            className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-400 hover:text-white hover:bg-white/10 transition-colors cursor-pointer"
          >
            <Minus className="w-3.5 h-3.5" />
          </button>
          <button
            type="button"
            onClick={onClose}
            title="Закрыть"
            aria-label="Закрыть окно"
            className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-400 hover:text-white hover:bg-rose-500/80 transition-colors cursor-pointer"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* Window Content */}
      <div className="flex-1 min-h-0 overflow-hidden bg-slate-950/40">{children}</div>
    </section>
  );
};
