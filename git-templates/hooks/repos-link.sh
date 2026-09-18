#!/usr/bin/env bash
#
# repos-link.sh —— 被 ~/.git-templates 里的 post-commit / post-checkout 调用。
#
# 作用：确保当前仓库已经在统一入口（默认 ~/repos）里有软链接。
#       如果链接已存在，link-repos.sh 会自行识别并跳过，不会重复创建。
#
# 设计原则：绝不能影响 git 操作本身 —— 任何失败都静默退出 0。
# 安装：见 ~/repos/link-repos.sh（脚本会把本文件随 git 模板一起复制到新仓库）。
#
set -u

# 只在需要时才引入的退出码：本脚本永远返回 0
repos_dir="${LINK_REPOS_TARGET:-$HOME/repos}"
sync="$repos_dir/link-repos.sh"

# 同步脚本不存在（例如入口目录被移动）→ 什么都不做
[[ -x "$sync" ]] || exit 0

# 当前仓库的顶层目录
top="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$top" && -d "$top" ]] || exit 0

# 快速路径：入口目录里的同名条目已指向本仓库时直接返回，
# 避免每次 commit / checkout 都去调用一次同步脚本。
# （同名但指向别处的情况交给 link-repos.sh 处理，它会自动加 -1/-2 后缀）
if [[ -e "$repos_dir/${top##*/}" || -L "$repos_dir/${top##*/}" ]]; then
  cur="$(readlink -f -- "$repos_dir/${top##*/}" 2>/dev/null || true)"
  [[ "$cur" == "$top" ]] && exit 0
fi

# 完全静默：不干扰 git 的正常输出
"$sync" --link-one "$top" -q >/dev/null 2>&1 || true
exit 0
