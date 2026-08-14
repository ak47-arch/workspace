# Task: implementer-ponytail

**Status**: complete
**Completed**: 2026-08-15 00:39
**Category**: Small
**Project**: software-factory
**Created**: 2026-08-14 00:45
**Source**: docs/tasks.txt — `Integrate the real ponytail skills into the implementer agent via pi --skill flags, replacing the prose directive (software-factory) [implementer-ponytail]`

## Artifacts

- Plan: (not yet created)

## Context

The implementer persona (`.pi/agents/implementer.md`) embeds ponytail only as a
hand-written prose directive ("Working style: ponytail (always-on directive)") —
never wired to the real skill package at `opensource/ponytail/skills/`. This task
upgrades it to the actual skills via the same repeatable `--skill` flag mechanism
the code-review agent uses (see decision 04 in session
`019ff79e-181d-7e8b-a869-398b6417d28a`).

## Sessions

- (planning not yet captured)
- [implementation](../knowledge/sessions/8483b243-ad9a-4e00-be82-0cdf26a8801d/session.jsonl)

## Decisions

- (none yet)- [ponytail-review-worker-skills](../knowledge/sessions/019ff79e-181d-7e8b-a869-398b6417d28a/decisions/04-ponytail-review-worker-skills.md)

## PR tracking

- PR: #2 (ak47-arch/workspace)
- URL: https://github.com/ak47-arch/workspace/pull/2
- Branch: factory/implementer-ponytail/20260814-212431
- Base: master · Head: 212370c67833ace883e263a17941a1f2f80e84d7 (raised 2026-08-14 21:40)
- Raised by: implementer run 8483b243-ad9a-4e00-be82-0cdf26a8801d
- Review: session 5b63c492-0880-4411-8ff5-26575091edff · verdict REQUEST_CHANGES—theimplementerwiredthesixponytail`--skill`flagscorrectly,butthecommitcontainsan**out-of-scope`opensource->/workspace/opensource`symlink**thatisabsentfromthePRDfilemap,contradictstheimplementer'sowndecisionrecord(whichstatesit"neverentersthecommit"),andisadanglingabsolute-host-pathartifactonanyotherclone.Thefull-suite-sweepacceptanceisalsonotreproduciblygreen(implementer-driver33/34inthisworktree)andthereportoverstatestheresult(34/34). · report docs/code-reviews/2026-08-14-implementer-ponytail/
- Revised: 20c84acbf6fd24f0f74c804513e72a8b900570ec (2026-08-15 00:15, impl session 8483b243-ad9a-4e00-be82-0cdf26a8801d, addressing review 5b63c492-0880-4411-8ff5-26575091edff)
- Review: session 85f5ce0b-7de4-4230-9f17-151742cac9b9 · verdict REQUEST_CHANGES—US4/decisionD5notfullyconformant:thepersonadropsthe · report docs/code-reviews/2026-08-15-implementer-ponytail/
- Revised: 2e4aa94623f17c089feb37dcaa0cfc3920f3fbd2 (2026-08-15 00:28, impl session 8483b243-ad9a-4e00-be82-0cdf26a8801d, addressing review 5b63c492-0880-4411-8ff5-26575091edff)
- Review: session 6b560fbb-bfe9-450b-94f9-fb24d8dadcec · verdict n/a · report docs/code-reviews/2026-08-15-implementer-ponytail/
- Merge: c469390a4fd9904ff458c7bd4ebd3de610d224d2 (2026-08-15 00:44, ak47-arch — user go-ahead, decision 05)
