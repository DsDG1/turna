# AI goldens (aiEnhance Phase 0)

Static section fixtures for hygiene / coverage probes in `ai_bench.py`.
No live LLM calls — metrics must be deterministic.

| File | Intent |
|------|--------|
| `a1_greetings_clean.json` | Healthy A1 intro section |
| `a1_with_placeholders.json` | Stubs with `[待补]` + needs-review |
| `a1_dangling_refs.json` | showWord pointing at missing wordId |
| `a1_grounded_pool.json` | Section + companion pool for coverage |
| `listening_phases.json` | Listening template shape |
| `mcq_dup_options.json` | MCQ with duplicate options |
| `intent_routes.json` | Intent router routing fixtures |
| `intent_llm_parse.json` | Intent LLM parse fixtures |
