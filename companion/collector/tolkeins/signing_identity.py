"""Choose a stable codesign identity for Tolkeins Collector.app.

Apple Development and Developer ID certificates survive rebuilds of the app.
The local self-signed certificate is only used when neither is available.
"""

from __future__ import annotations

import argparse
import re
import sys


APPLE_DEVELOPMENT_PREFIX = "Apple Development:"
DEVELOPER_ID_PREFIX = "Developer ID Application:"
LOCAL_IDENTITY = "local"
LOCAL_SENTINELS = {"local", "Tolkeins Collector"}
QUOTED_NAME = re.compile(r'"([^"]+)"')


class SigningIdentityError(ValueError):
    """TOLKEINS_SIGN_IDENTITY does not match a usable codesign identity."""


def identity_names(find_identity_text: str) -> list[str]:
    """Quoted identity names from `security find-identity`. Hashes are ignored."""

    return [match.group(1) for match in QUOTED_NAME.finditer(find_identity_text)]


def choose_signing_identity(names: list[str], override: str | None) -> str | None:
    """Return the identity name codesign should use.

    None means the installer should create the local Tolkeins Collector certificate.
    Apple Development wins over Developer ID so a later extra certificate does not
    change the designated requirement on its own.
    """

    wanted = override.strip() if override is not None else ""
    if wanted:
        if wanted in LOCAL_SENTINELS:
            return None
        if wanted not in names:
            available = ", ".join(names) if names else "(none)"
            raise SigningIdentityError(
                f"TOLKEINS_SIGN_IDENTITY is not a valid codesigning identity: {wanted}. "
                f"Available: {available}"
            )
        return wanted
    for prefix in (APPLE_DEVELOPMENT_PREFIX, DEVELOPER_ID_PREFIX):
        for name in names:
            if name.startswith(prefix):
                return name
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Choose the Tolkeins Collector codesign identity.")
    parser.add_argument("--override", default="")
    args = parser.parse_args(argv)
    try:
        chosen = choose_signing_identity(identity_names(sys.stdin.read()), args.override or None)
    except SigningIdentityError as error:
        print(str(error), file=sys.stderr)
        return 2
    sys.stdout.write(f"{chosen or LOCAL_IDENTITY}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
