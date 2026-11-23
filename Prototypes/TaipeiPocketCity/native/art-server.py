"""Serve only this prototype's artwork inputs on an ephemeral loopback port."""

from argparse import ArgumentParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import re
import shutil
import threading
from urllib.parse import unquote, urlsplit

parser = ArgumentParser()
parser.add_argument("--root", type=Path, required=True)
parser.add_argument("--port", type=int, default=0)
parser.add_argument("--ready", type=Path, required=True)
parser.add_argument("--parent", type=int, required=True)
args = parser.parse_args()
root = args.root.resolve()
assets = {
    "/native/art-host.html": "text/html; charset=utf-8",
    "/native/tile-bridge.js": "text/javascript; charset=utf-8",
    "/apple-pocket-art.js": "text/javascript; charset=utf-8",
    "/fuxing-fronts.js": "text/javascript; charset=utf-8",
    "/fuxing-block.js": "text/javascript; charset=utf-8",
    "/data/city170/index.json": "application/json",
}
packs = re.compile(r"/data/(?:city170|city170-frontages)/p\d+_\d+\.json(?:\.gz)?\Z")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_HEAD(self):
        self.send_asset(False)

    def do_GET(self):
        self.send_asset(True)

    def send_asset(self, body):
        if self.headers.get("Host") != f"127.0.0.1:{self.server.server_port}":
            self.send_error(403)
            return
        name = unquote(urlsplit(self.path).path)
        media = assets.get(name)
        if media is None and packs.fullmatch(name):
            media = "application/gzip" if name.endswith(".gz") else "application/json"
        if media is None:
            self.send_error(404)
            return
        path = (root / name.lstrip("/")).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            self.send_error(404)
            return
        try:
            with path.open("rb") as source:
                self.send_response(200)
                self.send_header("Content-Type", media)
                self.send_header("Content-Length", str(os.fstat(source.fileno()).st_size))
                self.send_header("X-Content-Type-Options", "nosniff")
                self.send_header("Cross-Origin-Resource-Policy", "same-origin")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                if body:
                    shutil.copyfileobj(source, self.wfile)
        except (BrokenPipeError, ConnectionResetError):
            pass


try:
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
except OSError:
    if args.port == 0:
        raise
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)


def watch_parent():
    wake = threading.Event()
    while os.getppid() == args.parent:
        wake.wait(1)
    server.shutdown()


with server:
    args.ready.write_text(str(server.server_port))
    threading.Thread(target=watch_parent, daemon=True).start()
    server.serve_forever()
