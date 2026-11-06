"""Render the LaunchAgent plist that starts Tolkeins Collector.app.

The program launchd execs is the responsible process for TCC. It must be the
signed helper, which then spawns python. Python itself is only TOLKEINS_PYTHON.
"""

from __future__ import annotations

import argparse
import stat
from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape


BUNDLE_ID = "com.tolkeins.collector"
APP_BUNDLE_NAME = "Tolkeins Collector.app"
EXECUTABLE_NAME = "tolkeins-collector"
LAUNCH_LABEL = "com.tolkeins.collector"
CERT_COMMON_NAME = "Tolkeins Collector"
EXECUTABLE_SUFFIX = f"/{APP_BUNDLE_NAME}/Contents/MacOS/{EXECUTABLE_NAME}"
INTERVAL_SECONDS = 600


class LaunchAgentError(ValueError):
    """The LaunchAgent plist would not keep the helper as the responsible process."""


@dataclass(frozen=True)
class LaunchAgentSpec:
    executable: str
    python: str
    install_dir: str
    config_dir: str
    log_dir: str


def render_launch_agent_plist(spec: LaunchAgentSpec) -> str:
    if not spec.executable.endswith(EXECUTABLE_SUFFIX):
        raise LaunchAgentError("LaunchAgent program must be the Tolkeins Collector.app executable")
    if not spec.python.startswith("/"):
        raise LaunchAgentError("TOLKEINS_PYTHON must be an absolute path")
    for field in (spec.install_dir, spec.config_dir, spec.log_dir):
        if not field.startswith("/"):
            raise LaunchAgentError("LaunchAgent paths must be absolute")

    def text(value: str) -> str:
        return escape(value, {'"': "&quot;"})

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>{text(LAUNCH_LABEL)}</string>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>{text(BUNDLE_ID)}</string>
  </array>
  <key>ProgramArguments</key>
  <array>
    <string>{text(spec.executable)}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>{text(spec.config_dir)}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PYTHONPATH</key>
    <string>{text(spec.install_dir)}</string>
    <key>TOLKEINS_CONFIG_DIR</key>
    <string>{text(spec.config_dir)}</string>
    <key>TOLKEINS_PYTHON</key>
    <string>{text(spec.python)}</string>
  </dict>
  <key>StartInterval</key>
  <integer>{INTERVAL_SECONDS}</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>{text(spec.log_dir)}/collector.log</string>
  <key>StandardErrorPath</key>
  <string>{text(spec.log_dir)}/collector.err.log</string>
</dict>
</plist>
"""


def app_executable(home: Path) -> Path:
    return home / "Applications" / APP_BUNDLE_NAME / "Contents" / "MacOS" / EXECUTABLE_NAME


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Write the Tolkeins LaunchAgent plist.")
    parser.add_argument("--executable", required=True)
    parser.add_argument("--python", required=True)
    parser.add_argument("--install-dir", required=True)
    parser.add_argument("--config-dir", required=True)
    parser.add_argument("--log-dir", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    spec = LaunchAgentSpec(
        executable=args.executable,
        python=args.python,
        install_dir=args.install_dir,
        config_dir=args.config_dir,
        log_dir=args.log_dir,
    )
    destination = Path(args.output)
    destination.write_text(render_launch_agent_plist(spec), encoding="utf-8")
    destination.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
