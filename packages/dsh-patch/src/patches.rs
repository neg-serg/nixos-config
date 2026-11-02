//! Patch tables for the dsh package build, one set per former `patch-*.py`.
//!
//! These strings are the anchors upstream's bundles carry; a dsh upgrade that
//! drifts one fails the build (the counts are asserted), so they are kept
//! verbatim rather than prettified.
//!
//! - `WIDGETS`: presentationMeta on the subagent/workflow/ralph tools and
//!   Session.append carrying `{ ignorable: true }`, so dsh-widgets cards have a
//!   structured descriptor and its bash_live events stop killing sessions.
//! - `SESSION_FORMAT`: released-0.1.x payloads (the permission/preset `origin`
//!   member, descriptor v2, ignorable plugin events) admitted by the v0->v1,
//!   v1->v2 and v2->v3 migrations and by the persistence worker.
//! - `SESSION_MIGRATION`: hold the steering-splice flag across the events that
//!   settle an aborted turn, and accept `next-step` splices as well.
//! - `PTC_ENV`: keep LD_LIBRARY_PATH in the PTC worker environment; the
//!   official Node build has no RPATH and workers died with exit 127.

use crate::engine::{Expected, FilePatch, Replacement};

pub const WIDGETS: &[FilePatch] = &[
    FilePatch {
        rel: r#"dsh-tool-subagent/lib/index.js"#,
        announce: true,
        replacements: &[Replacement {
            old: r#": outputValueText(value.output)
						}]
					},
					isConcurrencySafe: () => true,"#,
            new: r#": outputValueText(value.output)
						}],
					presentationMeta: (_args, value) => ({ kind: "subagent", result: value })
					},
					isConcurrencySafe: () => true,"#,
            expected: Expected::Count(1),
        }],
    },
    FilePatch {
        rel: r#"dsh-tool-workflow/lib/index.js"#,
        announce: true,
        replacements: &[Replacement {
            old: r#"renderResult(args.meta.name, value.agentsStarted, value.result, maxResultChars)
			}]
		},
		async execute(args, exec) {"#,
            new: r#"renderResult(args.meta.name, value.agentsStarted, value.result, maxResultChars)
			}],
			presentationMeta: (args, value) => ({
				kind: "workflow",
				runId: value.runId,
				agentsStarted: value.agentsStarted,
				result: value.result
			})
		},
		async execute(args, exec) {"#,
            expected: Expected::Count(1),
        }],
    },
    FilePatch {
        rel: r#"dsh-tool-ralph/lib/index.js"#,
        announce: true,
        replacements: &[Replacement {
            old: r#"text: renderResult(value.result, resolved.maxResultChars)
			}]
		},
		async execute(args, exec) {"#,
            new: r#"text: renderResult(value.result, resolved.maxResultChars)
			}],
			presentationMeta: (_args, value) => ({
				kind: "ralph",
				runId: value.runId,
				agentsStarted: value.agentsStarted,
				result: value.result
			})
		},
		async execute(args, exec) {"#,
            expected: Expected::Count(1),
        }],
    },
    FilePatch {
        rel: r#"dsh-session/lib/index.js"#,
        announce: true,
        replacements: &[Replacement {
            old: r#"		const surfaceMetadata = {
			...surfaceOpts?.sourceEventSeqs === void 0 ? {} : { sourceEventSeqs: surfaceOpts.sourceEventSeqs },
			...surfaceOpts?.surfaceOp === void 0 ? {} : { surfaceOp: surfaceOpts.surfaceOp }
		};"#,
            new: r#"		const surfaceMetadata = {
			...surfaceOpts?.sourceEventSeqs === void 0 ? {} : { sourceEventSeqs: surfaceOpts.sourceEventSeqs },
			...surfaceOpts?.surfaceOp === void 0 ? {} : { surfaceOp: surfaceOpts.surfaceOp },
			...surfaceOpts?.ignorable === true ? { ignorable: true } : {}
		};"#,
            expected: Expected::Count(1),
        }],
    },
];

pub const SESSION_FORMAT: &[FilePatch] = &[
    FilePatch {
        rel: r#"dsh-session-format-v0-to-v1/lib/index.js"#,
        announce: false,
        replacements: &[
            Replacement {
                old: r#"function normalizeLegacyTurnStart(event, sessionId) {"#,
                new: r#"/**
* Drop the legacy `origin` member from a `permission/preset` payload: released
* v0 (0.1.1) wrote { preset, origin } while the frozen inventory admits only
* `preset`, which made every such Session refuse to migrate.
*/
function normalizeLegacyPermissionPreset(event) {
	if (event.type !== "permission/preset") return event;
	const data = event.data;
	if (data === null || typeof data !== "object" || Array.isArray(data) || !Object.hasOwn(data, "origin")) return event;
	const { origin: _origin, ...preset } = data;
	return {
		...event,
		data: preset
	};
}

function normalizeLegacyTurnStart(event, sessionId) {"#,
                expected: Expected::Anchor(r#"permission/preset origin normalizer"#),
            },
            Replacement {
                old: r#"normalizeLegacyTurnStart(named, sessionId)"#,
                new: r#"normalizeLegacyTurnStart(normalizeLegacyPermissionPreset(named), sessionId)"#,
                expected: Expected::Anchor(r#"permission/preset normalizer chain"#),
            },
            Replacement {
                old: r#"function normalizeReleasedV0Event(event, sessionId, state) {
	const named = normalizeLegacyCompactionType(event);"#,
                new: r#"/**
* Promote a legacy v2 `subagent/descriptor` payload to the current v3
* vocabulary: v3 only added the optional `agentReasoningEffort` field, so the
* version stamp is the whole delta. 0.1.1 stamped v2 and the frozen v0
* inventory demands v3, so every Session holding a subagent descriptor refused
* to migrate.
*/
function normalizeLegacySubagentDescriptor(event) {
	if (event.type !== "subagent/descriptor") return event;
	const data = event.data;
	if (data === null || typeof data !== "object" || Array.isArray(data) || data.version !== 2) return event;
	return {
		...event,
		data: {
			...data,
			version: 3
		}
	};
}

function normalizeReleasedV0Event(event, sessionId, state) {
	const named = normalizeLegacyCompactionType(normalizeLegacySubagentDescriptor(event));"#,
                expected: Expected::Anchor(r#"subagent/descriptor v2 normalizer"#),
            },
            Replacement {
                old: r#"		const ignorableCurrent = !allowLegacySteering && !currentKnown && record["ignorable"] === true;"#,
                new: r#"		const ignorableCurrent = !currentKnown && record["ignorable"] === true;"#,
                expected: Expected::Anchor(r#"ignorable-unknown coordinate admission"#),
            },
            Replacement {
                old: r#"	transformEvent(event, context) {
		const normalized = normalizeReleasedV0Event(event, this.input.sourceHeader.id, this.state);"#,
                new: r#"	transformEvent(event, context) {
		/* A plugin-owned event the frozen v0 inventory does not know, written
		 * with `ignorable: true`, is passed through unchanged: the current
		 * read side already tolerates that shape, and dropping it here would
		 * leave a seq gap the target artifact rejects. */
		if (event["ignorable"] === true && RELEASED_V0_EVENT_DISPOSITIONS[event.type] === void 0) {
			context.emitEvent(event);
			return;
		}
		const normalized = normalizeReleasedV0Event(event, this.input.sourceHeader.id, this.state);"#,
                expected: Expected::Anchor(r#"ignorable-unknown pass-through"#),
            },
        ],
    },
    FilePatch {
        rel: r#"dsh-session-format-v1-to-v2/lib/index.js"#,
        announce: false,
        replacements: &[Replacement {
            old: r#"	if (RELEASED_V0_EVENT_DISPOSITIONS[event.type] === void 0) throw refusal(`format v1 contains unknown event type ${JSON.stringify(event.type)} at seq ${event.seq}`);"#,
            new: r#"	if (RELEASED_V0_EVENT_DISPOSITIONS[event.type] === void 0) {
		/* A plugin-owned event the frozen inventory does not know, written with
		 * `ignorable: true`, is passed through unchanged; the v2/v3 admission
		 * already tolerates that shape. */
		if (event["ignorable"] === true) {
			emitSource(state, event, context);
			return;
		}
		throw refusal(`format v1 contains unknown event type ${JSON.stringify(event.type)} at seq ${event.seq}`);
	}"#,
            expected: Expected::Anchor(r#"format v1 unknown-event admission"#),
        }],
    },
    FilePatch {
        rel: r#"dsh-session-format-v2-to-v3/lib/index.js"#,
        announce: false,
        replacements: &[Replacement {
            old: r#"	if (disposition === void 0 && !feedback) throw new SessionFormatUnsupportedMigrationError("format v2 to v3 cannot safely transform unclassified event " + event.type);"#,
            new: r#"	if (disposition === void 0 && !feedback) {
		/* A plugin-owned `ignorable` event this stage cannot classify is opaque,
		 * not a failure — the same tolerance the v3 admission already has. */
		if (event["ignorable"] === true) return;
		throw new SessionFormatUnsupportedMigrationError("format v2 to v3 cannot safely transform unclassified event " + event.type);
	}"#,
            expected: Expected::Anchor(r#"format v2 unclassified-event admission"#),
        }],
    },
    FilePatch {
        rel: r#"dsh-session-persistence-jsonl/lib/worker.cjs"#,
        announce: false,
        replacements: &[
            Replacement {
                old: r#"function normalizeLegacyTurnStart(event, sessionId) {"#,
                new: r#"/**
* Drop the legacy `origin` member from a `permission/preset` payload: released
* v0 (0.1.1) wrote { preset, origin } while the frozen inventory admits only
* `preset`, which made every such Session refuse to migrate.
*/
function normalizeLegacyPermissionPreset(event) {
	if (event.type !== "permission/preset") return event;
	const data = event.data;
	if (data === null || typeof data !== "object" || Array.isArray(data) || !Object.hasOwn(data, "origin")) return event;
	const { origin: _origin, ...preset } = data;
	return {
		...event,
		data: preset
	};
}

function normalizeLegacyTurnStart(event, sessionId) {"#,
                expected: Expected::Anchor(r#"permission/preset origin normalizer"#),
            },
            Replacement {
                old: r#"normalizeLegacyTurnStart(named, sessionId)"#,
                new: r#"normalizeLegacyTurnStart(normalizeLegacyPermissionPreset(named), sessionId)"#,
                expected: Expected::Anchor(r#"permission/preset normalizer chain"#),
            },
            Replacement {
                old: r#"function normalizeReleasedV0Event(event, sessionId, state) {
	const named = normalizeLegacyCompactionType(event);"#,
                new: r#"/**
* Promote a legacy v2 `subagent/descriptor` payload to the current v3
* vocabulary: v3 only added the optional `agentReasoningEffort` field, so the
* version stamp is the whole delta. 0.1.1 stamped v2 and the frozen v0
* inventory demands v3, so every Session holding a subagent descriptor refused
* to migrate.
*/
function normalizeLegacySubagentDescriptor(event) {
	if (event.type !== "subagent/descriptor") return event;
	const data = event.data;
	if (data === null || typeof data !== "object" || Array.isArray(data) || data.version !== 2) return event;
	return {
		...event,
		data: {
			...data,
			version: 3
		}
	};
}

function normalizeReleasedV0Event(event, sessionId, state) {
	const named = normalizeLegacyCompactionType(normalizeLegacySubagentDescriptor(event));"#,
                expected: Expected::Anchor(r#"subagent/descriptor v2 normalizer"#),
            },
            Replacement {
                old: r#"	if (RELEASED_V0_EVENT_DISPOSITIONS[event.type] === void 0) throw refusal(`format v1 contains unknown event type ${JSON.stringify(event.type)} at seq ${event.seq}`);"#,
                new: r#"	if (RELEASED_V0_EVENT_DISPOSITIONS[event.type] === void 0) {
		/* A plugin-owned event the frozen inventory does not know, written with
		 * `ignorable: true`, is passed through unchanged; the v2/v3 admission
		 * already tolerates that shape. */
		if (event["ignorable"] === true) {
			emitSource(state, event, context);
			return;
		}
		throw refusal(`format v1 contains unknown event type ${JSON.stringify(event.type)} at seq ${event.seq}`);
	}"#,
                expected: Expected::Anchor(r#"format v1 unknown-event admission"#),
            },
            Replacement {
                old: r#"	if (disposition === void 0 && !feedback) throw new SessionFormatUnsupportedMigrationError("format v2 to v3 cannot safely transform unclassified event " + event.type);"#,
                new: r#"	if (disposition === void 0 && !feedback) {
		/* A plugin-owned `ignorable` event this stage cannot classify is opaque,
		 * not a failure — the same tolerance the v3 admission already has. */
		if (event["ignorable"] === true) return;
		throw new SessionFormatUnsupportedMigrationError("format v2 to v3 cannot safely transform unclassified event " + event.type);
	}"#,
                expected: Expected::Anchor(r#"format v2 unclassified-event admission"#),
            },
        ],
    },
];

pub const SESSION_MIGRATION: &[FilePatch] = &[FilePatch {
    rel: r#"dsh-session-format-v3-to-v4/lib/index.js"#,
    announce: false,
    replacements: &[Replacement {
        old: r#"		this.nextTurnSpliced = event.type === "agent/inbox/spliced" && isSessionFormatJsonObject(data) && data["target"] === "next-turn" && Array.isArray(data["inserted"]) && data["inserted"].length > 0;"#,
        new: r#"		/* A steering splice is consumed by the restarting turn/start; the events
		 * that settle the aborted turn (assistant/attempt, step/end) must not clear
		 * it, or the synthetic turn/end below is skipped and the v4 reader refuses
		 * the artifact. Reset on the next turn boundary instead. */
		if (event.type === "agent/inbox/spliced" && isSessionFormatJsonObject(data) && (data["target"] === "next-turn" || data["target"] === "next-step") && Array.isArray(data["inserted"]) && data["inserted"].length > 0) this.nextTurnSpliced = true;
		else if (event.type === "turn/start" || event.type === "turn/end") this.nextTurnSpliced = false;"#,
        expected: Expected::Anchor(r#"v3->v4 interrupted-restart splice flag"#),
    }],
}];

pub const PTC_ENV: &[FilePatch] = &[FilePatch {
    rel: r#"dsh-ptc-runtime-node/lib/index.js"#,
    announce: true,
    replacements: &[Replacement {
        old: r#"const env = Object.fromEntries(Object.keys(process.env).filter((key) => !STARTUP_ENVIRONMENT_NAMES.has(key.toUpperCase()) && key.toUpperCase() !== "ELECTRON_RUN_AS_NODE").map((key) => [key, void 0]));"#,
        new: r#"const env = Object.fromEntries(Object.keys(process.env).filter((key) => !STARTUP_ENVIRONMENT_NAMES.has(key.toUpperCase()) && key.toUpperCase() !== "ELECTRON_RUN_AS_NODE").map((key) => [key, key.toUpperCase() === "LD_LIBRARY_PATH" ? process.env[key] : void 0]));"#,
        expected: Expected::Count(1),
    }],
}];

/// Printed once a set applied cleanly (the former scripts' final line).
pub const WIDGETS_DONE: &str = r#"patch-widgets: all patches applied cleanly"#;
pub const SESSION_FORMAT_DONE: &str = r#"patch-session-format: released-0.1.x payloads (permission/preset origin, descriptor v2, ignorable plugin events) now migrate"#;
pub const SESSION_MIGRATION_DONE: &str = r#"patch-session-migration: v3->v4 abandoned turns after a next-turn/next-step splice now synthesize their missing turn/end and migrate"#;
