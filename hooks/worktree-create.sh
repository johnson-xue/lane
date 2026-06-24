#!/usr/bin/env bash
# WorktreeCreate hook — 轻量通用增强
# 只做：ignore 验证 + 状态记录。不做项目 setup（归 SKILL + worktree.yaml）。
# hook 失败不应阻断 worktree 创建，所以始终 exit 0。
set -uo pipefail

input=$(cat 2>/dev/null || echo "")

# 提取 worktree 路径（字段名宽松尝试；官方 schema 待实装验证）
wt_path=$(printf '%s' "$input" | jq -r '(.worktree_path // .path // .worktree // empty)' 2>/dev/null || echo "")
if [[ -z "$wt_path" ]]; then
  # fallback：取 git worktree list 最新项
  wt_path=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{p=$2} END{print p}')
fi
[[ -z "$wt_path" || ! -d "$wt_path" ]] && exit 0

common_dir=$(git -C "$wt_path" rev-parse --git-common-dir 2>/dev/null || true)
[[ -z "$common_dir" ]] && exit 0
proj_root=$(cd "$common_dir/.." 2>/dev/null && pwd) || exit 0

# 1. ignore 验证：临时 worktree 目录应在 .gitignore
rel=$(printf '%s' "$wt_path" | sed "s|^$proj_root/||")
case "$rel" in
  .claude/worktrees/*|.worktrees/*|worktrees/*)
    git_dir=$(printf '%s' "$rel" | cut -d/ -f1-2)
    [[ "$git_dir" == ".claude" ]] && git_dir=".claude/worktrees"
    if ! git -C "$proj_root" check-ignore -q "$git_dir" 2>/dev/null; then
      printf '%s/\n' "$git_dir" >> "$proj_root/.gitignore"
      printf 'lane: added %s/ to .gitignore (please commit)\n' "$git_dir" >&2
    fi
    ;;
esac

# 2. 状态记录（供 sync/doctor 参考）
printf '%s %s %s\n' "$(date +%s 2>/dev/null)" "$wt_path" \
  "$(git -C "$wt_path" branch --show-current 2>/dev/null || echo '?')" \
  >> "$proj_root/.worktree-state" 2>/dev/null || true

exit 0
