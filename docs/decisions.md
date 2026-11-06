# Decisions

## 2026-11-06: One repository for the app and the companion

`cmdux-sh/tolkein` holds both projects. The CodexBar fork (the Mac menu-bar app) stays at the repository root. The former `cmdux-sh/tolkeins` repository (collector, Cloudflare Worker, iPhone widget) lives in `companion/`, imported with its history.

Why: the two repositories had nearly the same name and were easy to confuse. The companion reads the app, so the two belong together.

The app stays at the root and the root README is left as upstream wrote it, so syncing with `steipete/CodexBar` keeps merging cleanly.
