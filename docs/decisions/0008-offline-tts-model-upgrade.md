# ADR 0008: Offline TTS model upgrade path

## Status

Accepted (research + settings fix); **model binary swap deferred** pending license choice.

## Context

The bundled offline voice is Piper `sw_CD-lanfrica-medium` (int8). Official
Piper has **no** higher-quality East African (`sw_KE`) alternative. Users find
the Congo / English-finetune timbre unnatural compared with Google TTS.

## Decision

1. **Default learning voice remains System / Google TTS.**
2. **Offline path remains a first-class setting** with explicit preview feedback
   (`speakWithResult`, Snackbar, Retry init) — see Part 1 implementation.
3. **Candidate replacements for the offline ONNX bundle** (pick one later):

| Priority | Model | Pros | Cons |
|----------|--------|------|------|
| A | Meta `facebook/mms-tts-swh` → sherpa-onnx VITS | Best open quality candidate for Swahili | Often **CC-BY-NC**; conversion work |
| B | Official non-int8 `vits-piper-sw_CD-lanfrica-medium` | Drop-in; clearer license | Same Congo accent |
| C | Keep int8 Piper | Smallest APK | Current quality ceiling |

Until (A) license is confirmed safe for the intended distribution, prefer **(B)**
for a low-risk swap or keep **(C)** with Google as primary.

## Consequences

- No immediate APK size increase from a new model in this change set.
- Settings UX no longer silently confuses Google fallback with “Offline works”.
- `tool/generate_audio.py` must track whatever offline model ships in assets.

## References

- `docs/tts-troubleshooting.md`
- rhasspy/piper-voices: only `sw/sw_CD/lanfrica/medium`
- sherpa-onnx TTS MMS conversion docs
