"""Run the local CodexBar CLI. Credentials never leave this process."""

from __future__ import annotations

import json
import os
import subprocess
from typing import Any

from tolkeins.config import PROVIDER_ID


class CollectorAbort(RuntimeError):
    """The CLI cannot run, so the last published snapshot must be left alone."""


def codexbar_command(binary: str, provider: str) -> list[str]:
    """Argv for one provider.

    CodexBar 0.80.0 treats `--json` as a shortcut for `--format json`
    (`CLIOutputPreferences.resolveOutputFormat`). `--source` is omitted on
    purpose: the default is `auto`. Warp rejects `cli` ("Source 'cli' is not
    supported for warp"), and an explicit `cli` fetch also failed for Grok
    on the machine this tracker was designed against.
    """

    if PROVIDER_ID.fullmatch(provider) is None:
        raise CollectorAbort(f"refusing to pass an invalid provider id: {provider}")
    return [binary, "usage", "--provider", provider, "--json"]


def fetch_provider(binary: str, provider: str, timeout: float) -> Any:
    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        raise CollectorAbort(f"CodexBar CLI is not executable at {binary}")
    command = codexbar_command(binary, provider)
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            shell=False,
        )
    except FileNotFoundError as error:
        raise CollectorAbort(f"CodexBar CLI not found at {binary}") from error
    except subprocess.TimeoutExpired:
        return _collector_error(provider, f"codexbar timed out after {int(timeout)}s")
    try:
        return parse_codexbar_stdout(completed.stdout)
    except json.JSONDecodeError:
        return _collector_error(
            provider,
            f"codexbar returned non-JSON output (exit {completed.returncode})",
        )


def parse_codexbar_stdout(text: str) -> Any:
    stripped = text.strip().lstrip("\ufeff")
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        starts = [index for index in (stripped.find("["), stripped.find("{")) if index >= 0]
        if not starts:
            raise
        return json.loads(stripped[min(starts) :])


def _collector_error(provider: str, message: str) -> list[dict[str, Any]]:
    return [
        {
            "provider": provider,
            "source": "codexbar",
            "error": {"message": message, "kind": "collector", "code": 1},
        }
    ]
