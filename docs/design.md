# Lane — 通用 Worktree 管理插件 · 设计文档

## 1. 定位

project-agnostic 的 worktree 管理插件，**零配置安装即用**。提供多 worktree 批量管理（sync/doctor/clean）+ 单 worktree 生命周期 setup + 项目特化覆盖。与 summoner 同宇宙（LoL 灵感：summoner's lanes — parallel, isolated, swappable）。

## 2. 核心原则

| 原则 | 决策 |
|---|---|
| 上手门槛 | **放弃 init**，零配置安装即用 |
| 项目特化 | 运行时探测 + 可选 `worktree.yaml` 覆盖，不预生成 |
| 核心 setup | **Skill 驱动**（已验证模式，hook 做不了项目特定 setup） |
| 批量管理 | 脚本（worktree-mgr 先例，通用化） |
| hook 角色 | **轻量增强**（ignore 验证/prune），不承重 |
| 动态分支 | 模式匹配（`release_r*`），不写死 |
| clean 基准 | 按每个 worktree **归属线**判定，修单一基准 P0 |
| 确定性 | hook + 脚本探测，不靠 prompt |

## 3. 为什么放弃 init

init（summoner-init 模式：装 plugin 跑 init 生成项目配置）上手门槛高——连插件作者都觉得别扭，普通用户更不会跑。且 init 时机在 Claude Code 难确定性实现：
- 无 PostInstall hook（官方 29 个 hook 事件无安装 lifecycle hook）
- SessionStart 仅全新 session 触发，`/reload-plugins` 不触发
- 不存在的 `plugin-reload` hook（查证官方无此事件）

Lane 改为：**零配置 + 运行时探测 + 可选 worktree.yaml 覆盖**。装完即用，项目特化由探测 + 可选配置处理，不靠 init 预生成。

## 4. 为什么 hook 不承重

WorktreeCreate/Remove hook 里能合理做的只有**轻量通用操作**（ignore 验证、状态记录、prune）。核心 setup hook 做不了：

| 处理 | 为什么不适合 hook |
|---|---|
| 配置独立化（local.toml 改字段） | 项目特定，通用 hook 必然猜错 |
| 依赖安装（npm/cargo/go） | 耗时 + 项目特定命令 + 可能失败 |
| 基线测试 | 耗时 + 项目特定 + 失败需判断 |
| 自动 commit .gitignore | 有副作用 |
| 项目特定 setup | hook 不知道，靠可选配置 |

所以核心 setup 归 **Skill 驱动**（agent 按 skill 判断项目情况执行，读可选 `worktree.yaml.setup`），hook 只做轻量增强。

## 5. 架构分层

```
┌─ Skill 驱动（核心 setup，agent 调用）─────────────┐
│  lane SKILL.md: 建 worktree 时 检测→ignore→setup→基线 │
│  读可选 worktree.yaml 做项目特定 setup              │
└─────────────────────────────────────────────────┘
┌─ lane-core.sh（批量管理，运行时探测）─────────────┐
│  lane sync / doctor / clean / new / list          │
│  零配置：探测默认分支/长期分支模式/配置文件         │
│  clean 按归属线判定（修 P0）                       │
└─────────────────────────────────────────────────┘
┌─ hooks（轻量增强，不承重）────────────────────────┐
│  WorktreeCreate: ignore 验证 + 状态记录           │
│  WorktreeRemove: git worktree prune               │
└─────────────────────────────────────────────────┘
┌─ 可选 worktree.yaml（项目覆盖，非强制）───────────┐
│  default_branch / long_lived_branches / conf_file / setup │
└─────────────────────────────────────────────────┘
```

## 6. 文件结构

```
lane/
  plugin.json                # 注册 skill + WorktreeCreate/Remove hooks
  hooks/hooks.json           # hook 配置
  hooks/worktree-create.sh   # WorktreeCreate: ignore 验证 + 状态记录
  hooks/worktree-remove.sh   # WorktreeRemove: prune
  skills/lane/SKILL.md       # 单 worktree lifecycle + 批量管理指引
  scripts/lane-core.sh       # sync/doctor/clean/new/list，运行时探测
  scripts/lane-setup.sh      # 可选：一步生成 worktree.yaml + .gitignore（非必须，不跑也能用）
  references/worktree-spec.md # 可选 worktree.yaml 字段规范
  docs/design.md             # 本文档
  README.md
```

## 7. 核心组件

### 7.1 lane-core.sh（批量管理，零配置）

- `detect_default_branch()`：`origin/HEAD` → main>master>develop
- `expand_branches()`：具体名直接用，glob（`release_r*`）匹配实际分支
- `load_yaml_override()`：可选 worktree.yaml 覆盖（无 YAML 依赖，简单解析）
- `detect_lineage()`：探测 worktree 归属线（独有 commit 最少的长期分支）
- `cmd_clean()`：**按归属线判定**（修 P0），非单一 default_branch
- `cmd_new()`：建 worktree + 执行可选 setup（LANE_WT/LANE_BRANCH/LANE_BASE 环境变量）

### 7.2 SKILL.md（单 worktree setup，Skill 驱动）

借鉴 superpowers `using-git-worktrees`（已验证模式）：
1. 检测现有隔离（防 nested）
2. native 工具优先（EnterWorktree）
3. ignore 验证（hook 自动）
4. 项目 setup（读 worktree.yaml.setup）
5. 基线测试

### 7.3 hooks（轻量，不承重）

- `WorktreeCreate`：ignore 验证（未忽略则追加 .gitignore，不 commit）+ 状态记录
- `WorktreeRemove`：`git worktree prune`

### 7.4 可选 worktree.yaml（非强制）

见 `references/worktree-spec.md`。

## 8. clean 归属线判定（P0 修复）

**worktree-mgr 的问题**：`_default_branch()` 按 main>master>develop 优先匹配，antia 命中 master。但项目主开发分支是 develop、工作线还有 wechat_develop。worktree 基于 develop/wechat，没合并到 master → clean 一个都不删。

**Lane 修复**：对每个 worktree 探测归属线（`detect_lineage`：独有 commit 最少的长期分支），判定是否合并到归属线（本地或 `origin/<lineage>`）。长期分支支持 glob（`release_r*` 动态匹配，release 升级自动适配）。

## 9. 判断 worktree 分支去留（合并前必查）

三层判断（避免重复合 / 合入被撤回改动）：
1. **归属线**：独有 commit 最少的长期分支（lane clean 自动按此）
2. **目标分支 Revert 历史**：`git log --grep "<fix message>" <归属线>`，有 `Revert "fix(...)"` = 主动撤回，别再合
3. **等价 commit**：不同 hash 但同 message/改动的已合版本（`git branch --contains` 按 hash 查不出，按 message 查）

## 10. 与现有的关系

| 现有 | 关系 |
|---|---|
| **summoner** | manifest `worktree` phase 映射 lane；`/summoner:ops` 等可路由 |
| **superpowers:using-git-worktrees** | lane SKILL.md 借鉴其单 worktree lifecycle；lane 额外提供批量管理 + 项目特化 |
| **antia-worktree** | 退化为可选 `worktree.yaml` + antia 布局文档；逻辑归 lane |

## 11. 落地步骤

1. ✅ 建 lane repo 骨架
2. ✅ lane-core.sh（抽取 worktree-mgr + 归属线 P0 + 探测 + 模式 + 可选配置 + new）
3. ✅ plugin.json + hooks.json
4. ✅ hooks（worktree-create/remove 轻量）
5. ✅ SKILL.md
6. ⬜ references/worktree-spec.md
7. ⬜ antia 试用：装 lane + 放 worktree.yaml → 验证 sync/doctor/clean/new
8. ⬜ 验证通过 → antia-worktree 瘦身（保留 antia 布局文档 + worktree.yaml，逻辑归 lane）

## 12. 待验证

- WorktreeCreate hook 的 stdin JSON 字段名（`worktree_path`? 官方 schema 待实装验证，hook 用宽松提取 + fallback）
- hook 是否对所有 worktree 创建方式触发（EnterWorktree / 手动 `git worktree add` / `--worktree`）
- antia 试用：lane clean 按归属线是否正确清理、release_r* 模式展开、worktree.yaml.setup 执行
