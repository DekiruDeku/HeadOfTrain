"""Consistent SQLite demo backup/restore; never replace an existing destination."""
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import tempfile


def snapshot(source, destination):
    source, destination = Path(source).resolve(), Path(destination).absolute()
    if not source.is_file():
        raise FileNotFoundError(source)
    for target in [destination] + [Path(str(destination) + suffix) for suffix in ('-wal', '-shm', '-journal')]:
        if target.exists() or target.is_symlink():
            raise FileExistsError(target)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.sqlite-snapshot-', dir=destination.parent)
    os.close(fd)
    temporary = Path(name)
    try:
        # Read-only connection still includes committed WAL pages. A plain file
        # copy or immutable=1 would not provide this guarantee for a live DB.
        with closing(sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)) as src:
            with closing(sqlite3.connect(temporary)) as dst:
                src.backup(dst)
                integrity = [r[0] for r in dst.execute('PRAGMA integrity_check')]
                foreign_keys = dst.execute('PRAGMA foreign_key_check').fetchall()
                version = dst.execute('PRAGMA user_version').fetchone()[0]
                tables = {r[0] for r in dst.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if integrity != ['ok'] or foreign_keys or version not in (1, 2) or not {'players', 'trips', 'requests'} <= tables:
                    raise ValueError('Not a valid Head of Train database (schema 1 or 2).')
                dst.execute('PRAGMA journal_mode=DELETE')
        # Windows fsync requires a writable descriptor; r+b does not truncate.
        with temporary.open('r+b') as handle:
            os.fsync(handle.fileno())
        # Atomic publication fails if somebody created destination meanwhile.
        os.link(temporary, destination)
        return {'source': str(source), 'destination': str(destination),
                'schema_version': version, 'integrity_check': 'ok', 'foreign_key_check': []}
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('backup', 'restore'))
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    # Both operations copy a consistent database into a NEW file. Restore does
    # not change server settings: explicitly restart with --db destination.
    print(json.dumps(snapshot(args.source, args.destination), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
