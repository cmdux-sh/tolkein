from __future__ import annotations

import json
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tolkeins.normalize import build_snapshot, load_subscriptions, next_reset, scrub


FIXTURES = Path(__file__).resolve().parent / "fixtures"
ROOT = Path(__file__).resolve().parents[1]
NOW = datetime(2026, 10, 24, 5, 22, tzinfo=timezone.utc)


def load_fixture(name: str):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class NormalizeTests(unittest.TestCase):
    def setUp(self) -> None:
        text = (ROOT / "subscriptions.example.yaml").read_text(encoding="utf-8")
        self.subscriptions = load_subscriptions(text)
        self.snapshot = build_snapshot(
            {
                "claude": load_fixture("claude.json"),
                "codex": load_fixture("codex.json"),
                "cursor": load_fixture("cursor.json"),
                "warp": load_fixture("warp.json"),
                "grok": load_fixture("grok.json"),
            },
            self.subscriptions,
            ("claude", "codex", "cursor", "warp", "grok"),
            NOW,
        )
        self.by_id = {service["id"]: service for service in self.snapshot["services"]}

    def test_snapshot_shape_and_identity_stripping(self) -> None:
        encoded = json.dumps(self.snapshot)
        self.assertEqual(self.snapshot["schemaVersion"], 1)
        self.assertEqual(self.snapshot["generatedAt"], "2026-10-24T05:22:00Z")
        self.assertEqual(
            [service["id"] for service in self.snapshot["services"]],
            ["claude", "codex", "cursor", "warp", "grok"],
        )
        self.assertNotIn("accountEmail", encoded)
        self.assertNotIn("identity", encoded)
        self.assertNotIn("REDACTED", encoded)
        self.assertNotIn("@", encoded)
        self.assertNotIn("loginMethod", encoded)

    def test_claude_windows_pace_and_plan(self) -> None:
        claude = self.by_id["claude"]
        self.assertEqual(claude["name"], "Claude")
        self.assertEqual(claude["plan"], "Max")
        self.assertEqual(claude["source"], "claude")
        self.assertEqual(claude["fetchedAt"], "2026-10-24T05:18:46Z")
        self.assertEqual(claude["renewsOn"], "2026-11-12")
        self.assertEqual(claude["price"], {"amount": 100, "currency": "USD", "interval": "month"})
        self.assertNotIn("error", claude)
        self.assertEqual(
            [(window["label"], window["usedPercent"], window["windowMinutes"]) for window in claude["windows"]],
            [("Session", 20, 300), ("Weekly", 47, 10080), ("Fable only", 0, 10080)],
        )
        self.assertEqual(claude["windows"][0]["resetsAt"], "2026-10-24T06:40:00Z")
        self.assertEqual(claude["pace"]["primary"]["expectedUsedPercent"], 73)
        self.assertEqual(claude["pace"]["primary"]["stage"], "farBehind")
        self.assertTrue(claude["pace"]["primary"]["willLastToReset"])
        self.assertEqual(claude["pace"]["secondary"]["deltaPercent"], -42)

    def test_codex_null_primary_and_credits(self) -> None:
        codex = self.by_id["codex"]
        self.assertEqual(codex["plan"], "Pro")
        self.assertEqual(codex["source"], "codex-cli")
        self.assertEqual(len(codex["windows"]), 1)
        self.assertEqual(codex["windows"][0]["label"], "Weekly")
        self.assertEqual(codex["windows"][0]["usedPercent"], 44)
        self.assertEqual(codex["windows"][0]["resetsAt"], "2026-10-30T17:41:11Z")
        self.assertNotIn("primary", codex["pace"])
        self.assertEqual(codex["pace"]["secondary"]["stage"], "farAhead")
        self.assertEqual(codex["pace"]["secondary"]["etaSeconds"], 53273)
        self.assertFalse(codex["pace"]["secondary"]["willLastToReset"])
        self.assertAlmostEqual(codex["credits"]["remaining"], 42789.424725)
        self.assertEqual(codex["credits"]["currencyCode"], "Credits")
        self.assertNotIn("events", codex["credits"])
        self.assertNotIn("error", codex)

    def test_provider_errors_do_not_drop_the_snapshot(self) -> None:
        cursor = self.by_id["cursor"]
        warp = self.by_id["warp"]
        self.assertEqual(cursor["error"]["kind"], "needs-sign-in")
        self.assertIn("session", cursor["error"]["message"].lower())
        self.assertEqual(cursor["windows"], [])
        self.assertEqual(cursor["plan"], "Pro")
        self.assertEqual(warp["error"]["kind"], "unavailable")
        self.assertIn("not supported", warp["error"]["message"])
        self.assertEqual(warp["windows"], [])
        self.assertEqual(len(self.snapshot["services"]), 5)

    def test_grok_manual_weekly_replaces_sign_in_error(self) -> None:
        grok = self.by_id["grok"]
        self.assertEqual(grok["name"], "Grok Bot")
        self.assertEqual(grok["plan"], "SuperGrok")
        self.assertEqual(grok["source"], "manual")
        self.assertNotIn("error", grok)
        self.assertEqual(len(grok["windows"]), 1)
        window = grok["windows"][0]
        self.assertEqual(window["label"], "Weekly")
        self.assertEqual(window["usedPercent"], 0)
        self.assertEqual(window["windowMinutes"], 10080)
        # Saturday 24 Oct 2026 05:22 UTC is 01:22 in Toronto, after midnight,
        # so the next Saturday midnight is 31 Oct 04:00 UTC.
        self.assertEqual(window["resetsAt"], "2026-10-31T04:00:00Z")

    def test_yaml_plan_overrides_login_method(self) -> None:
        subscriptions = {"codex": {"plan": "Pro"}}
        snapshot = build_snapshot(
            {"codex": load_fixture("codex.json")},
            subscriptions,
            ("codex",),
            NOW,
        )
        self.assertEqual(snapshot["services"][0]["plan"], "Pro")

    def test_login_method_used_when_plan_missing(self) -> None:
        snapshot = build_snapshot({"claude": load_fixture("claude.json")}, {}, ("claude",), NOW)
        self.assertEqual(snapshot["services"][0]["plan"], "Max")

    def test_email_in_summary_is_stripped(self) -> None:
        payload = load_fixture("claude.json")
        payload[0]["pace"]["primary"]["summary"] = "mail me at person@example.com please"
        snapshot = build_snapshot({"claude": payload}, {}, ("claude",), NOW)
        summary = snapshot["services"][0]["pace"]["primary"]["summary"]
        self.assertNotIn("@", summary)
        self.assertNotIn("example.com", summary)

    def test_percent_is_clamped(self) -> None:
        payload = [
            {
                "provider": "claude",
                "source": "claude",
                "usage": {"primary": {"usedPercent": 140, "windowMinutes": 300, "resetsAt": "2026-10-24T06:40:00Z"}},
            }
        ]
        snapshot = build_snapshot({"claude": payload}, {}, ("claude",), NOW)
        self.assertEqual(snapshot["services"][0]["windows"][0]["usedPercent"], 100)

    def test_scrub_drops_nested_identity(self) -> None:
        cleaned = scrub({"usage": {"identity": {"accountEmail": "a@b.co"}, "usedPercent": 1}})
        self.assertEqual(cleaned, {"usage": {"usedPercent": 1}})

    def test_next_reset_weekday_still_ahead_today(self) -> None:
        # Wednesday 10:00 Toronto, reset Wednesday 12:00 -> same day 16:00 UTC.
        now = datetime(2026, 10, 21, 14, 0, tzinfo=timezone.utc)
        reset = next_reset(now, weekday=2, month_day=None, reset_time="12:00", timezone_name="America/Toronto")
        self.assertEqual(reset.strftime("%Y-%m-%dT%H:%M:%SZ"), "2026-10-21T16:00:00Z")

    def test_next_reset_month_day(self) -> None:
        reset = next_reset(
            NOW,
            weekday=None,
            month_day=15,
            reset_time="09:30",
            timezone_name="America/Toronto",
        )
        self.assertEqual(reset.strftime("%Y-%m-%dT%H:%M:%SZ"), "2026-11-15T14:30:00Z")


if __name__ == "__main__":
    unittest.main()
