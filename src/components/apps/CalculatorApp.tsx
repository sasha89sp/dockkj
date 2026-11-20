import React, { useState } from 'react';

type Operator = '+' | '-' | '×' | '÷' | null;

export const CalculatorApp: React.FC = () => {
  const [display, setDisplay] = useState('0');
  const [stored, setStored] = useState<number | null>(null);
  const [operator, setOperator] = useState<Operator>(null);
  const [waitingForNext, setWaitingForNext] = useState(false);

  const inputDigit = (digit: string) => {
    if (waitingForNext) {
      setDisplay(digit);
      setWaitingForNext(false);
      return;
    }
    setDisplay((prev) => (prev === '0' ? digit : prev.length < 14 ? prev + digit : prev));
  };

  const inputDot = () => {
    if (waitingForNext) {
      setDisplay('0.');
      setWaitingForNext(false);
      return;
    }
    if (!display.includes('.')) {
      setDisplay((prev) => prev + '.');
    }
  };

  const clearAll = () => {
    setDisplay('0');
    setStored(null);
    setOperator(null);
    setWaitingForNext(false);
  };

  const toggleSign = () => {
    const val = parseFloat(display);
    if (!Number.isNaN(val) && val !== 0) {
      setDisplay(String(-val));
    }
  };

  const applyPercent = () => {
    const val = parseFloat(display);
    if (!Number.isNaN(val)) {
      setDisplay(String(Number((val / 100).toPrecision(10))));
    }
  };

  const compute = (a: number, b: number, op: Operator): number => {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b === 0 ? 0 : a / b;
      default:
        return b;
    }
  };

  const chooseOperator = (nextOp: Operator) => {
    const currentVal = parseFloat(display);
    if (stored === null) {
      setStored(currentVal);
    } else if (operator && !waitingForNext) {
      const result = compute(stored, currentVal, operator);
      const formatted = String(Number(result.toPrecision(12)));
      setDisplay(formatted);
      setStored(result);
    }
    setOperator(nextOp);
    setWaitingForNext(true);
  };

  const evaluate = () => {
    if (operator === null || stored === null) return;
    const currentVal = parseFloat(display);
    const result = compute(stored, currentVal, operator);
    setDisplay(String(Number(result.toPrecision(12))));
    setStored(null);
    setOperator(null);
    setWaitingForNext(true);
  };

  const btnBase =
    'h-12 rounded-xl font-mono text-base font-medium transition-colors flex items-center justify-center cursor-pointer select-none';

  return (
    <div className="h-full flex flex-col p-4 bg-slate-950/70 text-white">
      <div className="rounded-xl bg-slate-900/80 border border-white/10 px-4 py-4 mb-4 text-right">
        <div className="text-[11px] font-mono text-slate-400 h-4">
          {stored !== null && operator ? `${stored} ${operator}` : ''}
        </div>
        <div className="font-mono text-3xl font-semibold tracking-tight truncate mt-1">
          {display}
        </div>
      </div>

      <div className="grid grid-cols-4 gap-2 flex-1">
        <button type="button" onClick={clearAll} className={`${btnBase} bg-slate-800 hover:bg-slate-700 text-slate-200`}>
          C
        </button>
        <button type="button" onClick={toggleSign} className={`${btnBase} bg-slate-800 hover:bg-slate-700 text-slate-200`}>
          ±
        </button>
        <button type="button" onClick={applyPercent} className={`${btnBase} bg-slate-800 hover:bg-slate-700 text-slate-200`}>
          %
        </button>
        <button
          type="button"
          onClick={() => chooseOperator('÷')}
          className={`${btnBase} ${
            operator === '÷' && waitingForNext
              ? 'bg-sky-400 text-slate-950'
              : 'bg-sky-500/25 hover:bg-sky-500/35 text-sky-200'
          }`}
        >
          ÷
        </button>

        {['7', '8', '9'].map((d) => (
          <button key={d} type="button" onClick={() => inputDigit(d)} className={`${btnBase} bg-slate-900 hover:bg-slate-800 border border-white/5`}>
            {d}
          </button>
        ))}
        <button
          type="button"
          onClick={() => chooseOperator('×')}
          className={`${btnBase} ${
            operator === '×' && waitingForNext
              ? 'bg-sky-400 text-slate-950'
              : 'bg-sky-500/25 hover:bg-sky-500/35 text-sky-200'
          }`}
        >
          ×
        </button>

        {['4', '5', '6'].map((d) => (
          <button key={d} type="button" onClick={() => inputDigit(d)} className={`${btnBase} bg-slate-900 hover:bg-slate-800 border border-white/5`}>
            {d}
          </button>
        ))}
        <button
          type="button"
          onClick={() => chooseOperator('-')}
          className={`${btnBase} ${
            operator === '-' && waitingForNext
              ? 'bg-sky-400 text-slate-950'
              : 'bg-sky-500/25 hover:bg-sky-500/35 text-sky-200'
          }`}
        >
          −
        </button>

        {['1', '2', '3'].map((d) => (
          <button key={d} type="button" onClick={() => inputDigit(d)} className={`${btnBase} bg-slate-900 hover:bg-slate-800 border border-white/5`}>
            {d}
          </button>
        ))}
        <button
          type="button"
          onClick={() => chooseOperator('+')}
          className={`${btnBase} ${
            operator === '+' && waitingForNext
              ? 'bg-sky-400 text-slate-950'
              : 'bg-sky-500/25 hover:bg-sky-500/35 text-sky-200'
          }`}
        >
          +
        </button>

        <button
          type="button"
          onClick={() => inputDigit('0')}
          className={`${btnBase} col-span-2 bg-slate-900 hover:bg-slate-800 border border-white/5`}
        >
          0
        </button>
        <button type="button" onClick={inputDot} className={`${btnBase} bg-slate-900 hover:bg-slate-800 border border-white/5`}>
          .
        </button>
        <button type="button" onClick={evaluate} className={`${btnBase} bg-sky-500 hover:bg-sky-400 text-slate-950 font-bold`}>
          =
        </button>
      </div>
    </div>
  );
};
