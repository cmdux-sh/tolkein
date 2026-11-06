"""Summarize a dry-run snapshot for the Chrome-backed providers.

Prints provider ids, window counts, and error kinds. Emails and token-like
strings are redacted. The write token is never read.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


CHROME_PROVIDER_IDS = ("gemini", "claudeplatform")
INFO_PROVIDER_IDS = ("cursor",)
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")
TOKEN_RE = re.compile(r"\b[A-Za-z0-9_\-]{20,}\b")
SECRET_LINE_RE = re.compile(
    r"(WRITE_TOKEN\s*=|Bearer\s+\S+|wk-[A-Za-z0-9]|sk-[A-Za-z0-9]|PRIVATE KEY)"
)
CHROME_GRANT_HINTS = ("chrome's profile", "files & folders", "files and folders")
KEYCHAIN_GRANT_HINTS = ("keychain permission", "safe storage")


def redact(text: str) -> str:
    cleaned = EMAIL_RE.sub("[redacted-email]", text)
    return TOKEN_RE.sub("[redacted]", cleaned)


COOKIE_LINE_RE = re.compile(r"(sessionKey=|^Cookie:|\b[\w.-]+=[^\s;]{8,})", re.IGNORECASE)


def redact_status(text: str) -> str:
    """Keep CodexBar status lines; drop cookie and secret lines; redact what is left."""

    kept: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or SECRET_LINE_RE.search(line) or COOKIE_LINE_RE.search(line):
            continue
        kept.append(redact(line))
    return "\n".join(kept)


def filter_stderr(text: str) -> str:
    kept: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or SECRET_LINE_RE.search(line) or "@" in line:
            continue
        kept.append(line)
    return "\n".join(kept)


def summarize_providers(
    snapshot: dict[str, Any],
    provider_ids: tuple[str, ...] = CHROME_PROVIDER_IDS,
) -> list[str]:
    services = snapshot.get("services")
    by_id: dict[str, dict[str, Any]] = {}
    if isinstance(services, list):
        for service in services:
            if isinstance(service, dict) and isinstance(service.get("id"), str):
                by_id[service["id"]] = service
    return [_provider_line(provider_id, by_id.get(provider_id)) for provider_id in provider_ids]


def chrome_grant_needed(snapshot: dict[str, Any]) -> bool:
    return _grant_needed(snapshot, "grant=tolkeins-collector-chrome")


def keychain_grant_needed(snapshot: dict[str, Any]) -> bool:
    return _grant_needed(snapshot, "grant=chrome-safe-storage")


def _grant_needed(snapshot: dict[str, Any], marker: str) -> bool:
    return any(marker in line for line in summarize_providers(snapshot))


def _provider_line(provider_id: str, service: dict[str, Any] | None) -> str:
    if service is None:
        return f"{provider_id} missing"
    windows = service.get("windows")
    window_list = windows if isinstance(windows, list) else []
    error = service.get("error") if isinstance(service.get("error"), dict) else None
    if error and not window_list:
        kind = error.get("kind") if isinstance(error.get("kind"), str) else "error"
        message = error.get("message") if isinstance(error.get("message"), str) else ""
        safe = redact(message)
        line = f"{provider_id} {kind} windows=0 message={safe}"
        lowered = message.lower()
        if any(hint in lowered for hint in CHROME_GRANT_HINTS):
            line += " grant=tolkeins-collector-chrome"
        if any(hint in lowered for hint in KEYCHAIN_GRANT_HINTS):
            line += " grant=chrome-safe-storage"
        return line
    parts = [f"{provider_id} ok windows={len(window_list)}"]
    for window in window_list:
        if not isinstance(window, dict):
            continue
        label = window.get("label")
        if not isinstance(label, str) or not label.strip():
            continue
        safe_label = redact(re.sub(r"\s+", "_", label.strip()))[:40]
        used = window.get("usedPercent")
        if isinstance(used, bool) or not isinstance(used, (int, float)):
            parts.append(safe_label)
            continue
        parts.append(f"{safe_label}={used:g}")
    return " ".join(parts)


def _providers_ok(lines: list[str]) -> bool:
    needed = {provider_id: False for provider_id in CHROME_PROVIDER_IDS}
    for line in lines:
        for provider_id in CHROME_PROVIDER_IDS:
            prefix = f"{provider_id} ok windows="
            if line.startswith(prefix) and not line.startswith(f"{provider_id} ok windows=0"):
                needed[provider_id] = True
    return all(needed.values())


def render_report(snapshot: dict[str, Any] | None, stderr_text: str) -> tuple[str, int]:
    lines: list[str] = []
    filtered = filter_stderr(stderr_text)
    if filtered:
        lines.append(filtered)
    if snapshot is None:
        lines.append("result=fail")
        lines.append("no snapshot was written")
        return "\n".join(lines) + "\n", 2
    summary = summarize_providers(snapshot)
    info = summarize_providers(snapshot, INFO_PROVIDER_IDS)
    lines.extend(summary)
    for line in info:
        if line.endswith(" missing"):
            continue
        lines.append(f"info {line}")
    if chrome_grant_needed(snapshot):
        lines.append(
            "next=System Settings → Privacy & Security → Files and Folders → "
            "Tolkeins Collector → turn Chrome on, then re-run collector/verify-chrome.sh"
        )
        lines.append(
            "note=CodexBar's text names CodexBar. This LaunchAgent's responsible app "
            "is Tolkeins Collector, so that is the Chrome switch that applies."
        )
    if keychain_grant_needed(snapshot):
        lines.append(
            "next=In Terminal.app, run ./collector/grant-chrome-keychain.sh and click "
            "Always Allow for the Chrome Safe Storage item. Then re-run collector/verify-chrome.sh"
        )
        lines.append(
            "note=CodexBar usage runs are non-interactive and will not show the Keychain "
            "prompt. cookie refresh --allow-keychain-prompt is the one-time step."
        )
    passed = _providers_ok(summary)
    lines.append("result=pass" if passed else "result=fail")
    return "\n".join(lines) + "\n", 0 if passed else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Summarize gemini and claudeplatform from a dry-run.")
    parser.add_argument("--snapshot")
    parser.add_argument("--stderr")
    parser.add_argument("--redact-stdin", action="store_true", help="Filter CodexBar status text on stdin.")
    args = parser.parse_args(argv)
    if args.redact_stdin:
        filtered = redact_status(sys.stdin.read())
        if filtered:
            sys.stdout.write(filtered + "\n")
        return 0
    if not args.snapshot or not args.stderr:
        parser.error("--snapshot and --stderr are required")
    stderr_text = Path(args.stderr).read_text(encoding="utf-8", errors="replace")
    raw = Path(args.snapshot).read_text(encoding="utf-8", errors="replace").strip()
    snapshot: dict[str, Any] | None
    if not raw:
        snapshot = None
    else:
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            snapshot = None
        else:
            snapshot = parsed if isinstance(parsed, dict) else None
    report, status = render_report(snapshot, stderr_text)
    sys.stdout.write(report)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
