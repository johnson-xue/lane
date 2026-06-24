#!/usr/bin/env bash
# WorktreeRemove hook — 轻量清理
# 只做：git worktree prune（清理 stale 注册）。删分支等需判断的操作归 lane clean/doctor。
set -uo pipefail
git worktree prune 2>/dev/null || true
exit 0
