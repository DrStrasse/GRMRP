#!/usr/bin/env python3
"""Точка входа gmodkit: работа с картами bsp/vmf и моделями mdl/smd.

    python3 tools/gmodkit.py bsp info maps/rp_city.bsp
    python3 tools/gmodkit.py mdl materials models/starless/atm.mdl
    python3 tools/gmodkit.py grm spawns maps/rp_city.bsp
    python3 tools/gmodkit.py selftest

Документация — WIKI.md, Часть V (глава «Архивный документ: docs/GMODKIT.md»).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gmodkit.cli import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main())
