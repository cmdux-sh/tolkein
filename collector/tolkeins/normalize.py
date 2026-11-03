"""Turn CodexBar payloads plus subscriptions.yaml into a public snapshot.

Account emails and identity objects are dropped before the snapshot exists.
Only usage numbers, plan labels, and reset times are published.
"""

from __future__ import annotations

import re
import sys
from calendar import monthrange
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from tolkeins.yaml_lite import YAMLError, parse_yaml


SCHEMA_VERSION = 1
# worker/src/snapshot.ts requireString max for services[].error.message.
ERROR_MESSAGE_LIMIT = 240
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")
DROP_KEYS = {
    "accountemail",
    "identity",
    "email",
    "accountid",
    "accountalias",
    "loginmethod",
}
SIGN_IN_HINTS = (
    "sign-in",
    "sign in",
    "signed in",
    "session",
    "not logged",
    "log in",
    "login",
    "unauthorized",
    "cookie",
    "api key",
    "no available fetch",
    "authenticate",
    "auth",
)
WEEKDAYS = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}
DEFAULT_NAMES = {
    "claude": "Claude",
    "codex": "Codex",
    "cursor": "Cursor",
    "warp": "Warp",
    "grok": "Grok",
}
PACE_FIELDS = (
    "stage",
    "willLastToReset",
    "expectedUsedPercent",
    "deltaPercent",
    "summary",
    "etaSeconds",
)


class SubscriptionError(ValueError):
    """subscriptions.yaml could not be read."""


def load_subscriptions(text: str) -> dict[str, dict[str, Any]]:
    try:
        parsed = parse_yaml(text)
    except YAMLError as error:
        raise SubscriptionError(str(error)) from error
    if parsed is None:
        return {}
    if not isinstance(parsed, dict):
        raise SubscriptionError("subscriptions.yaml must be a mapping")
    services = parsed.get("services") or {}
    if services is None:
        return {}
    if not isinstance(services, dict):
        raise SubscriptionError("services must be a mapping of provider id to settings")
    normalized: dict[str, dict[str, Any]] = {}
    for key, value in services.items():
        if not isinstance(value, dict):
            raise SubscriptionError(f"services.{key} must be a mapping")
        normalized[str(key)] = value
    return normalized


def build_snapshot(
    payloads: dict[str, Any],
    subscriptions: dict[str, dict[str, Any]],
    providers: tuple[str, ...] | list[str],
    generated_at: datetime,
) -> dict[str, Any]:
    services: list[dict[str, Any]] = []
    seen: set[str] = set()
    for provider in list(providers) + [key for key in subscriptions if key not in providers]:
        if provider in seen:
            continue
        seen.add(provider)
        services.append(
            normalize_service(
                provider,
                payloads.get(provider),
                subscriptions.get(provider),
                generated_at,
            )
        )
    snapshot = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": iso_z(generated_at),
        "services": services,
    }
    return scrub(snapshot)


def normalize_service(
    provider: str,
    payload: Any,
    subscription: dict[str, Any] | None,
    generated_at: datetime,
) -> dict[str, Any]:
    subscription = subscription or {}
    record = _select_record(provider, payload)
    error = _error_from_record(record)
    live_windows = _windows_from_record(record)
    manual_windows, manual_error = _manual_windows(subscription, generated_at)
    windows = _merge_windows(live_windows, manual_windows)
    # A per-service CodexBar failure must not blank out numbers we do have.
    # Sign-in and source errors are only the service state when nothing usable came back.
    if windows:
        error = None
    elif manual_error is not None:
        error = manual_error
    elif error is None:
        error = {"message": "CodexBar returned no usage", "kind": "collector"}

    usage = record.get("usage") if isinstance(record.get("usage"), dict) else {}
    plan = subscription.get("plan")
    if not isinstance(plan, str) or not plan.strip():
        login_method = usage.get("loginMethod") if isinstance(usage, dict) else None
        plan = login_method if isinstance(login_method, str) and login_method.strip() else None
    name = subscription.get("name")
    if not isinstance(name, str) or not name.strip():
        name = DEFAULT_NAMES.get(provider, provider.title())

    source = "manual" if manual_windows and not live_windows else None
    if source is None:
        raw_source = record.get("source")
        source = raw_source.strip() if isinstance(raw_source, str) and raw_source.strip() else "codexbar"

    fetched_at = generated_at
    updated = usage.get("updatedAt") if isinstance(usage, dict) else None
    parsed_updated = _parse_iso(updated) if isinstance(updated, str) else None
    if parsed_updated is not None:
        fetched_at = parsed_updated

    service: dict[str, Any] = {
        "id": provider,
        "name": name.strip(),
        "windows": windows,
        "source": source,
        "fetchedAt": iso_z(fetched_at),
    }
    if isinstance(plan, str) and plan.strip():
        service["plan"] = plan.strip()
    pace = _pace(record.get("pace"))
    if pace:
        service["pace"] = pace
    credits = _credits(record)
    if credits:
        service["credits"] = credits
    renews_on = subscription.get("renewsOn")
    if isinstance(renews_on, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", renews_on):
        service["renewsOn"] = renews_on
    price = _price(subscription.get("price"))
    if price:
        service["price"] = price
    if error:
        service["error"] = _publish_error(provider, error)
    return service


def clamp_error_message(text: str, limit: int = ERROR_MESSAGE_LIMIT) -> str:
    """Fit a service error into the worker's message limit, keeping an ellipsis."""

    if len(text) <= limit:
        return text
    ellipsis = "..."
    head = text[: limit - len(ellipsis)].rstrip()
    return f"{head}{ellipsis}"


def _publish_error(provider: str, error: dict[str, str]) -> dict[str, str]:
    message = error.get("message") or "Unknown error"
    clamped = clamp_error_message(message)
    if clamped != message:
        print(f"{provider} error message: {message}", file=sys.stderr)
    published = dict(error)
    published["message"] = clamped
    return published


def scrub(value: Any) -> Any:
    if isinstance(value, dict):
        cleaned: dict[str, Any] = {}
        for key, item in value.items():
            if str(key).lower() in DROP_KEYS:
                continue
            cleaned[str(key)] = scrub(item)
        return cleaned
    if isinstance(value, list):
        return [scrub(item) for item in value]
    if isinstance(value, str):
        return EMAIL_RE.sub("", value)
    return value


def iso_z(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _select_record(provider: str, payload: Any) -> dict[str, Any]:
    if isinstance(payload, dict):
        records = [payload]
    elif isinstance(payload, list):
        records = [item for item in payload if isinstance(item, dict)]
    else:
        records = []
    if not records:
        return {
            "provider": provider,
            "source": "codexbar",
            "error": {"message": "CodexBar returned no usage", "kind": "collector"},
        }
    for record in records:
        if record.get("provider") == provider:
            return record
    return records[0]


def _error_from_record(record: dict[str, Any]) -> dict[str, str] | None:
    error = record.get("error")
    if not isinstance(error, dict):
        return None
    return _classify_error(error)


def _classify_error(error: dict[str, Any]) -> dict[str, str]:
    message = error.get("message")
    text = message.strip() if isinstance(message, str) and message.strip() else "Unknown CodexBar error"
    text = EMAIL_RE.sub("", text).strip() or "Unknown error"
    lowered = text.lower()
    raw_kind = error.get("kind")
    if raw_kind == "collector":
        kind = "collector"
    elif "keychain permission" in lowered or "safe storage" in lowered:
        kind = "unavailable"
    elif any(hint in lowered for hint in SIGN_IN_HINTS):
        kind = "needs-sign-in"
    else:
        kind = "unavailable"
    return {"message": text or "Unknown error", "kind": kind}


def _windows_from_record(record: dict[str, Any]) -> list[dict[str, Any]]:
    usage = record.get("usage")
    if not isinstance(usage, dict):
        return []
    labels = record.get("rateWindowLabels") if isinstance(record.get("rateWindowLabels"), dict) else {}
    windows: list[dict[str, Any]] = []
    used_labels: set[str] = set()
    for key, fallback in (("primary", "Session"), ("secondary", "Weekly"), ("tertiary", "Other")):
        raw = usage.get(key)
        if not isinstance(raw, dict):
            continue
        label = labels.get(key) if isinstance(labels, dict) else None
        if not isinstance(label, str) or not label.strip():
            label = _fallback_label(raw, fallback)
        window = _window(label, raw, used_labels)
        if window:
            windows.append(window)
    extras = usage.get("extraRateWindows")
    if isinstance(extras, list):
        for extra in extras:
            if not isinstance(extra, dict):
                continue
            raw = extra.get("window")
            if not isinstance(raw, dict):
                continue
            label = extra.get("title") or extra.get("id") or "Extra"
            window = _window(str(label), raw, used_labels)
            if window:
                windows.append(window)
    return windows


def _window(label: str, raw: dict[str, Any], used_labels: set[str]) -> dict[str, Any] | None:
    percent = raw.get("usedPercent")
    if isinstance(percent, bool) or not isinstance(percent, (int, float)):
        return None
    window: dict[str, Any] = {
        "label": _unique_label(label, used_labels),
        "usedPercent": _clamp_percent(float(percent)),
    }
    resets_at = raw.get("resetsAt")
    if isinstance(resets_at, str) and _parse_iso(resets_at) is not None:
        window["resetsAt"] = iso_z(_parse_iso(resets_at))  # type: ignore[arg-type]
    minutes = raw.get("windowMinutes")
    if isinstance(minutes, bool):
        minutes = None
    if isinstance(minutes, (int, float)) and minutes >= 0:
        window["windowMinutes"] = int(minutes)
    return window


def _merge_windows(live: list[dict[str, Any]], manual: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen = {window["label"].casefold() for window in live}
    merged = list(live)
    for window in manual:
        if window["label"].casefold() in seen:
            continue
        merged.append(window)
        seen.add(window["label"].casefold())
    return merged


def _manual_windows(
    subscription: dict[str, Any],
    now: datetime,
) -> tuple[list[dict[str, Any]], dict[str, str] | None]:
    raw_windows = subscription.get("manualWindows")
    if raw_windows is None:
        return [], None
    if not isinstance(raw_windows, list):
        return [], {"message": "manualWindows must be a list", "kind": "collector"}
    windows: list[dict[str, Any]] = []
    used_labels: set[str] = set()
    for raw in raw_windows:
        if not isinstance(raw, dict):
            return [], {"message": "a manual window must be a mapping", "kind": "collector"}
        try:
            windows.append(_manual_window(raw, now, used_labels))
        except (SubscriptionError, ZoneInfoNotFoundError) as error:
            return [], {"message": str(error), "kind": "collector"}
    return windows, None


def _manual_window(raw: dict[str, Any], now: datetime, used_labels: set[str]) -> dict[str, Any]:
    label = raw.get("label")
    if not isinstance(label, str) or not label.strip():
        raise SubscriptionError("a manual window needs a label")
    percent = raw.get("usedPercent")
    if isinstance(percent, bool) or not isinstance(percent, (int, float)):
        raise SubscriptionError(f"{label} needs a numeric usedPercent")
    window: dict[str, Any] = {
        "label": _unique_label(label, used_labels),
        "usedPercent": _clamp_percent(float(percent)),
    }
    minutes = raw.get("windowMinutes")
    if isinstance(minutes, (int, float)) and not isinstance(minutes, bool) and minutes >= 0:
        window["windowMinutes"] = int(minutes)
    resets_at = raw.get("resetsAt")
    if isinstance(resets_at, str) and resets_at.strip():
        parsed = _parse_iso(resets_at)
        if parsed is None:
            raise SubscriptionError(f"{label} resetsAt is not an ISO timestamp")
        window["resetsAt"] = iso_z(parsed)
        return window
    weekday = raw.get("resetWeekday")
    month_day = raw.get("resetMonthDay")
    if weekday is None and month_day is None:
        return window
    reset_time = raw.get("resetTime") or "00:00"
    timezone_name = raw.get("timezone") or "UTC"
    if not isinstance(reset_time, str) or not isinstance(timezone_name, str):
        raise SubscriptionError(f"{label} resetTime and timezone must be strings")
    weekday_index = None
    if weekday is not None:
        if not isinstance(weekday, str) or weekday.lower() not in WEEKDAYS:
            raise SubscriptionError(f"{label} resetWeekday must be a weekday name")
        weekday_index = WEEKDAYS[weekday.lower()]
    day_index = None
    if month_day is not None:
        if isinstance(month_day, bool) or not isinstance(month_day, int) or not 1 <= month_day <= 31:
            raise SubscriptionError(f"{label} resetMonthDay must be from 1 to 31")
        day_index = month_day
    window["resetsAt"] = iso_z(
        next_reset(
            now,
            weekday=weekday_index,
            month_day=day_index,
            reset_time=reset_time,
            timezone_name=timezone_name,
        )
    )
    return window


def next_reset(
    now: datetime,
    weekday: int | None,
    month_day: int | None,
    reset_time: str,
    timezone_name: str,
) -> datetime:
    """Next reset strictly after `now` in the given IANA timezone."""

    try:
        zone = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError as error:
        raise SubscriptionError(f"unknown timezone {timezone_name}") from error
    hour, minute = _parse_hhmm(reset_time)
    local_now = now.astimezone(zone)
    if weekday is not None:
        days_ahead = (weekday - local_now.weekday()) % 7
        candidate = (local_now + timedelta(days=days_ahead)).replace(
            hour=hour,
            minute=minute,
            second=0,
            microsecond=0,
        )
        if candidate <= local_now:
            candidate += timedelta(days=7)
        return candidate.astimezone(timezone.utc)
    if month_day is not None:
        candidate = _month_reset(local_now.year, local_now.month, month_day, hour, minute, zone)
        if candidate <= local_now:
            year, month = local_now.year, local_now.month + 1
            if month == 13:
                year, month = year + 1, 1
            candidate = _month_reset(year, month, month_day, hour, minute, zone)
        return candidate.astimezone(timezone.utc)
    raise SubscriptionError("manual window needs resetsAt, resetWeekday, or resetMonthDay")


def _month_reset(year: int, month: int, month_day: int, hour: int, minute: int, zone: ZoneInfo) -> datetime:
    day = min(month_day, monthrange(year, month)[1])
    return datetime(year, month, day, hour, minute, tzinfo=zone)


def _parse_hhmm(value: str) -> tuple[int, int]:
    match = re.fullmatch(r"(\d{1,2}):(\d{2})", value.strip())
    if match is None:
        raise SubscriptionError(f"resetTime must be HH:MM, got {value!r}")
    hour, minute = int(match.group(1)), int(match.group(2))
    if hour > 23 or minute > 59:
        raise SubscriptionError(f"resetTime must be HH:MM, got {value!r}")
    return hour, minute


def _pace(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    pace: dict[str, Any] = {}
    for key in ("primary", "secondary"):
        side = raw.get(key)
        if not isinstance(side, dict):
            continue
        cleaned: dict[str, Any] = {}
        for field in PACE_FIELDS:
            if field not in side:
                continue
            value = side[field]
            if isinstance(value, str):
                cleaned[field] = EMAIL_RE.sub("", value)[:240]
            elif isinstance(value, (int, float, bool)):
                cleaned[field] = value
        if cleaned:
            pace[key] = cleaned
    return pace or None


def _credits(record: dict[str, Any]) -> dict[str, Any] | None:
    credits = record.get("credits") if isinstance(record.get("credits"), dict) else {}
    if credits.get("balanceReadSucceeded") is False:
        return None
    usage = record.get("usage") if isinstance(record.get("usage"), dict) else {}
    cost = usage.get("providerCost") if isinstance(usage.get("providerCost"), dict) else {}
    remaining = credits.get("remaining")
    if isinstance(remaining, bool) or not isinstance(remaining, (int, float)):
        remaining = cost.get("balance")
    if isinstance(remaining, bool) or not isinstance(remaining, (int, float)):
        return None
    result: dict[str, Any] = {"remaining": remaining}
    currency = cost.get("currencyCode")
    if isinstance(currency, str) and currency.strip():
        result["currencyCode"] = currency.strip()
    return result


def _price(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    amount = raw.get("amount")
    if isinstance(amount, bool) or not isinstance(amount, (int, float)):
        return None
    currency = raw.get("currency")
    interval = raw.get("interval") or "month"
    if not isinstance(currency, str) or len(currency.strip()) != 3:
        return None
    if interval not in {"month", "year"}:
        return None
    return {"amount": amount, "currency": currency.strip().upper(), "interval": interval}


def _fallback_label(raw: dict[str, Any], fallback: str) -> str:
    minutes = raw.get("windowMinutes")
    if minutes == 10080:
        return "Weekly"
    if isinstance(minutes, (int, float)) and not isinstance(minutes, bool) and minutes <= 360:
        return "Session"
    return fallback


def _unique_label(label: str, used: set[str]) -> str:
    base = " ".join(label.split()) or "Window"
    if base not in used:
        used.add(base)
        return base
    index = 2
    while f"{base} {index}" in used:
        index += 1
    deduped = f"{base} {index}"
    used.add(deduped)
    return deduped


def _clamp_percent(value: float) -> int | float:
    clamped = min(100.0, max(0.0, value))
    if clamped.is_integer():
        return int(clamped)
    return round(clamped, 2)


def _parse_iso(value: str) -> datetime | None:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)
