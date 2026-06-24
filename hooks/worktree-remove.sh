#!/usr/bin/env bash
# WorktreeRemove hook — 接管 worktree 移除
# 读 stdin (path) → git worktree remove → prune
set -uo pipefail

input=$(cat 2>/dev/null || echo "")
path=$(printf '%s' "$input" | jq -r '(.path // .worktree_path // .worktreePath // .worktree // empty)' 2>/dev/null || echo "")

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if [[ -n "$path" && -d "$path" ]]; then
    git -C "$REPO_ROOT" worktree remove "$path" --force 2>/dev/null || rm -rf "$path"
fi
git -C "$REPO_ROOT" worktree prune 2>/dev/null || true

exit 0
