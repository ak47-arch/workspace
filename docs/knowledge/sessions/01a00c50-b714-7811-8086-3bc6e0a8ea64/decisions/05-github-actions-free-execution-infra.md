## Decision: GitHub Actions on the public workspace repo is the factory's execution infra — cost is LLM tokens

**Status**: accepted
**Date**: 2026-08-17 17:27
**Task**: headless-agent-containerisation
**Project**: software-factory
**Session**: sessions/01a00c50-b714-7811-8086-3bc6e0a8ea64/session.jsonl

### Context

The headless implement → review loop (`factory.yml`) runs on GitHub-hosted
runners (`ubuntu-latest`). The workspace repo `ak47-arch/workspace` is public.
Billing in GitHub Actions attaches to the repo where the job runs, not the repos
the job pushes to; the loop pushes branches to cross-repo targets
(`llamacpp_inference_server`, `goal-agent`, `feed_analyser`, …).

### Problem

Price the factory's execution infrastructure honestly and design the credential
flow so the workers can run without exposing the host's GitHub identity.

### Alternatives

- **Self-hosted** (Woodpecker / herdr on our own box) — full control, but
  machine + maintenance + ops cost; deferred as extension paths.
- **Private-repo CI** — would bill the loop against the 2,000 private
  minutes/month allowance.

### Decision

Standard GitHub-hosted runners on the **public** workspace repo are the factory's
execution infra: implementer, reviewer, and revision iterations run free
(public-repo standard-runner minutes are free and unlimited). The real operating
cost is **LLM inference tokens** (OpenRouter per run), not infrastructure.
Credential flow: repo secrets (encrypted at rest) → job env via
`${{ secrets.X }}` → driver `env_allowlist` (`config/implementer.json`) →
`secrets.env` (`chmod 600`, deleted post-run) → `--env-file` into the sandbox
container. **GitHub credentials are never in the allowlist** — the host driver
owns git/gh, the worker container never sees the PAT.

### Rationale

The head+hands split made this possible: disposable containerized workers +
deterministic bash host are CI-native, so the loop fits an ephemeral free job
with no persistent infra of our own. The trust posture holds because the PAT
never enters the container; the residual risk is the standard agent-env exposure
of the LLM/Langfuse keys the worker must see.

### Consequences

- The factory's execution is $0/month in infra while the workspace stays public.
- Flipping the repo private re-introduces billing (2,000 min/month allowance).
- Larger/paid runners would bill even on public repos.
- Cross-repo pushes bill nothing; target repos' only CI (`openwiki-update.yml`)
  is cron/manual, not push-triggered.

### Revision triggers

- The workspace repo goes private.
- GitHub changes public-repo free-tier policy.
- A target repo adds push-triggered CI that factory branches would fire.
- The loop needs a non-standard (paid) runner.
