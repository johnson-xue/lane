#!/usr/bin/env bash
# WorktreeRemove hook — 接管 worktree 移除
# 读 stdin (path) → git worktree remove → prune。用 python3 解析 JSON（jq 可能未装）
set -uo pipefail

input=$(cat 2>/dev/null || echo "")
printf '%s\n' "$input" > /tmp/lane-hook-remove-stdin.log 2>/dev/null || true

path=$(printf '%s' "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get('path') or d.get('worktree_path') or d.get('worktreePath') or d.get('worktree') or '')
" 2>/dev/null || echo "")

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if [[ -n "$path" && -d "$path" ]]; then
    git -C "$REPO_ROOT" worktree remove "$path" --force 2>/dev/null || rm -rf "$path"
fi
git -C "$REPO_ROOT" worktree prune 2>/dev/null || true

exit 0
