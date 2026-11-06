from __future__ import annotations

import json
import sys
import threading
import unittest
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tolkeins.codexbar import codexbar_command, parse_codexbar_stdout
from tolkeins.config import ConfigError, load_config
from tolkeins.normalize import build_snapshot
from tolkeins.publish import PublishError, post_snapshot, validate_worker_url
from tolkeins.yaml_lite import YAMLError, parse_yaml


ROOT = Path(__file__).resolve().parents[1]


class YamlTests(unittest.TestCase):
    def test_example_file(self) -> None:
        parsed = parse_yaml((ROOT / "subscriptions.example.yaml").read_text(encoding="utf-8"))
        grok = parsed["services"]["grok"]
        self.assertEqual(grok["name"], "Grok Bot")
        self.assertEqual(grok["price"]["amount"], 30)
        window = grok["manualWindows"][0]
        self.assertEqual(window["resetWeekday"], "saturday")
        self.assertEqual(window["resetTime"], "00:00")
        self.assertEqual(window["windowMinutes"], 10080)
        self.assertIsInstance(window["usedPercent"], int)

    def test_comments_quotes_and_types(self) -> None:
        parsed = parse_yaml(
            """
            # header
            enabled: true
            note: "hash # stays"
            empty:
            items:
              - label: Weekly
                usedPercent: 1.5
            """
        )
        self.assertTrue(parsed["enabled"])
        self.assertEqual(parsed["note"], "hash # stays")
        self.assertIsNone(parsed["empty"])
        self.assertEqual(parsed["items"][0]["usedPercent"], 1.5)

    def test_tabs_rejected(self) -> None:
        with self.assertRaises(YAMLError):
            parse_yaml("services:\n\tclaude: 1\n")


class ConfigTests(unittest.TestCase):
    def test_missing_file_uses_defaults(self) -> None:
        config = load_config(Path("/tmp/tolkeins-missing-config-dir"))
        self.assertEqual(config.providers, ("claude", "codex", "cursor", "warp", "grok"))
        self.assertEqual(config.codexbar_bin, "/opt/homebrew/bin/codexbar")
        self.assertEqual(config.timeout_seconds, 90)

    def test_file_and_env_precedence(self) -> None:
        directory = Path("/tmp/tolkeins-config-test")
        directory.mkdir(exist_ok=True)
        (directory / "config.env").write_text(
            'WORKER_URL="https://example.workers.dev"\nWRITE_TOKEN=file-token\nPROVIDERS=claude, warp\n',
            encoding="utf-8",
        )
        import os

        previous = os.environ.get("WRITE_TOKEN")
        os.environ["WRITE_TOKEN"] = "env-token"
        try:
            config = load_config(directory)
        finally:
            if previous is None:
                os.environ.pop("WRITE_TOKEN", None)
            else:
                os.environ["WRITE_TOKEN"] = previous
        self.assertEqual(config.worker_url, "https://example.workers.dev")
        self.assertEqual(config.write_token, "env-token")
        self.assertEqual(config.providers, ("claude", "warp"))

    def test_invalid_provider_rejected(self) -> None:
        directory = Path("/tmp/tolkeins-config-invalid")
        directory.mkdir(exist_ok=True)
        (directory / "config.env").write_text("PROVIDERS=Claude\n", encoding="utf-8")
        with self.assertRaises(ConfigError):
            load_config(directory)


class CodexbarCommandTests(unittest.TestCase):
    def test_argv_uses_json_and_not_source(self) -> None:
        command = codexbar_command("/opt/homebrew/bin/codexbar", "warp")
        self.assertEqual(command, ["/opt/homebrew/bin/codexbar", "usage", "--provider", "warp", "--json"])
        self.assertNotIn("--source", command)

    def test_invalid_provider_is_not_passed_to_the_shell(self) -> None:
        with self.assertRaises(Exception):
            codexbar_command("/opt/homebrew/bin/codexbar", "warp; rm -rf /")

    def test_parse_stdout_with_leading_log_line(self) -> None:
        payload = parse_codexbar_stdout('warning: ignored\n[{"provider":"warp","source":"api"}]\n')
        self.assertEqual(payload[0]["provider"], "warp")


class PublishTests(unittest.TestCase):
    def test_rejects_insecure_remote_url(self) -> None:
        with self.assertRaises(PublishError):
            validate_worker_url("http://example.com")

    def test_post_sends_bearer_and_hides_token_on_failure(self) -> None:
        token = "super-secret-token"
        seen = {}

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length", "0"))
                seen["path"] = self.path
                seen["auth"] = self.headers.get("Authorization")
                seen["body"] = self.rfile.read(length)
                self.send_response(401)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"error":"unauthorized"}')

            def log_message(self, format: str, *args) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            port = server.server_address[1]
            with self.assertRaises(PublishError) as caught:
                post_snapshot(
                    f"http://127.0.0.1:{port}",
                    token,
                    {"schemaVersion": 1, "generatedAt": "2026-10-24T05:22:00Z", "services": []},
                )
        finally:
            server.shutdown()
            thread.join(timeout=2)
            server.server_close()
        self.assertEqual(seen["path"], "/v1/snapshot")
        self.assertEqual(seen["auth"], f"Bearer {token}")
        self.assertNotIn(token.encode(), seen["body"])
        self.assertNotIn(token, str(caught.exception))

    def test_post_accepts_200(self) -> None:
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(length)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"ok":true}')

            def log_message(self, format: str, *args) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            port = server.server_address[1]
            snapshot = build_snapshot(
                {},
                {},
                (),
                datetime(2026, 10, 24, tzinfo=timezone.utc),
            )
            post_snapshot(f"http://127.0.0.1:{port}", "token", snapshot)
        finally:
            server.shutdown()
            thread.join(timeout=2)
            server.server_close()
        self.assertNotIn("accountEmail", json.dumps(snapshot))


if __name__ == "__main__":
    unittest.main()
