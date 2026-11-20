import React, { useEffect, useState } from 'react';
import { Pause, Play, RotateCcw } from 'lucide-react';

type ClockMode = 'clock' | 'stopwatch' | 'timer';

export const ClockApp: React.FC = () => {
  const [mode, setMode] = useState<ClockMode>('clock');
  const [now, setNow] = useState(() => new Date());

  // Stopwatch state (milliseconds)
  const [swMs, setSwMs] = useState(0);
  const [swRunning, setSwRunning] = useState(false);

  // Timer state (seconds)
  const [timerInitialSec, setTimerInitialSec] = useState(25 * 60);
  const [timerSec, setTimerSec] = useState(25 * 60);
  const [timerRunning, setTimerRunning] = useState(false);

  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (!swRunning) return;
    const id = window.setInterval(() => setSwMs((prev) => prev + 50), 50);
    return () => window.clearInterval(id);
  }, [swRunning]);

  useEffect(() => {
    if (!timerRunning) return;
    const id = window.setInterval(() => {
      setTimerSec((prev) => {
        if (prev <= 1) {
          setTimerRunning(false);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => window.clearInterval(id);
  }, [timerRunning]);

  const formatStopwatch = (ms: number) => {
    const mins = Math.floor(ms / 60000);
    const secs = Math.floor((ms % 60000) / 1000);
    const centis = Math.floor((ms % 1000) / 10);
    return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}.${String(centis).padStart(2, '0')}`;
  };

  const formatTimer = (sec: number) => {
    const mins = Math.floor(sec / 60);
    const rem = sec % 60;
    return `${String(mins).padStart(2, '0')}:${String(rem).padStart(2, '0')}`;
  };

  const applyPreset = (minutes: number) => {
    setTimerRunning(false);
    setTimerInitialSec(minutes * 60);
    setTimerSec(minutes * 60);
  };

  return (
    <div className="h-full flex flex-col text-slate-100">
      <div className="px-4 py-3 border-b border-white/10 flex items-center gap-2 bg-slate-900/50">
        {(
          [
            ['clock', 'Часы'],
            ['stopwatch', 'Секундомер'],
            ['timer', 'Таймер'],
          ] as [ClockMode, string][]
        ).map(([id, label]) => (
          <button
            key={id}
            type="button"
            onClick={() => setMode(id)}
            className={`px-3.5 py-1.5 rounded-lg text-xs font-medium transition-colors cursor-pointer ${
              mode === id
                ? 'bg-sky-500/20 text-sky-200 border border-sky-400/30'
                : 'text-slate-400 hover:text-white hover:bg-white/5 border border-transparent'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      <div className="flex-1 flex flex-col items-center justify-center p-6 text-center">
        {mode === 'clock' && (
          <>
            <div className="font-mono text-5xl font-semibold tracking-tight text-white">
              {now.toLocaleTimeString('ru-RU', {
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit',
              })}
            </div>
            <div className="mt-3 text-sm text-slate-300 capitalize">
              {now.toLocaleDateString('ru-RU', {
                weekday: 'long',
                day: 'numeric',
                month: 'long',
                year: 'numeric',
              })}
            </div>
          </>
        )}

        {mode === 'stopwatch' && (
          <div className="space-y-6">
            <div className="font-mono text-5xl font-semibold tracking-tight text-white">
              {formatStopwatch(swMs)}
            </div>
            <div className="flex items-center justify-center gap-3">
              <button
                type="button"
                onClick={() => setSwRunning((r) => !r)}
                className="flex items-center gap-2 px-5 py-2.5 rounded-xl bg-sky-500 hover:bg-sky-400 text-slate-950 text-xs font-semibold transition-colors cursor-pointer"
              >
                {swRunning ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
                {swRunning ? 'Пауза' : 'Старт'}
              </button>
              <button
                type="button"
                onClick={() => {
                  setSwRunning(false);
                  setSwMs(0);
                }}
                className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-white/10 hover:bg-white/15 text-white text-xs font-medium transition-colors cursor-pointer"
              >
                <RotateCcw className="w-4 h-4" />
                Сброс
              </button>
            </div>
          </div>
        )}

        {mode === 'timer' && (
          <div className="space-y-5 w-full max-w-xs">
            <div className="font-mono text-5xl font-semibold tracking-tight text-white">
              {formatTimer(timerSec)}
            </div>

            <div className="flex items-center justify-center gap-2">
              {[5, 15, 25, 45].map((m) => (
                <button
                  key={m}
                  type="button"
                  onClick={() => applyPreset(m)}
                  className={`px-3 py-1 rounded-lg text-xs font-mono border transition-colors cursor-pointer ${
                    timerInitialSec === m * 60
                      ? 'bg-sky-500/20 border-sky-400/40 text-sky-200'
                      : 'bg-slate-900/60 border-white/10 text-slate-300 hover:border-white/25'
                  }`}
                >
                  {m}м
                </button>
              ))}
            </div>

            <div className="flex items-center justify-center gap-3">
              <button
                type="button"
                onClick={() => setTimerRunning((r) => !r)}
                className="flex items-center gap-2 px-5 py-2.5 rounded-xl bg-sky-500 hover:bg-sky-400 text-slate-950 text-xs font-semibold transition-colors cursor-pointer"
              >
                {timerRunning ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
                {timerRunning ? 'Пауза' : 'Запустить'}
              </button>
              <button
                type="button"
                onClick={() => {
                  setTimerRunning(false);
                  setTimerSec(timerInitialSec);
                }}
                className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-white/10 hover:bg-white/15 text-white text-xs font-medium transition-colors cursor-pointer"
              >
                <RotateCcw className="w-4 h-4" />
                Сброс
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
