# -*- coding: utf-8 -*-
"""Терминал Комитета — десктопное приложение.

Запуск:
    python main.py                # нативное окно (или браузер)
    python main.py --browser      # принудительно открыть в браузере
    python main.py --no-window    # только сервер (выводит URL)
    python main.py --port 9000    # фиксированный порт
    python main.py --data ПУТЬ.db # свой файл базы данных
"""
import argparse
import sys
import threading
import webbrowser

from db import DB
from server import start


def open_native_window(url):
    """Открыть нативное окно через pywebview, если он установлен."""
    try:
        import webview  # noqa
    except Exception:
        return False
    try:
        window = webview.create_window(
            "Терминал Комитета",
            url,
            width=1120,
            height=760,
            min_size=(840, 560),
        )
        webview.start()
        return True
    except Exception as e:
        print("[window] pywebview не запустился:", e)
        return False


def main():
    ap = argparse.ArgumentParser(description="Терминал Комитета")
    ap.add_argument("--browser", action="store_true", help="открыть в браузере")
    ap.add_argument("--no-window", action="store_true", help="только сервер")
    ap.add_argument("--port", type=int, default=None)
    ap.add_argument("--data", default=None, help="путь к файлу БД")
    args = ap.parse_args()

    db = DB(args.data)
    print("[db] база данных:", db.path)

    srv, port = start(db, args.port)
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()

    url = "http://127.0.0.1:%d/" % port
    print("[server] запущен:", url)
    print("[server] Ctrl+C для выхода")

    if args.no_window:
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            pass
        finally:
            srv.shutdown()
            db.close()
        return

    opened = False
    if not args.browser:
        opened = open_native_window(url)

    if not opened:
        print("[window] открываю в браузере...")
        webbrowser.open(url)
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            pass
        finally:
            srv.shutdown()
            db.close()


if __name__ == "__main__":
    main()
