"""Unit tests for AudioController."""
import unittest
from unittest.mock import MagicMock, patch
from PySide6.QtWidgets import QApplication, QDialog

from src.application.audio_controller import AudioController

app = QApplication.instance() or QApplication([])


class _FakeSignal:
    def __init__(self) -> None:
        self._callbacks: list = []

    def connect(self, callback) -> None:
        self._callbacks.append(callback)

    def emit(self, *args) -> None:
        for cb in self._callbacks:
            cb(*args)


class _InlineWorker:
    """Runs the target synchronously and emits the result immediately.

    The pre-TTS save runs on a worker in production (it used to freeze the
    GUI thread for the whole save chain). Tests run it inline so the
    assertions stay deterministic.
    """

    def __init__(self, target, *args, **kwargs):
        self.target = target
        self.args = args
        self.kwargs = kwargs
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()

    def start(self) -> None:
        try:
            result = self.target(*self.args, **self.kwargs)
        except Exception as exc:  # pragma: no cover - mirrors worker behaviour
            self.error_occurred.emit(str(exc))
            return
        self.result_ready.emit(result)

    def cancel(self) -> None:
        pass

    def isRunning(self) -> bool:
        return False

    def wait(self, _ms: int = 0) -> bool:
        return True


class FakeWindow:
    def __init__(self):
        self.course_dir = "fake/course/dir"
        self.adapter = MagicMock()
        self.adapter.save.return_value = MagicMock(ok=True)
        self._settings_obj = MagicMock()
        self._settings = MagicMock()
        self.job_tray = MagicMock()
        self.tree = MagicMock()
        self._generate_worker = None
        self._audio_save_worker = None
        self.undo_stack = MagicMock()
        self.statusBar = MagicMock()


class TestAudioController(unittest.TestCase):
    def setUp(self):
        self.controller = AudioController()
        self.win = FakeWindow()

    @patch("src.application.audio_controller.QMessageBox.warning")
    def test_warns_when_no_course(self, mock_warn):
        self.win.course_dir = None
        self.controller.handle_generate_audio(self.win)
        mock_warn.assert_called_once()
        self.win.adapter.save.assert_not_called()

    @patch("src.backend.generate_audio_client.sounds_dir_for")
    @patch("src.backend.generate_audio_client.preview_generation")
    @patch("src.dialogs.generate_audio_dialog.GenerateAudioDialog")
    @patch("src.application.ai_request_worker.AiRequestWorker", _InlineWorker)
    @patch("src.application.audio_controller.QMessageBox.warning")
    def test_warns_when_save_fails(self, mock_warn, mock_dlg_cls, mock_preview, mock_sounds):
        # #22: the save happens AFTER the user accepts the dialog now —
        # a failing save still cancels generation with the same warning.
        mock_dlg = MagicMock()
        mock_dlg.exec.return_value = QDialog.DialogCode.Accepted
        mock_dlg_cls.return_value = mock_dlg
        self.win.adapter.save.return_value = MagicMock(ok=False)
        self.controller.handle_generate_audio(self.win)
        mock_warn.assert_called_once()
        self.assertIsNone(self.win._generate_worker)

    @patch("src.backend.generate_audio_client.sounds_dir_for")
    @patch("src.backend.generate_audio_client.preview_generation")
    @patch("src.dialogs.generate_audio_dialog.GenerateAudioDialog")
    def test_dialog_rejected(self, mock_dlg_cls, mock_preview, mock_sounds):
        mock_dlg = MagicMock()
        mock_dlg.exec.return_value = QDialog.DialogCode.Rejected
        mock_dlg_cls.return_value = mock_dlg

        self.controller.handle_generate_audio(self.win)
        self.assertIsNone(self.win._generate_worker)
        # #22: merely opening the dialog no longer writes the course.
        self.win.adapter.save.assert_not_called()

    @patch("src.backend.generate_audio_client.sounds_dir_for")
    @patch("src.backend.generate_audio_client.preview_generation")
    @patch("src.dialogs.generate_audio_dialog.GenerateAudioDialog")
    @patch("src.application.ai_request_worker.AiRequestWorker", _InlineWorker)
    @patch("src.application.audio_worker.GenerateAudioWorker")
    @patch("src.application.audio_controller.QMessageBox.information")
    def test_spawns_worker_and_completes(
        self, mock_info, mock_worker_cls, mock_dlg_cls, mock_preview, mock_sounds
    ):
        mock_dlg = MagicMock()
        mock_dlg.exec.return_value = QDialog.DialogCode.Accepted
        mock_dlg.api_key.return_value = "fake-key"
        mock_dlg_cls.return_value = mock_dlg

        mock_worker = MagicMock()
        mock_worker_cls.return_value = mock_worker

        self.controller.handle_generate_audio(self.win)

        self.assertIs(self.win._generate_worker, mock_worker)
        mock_worker.start.assert_called_once()
        self.win.job_tray.start_job.assert_called_once_with("tts-generate", "生成听力音频…")


if __name__ == "__main__":
    unittest.main()
