"""TEST ONLY: subprocess clock injection and crash gates. No production endpoint."""
import argparse
import sys
from functools import partial
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from backend.tests.fault_server import GatedHandler, GatedStore, TestServer
from backend.server import ROOT

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', type=Path, required=True)
    parser.add_argument('--clock-file', type=Path, required=True)
    args = parser.parse_args()
    server = TestServer(('127.0.0.1', 0), partial(GatedHandler, directory=str(ROOT / 'build/web')))
    server.store = GatedStore(args.db, clock_ms=lambda: int(args.clock_file.read_text()))
    print(f'Game: http://127.0.0.1:{server.server_port}/', flush=True)
    server.serve_forever()
