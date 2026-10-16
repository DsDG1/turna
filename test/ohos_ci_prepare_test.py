#!/usr/bin/env python3
"""Unit tests for tool/ohos_ci_prepare.py.

Run with:
    python -m unittest discover -s test -p "ohos_ci_prepare_test.py"
"""

from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

import sys

# Add project root to path so we can import the tool module.
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from ohos_ci_prepare import (  # type: ignore
    assert_no_signing,
    prep_unsigned,
    strip_signing,
)

# The committed shape of ohos/build-profile.json5 on the companion build
# machine: DevEco-generated signing material behind absolute Windows paths,
# a product that references it, then the machine-independent remainder.
# Credential-bearing material members are elided from the fixture on purpose
# (security scanning); the strip removes the whole block regardless of which
# members the material object carries.
SIGNED_PROFILE = """{
  app: {
    signingConfigs: [
      {
        name: 'default',
        type: 'HarmonyOS',
        material: {
          certpath: 'C:\\\\Users\\\\someone\\\\.ohos\\\\config\\\\debug.cer',
          keyAlias: 'debugKey',
          profile: 'C:\\\\Users\\\\someone\\\\.ohos\\\\config\\\\debug.p7b',
          signAlg: 'SHA256withECDSA',
          storeFile: 'C:\\\\Users\\\\someone\\\\.ohos\\\\config\\\\debug.p12',
        },
      },
    ],
    products: [
      {
        name: 'default',
        signingConfig: 'default',
        compatibleSdkVersion: '5.1.0(18)',
        runtimeOS: 'HarmonyOS',
      },
    ],
    buildModeSet: [
      {
        name: 'debug',
      },
    ],
  },
  modules: [
    {
      name: 'entry',
      srcPath: './entry',
    },
  ],
}"""


class StripSigningTest(unittest.TestCase):
    def test_removes_signing_block_and_product_reference(self) -> None:
        stripped = strip_signing(SIGNED_PROFILE)
        assert_no_signing(stripped)
        self.assertNotIn("signingConfigs", stripped)
        self.assertNotIn("signingConfig", stripped)
        self.assertNotIn("C:", stripped)
        # The machine-independent remainder must survive untouched.
        self.assertIn("compatibleSdkVersion: '5.1.0(18)'", stripped)
        self.assertIn("name: 'entry'", stripped)
        self.assertIn("buildModeSet", stripped)

    def test_absent_key_is_the_gate_shape_not_empty_list(self) -> None:
        # The fork's checkOhosSignedInfo tool-exits on an *empty* signingConfigs
        # list but accepts an absent key, so the strip must delete the member,
        # not leave `signingConfigs: []` behind.
        stripped = strip_signing(SIGNED_PROFILE)
        self.assertNotIn("signingConfigs: []", stripped)
        self.assertNotIn("signingConfigs:", stripped)

    def test_idempotent(self) -> None:
        once = strip_signing(SIGNED_PROFILE)
        self.assertEqual(once, strip_signing(once))

    def test_already_clean_profile_passes_through(self) -> None:
        clean = strip_signing(SIGNED_PROFILE)
        self.assertEqual(clean, strip_signing(clean))

    def test_unbalanced_input_is_rejected_loudly(self) -> None:
        # If a future DevEco ever emits brackets inside quoted material
        # values, the naive bracket matcher must fail, not corrupt the file.
        broken = SIGNED_PROFILE.replace("signAlg: 'SHA256", "signAlg: 'SHA256[with")
        with self.assertRaises(ValueError):
            strip_signing(broken)


class PrepUnsignedTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="turna_ohos_ci_prep_"))
        ohos = self.root / "ohos"
        (ohos / "entry").mkdir(parents=True)
        (ohos / "build-profile.json5").write_text(SIGNED_PROFILE, encoding="utf-8")
        # Machine-local state: locks resolved against a local fork checkout,
        # env-derived local.properties, dependency trees, stale outputs.
        (ohos / "package-lock.json").write_text("{}", encoding="utf-8")
        (ohos / "local.properties").write_text("hwsdk.dir=D:\\\\DevEco Studio\\\\sdk\n", encoding="utf-8")
        (ohos / "entry" / "oh-package-lock.json5").write_text("{}", encoding="utf-8")
        (ohos / "node_modules").mkdir()
        (ohos / "node_modules" / "flutter-hvigor-plugin").mkdir()
        (ohos / "oh_modules").mkdir()
        (ohos / "entry" / "oh_modules").mkdir()
        (ohos / "build").mkdir()
        (ohos / "entry" / "build").mkdir()
        # Committed engine libs must never be pruned (ADR 0050 §6 步 1).
        libs = ohos / "entry" / "libs" / "arm64-v8a"
        libs.mkdir(parents=True)
        (libs / "libturna_anki.so").write_bytes(b"\x7fELF-fake")

    def tearDown(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)

    def test_prunes_machine_local_state_and_strips_signing(self) -> None:
        removed = prep_unsigned(self.root)
        self.assertIn("ohos/package-lock.json", removed)
        self.assertIn("ohos/entry/oh-package-lock.json5", removed)
        self.assertIn("ohos/local.properties", removed)
        self.assertIn("ohos/node_modules/", removed)
        self.assertIn("ohos/oh_modules/", removed)
        self.assertIn("ohos/entry/oh_modules/", removed)
        self.assertIn("ohos/build/", removed)
        self.assertIn("ohos/entry/build/", removed)
        self.assertFalse((self.root / "ohos" / "node_modules").exists())
        self.assertFalse((self.root / "ohos" / "entry" / "oh-package-lock.json5").exists())

        profile = (self.root / "ohos" / "build-profile.json5").read_text(encoding="utf-8")
        assert_no_signing(profile)
        self.assertIn("compatibleSdkVersion: '5.1.0(18)'", profile)

        # Committed engine libs survive the prune.
        so = self.root / "ohos" / "entry" / "libs" / "arm64-v8a" / "libturna_anki.so"
        self.assertTrue(so.is_file())

    def test_second_run_is_a_no_op(self) -> None:
        prep_unsigned(self.root)
        self.assertEqual([], prep_unsigned(self.root))


if __name__ == "__main__":
    unittest.main()
