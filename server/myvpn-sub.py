#!/usr/bin/env python3
"""myVPN 订阅静态服务：只对外提供 /<token>/myvpn.yaml 这一个文件，其余路径一律 404。

用法: python3 myvpn-sub.py <token> <订阅文件路径> [端口，默认 8443]
由 systemd 单元 myvpn-sub.service 拉起；本地部署/更新脚本见 server/deploy-sub.sh。
"""
import http.server
import pathlib
import sys
from urllib.parse import urlsplit

TOKEN = sys.argv[1]
FILE = pathlib.Path(sys.argv[2])
PORT = int(sys.argv[3]) if len(sys.argv) > 3 else 8443
ROUTE = f"/{TOKEN}/myvpn.yaml"


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "myvpn-sub"

    def _reply(self, code: int, body: bytes = b"", ctype: str = "text/plain; charset=utf-8") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self) -> None:
        if urlsplit(self.path).path == ROUTE:
            try:
                body = FILE.read_bytes()
            except OSError:
                self._reply(500, b"subscription file missing\n")
                return
            self._reply(200, body, "application/yaml; charset=utf-8")
        else:
            self._reply(404, b"not found\n")

    do_HEAD = do_GET


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
