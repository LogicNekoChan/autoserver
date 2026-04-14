#!/usr/bin/env bash
# 交互式重装 Linux 助手 - 优化加固版
set -eEuo pipefail
trap 'echo -e "\n❌ 脚本异常退出！" >&2' ERR

###########################
# 1. 镜像源（国内/自动切换）
###########################
readonly CN_REPO="https://cnb.cool/bin456789/reinstall/-/raw/main/reinstall.sh"
readonly GLOBAL_REPO="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"

# 智能判断国内网络
is_cn_network() {
    curl -s --max-time 5 --retry 2 http://www.qualcomm.cn/cdn-cgi/trace 2>/dev/null | grep -q '^loc=CN'
}

###########################
# 2. 支持的系统版本（最新有效）
###########################
declare -A SUPPORTED_DISTRO=(
    [debian]="11|12"
    [ubuntu]="20.04|22.04|24.04|25.04"
    [alpine]="3.20|3.21|3.22"
    [centos]="9|10"
    [rocky]="8|9|10"
    [almalinux]="8|9|10"
    [oracle]="8|9"
    [fedora]="41|42"
    [openeuler]="22.03|24.03|25.03"
    [anolis]="8|23"
    [opencloudos]="9|23"
    [nixos]="25.05"
    [opensuse]="15.6|tumbleweed"
)

###########################
# 3. 交互式选择界面
###########################
clear
echo -e "\033[1;36m======================================\033[0m"
echo -e "\033[1;32m      交互式重装系统向导 优化版      \033[0m"
echo -e "\033[1;36m======================================\033[0m"

echo -e "\n\033[1;33m支持的发行版：\033[0m"
printf '%s\n' "${!SUPPORTED_DISTRO[@]}" | sort | paste -sd'  ' | fold -s -w 80
echo

# 选择发行版
while true; do
    read -rp "请输入发行版名称: " DISTRO
    DISTRO=${DISTRO,,}  # 转小写
    [[ -n "${SUPPORTED_DISTRO[$DISTRO]-}" ]] && break
    echo -e "\033[1;31m❌ 不支持该系统，请重新输入！\033[0m"
done

# 选择版本
echo -e "\n\033[1;32m${DISTRO} 支持版本：${SUPPORTED_DISTRO[$DISTRO]}\033[0m"
read -rp "请输入版本号（直接回车使用最新默认）: " RELEASE

###########################
# 4. 自动拉取 SSH 公钥（可修改用户名）
###########################
readonly GITHUB_USER="LogicNekoChan"
echo -e "\n\033[1;33m正在获取 GitHub 用户 ${GITHUB_USER} 的 SSH 公钥...\033[0m"

SSH_KEY=""
for i in {1..3}; do
    SSH_KEY=$(curl -fsSL --max-time 10 "https://github.com/${GITHUB_USER}.keys" 2>/dev/null | head -n1 || true)
    [[ -n "$SSH_KEY" ]] && break
    sleep 1
done

if [[ -z "$SSH_KEY" ]]; then
    echo -e "\033[1;31m❌ SSH 公钥获取失败，请检查网络！\033[0m"
    exit 1
fi
echo -e "\033[1;32m✅ SSH 公钥获取成功\033[0m"

###########################
# 5. 构造启动参数
###########################
ARGS=("$DISTRO")
[[ -n "$RELEASE" ]] && ARGS+=("$RELEASE")
ARGS+=(--ssh-key "$SSH_KEY")

# RedHat 自定义镜像（极少用，保留但更严谨）
if [[ "$DISTRO" == "redhat" ]]; then
    echo -e "\033[1;31m注意：RedHat 需要手动提供 qcow2 镜像直链\033[0m"
    while [[ -z "$REDHAT_IMG" ]]; do
        read -rp "请输入 Red Hat qcow2 镜像直链: " REDHAT_IMG
    done
    ARGS+=(--img "$REDHAT_IMG")
fi

###########################
# 6. 下载并执行重装脚本
###########################
echo -e "\n\033[1;36m正在选择最优下载源...\033[0m"
REPO_URL=$(is_cn_network && echo "$CN_REPO" || echo "$GLOBAL_REPO")

# 下载（curl/wget 自动兼容）
if [[ ! -x "reinstall.sh" ]]; then
    echo "下载重装脚本：$REPO_URL"
    if curl -fsSL --retry 2 "$REPO_URL" -o reinstall.sh; then
        :
    elif wget -q --tries=2 -O reinstall.sh "$REPO_URL"; then
        :
    else
        echo -e "\033[1;31m❌ 脚本下载失败！\033[0m"
        exit 1
    fi
    chmod +x reinstall.sh
fi

###########################
# 7. 最终确认 + 启动
###########################
echo -e "\n======================================"
echo -e "\033[1;31m⚠️  警告：即将重装系统，数据会全部清空！\033[0m"
echo -e "执行命令：bash reinstall.sh ${ARGS[*]}"
echo -e "======================================\n"

read -rp "按 回车键 继续，Ctrl+C 立即取消 … "

# 启动重装
exec bash reinstall.sh "${ARGS[@]}"
