#!/usr/bin/env bash
# WorktreeCreate hook — 接管 worktree 创建（Claude Code 要求 hook 创建 + 返回 path）
# 读 stdin (branch/base/path) → git worktree add → ignore 验证 + 项目 setup + 状态记录 → echo path
# 用 python3 解析 JSON（jq 可能未装）
set -uo pipefail

input=$(cat 2>/dev/null || echo "")
# 调试：写 stdin（确认字段名，验证后删）
printf '%s\n' "$input" > /tmp/lane-hook-create-stdin.log 2>/dev/null || true

# python3 提取 branch/base/path（字段名宽松）
read -r branch base path < <(printf '%s' "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get('branch') or d.get('newBranch') or d.get('branchName') or '',
      d.get('base') or d.get('baseRef') or d.get('baseBranch') or '',
      d.get('path') or d.get('worktree_path') or d.get('worktreePath') or d.get('worktree') or '')
" 2>/dev/null || echo "  ")

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
[[ -z "$path" ]] && path="$REPO_ROOT/.claude/worktrees/${branch:-lane-wt-$$}"
[[ -z "$branch" ]] && branch=$(basename "$path")

# 创建 worktree（接管 git worktree add）
if [[ -n "$base" ]]; then
    git -C "$REPO_ROOT" worktree add -b "$branch" "$path" "$base" >&2 2>&1 \
        || git -C "$REPO_ROOT" worktree add "$path" "$base" >&2 2>&1
else
    git -C "$REPO_ROOT" worktree add -b "$branch" "$path" HEAD >&2 2>&1 \
        || git -C "$REPO_ROOT" worktree add "$path" HEAD >&2 2>&1
fi

# ignore 验证
rel=$(printf '%s' "$path" | sed "s|^$REPO_ROOT/||")
case "$rel" in
    .claude/worktrees/*|.worktrees/*|worktrees/*)
        git_dir=$(printf '%s' "$rel" | cut -d/ -f1-2)
        [[ "$git_dir" == ".claude" ]] && git_dir=".claude/worktrees"
        git -C "$REPO_ROOT" check-ignore -q "$git_dir" 2>/dev/null \
            || printf '%s/\n' "$git_dir" >> "$REPO_ROOT/.gitignore" ;;
esac

# 项目 setup（读 worktree.yaml）
f="$REPO_ROOT/worktree.yaml"
if [[ -f "$f" ]] && grep -qE '^[[:space:]]*setup:' "$f"; then
    setup_cmd=$(awk '
        /^[[:space:]]*setup:/{line=$0; sub(/^[[:space:]]*setup:[[:space:]]*\|?[[:space:]]*/,"",line); if(length(line)) print line; in_setup=1; next}
        in_setup && /^[[:space:]]+[^[:space:]]/{gsub(/^[[:space:]]*/,""); print; next}
        in_setup && /^[[:space:]]*$/{next}
        in_setup{exit}
    ' "$f")
    LANE_WT="$path" LANE_BRANCH="$branch" LANE_BASE="$base" LANE_REPO_ROOT="$REPO_ROOT" \
        bash -c "$setup_cmd" >&2 2>&1 || true
fi

# 状态记录
printf '%s %s %s\n' "$(date +%s 2>/dev/null)" "$path" "$branch" \
    >> "$REPO_ROOT/.worktree-state" 2>/dev/null || true

# 必须 echo path
echo "$path"
exit 0
