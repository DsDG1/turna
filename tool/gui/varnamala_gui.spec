# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for the Varnamala course editor GUI (guiplan §9 M5.2).

Build with:  python -m PyInstaller tool/gui/varnamala_gui.spec
(or:         python tool/gui/build_gui.py)

Produces a single-file executable `dist/varnamala-gui.exe` (Windows) that
launches the Qt course editor. The editor opens any course directory chosen by
the teacher, so course JSON is NOT bundled.

Known limitation (verify on host): `course_cli.SOUNDS_DIR` is the relative path
`assets/sounds`, used only by the audio-manifest publish step. In the packaged
exe this path resolves against CWD, so audio-manifest status checks may report
all assets as missing unless run from the repo root. Core editing / validate /
lint / version-bump do not depend on it.
"""

from pathlib import Path

ROOT = Path(SPECPATH).resolve().parent.parent  # repo root
GUI_DIR = ROOT / "tool" / "gui"
TOOL_DIR = ROOT / "tool"

block_cipher = None

a = Analysis(
    [str(GUI_DIR / "src" / "main.py")],
    pathex=[str(GUI_DIR), str(TOOL_DIR)],
    binaries=[],
    datas=[],
    hiddenimports=[
        "course_cli",
        "src.app",
        "src.backend.course_adapter",
        "src.backend.lesson_content",
        "src.dialogs.new_lesson_dialog",
        "src.teacher.linear_flow",
        "src.teacher.question_cards",
        "src.teacher.template_editors",
        "src.widgets.course_tree",
        "src.widgets.detail_panel",
        "src.widgets.interaction_forms",
        "src.widgets.lesson_editor",
        "src.widgets.metadata_form",
        "src.widgets.publish_dialog",
        "src.widgets.resource_editor",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="varnamala-gui",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
