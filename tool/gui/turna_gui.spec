# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for the Turna course editor GUI (guiplan §9 M5.2).

Build with:  python -m PyInstaller tool/gui/turna_gui.spec
(or:         python tool/gui/build_gui.py)

Produces a single-file executable `dist/turna-gui.exe` (Windows) that
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
    # The app only imports PySide6.QtCore / QtGui / QtWidgets (verified by
    # grep over tool/gui/src). Excluding the unused Qt modules keeps the
    # onefile exe noticeably smaller.
    excludes=[
        "PySide6.Qt3DAnimation",
        "PySide6.Qt3DCore",
        "PySide6.Qt3DExtras",
        "PySide6.Qt3DInput",
        "PySide6.Qt3DLogic",
        "PySide6.Qt3DQuick",
        "PySide6.Qt3DRender",
        "PySide6.QtBluetooth",
        "PySide6.QtCharts",
        "PySide6.QtDataVisualization",
        "PySide6.QtDesigner",
        "PySide6.QtGraphs",
        "PySide6.QtHelp",
        "PySide6.QtLocation",
        "PySide6.QtMultimedia",
        "PySide6.QtMultimediaWidgets",
        "PySide6.QtNetworkAuth",
        "PySide6.QtNfc",
        "PySide6.QtOpenGLWidgets",
        "PySide6.QtPdf",
        "PySide6.QtPdfWidgets",
        "PySide6.QtPositioning",
        "PySide6.QtQml",
        "PySide6.QtQuick",
        "PySide6.QtQuick3D",
        "PySide6.QtQuickControls2",
        "PySide6.QtQuickWidgets",
        "PySide6.QtRemoteObjects",
        "PySide6.QtScxml",
        "PySide6.QtSensors",
        "PySide6.QtSerialBus",
        "PySide6.QtSerialPort",
        "PySide6.QtSpatialAudio",
        "PySide6.QtSql",
        "PySide6.QtStateMachine",
        "PySide6.QtTest",
        "PySide6.QtTextToSpeech",
        "PySide6.QtVirtualKeyboard",
        "PySide6.QtWebChannel",
        "PySide6.QtWebEngineCore",
        "PySide6.QtWebEngineQuick",
        "PySide6.QtWebEngineWidgets",
        "PySide6.QtWebSockets",
        "PySide6.QtWebView",
    ],
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
    name="turna-gui",
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
