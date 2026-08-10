# Teaching Notes — Langfuse

## Lesson Log

- **0001 Trace anatomy** (2026-08-03): trace = session; observations = events; GENERATION/SPAN tree from pi extension. Record: `learning-records/0001-trace-anatomy.md`.
- **0002 Scores 101** (2026-08-09): score configs vs scores; BOOLEAN/NUMERIC/CATEGORICAL; three creation paths (config-first, annotation queues, LLM-judge); live-created `task-completion`, `response-quality` configs + `demo-queue-2026-08` queue. Record: `learning-records/0002-scores-101.md`.

## User Preferences (established session 2026-08-03)

- **Pace**: slow, lesson by lesson. One concept at a time.
- **Complexity**: always choose the least complex option. Avoid premature infrastructure.
- **Guide**: the official Langfuse skill is the reference. Don't teach from memory; fetch docs and skill references.
- **Interaction**: prefers hands-on demos over abstract explanations. Use real data (the 323 traces in the instance) whenever possible.
- **Scope**: wants to understand evals end-to-end, from manual scores to LLM-as-a-judge calibration.
- **Format**: HTML lessons in `docs/teach/langfuse/lessons/`. Beautiful, printable, self-contained.