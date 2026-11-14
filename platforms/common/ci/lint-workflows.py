#!/usr/bin/env python3
"""Static checks for chatvv GitHub Actions workflows and shell scripts.

Runs in the lightweight CI ``lint`` job (and can run locally after installing
PyYAML). It does not execute any workflow: it catches the mistakes that are
cheap to catch statically.

Checks:
  * workflow YAML parses and duplicate mapping keys are rejected;
  * every ``uses:`` reference is pinned to a major version tag (with a small
    allowlist for actions that use channel names by design);
  * ``needs.<job>.outputs.<name>`` references point at declared outputs and
    existing jobs, and referenced scripts/paths exist;
  * shell scripts pass ``bash -n``, python CI helpers compile, and scripts
    invoked as ``./...`` are executable;
  * no workflow contains a literal ``if: false`` (disable via a repo variable
    and a comment instead).

Usage: ``python3 platforms/common/ci/lint-workflows.py``
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

# CI helper scripts are often run straight from a checkout; do not litter it.
sys.dont_write_bytecode = True

try:
    import yaml
except ImportError:
    print(
        "::error::PyYAML is required for the lint job "
        "(python3 -m pip install pyyaml)",
        file=sys.stderr,
    )
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_DIR = ROOT / ".github" / "workflows"

# Actions that intentionally use a channel instead of a version tag.
ALLOWED_ACTION_REFS = {
    "dtolnay/rust-toolchain@stable",
}
ACTION_REF_RE = re.compile(r"^[^@\s]+@v\d+(?:\.\d+){0,2}$")
NEEDS_OUTPUT_RE = re.compile(r"needs\.([\w-]+)\.outputs\.([\w-]+)")
SCRIPT_PATH_RE = re.compile(r"(?<![\w/])((?:\./)?(?:scripts|platforms)/[\w./-]+\.(?:sh|ps1|py))")

errors: list[str] = []
warnings: list[str] = []


def error(message: str) -> None:
    errors.append(message)
    print(f"::error::{message}")


def warn(message: str) -> None:
    warnings.append(message)
    print(f"::warning::{message}")


class WorkflowLoader(yaml.BaseLoader):
    """BaseLoader (everything is a string) with duplicate-key rejection.

    BaseLoader is used on purpose: PyYAML's default YAML 1.1 resolver turns the
    top-level ``on:`` key into boolean True and ``if: false`` into a boolean,
    which would confuse the structural checks. The checks only need mapping/list
    structure and string references, so stringifying scalars is fine.
    """


def _construct_unique_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


WorkflowLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_unique_mapping
)


def walk_strings(node):
    """Yield every string value inside a parsed YAML document."""
    if isinstance(node, dict):
        for value in node.values():
            yield from walk_strings(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk_strings(value)
    elif isinstance(node, str):
        yield node


def check_workflow(path: Path) -> None:
    relative = path.relative_to(ROOT)
    try:
        document = yaml.load(path.read_text(encoding="utf-8"), Loader=WorkflowLoader)
    except yaml.YAMLError as exc:
        error(f"{relative}: YAML 解析失败: {exc}")
        return
    except OSError as exc:
        error(f"{relative}: 读取失败: {exc}")
        return

    if not isinstance(document, dict):
        error(f"{relative}: 顶层必须是 mapping")
        return
    for key in ("name", "on", "jobs"):
        if key not in document:
            error(f"{relative}: 缺少顶层 key {key!r}")
    jobs = document.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        error(f"{relative}: jobs 为空")
        return

    job_ids = set(jobs)
    declared_outputs: dict[str, set[str]] = {}
    for job_id, job in jobs.items():
        if not isinstance(job, dict):
            error(f"{relative}: job {job_id!r} 必须是 mapping")
            continue
        outputs = job.get("outputs")
        declared_outputs[job_id] = set(outputs) if isinstance(outputs, dict) else set()
        if "runs-on" not in job and "uses" not in job:
            error(f"{relative}: job {job_id!r} 缺少 runs-on")
        needs = job.get("needs")
        if isinstance(needs, str):
            needs = [needs]
        if isinstance(needs, list):
            for need in needs:
                if need not in job_ids:
                    error(f"{relative}: job {job_id!r} 的 needs 指向不存在的 job {need!r}")

    text = yaml.safe_dump(document, sort_keys=False, allow_unicode=True)

    # needs.<job>.outputs.<name> must resolve.
    for job_id, output_name in NEEDS_OUTPUT_RE.findall(text):
        if job_id not in job_ids:
            error(f"{relative}: 引用了不存在的 job {job_id!r}（needs.{job_id}.outputs.{output_name}）")
            continue
        if output_name not in declared_outputs.get(job_id, set()):
            error(
                f"{relative}: needs.{job_id}.outputs.{output_name} 未在 job {job_id!r} 的 outputs 中声明"
            )

    # Action pinning + literal if:false + referenced files.
    for job_id, job in jobs.items():
        job_if = job.get("if")
        if job_if is False or (isinstance(job_if, str) and job_if.strip() == "false"):
            error(f"{relative}: job {job_id!r} 使用字面量 'if: false'，请用仓库变量/注释代替")
        steps = job.get("steps") or []
        if not isinstance(steps, list):
            continue
        for step in steps:
            if not isinstance(step, dict):
                continue
            uses = step.get("uses")
            if isinstance(uses, str) and not uses.startswith("./"):
                if uses not in ALLOWED_ACTION_REFS and not ACTION_REF_RE.match(uses):
                    error(
                        f"{relative}: job {job_id!r} 的 action {uses!r} 未固定到 major tag "
                        "（例如 @v4）"
                    )
            run = step.get("run")
            if isinstance(run, str):
                for script in SCRIPT_PATH_RE.findall(run):
                    candidate = (ROOT / script.lstrip("./")).resolve()
                    if not candidate.exists():
                        error(f"{relative}: job {job_id!r} 引用了不存在的脚本 {script}")

    for script in SCRIPT_PATH_RE.findall(text):
        relative_script = script.lstrip("./")
        if not (ROOT / relative_script).exists():
            error(f"{relative}: 引用了不存在的脚本 {script}")


def run_check(command: list[str], description: str, relative: Path) -> None:
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        output = (result.stdout + result.stderr).strip().splitlines()
        detail = " / ".join(output[:5]) if output else "未知错误"
        error(f"{relative}: {description} 失败: {detail}")


def check_scripts() -> None:
    for directory in ("scripts", "platforms"):
        for path in sorted((ROOT / directory).rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(ROOT)
            suffix = path.suffix
            if suffix == ".sh":
                run_check(["bash", "-n", str(path)], "bash -n", relative)
                if not os.access(path, os.X_OK):
                    error(f"{relative}: 可执行位缺失（chmod +x）")
            elif suffix == ".py" and "platforms/common/ci" in str(path):
                try:
                    compile(path.read_text(encoding="utf-8"), str(relative), "exec")
                except SyntaxError as exc:
                    error(f"{relative}: python 语法错误: {exc}")


def check_platform_commands() -> None:
    """Every dynamic app matrix command must exist, and its output must be valid.

    The commands are produced by ``lib.build_app_matrix`` at runtime, so the
    workflow-level "referenced script exists" check cannot see them.
    """
    try:
        from lib import APP_PACKAGE_COMMANDS, build_app_matrix, buildable_platforms
    except ImportError as exc:  # pragma: no cover - defensive
        error(f"platforms/common/ci/lib.py 无法导入: {exc}")
        return
    root = find_repo_root()
    platforms = buildable_platforms(root)
    for mode in ("ci", "release"):
        matrix = build_app_matrix(platforms, mode)
        entries = matrix.get("include", [])
        if not entries:
            error(f"app matrix mode={mode} 为空（应至少包含已启用平台）")
        for platform, command in APP_PACKAGE_COMMANDS[mode].items():
            tokens = command.split()
            path = next((token for token in tokens if token.startswith("./")), "")
            if path and not (root / path[2:]).exists():
                error(f"app matrix mode={mode} platform={platform} 引用不存在的脚本 {path}")


def find_repo_root():
    """Repository root (platforms/common/ci/lint-workflows.py is 3 levels deep)."""
    return ROOT


def check_workflows() -> None:
    workflows = sorted(WORKFLOW_DIR.glob("*.yml"))
    if not workflows:
        error(".github/workflows: 没有找到 workflow")
        return
    names: set[str] = set()
    for path in workflows:
        check_workflow(path)
        try:
            document = yaml.load(path.read_text(encoding="utf-8"), Loader=WorkflowLoader)
        except yaml.YAMLError:
            continue
        if isinstance(document, dict):
            name = document.get("name")
            if name:
                if name in names:
                    error(f".github/workflows: workflow name 重复: {name!r}")
                names.add(name)


def main() -> int:
    check_workflows()
    check_scripts()
    check_platform_commands()
    if errors:
        print(f"\nlint: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1
    print(
        f"lint: OK — {len(list(WORKFLOW_DIR.glob('*.yml')))} workflow(s), "
        f"{len(list((ROOT / 'scripts').glob('*.sh'))) + len(list((ROOT / 'platforms').rglob('*.sh')))} shell script(s) checked"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
