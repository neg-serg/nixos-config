/**
 * Pure, dependency-free logic for dsh-plugin-recall.
 *
 * `recall` gives the model a cross-session memory: it full-text searches the
 * harness's own session history (via `ctx.sessionQuery.searchSessions`, backed
 * by SQLite FTS5) and brings the strongest matching excerpts back into the
 * current context. This module owns argument validation, request building,
 * and rendering so it can be unit-tested without a running harness
 * (see test/recall.test.mjs).
 *
 * @module dsh-plugin-recall/recall
 */

/** Maximum query length in characters. */
export const MAX_QUERY_LENGTH = 500;
/** Default number of session hits to return. */
export const DEFAULT_LIMIT = 5;
/** Hard cap on returned hits. */
export const MAX_LIMIT = 20;
/** Cap on session-id filters in one call. */
export const MAX_SESSION_IDS = 50;

/**
 * Validate `recall` tool arguments.
 * @param args - raw tool arguments.
 * @returns an error string, or null when acceptable.
 */
export function validateRecallArgs(args) {
	const query = args?.query;
	if (typeof query !== "string" || query.trim().length === 0) return "query must be a non-empty string";
	if (query.length > MAX_QUERY_LENGTH) return `query too long (${query.length} > ${MAX_QUERY_LENGTH} chars)`;
	if (query.includes("\0")) return "query must not contain NUL bytes";
	const limit = args?.limit;
	if (limit !== undefined && limit !== null) {
		if (!Number.isInteger(limit) || limit < 1 || limit > MAX_LIMIT) return `limit must be an integer in 1..${MAX_LIMIT}`;
	}
	const sessionIds = args?.sessionIds;
	if (sessionIds !== undefined && sessionIds !== null) {
		if (!Array.isArray(sessionIds)) return "sessionIds must be an array of session id strings";
		if (sessionIds.length === 0) return "sessionIds must not be empty";
		if (sessionIds.length > MAX_SESSION_IDS) return `sessionIds must not exceed ${MAX_SESSION_IDS} entries`;
		for (const id of sessionIds) {
			if (typeof id !== "string" || id.length === 0 || id.includes("\0")) return "each session id must be a non-empty string without NUL bytes";
		}
	}
	return null;
}

/**
 * Build the `ctx.sessionQuery.searchSessions` request from validated args.
 * @param args - validated tool arguments.
 * @returns a SessionSearchRequest-shaped plain object.
 */
export function buildSearchRequest(args) {
	const request = {
		query: args.query.trim(),
		limit: args.limit === undefined || args.limit === null ? DEFAULT_LIMIT : args.limit
	};
	if (args.sessionIds !== undefined && args.sessionIds !== null && args.sessionIds.length > 0) {
		request.sessionFilters = [{ kind: "id", values: [...args.sessionIds] }];
	}
	return request;
}

/**
 * Map one `SessionSearchHit` (a live service record) to a small plain record
 * safe for tool output. Never copies live objects.
 * @param hit - one search hit from `searchSessions`.
 * @returns `{ sessionId, live, persisted, time, type, snippet }`.
 */
export function toPlainHit(hit) {
	const best = hit.bestMatch;
	return {
		sessionId: best.sessionId ?? hit.header?.id ?? null,
		live: hit.live === true,
		persisted: hit.persisted === true,
		time: typeof best.time === "number" ? best.time : null,
		type: best.type ?? null,
		snippet: typeof best.snippet === "string" ? best.snippet : ""
	};
}

/** Format an epoch-ms timestamp as a short local ISO string. */
export function formatTime(time) {
	if (time === null || time === undefined) return "?";
	return new Date(time).toISOString();
}

/**
 * Render recall results into a text block.
 * @param query - the search query.
 * @param hits - plain hit records (from toPlainHit).
 * @returns a text block.
 */
export function renderHits(query, hits) {
	if (hits.length === 0) return `# recall: "${query}"\n\nNo matching sessions found. Try a different phrase.`;
	const lines = [`# recall: "${query}" (${hits.length} ${hits.length === 1 ? "hit" : "hits"})`, ""];
	hits.forEach((hit, index) => {
		lines.push(`${index + 1}. session ${hit.sessionId ?? "?"} · ${formatTime(hit.time)} · ${hit.type ?? "?"}${hit.live ? " · live" : ""}`);
		lines.push(`   ${hit.snippet}`);
	});
	return lines.join("\n");
}

/**
 * Render the "service unavailable" message.
 * @returns a text block.
 */
export function renderUnavailable() {
	return "recall is unavailable: ctx.sessionQuery is not mounted. Mount the standard web profile (it includes @deepseek-ai/dsh-session-query-sqlite) or add a sessionQuery provider to this composition.";
}
