"""One-time online download; runtime assistant never downloads models."""
from pathlib import Path
from faster_whisper.utils import download_model

if __name__ == '__main__':
    target = Path(__file__).resolve().parent / 'models' / 'whisper-base'
    print('Downloading the multilingual Whisper base model for offline use…')
    download_model('base', output_dir=str(target))
    print(f'Ready: {target}')
