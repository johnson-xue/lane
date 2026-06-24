#!/usr/bin/env bash
# WorktreeRemove hook — 接管 worktree 移除
# stdin: {"worktree_path": "<path>", ...} → 记分支 → git worktree remove → 删分支 → prune
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

if [[ -n "$path" && -d "$path" ]]; then
    # 移除前记分支（lane 约定 path=.claude/worktrees/<branch>）
    branch=$(git -C "$path" branch --show-current 2>/dev/null || basename "$path")
    git -C "$REPO_ROOT" worktree remove "$path" --force 2>/dev/null || rm -rf "$path"
    # worktree remove 不删分支，需补 git branch -D
    if [[ -n "$branch" && "$branch" != "(detached)" ]]; then
        git -C "$REPO_ROOT" branch -D "$branch" 2>/dev/null || true
    fi
fi
git -C "$REPO_ROOT" worktree prune 2>/dev/null || true

exit 0
