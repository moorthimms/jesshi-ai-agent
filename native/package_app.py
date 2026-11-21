"""Assemble a self-contained Apple Silicon app from the local build outputs."""
import json
import plistlib
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'dist/Offline Assistant.app'
RES = APP / 'Contents/Resources'
RUNTIME = Path('/Applications/Ollama.app/Contents/Resources')
MODEL_ROOT = Path.home() / '.ollama/models'

def copy(source, target):
    source, target = Path(source), Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    # Replace the inode so macOS does not retain a stale executable signature.
    temporary = target.with_name(target.name + '.new')
    shutil.copy2(source, temporary)
    temporary.replace(target)

if __name__ == '__main__':
    speech_source = ROOT / 'models/whisper-small'
    if not (speech_source / 'model.bin').is_file():
        raise RuntimeError('Whisper small download is incomplete; refusing to package mixed speech models')
    RES.mkdir(parents=True, exist_ok=True)
    copy(ROOT / 'build-cache/OfflineAssistant', APP / 'Contents/MacOS/OfflineAssistant')
    # Never overwrite a running PyInstaller executable/archive in place.
    # Its process may lazily decompress modules from the original inode.
    shutil.copytree(ROOT / 'build-cache/dist/backend', RES / 'backend', dirs_exist_ok=True, copy_function=copy)
    copy(ROOT / 'build-cache/dist/backend/backend', RES / 'backend/backend')
    shutil.copytree(ROOT / 'models/whisper-small', RES / 'speech', dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('.cache', '*.new'), copy_function=copy)
    runtime_target = RES / 'runtime'
    runtime_target.mkdir(exist_ok=True)
    for source in RUNTIME.iterdir():
        if source.name in ('ollama', 'llama-server') or source.suffix in ('.dylib', '.so') or 'LICENSE' in source.name or source.name.endswith('NOTICE'):
            copy(source, runtime_target / source.name)
        elif source.is_dir() and source.name.startswith('mlx_metal'):
            shutil.copytree(source, runtime_target / source.name, dirs_exist_ok=True)
    # Copy real files, not symlinks to the user's model store.
    for model in ('qwen3/8b', 'llama3.2/latest'):
        manifest_path = Path('manifests/registry.ollama.ai/library') / model
        source = MODEL_ROOT / manifest_path
        if model != 'qwen3/8b' and not source.is_file():
            continue
        manifest = json.loads(source.read_text())
        for layer in [manifest['config'], *manifest['layers']]:
            blob = layer['digest'].replace(':', '-')
            target = RES / 'models/blobs' / blob
            if not target.exists() or target.stat().st_size != layer['size']:
                copy(MODEL_ROOT / 'blobs' / blob, target)
        copy(source, RES / 'models' / manifest_path)
    info = dict(CFBundleName='Jessy', CFBundleDisplayName='Jessy',
                CFBundleIdentifier='local.offline.assistant.standalone',
                CFBundleExecutable='OfflineAssistant', CFBundlePackageType='APPL',
                CFBundleShortVersionString='1.4', CFBundleVersion='6',
                LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True,
                NSCalendarsWriteOnlyAccessUsageDescription='Create calendar events after you approve them.',
                NSCalendarsFullAccessUsageDescription='Read your calendar to show a briefing when you ask.',
                NSRemindersFullAccessUsageDescription='Add tasks to Apple Reminders when you request it.',
                NSLocalNetworkUsageDescription='Connect to your configured local Home Assistant server.',
                NSAppTransportSecurity={'NSAllowsLocalNetworking': True, 'NSAllowsArbitraryLoads': True},
                NSMicrophoneUsageDescription='Record your voice for offline transcription on this Mac.',
                NSAppleEventsUsageDescription='Control selected Mac apps after you approve an action.')
    with (APP / 'Contents/Info.plist').open('wb') as f:
        plistlib.dump(info, f)
    # Local ad-hoc signature. Developer ID signing/notarization is separate.
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(APP)], check=True)
    print(APP)
