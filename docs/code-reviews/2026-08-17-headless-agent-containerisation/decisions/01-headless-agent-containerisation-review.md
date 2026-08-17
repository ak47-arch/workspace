# Decision — Review findings on headless-agent-containerisation (PR #6)

Session: 3133f888-637f-4d83-99f1-f94b88a08328
Task: headless-agent-containerisation
Verdict: APPROVE

## Context
Reviewed the factory headless loop PR against the PRD. All stories implemented,
40/40 unit tests pass, dry-run wiring verified. Two non-blocking observations
worth recording for future runs.

## Decisions / observations

### 1. `.github/` un-ignore is a required enabling change, not scope creep
The PRD file-tree lists only `bin/factory-run.sh`, `.github/workflows/factory.yml`
and `bin/test-factory-run.sh`. The `.gitignore` change (+`!.github/`) lies outside
that map. It is **required for correctness**: `.gitignore` line 34 globally ignores
`.github/`, so without the negation the new workflow would never be committed.
Verified `.github/` contains only `workflows/factory.yml`, so re-tracking has no
collateral. Future PRs should add a `?.gitignore` entry to the file map or justify
such enabling changes explicitly.

### 2. Headless `--pick` fallback depends on the implementer's RUN_LOG line
In headless mode with an ambiguous multi-ready push the workflow passes `--pick`;
`factory-run.sh` then resolves the slug for the verdict read-back by grepping the
implementer RUN_LOG for `docs/tasks/<slug>.md`. Confirmed `implementer-run.sh`
(line ~709) emits `Task PR tracking: … recorded on docs/tasks/<PRD_SLUG>.md`, so
resolution holds. This coupling is worth a comment/commentary if the implementer's
tracking message wording ever changes.

### 3. Advisory (ponytail, ultra)
Duplicate slug-from-$RUN_LOG resolution at `bin/factory-run.sh:L135-137` vs
`L257-259` — extract a `resolve_slug()` helper. Not blocking.

## Outcome
No blocking findings. APPROVE. Real CI left to UAT (external infra/secrets).
