/**
 * Ask for permission before code is committed or pushed.
 *
 * Covers:
 * - agent bash tool calls
 * - user `!` / `!!` shell commands
 *
 * Approved `git commit` commands automatically push with `&& git push`.
 * Standalone `git push` commands still require approval.
 *
 * Auto-discovered from .pi/extensions/ and reloadable with /reload.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createLocalBashOperations } from "@earendil-works/pi-coding-agent";

function wantsGitCommit(command: string): boolean {
	return /\bgit\s+commit\b/i.test(command);
}

function wantsGitPush(command: string): boolean {
	return /\bgit\s+push\b/i.test(command);
}

function withAutomaticPush(command: string): string {
	return wantsGitPush(command) ? command : `${command} && git push`;
}

async function confirmAction(
	title: string,
	message: string,
	ctx: {
		hasUI: boolean;
		ui: {
			confirm(title: string, message: string): Promise<boolean>;
			notify(message: string, level: "info" | "warning" | "error"): void;
		};
	},
) {
	if (!ctx.hasUI) {
		return false;
	}

	return ctx.ui.confirm(title, message);
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return;

		const command = String(event.input.command ?? "");
		if (wantsGitCommit(command)) {
			const approvedCommand = withAutomaticPush(command);
			const confirmed = await confirmAction(
				"Commit and push code?",
				`A git commit was requested:\n\n${command}\n\nIf approved, pi will run:\n\n${approvedCommand}\n\nAllow it?`,
				ctx,
			);
			if (!confirmed) {
				if (ctx.hasUI) {
					ctx.ui.notify("Blocked git commit command", "warning");
				}
				return {
					block: true,
					reason: ctx.hasUI
						? "Blocked by user"
						: "git commit blocked because confirmation is unavailable in this mode.",
				};
			}

			event.input.command = approvedCommand;
			return;
		}

		if (!wantsGitPush(command)) return;

		const confirmed = await confirmAction(
			"Push code?",
			`A git push was requested:\n\n${command}\n\nAllow it?`,
			ctx,
		);
		if (!confirmed) {
			if (ctx.hasUI) {
				ctx.ui.notify("Blocked git push command", "warning");
			}
			return {
				block: true,
				reason: ctx.hasUI
					? "Blocked by user"
					: "git push blocked because confirmation is unavailable in this mode.",
			};
		}
	});

	pi.on("user_bash", async (event, ctx) => {
		const command = String(event.command ?? "");
		if (wantsGitCommit(command)) {
			const approvedCommand = withAutomaticPush(command);
			const confirmed = await confirmAction(
				"Commit and push code?",
				`A git commit was requested:\n\n${command}\n\nIf approved, pi will run:\n\n${approvedCommand}\n\nAllow it?`,
				ctx,
			);
			if (!confirmed) {
				if (ctx.hasUI) {
					ctx.ui.notify("Blocked git commit command", "warning");
				}
				return {
					result: {
						output: ctx.hasUI
							? "git commit cancelled by user"
							: "git commit blocked because confirmation is unavailable in this mode",
						exitCode: 1,
						cancelled: true,
						truncated: false,
					},
				};
			}

			const local = createLocalBashOperations();
			return {
				operations: {
					exec(runCommand, cwd, options) {
						return local.exec(withAutomaticPush(runCommand), cwd, options);
					},
				},
			};
		}

		if (!wantsGitPush(command)) return;

		const confirmed = await confirmAction(
			"Push code?",
			`A git push was requested:\n\n${command}\n\nAllow it?`,
			ctx,
		);
		if (confirmed) return;

		if (ctx.hasUI) {
			ctx.ui.notify("Blocked git push command", "warning");
		}

		return {
			result: {
				output: ctx.hasUI
					? "git push cancelled by user"
					: "git push blocked because confirmation is unavailable in this mode",
				exitCode: 1,
				cancelled: true,
				truncated: false,
			},
		};
	});
}
