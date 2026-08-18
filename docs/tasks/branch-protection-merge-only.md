# Task: branch-protection-merge-only

**Status**: in-prd
**Blocker**: GitHub free plan — branch protection (rulesets AND classic API) is Pro-gated for private repos; uncompletable as written on this plan
**Disposition**: kept open — never closed directly; public-repo portion done + verified (2026-08-18); private-repo portion blocked; workspace portion sequenced into `multi-repo-delivery-bookkeeping-prs`
**Category**: Small
**Project**: software-factory
**Created**: 2026-08-18 19:59
**Source**: docs/tasks.txt — `- Enforce merge-only on all repos: GitHub branch protection on every default branch so no code is ever pushed directly — everything merges via a reviewed PR (software-factory) [branch-protection-merge-only] (blocked: GitHub Pro required — kept open)`

## Artifacts

- Plan: `docs/prd-queue/2026-08-18-branch-protection-merge-only.md`

## Sessions

- `docs/knowledge/sessions/01a01515-8457-7260-a4d6-45731d61d571/session.jsonl` (planning)

## Decisions

- `docs/knowledge/sessions/01a01515-8457-7260-a4d6-45731d61d571/decisions/01-multi-repo-delivery-pr-shapes.md`
- `docs/knowledge/sessions/01a01515-8457-7260-a4d6-45731d61d571/decisions/02-branch-protection-merge-only.md`

## Blocker

This task cannot complete as written: on the GitHub **free plan**, branch
protection of any kind (repository rulesets or the classic API) is rejected
for **private** repos with HTTP 403 "Upgrade to GitHub Pro or make this
repository public to enable this feature". Five inventory repos
(`goal-agent`, `feed_analyser`, `workspace-portability`, `resume`,
`emotional_architecture`) are private, so their default branches cannot be
made merge-only on this plan.

Executed portion (2026-08-18): classic branch protection applied + verified
(GET) + observed negative push test on the three public app repos
(`llamacpp_inference_server`, `headroom-pi`, `timesheetViewer`). The
`workspace` repo is public and is sequenced as the capstone of
`multi-repo-delivery-bookkeeping-prs`.

**Disposition**: the task stays **open** (`in-prd`) and is never closed
directly. It becomes completable only if GitHub Pro is adopted (then the 5
private repos can be protected in one pass); until then it stays parked,
invisible to the headless loop (PRD Draft + task in-prd).
