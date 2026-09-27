"""Run B1/B2/B3 checks on isolated databases and retain actual logs."""
import argparse
import json
import platform
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/server/b3-local-check')
    parser.add_argument('--real-time', action='store_true', help='Also run a 26-second HTTP demo on the production clock')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    commands = [(['-m', 'unittest', 'discover', '-s', 'backend/tests', '-v'], 'test-results.txt'),
                (['backend/b2_paths.py', '--check'], 'path-table-check.txt'),
                (['backend/demo_b3.py', '--record', str(output / 'http-exchanges')], 'demo-results.txt')]
    if args.real_time:
        commands.append((['backend/demo_b3.py', '--real-time', '--record', str(output / 'realtime-http')], 'realtime-results.txt'))
    results = []
    try:
        for command, log in commands:
            result = subprocess.run([sys.executable, *command], cwd=ROOT, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, timeout=120)
            (output / log).write_text(result.stdout, encoding='utf-8')
            results.append({'command': [sys.executable, *command], 'exit_code': result.returncode, 'log': log})
            print(log + ': ' + ('OK' if result.returncode == 0 else 'FAIL'), flush=True)
            if result.returncode:
                raise SystemExit(result.returncode)
    finally:
        (output / 'run.json').write_text(json.dumps({'finished_at_utc': datetime.now(timezone.utc).isoformat(),
            'python': sys.version, 'sqlite': sqlite3.sqlite_version, 'platform': platform.platform(),
            'commands': results}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
