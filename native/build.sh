#!/bin/zsh
set -eu
cd -- "${0:A:h:h}"
mkdir -p build-cache
export CLANG_MODULE_CACHE_PATH="$PWD/build-cache/clang"
export PYINSTALLER_CONFIG_DIR="$PWD/build-cache/pyinstaller"
swiftc -parse-as-library -O -target arm64-apple-macosx14.0 native/OfflineAssistant.swift native/VoiceController.swift shared/PortableBackup.swift shared/DeviceServices.swift shared/Retrieval.swift -o build-cache/OfflineAssistant -module-cache-path "$PWD/build-cache/swift"
.venv/bin/python -m PyInstaller --noconfirm --onedir --name backend --paths . --hidden-import voice_worker --collect-all faster_whisper --collect-all ctranslate2 --collect-all tokenizers --collect-all onnxruntime --exclude-module sounddevice --exclude-module tkinter --distpath build-cache/dist --workpath build-cache/work native/backend.py
python3 native/package_app.py
