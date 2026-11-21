import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'native'))
from actions import UndoManager

class UndoTests(unittest.TestCase):
    def test_volume_undo_requires_permission_approval_and_unchanged_state(self):
        u = UndoManager(); u.pending = ('volume', 20, 40)
        with patch('assistant.run', return_value='40') as run:
            with self.assertRaises(ValueError): u.undo(set(), lambda _: 'y')
            self.assertIn('cancelled', u.undo({'set_volume'}, lambda _: 'n'))
            run.assert_called_once()
            u.undo({'set_volume'}, lambda _: 'y')
            self.assertIsNone(u.pending)
            self.assertEqual(run.call_args.args[0][-1], 'set volume output volume 20')

    def test_external_note_changes_block_undo(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'notes.txt';p.write_bytes(b'new external note')
            u=UndoManager();u.pending=('note',p,b'before',b'after')
            with self.assertRaises(ValueError):u.undo({'save_note'}, lambda _: 'y')
            self.assertEqual(p.read_bytes(),b'new external note')

    def test_declined_actions_do_not_replace_undo(self):
        u=UndoManager();u.original=Mock(return_value='User declined; no action performed.');u.pending=('volume',10,20)
        with patch('assistant.run',return_value='20'):u.execute('set_volume',{'level':50},lambda _: 'n')
        self.assertEqual(u.pending,('volume',10,20))
