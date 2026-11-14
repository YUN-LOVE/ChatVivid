#!/usr/bin/env python3
"""Parse a release tag (or workflow_dispatch input) into platform matrices.

Tag rules (documented in docs/ci-cd.md):

  vX.Y.Z                          build/publish every enabled platform
  vX.Y.Z-<platform>[-<platform>]  only the listed platforms
  vX.Y.Z-rc.N / -beta.N / ...     semver prerelease: every enabled platform,
                                  published with prerelease=true
  anything else                   fail with a clear message

Platform suffixes and semver prerelease suffixes are not combined: a tag like
``v1.2.3-rc.1-android`` is treated as a prerelease of all platforms (the '-' is
shared by both schemes; the prerelease form wins).

Known platform names: android, ios, linux, macos, web, windows. A platform is
"enabled" once its app runner exists (app/android, app/ios, ...). Linux, macOS
and Windows also have a C++ backend. iOS/web stay disabled until scaffolded.

Outputs (to ``$GITHUB_OUTPUT``, or stdout when unset)::

  source, tag, version, platforms_label, platforms, backend_platforms,
  app_platforms, app_matrix, run_backend, run_app, publish, prerelease

Local simulation::

    python3 platforms/common/ci/parse-tag.py v0.2.0-android-linux
    python3 platforms/common/ci/parse-tag.py v0.2.0
    DISPATCH_PLATFORMS=linux python3 platforms/common/ci/parse-tag.py
"""

from __future__ import annotations

import json
import os
import re
import sys

# CI helper scripts are often run straight from a checkout; do not litter it.
sys.dont_write_bytecode = True

from lib import (
    ALL_PLATFORMS,
    APP_PLATFORMS,
    BACKEND_PLATFORMS,
    build_app_matrix,
    emit_outputs,
    buildable_platforms,
    find_repo_root,
    split_platform_list,
)

TAG_RE = re.compile(r"^v(?P<version>\d+\.\d+\.\d+)(?:-(?P<suffix>.+))?$")
# semver prerelease markers that used to be supported by the old workflow.
PRERELEASE_RE = re.compile(r"^(rc|beta|alpha|pre|dev)[.-]?\d", re.IGNORECASE)
JSON_OUTPUTS = (
    "platforms",
    "backend_platforms",
    "app_platforms",
    "app_matrix",
)

USAGE = """tag 格式无效: {tag}

用法:
  vX.Y.Z                         发布全部启用平台
  vX.Y.Z-<platform>[-<platform>] 只构建/发布列出的平台
  vX.Y.Z-rc.N / -beta.N / -alpha.N / -pre.N / -dev.N
                                 预发布：构建全部启用平台，Release 标记 prerelease
  合法平台: {platforms}

注意: 平台后缀与预发布后缀不能组合；v1.2.3-rc.1-android 会按预发布处理（全平台）。
"""


def parse_tag(tag: str) -> tuple[str, list[str] | None, bool]:
    """Return (version, platforms-or-None-for-all, prerelease). Raises ValueError."""
    match = TAG_RE.match(tag.strip())
    if not match:
        raise ValueError(USAGE.format(tag=tag, platforms=", ".join(ALL_PLATFORMS)))

    version = f"v{match.group('version')}"
    suffix = match.group("suffix")
    if suffix is None:
        return version, None, False

    if suffix.startswith("-") or suffix.endswith("-"):
        raise ValueError(USAGE.format(tag=tag, platforms=", ".join(ALL_PLATFORMS)))

    tokens = [token for token in suffix.split("-") if token]
    if tokens and all(token in ALL_PLATFORMS for token in tokens):
        requested = set(tokens)
        return version, [platform for platform in ALL_PLATFORMS if platform in requested], False

    # Backwards compatibility: the old release workflow published tags like
    # v0.1.0-rc.1 as a prerelease of every platform.
    if PRERELEASE_RE.match(suffix):
        return f"{version}-{suffix}", None, True

    unknown = [token for token in tokens if token not in ALL_PLATFORMS]
    raise ValueError(
        f"未知平台后缀: {', '.join(unknown) or suffix}\n"
        f"合法平台: {', '.join(ALL_PLATFORMS)}\n"
        "也支持 semver 预发布后缀（rc.N / beta.N / alpha.N / pre.N / dev.N）。"
    )


def main() -> int:
    root = find_repo_root()
    event_name = os.environ.get("EVENT_NAME", "").strip()
    is_dispatch = event_name == "workflow_dispatch"
    # TAG_NAME comes from the workflow; the positional form is for local simulation.
    tag = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("TAG_NAME", "")).strip()
    dispatch_raw = (os.environ.get("DISPATCH_PLATFORMS") or "").strip()

    # A release tag is an explicit human decision, so it builds every platform
    # that has a runner in-tree regardless of the CI macOS cost gate.
    enabled = buildable_platforms(root)

    try:
        if is_dispatch:
            if dispatch_raw and dispatch_raw.lower() != "all":
                requested = split_platform_list(dispatch_raw)
            else:
                requested = [p for p in ALL_PLATFORMS if p in enabled]
            version = "v0.0.0"
            source = "workflow_dispatch"
            publish = "false"  # manual runs upload artifacts, never publish
            prerelease = False
        else:
            version, requested, prerelease = parse_tag(tag)
            source = "tag"
            publish = "true"
            if requested is None:
                requested = [p for p in ALL_PLATFORMS if p in enabled]
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    disabled = [p for p in requested if p not in enabled]
    if disabled:
        hint = []
        if "ios" in disabled:
            hint.append("iOS: 需要 macOS runner + app/ios（flutter create --platforms=ios）+ 签名配置")
        if "web" in disabled:
            hint.append("web: 需要 app/web（flutter create --platforms=web）")
        print(
            "::error::请求的平台尚未启用: "
            + ", ".join(disabled)
            + "。"
            + ("；".join(hint) if hint else ""),
            file=sys.stderr,
        )
        return 1

    backend = [p for p in BACKEND_PLATFORMS if p in requested]
    app = [p for p in APP_PLATFORMS if p in requested]
    if not backend and not app:
        print(
            "::error::没有可构建的平台被选中；检查 tag 平台后缀或 ENABLE_MACOS_RUNNERS。",
            file=sys.stderr,
        )
        return 1

    matrix_mode = "release"
    outputs = {
        "source": source,
        "tag": tag if source == "tag" else "",
        "version": version,
        "platforms_label": ", ".join(requested),
        "platforms": json.dumps(requested, separators=(",", ":")),
        "backend_platforms": json.dumps(backend, separators=(",", ":")),
        "app_platforms": json.dumps(app, separators=(",", ":")),
        "app_matrix": json.dumps(build_app_matrix(set(app), matrix_mode), separators=(",", ":")),
        "run_backend": "true" if backend else "false",
        "run_app": "true" if app else "false",
        "publish": publish,
        "prerelease": "true" if prerelease else "false",
    }
    for name in JSON_OUTPUTS:
        json.loads(outputs[name])
    emit_outputs(outputs)

    print(
        f"parse-tag: source={source} version={version} "
        f"publish={publish} prerelease={outputs['prerelease']}"
    )
    print(f"parse-tag: platforms={outputs['platforms']}")
    print(f"parse-tag: backend_platforms={outputs['backend_platforms']}")
    print(f"parse-tag: app_platforms={outputs['app_platforms']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
