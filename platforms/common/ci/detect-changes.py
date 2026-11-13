#!/usr/bin/env python3
"""Classify changed paths into the platforms/jobs that must run for CI.

Writes GitHub Actions step outputs (or plain ``name=value`` lines when
``GITHUB_OUTPUT`` is unset, which makes local simulation easy):

  mode               shared | platforms | dispatch | light
  reason             short human-readable summary
  changed_count      number of changed files considered
  platforms          JSON array, e.g. ["android","linux"]
  backend_platforms  JSON array subset of ["linux","macos","windows"]
  app_platforms      JSON array subset of ["android","ios","linux","macos","web","windows"]
  app_matrix         JSON object for the dynamic app-package matrix
  run_backend        "true"/"false"
  run_app            "true"/"false"
  light_only         "true"/"false"  (lint job only)
  backend_linux / backend_macos / backend_windows

Environment (set by .github/workflows/ci.yml):
  EVENT_NAME, BEFORE_SHA, PR_BASE_SHA, HEAD_SHA, DISPATCH_PLATFORMS,
  CHATVV_ENABLE_MACOS

Local simulation::

    DISPATCH_PLATFORMS=android,web python3 platforms/common/ci/detect-changes.py
    EVENT_NAME=push BEFORE_SHA=<sha> HEAD_SHA=<sha> python3 .../detect-changes.py
"""

from __future__ import annotations

import os
import sys

# CI helper scripts are often run straight from a checkout; do not litter it.
sys.dont_write_bytecode = True

from lib import (
    ALL_PLATFORMS,
    APP_PLATFORMS,
    BACKEND_PLATFORMS,
    build_outputs,
    buildable_platforms,
    classify_path,
    commit_exists,
    emit_outputs,
    ci_platforms,
    find_repo_root,
    git_diff_files,
    run_git,
    split_platform_list,
    truthy,
    warn,
)


def changed_files(root, event_name, before_sha, pr_base_sha, head_sha):
    """Return (files, reason); ``None`` means "cannot tell, run everything"."""
    if event_name == "pull_request" and pr_base_sha and head_sha:
        # PR merge commits need the base history; fetch it explicitly (fork PRs
        # may not have it after the default checkout).
        run_git(root, ["fetch", "--no-tags", "--quiet", "origin", pr_base_sha])
        files = git_diff_files(root, f"{pr_base_sha}...{head_sha}")
        if files is not None:
            return files, f"pull_request {pr_base_sha[:8]}...{head_sha[:8]}"
        files = git_diff_files(root, f"{pr_base_sha}..{head_sha}")
        if files is not None:
            return files, f"pull_request {pr_base_sha[:8]}..{head_sha[:8]}"
        return None, "无法对比 PR base/head，保守运行全部平台"

    if before_sha and commit_exists(root, before_sha) and head_sha:
        files = git_diff_files(root, f"{before_sha}..{head_sha}")
        if files is not None:
            return files, f"push {before_sha[:8]}..{head_sha[:8]}"
        return None, "git diff 失败，保守运行全部平台"

    return None, "无法确定变更范围（新分支/强制推送），保守运行全部平台"


def main() -> int:
    root = find_repo_root()
    event_name = os.environ.get("EVENT_NAME", "").strip()
    enable_macos = truthy(os.environ.get("CHATVV_ENABLE_MACOS"))
    # "buildable" = has a runner in-tree; "enabled" additionally applies the
    # macOS cost gate to *automatic* (shared-path) selection. Explicit changes
    # (platforms/<p>/**, manual dispatch) may pick macOS even when gated off.
    buildable = buildable_platforms(root)
    enabled = ci_platforms(root, enable_macos=enable_macos)
    dispatch_raw = (os.environ.get("DISPATCH_PLATFORMS") or "").strip()

    if event_name == "workflow_dispatch":
        try:
            if dispatch_raw and dispatch_raw.lower() != "all":
                requested = split_platform_list(dispatch_raw)
            else:
                requested = [p for p in ALL_PLATFORMS if p in enabled]
        except ValueError as error:
            print(f"::error::{error}", file=sys.stderr)
            return 1

        disabled = [p for p in requested if p not in buildable]
        if disabled:
            print(
                "::error::手动选择的平台尚未启用: "
                + ", ".join(disabled)
                + "。iOS 需要 app/ios（macOS runner + 签名），web 需要 app/web。",
                file=sys.stderr,
            )
            return 1

        backend = [p for p in BACKEND_PLATFORMS if p in requested]
        app = [p for p in APP_PLATFORMS if p in requested]
        reason = "workflow_dispatch: " + (", ".join(requested) if requested else "全部启用平台")
        outputs = build_outputs(
            backend_platforms=backend,
            app_platforms=app,
            mode="dispatch",
            reason=reason,
            changed_count=0,
        )
    else:
        files, reason = changed_files(
            root,
            event_name,
            os.environ.get("BEFORE_SHA", ""),
            os.environ.get("PR_BASE_SHA", ""),
            os.environ.get("HEAD_SHA", ""),
        )

        if files is None:
            backend = [p for p in BACKEND_PLATFORMS if p in enabled]
            app = [p for p in APP_PLATFORMS if p in enabled]
            outputs = build_outputs(
                backend_platforms=backend,
                app_platforms=app,
                mode="shared",
                reason=reason,
                changed_count=0,
            )
        else:
            shared = False
            platform_hits: set[str] = set()
            light_files = 0
            for path in files:
                kind, platform = classify_path(path)
                if kind == "shared":
                    shared = True
                elif kind == "platform" and platform:
                    platform_hits.add(platform)
                else:
                    light_files += 1

            if shared:
                backend = [p for p in BACKEND_PLATFORMS if p in enabled]
                app = [p for p in APP_PLATFORMS if p in enabled]
                outputs = build_outputs(
                    backend_platforms=backend,
                    app_platforms=app,
                    mode="shared",
                    reason=f"共享路径变更，重建全部启用平台（{reason}）",
                    changed_count=len(files),
                )
            elif platform_hits:
                backend = []
                app = []
                for platform in ALL_PLATFORMS:
                    if platform not in platform_hits:
                        continue
                    if platform in buildable:
                        if platform in BACKEND_PLATFORMS:
                            backend.append(platform)
                        if platform in APP_PLATFORMS:
                            app.append(platform)
                    else:
                        warn(
                            f"{platform} 目录有改动，但该平台在当前分支未启用"
                            f"（缺 app/{platform} runner），已跳过其构建"
                        )
                outputs = build_outputs(
                    backend_platforms=backend,
                    app_platforms=app,
                    mode="platforms" if (backend or app) else "light",
                    reason=f"平台专属路径变更（{reason}）",
                    changed_count=len(files),
                )
            else:
                # Only documentation/packaging changed: lint job is enough.
                outputs = build_outputs(
                    backend_platforms=[],
                    app_platforms=[],
                    mode="light",
                    reason=f"仅文档/打包等轻量路径变更（{reason}），只跑 lint",
                    changed_count=len(files),
                )

    emit_outputs(outputs)

    # Human-readable summary in the GitHub step log.
    print(f"detect: mode={outputs['mode']} reason={outputs['reason']}")
    print(f"detect: platforms={outputs['platforms']}")
    print(f"detect: backend_platforms={outputs['backend_platforms']}")
    print(f"detect: app_platforms={outputs['app_platforms']}")
    if outputs["light_only"] == "true":
        print("detect: no build jobs selected (lint only)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
