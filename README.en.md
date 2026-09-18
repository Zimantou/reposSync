# reposSync

[中文](./README.md) | **English**

> A single symlink-backed entry point for Git repositories scattered across your disk. Repositories stay exactly where they are.
> Created by Deepseek V4.1 Flash.

`reposSync` scans a directory you choose, finds every Git repository in it (any directory
containing `.git` counts), and creates a same-named symlink for each one under `~/repos/`.

```console
$ repos
ml-pipeline  /home/user/work/ml-pipeline
my-app       /home/user/projects/my-app
notes        /home/user/projects/notes

共 3 个仓库（/home/user/repos）
```

> **Note:** the scripts' console output is currently in Chinese. The commands, flags and
> exit codes are all in English and behave as documented here.

## What problem does this solve

Once you have a few projects, repositories end up everywhere: a couple under `~/work/`,
some in `~/Documents/`, and a few `git clone`s buried inside a conda environment's
`envs/<name>/`. Finding one means running `find` or browsing from memory.

`reposSync` gives you a fixed entry point, `~/repos/`, where every entry is a symlink to a
real repository:

- **Nothing moves.** A symlink is just a shortcut; deleting it never touches the repository.
- **Nothing to maintain.** The result comes from scanning the disk, not a hand-written config
  file, so it can't drift out of sync with reality.
- **Safe to re-run.** It's idempotent — running it again only fills in the gaps.

## Features

- Scans for and identifies Git repositories (`.git` may be a directory, a file, or a symlink)
- **Zero changes** to your repositories: symlinks only — no moving, copying, or modifying
- **Idempotent**: re-running never duplicates or breaks existing links
- Name clashes get an automatic `-1`, `-2` suffix plus a warning
- Nested repositories (submodules, etc.) are skipped by default; use `-N` to include them
- Prunes noisy directories such as `node_modules`, `.cache` and `venv`, so a scan takes well under a second
- Unreadable paths are skipped and counted instead of aborting the scan
- Optional: new `git init` / `git clone` repositories get **picked up automatically**
- Writes a repository listing, `REPOS_LIST.md`

## Requirements

- **Linux**, Bash 4.0+
- GNU coreutils (the scripts use `realpath`, `readlink -f`, `sort -z`, `mktemp -t`)
- `find` and `ln` (normally present already)

> macOS is untested. The scripts rely on several GNU-only options; on macOS you will most
> likely need `brew install coreutils` and the `gnubin` directory on your `PATH`.
> Portability patches are welcome.

## Installation

```bash
git clone https://github.com/Zimantou/reposSync.git ~/repos
~/repos/install.sh --scan
```

`install.sh` does two things:

1. **Hook templates** — symlinks `~/.git-templates` to the repo's `git-templates/` and sets
   `git config --global init.templateDir`, so new repositories are picked up automatically
2. **Shell integration** — prints a single `source` line for you to add to your shell config,
   which provides the `repos` command

`--scan` runs the first scan immediately after installing (scans `$HOME`, up to 5 levels deep).

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

It **never overwrites anything that already exists**, and **does not touch your rc files by
default** (it only prints the line to add). To have it write the line for you, pass
`--write-rc` (it backs up the file first):

```bash
~/repos/install.sh --write-rc
```

### Options

| Option | Effect |
|--------|--------|
| `--no-hooks` | Skip the Git hook template setup |
| `--no-shell` | Skip the shell integration |
| `--write-rc` | Append the `source` line to your rc file (default: just print it) |
| `--rc FILE` | Which rc file to write to (implies `--write-rc`) |
| `-s, --scan` | Run the first scan right after installing |
| `-n, --dry-run` | Preview what would happen; change nothing |

### Manual installation

If you'd rather not run the script, it's just a few steps:

```bash
# 1. Hook templates (optional, for automatic pickup of new repositories)
ln -s repos/git-templates "$HOME/.git-templates"
git config --global init.templateDir ~/.git-templates

# 2. Shell integration (provides the repos command)
echo '. "$HOME/repos/repos.sh"' >> ~/.bashrc

# 3. First scan
~/repos/link-repos.sh
```

> Never overwrite an existing `~/.git-templates` — it may hold hook templates you maintain
> yourself. `install.sh` stops and tells you when it finds one, rather than acting.

Not sure which links would be created? Preview first:

```bash
~/repos/link-repos.sh -n
```

## Usage

### `repos` — inspect the entry point

| Command | Effect |
|---------|--------|
| `repos` | Table of every link and its real path |
| `repos -g` | Same, plus each repo's current branch and last commit |
| `repos -p` | Print real paths only (pipe-friendly: `xargs`, `fzf`) |
| `repos -n` | Print link names only |
| `repos cd <name>` | `cd` into that repository (prefix matching supported) |
| `repos git <name> <args>` | Run a git command against that repository |
| `repos open <name>` | Print that repository's real absolute path |
| `repos sync` | Re-scan and sync the symlinks |
| `repos help` | Show help |

```console
$ repos -g
ml-pipeline  /home/user/work/ml-pipeline  [main] 2026-09-18 重构数据加载
my-app       /home/user/projects/my-app   [dev]  2026-09-17 修复登录态丢失
```

```bash
repos cd ml-pipeline                          # prefix matching, no need for the full name
repos git ml-pipeline log --oneline -3
```

If an entry in the entry point is broken (its repository was moved or deleted), the table
marks it with `✗` and shows the dead path.

### `link-repos.sh` — scan and sync

```bash
~/repos/link-repos.sh                  # full scan of $HOME (depth 5) and sync
~/repos/link-repos.sh -n               # preview only, change nothing (dry-run)
~/repos/link-repos.sh -d 3             # limit the scan depth
~/repos/link-repos.sh ~/work           # scan a different root directory
~/repos/link-repos.sh -t /data/repos   # use a different entry-point directory
~/repos/link-repos.sh -N               # also include nested repositories (submodules)
~/repos/link-repos.sh -q               # quiet: statistics only
~/repos/link-repos.sh -v               # more detail
~/repos/link-repos.sh -l               # list the mapping only (no scan)
~/repos/link-repos.sh --list-names     # print link names only
~/repos/link-repos.sh --list-paths     # print real paths only
~/repos/link-repos.sh --no-list        # don't refresh REPOS_LIST.md
~/repos/link-repos.sh -h               # full help
```

Full output of a first run:

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

Exit codes: `0` success, `1` partial failure (errors occurred), `2` bad arguments or
environment.

## Automatic pickup of new repositories (optional)

By default, a new repository appears in the entry point only after you run `link-repos.sh`
once. Install either of the layers below and repositories created by `git init` /
`git clone` are picked up automatically.

### Option 1: Git template hooks

The templates live in the repo's `git-templates/`:

| File | Effect |
|------|--------|
| `hooks/repos-link.sh` | Shared logic: make sure the current repository has a link |
| `hooks/post-commit` | Covers `git init` — creates the link on the first commit |
| `hooks/post-checkout` | Covers `git clone` — creates the link once checkout completes |

Running `install.sh` sets this up. To do it manually (symlink the template directory so it
stays under version control and you never end up with two drifting copies):

```bash
ln -s repos/git-templates "$HOME/.git-templates"    # never overwrite an existing path; handle it yourself first
git config --global init.templateDir ~/.git-templates
```

> Templates are copied into a new repository at `init` / `clone` time, so this **only affects
> repositories created afterwards**. The hooks are completely silent and always return 0 —
> they never interfere with any git operation.

### Option 2: the shell-level `git` wrapper

`repos.sh` also defines a very thin `git` wrapper function: `git init` / `git clone` create
the link as soon as they succeed, without waiting for a commit. Every other subcommand
(`git status`, `git log`, `git -C …`) is passed straight through, exit codes included.

It loads along with `repos.sh`, so it needs no extra configuration.

### Disabling

```bash
export LINK_REPOS_NO_GIT_WRAPPER=1             # disable the shell-level git wrapper (re-source after)
unset -f git                                   # or lift it in the current shell only
git config --global --unset init.templateDir   # stop the hook from creating links
rm ~/.git-templates                            # remove the template symlink (templates stay in the repo)
```

Existing symlinks are unaffected.

## How it works

For each candidate directory:

1. **Identify** — a directory containing `.git` (directory, file, or symlink) is a Git repository.
2. **Resolve** — take the absolute path with `realpath`; use the final path component as the link name.
3. **Deduplicate** — check whether the entry point already has `name`, `name-1`, `name-2`…
   pointing at the same real path; if so, skip it.
4. **Create the link** — `ln -s <absolute path> <entry point>/<name>`.

The scan is a single `find` invocation: it prunes noisy directories and the entry point
itself, bounds the walk with `-maxdepth`, and prints directories only. So a whole scan is one
disk traversal with no recursive script calls.

### Scan rules

- **Identification**: a directory containing `.git` counts as a repository
- **Scope**: `$HOME` by default, up to 5 levels deep
- **Pruning**: `node_modules`, `__pycache__`, `.cache`, `.local`, `.config`, `venv`, `.venv`,
  `site-packages`, `.cargo`, `.npm`, `.gradle`, `.vscode-server`, and similar
- **Conda environments are not pruned**: `miniconda3` / `anaconda3` / `miniforge3` are scanned
  normally, because `envs/<name>/` often holds real `git clone`s
- **Nested repositories are skipped**: repositories inside other repositories (submodules,
  etc.) are excluded by default; use `-N` to change that

## Configuration

Every command-line option has a matching environment variable:

| Variable | Equivalent option | Default |
|----------|-------------------|---------|
| `LINK_REPOS_TARGET` | `-t, --target` | `$HOME/repos` |
| `LINK_REPOS_DEPTH` | `-d, --depth` | `5` |
| `LINK_REPOS_LIST_FILE` | — | `REPOS_LIST.md` |
| `LINK_REPOS_PRUNE_EXTRA` | — | empty (extra prune names, `:`-separated) |
| `LINK_REPOS_NO_GIT_WRAPPER` | — | empty (non-empty disables the `git` wrapper) |
| `NO_COLOR` | — | empty (non-empty disables colored output) |

Example: skip a few extra directories for one run

```bash
LINK_REPOS_PRUNE_EXTRA="dist:build:.next" ~/repos/link-repos.sh
```

## FAQ

**A new repository didn't show up.**
Run `repos sync` to fill it in. A full scan usually takes under a second and is idempotent.
Cases that need it: the repository predates the hook install, it was created with
`git init --bare`, or the hook was explicitly skipped.

**A repository was missed — how do I debug it?**
Check, in order: whether it sits inside a pruned directory (see "Scan rules"), whether it is
deeper than the depth limit, and whether it was skipped as a nested repository. Use
`~/repos/link-repos.sh -n -d 8` to preview a deeper, more complete scan without changing
anything.

**Why does a link name have a `-1` or `-2` suffix?**
The entry point already had an entry with that name pointing elsewhere (two repositories with
the same name in different places). The script appends a suffix and warns. If both really are
clashing, consider giving one of them a clearer name.

**How do I include submodules / repositories nested in other repositories?**
They're skipped by default; use `-N` to include them all.

**Does deleting a link under `~/repos/` affect the repository?**
No. A symlink is just a shortcut — deleting it leaves the repository's files untouched.

**The listing shows broken links (`✗`) — how do I clean them up?**
When a repository is moved or deleted, its symlink becomes dangling. The script won't delete it
for you (deletion is destructive, so it isn't done implicitly) — it only marks it `✗`. To clean
up manually:

```bash
# See which ones are broken
find ~/repos -maxdepth 1 -type l ! -exec test -e {} \; -print

# Once you're happy, delete them (only dangling links are affected; valid ones are left alone)
find ~/repos -maxdepth 1 -type l ! -exec test -e {} \; -print -delete
```

**What about directories I can't read?**
The scan skips unreadable paths and reports them as a "permission denied" count in the
statistics. It never aborts.

## Uninstalling

```bash
git config --global --unset init.templateDir   # if you installed the hooks
rm ~/.git-templates                            # if the template symlink was created
# then delete the source repos.sh line from ~/.bashrc (if you used --write-rc, you can restore its backup)
rm -rf ~/repos                                 # removes symlinks and scripts; your repositories are untouched
```

## Known limitations

- **Linux only.** macOS / Windows are untested (the scripts rely on GNU-specific options).
- **No semantic handling of duplicate names.** It mechanically appends `-1`, `-2`; it does not
  try to work out which repository is which.
- **No incremental scan**: every run walks the tree again. Cost is controlled with `-maxdepth`
  and pruning; if your repositories live very deep, raise `-d` and accept a slower scan.
- **The mere presence of `.git` makes a repository** — no check that it is complete and usable
  (an interrupted clone is picked up too).
- **Dangling links are not cleaned up**: once a repository is moved or deleted, the symlink
  becomes dangling. The script only marks it `✗`, it never deletes it (to avoid implicit
  destructive behavior) — clean up manually, see the FAQ.
- **The entry point itself is not scanned**, to avoid self-reference.

## Files

| File | Maintained by | Purpose |
|------|---------------|---------|
| `install.sh` | ✍️ human | One-shot install: hook templates + shell integration |
| `link-repos.sh` | ✍️ human | Main scan-and-link script |
| `repos.sh` | ✍️ human | Defines the `repos` command and the `git` wrapper |
| `git-templates/` | ✍️ human | Git hook templates |
| `README.md` / `README.en.md` | ✍️ human | Chinese / English docs |
| `REPOS_LIST.md` | 🤖 generated locally | Repository listing, not committed (contains machine-specific absolute paths) |

## License

[MIT](./LICENSE)
