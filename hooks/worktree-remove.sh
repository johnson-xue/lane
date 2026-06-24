#!/usr/bin/env bash
# WorktreeRemove hook — 接管 worktree 移除
# stdin: {"worktree_path": "<path>", ...} → 移除 worktree（如存在）→ 删分支 → prune
# 删分支独立于 worktree 是否存在（ExitWorktree 可能已移除 worktree 目录）
# 用 python3 解析 JSON（jq 可能未装）
set -uo pipefail

input=$(cat 2>/dev/null || echo "")
path=$(printf '%s' "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get('worktree_path') or d.get('path') or '')
" 2>/dev/null || echo "")

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# branch 从 path basename 推断（lane 约定 path=.claude/worktrees/<branch>）
branch=$(basename "$path")

# 移除 worktree（如还存在 — ExitWorktree 可能已移除）
if [[ -n "$path" && -d "$path" ]]; then
    git -C "$REPO_ROOT" worktree remove "$path" --force 2>/dev/null || rm -rf "$path"
fi

# 删分支（独立于 worktree 存在 — worktree remove 不删分支，且 worktree 可能已被移除）
if [[ -n "$branch" && "$branch" != "(detached)" && "$branch" != "worktrees" && "$branch" != ".claude" ]]; then
    git -C "$REPO_ROOT" branch -D "$branch" 2>/dev/null || true
fi

git -C "$REPO_ROOT" worktree prune 2>/dev/null || true

exit 0
