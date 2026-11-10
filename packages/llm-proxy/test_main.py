#!/usr/bin/env python3
"""Unit tests for the proxy guards; run by the package checkPhase.

`main.py` is a script, not an importable module, so it is loaded by path.
Everything here is stdlib: the package has no test dependencies and the
build sandbox has no network.
"""

import importlib.util
import json
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "llm_proxy_main", HERE / "main.py"
)
lp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lp)

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "sh",
            "description": "run a command",
            "parameters": {
                "type": "object",
                "properties": {"command": {"type": "string"}},
                "required": ["command"],
            },
        },
    }
]


def tool_turn(n, size=200):
    """One assistant tool call plus the tool result that answers it."""
    return [
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {
                    "id": f"call{n}",
                    "type": "function",
                    "function": {
                        "name": "sh",
                        "arguments": json.dumps({"command": f"echo {n}"}),
                    },
                }
            ],
        },
        {
            "role": "tool",
            "tool_call_id": f"call{n}",
            "name": "sh",
            "content": "x" * size,
        },
    ]


def conversation(turns=12, size=200):
    msgs = [
        {"role": "system", "content": "SYSTEM"},
        {"role": "user", "content": "do the thing"},
    ]
    for n in range(turns):
        msgs.extend(tool_turn(n, size))
    return msgs


def paired(messages):
    """Every assistant tool_call is directly followed by its tool results."""
    i = 0
    while i < len(messages):
        m = messages[i]
        calls = m.get("tool_calls") or []
        if m.get("role") == "assistant" and calls:
            ids = [c["id"] for c in calls]
            following = messages[i + 1 : i + 1 + len(ids)]
            if [t.get("tool_call_id") for t in following] != ids:
                return False
            if any(t.get("role") != "tool" for t in following):
                return False
            i += 1 + len(ids)
            continue
        i += 1
    return True


class SingleToolRule(unittest.TestCase):
    def test_merges_into_the_client_system_prompt(self):
        msgs = [
            {"role": "system", "content": "S"},
            {"role": "user", "content": "U"},
        ]
        out = lp.inject_single_tool_rule(msgs, True)
        self.assertEqual(1, sum(m["role"] == "system" for m in out))
        self.assertTrue(out[0]["content"].startswith("S"))
        self.assertIn(lp.SINGLE_TOOL_RULE, out[0]["content"])

    def test_does_not_mutate_the_caller(self):
        msgs = [{"role": "system", "content": "S"}]
        lp.inject_single_tool_rule(msgs, True)
        self.assertEqual("S", msgs[0]["content"])

    def test_prepends_only_without_a_system_message(self):
        out = lp.inject_single_tool_rule(
            [{"role": "user", "content": "U"}], True
        )
        self.assertEqual(["system", "user"], [m["role"] for m in out])

    def test_rule_already_present_is_not_duplicated(self):
        msgs = [{"role": "system", "content": lp.SINGLE_TOOL_RULE}]
        self.assertEqual(1, len(lp.inject_single_tool_rule(msgs, True)))

    def test_disabled_returns_the_same_object(self):
        msgs = [{"role": "user", "content": "U"}]
        self.assertIs(msgs, lp.inject_single_tool_rule(msgs, False))

    def test_list_content_gets_an_extra_text_part(self):
        msgs = [{"role": "system", "content": [{"type": "text", "text": "S"}]}]
        out = lp.inject_single_tool_rule(msgs, True)
        parts = out[0]["content"]
        self.assertEqual(2, len(parts))
        self.assertEqual(lp.SINGLE_TOOL_RULE, parts[1]["text"])

    def test_injects_into_the_first_system_message_only(self):
        # The rule must not add a system message of its own: the Mistral/
        # Devstral template rejects a `system` role that is not first, which
        # turned every guarded request into an HTTP 500. Two system messages
        # sent by the client are the client's own bug and stay untouched.
        msgs = [
            {"role": "system", "content": "A"},
            {"role": "system", "content": "B"},
            {"role": "user", "content": "U"},
        ]
        out = lp.inject_single_tool_rule(msgs, True)
        self.assertEqual(2, sum(m["role"] == "system" for m in out))
        self.assertIn(lp.SINGLE_TOOL_RULE, out[0]["content"])
        self.assertEqual("B", out[1]["content"])


class ToolResults(unittest.TestCase):
    def test_unwraps_the_result_wrapper(self):
        msgs = [
            {
                "role": "assistant",
                "tool_calls": [
                    {"id": "c1", "function": {"name": "sh", "arguments": "{}"}}
                ],
            },
            {
                "role": "tool",
                "tool_call_id": "c1",
                "content": '{"result": 42}',
            },
        ]
        out = lp.normalize_tool_results(msgs)
        self.assertEqual("42", out[1]["content"])

    def test_adds_the_missing_name(self):
        msgs = [
            {
                "role": "assistant",
                "tool_calls": [
                    {"id": "c1", "function": {"name": "sh", "arguments": "{}"}}
                ],
            },
            {"role": "tool", "tool_call_id": "c1", "content": "plain"},
        ]
        self.assertEqual("sh", lp.normalize_tool_results(msgs)[1]["name"])

    def test_plain_text_and_other_roles_are_untouched(self):
        msgs = [
            {"role": "assistant", "content": "hello"},
            {
                "role": "tool",
                "tool_call_id": "c9",
                "content": "no wrapper {x}",
            },
        ]
        out = lp.normalize_tool_results(msgs)
        self.assertEqual("no wrapper {x}", out[1]["content"])
        self.assertEqual("hello", out[0]["content"])


class Estimate(unittest.TestCase):
    def test_grows_with_content_and_tools(self):
        small = lp.estimate_tokens([{"role": "user", "content": "x"}])
        big = lp.estimate_tokens([{"role": "user", "content": "x" * 400}])
        self.assertLess(small, big)
        self.assertGreater(
            lp.estimate_tokens([{"role": "user", "content": "x"}], TOOLS),
            small,
        )

    def test_is_pessimistic(self):
        # 3600 chars at 3.6 chars/token is 1000 tokens; the margin must push
        # the estimate above that, never below.
        self.assertGreater(
            lp.estimate_tokens([{"role": "user", "content": "x" * 3600}]), 1000
        )


class Trim(unittest.TestCase):
    def test_drops_oldest_units_until_it_fits(self):
        msgs = conversation()
        budget = 400
        out, trimmed = lp.fit(msgs, budget, 2, 2, TOOLS)
        self.assertGreater(trimmed, 0)
        self.assertLess(len(out), len(msgs))
        self.assertLessEqual(lp.estimate_tokens(out, TOOLS), budget + 40)

    def test_keeps_the_system_prompt_and_the_current_turn(self):
        msgs = conversation(turns=8)
        out, _ = lp.fit(msgs, 300, 1, 1, TOOLS)
        self.assertEqual("system", out[0]["role"])
        self.assertEqual("SYSTEM", out[0]["content"])
        self.assertEqual(msgs[-1], out[-1])

    def test_keeps_tool_call_pairs_together(self):
        # A surviving tool result without its assistant tool_call breaks the
        # chat template, so units are dropped whole.
        msgs = conversation(turns=10, size=400)
        out, _ = lp.fit(msgs, 500, 1, 1, TOOLS)
        self.assertTrue(paired(out))

    def test_under_budget_is_a_no_op(self):
        msgs = conversation(turns=2)
        out, trimmed = lp.fit(msgs, 10**6, 6, 8, TOOLS)
        self.assertEqual(0, trimmed)
        self.assertEqual(msgs, out)


class StatsCounters(unittest.TestCase):
    def test_each_event_moves_its_own_counter(self):
        s = lp.Stats()
        s.bump("requests", "m")
        s.bump("requests", "m")
        s.bump("trimmed", "m")
        s.bump("retries", "m")
        snap = s.snapshot()
        self.assertEqual(2, snap["requests"])
        self.assertEqual(1, snap["trimmed"])
        self.assertEqual(1, snap["retries"])
        self.assertEqual(2, snap["per_model"]["m"]["requests"])
        self.assertEqual(1, snap["per_model"]["m"]["retries"])

    def test_rows_are_isolated(self):
        s = lp.Stats()
        s.bump("requests", "a")
        s.bump("errors", "b")
        self.assertEqual(0, s.snapshot()["per_model"]["a"]["errors"])
        self.assertEqual(1, s.snapshot()["per_model"]["b"]["errors"])


if __name__ == "__main__":
    unittest.main()
