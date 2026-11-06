"""Load ~/.config/tolkeins/config.env without printing secrets."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path


DEFAULT_PROVIDERS = ("claude", "codex", "cursor", "warp", "grok")
DEFAULT_CODEXBAR = "/opt/homebrew/bin/codexbar"
DEFAULT_TIMEOUT_SECONDS = 90.0
PROVIDER_ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")


class ConfigError(ValueError):
    """Collector configuration is missing or invalid."""


@dataclass(frozen=True)
class CollectorConfig:
    config_dir: Path
    worker_url: str
    write_token: str
    codexbar_bin: str
    providers: tuple[str, ...]
    timeout_seconds: float
    subscriptions_path: Path

    @property
    def has_publish_target(self) -> bool:
        return bool(self.worker_url and self.write_token)


def default_config_dir() -> Path:
    override = os.environ.get("TOLKEINS_CONFIG_DIR")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".config" / "tolkeins"


def load_config(config_dir: Path | None = None) -> CollectorConfig:
    directory = (config_dir or default_config_dir()).expanduser()
    file_values = _read_env_file(directory / "config.env")
    # Process environment wins so a launchd or shell override beats the file.
    merged = {**file_values, **{key: value for key, value in os.environ.items() if value != ""}}
    providers = _providers(merged.get("PROVIDERS"))
    timeout = _timeout(merged.get("CODEXBAR_TIMEOUT"))
    return CollectorConfig(
        config_dir=directory,
        worker_url=merged.get("WORKER_URL", "").strip(),
        write_token=merged.get("WRITE_TOKEN", "").strip(),
        codexbar_bin=merged.get("CODEXBAR_BIN", DEFAULT_CODEXBAR).strip() or DEFAULT_CODEXBAR,
        providers=providers,
        timeout_seconds=timeout,
        subscriptions_path=directory / "subscriptions.yaml",
    )


def _read_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        key, separator, value = line.partition("=")
        if separator != "=" or not key.strip():
            raise ConfigError(f"{path}:{line_number} is not KEY=VALUE")
        values[key.strip()] = _unquote(value.strip())
    return values


def _unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def _providers(raw: str | None) -> tuple[str, ...]:
    if raw is None or not raw.strip():
        return DEFAULT_PROVIDERS
    providers = tuple(part.strip() for part in raw.split(",") if part.strip())
    if not providers:
        raise ConfigError("PROVIDERS is empty")
    invalid = [provider for provider in providers if PROVIDER_ID.fullmatch(provider) is None]
    if invalid:
        raise ConfigError(f"invalid provider id: {', '.join(invalid)}")
    return providers


def _timeout(raw: str | None) -> float:
    if raw is None or not raw.strip():
        return DEFAULT_TIMEOUT_SECONDS
    try:
        timeout = float(raw)
    except ValueError as error:
        raise ConfigError("CODEXBAR_TIMEOUT must be a number of seconds") from error
    if timeout <= 0 or timeout > 300:
        raise ConfigError("CODEXBAR_TIMEOUT must be between 1 and 300 seconds")
    return timeout
