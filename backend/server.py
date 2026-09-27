"""Local MVP server: persistent trips, progress and same-origin Godot static files."""
from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
from datetime import datetime, timezone
from functools import partial
from http.cookies import SimpleCookie, CookieError
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
from uuid import uuid4

try:
    from .storage import Store, APIError, fail
except ImportError:
    from storage import Store, APIError, fail

ROOT = Path(__file__).resolve().parents[1]
PLAYER_ID = re.compile(r'[0-9a-f]{32}\Z')
TRIP_PATH = re.compile(r'/api/trips/([A-F0-9]{32})(/actions|/assignments|/dialog/open|/dialog/close|/time|/report|/complete)?\Z')


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.js': 'text/javascript'}

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        super().end_headers()

    def json_response(self, status, data):
        payload = json.dumps(data, ensure_ascii=False, allow_nan=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        if getattr(self, 'issued_player_id', None):
            self.send_header('Set-Cookie', f'hot_demo_player={self.issued_player_id}; Path=/api; Max-Age=31536000; HttpOnly; SameSite=Strict')
        self.end_headers()
        self.wfile.write(payload)

    def identity(self, allow_legacy_create=False):
        token = self.headers.get('X-Demo-Player')
        if token is None:
            cookie = SimpleCookie()
            try:
                cookie.load(self.headers.get('Cookie', ''))
            except CookieError:
                fail(400, 'invalid_player_id', 'Некорректная cookie демо-игрока.')
            token = cookie['hot_demo_player'].value if 'hot_demo_player' in cookie else None
        if token is None and allow_legacy_create:
            token = uuid4().hex
            self.issued_player_id = token
        if token is None:
            fail(401, 'player_required', 'Передайте X-Demo-Player или cookie hot_demo_player.')
        if not PLAYER_ID.fullmatch(token):
            fail(400, 'invalid_player_id', 'Идентификатор демо-игрока: 32 строчные шестнадцатеричные цифры.')
        return token

    def read_body(self):
        if self.headers.get('Transfer-Encoding'):
            fail(400, 'invalid_body', 'Используйте Content-Length, chunked не поддерживается.')
        try:
            length = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            fail(400, 'invalid_body', 'Некорректный Content-Length.')
        if not 0 <= length <= 4096:
            fail(413, 'body_too_large', 'Максимальный размер тела — 4096 байт.')
        if length and self.headers.get_content_type() != 'application/json':
            fail(415, 'unsupported_media_type', 'Ожидается application/json.')
        def unique_pairs(pairs):
            value = {}
            for key, item in pairs:
                if key in value:
                    raise ValueError('Duplicate JSON key')
                value[key] = item
            return value
        def invalid_constant(value):
            raise ValueError(value)
        def finite_float(value):
            number = float(value)
            if not math.isfinite(number):
                raise ValueError('Non-finite number')
            return number
        try:
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise ValueError('Incomplete body')
            body = json.loads(raw or b'{}', object_pairs_hook=unique_pairs, parse_constant=invalid_constant, parse_float=finite_float)
            if not isinstance(body, dict):
                raise ValueError('Expected object')
            return body
        except (ValueError, UnicodeError, RecursionError):
            fail(400, 'invalid_json', 'Ожидается корректный JSON-объект без повторяющихся ключей.')

    def api(self, method):
        # A committed mutation stays committed if the peer disappears during
        # headers/body delivery. Do not try to write another response to the
        # broken socket; the client recovers with its original request_id.
        try:
            self.dispatch_api(method)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            self.close_connection = True
            self.log_error('Client disconnected; recover using the same request_id')

    def dispatch_api(self, method):
        try:
            path = urlsplit(self.path).path
            if path == '/api/health':
                if method != 'GET':
                    fail(405, 'method_not_allowed', 'Используйте GET.')
                return self.json_response(200, {'ok': True, 'service': 'head-of-train', 'time': datetime.now(timezone.utc).isoformat(), 'api_version': 'v1'})
            if path in ('/api/profile', '/api/leaderboard', '/api/notifications'):
                if method != 'GET':
                    fail(405, 'method_not_allowed', 'Используйте GET.')
                operation = path.rsplit('/', 1)[-1]
                query = parse_qs(urlsplit(self.path).query, keep_blank_values=True)
                allowed = {'scope','page','page_size'} if operation == 'leaderboard' else {'page','page_size'} if operation == 'notifications' else set()
                if set(query) - allowed or any(len(v) != 1 for v in query.values()):
                    fail(400, 'invalid_query', 'Неизвестные или повторяющиеся параметры.')
                params = {k:v[0] for k,v in query.items()}
                for k in ('page','page_size'):
                    if k in params:
                        if not re.fullmatch(r'[0-9]{1,7}', params[k]):
                            fail(400, 'invalid_query', 'Ожидается положительный номер страницы/размер.')
                        params[k] = int(params[k])
                return self.json_response(200, self.server.store.progress(self.identity(), operation, **params))
            if path == '/api/trips/start':
                if method != 'POST':
                    fail(405, 'method_not_allowed', 'Используйте POST.')
                body = self.read_body()
                player_id = self.identity(allow_legacy_create=body == {})
                return self.json_response(200, self.server.store.mutate(player_id, path, body))
            if path == '/api/trips/current':
                if method != 'GET':
                    fail(405, 'method_not_allowed', 'Используйте GET.')
                return self.json_response(200, self.server.store.get(self.identity()))
            match = TRIP_PATH.fullmatch(path)
            if not match:
                fail(404, 'not_found', 'Маршрут не найден.')
            trip_id, suffix = match.groups()
            required_method = 'POST' if suffix in ('/actions', '/assignments', '/dialog/open', '/dialog/close', '/time', '/complete') else 'GET'
            if method != required_method:
                fail(405, 'method_not_allowed', f'Используйте {required_method}.')
            player_id = self.identity()
            if suffix in ('/actions', '/assignments', '/dialog/open', '/dialog/close', '/time', '/complete'):
                data = self.server.store.mutate(player_id, path, self.read_body(), trip_id)
            else:
                data = self.server.store.get(player_id, trip_id, report=suffix == '/report')
            self.json_response(200, data)
        except APIError as exc:
            self.json_response(exc.status, exc.data)
        except sqlite3.Error:
            self.log_error('Database temporarily unavailable')
            self.json_response(503, {'ok': False, 'api_version': 'v1', 'error': 'storage_unavailable', 'message': 'Хранилище недоступно. Повторите тот же request_id.'})

    def do_GET(self):
        path = urlsplit(self.path).path
        if path.startswith('/api/'):
            self.api('GET')
        elif path == '/favicon.ico':
            self.send_response(204)
            self.end_headers()
        else:
            super().do_GET()

    def do_POST(self):
        self.api('POST')

    def do_HEAD(self):
        if urlsplit(self.path).path.startswith('/api/'):
            self.send_response(405)
            self.end_headers()
        else:
            super().do_HEAD()

    def list_directory(self, path):
        self.send_error(404)
        return None


class Server(ThreadingHTTPServer):
    # The stdlib default queue of 5 rejects small simultaneous browser bursts
    # on macOS before a handler can return/replay the committed JSON response.
    request_queue_size = 32


def make_server(host='127.0.0.1', port=8765, db_path=None):
    store = Store(db_path or ROOT / 'backend/var/head-of-train.sqlite3')
    server = Server((host, port), partial(Handler, directory=str(ROOT / 'build/web')))
    server.store = store
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--db', type=Path, default=ROOT / 'backend/var/head-of-train.sqlite3')
    args = parser.parse_args()
    server = make_server(args.host, args.port, args.db)
    address = f'http://{args.host}:{server.server_port}'
    print(f'Game: {address}/', flush=True)
    print(f'Health: {address}/api/health', flush=True)
    print(f'Database: {args.db.resolve()}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
