export type DockPosition = 'bottom' | 'top' | 'left' | 'right';

export type DockThemeId =
  | 'crystal'
  | 'aero3d'
  | 'graphite'
  | 'silk'
  | 'minimal'
  | 'retro';

export type HoverEffect = 'bubble' | 'lift' | 'none';

export type LaunchAnimation = 'bounce' | 'pulse' | 'none';

export type DockItemType = 'app' | 'link' | 'stack' | 'separator' | 'trash' | 'winapp';

export type BuiltInAppId =
  | 'launcher'
  | 'notes'
  | 'calculator'
  | 'clock'
  | 'settings'
  | 'trash'
  | 'portable';

export type IconGlyphKey =
  | 'compass'
  | 'notes'
  | 'calculator'
  | 'clock'
  | 'settings'
  | 'trash'
  | 'folder-blue'
  | 'folder-amber'
  | 'folder-emerald'
  | 'code'
  | 'terminal'
  | 'globe'
  | 'music'
  | 'video'
  | 'mail'
  | 'chat'
  | 'palette'
  | 'camera'
  | 'cloud'
  | 'book'
  | 'gamepad'
  | 'rocket'
  | 'briefcase'
  | 'star'
  | 'windows';

export interface StackEntry {
  id: string;
  title: string;
  url: string;
  iconKey: IconGlyphKey;
  color: string;
}

export interface DockItem {
  id: string;
  type: DockItemType;
  title: string;
  url?: string;
  winPath?: string;
  winArgs?: string;
  appId?: BuiltInAppId;
  iconKey: IconGlyphKey;
  color: string;
  customImage?: string;
  stackItems?: StackEntry[];
}

export interface DockSettings {
  position: DockPosition;
  theme: DockThemeId;
  iconSize: number; // 38..76
  zoomScale: number; // 1.0..2.0
  zoomSpan: number; // 1..4 neighbor radius
  hoverEffect: HoverEffect;
  launchAnimation: LaunchAnimation;
  opacity: number; // 25..100
  edgeOffset: number; // 0..48 px
  centerOffset: number; // -35..35 %
  autoHide: boolean;
  lockIcons: boolean;
  showLabels: boolean;
  showReflections: boolean;
  showDesktopClock: boolean;
  wallpaperId: string;
  customWallpaper?: string;
}

export interface DesktopWindowState {
  id: BuiltInAppId;
  title: string;
  x: number;
  y: number;
  width: number;
  height: number;
  isOpen: boolean;
  isMinimized: boolean;
  zIndex: number;
}

export interface NoteEntry {
  id: string;
  title: string;
  content: string;
  updatedAt: number;
}

export interface WallpaperOption {
  id: string;
  name: string;
  subtitle: string;
  url: string;
  fallbackGradient: string;
}

export interface PoofParticle {
  id: string;
  x: number;
  y: number;
}
