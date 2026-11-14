#!/usr/bin/env python3
"""Shared helpers for the chatvv CI path/tag classification scripts.

Used by ``detect-changes.py`` (push/PR/manual CI) and ``parse-tag.py``
(release tags). Keep the platform registry here so workflows, docs and scripts
cannot drift apart.

The scripts are plain Python 3 (standard library only) so they can be run
locally to simulate CI without any extra dependencies::

    python3 platforms/common/ci/detect-changes.py
    python3 platforms/common/ci/parse-tag.py v0.2.0-android-linux
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Canonical ordering: used for stable JSON output, job matrices and docs.
ALL_PLATFORMS = ("android", "ios", "linux", "macos", "windows")
BACKEND_PLATFORMS = ("linux", "macos", "windows")
APP_PLATFORMS = ("android", "ios", "linux", "macos", "windows")

# --- Path classification -----------------------------------------------------

# A change here requires every enabled platform to be rebuilt.
SHARED_PREFIXES = (
    "src/",
    "app/",
    "cmake/",
    "include/",
    "config/",
    "tests/",
    "third_party/",
    "platforms/common/",
    "scripts/",
)
SHARED_EXACT = (
    "CMakeLists.txt",
    "CMakePresets.json",
    "vcpkg.json",
)

# Changes here do not need a rebuild; the lightweight lint job is enough.
LIGHT_PREFIXES = (
    "docs/",
    "reference/",
    "archive/",
    "packaging/",
    ".github/",  # workflows themselves are handled before this tuple
)
LIGHT_EXACT = (
    "README.md",
    "CONTRIBUTING.md",
    "LICENSE",
    "ATTRIBUTION.md",
    ".gitignore",
    ".gitattributes",
    ".editorconfig",
    "platforms/README.md",
)
LIGHT_SUFFIXES = (".md",)

_PLATFORM_DIR_RE = re.compile(r"^platforms/([^/]+)/")


def classify_path(path: str) -> tuple[str, str | None]:
    """Classify one repository-relative path.

    Returns ``(kind, platform)`` where kind is one of:
      * ``"shared"``   - rebuild every enabled platform,
      * ``"platform"`` - only the returned platform,
      * ``"light"``    - documentation/packaging only, no rebuild.
    Unknown paths are treated as shared so new directories never silently skip
    CI. That is the conservative default; add them to the light list once the
    behaviour is clear.
    """
    if path.startswith(".github/workflows/"):
        # Workflow edits are validated by running the affected builds.
        return ("shared", None)

    match = _PLATFORM_DIR_RE.match(path)
    if match:
        platform = match.group(1)
        if platform == "common":
            return ("shared", None)
        if platform in ALL_PLATFORMS:
            return ("platform", platform)
        # platforms/<unknown>/: conservative, treat as shared.
        return ("shared", None)

    if path in SHARED_EXACT or any(path.startswith(p) for p in SHARED_PREFIXES):
        return ("shared", None)

    if path in LIGHT_EXACT or any(path.startswith(p) for p in LIGHT_PREFIXES):
        return ("light", None)
    if path.endswith(LIGHT_SUFFIXES):
        return ("light", None)

    return ("shared", None)


# --- Platform enablement -----------------------------------------------------


def find_repo_root() -> Path:
    """Locate the repository root from this file (platforms/common/ci/lib.py)."""
    return Path(__file__).resolve().parents[3]


def truthy(value: str | None) -> bool:
    return (value or "").strip().lower() in ("1", "true", "yes", "on")


def app_runner_exists(root: Path, platform: str) -> bool:
    return (root / "app" / platform).is_dir()


def buildable_platforms(root: Path) -> set[str]:
    """Platforms that have a buildable backend/app runner on this branch.

    * backend: Linux (x64 + arm64), macOS and Windows always exist in-tree;
    * app: a platform is enabled once its Flutter runner exists. iOS stays
      disabled until ``app/ios`` is scaffolded. Web is not a target at all
      (the old Web GalGame frontend is archived under ``archive/``).
    """
    buildable: set[str] = set(BACKEND_PLATFORMS)
    for platform in APP_PLATFORMS:
        if app_runner_exists(root, platform):
            buildable.add(platform)
    return buildable


def ci_platforms(root: Path, *, enable_macos: bool = True) -> set[str]:
    """Platforms automatically selected by path changes in CI.

    Hosted macOS runners are billed at 10x, so shared-path changes skip macOS
    unless the ENABLE_MACOS_RUNNERS repository variable is true. This gate is
    only about *automatic* selection: an explicit ``platforms/macos/**`` edit, a
    manual ``platforms=macos`` dispatch, or a release tag still builds macOS.
    """
    buildable = buildable_platforms(root)
    if enable_macos:
        return buildable
    return buildable - {"macos"}


# --- App package matrix ------------------------------------------------------


def _artifact_name(platform: str, mode: str) -> str:
    if mode == "ci" and platform == "android":
        return "chatvv-app-android-debug"
    return f"chatvv-app-{platform}"


# Matrix dimensions: strings are compared in `if:` expressions; `timeout` is a
# JSON number because jobs.timeout-minutes expects a number.
APP_RUNNERS: dict[str, dict[str, str]] = {
    "android": {
        "runner": "ubuntu-latest",
        "timeout": 90,
        "rust_targets": "aarch64-linux-android,armv7-linux-androideabi",
        "vulkan": "ON",
    },
    "ios": {
        "runner": "macos-14",
        "timeout": 60,
        "rust_targets": "aarch64-apple-ios",
        "vulkan": "OFF",
    },
    "linux": {
        "runner": "ubuntu-latest",
        "timeout": 90,
        "rust_targets": "x86_64-unknown-linux-gnu",
        "vulkan": "ON",
    },
    "macos": {
        "runner": "macos-14",
        "timeout": 60,
        "rust_targets": "aarch64-apple-darwin,x86_64-apple-darwin",
        "vulkan": "OFF",
    },
    "windows": {
        "runner": "windows-2022",
        "timeout": 120,
        "rust_targets": "x86_64-pc-windows-msvc",
        "vulkan": "ON",
    },
}

APP_PACKAGE_COMMANDS: dict[str, dict[str, str]] = {
    "ci": {
        "android": "CHATVV_APK_MODE=debug ./platforms/android/package-apk.sh",
        "ios": "./platforms/ios/package.sh",
        "linux": "./platforms/linux/package.sh",
        "macos": "./platforms/macos/package.sh",
        "windows": "./platforms/windows/package.ps1",
    },
    "release": {
        "android": "CHATVV_APK_MODE=release ./platforms/android/package-apk.sh",
        "ios": "./platforms/ios/package.sh",
        "linux": "./platforms/linux/package.sh",
        "macos": "./platforms/macos/package.sh",
        "windows": "./platforms/windows/package.ps1",
    },
}


def build_app_matrix(platforms: set[str], mode: str) -> dict:
    """Build the JSON object consumed by ``strategy.matrix`` in the workflows.

    ``{"include": [{"platform": ..., "runner": ..., ...}, ...]}``: a matrix with
    only include entries is valid, and GitHub Actions evaluates ``matrix``
    expressions, so the job only runs the platforms selected by detect/parse-tag.
    """
    if mode not in APP_PACKAGE_COMMANDS:
        raise ValueError(f"unknown app matrix mode: {mode}")
    entries = []
    for platform in ALL_PLATFORMS:
        if platform not in platforms:
            continue
        entry = dict(APP_RUNNERS[platform])
        entry["platform"] = platform
        entry["command"] = APP_PACKAGE_COMMANDS[mode][platform]
        entry["artifact"] = _artifact_name(platform, mode)
        entry["artifact_path"] = "artifacts/*"
        entries.append(entry)
    return {"include": entries}


# --- Output plumbing ---------------------------------------------------------

JSON_OUTPUTS = ("platforms", "backend_platforms", "app_platforms", "app_matrix")


def build_outputs(
    *,
    backend_platforms: list[str],
    app_platforms: list[str],
    mode: str,
    reason: str,
    changed_count: int,
) -> dict[str, str]:
    """Assemble the GitHub Actions step outputs (all values are strings)."""
    selected = [
        platform
        for platform in ALL_PLATFORMS
        if platform in backend_platforms or platform in app_platforms
    ]
    outputs = {
        "mode": mode,
        "reason": reason,
        "changed_count": str(changed_count),
        "platforms": json.dumps(selected, separators=(",", ":")),
        "backend_platforms": json.dumps(backend_platforms, separators=(",", ":")),
        "app_platforms": json.dumps(app_platforms, separators=(",", ":")),
        "app_matrix": json.dumps(build_app_matrix(set(app_platforms), "ci"), separators=(",", ":")),
        "run_backend": "true" if backend_platforms else "false",
        "run_app": "true" if app_platforms else "false",
        "light_only": "true" if not backend_platforms and not app_platforms else "false",
    }
    for platform in BACKEND_PLATFORMS:
        outputs[f"backend_{platform}"] = "true" if platform in backend_platforms else "false"
    return outputs


def emit_outputs(outputs: dict[str, str]) -> None:
    """Write step outputs to ``$GITHUB_OUTPUT``; print them when running locally."""
    for name in JSON_OUTPUTS:
        json.loads(outputs[name])  # fail loudly instead of smuggling invalid JSON into CI
    output_path = os.environ.get("GITHUB_OUTPUT")
    lines = [f"{name}={value}" for name, value in outputs.items()]
    if output_path:
        with open(output_path, "a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
    else:
        print("\n".join(lines))


# --- Git helpers -------------------------------------------------------------


def run_git(root: Path, args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def commit_exists(root: Path, revision: str) -> bool:
    if not revision or set(revision) == {"0"}:
        return False
    result = run_git(root, ["cat-file", "-e", f"{revision}^{{commit}}"])
    return result.returncode == 0


def git_diff_files(root: Path, spec: str) -> list[str] | None:
    """Return changed paths for a ``git diff`` revision spec, or None on error."""
    result = run_git(root, ["diff", "--name-only", "-z", spec])
    if result.returncode != 0:
        return None
    return [item for item in result.stdout.split("\0") if item]


def split_platform_list(raw: str) -> list[str]:
    """Parse a comma/space separated platform list, validating names."""
    tokens = [token for token in re.split(r"[,\s]+", raw.strip()) if token]
    unknown = [token for token in tokens if token.lower() not in ALL_PLATFORMS]
    if unknown:
        raise ValueError(
            "未知平台: "
            + ", ".join(unknown)
            + "；合法平台: "
            + ", ".join(ALL_PLATFORMS)
        )
    requested = {token.lower() for token in tokens}
    return [platform for platform in ALL_PLATFORMS if platform in requested]


def warn(message: str) -> None:
    print(f"::warning::{message}", file=sys.stderr)
