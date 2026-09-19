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

logger = logging.getLogger(__name__)

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
    # Re-entrancy guard: ``dlg.exec()`` below re-enters the Qt event loop;
    # if another exception escapes while the fatal dialog is up we must not
    # stack a second modal on top of it.
    _in_hook = {"active": False}

    def _hook(exc_type, exc_value, exc_tb):
        detail = "".join(traceback.format_exception(exc_type, exc_value, exc_tb))
        logging.error("Uncaught exception:\n%s", detail)
        telemetry.record_error(
            exc_value,
            context={"hook": "sys.excepthook", "fatal": True},
        )
        if not _in_hook["active"]:
            _in_hook["active"] = True
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
                logger.debug("main.py:_hook best-effort step failed", exc_info=True)
            finally:
                _in_hook["active"] = False
        old_hook(exc_type, exc_value, exc_tb)

    sys.excepthook = _hook


def main() -> int:
    from src.infrastructure.telemetry import telemetry

    if "--gallery" in sys.argv:
        from src.widgets.ui.gallery import run_gallery

        return run_gallery()

    _install_excepthook()
    telemetry.start_session()
    start = time.perf_counter()
    app = QApplication(sys.argv)
    app.setApplicationName("Turna Course Editor")
    apply_theme(app)
    # Global event filter records every click and input commit to operations.log.
    from src.infrastructure.user_action_filter import UserActionFilter

    app.installEventFilter(UserActionFilter(app))
    # Wheel must never adjust spin boxes / combos on hover (global UX rule);
    # scrolling over them scrolls the enclosing page instead.
    from src.infrastructure.wheel_guard import install_wheel_guard

    install_wheel_guard(app)
    # Keep every dialog / sub-window inside the screen (small laptops, 150%
    # font scale); windows that fit keep their position untouched.
    from src.infrastructure.screen_fit import install_screen_clamp

    install_screen_clamp(app)
    window = MainWindow()
    window.show()
    startup_ms = (time.perf_counter() - start) * 1000
    telemetry.record_duration("app.startup", startup_ms)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
