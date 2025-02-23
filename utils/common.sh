#!/bin/bash
# 公共函数库

# 输出信息
function echo_info() {
    echo "[INFO] $1"
}

# 输出错误信息
function echo_error() {
    echo "[ERROR] $1"
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

# 判断命令是否存在
function command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 获取系统的内存总量（MB）
function get_total_memory() {
    if [[ -f /proc/meminfo ]]; then
        grep MemTotal /proc/meminfo | awk '{print $2 / 1024 " MB"}'
    else
        echo "无法获取内存信息"
    fi
}

# 获取系统的硬盘总量（GB）
function get_total_disk() {
    df -h --total | grep total | awk '{print $2}'
}

# 检查网络连接
function check_network_connection() {
    local host="$1"
    ping -c 1 "$host" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "网络连接正常"
    else
        echo "无法连接到 $host"
    fi
}
