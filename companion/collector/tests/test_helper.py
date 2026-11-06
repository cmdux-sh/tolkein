from __future__ import annotations

import json
import stat
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tolkeins.chrome_status import filter_stderr, render_report
from tolkeins.launch_agent import (
    BUNDLE_ID,
    EXECUTABLE_NAME,
    LaunchAgentError,
    LaunchAgentSpec,
    render_launch_agent_plist,
)
from tolkeins.normalize import build_snapshot
from tolkeins.signing_identity import (
    SigningIdentityError,
    choose_signing_identity,
    identity_names,
)


ROOT = Path(__file__).resolve().parents[1]
MACOS = ROOT / "macos"
GENERATED = datetime(2026, 10, 24, 5, 22, tzinfo=timezone.utc)


def plist_map(element: ET.Element) -> dict[str, ET.Element]:
    children = list(element)
    mapped: dict[str, ET.Element] = {}
    for index in range(0, len(children), 2):
        key = children[index].text or ""
        mapped[key] = children[index + 1]
    return mapped


class LaunchAgentTests(unittest.TestCase):
    def spec(self, executable: str | None = None) -> LaunchAgentSpec:
        program = executable or (
            "/Users/arturo/Applications/Tolkeins Collector.app/Contents/MacOS/tolkeins-collector"
        )
        return LaunchAgentSpec(
            executable=program,
            python="/usr/bin/python3",
            install_dir="/Users/arturo/.local/share/tolkeins",
            config_dir="/Users/arturo/.config/tolkeins",
            log_dir="/Users/arturo/Library/Logs/tolkeins",
        )

    def test_program_is_the_helper_app(self) -> None:
        root = ET.fromstring(render_launch_agent_plist(self.spec()))
        fields = plist_map(root.find("dict"))
        arguments = [item.text for item in fields["ProgramArguments"]]
        self.assertEqual(
            arguments,
            ["/Users/arturo/Applications/Tolkeins Collector.app/Contents/MacOS/tolkeins-collector"],
        )
        self.assertNotIn("-m", arguments)
        environment = plist_map(fields["EnvironmentVariables"])
        self.assertEqual(environment["TOLKEINS_PYTHON"].text, "/usr/bin/python3")
        self.assertEqual(environment["PYTHONPATH"].text, "/Users/arturo/.local/share/tolkeins")
        self.assertEqual(fields["Label"].text, "com.tolkeins.collector")
        self.assertEqual([item.text for item in fields["AssociatedBundleIdentifiers"]], [BUNDLE_ID])
        self.assertEqual(fields["StartInterval"].text, "600")
        self.assertEqual(fields["RunAtLoad"].tag, "true")
        self.assertNotIn("WRITE_TOKEN", render_launch_agent_plist(self.spec()))

    def test_paths_are_escaped(self) -> None:
        spec = LaunchAgentSpec(
            executable="/Users/a&b/Applications/Tolkeins Collector.app/Contents/MacOS/tolkeins-collector",
            python="/usr/bin/python3",
            install_dir="/Users/a&b/.local/share/tolkeins",
            config_dir="/Users/a&b/.config/tolkeins",
            log_dir="/Users/a&b/Library/Logs/tolkeins",
        )
        text = render_launch_agent_plist(spec)
        self.assertIn("/Users/a&amp;b/Applications/Tolkeins Collector.app", text)
        ET.fromstring(text)

    def test_rejects_python_as_the_program(self) -> None:
        with self.assertRaises(LaunchAgentError):
            render_launch_agent_plist(self.spec("/usr/bin/python3"))

    def test_info_plist_matches_the_bundle_id(self) -> None:
        root = ET.fromstring((MACOS / "Info.plist").read_text(encoding="utf-8"))
        fields = plist_map(root.find("dict"))
        self.assertEqual(fields["CFBundleIdentifier"].text, BUNDLE_ID)
        self.assertEqual(fields["CFBundleExecutable"].text, EXECUTABLE_NAME)
        self.assertEqual(fields["CFBundleName"].text, "Tolkeins Collector")
        self.assertEqual(fields["LSUIElement"].tag, "true")

    def test_shell_scripts_parse(self) -> None:
        scripts = [
            ROOT / "install.sh",
            ROOT / "uninstall.sh",
            ROOT / "verify-chrome.sh",
            ROOT / "grant-chrome-keychain.sh",
            MACOS / "assemble-app.sh",
            MACOS / "sign-app.sh",
            MACOS / "build-prebuilt.sh",
            MACOS / "keychain-list.sh",
        ]
        for script in scripts:
            completed = subprocess.run(["bash", "-n", str(script)], check=False, capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(script.stat().st_mode & stat.S_IXUSR)

    def test_install_refuses_linux(self) -> None:
        completed = subprocess.run([str(ROOT / "install.sh")], check=False, capture_output=True, text=True)
        self.assertEqual(completed.returncode, 1)
        self.assertIn("macOS", completed.stderr)

    def test_keychain_grant_refuses_linux(self) -> None:
        completed = subprocess.run(
            [str(ROOT / "grant-chrome-keychain.sh")],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 1)
        self.assertIn("Mac mini", completed.stderr)
        text = (ROOT / "grant-chrome-keychain.sh").read_text(encoding="utf-8")
        self.assertIn("--allow-keychain-prompt", text)
        self.assertIn("Always Allow", text)
        self.assertIn("Chrome Safe Storage", text)
        self.assertIn("sessionKey=", text)

    def test_signing_script_keeps_a_certificate_identity(self) -> None:
        text = (MACOS / "sign-app.sh").read_text(encoding="utf-8")
        codesign_lines = [line for line in text.splitlines() if "codesign" in line]
        for line in codesign_lines:
            self.assertNotRegex(line, r"(--sign|-s)\s+-(?:\s|$)")
        self.assertIn("certificate", text)
        self.assertIn("TOLKEINS_SIGN_IDENTITY", text)
        self.assertNotIn('echo "$PASS"', text)
        self.assertNotIn("cat \"$KEY_FILE\"", text)
        uninstall = (ROOT / "uninstall.sh").read_text(encoding="utf-8")
        self.assertIn("Tolkeins Collector.app", uninstall)
        self.assertIn("--purge", uninstall)
        self.assertIn("tolkeins-collector.keychain-db", uninstall)

    def test_keychain_search_list_keeps_login_keychain(self) -> None:
        script = """
set -euo pipefail
source "$1"
security() {
  if [[ "$1" == "list-keychains" && "${4:-}" == "-s" ]]; then
    printf '%s\\n' "${@:5}"
    return 0
  fi
  printf '    "%s"\\n' "/Users/Arturo Mini/Library/Keychains/login.keychain-db"
  printf '    "%s"\\n' "/Library/Keychains/System.keychain"
}
KEYCHAIN="/Users/Arturo Mini/Library/Keychains/tolkeins-collector.keychain-db"
LOGIN_KEYCHAIN="/Users/Arturo Mini/Library/Keychains/login.keychain-db"
keychain_snapshot_search_list
keychain_restore_search_list
"""
        completed = subprocess.run(
            ["bash", "-c", script, "bash", str(MACOS / "keychain-list.sh")],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        lines = [line for line in completed.stdout.splitlines() if line]
        self.assertEqual(
            lines,
            [
                "/Users/Arturo Mini/Library/Keychains/tolkeins-collector.keychain-db",
                "/Users/Arturo Mini/Library/Keychains/login.keychain-db",
                "/Library/Keychains/System.keychain",
            ],
        )


class ChromeStatusTests(unittest.TestCase):
    def snapshot(self) -> dict:
        return build_snapshot(
            {
                "gemini": [
                    {
                        "provider": "gemini",
                        "source": "web",
                        "usage": {"primary": {"usedPercent": 20, "resetsAt": "2026-10-24T06:40:00Z"}},
                    }
                ],
                "claudeplatform": [
                    {
                        "provider": "claudeplatform",
                        "source": "web",
                        "error": {
                            "message": (
                                "Cannot read Chrome's profile. In System Settings → Privacy & Security → "
                                "Files & Folders, turn on Chrome under CodexBar, then refresh."
                            )
                        },
                    }
                ],
                "cursor": [
                    {
                        "provider": "cursor",
                        "source": "web",
                        "error": {"message": "Needs sign-in at cursor.com"},
                    }
                ],
            },
            {},
            ("gemini", "claudeplatform", "cursor"),
            GENERATED,
        )

    def test_chrome_failure_names_the_helper_grant(self) -> None:
        report, status = render_report(self.snapshot(), "gemini ok\nclaudeplatform error\n")
        self.assertEqual(status, 1)
        self.assertIn("gemini ok windows=1", report)
        self.assertIn("claudeplatform unavailable windows=0", report)
        self.assertIn("grant=tolkeins-collector-chrome", report)
        self.assertIn("result=fail", report)
        self.assertIn("info cursor", report)
        self.assertNotIn("WRITE_TOKEN", report)

    def test_both_providers_with_windows_pass(self) -> None:
        snapshot = build_snapshot(
            {
                "gemini": [
                    {
                        "provider": "gemini",
                        "source": "web",
                        "usage": {"primary": {"usedPercent": 12}},
                        "accountEmail": "person@example.com",
                    }
                ],
                "claudeplatform": [
                    {
                        "provider": "claudeplatform",
                        "source": "web",
                        "usage": {"primary": {"usedPercent": 40}},
                    }
                ],
                "cursor": [
                    {
                        "provider": "cursor",
                        "source": "web",
                        "error": {"message": "Needs sign-in"},
                    }
                ],
            },
            {},
            ("gemini", "claudeplatform", "cursor"),
            GENERATED,
        )
        report, status = render_report(snapshot, "")
        self.assertEqual(status, 0)
        self.assertIn("result=pass", report)
        self.assertIn("gemini ok windows=1", report)
        self.assertIn("claudeplatform ok windows=1", report)
        self.assertNotIn("person@example.com", report)
        self.assertIn("needs-sign-in", report)

    def test_stderr_filter_drops_secrets(self) -> None:
        filtered = filter_stderr(
            "gemini error\nWRITE_TOKEN=super-secret-token\nBearer abcdefghijklmnop\nperson@example.com failed\n"
        )
        self.assertIn("gemini error", filtered)
        self.assertNotIn("super-secret-token", filtered)
        self.assertNotIn("abcdefghijklmnop", filtered)
        self.assertNotIn("person@example.com", filtered)

    def test_error_message_redacts_token_and_email(self) -> None:
        snapshot = {
            "services": [
                {
                    "id": "gemini",
                    "windows": [],
                    "error": {
                        "kind": "unavailable",
                        "message": "failed for person@example.com token sk-abcdefghijklmnopqrstuvwxyz",
                    },
                },
                {"id": "claudeplatform", "windows": [{"label": "Session", "usedPercent": 1}]},
            ]
        }
        report, status = render_report(snapshot, "")
        self.assertEqual(status, 1)
        self.assertNotIn("person@example.com", report)
        self.assertNotIn("sk-abcdefghijklmnopqrstuvwxyz", report)
        self.assertIn("[redacted-email]", report)
        self.assertIn("[redacted]", report)

    def test_keychain_message_is_printed_in_full(self) -> None:
        message = (
            "Chrome cookie access needs Keychain permission — use Refresh beside Cookie source "
            "or Refresh in the provider menu to allow it, or paste a Cookie header in Manual mode."
        )
        snapshot = build_snapshot(
            {
                "gemini": [{"provider": "gemini", "source": "web", "error": {"message": message}}],
                "claudeplatform": [
                    {"provider": "claudeplatform", "source": "web", "error": {"message": message}}
                ],
            },
            {},
            ("gemini", "claudeplatform"),
            GENERATED,
        )
        self.assertEqual(snapshot["services"][0]["error"]["kind"], "unavailable")
        self.assertEqual(snapshot["services"][0]["error"]["message"], message)
        report, status = render_report(snapshot, "")
        self.assertEqual(status, 1)
        self.assertEqual(report.count(message), 2)
        self.assertIn("grant-chrome-keychain.sh", report)
        self.assertIn("Always Allow", report)
        self.assertNotIn("needs-sign-in", report)

    def test_invalid_snapshot_fails_closed(self) -> None:
        report, status = render_report(None, "CodexBar CLI is not executable at /opt/homebrew/bin/codexbar")
        self.assertEqual(status, 2)
        self.assertIn("result=fail", report)
        self.assertIn("no snapshot", report)


class SigningIdentityTests(unittest.TestCase):
    def names(self) -> list[str]:
        text = """
  1) ABCDEF0123456789 "Apple Development: Arturo Castaneyra (V7U5DSP776)"
  2) FFEEDDCCBBAA9988 "Developer ID Application: Example (TEAMID1234)"
     2 valid identities found
"""
        parsed = identity_names(text)
        self.assertNotIn("ABCDEF0123456789", parsed)
        return parsed

    def test_apple_development_wins_over_developer_id(self) -> None:
        chosen = choose_signing_identity(self.names(), None)
        self.assertEqual(chosen, "Apple Development: Arturo Castaneyra (V7U5DSP776)")

    def test_developer_id_when_that_is_the_only_apple_identity(self) -> None:
        chosen = choose_signing_identity(["Developer ID Application: Example (TEAMID1234)"], None)
        self.assertEqual(chosen, "Developer ID Application: Example (TEAMID1234)")

    def test_local_certificate_when_no_apple_identity_exists(self) -> None:
        self.assertIsNone(choose_signing_identity(["Tolkeins Collector"], None))
        self.assertIsNone(choose_signing_identity([], None))

    def test_override_selects_that_identity(self) -> None:
        chosen = choose_signing_identity(
            self.names(),
            "Developer ID Application: Example (TEAMID1234)",
        )
        self.assertEqual(chosen, "Developer ID Application: Example (TEAMID1234)")

    def test_override_local_keeps_the_self_signed_certificate(self) -> None:
        self.assertIsNone(choose_signing_identity(self.names(), "local"))
        self.assertIsNone(choose_signing_identity(self.names(), "Tolkeins Collector"))

    def test_unknown_override_is_rejected(self) -> None:
        with self.assertRaises(SigningIdentityError) as caught:
            choose_signing_identity(self.names(), "Apple Development: Someone Else (XXXXXXXXXX)")
        self.assertNotIn("ABCDEF0123456789", str(caught.exception))
        self.assertIn("Arturo Castaneyra", str(caught.exception))


class LauncherBinaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.TemporaryDirectory()
        cls.binary = Path(cls.temp.name) / "tolkeins-collector"
        completed = subprocess.run(
            [
                "gcc",
                "-Wall",
                "-Wextra",
                "-Werror",
                "-O2",
                "-o",
                str(cls.binary),
                str(MACOS / "tolkeins-collector.c"),
                "-ldl",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def fake_python(self, directory: Path) -> Path:
        script = directory / "fake-python"
        script.write_text(
            """#!/bin/sh
{
  printf 'args:'
  for arg in "$@"; do
    printf ' [%s]' "$arg"
  done
  printf '\\n'
  printf 'PYTHONPATH=%s\\n' "${PYTHONPATH-}"
  printf 'CONFIG=%s\\n' "${TOLKEINS_CONFIG_DIR-}"
  ppid=$(ps -o ppid= -p $$ | tr -d ' ')
  printf 'parent='
  tr '\\0' ' ' < "/proc/${ppid}/cmdline"
  printf '\\n'
  gpid=$(ps -o ppid= -p "$ppid" | tr -d ' ')
  printf 'grand='
  if [ -r "/proc/${gpid}/cmdline" ]; then
    tr '\\0' ' ' < "/proc/${gpid}/cmdline"
  fi
  printf '\\n'
} > "$FAKE_OUT"
exit "$FAKE_EXIT"
""",
            encoding="utf-8",
        )
        script.chmod(0o755)
        return script

    def run_launcher(self, args: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(self.binary), *args],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

    def test_spawns_python_module_and_stays_parent(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            script = self.fake_python(directory)
            out = directory / "out.txt"
            env = {
                "PATH": "/usr/bin:/bin",
                "HOME": str(directory),
                "TOLKEINS_PYTHON": str(script),
                "FAKE_OUT": str(out),
                "FAKE_EXIT": "3",
                "TOLKEINS_TEST_DISCLAIM": "0",
            }
            completed = self.run_launcher(["--dry-run"], env)
            self.assertEqual(completed.returncode, 3, completed.stderr)
            text = out.read_text(encoding="utf-8")
            self.assertIn("args: [-m] [tolkeins] [--dry-run]", text)
            self.assertIn(f"PYTHONPATH={directory}/.local/share/tolkeins", text)
            self.assertIn(f"CONFIG={directory}/.config/tolkeins", text)
            self.assertIn("tolkeins-collector", text.split("parent=", 1)[1].split("\n", 1)[0])
            self.assertNotIn("tolkeins-collector", text.split("grand=", 1)[1].split("\n", 1)[0])

    def test_disclaim_bootstrap_keeps_two_helper_processes(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            script = self.fake_python(directory)
            out = directory / "out.txt"
            env = {
                "PATH": "/usr/bin:/bin",
                "HOME": str(directory),
                "TOLKEINS_PYTHON": str(script),
                "TOLKEINS_CONFIG_DIR": str(directory / "cfg"),
                "PYTHONPATH": str(directory / "pkg"),
                "FAKE_OUT": str(out),
                "FAKE_EXIT": "0",
                "TOLKEINS_TEST_DISCLAIM": "1",
            }
            completed = self.run_launcher([], env)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            text = out.read_text(encoding="utf-8")
            self.assertIn("args: [-m] [tolkeins]", text)
            self.assertIn(f"PYTHONPATH={directory}/pkg", text)
            self.assertIn(f"CONFIG={directory}/cfg", text)
            parent = text.split("parent=", 1)[1].split("\n", 1)[0]
            grand = text.split("grand=", 1)[1].split("\n", 1)[0]
            self.assertIn("tolkeins-collector", parent)
            self.assertIn("tolkeins-collector", grand)

    def test_relative_python_is_rejected(self) -> None:
        completed = self.run_launcher(
            [],
            {
                "PATH": "/usr/bin:/bin",
                "HOME": "/tmp",
                "TOLKEINS_PYTHON": "python3",
                "TOLKEINS_TEST_DISCLAIM": "0",
            },
        )
        self.assertEqual(completed.returncode, 127)
        self.assertIn("absolute path", completed.stderr)


class PrebuiltLauncherTests(unittest.TestCase):
    def test_slices_are_mach_o_executables(self) -> None:
        expected = {
            "tolkeins-collector-arm64": 0x0100000C,
            "tolkeins-collector-x86_64": 0x01000007,
        }
        for name, cpu in expected.items():
            blob = (MACOS / "prebuilt" / name).read_bytes()
            self.assertLess(len(blob), 200_000, name)
            self.assertEqual(blob[:4], b"\xcf\xfa\xed\xfe", name)
            self.assertEqual(int.from_bytes(blob[4:8], "little"), cpu, name)
            self.assertEqual(int.from_bytes(blob[12:16], "little"), 2, name)
            self.assertIn(b"/usr/bin/python3", blob)
            self.assertIn(b"-m", blob)
            self.assertIn(b"tolkeins", blob)
            self.assertIn(b"responsibility_spawnattrs_setdisclaim", blob)
            self.assertNotIn(b"WRITE_TOKEN", blob)
            self.assertTrue(_links_libsystem(blob), name)


def _links_libsystem(blob: bytes) -> bool:
    # mach_header_64 is 32 bytes. Walk load commands for a libSystem dylib.
    if len(blob) < 32:
        return False
    command_count = int.from_bytes(blob[16:20], "little")
    offset = 32
    for _ in range(command_count):
        if offset + 8 > len(blob):
            return False
        command = int.from_bytes(blob[offset : offset + 4], "little")
        size = int.from_bytes(blob[offset + 4 : offset + 8], "little")
        if size < 8 or offset + size > len(blob):
            return False
        if command == 0xC and offset + 24 <= len(blob):
            name_offset = int.from_bytes(blob[offset + 8 : offset + 12], "little")
            start = offset + name_offset
            end = blob.find(b"\x00", start)
            if end != -1 and b"libSystem" in blob[start:end]:
                return True
        offset += size
    return False


class ReportJsonTests(unittest.TestCase):
    def test_cli_reads_files(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            snapshot = directory / "snapshot.json"
            stderr = directory / "stderr.txt"
            snapshot.write_text(
                json.dumps(
                    {
                        "services": [
                            {"id": "gemini", "windows": [{"label": "Session", "usedPercent": 5}]},
                            {"id": "claudeplatform", "windows": [{"label": "Weekly", "usedPercent": 9}]},
                        ]
                    }
                ),
                encoding="utf-8",
            )
            stderr.write_text("gemini ok\nclaudeplatform ok\n", encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "tolkeins.chrome_status",
                    "--snapshot",
                    str(snapshot),
                    "--stderr",
                    str(stderr),
                ],
                check=False,
                capture_output=True,
                text=True,
                cwd=str(ROOT),
                env={"PYTHONPATH": str(ROOT), "PATH": "/usr/bin:/bin"},
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("result=pass", completed.stdout)
            self.assertIn("Session=5", completed.stdout)
            self.assertIn("Weekly=9", completed.stdout)


if __name__ == "__main__":
    unittest.main()
