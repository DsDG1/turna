"""Entry point for the Varnamala GUI course editor."""
from __future__ import annotations

import sys
from pathlib import Path

_GUI_DIR = Path(__file__).resolve().parent.parent
if str(_GUI_DIR) not in sys.path:
    sys.path.insert(0, str(_GUI_DIR))

from PySide6.QtWidgets import QApplication

from src.app import MainWindow
from src.theme import apply_theme


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("Varnamala Course Editor")
    apply_theme(app)
    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())