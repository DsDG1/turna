library;

/// Single tuning point for the evidence-driven recognizer (doc 37 §3.5–3.6).
///
/// Every weight, threshold, and confidence band lives here. Domain-specific
/// words never do: only structural synonyms are allowed in the lexicon, and
/// only measurement thresholds are allowed in this file.

/// Bump when recognition logic changes in a way that should invalidate
/// cached suggestions for unconfirmed mappings.
const int recognizerVersion = 2;

// ---------------------------------------------------------------------------
// L1 field-role binding weights (§3.5)
// ---------------------------------------------------------------------------

/// Field name normalizes to an exact lexicon hit.
const double lexiconExactWeight = 0.55;

/// Field name contains a lexicon term (composite names like `VocabFront`).
const double lexiconContainsWeight = 0.35;

/// Field appears on the front template of some card (templateFacts/reqs).
const double structuralFrontWeight = 0.30;

/// Field appears only on back templates.
const double structuralBackWeight = 0.30;

/// Positional prior: field[0] leans prompt.
const double positionalFrontWeight = 0.25;

/// Positional prior: field[1] leans response.
const double positionalBackWeight = 0.25;

/// Sample values contain `[sound:` / `[anki:play:`.
const double sampleAudioWeight = 0.50;

/// Sample values contain `<img` / `[image:`.
const double sampleImageWeight = 0.50;

/// Sample values are plain short text: small boost to both text roles.
const double sampleShortTextWeight = 0.10;

/// Template `{{tts:}}` filter references the field.
const double templateTtsWeight = 0.30;

/// Confidence floor for the positional fallback binding pass.
const double positionalFallbackConfidence = 0.35;

/// Confidence assigned to fields that match no signal at all.
const double unmatchedFieldConfidence = 0.20;

/// Cap for a single field's accumulated role score.
const double bindingScoreCap = 1.0;

// ---------------------------------------------------------------------------
// L2 archetype rule weights (§3.6). Highest weight wins; ties break by
// rule order (earlier row first), which already encodes
// structure > binding > content.
// ---------------------------------------------------------------------------

const double ruleClozeDeclaredWeight = 1.00; // A1 structure
const double ruleTemplateRichHtmlWeight = 1.00; // A2 structure
const double ruleTypeInWeight = 0.95; // A3 structure
const double ruleChoiceBoundWeight = 0.90; // A4 binding
const double ruleContentScriptWeight = 0.95; // A2 content twin
const double ruleContentComplexHtmlWeight = 0.90; // A2 content twin
const double ruleEmbeddedOptionsUnparsedWeight = 0.90; // iron law
const double ruleSampleClozeWeight = 0.80; // A5 content
const double ruleEmbeddedOptionsWeight = 0.80; // A6 content
const double ruleEmbeddedOptionsMixedWeight = 0.78; // A6m content, review band
const double ruleAudioFirstWeight = 0.80; // A7 content
const double ruleShortPairWeight = 0.75; // A8 content
const double ruleDefaultPairedWeight = 0.60; // A9 with a bound pair
const double ruleDefaultBareWeight = 0.50; // A9 without a pair

/// Corroboration bonus when the winning content rule is backed by an
/// aligned binding (A6 answer alignment, A7 bound audio role).
const double corroboratedContentBonus = 0.08;

/// Corroboration bonus when a basicPair win is backed by strong prompt AND
/// response bindings (lexicon + structure agreed).
const double corroboratedPairBonus = 0.15;

// ---------------------------------------------------------------------------
// Content-rate thresholds (fraction of non-empty samples that must agree)
// ---------------------------------------------------------------------------

const double sampleRateThreshold = 0.60;

/// A6m floor: option-looking fronts at this rate..sampleRateThreshold fire
/// the mixed choice rule at review-band confidence instead of nothing.
const double embeddedOptionsReviewRate = 0.40;

// ---------------------------------------------------------------------------
// Confidence bands (§3.6)
// ---------------------------------------------------------------------------

const double bandAutoMin = 0.85;
const double bandReviewMin = 0.60;

// ---------------------------------------------------------------------------
// Text metrics
// ---------------------------------------------------------------------------

/// Answers at most this long (and single-line) count as "short".
const int shortAnswerMaxLength = 60;

/// Samples per notetype requested from the engine for recognition.
const int recognitionSampleLimit = 30;
