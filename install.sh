#!/usr/bin/env bash
#
# install.sh —— reposSync 一键安装
#
# 做两件事，每件事都可以单独跳过：
#
#   1. git hook 模板：把模板目录软链接到 ~/.git-templates，
#      并设置 git config --global init.templateDir
#      （装好后，git init / git clone 出的新仓库会自动出现在入口目录）
#
#   2. shell 接入：让交互式 shell 加载 repos.sh
#      （从而获得 repos 命令，以及 git init / git clone 自动建链接的包装）
#
# 特点：
#   - 幂等：重复运行安全，不会重复配置
#   - 保守：任何已存在的东西都不覆盖，只打印该怎么做
#   - 默认不改你的 rc 文件，只把该加的那一行打印出来；想自动写入用 --write-rc
#
# 用法: ./install.sh [选项]
#
set -uo pipefail

PROG="${0##*/}"
SELF="$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
REPO_DIR="$(dirname -- "$SELF")"

DO_HOOKS=1
DO_SHELL=1
WRITE_RC=0
RUN_SCAN=0
DRY_RUN=0
RC_FILE=""

# ------------------------------------------------------------------ 输出
c_reset=''; c_red=''; c_grn=''; c_yel=''; c_cyn=''; c_bld=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  c_reset=$'\033[0m'; c_red=$'\033[31m'; c_grn=$'\033[32m'
  c_yel=$'\033[33m'; c_cyn=$'\033[36m'; c_bld=$'\033[1m'
fi

hdr()  { printf '\n%s\n' "${c_bld}$*${c_reset}"; }
ok()   { printf '%s %s\n' "${c_grn}✓${c_reset}" "$*"; }
info() { printf '  %s\n' "$*"; }
skip() { printf '%s %s\n' "${c_cyn}·${c_reset}" "$*"; }
warn() { printf '%s %s\n' "${c_yel}⚠${c_reset}" "$*" >&2; }
err()  { printf '%s %s\n' "${c_red}✗${c_reset}" "$*" >&2; }
dry()  { printf '  %s\n' "${c_yel}[dry-run]${c_reset} $*"; }

usage() {
  cat <<EOF
${c_bld}${PROG}${c_reset} —— reposSync 一键安装

${c_bld}用法${c_reset}
  ${PROG} [选项]

${c_bld}选项${c_reset}
      --no-hooks       跳过 git hook 模板安装
      --no-shell       跳过 shell 接入
      --write-rc       自动把 source 那行写入 rc 文件（默认只打印，不改你的文件）
      --rc FILE        指定要写入的 rc 文件（隐含 --write-rc）
  -s, --scan           安装完成后立即执行首次扫描
  -n, --dry-run        只预览将要做的操作，不做任何修改
  -h, --help           显示本帮助

${c_bld}它具体做了什么${c_reset}
  1. ln -s ${REPO_DIR}/git-templates  ~/.git-templates
     git config --global init.templateDir ~/.git-templates
     给模板里的 hook 补上可执行位
  2. 在 rc 文件里加一行： . ${REPO_DIR}/repos.sh

${c_bld}注意事项${c_reset}
  * ~/.git-templates 若已存在（文件、目录或指向别处的链接），一律不会覆盖，
    只打印提示 —— 因为那里可能已经有你自己维护的 hook 模板。
  * 卸载方法见 README 的「卸载」一节。

${c_bld}退出码${c_reset}
  0 成功   1 部分失败   2 参数错误
EOF
}

# ------------------------------------------------------------------ 参数
parse_args() {
  while (( $# )); do
    case "$1" in
      --no-hooks)  DO_HOOKS=0; shift ;;
      --no-shell)  DO_SHELL=0; shift ;;
      --write-rc)  WRITE_RC=1; shift ;;
      --rc)
        [[ $# -ge 2 ]] || { err "选项 --rc 需要一个参数"; exit 2; }
        RC_FILE="$2"; WRITE_RC=1; shift 2 ;;
      --rc=*)      RC_FILE="${1#*=}"; WRITE_RC=1; shift ;;
      -s|--scan)   RUN_SCAN=1; shift ;;
      -n|--dry-run) DRY_RUN=1; shift ;;
      -h|--help)   usage; exit 0 ;;
      *) err "未知选项: $1（用 -h 查看帮助）"; exit 2 ;;
    esac
  done
}

# ------------------------------------------------------------------ 步骤 1：hook 模板
TEMPLATE_SRC=""
TEMPLATE_TARGET=""
tpl_failed=0
SHELL_PRESENT=0     # shell 接入是否已就绪（已存在或本次写入成功）

setup_hooks() {
  local src_real target_real

  TEMPLATE_SRC="$REPO_DIR/git-templates"
  if [[ ! -d "$TEMPLATE_SRC" ]]; then
    err "找不到模板目录: $TEMPLATE_SRC"
    err "请在仓库根目录运行本脚本"
    tpl_failed=1
    return 1
  fi
  src_real="$(readlink -f -- "$TEMPLATE_SRC")"

  # 沿用已有的 init.templateDir，否则用 ~/.git-templates
  local configured
  configured="$(git config --global --get init.templateDir 2>/dev/null || true)"
  TEMPLATE_TARGET="${configured%/}"
  [[ -n "$TEMPLATE_TARGET" ]] || TEMPLATE_TARGET="$HOME/.git-templates"

  # --- 链接本身 ---
  if [[ -L "$TEMPLATE_TARGET" ]]; then
    target_real="$(readlink -f -- "$TEMPLATE_TARGET" 2>/dev/null || true)"
    if [[ "$target_real" == "$src_real" ]]; then
      skip "模板软链接已就位: $TEMPLATE_TARGET"
    else
      warn "$TEMPLATE_TARGET 已是指向别处的软链接，未改动："
      info "  当前指向: ${target_real:-<失效>}"
      info "  若想改指本仓库: rm \"$TEMPLATE_TARGET\" && ln -s \"$TEMPLATE_SRC\" \"$TEMPLATE_TARGET\""
      tpl_failed=1
    fi
  elif [[ -e "$TEMPLATE_TARGET" ]]; then
    warn "$TEMPLATE_TARGET 已存在（不是软链接），未改动 —— 里面可能有你自己维护的模板"
    info "  确认可以替换后执行: rm -rf \"$TEMPLATE_TARGET\" && ln -s \"$TEMPLATE_SRC\" \"$TEMPLATE_TARGET\""
    tpl_failed=1
  else
    if (( DRY_RUN )); then
      dry "ln -s -- \"$TEMPLATE_SRC\" \"$TEMPLATE_TARGET\""
    elif ln -s -- "$TEMPLATE_SRC" "$TEMPLATE_TARGET" 2>/dev/null; then
      ok "已建立模板软链接: $TEMPLATE_TARGET -> $TEMPLATE_SRC"
    else
      err "创建软链接失败: $TEMPLATE_TARGET"
      tpl_failed=1
    fi
  fi

  # --- init.templateDir ---
  if [[ "$configured" == "$TEMPLATE_TARGET" ]]; then
    skip "init.templateDir 已配置: $TEMPLATE_TARGET"
  else
    if (( DRY_RUN )); then
      dry "git config --global init.templateDir \"$TEMPLATE_TARGET\""
    elif git config --global init.templateDir "$TEMPLATE_TARGET"; then
      ok "已设置 init.templateDir = $TEMPLATE_TARGET"
    else
      err "设置 init.templateDir 失败"
      tpl_failed=1
    fi
  fi

  # --- 可执行位 ---
  local f changed=0
  for f in "$TEMPLATE_SRC"/hooks/*; do
    [[ -e "$f" ]] || continue
    if [[ ! -x "$f" ]]; then
      if (( DRY_RUN )); then
        dry "chmod +x \"$f\""
      else
        chmod +x -- "$f" && ok "已补上可执行位: ${f##*/}"
      fi
      changed=1
    fi
  done
  (( changed )) || skip "hook 可执行位正常"

  # --- 确认 git 真的能读到模板 ---
  if (( ! DRY_RUN && ! tpl_failed )); then
    local probe
    probe="$(mktemp -d)" || return $tpl_failed
    if (cd "$probe" && git init -q __probe__ 2>/dev/null) &&
       [[ -f "$probe/__probe__/.git/hooks/post-commit" ]]; then
      ok "验证通过：新仓库会带上模板 hook"
    else
      warn "验证失败：模板似乎没被 git 采用，请检查 $TEMPLATE_TARGET/hooks/"
      tpl_failed=1
    fi
    rm -rf -- "$probe"
  fi

  return $tpl_failed
}

# ------------------------------------------------------------------ 步骤 2：shell 接入
RC_CANDIDATES=()
init_rc_candidates() {
  RC_CANDIDATES=("$HOME/.bashrc" "$HOME/.bash_aliases" "$HOME/.bash_profile" "$HOME/.profile")
}

# 任一候选文件里是否已经有 source repos.sh 的行
#
# 实现上先剔除注释行，再匹配 `(^|空白)(.|source) 空白 ... repos.sh`。
# 刻意不用 `([^#].*)?(\.|source)` 那种可选组写法 —— POSIX ERE 没有回溯，
# 同样的行第二次就匹配不到了，会让幂等检查失效。
rc_already_configured() {
  # 必须自己先初始化候选列表：首次调用时函数外还没初始化过
  init_rc_candidates
  local f
  for f in "${RC_CANDIDATES[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -vE '^[[:space:]]*#' "$f" 2>/dev/null |
       grep -qE '(^|[[:space:]])(\.|source)[[:space:]]+.*repos\.sh'; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

setup_shell() {
  init_rc_candidates
  RC_LINE=". \"$REPO_DIR/repos.sh\""

  local found
  if found="$(rc_already_configured)"; then
    SHELL_PRESENT=1
    skip "shell 接入已存在: $found"
    info "  $RC_LINE"
    return 0
  fi

  if (( ! WRITE_RC )); then
    hdr "shell 接入（需要你手动执行）"
    local target="${RC_CANDIDATES[0]}"
    info "把下面这行追加到 ${target}（或 ~/.bash_aliases）末尾："
    printf '\n    %s\n\n' "${c_bld}${RC_LINE}${c_reset}"
    info "或者重跑本脚本并加上 ${c_bld}--write-rc${c_reset}，由它代你写入（会先备份）"
    return 0
  fi

  local rc="$RC_FILE"
  if [[ -z "$rc" ]]; then
    rc="${RC_CANDIDATES[0]}"
  fi
  # 展开 ~ 与相对路径
  rc="${rc/#\~/$HOME}"

  if (( DRY_RUN )); then
    dry "追加到 $rc: $RC_LINE"
    return 0
  fi

  if [[ -e "$rc" ]]; then
    if [[ ! -w "$rc" ]]; then
      err "无法写入 $rc（权限不足）"
      info "  请手动追加: $RC_LINE"
      return 1
    fi
    local backup="$rc.repossync-backup.$(date +%Y%m%d%H%M%S)"
    if cp -p -- "$rc" "$backup"; then
      ok "已备份: $backup"
    else
      warn "备份失败，为安全起见中止写入"
      return 1
    fi
  else
    local dir; dir="$(dirname -- "$rc")"
    if [[ ! -d "$dir" ]]; then
      err "目录不存在: $dir"
      return 1
    fi
  fi

  printf '\n# reposSync: 提供 repos 命令\n%s\n' "$RC_LINE" >> "$rc" &&
    ok "已写入 $rc" || { err "写入 $rc 失败"; return 1; }
  SHELL_PRESENT=1
  info "重开终端或执行: source \"$rc\""
  return 0
}

# ------------------------------------------------------------------ 主流程
main() {
  parse_args "$@"

  printf '%s\n' "${c_bld}reposSync 安装${c_reset}"
  info "仓库目录: $REPO_DIR"
  (( DRY_RUN )) && info "模式: dry-run（不会修改任何文件）"

  local rc=0

  if (( DO_HOOKS )); then
    hdr "步骤 1/2 · git hook 模板"
    setup_hooks || rc=1
  else
    hdr "步骤 1/2 · git hook 模板"
    skip "已按 --no-hooks 跳过"
  fi

  if (( DO_SHELL )); then
    hdr "步骤 2/2 · shell 接入"
    setup_shell || rc=1
  else
    hdr "步骤 2/2 · shell 接入"
    skip "已按 --no-shell 跳过"
    (( DRY_RUN )) || SHELL_PRESENT=1   # 用户主动跳过，不再喋喋不休地提醒
  fi

  # ---- 首次扫描 ----
  hdr "下一步"
  local scan="$REPO_DIR/link-repos.sh"
  if (( RUN_SCAN )) && (( ! DRY_RUN )); then
    info "执行首次扫描..."
    "$scan" || rc=1
  else
    info "${c_bld}预览${c_reset}将要建立的链接:  $scan -n"
    info "${c_bld}执行${c_reset}首次扫描:            $scan"
    (( SHELL_PRESENT )) || info "追加 rc 那一行后重开终端，repos 命令即可用"
  fi

  if (( rc == 0 )); then
    printf '\n%s\n' "${c_grn}${c_bld}安装完成${c_reset}"
  else
    printf '\n%s\n' "${c_yel}${c_bld}安装完成，但有项目需要你手动处理（见上方 ⚠）${c_reset}"
  fi
  exit $rc
}

main "$@"
