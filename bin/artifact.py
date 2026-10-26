#!/usr/bin/env python3
"""Newton's local build receipt. Detects mismatches; it is not a remote trust signature."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def source_digest(root):
    paths = []
    for directory in ('Sources', 'Tests', 'Resources', 'Benchmarks', 'Automation', 'bin'):
        base = root / directory
        if base.is_symlink():
            raise ValueError(f'Build directories must not be symlinks: {base}')
        if base.exists():
            for path in base.rglob('*'):
                if '__pycache__' in path.parts or path.name == '.DS_Store':
                    continue
                if path.is_symlink():
                    raise ValueError(f'Build inputs must not be symlinks: {path}')
                if path.is_file():
                    paths.append(path)
    paths.extend(root / name for name in ('Package.swift', 'version.txt', 'build.sh', 'test.sh'))
    result = hashlib.sha256()
    for path in sorted(set(paths)):
        if path.is_symlink():
            raise ValueError(f'Build inputs must not be symlinks: {path}')
        name = path.relative_to(root).as_posix().encode()
        data = path.read_bytes()
        result.update(len(name).to_bytes(8, 'big') + name + len(data).to_bytes(8, 'big') + data)
    return result.hexdigest()


def version(root):
    text = (root / 'version.txt').read_text().strip()
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', text):
        raise ValueError('version.txt must contain a three-part numeric version')
    return text


def atomic_json(path, value):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    os.replace(temporary, path)


def verify(root, archive, receipt):
    data = json.loads(receipt.read_text())
    if data['version'] != version(root) or data['sourceSHA256'] != source_digest(root):
        raise ValueError('Artifact source/version differs from the current build inputs; rebuild first')
    if data['archiveSHA256'] != digest(archive.read_bytes()):
        raise ValueError('Archive digest does not match its build receipt')
    with zipfile.ZipFile(archive) as bundle:
        info = plistlib.loads(bundle.read('Newton.app/Contents/Info.plist'))
        if info['CFBundleShortVersionString'] != data['version'] or info['CFBundleVersion'] != data['version']:
            raise ValueError('Packaged app version differs from the receipt')
        if digest(bundle.read('Newton.app/Contents/MacOS/Newton')) != data['binarySHA256']:
            raise ValueError('Packaged binary differs from the receipt')
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['digest', 'create', 'verify', 'attest'])
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--expected-source')
    parser.add_argument('--sdk', default='unspecified')
    parser.add_argument('--signing-mode', default='unspecified')
    args = parser.parse_args()
    root = args.root.resolve()
    if args.action == 'digest':
        version(root)
        print(source_digest(root))
        return
    archive = args.archive or root / 'build/Newton.zip'
    receipt = args.receipt or root / 'build/receipt.json'
    if args.action == 'create':
        current_digest = source_digest(root)
        if args.expected_source != current_digest:
            raise ValueError('Build inputs changed during compilation; previous artifact is preserved')
        with zipfile.ZipFile(archive) as bundle:
            binary = bundle.read('Newton.app/Contents/MacOS/Newton')
        data = dict(version=version(root), sourceSHA256=current_digest,
                    archiveSHA256=digest(archive.read_bytes()), binarySHA256=digest(binary),
                    builtAt=datetime.datetime.now(datetime.timezone.utc).isoformat(), sourceCommit=None, sdk=args.sdk, signingMode=args.signing_mode,
                    compiler=subprocess.check_output(['swift','--version'], text=True).strip())
        atomic_json(receipt, data)
        verify(root, archive, receipt)
    else:
        data = verify(root, archive, receipt)
        if args.action == 'attest':
            if subprocess.check_output(['git', 'status', '--porcelain'], cwd=root).strip():
                raise ValueError('Commit reviewed changes before attesting a source snapshot')
            data['sourceCommit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
            atomic_json(receipt, data)
        print(f"Verified Newton {data['version']} · {data['sourceSHA256'][:12]}")


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
