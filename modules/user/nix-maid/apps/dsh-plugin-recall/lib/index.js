/**
 * @deepseek-ai/dsh-plugin-recall — a DeepSeek Harness host plugin that gives
 * the model a cross-session memory.
 *
 * The harness already persists every session and indexes the corpus with
 * SQLite FTS5 (`ctx.sessionQuery.searchSessions`), but no model-facing tool
 * reads it — a session starts with zero knowledge of what earlier sessions
 * decided, tried, or learned. This plugin adds:
 *
 *  - the `recall` tool — full-text search across all past sessions, returning
 *    the strongest matching excerpts so the model can pick up where a previous
 *    session left off, and
 *  - the `/recall` command — the same search for a human.
 *
 * Queries are treated as literal phrases (never executable FTS syntax), results
 * are plain JSON snapshots (session id, time, event type, snippet), and the
 * service is optional: without `ctx.sessionQuery` the tools fail with a clear
 * explanation instead of breaking the composition.
 *
 * Mount it in a profile patch or agent preset:
 *   - id: recall
 *     name: dsh-plugin-recall
 *
 * @module dsh-plugin-recall
 */
import {
	buildSearchRequest,
	renderHits,
	renderUnavailable,
	toPlainHit,
	validateRecallArgs
} from "./recall.js";

/** Stable Cordis plugin name. */
const name = "recall";
/** Hard dependency: the tool registry. sessionQuery is read optionally. */
const inject = ["tools"];

/** Run one recall search; returns `{ ok, hits?, message? }` plain output. */
async function performRecall(ctx, args) {
	const error = validateRecallArgs(args);
	if (error) return { ok: false, message: error };
	const sessionQuery = ctx.get("sessionQuery");
	if (sessionQuery === undefined) return { ok: false, message: renderUnavailable() };
	try {
		const page = await sessionQuery.searchSessions(buildSearchRequest(args));
		return { ok: true, query: args.query.trim(), hits: page.items.map(toPlainHit) };
	} catch (error) {
		return { ok: false, message: `recall failed: ${error instanceof Error ? error.message : String(error)}` };
	}
}

/**
 * Register the `recall` tool and the `/recall` command.
 * @param ctx - host plugin context (provides `tools`, optional `sessionQuery`, `commands`).
 */
function apply(ctx) {
	const definition = {
		name: "recall",
		description: "Search the harness's own session history (all past sessions, full-text) and return the strongest matching excerpts. Use it to remember earlier decisions, code, commands, or mistakes from previous sessions before starting work. Queries are literal phrases — quote exact wording.",
		parameters: {
			type: "object",
			properties: {
				query: {
					type: "string",
					description: "Literal phrase to search for in past session history (required, max 500 characters)."
				},
				limit: {
					type: "number",
					description: "Maximum number of sessions to return (default 5, cap 20)."
				},
				sessionIds: {
					type: "array",
					items: { type: "string" },
					description: "Optional session ids to restrict the search to."
				}
			},
			required: ["query"]
		},
		output: {
			schema: {
				type: "object",
				additionalProperties: false,
				properties: {
					ok: { type: "boolean" },
					query: { type: "string" },
					hits: {
						type: "array",
						items: {
							type: "object",
							additionalProperties: false,
							properties: {
								sessionId: { type: "string" },
								live: { type: "boolean" },
								persisted: { type: "boolean" },
								time: { type: "number" },
								type: { type: "string" },
								snippet: { type: "string" }
							}
						}
					},
					message: { type: "string" }
				}
			},
			render: (args, value) => [{ type: "text", text: value.ok ? renderHits(value.query, value.hits) : value.message }]
		},
		timeoutMs: 30000,
		async execute(args) {
			return performRecall(ctx, args);
		}
	};
	ctx.effect(() => ctx.tools.register(definition), "recall: tool");

	const commands = ctx.get("commands");
	if (commands !== undefined) {
		ctx.effect(() => commands.register({
			name: "recall",
			description: "Full-text search past sessions and print the strongest matching excerpts",
			handler: async (args) => {
				const query = typeof args === "string" && args.trim().length > 0 ? args.trim() : undefined;
				const result = await performRecall(ctx, { query });
				return { kind: "success", text: result.ok ? renderHits(result.query, result.hits) : result.message };
			}
		}), "recall: command");
	}
}

export { apply, inject, name };
