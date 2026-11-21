import unittest
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch, Mock
import assistant

class SafetyTests(unittest.TestCase):
    def test_voice_loader_disables_model_downloads(self):
        factory = Mock()
        with tempfile.TemporaryDirectory() as folder:
            with patch.dict('sys.modules', {'faster_whisper': SimpleNamespace(WhisperModel=factory)}):
                assistant.load_voice_model(Path(folder))
            factory.assert_called_once_with(str(Path(folder).resolve()), device='cpu',
                                            compute_type='int8', local_files_only=True)

    @patch('assistant.run')
    def test_rejects_invalid_actions(self, run):
        for name, args in [('shell', {}), ('set_volume', {'level': 101}),
                           ('set_volume', {'level': True}), ('open_app', {'name': 'Terminal'}),
                           ('get_time', {'extra': 'bad'})]:
            with self.assertRaises(ValueError):
                assistant.execute(name, args)
        run.assert_not_called()

    @patch('assistant.run')
    def test_denied_action_does_not_execute(self, run):
        result = assistant.execute('open_app', {'name': 'calculator'}, confirm=lambda _: 'no')
        self.assertIn('declined', result)
        run.assert_not_called()

    @patch('assistant.run')
    def test_approved_volume_uses_validated_argument(self, run):
        assistant.execute('set_volume', {'level': 30}, confirm=lambda _: 'y')
        run.assert_called_once_with(['osascript', '-e', 'set volume output volume 30'])

if __name__ == '__main__':
    unittest.main()

class ModelSelectionTests(unittest.TestCase):
    @patch('assistant.request')
    def test_prefers_tested_model_within_memory_budget(self, request):
        request.return_value = {'capabilities': ['completion', 'tools']}
        models = [{'name': 'huge:27b', 'size': 17_000_000_000},
                  {'name': 'qwen3:8b', 'size': 5_200_000_000},
                  {'name': 'llama3.2:latest', 'size': 2_000_000_000}]
        self.assertEqual(assistant.select_model(models, memory_bytes=16 * 1024**3), 'qwen3:8b')
        self.assertEqual(assistant.select_model(models, memory_bytes=8 * 1024**3), 'llama3.2:latest')

    @patch('assistant.request')
    def test_rejects_cloud_alias_and_models_without_tools(self, request):
        request.side_effect = [{'remote_host': 'https://example.com', 'capabilities': ['completion', 'tools']},
                               {'capabilities': ['embedding']}]
        models = [{'name': 'alias', 'size': 100}, {'name': 'embed', 'size': 200},
                  {'name': 'model:cloud', 'size': 300}]
        with self.assertRaises(ValueError):
            assistant.select_model(models, memory_bytes=16 * 1024**3)
        self.assertEqual(request.call_count, 2)

    @patch('assistant.request')
    def test_no_model_means_no_cloud_fallback(self, request):
        with self.assertRaises(ValueError):
            assistant.select_model([], memory_bytes=16 * 1024**3)
        request.assert_not_called()
