#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source bin/toolchain.sh
newton_output="${NEWTON_BUILD_OUTPUT:-build}"
mkdir -p "$newton_output" build
if ! mkdir build/.build-lock 2>/dev/null; then
    printf 'Another build owns build/.build-lock. Inspect its PID before removing a stale lock.\n' >&2
    exit 1
fi
printf '%s\n' "$$" > build/.build-lock/pid
newton_stage=""
newton_publishing=0
newton_published=0
cleanup() {
    newton_result=$?
    set +e
    if [[ "$newton_publishing" == 1 && "$newton_published" != 1 ]]; then
        for item in Newton.app Newton.zip receipt.json; do
            rm -rf -- "$newton_output/$item"
            if [[ -e "$newton_stage/previous/$item" ]]; then mv "$newton_stage/previous/$item" "$newton_output/$item"; fi
        done
    fi
    if [[ -n "$newton_stage" ]]; then rm -rf -- "$newton_stage"; fi
    rm -f build/.build-lock/pid
    rmdir build/.build-lock
    exit "$newton_result"
}
trap cleanup EXIT
newton_stage="$(mktemp -d "$newton_output/.stage.XXXXXX")"
newton_digest="$(python3 bin/artifact.py digest)"
swift build -c release --sdk "$newton_sdk"
newton_binary_dir="$(swift build -c release --sdk "$newton_sdk" --show-bin-path)"
mkdir -p "$newton_stage/Newton.app/Contents/"{MacOS,Resources}
cp "$newton_binary_dir/Newton" "$newton_stage/Newton.app/Contents/MacOS/Newton"
swift -sdk "$newton_sdk" bin/make-icon.swift "$newton_stage/Newton.iconset"
iconutil -c icns "$newton_stage/Newton.iconset" -o "$newton_stage/Newton.app/Contents/Resources/Newton.icns"
python3 - "$newton_stage" <<'PY'
import plistlib
from pathlib import Path
import sys
version = Path('version.txt').read_text().strip()
info = dict(CFBundleName='Newton', CFBundleDisplayName='Newton', CFBundleExecutable='Newton',
            CFBundleIdentifier='com.tapchipswipe.newton', CFBundlePackageType='APPL', CFBundleIconFile='Newton',
            CFBundleShortVersionString=version, CFBundleVersion=version,
            LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True,
            NSMicrophoneUsageDescription='Newton records microphone audio only when you start an on-device meeting transcript.',
            NSSpeechRecognitionUsageDescription='Newton uses on-device speech recognition for explicitly started meeting transcripts.',
            NSAudioCaptureUsageDescription='Newton requests system audio only for an explicitly enabled meeting session on supported systems.',
            NSAppleEventsUsageDescription='Newton reads Mail receipts and now-playing metadata without sending or changing messages.',
            NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
with open(Path(sys.argv[1])/'Newton.app/Contents/Info.plist','wb') as output:
    plistlib.dump(info, output)
PY
newton_identity="-"
newton_signing_mode="ad-hoc (stable macsync-dev identity unavailable)"
if [[ "$(security find-identity -v -p codesigning 2>/dev/null)" == *'"macsync-dev"'* ]]; then
    newton_identity="macsync-dev"
    newton_signing_mode="macsync-dev"
fi
codesign --force --sign "$newton_identity" "$newton_stage/Newton.app"
codesign --verify --strict "$newton_stage/Newton.app"
ditto -c -k --keepParent "$newton_stage/Newton.app" "$newton_stage/Newton.zip"
python3 bin/artifact.py create --archive "$newton_stage/Newton.zip" --receipt "$newton_stage/receipt.json" --expected-source "$newton_digest" --sdk "$newton_sdk" --signing-mode "$newton_signing_mode"
mkdir -p "$newton_stage/previous"
# Once packaging is complete, replace the three outputs together with rollback on errors.
for item in Newton.app Newton.zip receipt.json; do
    if [[ -e "$newton_output/$item" ]]; then cp -R "$newton_output/$item" "$newton_stage/previous/$item"; fi
done
newton_publishing=1
for item in Newton.app Newton.zip receipt.json; do
    rm -rf -- "$newton_output/$item"
    mv "$newton_stage/$item" "$newton_output/$item"
done
newton_published=1
printf 'Built and verified Newton.app, Newton.zip, and receipt.json\n'
