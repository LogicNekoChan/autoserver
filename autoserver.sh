#!/bin/bash

# 必须使用 root 用户运行
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以 root 用户权限运行。"
    echo "请使用 'sudo -i' 切换为 root 用户后再执行，或使用 root 账户登录。"
    exit 1
fi

# 设置仓库地址
REPO_URL="https://github.com/LogicNekoChan/autoserver.git"

# 设置目标文件夹路径
TARGET_DIR="/root/autoserver"

# 检测并安装 git（不使用 sudo）
if ! command -v git &>/dev/null; then
    echo "git 未安装，正在尝试安装 git..."
    if apt update >/dev/null 2>&1 && apt install -y git >/dev/null 2>&1; then
        echo "git 安装成功"
    else
        echo "错误：git 安装失败，请手动安装后重试"
        exit 1
    fi
else
    echo "git 已安装"
fi

# 切换到 root 用户的根目录
cd /root || { echo "无法切换到 /root 目录"; exit 1; }

# 删除旧目录（如果存在）
if [ -d "$TARGET_DIR" ]; then
    echo "发现旧目录 $TARGET_DIR，正在删除..."
    rm -rf "$TARGET_DIR" || { echo "目录删除失败"; exit 1; }
fi

# 克隆仓库
echo "正在克隆仓库到 $TARGET_DIR..."
if git clone "$REPO_URL" "$TARGET_DIR" >/dev/null 2>&1; then
    echo "仓库克隆成功"
else
    echo "错误：仓库克隆失败，请检查网络连接和仓库地址"
    exit 1
fi

# 设置目录权限（确保所有者为 root）
echo "设置目录权限..."
chmod -R 777 "$TARGET_DIR" && chown -R root:root "$TARGET_DIR" || {
    echo "权限设置失败"
    exit 1
}

# 执行主脚本
echo "正在启动主程序..."
cd "$TARGET_DIR" || { echo "无法进入 $TARGET_DIR 目录"; exit 1; }

if [ -f "main.sh" ]; then
    chmod +x main.sh && ./main.sh
else
    echo "错误：未找到 main.sh 文件"
    exit 1
fi
