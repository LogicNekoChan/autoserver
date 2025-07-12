#!/usr/bin/env bash
# reinstall.sh  – 一键重装 Linux（Linux 专用，交互式）
set -eE
set -o pipefail

#################### 1. 自动镜像源选择 ####################
CN_REPO="https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh"
GLOBAL_REPO="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"

is_cn() {
    curl -s --retry 3 http://www.qualcomm.cn/cdn-cgi/trace | grep -q '^loc=CN'
}

# 如果当前脚本小于 50 行，说明只是“启动器”，下载完整 reinstall.sh
[[ $(wc -l < "$0") -lt 50 ]] && {
    repo=$([ is_cn ] && echo "$CN_REPO" || echo "$GLOBAL_REPO")
    curl -fsSL "$repo" -o reinstall-real.sh || wget -O reinstall-real.sh "$repo"
    chmod +x reinstall-real.sh
    exec bash reinstall-real.sh "$@"
}

#################### 2. 交互式收集信息 ####################
mapfile -t ALL_DISTROS < <(
    cat <<'EOF' | column -t
anolis      7|8|23
opencloudos 8|9|23
rocky       8|9|10
oracle      8|9
almalinux   8|9|10
centos      9|10
fedora      41|42
nixos       25.05
debian      9|10|11|12
opensuse    15.6|tumbleweed
alpine      3.19|3.20|3.21|3.22
openeuler   20.03|22.03|24.03|25.03
ubuntu      16.04|18.04|20.04|22.04|24.04|25.04
kali
arch
gentoo
aosc
fnos
redhat
EOF
)

echo "====== 一键重装 Linux ======"
echo "支持的发行版及版本："
printf '%s\n' "${ALL_DISTROS[@]}"
echo

# 发行版
while :; do
    read -rp "请输入发行版名称（例如 debian / ubuntu / centos）: " DISTRO
    [[ -n $DISTRO ]] && break
done
DISTRO=${DISTRO,,}

# 版本号
read -rp "请输入版本号（留空使用最新版）: " RELEASE
[[ -z $RELEASE ]] && RELEASE=""

# Red Hat 特殊处理
if [[ $DISTRO == "redhat" ]]; then
    while [[ -z $REDHAT_IMG ]]; do
        read -rp "请输入 Red Hat qcow2 镜像直链: " REDHAT_IMG
    done
fi

#################### 3. 自动拉取 SSH 公钥 ####################
GITHUB_USER="LogicNekoChan"
echo -n "正在获取 GitHub 用户 $GITHUB_USER 的 SSH 公钥 … "
SSH_KEY=$(curl -fsSL "https://github.com/${GITHUB_USER}.keys" | head -n 1)
[[ -z $SSH_KEY ]] && { echo "获取失败，请检查网络或用户名"; exit 1; }
echo "OK"

#################### 4. 构造 reinstall.sh 参数 ####################
ARGS=("$DISTRO")
[[ -n $RELEASE ]] && ARGS+=("$RELEASE")
ARGS+=(--ssh-key "$SSH_KEY")          # 使用 GitHub 公钥
ARGS+=(--password "")                 # 关闭密码登录（空密码）

[[ -n $REDHAT_IMG ]] && ARGS+=(--img "$REDHAT_IMG")

#################### 5. 下载并调用真正的 reinstall.sh ####################
repo=$([ is_cn ] && echo "$CN_REPO" || echo "$GLOBAL_REPO")
if [[ ! -x reinstall.sh ]]; then
    curl -fsSL "$repo" -o reinstall.sh || wget -O reinstall.sh "$repo"
    chmod +x reinstall.sh
fi

echo
echo "即将执行：bash reinstall.sh ${ARGS[*]}"
read -rp "按回车继续，Ctrl+C 取消 …"

exec bash reinstall.sh "${ARGS[@]}"
