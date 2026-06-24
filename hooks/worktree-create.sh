#!/usr/bin/env bash
# WorktreeCreate hook — 接管 worktree 创建（Claude Code 要求 hook 创建 + 返回 path）
# 读 stdin (branch/base/path) → git worktree add → ignore 验证 + 项目 setup + 状态记录 → echo path
set -uo pipefail

input=$(cat 2>/dev/null || echo "")

# 提取 branch/base/path（字段名宽松，官方 schema 待确认）
branch=$(printf '%s' "$input" | jq -r '(.branch // .newBranch // .branchName // empty)' 2>/dev/null || echo "")
base=$(printf '%s' "$input" | jq -r '(.base // .baseRef // .baseBranch // empty)' 2>/dev/null || echo "")
path=$(printf '%s' "$input" | jq -r '(.path // .worktree_path // .worktreePath // .worktree // empty)' 2>/dev/null || echo "")

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# fallback
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

# ignore 验证：临时 worktree 目录应在 .gitignore
rel=$(printf '%s' "$path" | sed "s|^$REPO_ROOT/||")
case "$rel" in
    .claude/worktrees/*|.worktrees/*|worktrees/*)
        git_dir=$(printf '%s' "$rel" | cut -d/ -f1-2)
        [[ "$git_dir" == ".claude" ]] && git_dir=".claude/worktrees"
        git -C "$REPO_ROOT" check-ignore -q "$git_dir" 2>/dev/null \
            || printf '%s/\n' "$git_dir" >> "$REPO_ROOT/.gitignore" ;;
esac

# 项目 setup（读 worktree.yaml 的 setup 命令）
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

# 状态记录（供 lane sync/doctor 参考）
printf '%s %s %s\n' "$(date +%s 2>/dev/null)" "$path" "$branch" \
    >> "$REPO_ROOT/.worktree-state" 2>/dev/null || true

# 必须 echo path 到 stdout（Claude Code 要求）
echo "$path"
exit 0
