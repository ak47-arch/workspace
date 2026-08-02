# Mission: Langfuse

## Why
I run a software factory where pi and other applications produce constant LLM
output. I want to measure whether that output is good — systematically, at
scale — so quality is verifiable, not vibes. Langfuse evals are the tool.

## Success looks like
- I can open Langfuse and understand what any trace means
- I can score traces manually (annotation queues) and trust the results
- I can run LLM-as-a-judge evals at scale and know whether the judge is calibrated
- I can detect regressions in agent output quality over time
- Langfuse is integrated into every first-party application, not just pi

## Constraints
- Prefer the least complex option at every step
- The official Langfuse skill is the guide — I don't know how evals work
- Work happens slowly, lesson by lesson

## Out of scope
- Langfuse platform internals (clickhouse, redis tuning)
- v4 migration planning
- CI/CD experiment gates for now