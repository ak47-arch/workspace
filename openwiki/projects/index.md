# Files

- [Feed Analyser (X Capture Instrument)](feed-analyser.md) - Restructured repo now led by the capture instrument — a thin Chrome MV3 extension plus a minimal local FastAPI server that saves X/Twitter posts and curated comments as recursive node trees in artefacts.jsonl. The legacy feed_analyser application is archived.
- [LLM Inference Server and Client](llm-server-client.md) - Centralized inference server (Flask) with pluggable providers and a uniform pip-installable workflow client used by all downstream apps.
- [Software Factory](software-factory.md) - The software factory paradigm governing the workspace — four components (context engine, product/architecture, project management, assembly line), the task lifecycle state machine with merge bundles, the PRD queue/archive gate, temporal metadata, the automated transition tooling, and the headless GitHub Actions loop (implement → review → revise → sync).
- [Survival Infrastructure](survival-infrastructure.md) - Personal intelligence pipeline — captures freeform event narratives, extracts structured data via LLM, stores people/event nodes, and synthesizes wiki pages.
