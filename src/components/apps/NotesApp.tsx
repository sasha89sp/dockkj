import React, { useEffect, useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { NoteEntry } from '../../types/dock';

interface NotesAppProps {
  notes: NoteEntry[];
  onChangeNotes: React.Dispatch<React.SetStateAction<NoteEntry[]>>;
}

export const NotesApp: React.FC<NotesAppProps> = ({ notes, onChangeNotes }) => {
  const [selectedId, setSelectedId] = useState<string>(() => notes[0]?.id ?? '');

  useEffect(() => {
    if (!notes.some((n) => n.id === selectedId)) {
      setSelectedId(notes[0]?.id ?? '');
    }
  }, [notes, selectedId]);

  const activeNote = notes.find((n) => n.id === selectedId) ?? notes[0] ?? null;

  const createNote = () => {
    const newNote: NoteEntry = {
      id: `note-${Date.now()}`,
      title: 'Новая заметка',
      content: '',
      updatedAt: Date.now(),
    };
    onChangeNotes((prev) => [newNote, ...prev]);
    setSelectedId(newNote.id);
  };

  const updateNote = (id: string, patch: Partial<NoteEntry>) => {
    onChangeNotes((prev) =>
      prev.map((n) => (n.id === id ? { ...n, ...patch, updatedAt: Date.now() } : n))
    );
  };

  const deleteNote = (id: string) => {
    onChangeNotes((prev) => prev.filter((n) => n.id !== id));
  };

  return (
    <div className="h-full flex text-slate-100">
      <aside className="w-56 shrink-0 border-r border-white/10 bg-slate-900/50 flex flex-col">
        <div className="p-3 border-b border-white/10">
          <button
            type="button"
            onClick={createNote}
            className="w-full flex items-center justify-center gap-1.5 py-2 rounded-xl bg-amber-500/20 hover:bg-amber-500/30 border border-amber-400/30 text-amber-200 text-xs font-semibold transition-colors cursor-pointer"
          >
            <Plus className="w-3.5 h-3.5" />
            Новая заметка
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-2 space-y-1">
          {notes.map((note) => {
            const selected = note.id === activeNote?.id;
            return (
              <div
                key={note.id}
                className={`group flex items-start justify-between gap-1 p-2.5 rounded-xl cursor-pointer transition-colors ${
                  selected
                    ? 'bg-white/12 text-white'
                    : 'text-slate-300 hover:bg-white/5 hover:text-white'
                }`}
                onClick={() => setSelectedId(note.id)}
              >
                <div className="min-w-0 flex-1">
                  <div className="text-xs font-medium truncate">
                    {note.title || 'Без названия'}
                  </div>
                  <div className="text-[10px] text-slate-400 mt-0.5">
                    {new Date(note.updatedAt).toLocaleDateString('ru-RU', {
                      day: 'numeric',
                      month: 'short',
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                  </div>
                </div>
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    deleteNote(note.id);
                  }}
                  title="Удалить заметку"
                  aria-label="Удалить заметку"
                  className="opacity-0 group-hover:opacity-100 p-1 rounded text-slate-400 hover:text-rose-300 transition-opacity cursor-pointer"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
            );
          })}
        </div>
      </aside>

      <div className="flex-1 flex flex-col min-w-0">
        {activeNote ? (
          <>
            <div className="px-5 pt-4 pb-3 border-b border-white/10">
              <input
                type="text"
                value={activeNote.title}
                onChange={(e) => updateNote(activeNote.id, { title: e.target.value })}
                placeholder="Заголовок заметки"
                className="w-full bg-transparent font-display text-base font-semibold text-white placeholder:text-slate-500 focus:outline-none"
              />
            </div>
            <textarea
              value={activeNote.content}
              onChange={(e) => updateNote(activeNote.id, { content: e.target.value })}
              placeholder="Начните писать…"
              className="flex-1 w-full p-5 bg-transparent text-sm leading-relaxed text-slate-200 placeholder:text-slate-500 resize-none focus:outline-none"
            />
          </>
        ) : (
          <div className="flex-1 flex flex-col items-center justify-center text-xs text-slate-400 gap-3">
            <span>Заметок пока нет</span>
            <button
              type="button"
              onClick={createNote}
              className="px-3.5 py-2 rounded-xl bg-white/10 hover:bg-white/15 text-white font-medium cursor-pointer"
            >
              Создать первую заметку
            </button>
          </div>
        )}
      </div>
    </div>
  );
};
