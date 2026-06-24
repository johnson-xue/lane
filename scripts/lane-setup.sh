#!/usr/bin/env bash
# lane-setup.sh — 可选的一步初始化
#
# 生成 worktree.yaml（项目特化配置）+ 确保 .gitignore 忽略临时 worktree 目录。
# 不跑也能用 lane（零配置运行时探测）。此脚本仅便捷生成配置，非必须。
# 没跑此脚本的用户：lane 直接用（运行时探测），使用时若需精确配置可随时跑此脚本。
#
# 用法: lane-setup.sh [--quick]   （--quick 零交互，全用探测值）
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && { echo "ERROR: Not inside a git repository." >&2; exit 1; }
cd "$REPO_ROOT"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lane-core.sh
source "$SCRIPT_DIR/lane-core.sh"   # 复用探测函数（source guard 保证不 dispatch）

QUICK=false
[[ "${1:-}" == "--quick" ]] && QUICK=true

printf ">>> Lane setup — 生成 worktree.yaml（可选项目特化配置）\n"
printf "    不跑也能用 lane（零配置运行时探测）。此脚本仅便捷生成配置。\n\n"

# 探测（复用 lane-core 的 load_config）
load_config
DEF="$DEFAULT_BRANCH"
LL="$LONG_LIVED_BRANCHES"
# 探测配置文件（常见路径）
CONF=""
for c in configs/gameserver/local.toml configs/local.toml .env config.toml; do
  [ -f "$c" ] && { CONF="$c"; break; }
done

if ! $QUICK; then
  read -rp "default_branch [$DEF]: " v; DEF="${v:-$DEF}"
  read -rp "long_lived_branches（空格分隔，支持 release_r4.3.* 等模式）[$LL]: " v; LL="${v:-$LL}"
  [ -n "$CONF" ] && { read -rp "conf_file（建 worktree 后防冲突，可空）[$CONF]: " v; CONF="${v:-$CONF}"; }
fi

# long_lived_branches → YAML 行内 list ["a","b","c"]
ll_yaml=$(printf '%s' "$LL" | tr ' ' '\n' | grep -v '^$' | sed 's/.*/"&"/' | paste -sd, -)

# 生成 worktree.yaml
{
  printf 'version: "1"\n'
  printf 'default_branch: %s\n' "$DEF"
  printf 'long_lived_branches: [%s]\n' "$ll_yaml"
  [ -n "$CONF" ] && printf 'conf_file: %s\n' "$CONF"
  printf 'setup: |\n'
  printf '  # 项目特定 setup（建 worktree 后执行，LANE_WT/LANE_BRANCH/LANE_BASE 可用），按需编辑\n'
  printf '  # 例: sed -i "" "s/sqldb_mysql_dbname:.*/sqldb_mysql_dbname: ${LANE_BRANCH}/" "$LANE_WT/%s"\n' "${CONF:-configs/...}"
} > worktree.yaml

# .gitignore
if ! grep -q '^\.claude/worktrees/' .gitignore 2>/dev/null; then
  printf '.claude/worktrees/\n' >> .gitignore
  printf '✓ .gitignore 追加 .claude/worktrees/\n'
fi

printf '\n✓ worktree.yaml 已生成：\n'
cat worktree.yaml
printf '\n下一步: lane sync / lane doctor / lane clean / lane new <name>\n'
