#!/usr/bin/env python3
"""Unit tests for the proxy guards; run by the package checkPhase.

`main.py` is a script, not an importable module, so it is loaded by path.
Everything here is stdlib: the package has no test dependencies and the
build sandbox has no network.
"""

import importlib.util
import io
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

    def test_client_wording_of_the_rule_is_respected(self):
        # The sysadmin bench sends this; appending our own wording on top of
        # it changed the model's trajectory on task t5.
        msgs = [
            {
                "role": "system",
                "content": "Run exactly ONE command per turn and wait.",
            },
            {"role": "user", "content": "U"},
        ]
        self.assertTrue(lp.asks_single_tool(msgs))
        out = lp.inject_single_tool_rule(msgs, True)
        self.assertEqual(msgs[0]["content"], out[0]["content"])

    def test_unrelated_system_prompt_still_gets_the_rule(self):
        msgs = [
            {"role": "system", "content": "You are a careful assistant."},
            {"role": "user", "content": "U"},
        ]
        self.assertFalse(lp.asks_single_tool(msgs))
        out = lp.inject_single_tool_rule(msgs, True)
        self.assertIn(lp.SINGLE_TOOL_RULE, out[0]["content"])

    def test_multimodal_system_prompt_is_checked(self):
        msgs = [
            {
                "role": "system",
                "content": [
                    {"type": "text", "text": "use one command per turn"}
                ],
            }
        ]
        self.assertTrue(lp.asks_single_tool(msgs))

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

    def test_per_class_rates_are_pinned(self):
        # The rates come from measuring qwen3.8 and devstral over the same
        # texts; a change here has to be re-measured, not guessed.
        self.assertAlmostEqual(460 / lp.CPK_LATIN, 100, places=6)
        self.assertAlmostEqual(250 / lp.CPK_CYRILLIC, 100, places=6)
        self.assertAlmostEqual(120 / lp.CPK_CJK, 100, places=6)
        self.assertAlmostEqual(320 / lp.CPK_OTHER, 100, places=6)

    def test_cyrillic_costs_more_than_latin(self):
        latin = lp.char_tokens("a" * 330)
        cyrillic = lp.char_tokens("ж" * 330)
        self.assertGreater(cyrillic, latin)

    def test_cjk_is_never_underestimated(self):
        # Measured chars/token, baseline subtracted: Chinese runs at 2.00 on
        # qwen3.8 and 1.18 on devstral. The old 3.6-char constant estimated
        # 2.4x fewer tokens than devstral needs — a slot overflow, i.e. the
        # 400 this guard exists to prevent.
        sample = (
            "首先我们需要找到问题的来源：构建失败并不是因为配置写错了，"
            "而是因为替换缓存的请求超时。我们检查守护进程的日志，确认代理是"
            "否在运行。如果代理没有启动，那么每次请求都会等待一分钟然后失败，"
            "所以构建看起来像是卡住了，实际上只是它在等待网络。"
        )
        tokens = lp.char_tokens(sample)
        self.assertGreaterEqual(tokens, len(sample) / 1.3)
        self.assertEqual(1.2, round(len(sample) / tokens, 2))

    def test_russian_text_costs_more_than_english(self):
        ru = "Сборка падает не из-за конфигурации, а из-за кэша подстановки."
        en = "The build fails not because of the configuration but the cache."
        self.assertLess(
            len(ru) / lp.char_tokens(ru), len(en) / lp.char_tokens(en)
        )

    def test_latin_inside_russian_is_priced_as_russian(self):
        # Measured: Russian technical prose runs at 2.52 chars/token, not at
        # the 3.6 a class-by-class split predicted, because identifiers do not
        # tokenize at English rates inside Cyrillic text. The whole text is
        # priced at the script's rate once the share passes the threshold.
        sample = (
            "Перезапускаем systemd-юнит llm-proxy.service, смотрим "
            "journalctl -u llama-swap --since 15:00, проверяем /stats."
        )
        self.assertGreaterEqual(len(sample) / lp.char_tokens(sample), 2.4)

    def test_mostly_english_with_a_quote_stays_english_priced(self):
        text = "The build fails because the substituter times out. " * 20
        self.assertGreaterEqual(len(text) / lp.char_tokens(text), 4.0)


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


class FakeUpstream:
    """Raises a canned HTTP status and counts the attempts."""

    def __init__(self, code, body=b'{"error":"boom"}'):
        self.code = code
        self.body = body
        self.attempts = 0

    def request(self, path, payload=None, timeout=900):
        self.attempts += 1
        raise lp.urllib.error.HTTPError(
            "http://upstream", self.code, "err", None, io.BytesIO(self.body)
        )

    def unload(self):
        pass

    def wait_idle(self):
        pass


class RetryAndRelay(unittest.TestCase):
    def setUp(self):
        self._delays = lp.RETRY_DELAYS
        lp.RETRY_DELAYS = (0, 0, 0)

    def tearDown(self):
        lp.RETRY_DELAYS = self._delays

    def test_5xx_is_retried_three_times_and_carries_the_body(self):
        up = FakeUpstream(500, b'{"error":"Jinja Exception"}')
        stats = lp.Stats()
        with self.assertRaises(lp.UpstreamError) as caught:
            lp.chat(up, {"model": "m"}, stats, "m")
        self.assertEqual(3, up.attempts)
        self.assertEqual(500, caught.exception.code)
        self.assertIn("Jinja Exception", caught.exception.detail)
        self.assertEqual(2, stats.retries)

    def test_4xx_is_not_retried_but_keeps_the_body(self):
        up = FakeUpstream(400, b'{"error":"bad request"}')
        with self.assertRaises(lp.UpstreamError) as caught:
            lp.chat(up, {"model": "m"}, lp.Stats(), "m")
        self.assertEqual(1, up.attempts)
        self.assertEqual(400, caught.exception.code)
        self.assertIn("bad request", caught.exception.detail)


if __name__ == "__main__":
    unittest.main()
