"""Test-only HTTP server: pause after commit, before sending any response bytes.

Control uses stdin/stdout; this header/hook is never enabled in server.py.
"""
import argparse
import sys
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from backend.server import Handler, ROOT, Server
from backend.storage import Store


class GatedHandler(Handler):
    def api(self, method):
        result = super().api(method)
        if self.headers.get('X-Test-Hold-Response') == 'yes':
            print('HANDLER_DONE', flush=True)
        return result

    def json_response(self, status, data):
        if self.headers.get('X-Test-Hold-Response') == 'yes':
            print('COMMITTED' if status == 200 else 'REJECTED', flush=True)
            if sys.stdin.readline().strip() != 'release':
                return
        super().json_response(status, data)


class GatedStore(Store):
    def act(self, db, player_id, trip_id, body, *args, **kwargs):
        result = super().act(db, player_id, trip_id, body, *args, **kwargs)
        if body['request_id'] == 'hold-before-commit':
            print('UNCOMMITTED', flush=True)
            sys.stdin.readline()
        return result


class TestServer(Server):
    def handle_error(self, request, client_address):
        super().handle_error(request, client_address)
        print('HANDLER_FAILED', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', type=Path, required=True)
    args = parser.parse_args()
    server = TestServer(('127.0.0.1', 0), partial(GatedHandler, directory=str(ROOT / 'build/web')))
    server.store = GatedStore(args.db)
    print(f'Game: http://127.0.0.1:{server.server_port}/', flush=True)
    server.serve_forever()
