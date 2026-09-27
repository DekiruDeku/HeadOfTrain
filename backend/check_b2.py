"""Run B1+B2 tests and six HTTP demos on a temporary database; retain real logs."""
import argparse
import json
import platform
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/server/b2')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    commands = []

    def run(command, filename):
        result = subprocess.run([sys.executable, *command], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
        (output / filename).write_text(result.stdout, encoding='utf-8')
        commands.append({'command': [sys.executable, *command], 'exit_code': result.returncode, 'log': filename})
        print(result.stdout, end='', flush=True)
        if result.returncode:
            raise SystemExit(result.returncode)

    try:
        run(['-m', 'unittest', 'discover', '-s', 'backend/tests', '-v'], 'test-results.txt')
        run(['backend/b2_paths.py', '--check'], 'path-table-check.txt')
        with tempfile.TemporaryDirectory(prefix='hot-b2-') as tmp, (output / 'demo-server.log').open('w') as log:
            proc = subprocess.Popen([sys.executable, '-u', 'backend/server.py', '--port', '0', '--db', str(Path(tmp) / 'demo.sqlite3')], cwd=ROOT, stdout=subprocess.PIPE, stderr=log, text=True)
            try:
                first = proc.stdout.readline().strip()
                if not first.startswith('Game: '):
                    raise RuntimeError('Server failed to start: ' + first)
                base = first.removeprefix('Game: ').rstrip('/')
                run(['backend/demo.py', '--base-url', base, '--record', str(output / 'http-exchanges')], 'demo-results.txt')
            finally:
                proc.terminate()
                proc.wait(timeout=10)
                proc.stdout.close()
    finally:
        (output / 'run.json').write_text(json.dumps({'finished_at_utc': datetime.now(timezone.utc).isoformat(), 'python': sys.version, 'sqlite': sqlite3.sqlite_version, 'platform': platform.platform(), 'commands': commands}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
