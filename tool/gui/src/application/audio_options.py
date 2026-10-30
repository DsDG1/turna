"""UI-facing option lists for MiniMax TTS generation.

These are the *choices the dialog offers*, not the transport contract — the
script (``tool/generate_audio.py``) owns the authoritative enums and validates
them. Keeping the lists in the application layer means ``src/dialogs`` does not
need a direct ``src.backend`` import just to populate a combo box
(``ui_backend`` is a ratchet), while the backend bridge stays transport-only.

Values mirror the official ``t2a_v2`` reference.
"""
from __future__ import annotations

#: Documented model ids, newest first.
TTS_MODEL_CHOICES: tuple[str, ...] = (
    "speech-2.8-hd",
    "speech-2.8-turbo",
    "speech-2.6-hd",
    "speech-2.6-turbo",
    "speech-02-hd",
    "speech-02-turbo",
    "speech-01-hd",
    "speech-01-turbo",
)

#: ``language_boost`` values worth offering (the API accepts the full enum).
TTS_LANGUAGE_BOOSTS: tuple[str, ...] = (
    "Turkish",
    "English",
    "Chinese",
    "German",
    "French",
    "Spanish",
    "Italian",
    "Japanese",
    "Korean",
    "Russian",
    "Portuguese",
    "Arabic",
    "Dutch",
    "Polish",
    "auto",
)

#: ``voice_setting.emotion`` values; empty = let the model choose.
TTS_EMOTIONS: tuple[str, ...] = (
    "",
    "calm",
    "happy",
    "fluent",
    "sad",
    "surprised",
)

#: Normalization modes accepted by the API.
TTS_NORMALIZATION_CHOICES: tuple[str, ...] = ("quality", "basic")

#: Voices worth offering for a Turkish course. ``female-tianmei`` is the
#: historical default (Mandarin); the ``English_*`` ids are multilingual voices
#: documented by MiniMax and read Turkish with far less L1 interference.
TTS_VOICE_CHOICES: tuple[str, ...] = (
    "female-tianmei",
    "English_Graceful_Lady",
    "English_Persuasive_Man",
    "male-qn-jingying",
    "female-yujie",
    "male-qn-daxiong",
    "female-shaonv",
    "male-chengshu",
)
