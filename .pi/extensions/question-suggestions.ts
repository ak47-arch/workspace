/**
 * Question Suggestions Extension
 *
 * When the user asks a question (contains `?` outside of code blocks,
 * inline code spans, or quoted strings), the agent answers the question
 * and then suggests 2-4 possible next steps under "### Suggested Actions".
 *
 * This is purely additive — it does not constrain tool use or modify the
 * system prompt. Full agent autonomy is preserved.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const SUGGESTION_INSTRUCTION =
  '\n\nAfter answering, suggest 2-4 possible next steps under "### Suggested Actions".';

/**
 * Strip code blocks (```...```), inline code spans (`...`), and quoted
 * strings ("..." and '...') from the text before checking for `?`.
 */
function stripCodeAndQuotes(text: string): string {
  return (
    text
      // Fenced code blocks: ``` ... ```
      .replace(/```[\s\S]*?```/g, "")
      // Inline code spans: `...`
      .replace(/`[^`]*`/g, "")
      // Double-quoted strings: "..."
      .replace(/"[^"]*"/g, "")
      // Single-quoted strings: '...'
      .replace(/'[^']*'/g, "")
  );
}

function isQuestion(text: string): boolean {
  return stripCodeAndQuotes(text).includes("?");
}

export default function (pi: ExtensionAPI) {
  pi.on("input", async (event, ctx) => {
    // Never transform extension-injected messages
    if (event.source === "extension") {
      return { action: "continue" };
    }

    if (isQuestion(event.text)) {
      return {
        action: "transform",
        text: event.text + SUGGESTION_INSTRUCTION,
      };
    }

    return { action: "continue" };
  });
}
