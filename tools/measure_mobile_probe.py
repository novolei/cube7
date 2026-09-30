"""Measure the installed development probe on one explicitly selected phone.

python tools/measure_mobile_probe.py --adb <adb.exe> --serial <serial> --out <directory>
The probe must print MOBILE_IDLE and leave 45 seconds for the idle sample.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    base = [args.adb, '-s', args.serial]
    package = 'com.novolei.cube7.polishprobe'

    def adb(*parts):
        return subprocess.check_output(base + list(parts), timeout=15).decode('utf-8', errors='replace')

    adb('shell', 'am', 'force-stop', package)
    adb('shell', 'monkey', '-p', package, '-c', 'android.intent.category.LAUNCHER', '1')
    deadline = time.monotonic() + 120
    process = ''
    while time.monotonic() < deadline:
        try:
            process = adb('shell', 'pidof', package).strip()
        except subprocess.CalledProcessError as error:
            if error.returncode != 1:
                raise
            process = ''
        if process and 'MOBILE_IDLE' in adb('logcat', '-d', '--pid=' + process, '-v', 'brief'):
            break
        time.sleep(0.5)
    else:
        raise RuntimeError('The game did not reach the idle probe')
    time.sleep(5)  # Settle remaining background generation and shader compilation.
    start = time.monotonic()
    first = adb('shell', 'dumpsys', 'meminfo', package)
    (args.out / 'idle.png').write_bytes(subprocess.check_output(base + ['exec-out', 'screencap', '-p'], timeout=15))
    time.sleep(max(0, 30 - (time.monotonic() - start)))
    elapsed = time.monotonic() - start
    second = adb('shell', 'dumpsys', 'meminfo', package)
    record = {'serial': args.serial, 'idle_interval_seconds': elapsed, 'before': first, 'after': second}
    (args.out / 'memory.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
    print(f'Idle memory: {elapsed:.1f} seconds, saved to {args.out}', flush=True)
    while time.monotonic() < deadline:
        logs = adb('logcat', '-d', '--pid=' + process, '-v', 'brief')
        if 'later 4-9s' in logs:
            (args.out / 'runtime.log').write_text(logs, encoding='utf-8')
            rows = [json.loads(line[line.index('{'):]) for line in logs.splitlines() if '"phase"' in line and '{' in line]
            assert len(rows) == 7 and rows[0]['phase'] == 'baseline', 'Incomplete benchmark'
            (args.out / 'performance.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
            print(json.dumps(rows, indent=2), flush=True)
            return
        time.sleep(1)
    raise RuntimeError('The benchmark did not finish')


if __name__ == '__main__':
    main()
