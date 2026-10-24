"""POST a snapshot to the Worker. The body is usage numbers only."""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


class PublishError(RuntimeError):
    """The Worker refused the snapshot or could not be reached."""


def validate_worker_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url.strip())
    host = (parsed.hostname or "").lower()
    if parsed.scheme == "https" and host:
        return url.strip().rstrip("/")
    if parsed.scheme == "http" and host in {"127.0.0.1", "localhost"}:
        return url.strip().rstrip("/")
    raise PublishError("WORKER_URL must be an https URL")


def post_snapshot(url: str, token: str, snapshot: dict[str, Any], timeout: float = 30) -> None:
    if not token:
        raise PublishError("WRITE_TOKEN is empty")
    endpoint = validate_worker_url(url) + "/v1/snapshot"
    body = json.dumps(snapshot, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "tolkeins-collector/1",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = getattr(response, "status", 200)
            if status >= 300:
                raise PublishError(f"worker returned {status}")
    except urllib.error.HTTPError as error:
        try:
            detail = error.read(300).decode("utf-8", "replace")
        finally:
            error.close()
        message = f"worker returned {error.code}: {detail}"
        if token and token in message:
            message = message.replace(token, "[redacted]")
        raise PublishError(message) from None
    except urllib.error.URLError as error:
        raise PublishError(f"could not reach the worker: {error.reason}") from None
