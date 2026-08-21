"""Tests for credential_store: keyring abstraction with QSettings fallback."""
from __future__ import annotations

import unittest
from unittest.mock import patch, MagicMock

from PySide6.QtCore import QSettings


class CredentialStoreTokenTest(unittest.TestCase):
    def setUp(self) -> None:
        # Use in-memory QSettings for test isolation.
        QSettings.setDefaultFormat(QSettings.Format.IniFormat)
        QSettings.setPath(QSettings.Format.IniFormat, QSettings.Scope.UserScope, "/tmp/opencode/test-creds")

    def test_get_returns_none_when_not_set(self) -> None:
        from src.backend import credential_store
        with patch.object(credential_store, "_keyring_available", return_value=False):
            self.assertIsNone(credential_store.get_git_token("https://github.com/x/y.git"))

    def test_set_and_get_roundtrip_fallback(self) -> None:
        from src.backend import credential_store
        with patch.object(credential_store, "_keyring_available", return_value=False):
            credential_store.set_git_token("https://github.com/x/y.git", "secret123")
            self.assertEqual(
                credential_store.get_git_token("https://github.com/x/y.git"),
                "secret123",
            )

    def test_delete_returns_true_when_existed(self) -> None:
        from src.backend import credential_store
        with patch.object(credential_store, "_keyring_available", return_value=False):
            url = "https://github.com/x/z.git"
            credential_store.set_git_token(url, "tok")
            self.assertTrue(credential_store.delete_git_token(url))
            self.assertIsNone(credential_store.get_git_token(url))

    def test_delete_returns_false_when_not_set(self) -> None:
        from src.backend import credential_store
        with patch.object(credential_store, "_keyring_available", return_value=False):
            self.assertFalse(credential_store.delete_git_token("https://gitlab.com/none.git"))

    def test_account_for_url_extracts_host(self) -> None:
        from src.backend.credential_store import _account_for_url
        self.assertEqual(_account_for_url("https://github.com/x/y.git"), "github.com")
        self.assertEqual(_account_for_url("https://gitlab.com/a/b"), "gitlab.com")
        self.assertEqual(_account_for_url(""), "default")

    def test_keyring_path_uses_keyring_when_available(self) -> None:
        from src.backend import credential_store
        mock_keyring = MagicMock()
        mock_keyring.get_password.return_value = "keyring-token"
        mock_keyring.set_password = MagicMock()
        mock_keyring.delete_password = MagicMock()
        with patch.dict("sys.modules", {"keyring": mock_keyring}):
            with patch.object(credential_store, "_keyring_available", return_value=True):
                credential_store.set_git_token("https://github.com/x/y.git", "keyring-token")
                mock_keyring.set_password.assert_called_once()
                self.assertEqual(
                    credential_store.get_git_token("https://github.com/x/y.git"),
                    "keyring-token",
                )


class CredentialStoreSshKeyTest(unittest.TestCase):
    def setUp(self) -> None:
        QSettings.setDefaultFormat(QSettings.Format.IniFormat)
        QSettings.setPath(QSettings.Format.IniFormat, QSettings.Scope.UserScope, "/tmp/opencode/test-creds-ssh")

    def test_ssh_key_roundtrip(self) -> None:
        from src.backend import credential_store
        credential_store.set_ssh_key_path("/home/user/.ssh/id_ed25519")
        self.assertEqual(credential_store.get_ssh_key_path(), "/home/user/.ssh/id_ed25519")

    def test_ssh_key_default_empty(self) -> None:
        from src.backend import credential_store
        credential_store.set_ssh_key_path("")
        self.assertEqual(credential_store.get_ssh_key_path(), "")


class KeyringStatusTest(unittest.TestCase):
    def test_returns_dict_with_keys(self) -> None:
        from src.backend import credential_store
        with patch.object(credential_store, "_keyring_available", return_value=False):
            status = credential_store.keyring_status()
            self.assertIn("available", status)
            self.assertIn("backend", status)
            self.assertIn("service", status)
            self.assertFalse(status["available"])


if __name__ == "__main__":
    unittest.main()
