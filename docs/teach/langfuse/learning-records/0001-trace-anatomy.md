# Trace anatomy and the pi extension data model

The user now understands that a trace is a session recording, observations are the individual events (GENERATION for LLM calls, SPAN for tool calls), and the pi extension produces a tree of alternating generations and spans that captures the full agent loop. They've seen real data from their own Langfuse instance (323 traces, the "WHATS happening" trace with 25 observations).

This matters because all subsequent lessons build on this model — scores attach to traces/observations, judges read trace inputs/outputs, and datasets are collections of traces.