#!/usr/bin/env bash
# lane-core.sh — 通用 worktree 管理（lane 插件核心脚本）
#
# 零配置安装即用：运行时探测项目分支/布局；可选 worktree.yaml 覆盖。
# 命令: lane sync | doctor | clean | new | list | help
#
# 设计要点:
#   - clean 按每个 worktree 的归属线判定合并（修复 worktree-mgr 单一基准误判）
#   - 长期分支支持 glob 模式（release_r4.3.* 动态匹配，应对 release 升级）
#   - 无 worktree.yaml 也能跑（纯探测）；有则覆盖
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && { echo "ERROR: Not inside a git repository." >&2; exit 1; }

# 颜色
CR='\033[0m'; CRed='\033[0;31m'; CGreen='\033[0;32m'
CYellow='\033[1;33m'; CCyan='\033[0;36m'; CBold='\033[1m'; CDim='\033[2m'
die()  { printf "%bERROR: %s%b\n" "$CRed" "$*" "$CR" >&2; exit 1; }
ok()   { printf "%b%s%b\n" "$CCyan" "$*" "$CR"; }
warn() { printf "%b%s%b\n" "$CYellow" "$*" "$CR"; }

# ── worktree 列表解析 ─────────────────────────────────────────────────
_wt() {
    git worktree list --porcelain | awk '
    BEGIN{FS=" ";OFS="|";p="";b="";h=""}
    /^worktree /{p=$2} /^HEAD /{h=$2}
    /^branch /{gsub(/^refs\/heads\//,"",$2);b=$2}
    /^detached/{b="(detached)"}
    /^$/{if(p!="")print p,b,h;p="";b="";h=""}'
}

# ── 配置：运行时探测 + 可选 worktree.yaml 覆盖 ────────────────────────
detect_default_branch() {
    local ref
    ref="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
    [[ -n "$ref" ]] && { basename "$ref"; return; }
    for n in main master develop; do
        git rev-parse --verify "origin/$n" &>/dev/null && { echo "$n"; return; }
        git rev-parse --verify "$n" &>/dev/null && { echo "$n"; return; }
    done
    echo main
}

# 模式展开：具体名直接用，glob 匹配实际存在的分支（release_r4.3.* 等）
expand_branches() {
    local pat b
    for pat in "$@"; do
        case "$pat" in
            *'*'*|*'?'*)
                while read -r b; do
                    [[ -z "$b" ]] && continue
                    case "$b" in $pat) echo "$b" ;; esac
                done < <(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null | sed 's|^origin/||' | sort -u) ;;
            *) echo "$pat" ;;
        esac
    done
}

# 解析行内 YAML list [a, b, "c*"] 或 block list（- a\n- b）→ 空格分隔
parse_yaml_list() {
    local line="$1" f="$2"
    if printf '%s' "$line" | grep -q '\['; then
        # 行内 list
        printf '%s' "$line" | sed 's/.*\[\(.*\)\].*/\1/' | tr ',' '\n' \
            | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//'
    else
        # block list（后续 - item 行）
        awk '/long_lived_branches:/{f=1;next} /^[[:space:]]*[^-]/{if(f)exit} f{gsub(/^[[:space:]-]+/,"");print}' "$f" | tr -d '"'
    fi
}

# 可选 worktree.yaml 解析（简单 key: value，无 YAML 依赖）
load_yaml_override() {
    local f="$REPO_ROOT/worktree.yaml"
    [[ -f "$f" ]] || return 0
    local v line items
    v=$(grep -E '^[[:space:]]*default_branch:' "$f" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//; s/[ "]//g')
    [[ -n "$v" ]] && DEFAULT_BRANCH="$v"
    if grep -qE '^[[:space:]]*long_lived_branches:' "$f"; then
        line=$(grep -E '^[[:space:]]*long_lived_branches:' "$f" | head -1)
        items=$(parse_yaml_list "$line" "$f")
        LONG_LIVED_BRANCHES=$(expand_branches $items | sort -u | tr '\n' ' ')
    fi
    CONF_FILE=$(grep -E '^[[:space:]]*conf_file:' "$f" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//; s/^"//; s/"$//')
}

load_config() {
    DEFAULT_BRANCH=$(detect_default_branch)
    # 默认长期分支：默认分支 + 常见开发分支 + 当前 worktree 涉及的分支
    # 不默认展开 release_r*（会匹配所有历史 release 导致爆炸）；release 等模式由 worktree.yaml 显式指定
    local wt_branches
    wt_branches=$(git worktree list --porcelain 2>/dev/null \
        | awk '/^branch /{gsub(/^refs\/heads\//,"",$2);print $2}' | sort -u)
    LONG_LIVED_BRANCHES=$(expand_branches $DEFAULT_BRANCH develop wechat_develop $wt_branches | sort -u | tr '\n' ' ')
    CONF_FILE=""
    load_yaml_override
}

# 探测 worktree 归属线：独有 commit 最少的长期分支
detect_lineage() {
    local wt_branch="$1" base ahead min_ahead=999999 lineage=""
    [[ "$wt_branch" == "(detached)" ]] && { echo "$DEFAULT_BRANCH"; return; }
    for base in $LONG_LIVED_BRANCHES; do
        ahead=$(git rev-list --count "$base..$wt_branch" 2>/dev/null || echo 999999)
        if [[ "$ahead" -lt "$min_ahead" ]]; then
            min_ahead=$ahead; lineage="$base"
        fi
    done
    [[ -z "$lineage" ]] && lineage="$DEFAULT_BRANCH"
    echo "$lineage"
}

# ── sync ──────────────────────────────────────────────────────────────
cmd_sync() {
    git -C "$REPO_ROOT" fetch --all --prune 2>/dev/null || true
    printf "%b%-50s %-22s %s%b\n" "$CBold" "WORKTREE" "BRANCH" "STATUS" "$CR"
    local path branch sha
    while IFS='|' read -r path branch sha; do
        local remote behind ahead dirty s
        remote="$(git -C "$path" config "branch.$branch.remote" 2>/dev/null || echo origin)"
        behind="$(git -C "$path" rev-list --count "$branch..$remote/$branch" 2>/dev/null || echo "?")"
        ahead="$(git -C "$path" rev-list --count "$remote/$branch..$branch" 2>/dev/null || echo "?")"
        dirty=""
        [[ -n "$(git -C "$path" status --porcelain 2>&1)" ]] && dirty="${CYellow}[dirty]${CR} "
        if [[ "$behind" == "?" ]]; then
            s="${CDim}(no remote)${CR}"
        elif [[ "$behind" -eq 0 && "$ahead" -eq 0 ]]; then
            s="${dirty}${CGreen}synced${CR}"
        else
            local parts=""
            [[ "$behind" -gt 0 ]] && parts="${CRed}down${behind}${CR}"
            [[ "$ahead" -gt 0 ]]  && parts="${parts} ${CCyan}up${ahead}${CR}"
            s="${dirty}${parts# }"
        fi
        printf "%-50s %-22s %b\n" "$path" "$branch" "$s"
    done < <(_wt)
}

# ── clean（按归属线判定，修复 worktree-mgr 单一基准 P0）──────────────
cmd_clean() {
    local force=false
    [[ "${1:-}" == "--force" ]] && force=true
    git -C "$REPO_ROOT" fetch --all --prune 2>/dev/null || true
    load_config
    ok "Default: $DEFAULT_BRANCH | Long-lived: $LONG_LIVED_BRANCHES"

    # 残留分支清理：.worktree-state 记录但 worktree 已移除的分支（ExitWorktree remove 残留，
    # 因 ExitWorktree remove 不触发 WorktreeRemove hook、git worktree remove 不删分支）
    local residue=0
    if [[ -f "$REPO_ROOT/.worktree-state" ]]; then
        local state_new=""
        while IFS=' ' read -r ts wt_path wt_branch; do
            [[ -z "$wt_path" ]] && continue
            if git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree/{print $2}' | grep -qxF "$wt_path"; then
                state_new+="${ts} ${wt_path} ${wt_branch}"$'\n'
            elif [[ -n "$wt_branch" && "$wt_branch" != "(detached)" ]] \
                 && git -C "$REPO_ROOT" rev-parse --verify "$wt_branch" &>/dev/null; then
                printf "  %bOK%b 残留分支: %s (worktree 已移除)\n" "$CGreen" "$CR" "$wt_branch"
                if $force; then git -C "$REPO_ROOT" branch -D "$wt_branch" 2>/dev/null && ok "  Deleted: $wt_branch"; fi
                residue=1
            fi
        done < "$REPO_ROOT/.worktree-state"
        if $force; then printf '%s' "$state_new" > "$REPO_ROOT/.worktree-state"; fi
    fi

    local candidates=() path branch lineage b is_long_lived
    while IFS='|' read -r path branch sha; do
        [[ "$path" == "$REPO_ROOT" || "$branch" == "(detached)" ]] && continue
        is_long_lived=false
        for b in $LONG_LIVED_BRANCHES; do [[ "$b" == "$branch" ]] && is_long_lived=true; done
        $is_long_lived && continue

        lineage=$(detect_lineage "$branch")
        if git merge-base --is-ancestor "$branch" "$lineage" 2>/dev/null \
           || git merge-base --is-ancestor "$branch" "origin/$lineage" 2>/dev/null; then
            local dm=""
            [[ -n "$(git -C "$path" status --porcelain 2>&1)" ]] && dm=" ${CYellow}[uncommitted]${CR}"
            candidates+=("$path|$branch|$lineage")
            printf "  %bOK%b %-50s %-20s ← %s%b\n" "$CGreen" "$CR" "$path" "$branch" "$lineage" "$dm"
        fi
    done < <(_wt)

    if [[ ${#candidates[@]} -eq 0 && $residue -eq 0 ]]; then
        ok "No merged worktrees or residue branches to clean."
        return
    fi
    if ! $force; then
        warn "Dry run — add --force to actually remove."
        return
    fi
    local entry p
    for entry in "${candidates[@]}"; do
        p="${entry%%|*}"; b="${entry#*|}"; b="${b%|*}"
        ok "Removing: $p [$b]"
        git worktree remove "$p" 2>&1 || warn "  Failed to remove $p"
        if ! git worktree list --porcelain | awk '/^branch/{gsub(/^refs\/heads\//,"",$2);print $2}' | grep -qxF "$b"; then
            git -C "$REPO_ROOT" branch -D "$b" 2>/dev/null && ok "  Deleted branch: $b"
        fi
    done
    git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
}

# ── doctor ────────────────────────────────────────────────────────────
cmd_doctor() {
    ok "Running health checks..."
    git -C "$REPO_ROOT" fetch --all --prune 2>/dev/null || true
    local issues=0 path branch sha remote ts days
    while IFS='|' read -r path branch sha; do
        remote="$(git -C "$path" config "branch.$branch.remote" 2>/dev/null || echo origin)"
        if [[ "$branch" != "(detached)" ]]; then
            if ! git -C "$path" rev-parse "$remote/$branch" &>/dev/null; then
                warn "Orphan: $path [$branch] — remote tracking gone"; ((issues++))
            fi
            if ! git -C "$path" config "branch.$branch.remote" &>/dev/null; then
                warn "No remote: $path [$branch]"; ((issues++))
            fi
        else
            warn "Detached HEAD: $path"; ((issues++))
        fi
        if [[ -n "$(git -C "$path" status --porcelain 2>&1)" ]]; then
            ts="$(git -C "$path" log -1 --format=%ct 2>/dev/null || echo 0)"
            days=$(( ($(date +%s) - ts) / 86400 ))
            if (( days > 7 )); then
                warn "Stale: $path [$branch] — dirty, last commit ${days}d ago"; ((issues++))
            fi
        fi
    done < <(_wt)
    if (( issues == 0 )); then ok "All worktrees healthy."; else warn "$issues issue(s) found."; fi
}

# ── new（建 worktree + 可选项目 setup）───────────────────────────────
cmd_new() {
    local name="${1:-}"
    [[ -z "$name" ]] && die "Usage: lane new <branch-name> [base]"
    local base="${2:-}"
    load_config
    [[ -z "$base" ]] && base="$DEFAULT_BRANCH"
    local wt="$REPO_ROOT/.claude/worktrees/$name"
    ok "Creating worktree: $wt (branch $name from $base)"
    git -C "$REPO_ROOT" worktree add -b "$name" "$wt" "$base"
    local f="$REPO_ROOT/worktree.yaml"
    if [[ -f "$f" ]] && grep -qE '^[[:space:]]*setup:' "$f"; then
        ok "Running project setup..."
        local setup_cmd
        setup_cmd=$(awk '
            /^[[:space:]]*setup:/{
                line=$0; sub(/^[[:space:]]*setup:[[:space:]]*\|?[[:space:]]*/,"",line)
                if(length(line)) print line
                in_setup=1; next
            }
            in_setup && /^[[:space:]]+[^[:space:]]/{ gsub(/^[[:space:]]*/,""); print; next }
            in_setup && /^[[:space:]]*$/{ next }
            in_setup{ exit }
        ' "$f")
        LANE_WT="$wt" LANE_BRANCH="$name" LANE_BASE="$base" LANE_REPO_ROOT="$REPO_ROOT" bash -c "$setup_cmd" || warn "setup 返回非 0（忽略）"
    fi
    [[ -n "${CONF_FILE}" ]] && warn "记得为新 worktree 独立配置 ${CONF_FILE}（防端口/DB 冲突）"
    ok "Worktree ready at $wt"
}

# ── list ──────────────────────────────────────────────────────────────
cmd_list() { git -C "$REPO_ROOT" worktree list; }

# ── dispatch ──────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
lane — 通用 worktree 管理（零配置，运行时探测）

命令:
  sync               概览所有 worktree 的 ahead/behind/dirty 状态
  doctor             健康检查：孤儿分支、无远程、detached、脏停留
  clean [--force]    按归属线判定，清理已合并 worktree（默认 dry run）
  new <name> [base]  建 worktree（.claude/worktrees/<name>），可选项目 setup
  list               列出所有 worktree

配置（可选，非强制）:
  项目根放 worktree.yaml 覆盖探测：
    default_branch: develop
    long_lived_branches: [develop, wechat_develop, "release_r4.3.*"]
    conf_file: configs/gameserver/local.toml
    setup: |
      sed -i '' "s/.../" "$LANE_WT/..."

日常 git 操作仍用纯 git（fetch/pull/push/status）。
EOF
    exit 0
}

# 仅直接执行时分发（source 时不分发，供 lane-setup.sh 复用探测函数）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        sync)   cmd_sync ;;
        doctor) cmd_doctor ;;
        clean)  shift; cmd_clean "$@" ;;
        new)    shift; cmd_new "$@" ;;
        list)   cmd_list ;;
        help|-h|--help) usage ;;
        *)      usage ;;
    esac
fi
