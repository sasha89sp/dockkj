import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ExternalLink, Pencil, Plus } from 'lucide-react';
import { BuiltInAppId, DockItem, DockSettings } from '../types/dock';
import { AppIconArt } from './AppIconArt';

interface DockBarProps {
  items: DockItem[];
  settings: DockSettings;
  openAppIds: BuiltInAppId[];
  trashCount: number;
  bouncingId: string | null;
  onActivateItem: (item: DockItem) => void;
  onReorderItems: (fromIndex: number, toIndex: number) => void;
  onRemoveItemByDrag: (item: DockItem, clientX: number, clientY: number) => void;
  onItemContextMenu: (e: React.MouseEvent, item: DockItem) => void;
  onDockContextMenu: (e: React.MouseEvent) => void;
  onEditItem: (item: DockItem) => void;
}

export const DockBar: React.FC<DockBarProps> = ({
  items,
  settings,
  openAppIds,
  trashCount,
  bouncingId,
  onActivateItem,
  onReorderItems,
  onRemoveItemByDrag,
  onItemContextMenu,
  onDockContextMenu,
  onEditItem,
}) => {
  const isHorizontal = settings.position === 'bottom' || settings.position === 'top';
  const dockRef = useRef<HTMLDivElement | null>(null);
  const itemRefs = useRef<(HTMLDivElement | null)[]>([]);

  const [mouseAxis, setMouseAxis] = useState<number | null>(null);
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const [openStackId, setOpenStackId] = useState<string | null>(null);
  const [isAutoReveal, setIsAutoReveal] = useState(false);

  // Drag state
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const [dragOverIndex, setDragOverIndex] = useState<number | null>(null);
  const dragStartCoords = useRef<{ x: number; y: number } | null>(null);

  // Close open stack on click outside
  useEffect(() => {
    if (!openStackId) return;
    const handlePointerDown = (ev: MouseEvent) => {
      if (dockRef.current && !dockRef.current.contains(ev.target as Node)) {
        setOpenStackId(null);
      }
    };
    window.addEventListener('mousedown', handlePointerDown);
    return () => window.removeEventListener('mousedown', handlePointerDown);
  }, [openStackId]);

  const handleDockMouseMove = useCallback(
    (e: React.MouseEvent) => {
      if (settings.hoverEffect === 'none') {
        if (mouseAxis !== null) setMouseAxis(null);
        return;
      }
      setMouseAxis(isHorizontal ? e.clientX : e.clientY);
    },
    [isHorizontal, settings.hoverEffect, mouseAxis]
  );

  const handleDockMouseLeave = useCallback(() => {
    setMouseAxis(null);
    setHoveredId(null);
    if (settings.autoHide && !openStackId) {
      setIsAutoReveal(false);
    }
  }, [settings.autoHide, openStackId]);

  // Compute fisheye / cosine scale for each item based on live pointer coordinates
  const scales = useMemo(() => {
    if (mouseAxis === null || settings.hoverEffect === 'none') {
      return items.map(() => 1);
    }
    const maxScale = settings.hoverEffect === 'bubble' ? settings.zoomScale : 1.16;
    const radiusPx = settings.iconSize * Math.max(1.2, settings.zoomSpan);

    return items.map((item, idx) => {
      if (item.type === 'separator') return 1;
      if (settings.hoverEffect === 'lift') {
        return hoveredId === item.id ? 1.15 : 1;
      }
      const el = itemRefs.current[idx];
      if (!el) return 1;
      const rect = el.getBoundingClientRect();
      const center = isHorizontal ? rect.left + rect.width / 2 : rect.top + rect.height / 2;
      const dist = Math.abs(mouseAxis - center);
      if (dist >= radiusPx) return 1;
      // Smooth cosine bell curve matching classic RocketDock bubble zoom
      const ratio = Math.cos((dist / radiusPx) * (Math.PI / 2));
      return 1 + (maxScale - 1) * Math.pow(ratio, 1.35);
    });
  }, [
    mouseAxis,
    items,
    settings.hoverEffect,
    settings.zoomScale,
    settings.zoomSpan,
    settings.iconSize,
    hoveredId,
    isHorizontal,
  ]);

  // Theme styling rules
  const shelfStyle = useMemo(() => {
    const alpha = Math.max(0.2, Math.min(1, settings.opacity / 100));
    switch (settings.theme) {
      case 'crystal':
        return {
          background: `linear-gradient(180deg, rgba(255,255,255,${(0.24 * alpha).toFixed(2)}) 0%, rgba(15,23,42,${(0.58 * alpha).toFixed(2)}) 100%)`,
          border: `1px solid rgba(255,255,255,${(0.32 * alpha).toFixed(2)})`,
          boxShadow: '0 14px 36px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.4)',
          backdropFilter: 'blur(18px)',
        };
      case 'aero3d':
        return {
          background: `linear-gradient(180deg, rgba(226,232,240,${(0.34 * alpha).toFixed(2)}) 0%, rgba(30,41,59,${(0.62 * alpha).toFixed(2)}) 100%)`,
          border: `1px solid rgba(255,255,255,${(0.42 * alpha).toFixed(2)})`,
          boxShadow: '0 18px 34px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.55)',
          backdropFilter: 'blur(14px)',
        };
      case 'graphite':
        return {
          background: `rgba(15,23,42,${(0.88 * alpha).toFixed(2)})`,
          border: `1px solid rgba(148,163,184,${(0.22 * alpha).toFixed(2)})`,
          boxShadow: '0 16px 36px rgba(0,0,0,0.55)',
          backdropFilter: 'blur(16px)',
        };
      case 'silk':
        return {
          background: `rgba(248,250,252,${(0.8 * alpha).toFixed(2)})`,
          border: `1px solid rgba(255,255,255,${(0.9 * alpha).toFixed(2)})`,
          boxShadow: '0 14px 34px rgba(15,23,42,0.24), inset 0 1px 0 rgba(255,255,255,0.9)',
          backdropFilter: 'blur(20px)',
        };
      case 'minimal':
        return {
          background: `rgba(15,23,42,${(0.42 * alpha).toFixed(2)})`,
          border: `1px solid rgba(255,255,255,${(0.14 * alpha).toFixed(2)})`,
          boxShadow: '0 8px 24px rgba(0,0,0,0.28)',
          backdropFilter: 'blur(12px)',
        };
      case 'retro':
        return {
          background: `linear-gradient(180deg, rgba(203,213,225,${(0.88 * alpha).toFixed(2)}) 0%, rgba(100,116,139,${(0.92 * alpha).toFixed(2)}) 49%, rgba(71,85,105,${(0.95 * alpha).toFixed(2)}) 51%, rgba(30,41,59,${(0.96 * alpha).toFixed(2)}) 100%)`,
          border: `1px solid rgba(241,245,249,${(0.48 * alpha).toFixed(2)})`,
          boxShadow: '0 14px 30px rgba(0,0,0,0.52), inset 0 1px 0 rgba(255,255,255,0.65)',
          backdropFilter: 'blur(6px)',
        };
    }
  }, [settings.theme, settings.opacity]);

  const isLightTheme = settings.theme === 'silk';
  const hiddenByAutoHide = settings.autoHide && !isAutoReveal && !openStackId && dragIndex === null;

  // Compute positioning container styles
  const wrapperStyle = useMemo<React.CSSProperties>(() => {
    const offset = `${settings.edgeOffset}px`;
    const shift = `${settings.centerOffset}vw`;
    const shiftY = `${settings.centerOffset}vh`;

    if (settings.position === 'bottom') {
      return {
        bottom: offset,
        left: '50%',
        transform: `translateX(calc(-50% + ${shift})) translateY(${hiddenByAutoHide ? '135%' : '0'})`,
      };
    }
    if (settings.position === 'top') {
      return {
        top: `${settings.edgeOffset + 42}px`,
        left: '50%',
        transform: `translateX(calc(-50% + ${shift})) translateY(${hiddenByAutoHide ? '-165%' : '0'})`,
      };
    }
    if (settings.position === 'left') {
      return {
        left: offset,
        top: '50%',
        transform: `translateY(calc(-50% + ${shiftY})) translateX(${hiddenByAutoHide ? '-135%' : '0'})`,
      };
    }
    return {
      right: offset,
      top: '50%',
      transform: `translateY(calc(-50% + ${shiftY})) translateX(${hiddenByAutoHide ? '135%' : '0'})`,
    };
  }, [settings.position, settings.edgeOffset, settings.centerOffset, hiddenByAutoHide]);

  // Auto-hide hot edge trigger zone
  const edgeTriggerClass = useMemo(() => {
    if (!settings.autoHide) return '';
    switch (settings.position) {
      case 'bottom':
        return 'fixed bottom-0 inset-x-0 h-5 z-40';
      case 'top':
        return 'fixed top-10 inset-x-0 h-5 z-40';
      case 'left':
        return 'fixed left-0 inset-y-12 w-5 z-40';
      case 'right':
        return 'fixed right-0 inset-y-12 w-5 z-40';
    }
  }, [settings.autoHide, settings.position]);

  const getBounceClass = (id: string) => {
    if (bouncingId !== id || settings.launchAnimation === 'none') return '';
    if (settings.launchAnimation === 'pulse') return 'animate-dock-pulse';
    return `animate-dock-bounce-${settings.position}`;
  };

  // Drag handlers
  const handleDragStart = (e: React.DragEvent, index: number) => {
    if (settings.lockIcons) {
      e.preventDefault();
      return;
    }
    setDragIndex(index);
    setOpenStackId(null);
    dragStartCoords.current = { x: e.clientX, y: e.clientY };
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', String(index));
  };

  const handleDragOver = (e: React.DragEvent, index: number) => {
    e.preventDefault();
    if (dragIndex !== null && dragIndex !== index) {
      setDragOverIndex(index);
    }
  };

  const handleDrop = (e: React.DragEvent, index: number) => {
    e.preventDefault();
    if (dragIndex !== null && dragIndex !== index) {
      onReorderItems(dragIndex, index);
    }
    setDragIndex(null);
    setDragOverIndex(null);
  };

  const handleDragEnd = (e: React.DragEvent, item: DockItem) => {
    if (dragIndex !== null && !settings.lockIcons && dockRef.current) {
      const rect = dockRef.current.getBoundingClientRect();
      const pad = 76;
      const outside =
        e.clientX < rect.left - pad ||
        e.clientX > rect.right + pad ||
        e.clientY < rect.top - pad ||
        e.clientY > rect.bottom + pad;

      // Protect Settings & Trash from accidental drag-off deletion
      if (outside && item.type !== 'trash' && item.appId !== 'settings') {
        onRemoveItemByDrag(item, e.clientX, e.clientY);
      }
    }
    setDragIndex(null);
    setDragOverIndex(null);
  };

  const tooltipPositionClass = useMemo(() => {
    switch (settings.position) {
      case 'bottom':
        return 'bottom-full mb-3 left-1/2 -translate-x-1/2';
      case 'top':
        return 'top-full mt-3 left-1/2 -translate-x-1/2';
      case 'left':
        return 'left-full ml-3 top-1/2 -translate-y-1/2';
      case 'right':
        return 'right-full mr-3 top-1/2 -translate-y-1/2';
    }
  }, [settings.position]);

  const stackPopoverPositionClass = useMemo(() => {
    switch (settings.position) {
      case 'bottom':
        return 'bottom-full mb-4 left-1/2 -translate-x-1/2';
      case 'top':
        return 'top-full mt-4 left-1/2 -translate-x-1/2';
      case 'left':
        return 'left-full ml-4 top-1/2 -translate-y-1/2';
      case 'right':
        return 'right-full mr-4 top-1/2 -translate-y-1/2';
    }
  }, [settings.position]);

  const activeIndicatorClass = useMemo(() => {
    const colorCls = isLightTheme ? 'bg-slate-800' : 'bg-sky-300 shadow-[0_0_8px_rgba(125,211,252,0.9)]';
    switch (settings.position) {
      case 'bottom':
        return `absolute -bottom-1.5 left-1/2 -translate-x-1/2 w-1.5 h-1.5 rounded-full ${colorCls}`;
      case 'top':
        return `absolute -top-1.5 left-1/2 -translate-x-1/2 w-1.5 h-1.5 rounded-full ${colorCls}`;
      case 'left':
        return `absolute -left-1.5 top-1/2 -translate-y-1/2 w-1.5 h-1.5 rounded-full ${colorCls}`;
      case 'right':
        return `absolute -right-1.5 top-1/2 -translate-y-1/2 w-1.5 h-1.5 rounded-full ${colorCls}`;
    }
  }, [settings.position, isLightTheme]);

  return (
    <>
      {/* Auto-hide edge trigger strip */}
      {settings.autoHide && (
        <div
          className={edgeTriggerClass}
          onMouseEnter={() => setIsAutoReveal(true)}
          aria-hidden="true"
        />
      )}

      {/* Dock Container */}
      <nav
        ref={dockRef}
        aria-label="Док-панель приложений AeroDock"
        style={wrapperStyle}
        onMouseEnter={() => {
          if (settings.autoHide) setIsAutoReveal(true);
        }}
        onMouseMove={handleDockMouseMove}
        onMouseLeave={handleDockMouseLeave}
        onContextMenu={(e) => {
          if (e.target === e.currentTarget) {
            onDockContextMenu(e);
          }
        }}
        className="fixed z-50 transition-transform duration-300 ease-[cubic-bezier(0.16,1,0.3,1)]"
      >
        <div className="relative flex items-center justify-center">
          {/* Background Shelf Surface */}
          {settings.theme === 'aero3d' && isHorizontal ? (
            <div
              aria-hidden="true"
              onContextMenu={onDockContextMenu}
              style={shelfStyle}
              className={`pointer-events-auto absolute inset-x-[-14px] h-[54%] rounded-2xl ${
                settings.position === 'bottom'
                  ? 'bottom-[-2px] aero-3d-shelf'
                  : 'top-[-2px] aero-3d-shelf-top'
              }`}
            />
          ) : (
            <div
              aria-hidden="true"
              onContextMenu={onDockContextMenu}
              style={shelfStyle}
              className="pointer-events-auto absolute inset-0 rounded-[22px]"
            />
          )}

          {/* Icons Strip */}
          <div
            onContextMenu={(e) => {
              if (e.target === e.currentTarget) onDockContextMenu(e);
            }}
            className={`relative z-10 flex ${
              isHorizontal
                ? settings.position === 'bottom'
                  ? 'flex-row items-end px-3.5 pt-2.5 pb-2.5 gap-1.5'
                  : 'flex-row items-start px-3.5 pt-2.5 pb-2.5 gap-1.5'
                : settings.position === 'left'
                  ? 'flex-col items-start py-3.5 px-2.5 gap-1.5'
                  : 'flex-col items-end py-3.5 px-2.5 gap-1.5'
            }`}
          >
            {items.map((item, idx) => {
              const scale = scales[idx] ?? 1;
              const visualSize = Math.round(settings.iconSize * scale);
              const isRunning = item.appId ? openAppIds.includes(item.appId) : false;
              const isDragTarget = dragOverIndex === idx;

              if (item.type === 'separator') {
                return (
                  <div
                    key={item.id}
                    ref={(el) => {
                      itemRefs.current[idx] = el;
                    }}
                    draggable={!settings.lockIcons}
                    onDragStart={(e) => handleDragStart(e, idx)}
                    onDragOver={(e) => handleDragOver(e, idx)}
                    onDrop={(e) => handleDrop(e, idx)}
                    onDragEnd={(e) => handleDragEnd(e, item)}
                    onContextMenu={(e) => {
                      e.preventDefault();
                      e.stopPropagation();
                      onItemContextMenu(e, item);
                    }}
                    title="Разделитель (ПКМ для удаления)"
                    className={`shrink-0 flex items-center justify-center cursor-grab active:cursor-grabbing ${
                      isHorizontal ? 'px-1.5 self-center' : 'py-1.5 self-center'
                    } ${isDragTarget ? 'opacity-40' : ''}`}
                  >
                    <div
                      className={`rounded-full ${
                        isLightTheme ? 'bg-slate-400/70' : 'bg-white/30'
                      }`}
                      style={
                        isHorizontal
                          ? { width: '1.5px', height: `${Math.round(settings.iconSize * 0.64)}px` }
                          : { height: '1.5px', width: `${Math.round(settings.iconSize * 0.64)}px` }
                      }
                    />
                  </div>
                );
              }

              const liftPx =
                settings.hoverEffect === 'none'
                  ? 0
                  : Math.round((scale - 1) * (settings.iconSize * 0.32));

              const liftTransform =
                settings.position === 'bottom'
                  ? `translateY(-${liftPx}px)`
                  : settings.position === 'top'
                    ? `translateY(${liftPx}px)`
                    : settings.position === 'left'
                      ? `translateX(${liftPx}px)`
                      : `translateX(-${liftPx}px)`;

              const isExternalLink = item.type === 'link' && item.url;
              const isStackOpen = item.type === 'stack' && openStackId === item.id;

              const iconBody = (
                <div
                  className={`relative flex items-center justify-center transition-[width,height] duration-100 ease-out ${getBounceClass(
                    item.id
                  )}`}
                  style={{
                    width: `${visualSize}px`,
                    height: `${visualSize}px`,
                    transform: liftTransform,
                  }}
                >
                  <AppIconArt
                    iconKey={item.iconKey}
                    color={item.color}
                    customImage={item.customImage}
                    trashCount={item.type === 'trash' ? trashCount : 0}
                    title={item.title}
                  />

                  {/* Trash item counter */}
                  {item.type === 'trash' && trashCount > 0 && (
                    <span className="pointer-events-none absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 rounded-full bg-rose-600 text-white text-[10px] font-mono font-semibold flex items-center justify-center shadow ring-1 ring-white/40">
                      {trashCount}
                    </span>
                  )}

                  {/* Classic RocketDock reflection for bottom dock */}
                  {settings.showReflections && settings.position === 'bottom' && (
                    <div
                      aria-hidden="true"
                      className="pointer-events-none absolute top-[102%] inset-x-0 h-[42%] opacity-28 overflow-hidden"
                      style={{
                        transform: 'scaleY(-1)',
                        maskImage: 'linear-gradient(to bottom, rgba(0,0,0,0.65), transparent 88%)',
                        WebkitMaskImage:
                          'linear-gradient(to bottom, rgba(0,0,0,0.65), transparent 88%)',
                      }}
                    >
                      <div className="w-full" style={{ height: `${visualSize}px` }}>
                        <AppIconArt
                          iconKey={item.iconKey}
                          color={item.color}
                          customImage={item.customImage}
                          trashCount={item.type === 'trash' ? trashCount : 0}
                        />
                      </div>
                    </div>
                  )}
                </div>
              );

              return (
                <div
                  key={item.id}
                  ref={(el) => {
                    itemRefs.current[idx] = el;
                  }}
                  draggable={!settings.lockIcons}
                  onDragStart={(e) => handleDragStart(e, idx)}
                  onDragOver={(e) => handleDragOver(e, idx)}
                  onDrop={(e) => handleDrop(e, idx)}
                  onDragEnd={(e) => handleDragEnd(e, item)}
                  onMouseEnter={() => setHoveredId(item.id)}
                  onMouseLeave={() => setHoveredId((prev) => (prev === item.id ? null : prev))}
                  onContextMenu={(e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    setOpenStackId(null);
                    onItemContextMenu(e, item);
                  }}
                  className={`relative shrink-0 flex items-center justify-center select-none ${
                    isDragTarget
                      ? 'ring-2 ring-sky-400/70 rounded-xl'
                      : ''
                  } ${dragIndex === idx ? 'opacity-40' : ''}`}
                >
                  {/* Hover Tooltip Label */}
                  {settings.showLabels && hoveredId === item.id && !isStackOpen && (
                    <div
                      className={`pointer-events-none absolute z-50 ${tooltipPositionClass} px-2.5 py-1 rounded-lg bg-slate-950/90 text-slate-50 text-xs font-medium whitespace-nowrap shadow-xl border border-white/15 backdrop-blur-md`}
                    >
                      {item.title}
                    </div>
                  )}

                  {/* Stack Popover Menu */}
                  {isStackOpen && (
                    <div
                      className={`absolute z-50 ${stackPopoverPositionClass} w-64 rounded-2xl bg-slate-900/94 text-slate-100 border border-white/15 shadow-2xl backdrop-blur-xl p-2.5`}
                    >
                      <div className="flex items-center justify-between px-2 pb-2 mb-1.5 border-b border-white/10">
                        <span className="text-xs font-semibold text-slate-200 truncate">
                          {item.title}
                        </span>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            setOpenStackId(null);
                            onEditItem(item);
                          }}
                          className="p-1 rounded-md text-slate-400 hover:text-white hover:bg-white/10 transition-colors"
                          title="Настроить стек"
                        >
                          <Pencil className="w-3.5 h-3.5" />
                        </button>
                      </div>

                      {item.stackItems && item.stackItems.length > 0 ? (
                        <div className="flex flex-col gap-1 max-h-64 overflow-y-auto dock-scroll">
                          {item.stackItems.map((entry) => (
                            <a
                              key={entry.id}
                              href={entry.url}
                              target="_blank"
                              rel="noopener noreferrer"
                              onClick={() => setOpenStackId(null)}
                              className="flex items-center gap-2.5 px-2 py-1.5 rounded-xl hover:bg-white/10 transition-colors group"
                            >
                              <div className="w-7 h-7 shrink-0">
                                <AppIconArt iconKey={entry.iconKey} color={entry.color} title={entry.title} />
                              </div>
                              <div className="min-w-0 flex-1">
                                <div className="text-xs font-medium text-slate-100 truncate">
                                  {entry.title}
                                </div>
                                <div className="text-[11px] text-slate-400 truncate">
                                  {entry.url.replace(/^https?:\/\//, '')}
                                </div>
                              </div>
                              <ExternalLink className="w-3.5 h-3.5 text-slate-500 group-hover:text-sky-400 shrink-0" />
                            </a>
                          ))}
                        </div>
                      ) : (
                        <div className="py-5 text-center text-xs text-slate-400">
                          В стеке пока нет ссылок
                        </div>
                      )}

                      <button
                        type="button"
                        onClick={() => {
                          setOpenStackId(null);
                          onEditItem(item);
                        }}
                        className="mt-2 w-full flex items-center justify-center gap-1.5 py-1.5 px-2.5 rounded-lg bg-white/8 hover:bg-white/14 text-xs font-medium text-slate-200 transition-colors"
                      >
                        <Plus className="w-3.5 h-3.5" />
                        Изменить состав стека
                      </button>
                    </div>
                  )}

                  {/* Clickable Launcher Surface */}
                  {isExternalLink ? (
                    <a
                      href={item.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      onClick={() => onActivateItem(item)}
                      aria-label={item.title}
                      className="block rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400"
                    >
                      {iconBody}
                    </a>
                  ) : (
                    <button
                      type="button"
                      onClick={() => {
                        if (item.type === 'stack') {
                          setOpenStackId((prev) => (prev === item.id ? null : item.id));
                        } else {
                          setOpenStackId(null);
                        }
                        onActivateItem(item);
                      }}
                      aria-label={item.title}
                      className="block rounded-xl focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400 cursor-pointer"
                    >
                      {iconBody}
                    </button>
                  )}

                  {/* Running App Indicator */}
                  {isRunning && <span aria-hidden="true" className={activeIndicatorClass} />}
                </div>
              );
            })}
          </div>
        </div>
      </nav>
    </>
  );
};
