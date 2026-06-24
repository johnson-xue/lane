#!/usr/bin/env bash
# WorktreeRemove hook — 接管 worktree 移除
# stdin: {"worktree_path": "<path>", ...} → git worktree remove → prune
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
    git -C "$REPO_ROOT" worktree remove "$path" --force 2>/dev/null || rm -rf "$path"
fi
git -C "$REPO_ROOT" worktree prune 2>/dev/null || true

exit 0
