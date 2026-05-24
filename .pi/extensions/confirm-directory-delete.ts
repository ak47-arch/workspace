/**
 * Ask for permission before the agent runs a bash command that deletes a directory.
 *
 * Auto-discovered from .pi/extensions/ and reloadable with /reload.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function deletesDirectory(command: string): boolean {
	return /\brmdir\b/i.test(command)
		|| (/\brm\b/i.test(command)
			&& (/(^|\s)--recursive(\s|$)/i.test(command)
				|| /(^|\s)--dir(\s|$)/i.test(command)
				|| /(^|\s)-[^\s]*r[^\s]*(\s|$)/i.test(command)
				|| /(^|\s)-[^\s]*d[^\s]*(\s|$)/i.test(command)));
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return;

		const command = String(event.input.command ?? "");
		if (!deletesDirectory(command)) return;

		if (!ctx.hasUI) {
			return {
				block: true,
				reason: "Directory deletion blocked because confirmation is unavailable in this mode.",
			};
		}

		const confirmed = await ctx.ui.confirm(
			"Delete directory?",
			`The agent wants to run a command that may delete a directory:\n\n${command}\n\nAllow it?`,
		);

		if (!confirmed) {
			ctx.ui.notify("Blocked directory deletion command", "warning");
			return { block: true, reason: "Blocked by user" };
		}
	});
}
