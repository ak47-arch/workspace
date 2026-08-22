# Decision-Loop Evaluation — 2026-08-22

Decisions: 120 · PASS 63 / FAIL 36 / SKIP 21

| decision | session | verdict | claim failures | trace |
|---|---|---|---|---|
| 01-factory-architecture-decisions.md | 019f8faf | SKIP | — | — |
| 01-github-browser-auth-flow.md | 019f937c | SKIP | — | — |
| 01-parallel-repo-clone.md | 019f93aa | FAIL | parallel clone implemented (restore_workspace.py concurrency | — |
| 01-capture-instrument-architecture.md | 019f9487 | FAIL | capture instrument architecture exists (feed_analyser/captur | — |
| 02-extension-platform-and-ux.md | 019f9487 | SKIP | — | — |
| 03-artefact-data-model-and-storage.md | 019f9487 | FAIL | capture server + storage present (feed_analyser/capture/serv | — |
| 04-legacy-feed-analyser-archiving.md | 019f9487 | FAIL | feed_analyser legacy archive is archived (local archive dir) | — |
| 01-gdrive-integration-model.md | 019f9a16 | FAIL | gdrive ingestion is a planned feature (PRD in queue) | — |
| 02-gdrive-auth-and-configuration.md | 019f9a16 | FAIL | gdrive auth config scoped (PRD in queue) | — |
| 03-gdrive-file-export-and-storage.md | 019f9a16 | FAIL | gdrive export/storage scoped (PRD in queue) | — |
| 01-cognee-ingestion-test-fidelity-assessment.md | 019f9a5c | FAIL | cognee present for ingestion assessment | — |
| 02-graphify-mismatch-with-context-engine.md | 019f9a5c | FAIL | graphify present for context-engine comparison | — |
| 01-opensource-repo-manifest-registration-skill.md | 019fa31b | FAIL | opensource registration skill path resolves | — |
| 01-voice-input-via-whisper-cpp.md | 019fa825 | PASS | — | — |
| 01-survival-infrastructure-core-product-architecture.md | 019faf18 | FAIL | survival-infrastructure is a live first-party project | — |
| 01-github-device-auth-flow-implementation.md | 019faf44 | FAIL | device-auth flow script exists (workspace-portability/github | — |
| 02-device-flow-test-verification.md | 019faf44 | FAIL | device-flow test suite exists (test-restore.sh) | — |
| 01-herdr-pi-session-repopulation.md | 019fb3a9 | FAIL | herdr repo is present for session repopulation | — |
| 01-mission-control-deprecation.md | 019fb3b8 | PASS | — | — |
| 01-task-identification.md | 019fb3ee | PASS | — | — |
| 02-task-centric-storage.md | 019fb3ee | PASS | — | — |
| 03-prd-queue-lifecycle.md | 019fb3ee | PASS | — | — |
| 04-traceability-links.md | 019fb3ee | PASS | — | — |
| 01-vision-document-convention.md | 019fb45b | PASS | — | — |
| 01-make-repos-private.md | 019fb4a3 | FAIL | first-party repos are private on GitHub (gh api visibility) | — |
| 01-three-phase-product-layer.md | 019fb4f8 | PASS | — | — |
| 01-task-lifecycle-state-machine-and-transition-tooling.md | 019fb98c | PASS | — | — |
| 01-single-factory-context-document.md | 019fbd12 | PASS | — | — |
| 02-context-engine-nomenclature.md | 019fbd12 | PASS | — | — |
| 03-reliable-transition-script-with-tests.md | 019fbd12 | PASS | — | — |
| 01-temporal-metadata-convention.md | 019fc389 | PASS | — | — |
| 01-langfuse-v3-to-v4-upgrade.md | 019fc40a | FAIL | v4 write mode stays `dual` (pi tracing must not break on res | — |
| 01-capture-text-only-scope-and-vision.md | 019fc8f4 | FAIL | capture text-only scope and vision docs exist (capture/docs) | — |
| 02-capture-api-contract.md | 019fc8f4 | FAIL | capture server (X capture) still present | — |
| 03-capture-server-fixed-config.md | 019fc8f4 | SKIP | — | — |
| 01-prd-as-routing-document-context-engine-depth.md | 019fd00b | PASS | — | — |
| 02-review-sub-agent-in-session-validation-gate.md | 019fd00b | PASS | — | — |
| 03-scope-boundary-ci-and-implementer-deferred-to-part2.md | 019fd00b | SKIP | — | — |
| 04-subagent-infrastructure-pi-extension-project-local.md | 019fd00b | PASS | — | — |
| 01-capture-v1-single-intent-save-whole-post.md | 019fd314 | SKIP | — | — |
| 02-capture-links-embedded-tweets-and-tco-resolution.md | 019fd314 | FAIL | capture link/tco resolution landed (capture server) | — |
| 03-prd-archive-requires-uat-and-user-signoff.md | 019fd314 | PASS | — | — |
| 04-capture-recursive-node-tree-comment-is-tweet.md | 019fd314 | FAIL | capture recursive node-tree comment handling landed (server) | — |
| 05-capture-resolve-links-and-restart-server.md | 019fd314 | FAIL | capture resolve-links + restart server landed (run-server.sh | — |
| 01-pi-sdk-agent-service.md | 019fd8a4 | FAIL | pi-SDK agent-service present (feed_analyser/capture/agent-se | — |
| 02-openrouter-inference-server-side-key.md | 019fd8a4 | FAIL | OpenRouter inference server-side key (llm/ server config) | — |
| 03-agent-tools-fetch-url-only.md | 019fd8a4 | FAIL | fetch_url tool present (agent-service/tools/fetch_url.js) | — |
| 04-artefact-session-evidence-model.md | 019fd8a4 | FAIL | session evidence model landed (agent-service agent.js + pers | — |
| 05-twitter-kb-plain-files-fts5-read-api.md | 019fd8a4 | FAIL | twitter-kb FTS5 read API landed (server/data/index.db) | — |
| 06-browser-control-deferred.md | 019fd8a4 | SKIP | — | — |
| 07-prd-status-lifecycle.md | 019fd8a4 | PASS | — | — |
| 08-subagent-handover-hang-herdr.md | 019fd8a4 | FAIL | subagent handover hang fix (herdr present) | — |
| 09-large-documents-written-incrementally.md | 019fd8a4 | SKIP | — | — |
| 01-implementer-harness-host-cattle-container.md | 019fe7d2 | PASS | — | — |
| 02-durable-state-host-session-outside-container.md | 019fe7d2 | FAIL | durable state lives outside the container (~/.factory/runs + | — |
| 03-sandbox-on-workspace-portability.md | 019fe7d2 | PASS | — | — |
| 04-implementer-runtime-config-model-skills-extensions.md | 019fe7d2 | PASS | — | — |
| 05-implementer-lifecycle-traceability.md | 019fe7d2 | PASS | — | — |
| 01-implementer-false-kill-tool-liveness-session-continuation.md | 019fecde | PASS | — | — |
| 02-fix-silent-delivery-loss-git-identity.md | 019fecde | PASS | — | — |
| 03-pointer-map-not-bundle-agents-as-roster.md | 019fecde | PASS | — | — |
| 04-cleanup-shutdown-durable-disposable.md | 019fecde | PASS | — | — |
| 01-code-review-manual-trigger.md | 019ff79e | PASS | — | — |
| 02-code-review-archive-location.md | 019ff79e | PASS | — | — |
| 03-review-worker-read-only-git.md | 019ff79e | PASS | — | — |
| 04-ponytail-review-worker-skills.md | 019ff79e | FAIL | ponytail review-worker skills present (opensource/ponytail) | — |
| 05-review-never-merges.md | 019ff79e | PASS | — | — |
| 06-task-pr-tracking.md | 019ff79e | PASS | — | — |
| 07-merge-tool-operator-authority-split.md | 019ff79e | PASS | — | — |
| 08-implementer-revision-same-session.md | 019ff79e | PASS | — | — |
| 09-pick-prd-ready-only.md | 019ff79e | PASS | — | — |
| 10-mock-gh-reject-unknown-fields.md | 019ff79e | PASS | — | — |
| 11-merge-pr-requires-master-branch.md | 019ff79e | PASS | — | — |
| 12-manual-host-delivery-fallback.md | 019ff79e | PASS | — | — |
| 13-revise-cross-repo-uuid-join.md | 019ff79e | PASS | — | — |
| 01-ponytail-skills-fixed-mount.md | 01a005a8 | FAIL | ponytail skills fixed mount (opensource/ponytail present) | — |
| 02-opensource-restore-manifest-reclone.md | 01a005a8 | PASS | — | — |
| 01-capture-agent-followup-persistence-reconnect-fixes.md | 01a00610 | FAIL | capture agent followup/persistence/reconnect fixes landed (a | — |
| 01-headless-backend-host-scope.md | 01a00c50 | PASS | — | — |
| 02-merge-ready-deliverable.md | 01a00c50 | PASS | — | — |
| 03-github-actions-fast-path.md | 01a00c50 | PASS | — | — |
| 04-factory-run-headless-loop.md | 01a00c50 | PASS | — | — |
| 05-github-actions-free-execution-infra.md | 01a00c50 | PASS | — | — |
| 06-workflow-scope-gh-auth-pattern.md | 01a00c50 | PASS | — | — |
| 07-ci-tracking-sync-ephemeral-runners.md | 01a00c50 | PASS | — | — |
| 08-delivery-failure-loud.md | 01a00c50 | PASS | — | — |
| 09-code-master-pr-gate.md | 01a00c50 | FAIL | code lands on master only via PR (master merge-only enforced | — |
| 01-multi-repo-delivery-pr-shapes.md | 01a01515 | PASS | — | — |
| 02-branch-protection-merge-only.md | 01a01515 | FAIL | default branch is merge-only via GitHub branch protection | — |
| 03-local-first-herdr-execution-substrate.md | 01a01515 | FAIL | local-first herdr execution substrate (opensource/herdr) | — |
| 04-reviewer-verifies-production-wiring.md | 01a01515 | PASS | — | — |
| 05-evidence-stream-toolcall-delta-replay.md | 01a01515 | PASS | — | — |
| 06-langfuse-complete-session-retention.md | 01a01515 | PASS | — | — |
| 07-pr-dependency-invariant.md | 01a01515 | PASS | — | — |
| 01-langfuse-factory-eval-spine-decision-loop.md | 01a01a70 | SKIP | — | — |
| 02-eval-factory-department.md | 01a01a70 | PASS | — | — |
| 03-eval-feedback-target-context-engine.md | 01a01a70 | PASS | — | — |
| 01-ponytail-skills-fixed-mount-conditional-mount.md | 0ded66e7 | FAIL | ponytail skills fixed mount (opensource/ponytail present); p | — |
| 02-review-simulation-blind-spot-real-driver-bugs.md | 19cb853b | PASS | — | — |
| 03-label-seam-gh-pr-edit.md | 19cb853b | SKIP | — | — |
| 01-task-similarity-check-scope.md | 357a4c1d | PASS | — | — |
| 02-semantic-similarity-assessment.md | 357a4c1d | SKIP | — | — |
| 03-partial-split-remainder-registration.md | 357a4c1d | SKIP | — | — |
| 04-llm-credential-resolution-from-auth-json.md | 357a4c1d | PASS | — | — |
| 05-direct-implementation-for-assembly-line-self-repair.md | 357a4c1d | SKIP | — | — |
| 06-driver-sourcing-hazard.md | 357a4c1d | SKIP | — | — |
| 01-multi-repo-repo-key-resolution.md | 4d89a859 | SKIP | — | — |
| 02-loop-end-delivery-invariant.md | 4d89a859 | PASS | — | — |
| 01-extension-inline-agent.md | 60c0c537 | FAIL | inline-agent service + fetch_url tool present (agent-service | — |
| 05-headless-ci-gitignore-track-workflow.md | 771b4017 | PASS | — | — |
| 01-implementer-delivery-failure-loud.md | 82eae199 | PASS | — | — |
| 01-implementer-delivery-failure-loud.md | 8370f85b | PASS | — | — |
| 01-implementer-ponytail-test-env.md | 8483b243 | SKIP | — | — |
| 02-implementer-ponytail-restore-vanishing-scope.md | 8483b243 | SKIP | — | — |
| 01-delivery-failure-loud-gh-seam.md | afe61c92 | SKIP | — | — |
| 02-delivery-failure-loud-local-nounset.md | afe61c92 | SKIP | — | — |
| 01-pickup-similarity-merge.md | b77c5e2b | SKIP | — | — |
| 01-implementer-revision-test-seams.md | cb6a90c1 | PASS | — | — |
| 01-implementer-delivery-fail-loudly.md | d5492a5c | SKIP | — | — |
| 01-review-driver-gh-call-and-test-seam.md | d7a5fbb9 | PASS | — | — |

## Gaps

- (none)

_JSON: docs/evaluations/2026-08-22-decisions.json_

