#!/usr/bin/env bash
set -euo pipefail

# 引入所有功能模块（此处仅示例，可把真实模块按需 source）
# source ./lib/backup.sh
# source ./lib/restore.sh
# source ./lib/delete.sh
# source ./lib/deploy.sh

# 唯一需要 source 的子代码：负责打印菜单并返回用户选择
source "$(dirname "$0")/menu.sh"

main_loop() {
    while :; do
        # 调用子代码：清屏、打印菜单，并把用户选择带回
        local choice
        choice="$(show_menu_and_get_choice)"   # 获得 1-5 的数字

        case "$choice" in
            1) echo "执行 容器备份"   ;; # backup_system
            2) echo "执行 数据恢复"   ;; # restore_system
            3) echo "执行 容器删除"   ;; # delete_system
            4) echo "执行 部署容器"   ;; # deploy_containers
            5) echo "已退出"; exit 0 ;;
            *) echo "无效选择，请重试"; sleep 1 ;;
        esac
    done
}

main_loop "$@"
