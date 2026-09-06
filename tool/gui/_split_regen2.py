"""P2-B: extract _on_ok/_on_err closures of _run_regen_flow into module fns."""
import re
from pathlib import Path

F = Path("src/application/experience_handlers/regenerate.py")
text = F.read_text(encoding="utf-8")
lines = text.splitlines(keepends=True)


def seg(a, b):
    return "".join(lines[a - 1:b])


def to_module_fn(def_line_old: str, def_line_new: str, body: str) -> str:
    out = []
    for ln in body.splitlines(keepends=True):
        if ln.strip() == def_line_old:
            ln = def_line_new + "\n"
        elif ln.startswith("    "):
            ln = ln[4:]
        out.append(ln)
    return "".join(out)


FIELDS = ("host", "action_id", "kind", "node_id", "section", "sid",
          "job_id", "job_label", "guard_key", "tx_snap")

ok_body = seg(379, 435)
err_body = seg(437, 452)


def specialize(body: str, def_old: str, def_new: str) -> str:
    out = []
    for ln in body.splitlines(keepends=True):
        if ln.strip() == def_old:
            ln = def_new + "\n"
        elif ln.startswith("    "):
            ln = ln[4:]
        out.append(ln)
    t = "".join(out)
    for var in FIELDS:
        t = re.sub(rf"\b{var}\b", f"s.{var}", t)
    return t


ok_fn = specialize(ok_body, "def _on_ok(result: object) -> None:",
                   'def _regen_on_ok(s: "_RegenSession", result: object) -> None:')
err_fn = specialize(err_body, "def _on_err(msg: str) -> None:",
                    'def _regen_on_err(s: "_RegenSession", msg: str) -> None:')

SESSION_DEF = '''@dataclass
class _RegenSession:
    """Shared state of one single-node regeneration flow (P2 split)."""

    host: ExperienceHost
    action_id: str
    kind: str
    node_id: str
    section: dict
    sid: str
    job_id: str
    job_label: str
    guard_key: str
    tx_snap: Any


'''

SESSION_BUILD = '''    session = _RegenSession(
        host=host,
        action_id=action_id,
        kind=kind,
        node_id=node_id,
        section=section,
        sid=sid,
        job_id=job_id,
        job_label=job_label,
        guard_key=guard_key,
        tx_snap=tx_snap,
    )

    worker.result_ready.connect(partial(_regen_on_ok, session))
    worker.error_occurred.connect(partial(_regen_on_err, session))
    worker.start()
    host._experience_worker = worker
'''

# Replace from "    def _on_ok" (379) through "host._experience_worker = worker" (457)
old_block = seg(379, 457)
assert "def _on_ok" in old_block and "worker.start()" in old_block
text = text.replace(old_block, SESSION_BUILD, 1)

# Insert the dataclass before _run_regen_flow
anchor = "def _run_regen_flow(\n"
assert anchor in text
text = text.replace(anchor, SESSION_DEF + anchor, 1)

# Append the two module functions after the alias
alias = "handle_run_regen_flow = _run_regen_flow\n"
assert alias in text
text = text.replace(
    alias,
    alias + "\n\n" + ok_fn + "\n\n" + err_fn,
    1,
)

# functools.partial import at the top
text = text.replace(
    "from dataclasses import dataclass\n",
    "from dataclasses import dataclass\nfrom functools import partial\n",
    1,
)

F.write_text(text, encoding="utf-8", newline="")
import ast

ast.parse(text)
print("regen flow ok/err split; syntax ok")
