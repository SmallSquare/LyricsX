#!/usr/bin/env python3
"""Measure macOS process CPU time deltas; 100% means one CPU core."""
import argparse
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--pids', required=True)
parser.add_argument('--seconds', type=int, default=30)
parser.add_argument('--scenario', required=True)
parser.add_argument('--out', required=True)
args = parser.parse_args()
pids = [int(pid) for pid in args.pids.split(',')]


def snapshot():
    rows = {}
    output = subprocess.check_output(
        ['ps', '-p', args.pids, '-o', 'pid=,time=,pcpu='], text=True)
    for line in output.splitlines():
        pid, used, pcpu = line.split()
        seconds = 0.0
        for segment in used.split(':'):
            seconds = seconds * 60 + float(segment)
        rows[int(pid)] = {'cpu_seconds': seconds, 'pcpu_snapshot': float(pcpu)}
    if set(rows) != set(pids):
        raise RuntimeError('A measured process exited')
    return rows


first = snapshot()
started = time.monotonic()
samples = []
for _ in range(args.seconds):
    time.sleep(1)
    samples.append({'elapsed': time.monotonic() - started, 'processes': snapshot()})
wall = time.monotonic() - started
final = samples[-1]['processes']
report = {'scenario': args.scenario, 'seconds': wall, 'first': first, 'samples': samples,
          'cpu_percent_mean': {pid: 100 * (final[pid]['cpu_seconds'] - first[pid]['cpu_seconds']) / wall
                               for pid in pids}}
Path(args.out).write_text(json.dumps(report, indent=2))
print(json.dumps({'seconds': wall, 'cpu_percent_mean': report['cpu_percent_mean']}))
