#!/usr/bin/env bash
# cninstall_qinglong_alpine.sh
# 适用于：ZeroTermux / proot Alpine(建议 3.18+) 的「非 Docker」本地一键安装青龙面板
# 对齐新版 Dockerfile.txt 的关键点：
#   - 默认分支：develop
#   - Node + npm + pnpm@8.3.1 + pm2 + ts-node
#   - 依赖包：bash/coreutils/git/curl/wget/tzdata/perl/openssl/jq/openssh/procps/netcat-openbsd/unzip/npm
#   - 目录：/ql
#   - dep_cache：/ql/data/dep_cache/node  与  /ql/data/dep_cache/python3
#   - pip 安装 requests 到 PYTHON_HOME
#
# 使用方式：
#   1) 在 proot Alpine 中：chmod +x cninstall_qinglong_alpine.sh && ./cninstall_qinglong_alpine.sh
#   2) 自定义（可选）：
#      export QL_BRANCH=develop
#      export QL_MAINTAINER=whyour
#      export QL_URL=https://github.com/whyour/qinglong.git
#      export QL_STATIC_URL=https://github.com/whyour/qinglong-static.git
#      export ALPINE_MIRROR=mirrors.aliyun.com
#      export NPM_REGISTRY=https://registry.npmmirror.com
#      export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple
#
set -euo pipefail

log()  { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2; }

# --------------------------
# 可配参数（执行前 export 覆盖）
# --------------------------
QL_MAINTAINER="${QL_MAINTAINER:-whyour}"
QL_BRANCH="${QL_BRANCH:-develop}"
QL_DIR="${QL_DIR:-/ql}"

# Dockerfile 默认 GitHub；国内网络可自行 export 为 Gitee
QL_URL="${QL_URL:-https://github.com/${QL_MAINTAINER}/qinglong.git}"
QL_URL_FALLBACK="${QL_URL_FALLBACK:-https://gitee.com/${QL_MAINTAINER}/qinglong.git}"

QL_STATIC_URL="${QL_STATIC_URL:-https://github.com/${QL_MAINTAINER}/qinglong-static.git}"
QL_STATIC_URL_FALLBACK="${QL_STATIC_URL_FALLBACK:-https://gitee.com/${QL_MAINTAINER}/qinglong-static.git}"

PNPM_HOME="${PNPM_HOME:-${QL_DIR}/data/dep_cache/node}"
PYTHON_HOME="${PYTHON_HOME:-${QL_DIR}/data/dep_cache/python3}"
PYTHON_SHORT_VERSION="${PYTHON_SHORT_VERSION:-3.11}"

# 国内源（按需改）
ALPINE_MIRROR="${ALPINE_MIRROR:-mirrors.aliyun.com}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://mirrors.aliyun.com/pypi/simple}"

# --------------------------
# 0) 前置检查
# --------------------------
if [ "${EUID:-0}" -ne 0 ]; then
  warn "检测到非 root 执行；在 proot Alpine 里通常应为 root。若安装失败请切换 root。"
fi

# --------------------------
# 1) 切换 Alpine 软件源、更新
# --------------------------
log "[1/7] 切换 Alpine 软件源到 ${ALPINE_MIRROR} 并更新..."
if [ -f /etc/apk/repositories ]; then
  sed -i "s/dl-cdn.alpinelinux.org/${ALPINE_MIRROR}/g" /etc/apk/repositories || true
fi
apk update -f
apk upgrade || true

# --------------------------
# 2) 安装系统依赖（对齐 Dockerfile）
# --------------------------
log "[2/7] 安装系统依赖..."
apk --no-cache add -f \
  bash coreutils \
  git curl wget \
  tzdata perl openssl \
  jq \
  openssh \
  nodejs npm \
  procps netcat-openbsd unzip \
  python3 py3-pip

rm -rf /var/cache/apk/* || true

# 时区
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# --------------------------
# 3) Node 全局工具：pnpm/pm2/ts-node（对齐 Dockerfile）
# --------------------------
log "[3/7] 配置 npm 源并安装 pnpm@8.3.1 / pm2 / ts-node ..."
npm config set registry "${NPM_REGISTRY}" || true
npm i -g pnpm@8.3.1 pm2 ts-node

# --------------------------
# 4) Git 全局配置（对齐 Dockerfile 里的 user / postBuffer）
# --------------------------
log "[4/7] 配置 git 全局信息..."
git config --global user.email "qinglong@users.noreply.github.com" || true
git config --global user.name "qinglong" || true
git config --global http.postBuffer 524288000 || true

# --------------------------
# 5) 克隆/更新青龙与静态资源
# --------------------------
log "[5/7] 克隆/更新青龙：branch=${QL_BRANCH} dir=${QL_DIR}"
mkdir -p "${QL_DIR}"

clone_repo() {
  local url="$1" dir="$2" branch="$3"
  if [ ! -d "${dir}/.git" ]; then
    git clone --depth=1 -b "${branch}" "${url}" "${dir}"
  else
    ( cd "${dir}" \
      && git fetch --depth=1 origin "${branch}" \
      && git checkout "${branch}" \
      && git pull --rebase )
  fi
}

if ! clone_repo "${QL_URL}" "${QL_DIR}" "${QL_BRANCH}"; then
  warn "使用主地址克隆失败：${QL_URL}，尝试备用：${QL_URL_FALLBACK}"
  clone_repo "${QL_URL_FALLBACK}" "${QL_DIR}" "${QL_BRANCH}"
fi

cd "${QL_DIR}"
cp -f .env.example .env 2>/dev/null || true
chmod 777 "${QL_DIR}/shell/"*.sh 2>/dev/null || true
chmod 777 "${QL_DIR}/docker/"*.sh 2>/dev/null || true

log "拉取静态资源 qinglong-static ..."
rm -rf /static 2>/dev/null || true
if ! git clone --depth=1 -b "${QL_BRANCH}" "${QL_STATIC_URL}" /static; then
  warn "静态资源主地址失败：${QL_STATIC_URL}，尝试备用：${QL_STATIC_URL_FALLBACK}"
  git clone --depth=1 -b "${QL_BRANCH}" "${QL_STATIC_URL_FALLBACK}" /static
fi
mkdir -p "${QL_DIR}/static"
cp -rf /static/* "${QL_DIR}/static" || true
rm -rf /static || true

# --------------------------
# 6) 依赖缓存目录 + 环境变量（对齐 Dockerfile 的 ENV）
# --------------------------
log "[6/7] 配置 dep_cache 目录与环境变量..."
mkdir -p "${PNPM_HOME}" "${PYTHON_HOME}" "${PYTHON_HOME}/pip"

export PNPM_HOME PYTHON_HOME
export PYTHONUSERBASE="${PYTHON_HOME}"
export LANG="C.UTF-8"
export SHELL="/bin/bash"
export PS1="\u@\h:\w \$ "
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PNPM_HOME}:${PYTHON_HOME}/bin"
export NODE_PATH="/usr/local/bin:/usr/local/lib/node_modules:${PNPM_HOME}/global/5/node_modules"
export PIP_CACHE_DIR="${PYTHON_HOME}/pip"
export PYTHONPATH="${PYTHON_HOME}:${PYTHON_HOME}/lib/python${PYTHON_SHORT_VERSION}:${PYTHON_HOME}/lib/python${PYTHON_SHORT_VERSION}/site-packages"

# 写入持久化 profile（下次登录自动生效）
cat >/etc/profile.d/qinglong.sh <<EOF
export PNPM_HOME="${PNPM_HOME}"
export PYTHON_HOME="${PYTHON_HOME}"
export PYTHONUSERBASE="${PYTHON_HOME}"
export LANG="C.UTF-8"
export SHELL="/bin/bash"
export PS1="\\u@\\h:\\w \\$ "
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\${PNPM_HOME}:\${PYTHON_HOME}/bin"
export NODE_PATH="/usr/local/bin:/usr/local/lib/node_modules:\${PNPM_HOME}/global/5/node_modules"
export PIP_CACHE_DIR="\${PYTHON_HOME}/pip"
export PYTHONPATH="\${PYTHON_HOME}:\${PYTHON_HOME}/lib/python${PYTHON_SHORT_VERSION}:\${PYTHON_HOME}/lib/python${PYTHON_SHORT_VERSION}/site-packages"
EOF

# pip 国内源 + requests（对齐 Dockerfile 的 pip install --prefix PYTHON_HOME requests）
python3 -m pip config set global.index-url "${PIP_INDEX_URL}" 2>/dev/null || true
python3 -m pip install --prefix "${PYTHON_HOME}" --no-cache-dir requests

# 项目依赖（生产）
log "安装 Node 生产依赖（pnpm install --prod）..."
if [ -f package.json ]; then
  rm -rf /root/.npm /root/.pnpm-store 2>/dev/null || true
  # 不强行覆盖已有 .npmrc；若不存在则写入 registry
  if [ ! -f .npmrc ]; then
    echo "registry=${NPM_REGISTRY}" > .npmrc
  fi
  pnpm install --prod
else
  warn "未找到 package.json，跳过 pnpm install。"
fi

ulimit -c 0 2>/dev/null || true

# --------------------------
# 7) 适配 proot：把 shell 脚本里的 QL_DIR 引用替换为 /ql（可选但推荐）
# --------------------------
log "[7/7] 修补 /ql/shell/*.sh 中的 $QL_DIR / ${QL_DIR} 引用为 /ql（幂等，带备份）..."
PATCH_TS="$(date +%F-%H%M%S)"
SHELL_DIR="${QL_DIR}/shell"

if [ -d "${SHELL_DIR}" ] && find "${SHELL_DIR}" -maxdepth 1 -type f -name '*.sh' -print -quit 2>/dev/null | grep -q .; then
  while IFS= read -r f; do
    if grep -Eq '\$\{?QL_DIR\}?([^A-Za-z0-9_]|$)' "$f"; then
      cp -a "$f" "${f}.bak.${PATCH_TS}"
      sed -E -i \
        -e 's|\$\{QL_DIR\}|/ql|g' \
        -e 's|\$QL_DIR|/ql|g' \
        "$f"
      log "[修补] $(basename "$f")"
    fi
    chmod +x "$f" 2>/dev/null || true
  done < <(find "${SHELL_DIR}" -type f -name '*.sh' -print)
else
  warn "未找到 ${SHELL_DIR} 或无 .sh 文件，跳过修补。"
fi

# 修补入口脚本：注入 QL_DIR 兜底，并把 source 路径改为绝对引用
ENTRY="${QL_DIR}/docker/docker-entrypoint.sh"
if [ -f "${ENTRY}" ]; then
  log "修补入口脚本：${ENTRY}"
  if ! grep -q 'export QL_DIR=' "${ENTRY}"; then
    awk -v ql_dir="${QL_DIR}" 'NR==1{print; print "export QL_DIR=\"" ql_dir "\""; next}1' "${ENTRY}" > "${ENTRY}.tmp" \
      && mv "${ENTRY}.tmp" "${ENTRY}"
  fi
  sed -i \
    -e 's#\.\s\+\.\/ql\/shell\/share\.sh#. "${QL_DIR}/shell/share.sh"#' \
    -e 's#\.\s\+\.\/ql\/shell\/env\.sh#. "${QL_DIR}/shell/env.sh"#' \
    -e 's#\.\s\+\$dir_shell/share\.sh#. "${QL_DIR}/shell/share.sh"#' \
    -e 's#\.\s\+\$dir_shell/env\.sh#. "${QL_DIR}/shell/env.sh"#' \
    "${ENTRY}" || true
else
  warn "未找到入口脚本：${ENTRY}（可能仓库结构变动），请自行在 ${QL_DIR}/docker 下查看。"
fi

log "安装完成！启动方式："
echo "  立即启动：bash ${ENTRY}"
echo "  以后启动：bash /ql/docker/docker-entrypoint.sh"

exec bash "${ENTRY}"
