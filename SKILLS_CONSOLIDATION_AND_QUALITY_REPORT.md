# Skills Consolidation and Quality Report

Date: 2026-05-31
Scope: workspace-wide audit of first-party skill systems, delivery conventions, and skill quality

## Executive Summary

The company currently has two coupled problems:

1. **Delivery fragmentation**: skills are authored and consumed through multiple incompatible directory conventions and agent-specific packaging models.
2. **Quality degradation**: many skills are too long, too prescriptive, too path-coupled, and too tool-specific to improve model performance reliably.

The result is not merely inconvenience. In several repositories, skills are likely **reducing** agent capability by:

- overwhelming the model with high-token procedural prose
- teaching the wrong tool names for the active harness
- hardcoding obsolete directory layouts into reusable instructions
- duplicating the same skill in multiple repos, creating guaranteed drift
- mixing repo policy, reusable capability, tool documentation, and orchestration into one retrieval unit

A company-wide reset is warranted. The recommended direction is:

- adopt **`.agent/skills/`** as the canonical repo-local authored skill source
- split repo-specific process law into **`.agent/policies/`** and **`.agent/workflows/`** rather than forcing everything into `SKILL.md`
- treat `.pi/skills`, `.agents/skills`, `.github/skills`, `.claude-plugin`, and future `.omp/*` paths as **projections**, not authored source
- aggressively shorten and restructure existing skills around progressive disclosure
- add a real lint/review/measurement loop for skill quality

---

## 1. Current State: Delivery Fragmentation

### 1.1 Active conventions in the workspace

Observed first-party skill layouts:

- root workspace: `.pi/skills/` and `.github/skills/`
- `llm`: `.agents/skills/`
- `feed_analyser`: `.agents/skills/`
- `survival-infrastructure`: `.github/skills/`
- `skills`: `skills/skills/...` plus `.claude-plugin/plugin.json`
- `agent-browser`: `skills/` discovery stub plus `skill-data/` runtime-served detailed content
- `hermes`: `skills/`, `optional-skills/`, `.pi/skills/`, and runtime/materialized `.hermes-data/skills/`

Evidence:

- Pi supports multiple skill locations, including `~/.pi/agent/skills/`, `~/.agents/skills/`, `.pi/skills/`, ancestor `.agents/skills/`, package `skills/`, settings paths, and CLI overrides: `pi-mono/packages/coding-agent/docs/skills.md:24-40`
- Pi SDK documents project discovery from `.pi/skills/` and ancestor `.agents/skills/`: `pi-mono/packages/coding-agent/docs/sdk.md:345-359`
- `skills` repo is organized under `skills/` buckets and requires entries in `.claude-plugin/plugin.json`: `skills/CLAUDE.md:1-15`, `skills/.claude-plugin/plugin.json:1-19`
- `skills` install script links skills into `~/.claude/skills`: `skills/scripts/link-skills.sh:4-8`, `skills/scripts/link-skills.sh:24-38`
- `feed_analyser` binds its agent config directly to `.agents/skills/sdd_tdd_developer/SKILL.md`: `feed_analyser/.opencode/config.json:4-8`
- `survival-infrastructure` feature agent loads skills from `.github/skills/...`: `survival-infrastructure/.github/agents/feature-development.agent.md:24-28`, `104-120`, `156-173`, `214-217`
- `llm` prompt and skill chain load `.agents/skills/...`: `llm/.pi/prompts/feature-development.md:1-9`, `llm/.agents/skills/feature-development/SKILL.md:50-55`, `151-155`, `168-171`, `187-190`, `220-223`
- Hermes distinguishes repo-local `skills/...`, user-local `~/.hermes/skills/...`, and runtime-loaded external dirs: `hermes/skills/software-development/hermes-agent-skill-authoring/SKILL.md:18-27`, `hermes/.hermes-data/config.yaml:348-359`

### 1.2 No current `.agent/skills` standard

A literal workspace search found **no checked-in `.agent/skills` references**.

This means the desired standard does not yet exist anywhere as an implemented convention. Migration will require both loader support and content rewrites.

### 1.3 No active `.omp` skill layout yet

A literal workspace search found **no `.omp/` skill path usage**.

This is good news: `.omp` has not yet become another entrenched authored source layout.

### 1.4 Compatibility burden is already visible in Pi

Pi is currently functioning as a compatibility matrix rather than a clean standard:

- loads both `.pi/skills` and `.agents/skills`: `pi-mono/packages/coding-agent/docs/skills.md:24-40`
- preserves different discovery behavior per location, including root markdown special-casing: `pi-mono/packages/coding-agent/docs/skills.md:36-40`
- added `.agents/skills` later as an extension: `pi-mono/packages/coding-agent/CHANGELOG.md:1643-1643`
- had to fix duplicate discovery when `~/.pi/agent/skills` points at `~/.agents/skills`: `pi-mono/packages/coding-agent/CHANGELOG.md:689-689`
- had to fix scoping problems around `~/.agents/skills`: `pi-mono/packages/coding-agent/CHANGELOG.md:1445-1445`
- had to special-case root markdown handling for `.agents/skills` vs other layouts: `pi-mono/packages/coding-agent/CHANGELOG.md:1081-1081`

This is evidence of structural friction, not just feature richness.

---

## 2. Current State: Skill Quality Problems

## 2.1 Skills are often too long to serve as effective retrieval units

Measured during the audit:

- root `.pi/skills`: median about 86.5 lines, max 162 lines
- `skills` repo: median about 84 lines, max 131 lines
- `llm/.agents/skills`: median about 170.5 lines, max 299 lines
- `survival-infrastructure/.github/skills`: median about 148.5 lines, max 286 lines
- `hermes/skills`: median about 238 lines, max 2378 lines

Representative oversized skills:

- `llm/.agents/skills/feature-development/SKILL.md`: 299 lines
- `llm/.agents/skills/spec-verifier/SKILL.md`: 286 lines
- `survival-infrastructure/.github/skills/spec-verifier/SKILL.md`: 286 lines
- `hermes/skills/research/research-paper-writing/SKILL.md`: 2378 lines, 102,437 chars
- `hermes/skills/autonomous-ai-agents/hermes-agent/SKILL.md`: 1021 lines

This is particularly problematic because Hermes’ own authoring guidance says:

- aim for 8–14k chars for peer skills
- split beyond 20k chars into references
- max content 100,000 chars

Evidence: `hermes/skills/software-development/hermes-agent-skill-authoring/SKILL.md:58-63`

Yet `research-paper-writing` exceeds the stated max and is far beyond any reasonable dispatch artifact size: `hermes/skills/research/research-paper-writing/SKILL.md:1-83`

## 2.2 Skills frequently mix too many concerns

A single skill often tries to be all of the following simultaneously:

- dispatch/routing surface
- repo policy contract
- workflow engine
- tool manual
- audit rubric
- reporting schema
- agent roleplay/identity layer

Representative example:

- `llm/.agents/skills/feature-development/SKILL.md` contains repo law, approval gates, phase choreography, cross-skill loading, commit/traceability policy, subagent instructions, and test/audit loops in one file: `llm/.agents/skills/feature-development/SKILL.md:19-30`, `34-84`, `90-163`, `166-257`

This is not progressive disclosure. It is procedural overload.

## 2.3 Identity boilerplate and roleplay are overused

Many skills spend valuable context budget on repeated self-positioning such as:

- “you are the independent auditor”
- “you have no stake in the outcome”
- “you are strictly read-only”
- “produce the report and stop”

Examples:

- `survival-infrastructure/.github/skills/spec-verifier/SKILL.md:3-9`
- `llm/.agents/skills/test-verifier/SKILL.md:8-20`

A small amount of role framing can be useful. Repeating it at length across many skills is mostly prompt tax.

## 2.4 Skills sometimes teach the wrong tools

This is a direct capability hazard.

`survival-infrastructure/.github/skills/spec-verifier/SKILL.md` instructs use of `file_search` and `grep_search`: `survival-infrastructure/.github/skills/spec-verifier/SKILL.md:64-73`

Those names do not match the current harness tools. Similar agent-specific or stale tool references appear elsewhere:

- `read_file` in GitHub-agent workflow docs: `survival-infrastructure/.github/agents/feature-development.agent.md:24-28`
- `read:` instructions wired to `.agents/skills` paths in `llm`: `llm/.agents/skills/feature-development/SKILL.md:50-55`, `151-155`, `168-171`, `187-190`, `220-223`
- Hermes-specific `skill_manage(...)` behavior in authoring guidance: `hermes/skills/software-development/hermes-agent-skill-authoring/SKILL.md:20-27`, `132-137`

A skill that teaches stale or non-portable tool names is worse than no skill.

## 2.5 Skills are path-coupled and layout-coupled

Reusable content currently hardcodes legacy paths:

- `.agents/skills/...`: `llm/.agents/skills/feature-development/SKILL.md:53`, `154`, `171`, `190`, `223`, `238`
- `.github/skills/...`: `survival-infrastructure/.github/agents/feature-development.agent.md:27`, `107`, `120`, `159`, `217`
- `.pi/skills/...`: `feed_analyser/.opencode/config.json:5-8`
- absolute machine-specific path in Hermes: `hermes/skills/software-development/hermes-agent-skill-authoring/SKILL.md:21`

This prevents easy projection into a new standard, and it means the content itself contains infrastructure coupling that should live outside the skill body.

## 2.6 Descriptions are sometimes too long and too broad

Skill descriptions are the always-in-context dispatch surface. They should optimize routing.

The `agent-browser` stub description is extremely long and enumerates a wide range of triggers and products before the body even begins: `agent-browser/skills/agent-browser/SKILL.md:1-5`

The body itself is actually a good pattern — a thin stub that delegates to version-matched runtime skill content: `agent-browser/skills/agent-browser/SKILL.md:15-27`

This contrast is instructive:

- **good**: the stub stays stable and avoids stale manuals
- **bad**: the frontmatter description is trying to encode too much routing logic and product surface area into the system prompt

---

## 3. Duplicate Content and Drift Risk

Exact duplicate skill bodies already exist across multiple repos.

Observed duplicates during the audit:

- `grill-me` in 4 places:
  - `llm/.agents/skills/grill-me/SKILL.md`
  - `survival-infrastructure/.github/skills/grill-me/SKILL.md`
  - `.pi/skills/grill-me/SKILL.md`
  - `skills/skills/productivity/grill-me/SKILL.md`
- `grill-with-docs` duplicated between root `.pi` and `skills`
- `tdd` duplicated between root `.pi` and `skills`
- `to-issues` duplicated between root `.pi` and `skills`
- `to-prd` duplicated between root `.pi` and `skills`
- `tdd-karpathy-guidelines` duplicated between `llm` and `survival-infrastructure`
- `test-verifier` duplicated between `llm` and `survival-infrastructure`
- `vscode-speech-mic-recovery` duplicated between `llm` and `survival-infrastructure`

There are also name collisions across projects even when files are not exact duplicates, including:

- `feature-traceability`
- `module-boundary`
- `spec-verifier`
- `karpathy-guidelines`

This means drift is not hypothetical. It is built into the current authoring model.

---

## 4. Anti-Patterns Detected

## 4.1 “Skill as replacement system prompt”

Many skills try to redefine general agent behavior rather than supply task-local specialization.

Symptoms:

- heavy identity framing
- repeated safety/discipline mantras
- generalized collaboration rules
- workflow ceremony repeated inside every skill

Effect:

- inflated token cost
- more chances to conflict with harness/system instructions
- reduced clarity on what the skill actually adds

## 4.2 “One skill = full methodology”

Files like `feature-development`, `spec-verifier`, `test-verifier`, and `module-boundary` are too broad.

They should be decomposed into:

- dispatch surface
- execution procedure
- report schema
- reference docs
- repo workflow/policy

Instead, each is a monolith.

## 4.3 “Path-bound composition”

Skills load other skills by literal filesystem path.

Examples:

- `llm/.agents/skills/feature-development/SKILL.md:50-55`, `151-155`, `168-171`, `187-190`, `220-223`
- `survival-infrastructure/.github/agents/feature-development.agent.md:24-28`, `104-120`, `156-173`, `214-217`

This is brittle and makes migration expensive because the authored content is coupled to the current layout.

## 4.4 “Policy embedded in reusable skills”

Many skills embed repo-specific approval rules, commit conventions, or traceability rules that are not general capabilities.

Example:

- `llm/.agents/skills/feature-development/SKILL.md:19-30`, `139-163`

This belongs in repo workflow/policy configuration, not in a reusable task capability unit.

## 4.5 “Tool manual embedded in dispatch artifact”

Some skills try to contain complete manuals directly in `SKILL.md`, rather than delegating detailed or volatile content into references or runtime docs.

The best counterexample is `agent-browser`, which uses a thin stub and serves detailed, version-matched content from the CLI: `agent-browser/skills/agent-browser/SKILL.md:15-27`, `agent-browser/README.md:1256-1266`

## 4.6 “Self-contradictory guidance”

Hermes’ authoring guidance advocates size limits and splitting into references, but the repo contains many skills that ignore those principles, including at least one that exceeds the documented max: `hermes/skills/software-development/hermes-agent-skill-authoring/SKILL.md:58-63`, `hermes/skills/research/research-paper-writing/SKILL.md:1-83`

This indicates there is no enforced quality gate.

## 4.7 “Mandatory chat ceremony”

Some workflows instruct the agent to repeatedly surface phase status or stop at many boundaries.

Examples:

- `survival-infrastructure/.github/agents/feature-development.agent.md:7-10`
- `llm/.agents/skills/feature-development/SKILL.md:13-16`

That pattern increases interaction overhead and can reduce autonomous execution quality.

---

## 5. Bottlenecks

## 5.1 No canonical author-once / project-many pipeline

Today, the same capability is copied into multiple repos and multiple agent-specific directories. There is no standard projection tool generating compatibility views from one source.

## 5.2 No company-wide quality gate

There is no shared linter or CI rule enforcing:

- size budgets
- forbidden path literals
- tool name validity
- duplication detection
- split/reference usage
- description quality
- projection freshness

## 5.3 No usage or effectiveness telemetry

The organization currently lacks a systematic loop for measuring:

- trigger precision / false positives
- success after loading a skill
- user override rate
- token cost per skill load
- stale instruction rate
- tool mismatch incidents

Without that, verbose or harmful skills can persist indefinitely.

## 5.4 No taxonomy separating capability from workflow from policy

The current `SKILL.md` format is being forced to represent three different things:

- reusable capability
- repo workflow orchestration
- repo-specific governance/policy

These should not be flattened into one unit.

## 5.5 No controlled promotion / dedupe path

There is no formal process for deciding when a repo-local skill should become:

- company canonical
- repo overlay
- experimental
- deprecated
- tool-owned dynamic stub

That vacuum encourages copy-paste reuse.

---

## 6. What Good Should Look Like

## 6.1 Canonical authored layout

Recommended canonical repo-local authored source:

```text
.agent/
  skills/
    <skill-name>/
      SKILL.md
      references/
      templates/
      scripts/
      assets/
  workflows/
  policies/
  skill-manifest.json
```

Interpretation:

- `.agent/skills/` = reusable task capabilities
- `.agent/workflows/` = repo orchestration flows
- `.agent/policies/` = repo law / process contracts

This prevents capability, workflow, and policy from contaminating one another.

## 6.2 Treat legacy layouts as projections, not source

The following should become generated compatibility outputs where needed:

- `.pi/skills/`
- `.agents/skills/`
- `.github/skills/`
- `.claude/skills/`
- `.omp/skills/` if introduced later

Author once in `.agent/skills/`. Project many.

## 6.3 Define skill types explicitly

### Type A — Dispatch stub

Purpose: routing and minimal entry guidance.

Rules:

- very short description
- very short body
- no detailed manual
- can delegate to references or runtime docs

### Type B — Procedure skill

Purpose: bounded workflow execution.

Rules:

- one job only
- clear entry/exit conditions
- limited checklist
- avoid repo-specific law unless truly local

### Type C — Reference pack

Purpose: details, examples, schemas, edge cases.

Rules:

- lives in `references/`, `templates/`, or `scripts/`
- loaded only on demand

### Type D — Repo workflow/policy

Purpose: project-specific operating contract.

Rules:

- should live under `.agent/workflows/` or `.agent/policies/`
- should not masquerade as a general reusable skill

## 6.4 Use dynamic stubs for volatile tool surfaces

For tools whose commands and behavior evolve rapidly, emulate `agent-browser`:

- keep a stable discovery stub in the repo
- fetch current detailed content from the installed tool/runtime

Evidence of the pattern:

- `agent-browser/skills/agent-browser/SKILL.md:15-27`
- `agent-browser/README.md:1256-1266`

This is the best current anti-drift pattern found in the workspace.

---

## 7. Recommended Quality Rules

Suggested default company rules for canonical authored skills:

### 7.1 Frontmatter

- `name`
- `description`
- optional lightweight metadata only

### 7.2 Hard budgets

- description <= 240 chars preferred; 400 absolute max unless justified
- dispatch `SKILL.md` <= 120 lines preferred
- if body exceeds 120 lines, split into references or justify waiver
- no single canonical skill body should approach the current Hermes megafile scale

### 7.3 Forbidden content in canonical authored skills

- legacy layout literals (`.pi/skills`, `.agents/skills`, `.github/skills`) unless in migration notes/reference docs
- absolute machine-specific paths
- stale or invented tool names not in the target harness map
- repeated identity boilerplate beyond a short minimal framing
- repo-specific commit/process law in general-purpose capability skills

### 7.4 Required design properties

- one skill, one job
- clear trigger surface
- explicit counter-triggers where ambiguity is likely
- references for depth, not bloated body text
- no mandatory user interruptions unless a real decision is needed

---

## 8. Recommended Migration and Refinement Program

## Phase 1 — Freeze the standard

1. Adopt `.agent/skills/` as canonical authored source.
2. Introduce `.agent/workflows/` and `.agent/policies/`.
3. Declare existing repo-local `.pi/skills`, `.agents/skills`, and `.github/skills` authored usage deprecated.
4. Do not add any new first-party skills to legacy authored locations.

## Phase 2 — Build the tooling

Build a company skill toolchain with three core commands:

### `agent-skills lint`
Checks for:

- size budget violations
- duplicate exact content
- duplicate names
- bad descriptions
- forbidden path literals
- stale tool names
- missing referenced files
- projection drift

### `agent-skills sync`
Projects canonical authored skills into compatibility targets:

- `.agents/skills/`
- `.github/skills/`
- `.pi/skills/`
- `.claude-plugin` manifest output
- any future `.omp/*` integration

### `agent-skills audit`
Reports:

- duplicates across repos
- oversized skills
- repo policy embedded in skills
- unused skills
- hardcoded path chains
- likely candidates for stub conversion

## Phase 3 — Triage the current inventory

Classify every current skill as one of:

- keep
- rewrite
- split
- convert to stub
- move to workflow/policy
- merge into company canonical
- delete / deprecate

High-priority rewrite/split candidates:

- `feature-development`
- `spec-verifier`
- `test-verifier`
- `module-boundary`
- oversized Hermes skills such as `research-paper-writing`

High-priority dedupe candidates:

- `grill-me`
- `grill-with-docs`
- `tdd`
- `to-issues`
- `to-prd`
- `karpathy-guidelines`
- `test-verifier`
- `spec-verifier`
- `module-boundary`
- `feature-traceability`

## Phase 4 — Rewrite the worst patterns first

### 8.4.1 Split monolithic workflow skills

Example target decomposition for current `feature-development` monolith:

- `.agent/workflows/feature-delivery.md` — repo orchestration and approval flow
- `.agent/skills/discovery-grill/` — discovery questioning procedure
- `.agent/skills/spec-authoring/` — canonical spec drafting/update procedure
- `.agent/skills/tdd-loop/` — red/green/refactor execution
- `.agent/skills/test-audit/` — test quality audit procedure + report schema
- `.agent/skills/spec-audit/` — spec audit procedure + report schema
- `.agent/skills/module-boundary-audit/` — boundary audit procedure + scripts/references

### 8.4.2 Convert dynamic tool manuals to stubs

Where a skill mostly teaches a volatile CLI or API surface, use a thin discovery stub plus runtime-served docs.

### 8.4.3 Remove hardcoded path composition

Replace authored content that says things like:

```text
read: .agents/skills/spec-verifier/SKILL.md
```

with symbolic references resolved by the runtime/manifest layer.

## Phase 5 — Roll out governance

Add CI gates:

- canonical source only
- projections up to date
- no duplicate exact content without explicit linkage
- no oversized skill without waiver
- no stale tool references

---

## 9. Recommended Governance Loop

## 9.1 Ownership model

Each skill should declare a tier:

- `company-core`
- `company-tool`
- `repo-workflow`
- `repo-policy`
- `experimental`
- `deprecated`

This forces clarity about whether a skill is broadly reusable or locally specific.

## 9.2 Review loop

For each new or modified skill:

1. **Structure review**
   - Is it the right type?
   - Is it too broad?
   - Should some content move to references or workflow/policy?

2. **Portability review**
   - Any path literals?
   - Any harness-specific tool leaks?
   - Any repo-local assumptions?

3. **Quality review**
   - Is it concise?
   - Does the description route cleanly?
   - Does it over-instruct?

4. **Duplication review**
   - Does an existing skill already cover this?
   - Should this be a fork, an extension, or a merge?

## 9.3 Measurement loop

Track per skill:

- load frequency
- false-trigger rate
- completion success rate
- user override rate
- incremental token cost
- tool mismatch incidents
- stale-content incidents
- whether the agent ignored the skill after loading it

The point is to make skill quality measurable instead of aesthetic.

---

## 10. Immediate Actions

### Immediate action 1
Freeze new authored skill creation outside the future canonical layout.

### Immediate action 2
Implement `.agent/skills` support first in `pi-mono`, because Pi already owns the broadest compatibility surface: `pi-mono/packages/coding-agent/docs/skills.md:24-40`

### Immediate action 3
Build a scanner that flags literal references to:

- `.pi/skills`
- `.agents/skills`
- `.github/skills`

These hardcoded references are the primary migration drag.

### Immediate action 4
Pick one representative bad stack and replace it end-to-end. Best candidate:

- `feature-development`
- `test-verifier`
- `spec-verifier`

These files are currently large, path-bound, and process-heavy.

### Immediate action 5
Use `agent-browser` as the reference pattern for volatile tool skills:

- short stub in canonical source
- runtime-served detailed docs when needed

---

## 11. Bottom Line

The current system is suffering from both **distribution entropy** and **instruction quality entropy**.

The core mistakes are:

- authoring in many locations
- copying instead of projecting
- treating every kind of agent guidance as a `SKILL.md`
- writing monolithic prose-heavy skills instead of compact dispatch plus references
- embedding stale path and tool assumptions directly in reusable content

A clean company-wide solution is available:

- canonical authored source in `.agent/skills/`
- explicit separation of skills vs workflows vs policies
- generated compatibility projections for agent-specific ecosystems
- strict quality budgets and linting
- aggressive dedupe and splitting of current monoliths
- measurement-based refinement instead of organic drift

Without that reset, the company will continue paying the same costs repeatedly: drift, inconsistent agent behavior, degraded model performance, and ever-higher migration friction.
