---
name: langfuse-tracing
description: Langfuse observability for pi agent traces — integration overview and recovery.
disable-model-invocation: true
---

# Langfuse Tracing

The pi extension at `.pi/extensions/langfuse-tracing.ts` pushes every agent turn (LLM calls + tool usage) to a self-hosted Langfuse instance at `opensource/langfuse/` (podman behind `DOCKER_HOST=unix:///run/user/1000/podman/podman.sock`). Credentials are in `.env.langfuse` and must match the `LANGFUSE_INIT_PROJECT_*` vars in `opensource/langfuse/.env`. If things go sideways, check container logs (`docker-compose logs langfuse-web`), verify the API responds at `http://localhost:3000/api/public/health`, and ensure the Basic auth header isn’t split by base64 line wrapping.