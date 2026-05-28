---
name: survival-infrastructure-runtime
description: Start the Survival Infrastructure containers with the canonical startup script. Use when asked to run app-dev by default, or specific services like app-prod, app-prod-copy, hermes, or llm. The script automatically ensures the standalone llm container is running and ready first.
---

# Survival Infrastructure Runtime

Use this skill whenever the user asks to run the Survival Infrastructure application or one of its containers.

This skill only handles starting containers. For stop, restart, logs, or status operations, do not use start_stack.sh; defer to standard docker/compose commands or another skill.

## Preferred skill entrypoint

Use the bundled skill wrapper:

```bash
./start.sh
```

The wrapper delegates to the canonical project script at:

```bash
../../../survival-infrastructure/start_stack.sh
```

The relative path `../../../survival-infrastructure/start_stack.sh` is resolved from the current working directory; if that location is uncertain, use the absolute path `/home/anupam/Desktop/workspace/survival-infrastructure/start_stack.sh`.

## Default behavior

With no arguments, it starts:

- `app-dev`

and it first ensures:

- the standalone `llm` container is running
- the LLM runtime passes readiness checks

## Supported targets

Pass one or more of these targets when the user asks for a specific container:

- `app-dev`
- `app-prod`
- `app-prod-copy`
- `hermes`
- `llm`

Aliases accepted by the script:

- `dev` -> `app-dev`
- `prod` -> `app-prod`
- `prod-copy` -> `app-prod-copy`

If the user requests a target not in the supported list or aliases, ask for clarification rather than guessing or passing it through.

## Example commands

Default dev app:

```bash
./start.sh
```

Run prod copy:

```bash
./start.sh app-prod-copy
```

Run Hermes too:

```bash
./start.sh hermes
```

Run multiple targets:

```bash
./start.sh app-dev app-prod-copy
```

Start only the standalone LLM container:

```bash
./start.sh llm
```

## Operational notes

- Prefer this script over ad hoc `docker-compose` commands when starting Survival Infrastructure.
- The script validates `LLAMA_CPP_DIR`, ensures the shared Docker network exists, starts the standalone `llm` repo container if needed, then starts the requested Survival Infrastructure services.
- If `LLAMA_CPP_DIR` is unset or invalid, instruct the user to export `LLAMA_CPP_DIR` to the path of their llama.cpp checkout before re-running.
- The script verifies:
  - `http://127.0.0.1:8012/health`
  - `http://127.0.0.1:8012/ready`
  - app endpoints for requested app services
- If the script exits non-zero or readiness checks fail, surface the script's stderr to the user and do not retry automatically; suggest checking `LLAMA_CPP_DIR` and the `llm` container logs.
- If the user does not specify a target, default to running `app-dev`.
