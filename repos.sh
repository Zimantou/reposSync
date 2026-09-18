# repos.sh —— 在 shell 中提供 `repos` 命令，快速查看 ~/repos 下软链接对应的真实仓库。
#
# 安装：把这行加到 ~/.bashrc 末尾
#     source ~/repos/repos.sh
#
# 用法：
#     repos                 # 表格列出所有链接及真实路径
#     repos sync            # 重新扫描并同步软链接（新建仓库后用它更新索引）
#     repos -p              # 只输出真实路径（可管道给 xargs / fzf）
#     repos -n              # 只输出链接名
#     repos -g              # 额外显示每个仓库的当前分支和最后一次提交
#     repos cd <名字>       # 进入该仓库（支持前缀匹配）
#     repos git <名字> ...  # 对该仓库执行 git 命令
#     repos open <名字>     # 打印真实路径
#     repos help
#
# 另外，source 本文件后会用一个很薄的包装层接管 `git`：
#     git init / git clone 成功后，自动在 ~/repos 建立软链接。
#     非 init/clone 的子命令原样透传。想关掉：export LINK_REPOS_NO_GIT_WRAPPER=1

repos() {
    local REPOS_DIR="${LINK_REPOS_TARGET:-$HOME/repos}"
    local SYNC_SCRIPT="$REPOS_DIR/link-repos.sh"
    local mode="table" show_git=0

    case "${1:-}" in
        ""|-l|--list|ls|list) mode="table" ;;
        -p|--paths|paths)     mode="paths"; shift ;;
        -n|--names|names)     mode="names"; shift ;;
        -g|--git)             mode="table"; show_git=1; shift ;;
        cd|goto)              mode="cd"; shift ;;
        git)                  mode="git"; shift ;;
        open|path)            mode="open"; shift ;;
        sync|update|refresh|index) mode="sync"; shift ;;
        -h|--help|help)       mode="help"; shift ;;
        *) mode="table" ;;
    esac

    if [[ "$mode" == "help" ]]; then
        cat <<'EOF'
repos —— ~/repos 统一仓库入口的使用助手

用法:
  repos                   表格列出所有链接及真实路径
  repos sync              重新扫描并同步软链接（新建 Git 仓库后用这个更新索引）
  repos -g                表格 + 每个仓库的当前分支和最后一次提交
  repos -p                只输出真实路径（可管道给 xargs / fzf）
  repos -n                只输出链接名
  repos cd <名字>         进入该仓库（支持前缀匹配）
  repos git <名字> <参数> 对该仓库执行 git 命令，例: repos git GPUTest status
  repos open <名字>       打印该仓库的真实绝对路径
  repos help              显示本帮助

提示:
  repos sync 之后的多余参数会原样传给 link-repos.sh，例如:
     repos sync -n        # 只预览，不做修改
     repos sync -q        # 安静模式，只输出统计

自动同步:
  source 本文件后，`git init` / `git clone` 成功时会自动调用
  link-repos.sh --link-one 建立链接（其余 git 子命令原样透传）。
  想关掉：export LINK_REPOS_NO_GIT_WRAPPER=1 后重新 source
  临时解除：unset -f git
EOF
        return 0
    fi

    if [[ ! -d "$REPOS_DIR" ]]; then
        echo "repos: 目录不存在: $REPOS_DIR" >&2
        return 1
    fi

    # 前缀匹配出一个仓库名（多个匹配时报错）
    _repos_resolve() {
        local key="$1" hit=() p
        for p in "$REPOS_DIR"/*; do
            [[ -L "$p" ]] || continue
            local b="${p##*/}"
            [[ "$b" == "$key" ]] && { printf '%s' "$b"; return 0; }
            [[ "$b" == "$key"* ]] && hit+=("$b")
        done
        if (( ${#hit[@]} == 1 )); then printf '%s' "${hit[0]}"; return 0; fi
        if (( ${#hit[@]} == 0 )); then echo "repos: 找不到匹配 '$key' 的仓库" >&2; return 1; fi
        echo "repos: '$key' 匹配到多个仓库: ${hit[*]}" >&2
        return 1
    }

    case "$mode" in
        sync)
            if [[ ! -x "$SYNC_SCRIPT" ]]; then
                echo "repos: 找不到同步脚本 $SYNC_SCRIPT" >&2
                return 1
            fi
            "$SYNC_SCRIPT" "$@"
            ;;
        cd)
            local name; name="$(_repos_resolve "${1:?用法: repos cd <名字>}")" || return 1
            builtin cd -- "$REPOS_DIR/$name" || return 1
            ;;
        open)
            local name; name="$(_repos_resolve "${1:?用法: repos open <名字>}")" || return 1
            printf '%s\n' "$REPOS_DIR/$name"
            ;;
        git)
            local name; name="$(_repos_resolve "${1:?用法: repos git <名字> <git 参数...>}")" || return 1
            shift
            git -C "$REPOS_DIR/$name" "$@"
            ;;
        names)
            find "$REPOS_DIR" -mindepth 1 -maxdepth 1 -type l -printf '%f\n' | sort
            ;;
        paths)
            find "$REPOS_DIR" -mindepth 1 -maxdepth 1 -type l -print0 \
              | sort -z | xargs -0 -r -n1 readlink -f
            ;;
        table)
            local -a names=() reals=()
            local link
            while IFS= read -r -d '' link; do
                names+=("${link##*/}")
                reals+=("$(readlink -f -- "$link" 2>/dev/null || echo '<失效>')")
            done < <(find "$REPOS_DIR" -mindepth 1 -maxdepth 1 -type l -print0 | sort -z)

            if (( ${#names[@]} == 0 )); then
                echo "（$REPOS_DIR 下暂无软链接，可运行 $REPOS_DIR/link-repos.sh 生成）"
                return 0
            fi

            local w=0 i
            for ((i = 0; i < ${#names[@]}; i++)); do
                (( ${#names[$i]} > w )) && w=${#names[$i]}
            done

            for ((i = 0; i < ${#names[@]}; i++)); do
                local extra=""
                if (( show_git )) && [[ -e "${reals[$i]}/.git" ]]; then
                    local br last
                    br="$(git -C "${reals[$i]}" rev-parse --abbrev-ref HEAD 2>/dev/null)"
                    last="$(git -C "${reals[$i]}" log -1 --format='%ad %s' --date=short 2>/dev/null)"
                    extra="  [${br:-?}] ${last}"
                fi
                printf '%-*s  %s%s\n' "$w" "${names[$i]}" "${reals[$i]}" "$extra"
            done
            printf '\n共 %d 个仓库（%s）\n' "${#names[@]}" "$REPOS_DIR"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# 可选：包装 `git`，让 `git init` / `git clone` 成功后自动在 ~/repos 建立链接。
#   不想用时：在 source 本文件之前设置 LINK_REPOS_NO_GIT_WRAPPER=1
#   也可单独关闭：unset -f git
# 包装层非常薄：非 init/clone 的子命令原样透传给真正的 git。
# ---------------------------------------------------------------------------
if [[ -z "${LINK_REPOS_NO_GIT_WRAPPER:-}" ]] && command -v git >/dev/null 2>&1; then

    # 该选项是否需要一个值？（用于跳过它的值，避免把值误当成目录参数）
    _repos_opt_takes_value() {
        case "$1:$2" in
            init:--separate-git-dir | init:--template | init:-b | init:--initial-branch | \
            init:--object-format | init:--ref-format) return 0 ;;
            clone:--origin | clone:-o | clone:--branch | clone:-b | clone:--upload-pack | \
            clone:-u | clone:--reference | clone:--reference-if-able | \
            clone:--separate-git-dir | clone:--depth | clone:--shallow-since | \
            clone:--shallow-exclude | clone:--template | clone:--config | clone:-c | \
            clone:--jobs | clone:-j | clone:--filter | clone:--bundle-uri | \
            clone:--revision | clone:-r) return 0 ;;
        esac
        return 1
    }

    # 从 git 参数中提取位置参数（目录/URL），每行一个
    _repos_positional_args() {
        local sub="${1:-}"
        [[ $# -gt 0 ]] && shift
        local a opt seen_dd=0
        local -a out=()
        while (( $# )); do
            a="$1"
            if (( seen_dd )); then out+=("$a"); shift; continue; fi
            case "$a" in
                --) seen_dd=1; shift; continue ;;
                --*)
                    if [[ "$a" != *=* ]] && _repos_opt_takes_value "$sub" "$a"; then
                        shift 2 2>/dev/null || shift
                    else
                        shift
                    fi
                    continue ;;
                -?*)
                    opt="${a:0:2}"
                    if _repos_opt_takes_value "$sub" "$opt"; then
                        if (( ${#a} > 2 )); then shift; else shift 2 2>/dev/null || shift; fi
                    else
                        shift
                    fi
                    continue ;;
            esac
            out+=("$a")
            shift
        done
        (( ${#out[@]} )) && printf '%s\n' "${out[@]}"
        return 0
    }

    git() {
        command git "$@"
        local __rc=$?

        local __sub="${1:-}"
        case "$__sub" in init | clone) ;; *) return $__rc ;; esac
        (( __rc == 0 )) || return $__rc

        local __sync="${LINK_REPOS_TARGET:-$HOME/repos}/link-repos.sh"
        [[ -x "$__sync" ]] || return $__rc

        local -a __pos=()
        local __line
        while IFS= read -r __line; do
            [[ -n "$__line" ]] && __pos+=("$__line")
        done < <(_repos_positional_args "$@")

        # 推出应该建立链接的目录
        local __dir=""
        if [[ "$__sub" == "init" ]]; then
            __dir="${__pos[0]:-}"
            [[ -n "$__dir" ]] || __dir="$PWD"
        else
            __dir="${__pos[1]:-}"
            if [[ -z "$__dir" && -n "${__pos[0]:-}" ]]; then
                local __url="${__pos[0]%/}"
                __dir="${__url##*/}"
                __dir="${__dir%.git}"
            fi
        fi

        if [[ -n "$__dir" && -d "$__dir" ]]; then
            "$__sync" --link-one "$__dir" || true
        else
            # 解析不出来（冷门选项组合等），退化为完整重扫，保证不漏
            "$__sync" -q || true
        fi
        return $__rc
    }
fi
