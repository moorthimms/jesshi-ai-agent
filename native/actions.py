"""User-approved, reversible actions for the private native runtime."""
from pathlib import Path
import assistant


class UndoManager:
    def __init__(self):
        self.pending = None

    def execute(self, name, args, confirm):
        snapshot = None
        if name == 'set_volume' and type(args.get('level')) is int and 0 <= args['level'] <= 100:
            try:
                before = int(assistant.run(['osascript', '-e', 'output volume of (get volume settings)']))
                snapshot = ('volume', before, args['level'])
            except (ValueError, OSError):
                pass
        elif name == 'save_note':
            path = Path(assistant.__file__).with_name('notes.txt')
            before = path.read_bytes() if path.exists() else b''
            snapshot = ('note', path, before)
        result = self.original(name, args, confirm=confirm)
        if result.endswith(': completed.') and snapshot:
            if snapshot[0] == 'note':
                self.pending = (*snapshot, snapshot[1].read_bytes())
            else:
                self.pending = snapshot
        return result

    def undo(self, allowed, confirm):
        if not self.pending:
            return 'No reversible action in this engine session.'
        kind, target, before = self.pending[:3]
        if kind == 'volume':
            if 'set_volume' not in allowed:
                raise ValueError('Volume permission is disabled')
            current = int(assistant.run(['osascript', '-e', 'output volume of (get volume settings)']))
            if current != before:
                raise ValueError('Volume changed since this action; undo refused')
            if confirm(f'Restore volume to {target}% [y/N] ') != 'y':
                return 'Undo cancelled.'
            assistant.run(['osascript', '-e', f'set volume output volume {target}'])
        else:
            if 'save_note' not in allowed:
                raise ValueError('Notes permission is disabled')
            if not target.exists() or target.read_bytes() != self.pending[3]:
                raise ValueError('Notes changed since this action; undo refused')
            if confirm('Remove the last appended tool note? [y/N] ') != 'y':
                return 'Undo cancelled.'
            target.write_bytes(before)
        self.pending = None
        return 'Last reversible action undone.'
