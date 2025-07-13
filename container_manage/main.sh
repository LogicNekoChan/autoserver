#!/usr/bin/env bash
set -euo pipefail

# ---------- 路径 ----------
readonly LIB_DIR="/root/autoserver/container_manage/lib"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

# ---------- 通用函数 ----------
pause() {
    read -rp $'\n按回车返回主菜单...'
}

# ---------- 主菜单 ----------
show_menu() {
    clear
    cat <<EOF
Docker 容器管理套件
--------------------------------
1) 容器备份
2) 数据恢复
3) 容器删除
4) 部署容器
5) 退出
--------------------------------
EOF
}

# ---------- 主循环 ----------
main_loop() {
    while :; do
        show_menu
        local choice
        read -rp "请输入操作编号: " choice

        case "$choice" in
            1) bash "$LIB_DIR/backup.sh"   ;;
            2) bash "$LIB_DIR/restore.sh"  ;;
            3) bash "$LIB_DIR/delete.sh"   ;;
            4) bash "$LIB_DIR/deploy.sh"   ;;
            5) echo -e "${GREEN}已退出，再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选择，请重试${NC}"; sleep 1 ;;
        esac
    done
}

# ---------- 入口 ----------
trap 'echo -e "\n${RED}脚本被中断${NC}"; exit 130' INT
main_loop "$@"
