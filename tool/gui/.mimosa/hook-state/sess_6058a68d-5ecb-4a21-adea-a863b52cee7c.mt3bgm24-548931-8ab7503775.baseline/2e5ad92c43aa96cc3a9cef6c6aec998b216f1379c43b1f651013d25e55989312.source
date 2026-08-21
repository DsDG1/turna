"""Entry point for the Turna GUI course editor."""
from __future__ import annotations

import logging
import sys
import time
import traceback
from pathlib import Path

_GUI_DIR = Path(__file__).resolve().parent.parent
if str(_GUI_DIR) not in sys.path:
    sys.path.insert(0, str(_GUI_DIR))

from PySide6.QtWidgets import QApplication

from src.app import MainWindow
from src.application.settings import app_data_dir
from src.theme import apply_theme

_LOG_DIR = app_data_dir()
_LOG_DIR.mkdir(parents=True, exist_ok=True)
_LOG_FILE = _LOG_DIR / "app.log"

logging.basicConfig(
    filename=_LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    encoding="utf-8",
)


def _install_excepthook() -> None:
    """Log unhandled exceptions, record telemetry, and offer AI analysis."""
    from src.infrastructure.telemetry import telemetry

    old_hook = sys.excepthook

    def _hook(exc_type, exc_value, exc_tb):
        detail = "".join(traceback.format_exception(exc_type, exc_value, exc_tb))
        logging.error("Uncaught exception:\n%s", detail)
        telemetry.record_error(
            exc_value,
            context={"hook": "sys.excepthook", "fatal": True},
        )
        try:
            from src.dialogs.ai_error_analyzer import offer_ai_analysis
            if offer_ai_analysis(
                None, "未捕获的错误", f"程序遇到错误：{exc_value}",
                informative_text=f"详细信息已写入 {_LOG_FILE}", default_to_analyze=True,
            ):
                from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog

                dlg = AiErrorAnalyzerDialog(
                    detail,
                    context={"hook": "sys.excepthook", "fatal": True},
                )
                dlg.exec()
        except Exception:
            pass
        old_hook(exc_type, exc_value, exc_tb)

    sys.excepthook = _hook


def main() -> int:
    from src.infrastructure.telemetry import telemetry

    _install_excepthook()
    telemetry.start_session()
    start = time.perf_counter()
    app = QApplication(sys.argv)
    app.setApplicationName("Turna Course Editor")
    apply_theme(app)
    # Global event filter records every click and input commit to operations.log.
    from src.infrastructure.user_action_filter import UserActionFilter

    app.installEventFilter(UserActionFilter(app))
    window = MainWindow()
    window.show()
    startup_ms = (time.perf_counter() - start) * 1000
    telemetry.record_duration("app.startup", startup_ms)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
