"""Serve the bundled Pocket City map locally, including its gzip-compressed vector tiles."""
from argparse import ArgumentParser
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class MapHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.pbf': 'application/x-protobuf'}

    def end_headers(self):
        if urlsplit(self.path).path.endswith('.pbf'):
            tile = Path(self.translate_path(self.path))
            if tile.is_file():
                with tile.open('rb') as payload:
                    if payload.read(2) == b'\x1f\x8b':
                        self.send_header('Content-Encoding', 'gzip')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


if __name__ == '__main__':
    parser = ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=42418)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with ThreadingHTTPServer(('127.0.0.1', args.port), partial(MapHandler, directory=str(root))) as server:
        server.serve_forever()
