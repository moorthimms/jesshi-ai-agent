import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('package_app', Path(__file__).resolve().parents[1] / 'native/package_app.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)

class PackagingTests(unittest.TestCase):
    def test_replacing_runtime_preserves_running_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder)/'new', Path(folder)/'runtime'
            source.write_bytes(b'new archive')
            target.write_bytes(b'old running archive')
            with target.open('rb') as running:
                package.copy(source, target)
                self.assertEqual(running.read(), b'old running archive')
            self.assertEqual(target.read_bytes(), b'new archive')
