# reposSync

**中文** | [English](./README.en.md)

> 为散落在磁盘各处的 Git 仓库建立一个软链接统一入口。原仓库原地不动。
> 由Deepseek V4.1 Flash创建。

`reposSync` 扫描你指定的目录，找出其中所有 Git 仓库（目录里含 `.git` 即为仓库），
然后在 `~/repos/` 下为每个仓库创建一个同名软链接。

```console
$ repos
ml-pipeline  /home/user/work/ml-pipeline
my-app       /home/user/projects/my-app
notes        /home/user/projects/notes

共 3 个仓库（/home/user/repos）
```

## 解决什么问题

项目一多，仓库就散得到处都是：`~/work/` 下面几个、`~/Documents/` 里几个、
某个 conda 环境的 `envs/<环境名>/` 里还藏着几个 `git clone`。想找某个仓库得靠 `find`，
或者凭记忆翻目录。

`reposSync` 给你一个固定入口 `~/repos/`，里面的每个条目都是指向真实仓库的软链接：

- **原仓库不搬家**。软链接只是快捷方式，删掉它不会影响原仓库的任何文件。
- **不用维护清单**。结果来自扫描磁盘，不是手写的配置文件，不会和实际状态脱节。
- **可重复运行**。幂等，反复跑只补齐差量。

## 特性

- 自动扫描并识别 Git 仓库（`.git` 是目录、文件或符号链接都能识别）
- 原仓库**零改动**：只创建软链接，不移动、不复制、不修改
- **幂等**：重复运行不会重复建链接，也不会破坏已有链接
- 重名仓库自动加 `-1`、`-2` 后缀并给出警告
- 默认跳过嵌套仓库（子模块等），需要时用 `-N` 全部收录
- 自动剪枝 `node_modules`、`.cache`、`venv` 等噪声目录，扫描亚秒级完成
- 无读取权限的路径自动跳过并计数，不中断扫描
- 可选：让 `git init` / `git clone` 出的新仓库**自动收录**，无需手动同步
- 输出仓库清单 `REPOS_LIST.md`。

## 环境要求

- **Linux**，Bash 4.0+
- GNU coreutils（脚本用到了 `realpath`、`readlink -f`、`sort -z`、`mktemp -t`）
- `find`、`ln`（通常随系统自带）

> macOS 未测试。脚本依赖若干 GNU 特有选项，在 macOS 上大概需要
> `brew install coreutils` 并把 `gnubin` 加进 `PATH`，欢迎提交适配。

## 安装

```bash
git clone https://github.com/Zimantou/reposSync.git ~/repos
~/repos/install.sh --scan
```

`install.sh` 做两件事：

1. **hook 模板** —— 把 `~/.git-templates` 软链接到仓库里的 `git-templates/`，
   并设置 `git config --global init.templateDir`，让新仓库自动收录
2. **shell 接入** —— 打印一行 `source` 命令，加到 shell 配置里即可获得 `repos` 命令

`--scan` 表示安装完立即执行首次扫描（扫描 `$HOME`，最大深度 5 层）。

```console
$ ~/repos/install.sh --scan
reposSync 安装
  仓库目录: /home/user/repos

步骤 1/2 · git hook 模板
✓ 已建立模板软链接: /home/user/.git-templates -> /home/user/repos/git-templates
✓ 已设置 init.templateDir = /home/user/.git-templates
· hook 可执行位正常
✓ 验证通过：新仓库会带上模板 hook

步骤 2/2 · shell 接入

shell 接入（需要你手动执行）
  把下面这行追加到 /home/user/.bashrc（或 ~/.bash_aliases）末尾：

    . "/home/user/repos/repos.sh"

  或者重跑本脚本并加上 --write-rc，由它代你写入（会先备份）

下一步
  执行首次扫描...
扫描 Git 仓库
  根目录  : /home/user
  最大深度: 5
  链接目录: /home/user/repos

✓  my-app  → /home/user/projects/my-app
✓  ml-pipeline  → /home/user/work/ml-pipeline

────────────── 统计 ──────────────
发现 Git 仓库  : 2
新建软链接     : 2
...
安装完成
```

它**不覆盖任何已存在的东西**，也**默认不改你的 rc 文件**（只打印该加的那一行）。
想让它代你写入，加 `--write-rc`（会先备份原文件）：

```bash
~/repos/install.sh --write-rc
```

### 选项

| 选项 | 作用 |
|------|------|
| `--no-hooks` | 跳过 git hook 模板安装 |
| `--no-shell` | 跳过 shell 接入 |
| `--write-rc` | 自动把 `source` 行写入 rc 文件（默认只打印） |
| `--rc FILE` | 指定写入哪个 rc 文件（隐含 `--write-rc`） |
| `-s, --scan` | 安装完成后立即执行首次扫描 |
| `-n, --dry-run` | 只预览将要做的操作，不做任何修改 |

### 手动安装

不想跑脚本的话，就这几步：

```bash
# 1. hook 模板（可选，用于自动收录新仓库）
ln -s repos/git-templates "$HOME/.git-templates"
git config --global init.templateDir ~/.git-templates

# 2. shell 接入（获得 repos 命令）
echo '. "$HOME/repos/repos.sh"' >> ~/.bashrc

# 3. 首次扫描
~/repos/link-repos.sh
```

> `~/.git-templates` 已存在时切勿直接覆盖 —— 那里可能有你自己维护的 hook 模板。
> `install.sh` 遇到这种情况会停下来提示，不会动手。

不确定会建哪些链接？先预览：

```bash
~/repos/link-repos.sh -n
```

## 使用

### `repos` —— 查看入口目录

| 命令 | 作用 |
|------|------|
| `repos` | 表格列出所有链接及其真实路径 |
| `repos -g` | 同上，另附每个仓库的当前分支与最后一次提交 |
| `repos -p` | 只输出真实路径（可管道给 `xargs` / `fzf`） |
| `repos -n` | 只输出链接名 |
| `repos cd <名字>` | 进入该仓库（支持前缀匹配） |
| `repos git <名字> <参数>` | 对该仓库执行 git 命令 |
| `repos open <名字>` | 打印该仓库的真实绝对路径 |
| `repos sync` | 重新扫描并同步软链接 |
| `repos help` | 显示帮助 |

```console
$ repos -g
ml-pipeline  /home/user/work/ml-pipeline  [main] 2026-09-18 重构数据加载
my-app       /home/user/projects/my-app   [dev]  2026-09-17 修复登录态丢失
```

```bash
repos cd ml-pipeline                          # 前缀匹配，不必打全名
repos git ml-pipeline log --oneline -3
```

入口目录里若有条目已损坏（原仓库被移动或删除），表格会用 `✗` 标出并显示失效路径。

### `link-repos.sh` —— 扫描与同步

```bash
~/repos/link-repos.sh                  # 全量扫描 $HOME（深度 5）并同步
~/repos/link-repos.sh -n               # 先预览，不做任何修改（dry-run）
~/repos/link-repos.sh -d 3             # 限制扫描深度
~/repos/link-repos.sh ~/work           # 换一个扫描根目录
~/repos/link-repos.sh -t /data/repos   # 换一个入口目录
~/repos/link-repos.sh -N               # 连嵌套仓库（子模块）也收录
~/repos/link-repos.sh -q               # 安静模式，只输出统计
~/repos/link-repos.sh -v               # 输出更多细节
~/repos/link-repos.sh -l               # 只列出映射表（不扫描）
~/repos/link-repos.sh --list-names     # 只输出链接名
~/repos/link-repos.sh --list-paths     # 只输出真实路径
~/repos/link-repos.sh --no-list        # 不刷新 REPOS_LIST.md
~/repos/link-repos.sh -h               # 完整帮助
```

第一次运行的完整输出：

```console
$ ~/repos/link-repos.sh
扫描 Git 仓库
  根目录  : /home/user
  最大深度: 5
  链接目录: /home/user/repos

✓  notes  → /home/user/projects/notes
✓  my-app  → /home/user/projects/my-app
✓  ml-pipeline  → /home/user/work/ml-pipeline

────────────── 统计 ──────────────
发现 Git 仓库  : 3
新建软链接     : 3
已存在跳过     : 0
名称冲突改名   : 0
嵌套仓库跳过   : 0
错误           : 0
──────────────────────────────────
```

退出码：`0` 成功、`1` 部分失败（有错误）、`2` 参数或环境错误。

## 自动收录新仓库（可选）

默认情况下，新建的仓库要等你手动跑一次 `link-repos.sh` 才会出现在入口目录。
装上下面任意一层之后，`git init` / `git clone` 出的新仓库就会自动收录。

### 方案一：Git 模板 hook

模板在仓库的 `git-templates/` 里：

| 文件 | 作用 |
|------|------|
| `hooks/repos-link.sh` | 公共逻辑：确保当前仓库在入口目录里有链接 |
| `hooks/post-commit` | 覆盖 `git init` 场景 —— 首次 commit 时建立链接 |
| `hooks/post-checkout` | 覆盖 `git clone` 场景 —— 检出完成时建立链接 |

跑 `install.sh` 就会装好这一步。手动装的话（把模板目录软链接过去，
这样它仍受版本控制，不会出现两份副本各自跑偏）：

```bash
ln -s repos/git-templates "$HOME/.git-templates"    # 该路径已存在时切勿覆盖，先自行处理
git config --global init.templateDir ~/.git-templates
```

> 模板只在 `init` / `clone` 那一刻被复制进新仓库，因此**只对之后新建的仓库生效**。
> hook 全程静默、永远返回 0，不会干扰任何 git 操作。

### 方案二：shell 层的 `git` 包装

`repos.sh` 还定义了一个很薄的 `git` 包装函数 —— `git init` / `git clone` 一成功就立刻建链接，
不必等到 commit。其余子命令（`git status`、`git log`、`git -C …`）原样透传，退出码也不变。

它随 `repos.sh` 一起加载，不需要额外配置。

### 关闭

```bash
export LINK_REPOS_NO_GIT_WRAPPER=1             # 关闭 shell 层 git 包装（需重新 source）
unset -f git                                   # 或在当前 shell 临时解除
git config --global --unset init.templateDir   # 关闭 hook 自动建链接
rm ~/.git-templates                            # 解除模板软链接（仓库里的模板仍在）
```

已建好的软链接不受影响。

## 工作原理

对每个候选目录：

1. **识别** —— 目录里存在 `.git`（目录、文件、符号链接都算）即视为 Git 仓库。
2. **解析** —— 用 `realpath` 取得绝对路径，取末段作为链接名。
3. **去重** —— 检查入口目录里是否已有 `名字`、`名字-1`、`名字-2`…… 指向同一真实路径，有则跳过。
4. **建链接** —— `ln -s <绝对路径> <入口目录>/<名字>`。

扫描由单条 `find` 完成：剪枝噪声目录与入口目录自身，用 `-maxdepth` 限制深度，只输出目录。
所以整次扫描就是一次磁盘遍历，没有递归的脚本调用。

### 扫描规则

- **识别**：目录含 `.git` 即视为仓库
- **范围**：默认 `$HOME`，最大深度 5 层
- **剪枝**：`node_modules`、`__pycache__`、`.cache`、`.local`、`.config`、`venv`、`.venv`、
  `site-packages`、`.cargo`、`.npm`、`.gradle`、`.vscode-server` 等
- **conda 环境不剪枝**：`miniconda3` / `anaconda3` / `miniforge3` 照常扫描，
  因为 `envs/<环境名>/` 下经常放着真正的 `git clone`
- **跳过嵌套仓库**：仓库内部的仓库（子模块等）默认不收录，用 `-N` 改变

## 配置

命令行选项都有对应的环境变量：

| 变量 | 等价选项 | 默认值 |
|------|----------|--------|
| `LINK_REPOS_TARGET` | `-t, --target` | `$HOME/repos` |
| `LINK_REPOS_DEPTH` | `-d, --depth` | `5` |
| `LINK_REPOS_LIST_FILE` | — | `REPOS_LIST.md` |
| `LINK_REPOS_PRUNE_EXTRA` | — | 空（追加剪枝目录名，用 `:` 分隔） |
| `LINK_REPOS_NO_GIT_WRAPPER` | — | 空（非空则不定义 `git` 包装） |
| `NO_COLOR` | — | 空（非空则关闭彩色输出） |

例：临时多跳过几个目录

```bash
LINK_REPOS_PRUNE_EXTRA="dist:build:.next" ~/repos/link-repos.sh
```

## 常见问题

**新建的仓库没有出现？**
跑一次 `repos sync` 手动补齐即可。全量扫描通常不到 1 秒，且幂等。
需要它的场景：仓库建于装 hook 之前、用了 `git init --bare`、或 hook 被显式跳过。

**某个仓库没被扫到，怎么排查？**
依次检查：是否落在剪枝目录里（见「扫描规则」）、深度是否超过上限、是否被当成嵌套仓库跳过了。
用 `~/repos/link-repos.sh -n -d 8` 可以预览更深、更全的扫描结果，不会做任何修改。

**链接名后面为什么带 `-1`、`-2`？**
入口目录里已有同名条目却指向别的路径（不同位置的重名仓库），脚本自动加后缀并警告。
如果两个仓库确实重名，建议给其中一个改个更明确的名字。

**想收录子模块 / 嵌在其他仓库里的仓库？**
默认跳过，用 `-N` 全部收录。

**删掉 `~/repos/` 里的链接会影响原仓库吗？**
不会。软链接只是快捷方式，删掉它不会动到原仓库的任何文件。

**列表里有失效链接（`✗`），怎么清理？**
原仓库被移动或删除后，入口目录里的软链接会变成悬空链接。脚本不会自动删它
（删除是破坏性操作，不做隐式处理），只在列表里标 `✗`。手动清理：

```bash
# 先看看有哪些
find ~/repos -maxdepth 1 -type l ! -exec test -e {} \; -print

# 确认无误后删除（只会波及失效链接，有效的不会被动）
find ~/repos -maxdepth 1 -type l ! -exec test -e {} \; -print -delete
```

**权限不足的目录怎么办？**
扫描自动跳过无读取权限的路径，并在统计里以「权限不足跳过」计数提示，不会中断。

## 卸载

```bash
git config --global --unset init.templateDir   # 若装过 hook
rm ~/.git-templates                            # 若建过模板软链接
# 再从 ~/.bashrc 里删掉 source repos.sh 那一行（若用过 --write-rc，可回滚它的备份）
rm -rf ~/repos                                 # 只删软链接与脚本，原仓库不受影响
```

## 已知限制

- **仅支持 Linux**。macOS / Windows 未测试（脚本依赖 GNU coreutils 特有选项）。
- **不处理重名仓库的语义**。只是机械地加 `-1`、`-2` 后缀，不去理解哪个是哪个。
- **不做增量扫描**：每次都重新遍历。靠 `-maxdepth` 与剪枝控制开销；
  仓库分布很深的场景建议调大 `-d`，并接受更长的扫描时间。
- **`.git` 存在即认定是仓库**，不校验其是否完整可用（例如中断的 clone 也会被收录）。
- **不清理失效链接**：原仓库被移走或删除后，软链接会变成悬空链接。脚本只把它标成 `✗`，
  不会自动删除（避免隐式破坏性操作）——需手动清理，见「常见问题」。
- **不扫描入口目录自身**，避免自我引用。

## 文件说明

| 文件 | 归属 | 说明 |
|------|------|------|
| `install.sh` | ✍️ 人工 | 一键安装：hook 模板 + shell 接入 |
| `link-repos.sh` | ✍️ 人工 | 扫描与建链接的主脚本 |
| `repos.sh` | ✍️ 人工 | `repos` 命令与 `git` 包装的定义 |
| `git-templates/` | ✍️ 人工 | git hook 模板 |
| `README.md` / `README.en.md` | ✍️ 人工 | 中文 / 英文文档 |
| `REPOS_LIST.md` | 🤖 本地生成 | 仓库清单，不入库（含本机绝对路径） |

## 许可

[MIT](./LICENSE)
