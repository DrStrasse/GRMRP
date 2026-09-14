# -*- coding: utf-8 -*-
"""Встроенный HTTP-сервер + REST API для «Терминала Комитета»."""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from db import DB, TABLES

INDEX_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html")


def resource_path(name):
    """Корректный путь и при запуске из PyInstaller (sys._MEIPASS)."""
    if getattr(sys, "frozen", False):
        base = getattr(sys, "_MEIPASS", os.path.dirname(sys.executable))
        return os.path.join(base, name)
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), name)


class Handler(BaseHTTPRequestHandler):
    db = None  # подставляется при старте

    def log_message(self, *a):  # тихий режим
        pass

    # --- helpers ---
    def _send(self, code, body=None, ctype="application/json; charset=utf-8"):
        if body is None:
            data = b""
        elif isinstance(body, (dict, list)):
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        elif isinstance(body, str):
            data = body.encode("utf-8")
        else:
            data = body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _json_body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if not n:
            return {}
        raw = self.rfile.read(n)
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    # --- routing ---
    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/" or p == "/index.html":
            try:
                with open(resource_path("index.html"), "rb") as f:
                    return self._send(200, f.read(), "text/html; charset=utf-8")
            except OSError:
                return self._send(500, "index.html не найден")
        if p == "/api/db":
            return self._send(200, self.db.full())
        if p == "/api/export":
            data = json.dumps(self.db.full(), ensure_ascii=False, indent=2)
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header(
                "Content-Disposition",
                "attachment; filename=komitet_db.json",
            )
            self.send_header("Content-Length", str(len(data.encode("utf-8"))))
            self.end_headers()
            self.wfile.write(data.encode("utf-8"))
            return
        self._send(404, {"error": "not found"})

    def do_POST(self):
        p = self.path.split("?")[0]
        body = self._json_body()
        if p == "/api/wipe":
            self.db.wipe()
            return self._send(200, {"ok": True})
        if p == "/api/log":
            self.db.add_log(body.get("msg", ""))
            return self._send(200, {"ok": True})
        if p == "/api/import":
            try:
                self.db.replace(body)
                return self._send(200, {"ok": True})
            except Exception as e:
                return self._send(400, {"error": str(e)})
        # POST /api/{table}  -> вставка
        tab = p.strip("/").split("/")
        if len(tab) == 2 and tab[0] == "api" and tab[1] in TABLES:
            rec = self.db.insert(tab[1], body)
            return self._send(200, rec)
        self._send(404, {"error": "not found"})

    def do_PUT(self):
        p = self.path.split("?")[0]
        parts = p.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "api" and parts[1] in TABLES:
            rec = self.db.update(parts[1], parts[2], self._json_body())
            if rec is None:
                return self._send(404, {"error": "not found"})
            return self._send(200, rec)
        self._send(404, {"error": "not found"})

    def do_DELETE(self):
        p = self.path.split("?")[0]
        parts = p.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "api" and parts[1] in TABLES:
            ok = self.db.delete(parts[1], parts[2])
            return self._send(200, {"ok": ok})
        self._send(404, {"error": "not found"})


def find_port(start=8765, tries=20):
    for port in range(start, start + tries):
        try:
            srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
            return srv, port
        except OSError:
            continue
    raise RuntimeError("не удалось найти свободный порт")


def start(db, port=None):
    if port:
        srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    else:
        srv, port = find_port()
    Handler.db = db
    return srv, port
