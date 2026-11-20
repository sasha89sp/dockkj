import React, { useEffect, useState } from 'react';
import {
  BookOpen,
  Briefcase,
  Calculator,
  Camera,
  Cloud,
  Code2,
  Compass,
  FileText,
  Gamepad2,
  Globe,
  Mail,
  MessageSquare,
  Monitor,
  Music,
  Palette,
  Play,
  Rocket,
  Settings,
  Star,
  Terminal,
} from 'lucide-react';
import { IconGlyphKey } from '../types/dock';

interface AppIconArtProps {
  iconKey: IconGlyphKey;
  color: string;
  customImage?: string;
  trashCount?: number;
  size?: number;
  title?: string;
}

function LiveClockFace() {
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const seconds = now.getSeconds();
  const minutes = now.getMinutes() + seconds / 60;
  const hours = (now.getHours() % 12) + minutes / 60;

  return (
    <svg viewBox="0 0 64 64" className="w-full h-full drop-shadow-md">
      <defs>
        <linearGradient id="clockBezel" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#334155" />
          <stop offset="100%" stopColor="#0f172a" />
        </linearGradient>
        <radialGradient id="clockDial" cx="50%" cy="35%" r="65%">
          <stop offset="0%" stopColor="#ffffff" />
          <stop offset="100%" stopColor="#e2e8f0" />
        </radialGradient>
      </defs>
      <rect x="4" y="4" width="56" height="56" rx="15" fill="url(#clockBezel)" stroke="rgba(255,255,255,0.25)" strokeWidth="1.5" />
      <circle cx="32" cy="32" r="22" fill="url(#clockDial)" />
      {[0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330].map((deg) => (
        <line
          key={deg}
          x1="32"
          y1={deg % 90 === 0 ? '13' : '14.5'}
          x2="32"
          y2="17"
          stroke={deg % 90 === 0 ? '#0f172a' : '#64748b'}
          strokeWidth={deg % 90 === 0 ? '2' : '1.2'}
          strokeLinecap="round"
          transform={`rotate(${deg} 32 32)`}
        />
      ))}
      <line
        x1="32"
        y1="32"
        x2="32"
        y2="21"
        stroke="#0f172a"
        strokeWidth="2.8"
        strokeLinecap="round"
        transform={`rotate(${hours * 30} 32 32)`}
      />
      <line
        x1="32"
        y1="32"
        x2="32"
        y2="16"
        stroke="#1e293b"
        strokeWidth="2"
        strokeLinecap="round"
        transform={`rotate(${minutes * 6} 32 32)`}
      />
      <line
        x1="32"
        y1="36"
        x2="32"
        y2="15"
        stroke="#e11d48"
        strokeWidth="1.2"
        strokeLinecap="round"
        transform={`rotate(${seconds * 6} 32 32)`}
      />
      <circle cx="32" cy="32" r="2.2" fill="#e11d48" />
    </svg>
  );
}

function FolderIconArt({ variant }: { variant: 'blue' | 'amber' | 'emerald' }) {
  const palettes = {
    blue: { back: '#1d4ed8', frontTop: '#60a5fa', frontBot: '#2563eb', tab: '#3b82f6' },
    amber: { back: '#b45309', frontTop: '#fbbf24', frontBot: '#d97706', tab: '#f59e0b' },
    emerald: { back: '#047857', frontTop: '#34d399', frontBot: '#059669', tab: '#10b981' },
  };
  const p = palettes[variant];
  const gradId = `folder-grad-${variant}`;

  return (
    <svg viewBox="0 0 64 64" className="w-full h-full drop-shadow-md">
      <defs>
        <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={p.frontTop} />
          <stop offset="100%" stopColor={p.frontBot} />
        </linearGradient>
      </defs>
      <path
        d="M8 17C8 13.7 10.7 11 14 11H25.5C27.4 11 29.2 11.9 30.3 13.4L32.5 16.5H50C53.3 16.5 56 19.2 56 22.5V48C56 51.3 53.3 54 50 54H14C10.7 54 8 51.3 8 48V17Z"
        fill={p.back}
      />
      <rect x="12" y="19" width="40" height="8" rx="3" fill="rgba(255,255,255,0.82)" />
      <rect
        x="7"
        y="22"
        width="50"
        height="33"
        rx="7"
        fill={`url(#${gradId})`}
        stroke="rgba(255,255,255,0.35)"
        strokeWidth="1.2"
      />
      <path d="M13 27H51" stroke="rgba(255,255,255,0.3)" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function TrashBinArt({ isFull }: { isFull: boolean }) {
  return (
    <svg viewBox="0 0 64 64" className="w-full h-full drop-shadow-md">
      <defs>
        <linearGradient id="trashBody" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor="#e2e8f0" stopOpacity="0.92" />
          <stop offset="50%" stopColor="#94a3b8" stopOpacity="0.82" />
          <stop offset="100%" stopColor="#475569" stopOpacity="0.92" />
        </linearGradient>
        <linearGradient id="trashRim" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#f8fafc" />
          <stop offset="100%" stopColor="#94a3b8" />
        </linearGradient>
      </defs>
      {isFull && (
        <g>
          <path d="M20 19L27 11L35 16L29 24Z" fill="#f8fafc" stroke="#cbd5e1" strokeWidth="1" />
          <path d="M31 18L40 12L46 19L37 24Z" fill="#e2e8f0" stroke="#94a3b8" strokeWidth="1" />
          <path d="M23 21L33 15L41 21L30 25Z" fill="#ffffff" stroke="#cbd5e1" strokeWidth="1" />
        </g>
      )}
      <path
        d="M15 20L19 52C19.4 55 22 57 25 57H39C42 57 44.6 55 45 52L49 20H15Z"
        fill="url(#trashBody)"
        stroke="rgba(255,255,255,0.55)"
        strokeWidth="1.4"
      />
      <ellipse cx="32" cy="20" rx="17" ry="4.5" fill="url(#trashRim)" stroke="rgba(255,255,255,0.75)" strokeWidth="1.2" />
      <ellipse cx="32" cy="20" rx="13.5" ry="2.6" fill="#334155" fillOpacity="0.45" />
      <line x1="25" y1="27" x2="26.5" y2="50" stroke="rgba(255,255,255,0.4)" strokeWidth="2" strokeLinecap="round" />
      <line x1="32" y1="27" x2="32" y2="51" stroke="rgba(255,255,255,0.4)" strokeWidth="2" strokeLinecap="round" />
      <line x1="39" y1="27" x2="37.5" y2="50" stroke="rgba(255,255,255,0.4)" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

export const AppIconArt: React.FC<AppIconArtProps> = ({
  iconKey,
  color,
  customImage,
  trashCount = 0,
  title,
}) => {
  const [imgError, setImgError] = useState(false);

  useEffect(() => {
    setImgError(false);
  }, [customImage]);

  if (customImage && !imgError) {
    return (
      <div className="w-full h-full rounded-[22%] overflow-hidden shadow-lg ring-1 ring-white/25 bg-slate-900/50">
        <img
          src={customImage}
          alt={title || 'Значок приложения'}
          referrerPolicy="no-referrer"
          onError={() => setImgError(true)}
          className="w-full h-full object-cover"
          draggable={false}
        />
      </div>
    );
  }

  if (iconKey === 'clock') {
    return <LiveClockFace />;
  }

  if (iconKey === 'trash') {
    return <TrashBinArt isFull={trashCount > 0} />;
  }

  if (iconKey === 'folder-blue') return <FolderIconArt variant="blue" />;
  if (iconKey === 'folder-amber') return <FolderIconArt variant="amber" />;
  if (iconKey === 'folder-emerald') return <FolderIconArt variant="emerald" />;

  const renderGlyph = () => {
    const cls = 'w-[54%] h-[54%] text-white drop-shadow-sm stroke-[2]';
    switch (iconKey) {
      case 'compass':
        return <Compass className={cls} />;
      case 'notes':
        return <FileText className={cls} />;
      case 'calculator':
        return <Calculator className={cls} />;
      case 'settings':
        return <Settings className={cls} />;
      case 'code':
        return <Code2 className={cls} />;
      case 'terminal':
        return <Terminal className={cls} />;
      case 'globe':
        return <Globe className={cls} />;
      case 'music':
        return <Music className={cls} />;
      case 'video':
        return <Play className={`${cls} fill-white/90`} />;
      case 'mail':
        return <Mail className={cls} />;
      case 'chat':
        return <MessageSquare className={cls} />;
      case 'palette':
        return <Palette className={cls} />;
      case 'camera':
        return <Camera className={cls} />;
      case 'cloud':
        return <Cloud className={cls} />;
      case 'book':
        return <BookOpen className={cls} />;
      case 'gamepad':
        return <Gamepad2 className={cls} />;
      case 'briefcase':
        return <Briefcase className={cls} />;
      case 'star':
        return <Star className={cls} />;
      case 'windows':
        return <Monitor className={cls} />;
      case 'rocket':
      default:
        return <Rocket className={cls} />;
    }
  };

  return (
    <div
      className="relative w-full h-full rounded-[24%] flex items-center justify-center overflow-hidden shadow-[0_6px_16px_rgba(0,0,0,0.42)] ring-1 ring-white/30"
      style={{
        background: `linear-gradient(155deg, ${color} 0%, color-mix(in srgb, ${color} 68%, #020617) 100%)`,
      }}
    >
      {/* Subtle RocketDock glass specular highlight */}
      <div
        className="pointer-events-none absolute inset-x-0 top-0 h-[48%]"
        style={{
          background:
            'linear-gradient(180deg, rgba(255,255,255,0.38) 0%, rgba(255,255,255,0.06) 100%)',
          borderBottomLeftRadius: '50% 24%',
          borderBottomRightRadius: '50% 24%',
        }}
      />
      <div className="relative z-10 w-full h-full flex items-center justify-center">
        {renderGlyph()}
      </div>
    </div>
  );
};
