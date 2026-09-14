# -*- coding: utf-8 -*-
"""Слой базы данных «Терминала Комитета» (SQLite)."""
import os
import sqlite3
import time
import uuid

# --- Схема таблиц (зеркало JS-схемы в index.html) ---
TABLES = {
    "dossier": {
        "label": "Досье на игрока",
        "columns": ["nick", "type", "cat", "status", "notes"],
    },
    "reports": {
        "label": "Рапорт",
        "columns": ["topic", "source", "cat", "status", "body"],
    },
    "agents": {
        "label": "Агент",
        "columns": ["nick", "role", "clear", "status", "notes"],
    },
}

COLS_DEF = {
    "dossier": (
        "id TEXT PRIMARY KEY, nick TEXT, type TEXT, cat TEXT, "
        "status TEXT, notes TEXT, updated TEXT"
    ),
    "reports": (
        "id TEXT PRIMARY KEY, topic TEXT, source TEXT, cat TEXT, "
        "status TEXT, body TEXT, updated TEXT"
    ),
    "agents": (
        "id TEXT PRIMARY KEY, nick TEXT, role TEXT, clear TEXT, "
        "status TEXT, notes TEXT, updated TEXT"
    ),
}

LOG_DEF = "id TEXT PRIMARY KEY, t TEXT, msg TEXT"


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime())


def _uid():
    return uuid.uuid4().hex[:12]


def data_dir():
    """Каталог хранения данных (общий для всех запусков)."""
    if os.name == "nt":
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
        d = os.path.join(base, "Komitet")
    else:
        base = os.environ.get("XDG_DATA_HOME") or os.path.join(
            os.path.expanduser("~"), ".local", "share"
        )
        d = os.path.join(base, "komitet")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        d = os.path.expanduser("~")
    return d


class DB:
    def __init__(self, path=None):
        self.path = path or os.path.join(data_dir(), "komitet.db")
        self.conn = sqlite3.connect(self.path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self._create()
        self._seed_if_empty()

    # --- создание ---
    def _create(self):
        cur = self.conn.cursor()
        for name, ddl in COLS_DEF.items():
            cur.execute("CREATE TABLE IF NOT EXISTS %s (%s)" % (name, ddl))
        cur.execute("CREATE TABLE IF NOT EXISTS log (%s)" % LOG_DEF)
        self.conn.commit()

    def _seed_if_empty(self):
        cur = self.conn.cursor()
        cur.execute("SELECT COUNT(*) FROM dossier")
        n = cur.fetchone()[0]
        if n:
            return
        self._seed()

    def _seed(self):
        self.insert("dossier", {
            "nick": "Steve_77", "type": "Наблюдатель", "cat": "B",
            "status": "Наблюдение",
            "notes": "Замечен у ворот цитадели. Молчит, но фиксирует перемещения патрулей.",
        })
        self.insert("dossier", {
            "nick": "xX_Grief_Xx", "type": "Враждебный", "cat": "E",
            "status": "Нейтрализован",
            "notes": "Попытка саботажа 12.09. Передан наверх. Не отвечать на провокации.",
        })
        self.insert("dossier", {
            "nick": "Bookkeeper", "type": "Прагматик", "cat": "C",
            "status": "Активен",
            "notes": "Ищет выгоду. Возможен источник по сделкам торговой гильдии.",
        })
        self.insert("reports", {
            "topic": "Слух о мятеже", "source": "Аноним", "cat": "D",
            "status": "Новый",
            "body": "Непроверяемое сообщение о готовящемся выступлении. Требует перекрёстной проверки.",
        })
        self.insert("reports", {
            "topic": "Сделка с чужими", "source": "Bookkeeper", "cat": "C",
            "status": "В работе",
            "body": "Один источник, доказательств нет. Ожидание второго независимого подтверждения.",
        })
        self.insert("agents", {
            "nick": "Agent_13", "role": "Интервьюер", "clear": "B",
            "status": "Активен",
            "notes": "Специализация — допросы. Склонен к излишнему давлению.",
        })
        self.insert("agents", {
            "nick": "Agent_07", "role": "Аналитик", "clear": "A",
            "status": "Активен",
            "notes": "Работа с донесениями категории B и выше.",
        })
        self.insert("agents", {
            "nick": "Agent_21", "role": "Исполнитель", "clear": "C",
            "status": "Отстранён",
            "notes": "Отстранён до разбирательства.",
        })
        self.add_log("Система инициализирована")

    # --- CRUD ---
    def list(self, table):
        cur = self.conn.cursor()
        cur.execute("SELECT * FROM %s ORDER BY updated DESC" % table)
        return [dict(r) for r in cur.fetchall()]

    def get(self, table, rid):
        cur = self.conn.cursor()
        cur.execute("SELECT * FROM %s WHERE id=?" % table, (rid,))
        r = cur.fetchone()
        return dict(r) if r else None

    def insert(self, table, data):
        cols = TABLES[table]["columns"]
        rid = _uid()
        values = {"id": rid, "updated": _now()}
        for c in cols:
            values[c] = (data.get(c) or "").strip()
        cur = self.conn.cursor()
        keys = list(values.keys())
        cur.execute(
            "INSERT INTO %s (%s) VALUES (%s)"
            % (table, ",".join(keys), ",".join("?" * len(keys))),
            [values[k] for k in keys],
        )
        self.conn.commit()
        return self.get(table, rid)

    def update(self, table, rid, data):
        if self.get(table, rid) is None:
            return None
        cols = TABLES[table]["columns"]
        sets = []
        params = []
        for c in cols:
            sets.append("%s=?" % c)
            params.append((data.get(c) or "").strip())
        sets.append("updated=?")
        params.append(_now())
        params.append(rid)
        cur = self.conn.cursor()
        cur.execute(
            "UPDATE %s SET %s WHERE id=?" % (table, ",".join(sets)), params
        )
        self.conn.commit()
        return self.get(table, rid)

    def delete(self, table, rid):
        cur = self.conn.cursor()
        cur.execute("DELETE FROM %s WHERE id=?" % table, (rid,))
        self.conn.commit()
        return cur.rowcount > 0

    # --- журнал ---
    def add_log(self, msg):
        cur = self.conn.cursor()
        cur.execute(
            "INSERT INTO log (id,t,msg) VALUES (?,?,?)",
            (_uid(), _now(), msg),
        )
        # ограничение размера журнала
        cur.execute(
            "DELETE FROM log WHERE id NOT IN "
            "(SELECT id FROM log ORDER BY t DESC LIMIT 500)"
        )
        self.conn.commit()

    def list_log(self, limit=300):
        cur = self.conn.cursor()
        cur.execute("SELECT * FROM log ORDER BY t DESC LIMIT ?", (limit,))
        return [dict(r) for r in cur.fetchall()]

    # --- целиком (для экспорта/импорта/отдачи) ---
    def full(self):
        return {
            "dossier": self.list("dossier"),
            "reports": self.list("reports"),
            "agents": self.list("agents"),
            "log": self.list_log(500),
        }

    def replace(self, data):
        """Замена всей базы (импорт)."""
        for name in TABLES:
            self.conn.execute("DELETE FROM %s" % name)
        self.conn.execute("DELETE FROM log")
        self.conn.commit()
        for name in ("dossier", "reports", "agents"):
            for rec in data.get(name, []):
                if isinstance(rec, dict) and rec.get("id"):
                    self._insert_raw(name, rec)
        for entry in reversed(data.get("log", [])):
            if isinstance(entry, dict) and entry.get("msg"):
                self._insert_log_raw(entry)
        self.add_log("Импорт базы данных")

    def _insert_raw(self, table, rec):
        cols = ["id"] + TABLES[table]["columns"] + ["updated"]
        params = [
            rec.get("id", _uid()),
        ]
        for c in TABLES[table]["columns"]:
            params.append(rec.get(c) or "")
        params.append(rec.get("updated") or _now())
        cur = self.conn.cursor()
        cur.execute(
            "INSERT OR REPLACE INTO %s (%s) VALUES (%s)"
            % (table, ",".join(cols), ",".join("?" * len(cols))),
            params,
        )
        self.conn.commit()

    def _insert_log_raw(self, entry):
        cur = self.conn.cursor()
        cur.execute(
            "INSERT OR REPLACE INTO log (id,t,msg) VALUES (?,?,?)",
            (entry.get("id", _uid()), entry.get("t") or _now(), entry.get("msg", "")),
        )
        self.conn.commit()

    def wipe(self):
        for name in TABLES:
            self.conn.execute("DELETE FROM %s" % name)
        self.conn.execute("DELETE FROM log")
        self.conn.commit()
        self.add_log("База данных стёрта")

    def close(self):
        try:
            self.conn.close()
        except Exception:
            pass
