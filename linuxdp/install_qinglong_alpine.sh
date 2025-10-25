#!/usr/bin/env bash
# install_qinglong_alpine.sh
# 适用 Alpine 3.18+，整合新版 Dockerfile 的依赖与结构，并结合你之前的本地安装做法。
# 默认使用 TUNA 镜像、国内 npm/pip 源，分支默认 develop，可通过环境变量覆盖：QL_BRANCH=master

set -euo pipefail

# --------------------------
# 可配参数（如需自定义可在执行前 export）
# --------------------------
QL_MAINTAINER="${QL_MAINTAINER:-whyour}"
QL_URL="${QL_URL:-https://gh-proxy.com/https://github.com/${QL_MAINTAINER}/qinglong.git}"
QL_BRANCH="${QL_BRANCH:-master}"

QL_DIR="${QL_DIR:-/ql}"
PNPM_HOME="${PNPM_HOME:-${QL_DIR}/data/dep_cache/node}"
PYTHON_HOME="${PYTHON_HOME:-${QL_DIR}/data/dep_cache/python3}"
PYTHON_SHORT_VERSION="${PYTHON_SHORT_VERSION:-3.11}"

# 国内源
ALPINE_MIRROR="${ALPINE_MIRROR:-mirrors.tuna.tsinghua.edu.cn}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"

# --------------------------
# 基础优化：Alpine 源、时区
# --------------------------
echo "[1/6] 切换 Alpine 软件源到 ${ALPINE_MIRROR}..."
sed -i "s/dl-cdn.alpinelinux.org/${ALPINE_MIRROR}/g" /etc/apk/repositories

apk update -f
apk upgrade

echo "[2/6] 安装基础依赖..."
# 按新版 Dockerfile 与旧脚本综合
apk --no-cache add -f \
  bash coreutils moreutils \
  git curl wget \
  tzdata perl openssl \
  nginx \
  python3 py3-pip \
  jq \
  openssh \
  nodejs npm \
  procps netcat-openbsd unzip

# 清缓存
rm -rf /var/cache/apk/*

# 时区
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# --------------------------
# Node/pnpm 全局安装 + 国内源
# --------------------------
echo "[3/6] 配置 npm 国内源并安装 pnpm/pm2/ts-node/typescript/tslib..."
npm config set registry "${NPM_REGISTRY}"
# 为确保版本一致性，采用与 Dockerfile 中一致的 pnpm 版本
npm i -g pnpm@8.3.1 pm2 ts-node typescript tslib

# --------------------------
# Git 全局配置
# --------------------------
git config --global user.email "qinglong@users.noreply.github.com"
git config --global user.name "qinglong"
git config --global http.postBuffer 524288000

# --------------------------
# 克隆项目与静态资源
# --------------------------
echo "[4/6] 克隆青龙 ${QL_BRANCH} 分支..."
mkdir -p "${QL_DIR}"
if [ ! -d "${QL_DIR}/.git" ]; then
  git clone --depth=1 -b "${QL_BRANCH}" "${QL_URL}" "${QL_DIR}"
else
  echo "检测到 ${QL_DIR} 已存在，执行拉取更新..."
  cd "${QL_DIR}"
  git fetch --depth=1 origin "${QL_BRANCH}" || true
  git checkout "${QL_BRANCH}" || true
  git pull --rebase || true
fi

cd "${QL_DIR}"
cp -f .env.example .env || true
chmod 777 "${QL_DIR}/shell/"*.sh || true
chmod 777 "${QL_DIR}/docker/"*.sh || true

echo "[5/6] 拉取静态资源..."
git clone --depth=1 -b "${QL_BRANCH}" https://gh-proxy.com/https://github.com/${QL_MAINTAINER}/qinglong-static.git /static
mkdir -p "${QL_DIR}/static"
cp -rf /static/* "${QL_DIR}/static"
rm -rf /static

# --------------------------
# 依赖缓存与环境变量
# --------------------------
echo "[6/6] 配置依赖缓存与环境变量..."

# PNPM/Python 缓存目录
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

# 写入持久环境文件（登录即生效）
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

# pip 国内源 + 必要依赖（与 Dockerfile 对齐）
python3 -m pip config set global.index-url "${PIP_INDEX_URL}" || true
python3 -m pip install --prefix "${PYTHON_HOME}" --no-cache-dir requests

# 使用 pnpm 安装项目依赖（生产）
# 为了识别国内源，可以在项目根写入 .npmrc（如有）或使用 npm registry 设置
# 保证在 /ql 下执行
cd "${QL_DIR}"
# 如项目含 package.json，执行依赖安装
if [ -f package.json ]; then
  # 清理可能遗留的缓存以避免权限问题
  rm -rf /root/.npm || true
  rm -rf /root/.pnpm-store || true

  # 将国内源固化到项目（可选）
  echo "registry=${NPM_REGISTRY}" > .npmrc

  # 安装生产依赖
  pnpm install --prod
fi

# 软限制对齐
ulimit -c 0 || true

# --------------------------
# 批量修补 /ql/shell 下所有 .sh：把 $QL_DIR / ${QL_DIR} 替换为 /ql
# 说明：
# 1) 幂等：重复执行不会破坏内容；
# 2) 带备份：每个文件生成 .bak.<timestamp>，方便回滚；
# 3) 同时处理 $QL_DIR 与 ${QL_DIR} 两种写法；
# 4) 保留其它内容不变；
# --------------------------
echo "批量修补 /ql/shell/*.sh 中的 QL_DIR 引用为绝对路径 /ql ..."
PATCH_TS="$(date +%F-%H%M%S)"
SHELL_DIR="${QL_DIR}/shell"

# 防御：确保目录存在且有脚本
if [ ! -d "$SHELL_DIR" ]; then
  echo "[错误] 未找到目录：$SHELL_DIR"
  exit 1
fi
if ! find "$SHELL_DIR" -type f -name '*.sh' | grep -q .; then
  echo "[提示] ${SHELL_DIR} 下没有 .sh 文件，无需修补。"
else
  # 逐个文件处理，保留备份
  while IFS= read -r f; do
    # 只在文件中确实出现变量引用时才处理
    if grep -Eq '\$\{?QL_DIR\}?([^A-Za-z0-9_]|$)' "$f"; then
      cp -a "$f" "${f}.bak.${PATCH_TS}"
      # 将 $QL_DIR 和 ${QL_DIR} 都替换为 /ql
      # 使用分隔符 |，避免路径斜杠冲突；-E 支持扩展正则
      # 两次替换分别针对 ${QL_DIR} 与 $QL_DIR 写法
      sed -E -i \
        -e 's|\$\{QL_DIR\}|/ql|g' \
        -e 's|\$QL_DIR|/ql|g' \
        "$f"
      echo "[修补] $(basename "$f")"
    fi
    # 确保可执行权限
    chmod +x "$f" || true
  done < <(find "$SHELL_DIR" -type f -name '*.sh' -print)
fi
``

# 修补入口脚本路径与 QL_DIR 兜底
echo "修补入口脚本路径与 QL_DIR 兜底..."
ENTRY="${QL_DIR}/docker/docker-entrypoint.sh"
if [ ! -f "$ENTRY" ]; then
  echo "未找到入口脚本：$ENTRY"
  exit 1
fi

# 在 shebang 之后仅注入 QL_DIR 兜底（一次性）
if ! grep -q 'export QL_DIR=' "$ENTRY"; then
  awk 'NR==1{print; print "export QL_DIR=\"${QL_DIR:-/ql}\""; next}1' "$ENTRY" > "${ENTRY}.tmp" \
    && mv "${ENTRY}.tmp" "$ENTRY"
fi

# 统一修复 source 路径为绝对路径
sed -i \
  -e 's#\.\s\+\.\/ql\/shell\/share\.sh#. "${QL_DIR}/shell/share.sh"#' \
  -e 's#\.\s\+\.\/ql\/shell\/env\.sh#. "${QL_DIR}/shell/env.sh"#' \
  -e 's#\.\s\+\$dir_shell/share\.sh#. "${QL_DIR}/shell/share.sh"#' \
  -e 's#\.\s\+\$dir_shell/env\.sh#. "${QL_DIR}/shell/env.sh"#' \
  "$ENTRY"

# （可选）统一 dir_shell 的定义
#sed -i 's#^dir_shell=.*#dir_shell="${QL_DIR}/shell"#' "$ENTRY"

# 启动
echo "安装完毕！！启动青龙入口脚本...机器重启后请执行 bash /ql/docker/docker-entrypoint.sh 即可"
exec bash "${ENTRY}"
