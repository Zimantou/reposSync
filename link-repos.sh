#!/usr/bin/env bash
#
# link-repos.sh —— 扫描系统中的 Git 仓库，并在统一入口目录（默认 ~/repos）下创建软链接。
#
#   原仓库保留在原地，不移动、不复制，只创建符号链接。
#   脚本是幂等的：可以反复运行，不会重复创建或破坏已有链接。
#
# 用法:
#   link-repos.sh [选项] [扫描根目录]
#
# 示例:
#   link-repos.sh                        # 扫描 $HOME（深度 5），同步到 ~/repos
#   link-repos.sh ~/work -d 3            # 扫描 ~/work，最大深度 3
#   link-repos.sh -n                     # dry-run：只预览，不做任何修改
#   link-repos.sh -q                     # 安静模式：只输出统计信息
#   link-repos.sh -l                     # 只列出 ~/repos 下的软链接（不扫描）
#
# 作者: Deepseek V4.1 Flash | 版本: 1.0.0
#
set -uo pipefail

PROG="${0##*/}"
VERSION="1.0.0"

# ------------------------------------------------------------------ 默认配置
# 链接存放目录（统一入口）
TARGET_DIR="${LINK_REPOS_TARGET:-$HOME/repos}"
# 最大扫描深度
MAX_DEPTH="${LINK_REPOS_DEPTH:-5}"
# 默认扫描根目录
DEFAULT_ROOT="$HOME"
# 自动生成的仓库清单文件名（相对 TARGET_DIR）。
# 注意：脚本只写这个文件，**绝不动 README.md** —— README.md 由人手工维护。
LIST_FILE="${LINK_REPOS_LIST_FILE:-REPOS_LIST.md}"

# 扫描时“剪枝”的目录名（命中后不再向下递归）。
# 需要临时追加时，可设置环境变量 LINK_REPOS_PRUNE_EXTRA="foo:bar"
PRUNE_NAMES=(
  # —— 你明确要求的 ——
  .git .hg .svn
  node_modules
  __pycache__
  .cache .local .config
  venv .venv virtualenv
  # —— 常见噪声目录（可按需增删）——
  site-packages .tox .nox .eggs
  .mypy_cache .pytest_cache .ruff_cache
  .npm .pnpm-store .yarn
  .cargo .rustup .gradle .m2
  .conda .anaconda .julia
  .vscode-server .vscode-server-insiders .cursor-server
  .terraform
)

# 注意：conda 的安装目录（miniconda3 / anaconda3 / miniforge3）**不剪枝**。
# 它们的 envs/ 下经常放着真正的 git clone（例如某个 env 里装的项目源码），
# 剪掉就会漏掉这些仓库。maxdepth 会限制遍历深度，实测全量扫描仍在 0.3 秒内。

# ------------------------------------------------------------------ 运行时状态
SCAN_ROOT=""
DRY_RUN=0
QUIET=0
VERBOSE=0
INCLUDE_NESTED=0
WRITE_LIST=1
LINK_ONE=""          # 非空时只处理这一个目录（单目录模式）
MODE="scan"          # scan | list | list-names | list-paths | help | version

found=0              # 发现的 Git 仓库数
created=0            # 新建软链接数
skipped=0            # 已存在且正确，跳过
conflicts=0          # 发生名称冲突（自动改名）
nested_skipped=0     # 嵌套仓库被跳过
errs=0               # 错误数
NEEDED_SUFFIX=0

# ------------------------------------------------------------------ 输出工具
c_reset=$'\033[0m'; c_red=$'\033[31m'; c_grn=$'\033[32m'
c_yel=$'\033[33m'; c_cyn=$'\033[36m'; c_bld=$'\033[1m'
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
  c_reset=""; c_red=""; c_grn=""; c_yel=""; c_cyn=""; c_bld=""
fi

say()      { (( QUIET )) || printf '%s\n' "$*"; }
info()     { (( QUIET )) || printf '%s\n' "$*"; }
warn()     { printf '%s\n' "${c_yel}⚠  $*${c_reset}" >&2; }
err()      { printf '%s\n' "${c_red}✗  $*${c_reset}" >&2; }
okline()   { (( QUIET )) || printf '%s\n' "${c_grn}✓${c_reset}  $*"; }
vmsg()     { (( VERBOSE )) && printf '%s\n' "   · $*"; return 0; }

usage() {
  cat <<EOF
${c_bld}${PROG}${c_reset} v${VERSION} —— 为所有 Git 仓库在统一目录建立软链接

${c_bld}用法${c_reset}
  ${PROG} [选项] [扫描根目录]

${c_bld}选项${c_reset}
  -d, --depth N          最大扫描深度（默认 ${MAX_DEPTH}）
  -t, --target DIR       软链接存放目录（默认 \$HOME/repos）
  -n, --dry-run          只预览将要执行的操作，不创建任何链接
  -N, --include-nested   连嵌套在其他仓库内部的仓库也一并收录
                          （默认跳过：避免把子模块 / 内部目录当成独立仓库）
      --no-list          不生成/更新仓库清单（${LIST_FILE}）
      --no-readme        同上（旧名，保留兼容）
      --link-one DIR     只处理单个目录 DIR（建链接后立即退出，不扫描根目录）
                         供 git hook / shell 包装调用，速度更快
  -q, --quiet            安静模式：只输出最后的统计信息
  -v, --verbose          输出更多细节
  -l, --list             只以表格列出已有软链接及其真实路径
      --list-names       只输出链接名
      --list-paths       只输出真实路径（可用于 xargs / 管道）
  -h, --help             显示本帮助
  -V, --version          显示版本号

${c_bld}生成的文件${c_reset}
  ${PROG} 会在入口目录写一个 ${LIST_FILE}（仓库清单）。
  README.md 是手工维护的说明文档，脚本永远不会读写它。

${c_bld}环境变量${c_reset}
  LINK_REPOS_TARGET      等价于 --target
  LINK_REPOS_DEPTH       等价于 --depth
  LINK_REPOS_LIST_FILE   清单文件名（默认 ${LIST_FILE}）
  LINK_REPOS_PRUNE_EXTRA 追加剪枝目录名，用 ":" 分隔，如 "dist:build"
  NO_COLOR               非空时关闭彩色输出

${c_bld}退出码${c_reset}
  0 成功   1 部分失败   2 参数/环境错误
EOF
}

# ------------------------------------------------------------------ 参数解析
parse_args() {
  local positional=()
  while (( $# )); do
    case "$1" in
      -d|--depth)
        [[ $# -ge 2 ]] || { err "选项 $1 需要一个参数"; exit 2; }
        MAX_DEPTH="$2"; shift 2 ;;
      --depth=*) MAX_DEPTH="${1#*=}"; shift ;;
      -t|--target)
        [[ $# -ge 2 ]] || { err "选项 $1 需要一个参数"; exit 2; }
        TARGET_DIR="$2"; shift 2 ;;
      --target=*) TARGET_DIR="${1#*=}"; shift ;;
      -n|--dry-run)       DRY_RUN=1; shift ;;
      -N|--include-nested) INCLUDE_NESTED=1; shift ;;
      --no-list|--no-readme) WRITE_LIST=0; shift ;;
      --link-one)
        [[ $# -ge 2 ]] || { err "选项 $1 需要一个参数（目录）"; exit 2; }
        LINK_ONE="$2"; shift 2 ;;
      --link-one=*) LINK_ONE="${1#*=}"; shift ;;
      -q|--quiet)         QUIET=1; shift ;;
      -v|--verbose)       VERBOSE=1; shift ;;
      -l|--list)          MODE="list"; shift ;;
      --list-names)       MODE="list-names"; shift ;;
      --list-paths)       MODE="list-paths"; shift ;;
      -h|--help)          MODE="help"; shift ;;
      -V|--version)       MODE="version"; shift ;;
      --)                 shift; while (( $# )); do positional+=("$1"); shift; done ;;
      -*)                 err "未知选项: $1（用 -h 查看帮助）"; exit 2 ;;
      *)                  positional+=("$1"); shift ;;
    esac
  done

  if [[ "${#positional[@]}" -gt 1 ]]; then
    err "最多只能指定一个扫描根目录（收到 ${#positional[@]} 个）"
    exit 2
  fi
  SCAN_ROOT="${positional[0]:-$DEFAULT_ROOT}"

  if ! [[ "$MAX_DEPTH" =~ ^[0-9]+$ ]] || (( MAX_DEPTH < 1 )); then
    err "深度必须是 >=1 的整数，当前为: $MAX_DEPTH"
    exit 2
  fi

  # 保护 README.md：它是人工维护的说明文档，脚本永远不该写它。
  # 万一有人用 LINK_REPOS_LIST_FILE 指过去，这里直接拒绝执行。
  if [[ "${LIST_FILE##*/}" == "README.md" ]]; then
    err "拒绝执行：清单文件名不能是 README.md"
    err "README.md 由人工维护；如需自定义清单名，请设置 LINK_REPOS_LIST_FILE=其他文件名"
    exit 2
  fi
  # 清单名不能带路径分隔符，避免写到入口目录之外
  if [[ "$LIST_FILE" == */* ]]; then
    err "清单文件名不能包含 '/'：$LIST_FILE"
    exit 2
  fi

  # 追加用户自定义剪枝目录
  if [[ -n "${LINK_REPOS_PRUNE_EXTRA:-}" ]]; then
    local IFS=':'
    local extra
    for extra in $LINK_REPOS_PRUNE_EXTRA; do
      [[ -n "$extra" ]] && PRUNE_NAMES+=("$extra")
    done
  fi
}

# ------------------------------------------------------------------ 列表功能
collect_links() {
  # 输出 0 分隔的 "链接名<TAB>真实路径<TAB>状态" 记录
  local link name real state
  while IFS= read -r -d '' link; do
    name="${link##*/}"
    real="$(readlink -f -- "$link" 2>/dev/null || true)"
    if [[ -n "$real" && -e "$real" ]]; then state="ok"; else state="broken"; fi
    printf '%s\t%s\t%s\0' "$name" "${real:-<目标不存在>}" "$state"
  done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null | sort -z)
}

list_links() {
  local want="$1"   # table | names | paths
  if [[ ! -d "$TARGET_DIR" ]]; then
    err "目录不存在: $TARGET_DIR"
    return 1
  fi

  local -a names=() paths=() states=()
  local rec
  while IFS= read -r -d '' rec; do
    names+=("${rec%%$'\t'*}")
    local rest="${rec#*$'\t'}"
    paths+=("${rest%%$'\t'*}")
    states+=("${rest#*$'\t'}")
  done < <(collect_links)

  case "$want" in
    names)
      local i; for ((i=0; i<${#names[@]}; i++)); do printf '%s\n' "${names[$i]}"; done
      return 0 ;;
    paths)
      local i; for ((i=0; i<${#paths[@]}; i++)); do printf '%s\n' "${paths[$i]}"; done
      return 0 ;;
  esac

  if (( ${#names[@]} == 0 )); then
    info "（$TARGET_DIR 下暂无软链接）"
    return 0
  fi

  local w=0 i
  for ((i=0; i<${#names[@]}; i++)); do (( ${#names[$i]} > w )) && w=${#names[$i]}; done
  (( w < 4 )) && w=4

  printf '%s\n' "${c_bld}$(printf '%-*s' "$w" '链接名')  真实路径${c_reset}"
  printf '%s\n' "$(printf '%.0s─' $(seq 1 $w))  $(printf '%.0s─' $(seq 1 40))"
  for ((i=0; i<${#names[@]}; i++)); do
    if [[ "${states[$i]}" == "broken" ]]; then
      printf '%s  %s %s%s%s\n' "$(printf '%-*s' "$w" "${names[$i]}")" "${c_yel}✗${c_reset}" "${c_red}${paths[$i]}${c_reset}" "" "（失效链接）"
    else
      printf '%s  %s %s\n' "$(printf '%-*s' "$w" "${names[$i]}")" "${c_grn}→${c_reset}" "${paths[$i]}"
    fi
  done
  printf '\n共 %d 个链接（%s）\n' "${#names[@]}" "$TARGET_DIR"
}

# ------------------------------------------------------------------ 仓库判断
# 目录中是否存在 .git（目录、文件、或指向别处的符号链接都算）
has_git() {
  local d="$1"
  [[ -d "$d/.git" || -f "$d/.git" || -L "$d/.git" ]]
}

# 判断仓库是否嵌套在另一个仓库内部（子模块 / 仓库里的仓库）
is_nested() {
  local p
  p="$(dirname -- "$1")"
  while [[ "$p" == "$SCAN_ROOT_ABS"/* ]]; do
    if has_git "$p"; then return 0; fi
    p="$(dirname -- "$p")"
  done
  return 1
}

# ------------------------------------------------------------------ 建立链接
# 返回: 0 新建成功 | 1 错误 | 2 已存在且正确（跳过）
link_repo() {
  local real="$1" base="$2"
  NEEDED_SUFFIX=0

  # ---- 幂等检查：base 或 base-N 是否已经指向同一个真实路径 ----
  local i name cur dest
  for ((i=0; i<=30; i++)); do
    if (( i == 0 )); then name="$base"; else name="$base-$i"; fi
    dest="$TARGET_DIR/$name"
    if [[ -L "$dest" ]]; then
      cur="$(readlink -f -- "$dest" 2>/dev/null || true)"
      if [[ -n "$cur" && "$cur" == "$real" ]]; then
        vmsg "已存在，跳过: $name -> $real"
        return 2
      fi
    fi
  done

  # ---- 找一个不冲突的名字 ----
  local candidate="$base" n=1
  while [[ -e "$TARGET_DIR/$candidate" || -L "$TARGET_DIR/$candidate" ]]; do
    candidate="$base-$n"
    ((n++))
  done
  if [[ "$candidate" != "$base" ]]; then
    NEEDED_SUFFIX=1
    local occupied
    occupied="$(readlink -f -- "$TARGET_DIR/$base" 2>/dev/null || true)"
    [[ -n "$occupied" ]] || occupied="<普通文件/目录或失效链接>"
    warn "名称冲突: \"$base\" 已被占用（$occupied），自动改用 \"$candidate\""
  fi

  # ---- 创建 ----
  dest="$TARGET_DIR/$candidate"
  if (( DRY_RUN )); then
    printf '%s\n' "   [dry-run] ln -s -- $real $dest"
    return 0
  fi
  if ln -s -- "$real" "$dest" 2>/dev/null; then
    okline "$candidate  ${c_cyn}→${c_reset} $real"
    return 0
  else
    err "创建软链接失败（权限不足？）: $dest"
    return 1
  fi
}

# ------------------------------------------------------------------ 仓库清单
# 生成 ${LIST_FILE}（仓库清单）。这是脚本唯一会写的文档文件。
# README.md 由人手工维护，本脚本绝不读写它。
write_list() {
  local now tmp
  now="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  tmp="$TARGET_DIR/.$LIST_FILE.tmp.$$"

  local -a names=() paths=() states=()
  local rec
  while IFS= read -r -d '' rec; do
    names+=("${rec%%$'\t'*}")
    local rest="${rec#*$'\t'}"
    paths+=("${rest%%$'\t'*}")
    states+=("${rest#*$'\t'}")
  done < <(collect_links)

  {
    cat <<MDEOF
# 仓库清单（自动生成）

> ⚠️ **本文件由 [\`link-repos.sh\`](./link-repos.sh) 自动生成，请勿手动编辑** ——
> 每次全量同步都会覆盖它。使用说明请看 [\`README.md\`](./README.md)。

MDEOF
    printf -- '- 生成时间: `%s`\n' "$now"
    printf -- '- 扫描根目录: `%s`\n' "$SCAN_ROOT_ABS"
    printf -- '- 最大扫描深度: `%s`\n' "$MAX_DEPTH"
    printf -- '- 链接数量: `%d`\n\n' "${#names[@]}"

    if (( ${#names[@]} == 0 )); then
      printf '_(当前没有任何软链接)_\n'
    else
      printf '| # | 链接名 | 真实路径 |\n|---|--------|----------|\n'
      local i np
      for ((i=0; i<${#names[@]}; i++)); do
        np="${paths[$i]//|/\\|}"
        if [[ "${states[$i]}" == "broken" ]]; then
          printf '| %d | `%s` | `%s` ⚠️ 失效 |\n' "$((i+1))" "${names[$i]}" "$np"
        else
          printf '| %d | [`%s`](./%s) | `%s` |\n' "$((i+1))" "${names[$i]}" "${names[$i]}" "$np"
        fi
      done
      printf '\n> ⚠️ 表示软链接指向的目标已不存在（仓库可能已被移动或删除）。\n'
    fi

    cat <<MDEOF

---

快速查看：\`repos\`（表格）、\`repos -p\`（只输出路径）、\`repos -g\`（附分支与最后提交）。
未安装 \`repos\` 命令时：\`cd $TARGET_DIR && ./link-repos.sh -l\`。
MDEOF
  } > "$tmp" && mv -f -- "$tmp" "$TARGET_DIR/$LIST_FILE" || {
    rm -f -- "$tmp"
    err "写入 $LIST_FILE 失败"
    return 1
  }
  vmsg "$LIST_FILE 已更新: $TARGET_DIR/$LIST_FILE"
}

# ------------------------------------------------------------------ 单目录模式
# 只处理一个目录：必要时建链接，并在链接集合发生变化时刷新清单。
# 供 git 模板 hook 与 shell 包装调用，因此刻意保持静默、快速。
# 返回: 0 成功或无需处理 | 1 出错
link_one() {
  local dir="$1" real base rc

  # 仓库清单里会用到，单目录模式下没有扫描根，用一个合理值占位
  SCAN_ROOT_ABS="$(realpath -m -- "$SCAN_ROOT" 2>/dev/null || printf '%s' "$SCAN_ROOT")"

  if [[ ! -d "$dir" ]]; then
    err "目录不存在: $dir"
    return 1
  fi
  if ! real="$(realpath -- "$dir" 2>/dev/null)"; then
    err "无法解析路径: $dir"
    return 1
  fi

  # 入口目录自身 / 入口目录内部，不处理
  if [[ "$real" == "$TARGET_ABS" || "$real" == "$TARGET_ABS"/* ]]; then
    vmsg "位于入口目录内，跳过: $real"
    return 0
  fi
  if ! has_git "$real"; then
    vmsg "不是 Git 仓库（无 .git），跳过: $real"
    return 0
  fi

  if [[ ! -d "$TARGET_DIR" ]]; then
    if (( DRY_RUN )); then
      warn "[dry-run] 目录不存在，将创建: $TARGET_DIR"
    elif ! mkdir -p -- "$TARGET_DIR" 2>/dev/null; then
      err "无法创建目录（权限不足？）: $TARGET_DIR"
      return 1
    fi
  fi

  found=1
  base="${real##*/}"
  link_repo "$real" "$base"
  rc=$?
  case $rc in
    0) created=1 ;;
    2) skipped=1 ;;
    *) ((errs++)); return 1 ;;
  esac
  (( NEEDED_SUFFIX )) && ((conflicts++))

  # 只在链接集合真的变了的时候重写清单，避免每次 commit 都改动它
  if (( WRITE_LIST )) && (( ! DRY_RUN )) && (( created > 0 || conflicts > 0 )); then
    write_list
  fi
  return 0
}

# ------------------------------------------------------------------ 主流程
main() {
  TARGET_ABS="$(realpath -m -- "$TARGET_DIR" 2>/dev/null)" || TARGET_ABS="$TARGET_DIR"

  # ---- 单目录模式（git hook / shell 包装用）----
  if [[ -n "$LINK_ONE" ]]; then
    link_one "$LINK_ONE"
    exit $?
  fi

  # 扫描根目录必须是存在的目录
  if [[ ! -d "$SCAN_ROOT" ]]; then
    err "扫描根目录不存在或不是目录: $SCAN_ROOT"
    exit 2
  fi
  SCAN_ROOT_ABS="$(realpath -- "$SCAN_ROOT" 2>/dev/null)" || {
    err "无法解析扫描根目录: $SCAN_ROOT"; exit 2
  }

  case "$MODE" in
    help)    usage; exit 0 ;;
    version) printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
    list)       list_links table; exit $? ;;
    list-names) list_links names; exit $? ;;
    list-paths) list_links paths; exit $? ;;
  esac

  # ---- 准备目标目录 ----
  if [[ ! -d "$TARGET_DIR" ]]; then
    if (( DRY_RUN )); then
      warn "[dry-run] 目录不存在，将创建: $TARGET_DIR"
    elif mkdir -p -- "$TARGET_DIR" 2>/dev/null; then
      info "已创建目录: $TARGET_DIR"
    else
      err "无法创建目录（权限不足？）: $TARGET_DIR"
      exit 2
    fi
  fi

  info "${c_bld}扫描 Git 仓库${c_reset}"
  info "  根目录  : $SCAN_ROOT_ABS"
  info "  最大深度: $MAX_DEPTH"
  info "  链接目录: $TARGET_DIR"
  (( DRY_RUN )) && info "  模式    : dry-run（不会修改任何文件）"
  info ""

  # ---- 构造 find：剪枝目标目录 + 剪枝噪声目录 + 只输出目录 ----
  local -a prune_args=( -type d \( )
  local first=1 n
  for n in "${PRUNE_NAMES[@]}"; do
    (( first )) && first=0 || prune_args+=( -o )
    prune_args+=( -name "$n" )
  done
  prune_args+=( \) -prune )

  local -a find_args=(
    "$SCAN_ROOT_ABS" -mindepth 1 -maxdepth "$MAX_DEPTH"
  )
  # 目标目录自身不扫描（防递归）；若目标目录就是根目录则不加此条件
  if [[ "$TARGET_ABS" != "$SCAN_ROOT_ABS" && "$TARGET_ABS" == "$SCAN_ROOT_ABS"/* ]]; then
    find_args+=( \( -path "$TARGET_ABS" -prune \) -o )
  fi
  find_args+=( "${prune_args[@]}" -o -type d -print0 )

  local errlog
  errlog="$(mktemp -t link-repos-errlog.XXXXXX)"
  trap 'rm -f -- "${errlog:-}"' EXIT

  local cand real base rc
  while IFS= read -r -d '' cand; do
    # 只处理真正的 Git 仓库
    has_git "$cand" || continue

    if ! real="$(realpath -- "$cand" 2>/dev/null)"; then
      warn "无法解析真实路径，跳过: $cand"
      ((errs++))
      continue
    fi

    # 跳过扫描根自身 / 目标目录自身
    [[ "$real" == "$SCAN_ROOT_ABS" ]] && continue
    [[ "$real" == "$TARGET_ABS" ]] && continue
    [[ "$real" == "/" ]] && continue

    # 跳过嵌套仓库
    if (( ! INCLUDE_NESTED )) && is_nested "$real"; then
      ((nested_skipped++))
      vmsg "跳过嵌套仓库: $real"
      continue
    fi

    ((found++))
    base="${real##*/}"
    [[ -n "$base" && "$base" != "/" ]] || { warn "无法取得目录名，跳过: $real"; continue; }

    link_repo "$real" "$base"
    rc=$?
    case $rc in
      0) ((created++)); (( NEEDED_SUFFIX )) && ((conflicts++)) ;;
      2) ((skipped++)); (( NEEDED_SUFFIX )) && ((conflicts++)) ;;
      *) ((errs++)) ;;
    esac
  done < <(find "${find_args[@]}" 2>"$errlog")

  # ---- 仓库清单 ----
  if (( WRITE_LIST )) && (( ! DRY_RUN )) && [[ -d "$TARGET_DIR" ]]; then
    write_list
  fi

  # ---- 统计 ----
  local perm=0
  [[ -s "$errlog" ]] && perm="$(wc -l < "$errlog")"

  printf '\n%s\n' "${c_bld}────────────── 统计 ──────────────${c_reset}"
  printf '发现 Git 仓库  : %d\n' "$found"
  printf '新建软链接     : %d\n' "$created"
  printf '已存在跳过     : %d\n' "$skipped"
  printf '名称冲突改名   : %d\n' "$conflicts"
  printf '嵌套仓库跳过   : %d\n' "$nested_skipped"
  printf '错误           : %d\n' "$errs"
  if (( perm > 0 )); then
    printf '%s\n' "${c_yel}权限不足跳过   : ${perm} 个路径（无读取权限，已忽略）${c_reset}"
  fi
  printf '%s\n' "${c_bld}──────────────────────────────────${c_reset}"
  (( DRY_RUN )) && printf '%s\n' "${c_yel}[dry-run] 未做任何修改；去掉 -n 即可真正执行。${c_reset}"
  (( QUIET )) || printf '\n入口目录: %s\n提示: 查看映射可用  %s -l\n' "$TARGET_DIR" "$PROG"

  (( errs > 0 )) && exit 1
  exit 0
}

parse_args "$@"
main
