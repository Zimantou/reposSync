# 📁 repos — 统一 Git 仓库入口

> **本文件由人工维护，脚本不会读写它。** 可以随意编辑、补充排错笔记。
> 仓库清单 `REPOS_LIST.md` 由脚本在**使用时本地生成**，不入库（内容是本机绝对路径）。

本目录由 [`link-repos.sh`](./link-repos.sh) 维护：脚本会扫描指定根目录下所有 Git 仓库
（目录中含 `.git` 即视为仓库），并为每个仓库在这里创建一个同名软链接。

> **原仓库不会被移动或复制**，软链接只是“快捷方式”。删除这里的链接不会影响原仓库。

新建的仓库会被**自动收录**（`git init` / `git clone` 后无需手动操作），详见 [自动同步](#自动同步新建仓库无需手动操作)。

日常使用直接跑 `repos` 即可拿清单：

```bash
repos          # 表格：链接名 → 真实路径
repos -g       # 附每个仓库的当前分支与最后一次提交
repos -p       # 只输出真实路径
```

文件分工：

| 文件 | 归属 | 说明 |
|------|------|------|
| `README.md` | ✍️ 人工 | 本文件，说明与排错笔记 |
| `link-repos.sh` | ✍️ 人工 | 扫描与建链接的主脚本 |
| `repos.sh` | ✍️ 人工 | `repos` 命令的定义 |
| `git-templates/` | ✍️ 人工 | git hook 模板（本机 `~/.git-templates` 软链接到此） |
| `REPOS_LIST.md` | 🤖 本地生成 | 仓库清单，不入库（含本机绝对路径） |

## 仓库清单

清单由脚本在**首次运行时本地生成**为 `REPOS_LIST.md`（不入库，含本机绝对路径）。
日常直接跑 `repos` 命令即可，不必去看那个文件：

```bash
repos          # 表格：链接名 → 真实路径
repos -g       # 附每个仓库的当前分支与最后一次提交
repos -p       # 只输出真实路径
```

链接失效（原仓库被移动或删除）时，`repos` 会在表格里把该项标成 `✗` 并显示失效路径。

## 快速使用

```bash
cd ~/repos/<链接名>          # 直接进入对应仓库
```

把下面这行加到 `~/.bashrc`（或 `~/.bash_aliases`）末尾，即可获得 `repos` 命令：

```bash
source ~/repos/repos.sh
```

之后：

| 命令 | 作用 |
|------|------|
| `repos` | 表格列出所有链接及其真实路径 |
| `repos -g` | 同上，另附每个仓库的当前分支与最后一次提交 |
| `repos -p` | 只输出真实路径（可管道给 `xargs` / `fzf`） |
| `repos -n` | 只输出链接名 |
| `repos cd <名字>` | 进入该仓库（支持前缀匹配） |
| `repos git <名字> <参数>` | 对该仓库执行 git 命令，例：`repos git GPUTest status` |
| `repos open <名字>` | 打印该仓库的真实绝对路径 |
| `repos sync` | 重新扫描并同步软链接（需要手动补一次时用） |
| `repos help` | 显示帮助 |

## 自动同步：新建仓库无需手动操作

索引的更新是自动的。装好下面两层之后，**`git init` / `git clone` 出来的新仓库会自动出现在这里**，
不需要再手动执行 `repos sync`。

### ① 全局 Git 模板 hook

模板就放在本仓库的 `git-templates/` 里：

| 文件 | 说明 |
|------|------|
| `git-templates/hooks/repos-link.sh` | 公共逻辑：确保当前仓库在本目录有链接 |
| `git-templates/hooks/post-commit` | 覆盖 `git init` 场景 —— 首次 commit 时建立链接 |
| `git-templates/hooks/post-checkout` | 覆盖 `git clone` 场景 —— 检出完成时建立链接 |

启用方式（只需执行一次）。建议把 `~/.git-templates` 软链接到本仓库的 `git-templates/`，
模板因此受版本控制，不会出现两份副本各自跑偏：

```bash
cd "$HOME" && ln -s repos/git-templates .git-templates
git config --global init.templateDir ~/.git-templates
```

> 模板 hook 只在 `init` / `clone` 那一刻被复制进新仓库，因此**只对之后新建的仓库生效**，
> 已有仓库不受影响。hook 全程静默、永远返回 0，不会干扰任何 git 操作。

### ② shell 层的 `git` 包装（由 `repos.sh` 定义）

`git init` / `git clone` 一成功就立刻建立链接，不必等到 commit。
其余子命令（`git status`、`git log`、`git -C …` …）原样透传，退出码也保持不变。

### 关闭自动同步

```bash
export LINK_REPOS_NO_GIT_WRAPPER=1             # 关闭 shell 层 git 包装（需重新 source）
unset -f git                                   # 或在当前 shell 临时解除
git config --global --unset init.templateDir   # 关闭 hook 自动建链接
rm ~/.git-templates                            # 解除模板软链接（只删链接，仓库里的模板保留）
```

关闭后只是不再自动建链接，已有的软链接不受影响。

## 扫描规则

- **识别规则**：目录中含 `.git`（目录、文件或符号链接均可）即视为 Git 仓库。
- **扫描范围**：默认 `$HOME`，最大深度 5 层。
- **自动跳过**：`node_modules`、`__pycache__`、`.cache`、`.local`、`.config`、`venv`、`.venv`、
  `site-packages`、`.cargo`、`.npm`、`.vscode-server` 等噪声目录。
- **conda 目录不跳过**：`miniconda3` / `anaconda3` / `miniforge3` 内部照常扫描，
  因为 `envs/<环境名>/` 下经常放着真正的 git clone。
  本机 `miniconda3/envs/seed/` 下的 `PXDesign`、`Protenix`、`Protenix_pxd` 就是这样被收录的。

## 常见问题

**新建了仓库，但这里没出现？**
执行 `repos sync` 手动补一次即可 —— 全量扫描约 0.4 秒，幂等，反复运行安全。
（少数情况需要它：仓库建于装上 hook 之前、用了 `git init --bare`、或 hook 被显式跳过。）

**某个仓库没被扫到，怎么排查？**
先看它是否落在剪枝目录里（见上方「扫描规则」），再看深度是否超过 5 层。
用 `~/repos/link-repos.sh -n -d 8` 可以预览更深/更全的扫描结果而不会做任何修改。

**链接名后面为什么带 `-1`、`-2`？**
本目录下已有同名条目却指向别的路径（不同位置的重名仓库），脚本会自动加后缀并打印警告。

**想收录子模块 / 嵌套在别的仓库里的仓库？**
默认会跳过“仓库内部的仓库”，用 `~/repos/link-repos.sh -N` 可全部收录。

**删除这里的链接会影响原仓库吗？**
不会。软链接只是快捷方式，删掉它不会动到原仓库的任何文件。

**权限不足的目录怎么办？**
扫描会自动跳过无读取权限的路径，并在统计里以「权限不足跳过」计数提示，不会中断。

## 注意事项

`REPOS_LIST.md` 是**本地生成文件**，每次全量同步都会被覆盖，不要手改它（它也不入库）。
`README.md`（本文件）不会被脚本触碰，可以放心编辑。

## 重新生成与常用选项

```bash
~/repos/link-repos.sh                  # 全量扫描 $HOME（深度 5）并同步，刷新 REPOS_LIST.md
~/repos/link-repos.sh -n               # 先预览，不做任何修改（dry-run）
~/repos/link-repos.sh -d 3             # 限制扫描深度
~/repos/link-repos.sh -N               # 连嵌套仓库（子模块）也收录
~/repos/link-repos.sh -t /data/repos   # 换一个入口目录
~/repos/link-repos.sh -q               # 安静模式，只输出统计
~/repos/link-repos.sh -l               # 只列出映射表（不扫描）
~/repos/link-repos.sh --list-paths     # 只输出真实路径
~/repos/link-repos.sh --no-list        # 不刷新 REPOS_LIST.md
```

环境变量：`LINK_REPOS_TARGET`（入口目录）、`LINK_REPOS_DEPTH`（扫描深度）、
`LINK_REPOS_LIST_FILE`（清单文件名，默认 `REPOS_LIST.md`；**不能设为 README.md**，脚本会拒绘执行）、
`LINK_REPOS_PRUNE_EXTRA`（追加要跳过的目录名，用 `:` 分隔）、`NO_COLOR`（关闭彩色输出）。

`repos` 命令的等价用法：`cd ~/repos && ./link-repos.sh -l`、
`./link-repos.sh --list-paths`（无需 source 即可用）。
