# Lane

<p align="center"><strong>通用 worktree 管理插件 · 零配置安装即用</strong><br>
<sub>Like summoner's lanes: parallel, isolated, swappable.</sub></p>

多 worktree 项目的批量管理（sync/doctor/clean）+ 单 worktree 生命周期 setup + 可选项目特化覆盖。运行时探测，无需 init。与 [summoner](https://github.com/johnson-xue/summoner) 同宇宙（LoL 灵感）。

## 为什么

多分支并行项目需要：批量同步总览、健康检查、安全清理。纯 git 要组合多条命令；`lane` 一条搞定。且修复了常见 worktree 管理工具的 clean 基准误判——**按归属线清理，不绑单一 master**。

## 安装即用（零配置）

```bash
# Claude Code
/plugin marketplace add <you>/lane
/plugin install lane
```

装完直接用，**无需 init**：

```bash
lane sync          # 所有 worktree 状态总览
lane doctor        # 健康检查
lane clean         # 清理已合并（dry run，--force 执行）
lane new feat/x    # 建 worktree
```

lane 运行时探测：默认分支（`origin/HEAD`）、长期分支（develop / wechat_develop / `release_r*` 等模式动态匹配）。

## 可选配置（项目特化，非强制）

**便捷生成**：`scripts/lane-setup.sh [--quick]` 一步探测项目并生成 `worktree.yaml` + `.gitignore`。也可手写。**不跑也能用 lane**（零配置运行时探测）。

项目根放 `worktree.yaml` 覆盖探测 + 指定项目 setup：

```yaml
default_branch: develop
long_lived_branches: [develop, wechat_develop, "release_r*"]
conf_file: configs/gameserver/local.toml
setup: |
  sed -i '' "s/sqldb_mysql_dbname:.*/sqldb_mysql_dbname: ${LANE_BRANCH}/" "$LANE_WT/configs/gameserver/local.toml"
```

无 `worktree.yaml` 也能用（纯探测）。字段规范见 `references/worktree-spec.md`。

## 命令

| 命令 | 作用 |
|------|------|
| `lane sync` | 所有 worktree ahead/behind/dirty 总览 |
| `lane doctor` | 孤儿/无远程/detached/stale 健康检查 |
| `lane clean [--force]` | 按归属线清理已合并（默认 dry run） |
| `lane new <name> [base]` | 建 worktree + 可选 setup |
| `lane list` | 列出 worktree |

## 设计要点

- **零配置安装即用**（无 init，运行时探测）——init 上手门槛高，连作者都觉得别扭
- **clean 按归属线判定**（修复 worktree-mgr 单一 master 基准的 P0）
- **长期分支 glob 模式**（`release_r*` 动态匹配，应对 release 升级）
- **Skill 驱动**单 worktree setup + **脚本**批量管理 + **hook 轻量增强**（ignore/prune，不承重）
- **项目特化靠可选 worktree.yaml**，不靠 init 预生成

详见 `docs/design.md`。

## 与 summoner / superpowers 的关系

- **summoner**：manifest `worktree` phase 映射 lane；`/summoner:ops` 等可路由到 lane
- **superpowers:using-git-worktrees**：lane SKILL.md 借鉴其已验证的单 worktree lifecycle；lane 额外提供批量管理 + 项目特化

## License

MIT
