#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "$(git status --porcelain)" ]]; then
    printf 'Commit reviewed changes before mirroring.\n' >&2
    exit 1
fi
newton_lock="$(git rev-parse --git-common-dir)/newton-mirror-lock"
if ! mkdir "$newton_lock" 2>/dev/null; then
    printf 'Another mirror owns %s; inspect it before removing a stale lock.\n' "$newton_lock" >&2
    exit 1
fi
newton_stage=""
cleanup() {
    newton_result=$?
    set +e
    if [[ -n "$newton_stage" ]]; then rm -rf -- "$newton_stage"; fi
    rmdir "$newton_lock"
    exit "$newton_result"
}
trap cleanup EXIT
newton_commit="$(git rev-parse HEAD)"
newton_artifacts="${NEWTON_ARTIFACT_DIRECTORY:-build}"
python3 bin/artifact.py attest --archive "$newton_artifacts/Newton.zip" --receipt "$newton_artifacts/receipt.json"
newton_mirror="${NEWTON_MIRROR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Projects/Newton}"
mkdir -p "$newton_mirror/snapshots"
newton_stage="$(mktemp -d "$newton_mirror/.snapshot.XXXXXX")"
git archive "$newton_commit" | tar -x -C "$newton_stage"
mkdir -p "$newton_stage/_artifacts"
cp "$newton_artifacts/Newton.zip" "$newton_artifacts/receipt.json" "$newton_stage/_artifacts/"
python3 bin/artifact.py verify --root "$newton_stage" --archive "$newton_stage/_artifacts/Newton.zip" --receipt "$newton_stage/_artifacts/receipt.json"
newton_archive="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["archiveSHA256"])' "$newton_stage/_artifacts/receipt.json")"
mkdir -p "$newton_mirror/snapshots/$newton_commit"
newton_destination="$newton_mirror/snapshots/$newton_commit/$newton_archive"
if [[ -e "$newton_destination" ]]; then
    cmp "$newton_destination/_artifacts/Newton.zip" "$newton_stage/_artifacts/Newton.zip"
    python3 bin/artifact.py verify --root "$newton_destination" --archive "$newton_destination/_artifacts/Newton.zip" --receipt "$newton_destination/_artifacts/receipt.json"
else
    mv "$newton_stage" "$newton_destination"
fi
if [[ -n "$(git status --porcelain)" || "$(git rev-parse HEAD)" != "$newton_commit" ]]; then
    printf 'Repository changed during mirroring; current.json was not advanced.\n' >&2
    exit 1
fi
python3 - "$newton_mirror" "$newton_commit" "$newton_archive" <<'PY'
import json, os, sys
from pathlib import Path
root=Path(sys.argv[1]); commit=sys.argv[2]; archive=sys.argv[3]
snapshot=root/'snapshots'/commit/archive
receipt=json.loads((snapshot/'_artifacts/receipt.json').read_text())
manifest=dict(commit=commit,version=receipt['version'],snapshot=f'snapshots/{commit}/{archive}',archiveSHA256=receipt['archiveSHA256'],cloudUploadVerified=False)
p=root/'current.json.tmp'; p.write_text(json.dumps(manifest,indent=2)+'\n'); os.replace(p,root/'current.json')
(root/'MEMORY.md').write_bytes((snapshot/'MEMORY.md').read_bytes())
(root/'MIRROR.md').write_text('Read current.json for the exact latest source/artifact snapshot. Older top-level files are legacy v0.1.0 copies, retained rather than silently removed. No server upload is inferred.\n')
PY
printf 'Verified local iCloud snapshot: %s (server upload unverified)\n' "$newton_destination"
