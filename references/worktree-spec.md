# worktree.yaml 字段规范（可选）

`worktree.yaml` 放项目根，覆盖 lane 的运行时探测。**非强制**——没有也能用（纯探测）。

## 字段

| 字段 | 类型 | 必需 | 作用 |
|------|------|:----:|------|
| `version` | string | 否 | 规范版本，目前 `"1"` |
| `default_branch` | string | 否 | 覆盖探测的默认分支（默认探测 `origin/HEAD` 或 main>master>develop） |
| `long_lived_branches` | list | 否 | 长期分支列表，支持 glob（`release_r*`）；clean 归属线判定 + sync 总览用 |
| `conf_file` | string | 否 | 项目配置文件路径（建 worktree 后提示独立配置防端口/DB 冲突） |
| `setup` | string (multiline) | 否 | 建 worktree 后执行的项目特定 setup 命令 |

## setup 环境变量

`setup` 命令执行时可用的环境变量：

| 变量 | 含义 |
|------|------|
| `LANE_WT` | 新 worktree 的绝对路径 |
| `LANE_BRANCH` | 新 worktree 的分支名 |
| `LANE_BASE` | 基分支（从哪个分支建） |

## 示例

```yaml
version: "1"
default_branch: develop
long_lived_branches: [develop, wechat_develop, "release_r*"]
conf_file: configs/gameserver/local.toml
setup: |
  sed -i '' "s/sqldb_mysql_dbname:.*/sqldb_mysql_dbname: ${LANE_BRANCH}/" "$LANE_WT/configs/gameserver/local.toml"
  sed -i '' "s/^project:.*/project: ${LANE_BRANCH}/" "$LANE_WT/configs/gameserver/local.toml"
```

## 解析说明

lane-core.sh 用简单 grep/awk 解析（无 YAML 依赖），支持：
- `key: value`（标量）
- `long_lived_branches: [a, b, "pattern*"]`（行内 list）
- `setup: |` 后续缩进多行（block scalar）

不支持嵌套结构、anchor、复杂 YAML。保持简单。
