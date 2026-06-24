---
name: lane
description: 通用 worktree 管理。建 worktree 时做检测/ignore/setup/基线；批量管理调 lane-core（sync/doctor/clean/new）。零配置运行时探测，可选 worktree.yaml 覆盖。
---

# Lane — Worktree 管理

## 概述

确保 work 在隔离 worktree；管理多 worktree（sync/doctor/clean）。**零配置安装即用**，运行时探测项目分支/布局，可选 `worktree.yaml` 覆盖。

**核心原则**：建 worktree 优先 native 工具（EnterWorktree）；批量管理用 lane-core 脚本；项目特化靠可选 `worktree.yaml`，**不靠 init**。

## 建单个 worktree（lifecycle）

### Step 0: 检测现有隔离
建前先查是否已在 worktree（`GIT_DIR != GIT_COMMON`，排除 submodule）。已隔离就别再建（防 nested）。

### Step 1: 优先 native 工具
有 `EnterWorktree` 就用它，**绝不**手动 `git worktree add`——会产生 harness 看不到的 phantom state。无 native 工具才 `git worktree add` fallback。

### Step 2: ignore 验证
临时 worktree 目录（`.claude/worktrees/`）应在 `.gitignore`。WorktreeCreate hook 自动验证+追加。

### Step 3: 项目 setup（读可选 worktree.yaml）
若项目根有 `worktree.yaml` 且含 `setup` 命令，建 worktree 后执行（环境变量 `LANE_WT` / `LANE_BRANCH` / `LANE_BASE` 可用）。无则跳过。
> 项目特定 setup（如改 local.toml 字段）放这里——hook 做不了的事，Skill + 可选配置做。

### Step 4: 基线测试
建后跑项目测试确认干净起点（`npm test` / `cargo test` / `go test ./...`），区分新 bug vs 预存问题。

## 批量管理（lane-core）

调 `lane` 命令（= `scripts/lane-core.sh`）：

| 命令 | 作用 |
|------|------|
| `lane sync` | 所有 worktree ahead/behind/dirty 总览 |
| `lane doctor` | 健康检查（孤儿/无远程/detached/stale） |
| `lane clean [--force]` | **按归属线**清理已合并（默认 dry run） |
| `lane new <name> [base]` | 建 worktree + 可选 setup |
| `lane list` | 列出 worktree |

零配置：lane-core 运行时探测默认分支（`origin/HEAD` 或 main>master>develop）、长期分支（develop/wechat_develop/`release_r*` 等模式动态匹配）。

## 可选 worktree.yaml（项目特化覆盖，非强制）

**便捷生成**：跑 `scripts/lane-setup.sh`（或 `--quick` 零交互）一步探测项目并生成 `worktree.yaml` + `.gitignore`。也可手写。**不跑也能用 lane**（零配置运行时探测）。

项目根放 `worktree.yaml` 覆盖探测 + 指定 setup：

```yaml
default_branch: develop
long_lived_branches: [develop, wechat_develop, "release_r*"]
conf_file: configs/gameserver/local.toml
setup: |
  sed -i '' "s/sqldb_mysql_dbname:.*/sqldb_mysql_dbname: ${LANE_BRANCH}/" "$LANE_WT/configs/gameserver/local.toml"
```

无 `worktree.yaml` 也能用（纯探测）。字段规范见 `references/worktree-spec.md`。

## 判断 worktree 分支去留（合并前必查）

三层判断（避免重复合 / 合入被撤回的改动）：
1. **归属线**：独有 commit 最少的长期分支（`lane clean` 自动按此）
2. **目标分支 Revert 历史**：`git log --grep "<fix message>" <归属线>`，有 `Revert "fix(...)"` = 主动撤回，别再合
3. **等价 commit**：不同 hash 但同 message/改动的已合版本（`git branch --contains` 按 hash 查不出，按 message 查）

## 关键规则

- 临时 worktree（`.claude/worktrees/`）短生命周期，用完 `lane clean --force` 清理
- 永久 worktree（兄弟目录 `<project>-<用途>`）用于切长期分支
- `lane clean` 按归属线，不按单一 master/develop（修复 worktree-mgr 的 P0）
- 不靠 init 预生成配置；运行时探测 + 可选覆盖
- hook 只做轻量（ignore/prune），核心 setup 归 Skill + worktree.yaml

## 常见自欺借口

| 想法 | 真相 |
|------|------|
| "改动小，直接在主 worktree 改" | 并行任务/用户工作副本会冲突，用 EnterWorktree 隔离 |
| "worktree 不清理也没事" | 累积废弃 worktree 污染 sync/doctor，且未合并代码可能丢 |
| "clean 用 master 基准就行" | 多主线项目（develop/wechat）worktree 没合并到 master，clean 全无效——按归属线 |
| "release 分支写死 release_r4.3.400" | release 会升级，用 `release_r*` 模式动态匹配 |
