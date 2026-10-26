#!/usr/bin/env python3
"""Read-only Newton resource/coverage soak. No history text, mail evidence or audio exported."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import time


def identity(pid):
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'lstart=,comm='], capture_output=True, text=True, timeout=5)
    return result.stdout.strip() if result.returncode == 0 else None


def snapshot(pid, directory):
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', '%cpu=,rss=,cputime='], capture_output=True, text=True, timeout=5)
    fields = result.stdout.split()
    if len(fields) != 3:
        raise RuntimeError('Monitored process unavailable')
    files = {}
    for stem in ('history.sqlite', 'intelligence.sqlite'):
        for suffix in ('', '-wal', '-shm'):
            path = directory / (stem + suffix)
            if path.exists():
                stat = path.stat()
                files[path.name] = {'logicalBytes': stat.st_size, 'allocatedBytes': stat.st_blocks * 512}
    counts = {}
    coverage = []
    for stem, query in [('history.sqlite', 'SELECT count(*) FROM events'), ('intelligence.sqlite', 'SELECT count(*) FROM records')]:
        path = directory / stem
        if not path.exists():
            continue
        with sqlite3.connect('file:' + str(path) + '?mode=ro', uri=True, timeout=2) as db:
            counts[stem] = db.execute(query).fetchone()[0]
            if stem == 'intelligence.sqlite':
                coverage = [json.loads(row[0]) for row in db.execute("SELECT payload FROM records WHERE namespace='coverage' AND json_extract(payload,'$.end') IS NULL")]
    return {'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'cpuPercent': float(fields[0]), 'rssKiB': int(fields[1]), 'cumulativeCPU': fields[2], 'databaseFiles': files, 'rowCounts': counts, 'sourceStates': [{'source': x['source'], 'state': x['state'], 'reason': x['reason'][:300]} for x in coverage]}


def atomic_write(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--duration', type=float, default=86400)
    parser.add_argument('--interval', type=float, default=60)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    initial_identity = identity(args.pid)
    if not initial_identity:
        raise SystemExit('Newton is not running')
    receipt = {'startedAt': dt.datetime.now(dt.timezone.utc).isoformat(), 'requestedSeconds': args.duration, 'pid': args.pid, 'processIdentity': initial_identity, 'binarySHA256': hashlib.sha256(args.binary.read_bytes()).hexdigest(), 'complete': False, 'samples': [], 'errors': [], 'scope': 'Observed resource/coverage soak; real sleep/wake and utility acceptance are separate receipts. CPU samples do not imply a zero-CPU guarantee.'}
    started = time.monotonic()
    while True:
        elapsed = time.monotonic() - started
        if identity(args.pid) != initial_identity:
            receipt['errors'].append('Original Newton process exited or PID identity changed')
            break
        try:
            receipt['samples'].append(snapshot(args.pid, args.directory))
        except Exception as error:
            receipt['errors'].append(str(error))
        receipt['elapsedSeconds'] = elapsed
        receipt['complete'] = elapsed >= args.duration and not receipt['errors']
        atomic_write(args.output, receipt)
        if elapsed >= args.duration:
            break
        time.sleep(min(max(1, args.interval), args.duration - elapsed))
    receipt['finishedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    atomic_write(args.output, receipt)


if __name__ == '__main__':
    main()
