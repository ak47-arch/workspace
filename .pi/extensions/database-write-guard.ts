/**
 * Database Write Guard Extension
 *
 * Intercepts write operations to any database and asks for confirmation.
 * Covers:
 *   - bash: SQL statements (INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, CREATE, REPLACE)
 *   - bash: Database CLI tools (psql, mysql, sqlite3, pgcli, mycli, mongo, redis-cli, etc.)
 *   - bash: ORM / migration tools (prisma, drizzle-kit, knex, typeorm, sequelize, hasura)
 *   - write/edit: Database file paths (.db, .sqlite, .sqlite3, .mdb, .frm, .ibd, .sql, etc.)
 */

import type { ExtensionAPI, ToolCallEvent } from "@earendil-works/pi-coding-agent";

// ── SQL write statement patterns ──────────────────────────────────────────────
const SQL_WRITE_PATTERNS = [
	/\bINSERT\s+(?:INTO\s+)?\w+/i,
	/\bUPDATE\s+\w+/i,
	/\bDELETE\s+FROM\s+\w+/i,
	/\bDROP\s+(?:TABLE|DATABASE|SCHEMA|VIEW|INDEX|TRIGGER|PROCEDURE|FUNCTION)\s+/i,
	/\bALTER\s+(?:TABLE|DATABASE|SCHEMA|VIEW|INDEX|TRIGGER|PROCEDURE|FUNCTION)\s+/i,
	/\bTRUNCATE\s+(?:TABLE\s+)?\w+/i,
	/\bCREATE\s+(?:TABLE|DATABASE|SCHEMA|VIEW|INDEX|TRIGGER|PROCEDURE|FUNCTION)\s+/i,
	/\bREPLACE\s+(?:INTO\s+)?\w+/i,
	/\bMERGE\s+INTO\s+/i,
	/\bUPSERT\b/i,
	/\bGRANT\s+/i,
	/\bREVOKE\s+/i,
	/\bRENAME\s+(?:TABLE|DATABASE|SCHEMA|COLUMN)\s+/i,
];

// ── Database CLI / ORM tool invocations ───────────────────────────────────────
// Each entry's `id` is used only for human-readable detail messages.
const DB_WRITE_TOOLS = [
	// SQL CLIs (any invocation is potentially a write, but we check for inline SQL)
	{ pattern: /\bpsql\b/, id: "psql" },
	{ pattern: /\bmysql\b/, id: "mysql" },
	{ pattern: /\bsqlite3\b/, id: "sqlite3" },
	{ pattern: /\bsqlcmd\b/, id: "sqlcmd" },
	{ pattern: /\bpgcli\b/, id: "pgcli" },
	{ pattern: /\bmycli\b/, id: "mycli" },
	{ pattern: /\bmssql-cli\b/, id: "mssql-cli" },
	{ pattern: /\bbq\s+query\b/, id: "bq query" },
	// NoSQL / cache
	{ pattern: /\bmongosh?\b/, id: "mongosh/mongo" },
	{ pattern: /\bmongoimport\b/, id: "mongoimport" },
	{ pattern: /\bredis-cli\b/, id: "redis-cli" },
	{ pattern: /\bcouchbase-cli\b/, id: "couchbase-cli" },
	{ pattern: /\bdynamodb-admin\b/, id: "dynamodb-admin" },
	// ORM / migration tools
	{ pattern: /\bprisma\s+(migrate|db\s+push|db\s+seed)\b/, id: "prisma" },
	{ pattern: /\bsequelize\s+(db:migrate|db:seed)/, id: "sequelize" },
	{ pattern: /\bknex\s+(migrate|seed)\b/, id: "knex" },
	{ pattern: /\bdrizzle-kit\s+(push|migrate|generate)\b/, id: "drizzle-kit" },
	{ pattern: /\btypeorm\s+(migration:run|schema:sync)\b/, id: "typeorm" },
	{ pattern: /\bhasura\s+(console|migrate|metadata)\b/, id: "hasura" },
	{ pattern: /\bmigrate\s+(up|down|redo|latest)\b/, id: "migrate CLI" },
	{ pattern: /\bgoose\s+(up|down|redo|status)\b/, id: "goose" },
	// Admin / import tools
	{ pattern: /\bmysqlimport\b/, id: "mysqlimport" },
	{ pattern: /\bpg_restore\b/, id: "pg_restore" },
	{ pattern: /\bpg_dump\b/, id: "pg_dump" },
	{ pattern: /\bmongorestore\b/, id: "mongorestore" },
];

// ── File extensions for database files ─────────────────────────────────────────
const DB_FILE_EXTENSIONS = [
	".db",
	".sqlite",
	".sqlite3",
	".sqlite2",
	".db3",
	".sdb",
	".frm",
	".ibd",
	".ibdata",
	".myd",
	".myi",
	".mdb",
	".accdb",
	".mdf",
	".ldf",
	".ndf",
	".dbf",
	".sql",
	".dump",
	".rdb",
	".aof",
	".wals",
	".wal",
	".shm",
];

// ── Helpers ────────────────────────────────────────────────────────────────────

/**
 * Commands that, when they precede a DB tool name in the same pipeline,
 * indicate the tool name is an argument / search term rather than an invocation.
 */
const SKIP_PARENT_COMMANDS = new Set([
	// Search / filter
	"grep", "egrep", "fgrep", "rg", "ag", "ack", "ripgrep",
	// Package management (listing/searching, not running the DB tool)
	"apt", "apt-get", "apt-cache", "dpkg", "dpkg-query", "dpkg-deb",
	"pip", "pip3", "npm", "yarn", "pnpm", "brew", "snap", "flatpak",
	"cargo", "gem", "bundle",
	// Output / display
	"echo", "printf", "cat", "head", "tail", "less", "more",
	// Introspection / docs
	"which", "whereis", "type", "command", "man", "info", "whatis",
	"file", "strings", "xxd", "od",
	// Text processing
	"sed", "awk", "sort", "uniq", "wc", "cut", "tr", "xargs",
	"find", "locate", "ls",
	// Build / test (DB tool name in dependency list)
	"make", "cmake", "go", "rustc",
	// Shell internals (dot-source; time/env/nohup DO run the named tool)
	".",
]);

/**
 * Scan forward to find the start of the current command segment
 * (the position just after the last unquoted |, ;, &&, or || before pos).
 * Also returns whether pos is inside a quoted string.
 */
function findSegmentAt(
	command: string,
	pos: number,
): { segmentStart: number; insideQuotes: boolean } {
	let depth = 0;
	let inSingle = false;
	let inDouble = false;
	let lastSegmentStart = 0;
	for (let i = 0; i < pos; i++) {
		const ch = command[i];
		if (inSingle) {
			if (ch === "'") inSingle = false;
			continue;
		}
		if (inDouble) {
			if (ch === '"') inDouble = false;
			continue;
		}
		if (ch === "'") { inSingle = true; continue; }
		if (ch === '"') { inDouble = true; continue; }
		if (ch === "(" || ch === "{") { depth++; continue; }
		if (ch === ")" || ch === "}") { depth--; continue; }
		if (depth === 0 && (ch === "|" || ch === ";" || ch === "&")) {
			// Consume a second consecutive & or | for && / ||
			if ((ch === "&" || ch === "|") && i + 1 < pos && command[i + 1] === ch) {
				i++;
			}
			lastSegmentStart = i + 1;
		}
	}
	return { segmentStart: lastSegmentStart, insideQuotes: inSingle || inDouble };
}

/**
 * Commands that wrap another command; we "see through" them to find the
 * actual command when checking against SKIP_PARENT_COMMANDS.
 */
const WRAPPER_COMMANDS = new Set(["sudo", "doas", "time", "env", "nohup", "nice", "ionice"]);

/**
 * Get the first non-option, non-wrapper word of the segment (the command name)
 * by scanning forward from segmentStart.
 */
function getSegmentCommand(command: string, segmentStart: number): string | undefined {
	const rest = command.slice(segmentStart).trimStart();
	const tokens = rest.split(/\s+/);
	let depth = 0;
	for (const token of tokens) {
		if (!token) continue;
		// Skip env var assignments like FOO=bar
		if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(token)) continue;
		// Skip flags
		if (token.startsWith("-")) continue;
		// Skip wrappers on the first pass only (you can't nest wrappers meaningfully)
		if (depth === 0 && WRAPPER_COMMANDS.has(token)) { depth++; continue; }
		return token;
	}
	return undefined;
}

/** Check whether a tool-name match is a genuine command invocation. */
function isGenuineInvocation(command: string, matchIndex: number): boolean {
	const { segmentStart, insideQuotes } = findSegmentAt(command, matchIndex);

	// Inside a quoted string → not a command invocation
	if (insideQuotes) return false;

	const beforeText = command.slice(segmentStart, matchIndex);
	const trimmed = beforeText.trimEnd();

	// No word before the match → tool name is the first word → invocation
	if (trimmed.length === 0) return true;

	// Check immediately preceding word for direct skip cases (which, man, grep, etc.)
	const lastSpace = trimmed.lastIndexOf(" ");
	const precedingWord = lastSpace === -1 ? trimmed : trimmed.slice(lastSpace + 1);
	if (SKIP_PARENT_COMMANDS.has(precedingWord)) return false;

	// If preceded by flags, walk back to find the actual preceding command word
	if (precedingWord.startsWith("-")) {
		const beforeFlag = lastSpace === -1 ? "" : trimmed.slice(0, lastSpace).trimEnd();
		if (beforeFlag) {
			const prevSpace = beforeFlag.lastIndexOf(" ");
			const cmdWord = prevSpace === -1 ? beforeFlag : beforeFlag.slice(prevSpace + 1);
			if (cmdWord && !cmdWord.startsWith("-") && SKIP_PARENT_COMMANDS.has(cmdWord)) {
				return false;
			}
		}
		// Ambiguous behind flags — conservatively assume invocation
		return true;
	}

	// For 'apt search mysql' style: check the first command word of the segment
	const segmentCmd = getSegmentCommand(command, segmentStart);
	if (segmentCmd && segmentCmd !== precedingWord && SKIP_PARENT_COMMANDS.has(segmentCmd)) {
		return false;
	}

	// The tool name follows an unknown word — it COULD be a wrapper (time, env, etc.)
	// Conservatively assume it's a genuine invocation
	return true;
}

/** Check if a bash command likely performs database writes. */
function detectDatabaseWrite(
	command: string,
): { match: boolean; detail: string } {
	// 1. Check for inline SQL write statements
	for (const pattern of SQL_WRITE_PATTERNS) {
		const m = command.match(pattern);
		if (m) {
			// Avoid false-positives on harmless identifiers like `create_directory`
			const keyword = m[0];
			// Skip if the keyword is part of a variable/function name
			const idx = m.index ?? 0;
			const before = command[idx - 1] ?? " ";
			if (/[a-zA-Z0-9_]/.test(before)) continue;
			return { match: true, detail: `SQL write statement "${keyword}"` };
		}
	}

	// 2. Check for database CLI / ORM tool invocations
	for (const tool of DB_WRITE_TOOLS) {
		// Create a global copy so matchAll iterates all occurrences
		const globalRe = new RegExp(tool.pattern.source, tool.pattern.flags.replace("g", "") + "g");
		for (const m of command.matchAll(globalRe)) {
			// For each match, verify it's a genuine command invocation
			if (isGenuineInvocation(command, m.index)) {
				return { match: true, detail: `DB tool "${tool.id}"` };
			}
		}
	}

	return { match: false, detail: "" };
}

/** Check if a file path targets a database file. */
function detectDatabaseFile(path: string): { match: boolean; detail: string } {
	const lower = path.toLowerCase();
	for (const ext of DB_FILE_EXTENSIONS) {
		if (lower.endsWith(ext)) {
			return { match: true, detail: `File type: ${ext}` };
		}
	}
	// Catch paths containing "database" or "db" in a data context
	if (
		/\b(?:databases?|db)\b/i.test(lower) &&
		!/\/(?:node_modules|\.git|__pycache__|vendor)\//.test(path)
	) {
		return {
			match: true,
			detail: "Path references a database directory",
		};
	}
	return { match: false, detail: "" };
}

/** Format an operation preview for the confirmation dialog. */
function formatPreview(input: string): string {
	const MAX = 500;
	if (input.length <= MAX) return input;
	return `${input.slice(0, MAX)}\n\n... [truncated, ${input.length - MAX} more chars]`;
}

// ── Extension ──────────────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
	// Allowlist: all DB writes allowed for remainder of the current turn
	let turnAllow = false;

	pi.on("turn_start", () => {
		turnAllow = false;
	});
	pi.on("turn_end", () => {
		turnAllow = false;
	});

	// ── bash tool ────────────────────────────────────────────────────────────
	pi.on("tool_call", async (event: ToolCallEvent, ctx) => {
		if (event.toolName === "bash") {
			const command = event.input.command as string;
			const { match, detail } = detectDatabaseWrite(command);

			if (!match) return undefined;
			if (turnAllow) return undefined;

			if (!ctx.hasUI) {
				return {
					block: true,
					reason: `Database write blocked (no UI for confirmation): ${detail}`,
				};
			}

			const preview = formatPreview(command);
			const choice = await ctx.ui.select(
				`🛡️  Database Write — ${detail}`,
				[
					`Allow once`,
					`Allow for this turn`,
					`Block`,
				],
			);

			if (choice === "Allow once") {
				ctx.ui.notify(`✅ Database write allowed`, "info");
				return undefined;
			}

			if (choice === "Allow for this turn") {
				ctx.ui.notify(`✅ DB writes allowed for this turn`, "info");
				turnAllow = true;
				return undefined;
			}

			return { block: true, reason: `Database write blocked by user: ${detail}` };
		}

		// ── write / edit tools ───────────────────────────────────────────────
		if (event.toolName === "write" || event.toolName === "edit") {
			const path = event.input.path as string;
			const { match, detail } = detectDatabaseFile(path);

			if (!match) return undefined;
			if (turnAllow) return undefined;

			if (!ctx.hasUI) {
				return {
					block: true,
					reason: `Database file write blocked (no UI for confirmation): ${detail}`,
				};
			}

			const choice = await ctx.ui.select(
				`🛡️  Database File Write — ${detail}`,
				[`Allow once`, `Block`],
			);

			if (choice === "Allow once") {
				ctx.ui.notify(`✅ Database file write allowed`, "info");
				return undefined;
			}

			return { block: true, reason: `Database file write blocked by user: ${detail}` };
		}

		return undefined;
	});
}