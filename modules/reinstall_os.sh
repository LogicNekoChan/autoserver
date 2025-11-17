#!/usr/bin/env bash
# 5_reinstall.sh  – 交互式重装 Linux（Linux Only）
set -eE
set -o pipefail

#################### 1. 镜像源 ####################
CN_REPO="https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh"
GLOBAL_REPO="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"

is_cn() {
    curl -s --retry 3 http://www.qualcomm.cn/cdn-cgi/trace | grep -q '^loc=CN'
}

#################### 2. 发行版列表 ####################
declare -A MAP=(
    [anolis]="7|8|23"
    [opencloudos]="8|9|23"
    [rocky]="8|9|10"
    [oracle]="8|9"
    [almalinux]="8|9|10"
    [centos]="9|10"
    [fedora]="41|42"
    [nixos]="25.05"
    [debian]="9|10|11|12"
    [opensuse]="15.6|tumbleweed"
    [alpine]="3.19|3.20|3.21|3.22"
    [openeuler]="20.03|22.03|24.03|25.03"
    [ubuntu]="16.04|18.04|20.04|22.04|24.04|25.04"
)

#################### 3. 交互式选择 ####################
echo "======================================"
echo "      交互式重装系统向导              "
echo "======================================"

echo "可选发行版："
printf '%s\n' "${!MAP[@]}" | sort | paste -sd'  ' | fold -s -w 80
echo

read -rp "请选择发行版名称: " DISTRO
DISTRO=${DISTRO,,}
[[ -z ${MAP[$DISTRO]} ]] && { echo "不支持的发行版！"; exit 1; }

# 版本号
if [[ -n ${MAP[$DISTRO]} ]]; then
    echo "${DISTRO} 可选版本：${MAP[$DISTRO]}"
    read -rp "请输入版本号（留空使用最新）: " RELEASE
    [[ -z $RELEASE ]] && RELEASE=""
else
    RELEASE=""
fi

# Red Hat 镜像
REDHAT_IMG=""
if [[ $DISTRO == "redhat" ]]; then
    while [[ -z $REDHAT_IMG ]]; do
        read -rp "请输入 Red Hat qcow2 镜像直链: " REDHAT_IMG
    done
fi

#################### 4. 默认配置 ####################
GITHUB_USER="LogicNekoChan"
echo -n "自动获取 GitHub 用户 $GITHUB_USER 的 SSH 公钥 … "
SSH_KEY=$(curl -fsSL "https://github.com/${GITHUB_USER}.keys" | head -n1)
[[ -z $SSH_KEY ]] && { echo "失败"; exit 1; }
echo "OK"

#################### 5. 构造 reinstall.sh 参数 ####################
BUILD_ARGS=("$DISTRO")
[[ -n $RELEASE ]] && BUILD_ARGS+=("$RELEASE")
BUILD_ARGS+=(--ssh-key "$SSH_KEY")
[[ -n $REDHAT_IMG ]] && BUILD_ARGS+=(--img "$REDHAT_IMG")

#################### 6. 下载并启动 ####################
repo=$($is_cn && echo "$CN_REPO" || echo "$GLOBAL_REPO")
[[ ! -x reinstall.sh ]] && {
    curl -fsSL "$repo" -o reinstall.sh || wget -O reinstall.sh "$repo"
    chmod +x reinstall.sh
}

echo
echo "即将执行：bash reinstall.sh ${BUILD_ARGS[*]}"
read -rp "按回车继续，Ctrl+C 取消 …"

exec bash reinstall.sh "${BUILD_ARGS[@]}"
