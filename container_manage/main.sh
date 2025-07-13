#!/usr/bin/env bash
set -euo pipefail

# ---------- 功能模块按需 source ----------
# 假设四个模块放在同目录的 lib/ 里
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/restore.sh"
source "$SCRIPT_DIR/lib/delete.sh"
source "$SCRIPT_DIR/lib/deploy.sh"

# ---------- 主菜单（原 menu.sh 内容内嵌） ----------
show_menu_and_get_choice() {
    clear
    cat <<'EOF'

Docker 容器管理套件
--------------------------------
1) 容器备份
2) 数据恢复
3) 容器删除
4) 部署容器
5) 退出
--------------------------------
EOF
    local choice
    read -rp "请输入操作编号: " choice
    printf '%s\n' "$choice"
}

# ---------- 主循环 ----------
main_loop() {
    while :; do
        local choice
        choice="$(show_menu_and_get_choice)"

        case "$choice" in
            1) backup_system   ;;
            2) restore_system  ;;
            3) delete_system   ;;
            4) deploy_system   ;;
            5) echo "已退出"; exit 0 ;;
            *) echo "无效选择，请重试"; sleep 1 ;;
        esac
    done
}

# ---------- 入口 ----------
main_loop "$@"
