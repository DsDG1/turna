"""Experience skill handlers (M7).

Handlers are ``(host, scope) -> None``. Heavy implementations still live on
``ExperienceSkillsMixin`` and are invoked via host methods; this package owns
the *registration map* used by ``experience_dispatch`` so new skills do not
touch the mixin dispatch surface.
"""
from __future__ import annotations

from src.application.experience_handlers import registry as _registry

# Re-export registry helpers
HANDLERS = _registry.HANDLERS
register_all = _registry.register_all

__all__ = ["HANDLERS", "register_all"]
