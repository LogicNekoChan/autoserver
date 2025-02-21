#!/bin/bash
# 公共函数库

# 彩色输出
function echo_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

function echo_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

# 检测操作系统类型
function detect_os() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    else
        echo "unknown"
    fi
}
