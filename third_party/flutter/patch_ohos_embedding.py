"""Patch the OHOS Flutter engine embedding so it compiles against API 26.

`@ohos/flutter_ohos` (shipped as `flutter_embedding_<mode>.har`) targets an API 26
SDK that exposes the full autoFill surface: `AutoFillType`, `ViewData`,
`FillRequest`, `AutoFillCallback`, `FillFailureResult`, `AutoFillTriggerType`,
`requestAutoFill` and `SaveRequest`. The HarmonyOS SDK available here
(26.0.0.23) ships `autoFillManager` reduced to `AutoSaveCallback` plus a
two-argument `requestAutoSave(context, callback)`, so the file does not compile:

    10505001 ArkTS Compiler Error
    Namespace 'autoFillManager' has no exported member 'AutoFillType'.

Turna renders no autofill form, so the autofill side is stubbed to a local no-op
that reports failure, and the autosave side is re-pointed at the surviving
signature. Text input, the IME and the platform channel are untouched.

The HAR is a gzipped tar holding *uncompiled* ArkTS sources, so nothing has to be
compiled here: the project's own hvigor pass compiles the patched file. The
ArkTS compile passing is the proof the patch took effect.

Idempotent: a package already carrying the shim is left alone.

Usage:
    python third_party/flutter/patch_ohos_embedding.py --check --sdk <ohos flutter sdk>
    python third_party/flutter/patch_ohos_embedding.py --apply --sdk <ohos flutter sdk>
"""

from __future__ import annotations

import argparse
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile

RELATIVE = "src/main/ets/plugin/editing/OhosAutoFillHelper.ets"
MARKER = "Turna companion-build shim"

# Members API 26 no longer exports. Each maps to the local stand-in introduced
# by the shim; the two surviving members (AutoSaveCallback, requestAutoSave) are
# deliberately absent from this table.
REPLACEMENTS = [
    ("autoFillType: autoFillManager.AutoFillType;", "autoFillType: OhosSdkAutoFillType;"),
    (
        "private static toSdkAutoFillType(value: number): autoFillManager.AutoFillType {",
        "private static toSdkAutoFillType(value: number): OhosSdkAutoFillType {",
    ),
    ("    return value as autoFillManager.AutoFillType;", "    return value as OhosSdkAutoFillType;"),
    (
        "private static toManagerViewData(viewData: OhosViewData): autoFillManager.ViewData {",
        "private static toManagerViewData(viewData: OhosViewData): OhosSdkViewData {",
    ),
    ("    return managerViewData as autoFillManager.ViewData;", "    return managerViewData as OhosSdkViewData;"),
    (
        "static parseFillResult(viewData: autoFillManager.ViewData): Map<number, string> {",
        "static parseFillResult(viewData: OhosSdkViewData): Map<number, string> {",
    ),
    (
        "triggerType: AUTOFILL_TRIGGER_AUTO_REQUEST as autoFillManager.AutoFillTriggerType,",
        "triggerType: AUTOFILL_TRIGGER_AUTO_REQUEST as OhosSdkAutoFillTriggerType,",
    ),
    ("    } as autoFillManager.FillRequest;", "    } as OhosSdkFillRequest;"),
    ("    const callback: autoFillManager.AutoFillCallback = {", "    const callback: OhosSdkAutoFillCallback = {"),
    (
        "      onSuccess: (filledViewData: autoFillManager.ViewData): void => {",
        "      onSuccess: (filledViewData: OhosSdkViewData): void => {",
    ),
    (
        "      onFailure: (result: autoFillManager.FillFailureResult): void => {",
        "      onFailure: (result: OhosSdkFillFailureResult): void => {",
    ),
    (
        "      autoFillManager.requestAutoFill(uiContext, fillRequest, callback);",
        "      requestOhosAutoFill(uiContext, fillRequest, callback);",
    ),
    ("    const saveRequest: autoFillManager.SaveRequest = {", "    const saveRequest: OhosSdkSaveRequest = {"),
    (
        "      autoFillManager.requestAutoSave(uiContext, saveRequest, napiCallback);",
        "      autoFillManager.requestAutoSave(uiContext, napiCallback);",
    ),
]

SHIM_ANCHOR = "export const AUTOFILL_SUPPORT_API = 26;"

SHIM = """

/*
 * Turna companion-build shim (ADR 0047).
 *
 * This embedder targets an API 26 SDK exposing the full autoFill surface
 * (AutoFillType / ViewData / FillRequest / AutoFillCallback / FillFailureResult
 * / AutoFillTriggerType / requestAutoFill / SaveRequest). The only HarmonyOS SDK
 * available for the companion build ships autoFillManager reduced to
 * AutoSaveCallback plus a two-argument requestAutoSave, so the file does not
 * compile as shipped. Turna renders no autofill form, so the autofill side is
 * stubbed to a local no-op that reports failure, and the autosave side is
 * re-pointed at the surviving requestAutoSave(context, callback) signature.
 * Text input, IME and the platform channel are untouched.
 */
type OhosSdkAutoFillType = number;
type OhosSdkAutoFillTriggerType = number;

interface OhosSdkViewData {
  bundleName: string;
  moduleName: string;
  abilityName: string;
  pageUrl: string;
  pageNodeInfos: AutoFillManagerPageNodeInfo[];
  pageRect: OhosAutoFillRect;
  isUserSelected: boolean;
  isOtherAccount: boolean;
}

interface OhosSdkFillRequest {
  type: OhosSdkAutoFillType;
  viewData: OhosSdkViewData;
  customData: AutoFillCustomData;
  isPopup: boolean;
  triggerType: OhosSdkAutoFillTriggerType;
}

interface OhosSdkSaveRequest {
  viewData: OhosSdkViewData;
}

interface OhosSdkFillFailureResult {
  errCode: number;
}

interface OhosSdkAutoFillCallback {
  onSuccess: (viewData: OhosSdkViewData) => void;
  onFailure: (result: OhosSdkFillFailureResult) => void;
}

function requestOhosAutoFill(
  uiContext: UIContext,
  request: OhosSdkFillRequest,
  callback: OhosSdkAutoFillCallback,
): void {
  Log.w(TAG, 'autofill unavailable on this SDK; request ignored');
  callback.onFailure({ errCode: -1 });
}"""

REMOVED = (
    "autoFillManager.AutoFillType",
    "autoFillManager.ViewData",
    "autoFillManager.FillRequest",
    "autoFillManager.AutoFillCallback",
    "autoFillManager.FillFailureResult",
    "autoFillManager.AutoFillTriggerType",
    "autoFillManager.SaveRequest",
    "autoFillManager.requestAutoFill(",
)


def patch_text(text: str) -> tuple[str, list[str]]:
    """Return patched text plus the substitutions that failed to apply."""
    if MARKER in text:
        return text, []
    if SHIM_ANCHOR not in text:
        return text, [f"anchor not found: {SHIM_ANCHOR}"]
    text = text.replace(SHIM_ANCHOR, SHIM_ANCHOR + SHIM, 1)
    missing = []
    for old, new in REPLACEMENTS:
        if old not in text:
            missing.append(old.strip())
            continue
        text = text.replace(old, new, 1)
    return text, missing


def leftovers(text: str) -> list[str]:
    """Removed members still referenced by code.

    Line-based and comment-aware on purpose: the doc comment on OhosPageNodeInfo
    names `autoFillManager.ViewData`, and a plain substring scan reports it as an
    unfixed reference, which is both untrue and enough to abort the patch.
    """
    hits: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
            continue
        for member in REMOVED:
            if member in line and member not in hits:
                hits.append(member)
    return hits


def hars(sdk: pathlib.Path) -> list[pathlib.Path]:
    engine = sdk / "bin" / "cache" / "artifacts" / "engine"
    return sorted(engine.glob("ohos-*/flutter_embedding_*.har"))


def process(sdk: pathlib.Path, apply: bool) -> int:
    changed = 0
    problems: list[str] = []
    for har in hars(sdk):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp) / "package"
            with tarfile.open(har, "r:gz") as tf:
                tf.extractall(tmp, filter="data")
            target = root / RELATIVE
            if not target.is_file():
                problems.append(f"{har.name}: {RELATIVE} missing")
                continue
            text = target.read_text(encoding="utf-8")
            already = MARKER in text
            patched, missing = patch_text(text)
            if missing:
                problems.append(f"{har.name}: {len(missing)} substitution(s) missed")
                for m in missing[:3]:
                    problems.append(f"    {m}")
                continue
            left = leftovers(patched)
            if left:
                problems.append(f"{har.name}: still references {left}")
                continue
            if already or not apply:
                print(f"{'patched' if already else 'would patch'} {har.parent.name}/{har.name}")
                continue
            target.write_text(patched, encoding="utf-8")
            staged = har.with_suffix(".har.new")
            with tarfile.open(staged, "w:gz") as tf:
                tf.add(root, arcname="package")
            shutil.move(str(staged), str(har))
            changed += 1
            print(f"patched {har.parent.name}/{har.name}")
    for p in problems:
        print(f"  ! {p}", file=sys.stderr)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk", required=True, type=pathlib.Path)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if not args.sdk.is_dir():
        print(f"not a directory: {args.sdk}", file=sys.stderr)
        return 2
    found = hars(args.sdk)
    if not found:
        print(f"no embedding HAR under {args.sdk}", file=sys.stderr)
        return 2
    process(args.sdk, apply=args.apply)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
