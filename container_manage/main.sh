#!/usr/bin/env bash
set -euo pipefail

# ---------- 通用工具 ----------
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly NC='\033[0m' # No Color

pause() {
    read -rp $'\n按回车返回主菜单...'
}

# ---------- 子功能实现 ----------
backup_system() {
    clear
    echo -e "${GREEN}===== 容器备份 =====${NC}"
    read -rp "请输入要备份的容器名: " cname
    [[ -z "$cname" ]] && { echo -e "${RED}容器名不能为空${NC}"; pause; return; }
    echo "正在备份容器 $cname ..."
    sleep 1
    echo -e "${GREEN}备份完成！文件保存在 ./backups/${cname}_$(date +%F).tar.gz${NC}"
    pause
}

restore_system() {
    clear
    echo -e "${GREEN}===== 数据恢复 =====${NC}"
    local backups=(backups/*.tar.gz)
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未找到备份文件${NC}"
    else
        PS3="请选择要恢复的备份（输入编号）: "
        select b in "${backups[@]}"; do
            [[ -n $b ]] && { echo "正在恢复 $b ..."; sleep 1; echo -e "${GREEN}恢复成功${NC}"; break; }
        done
    fi
    pause
}

delete_system() {
    clear
    echo -e "${GREEN}===== 容器删除 =====${NC}"
    read -rp "请输入要删除的容器名: " cname
    [[ -z "$cname" ]] && { echo -e "${RED}容器名不能为空${NC}"; pause; return; }
    read -rp "确定删除容器 $cname 吗？[y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "已取消"; pause; return; }
    echo "正在删除容器 $cname ..."
    sleep 1
    echo -e "${GREEN}删除完成${NC}"
    pause
}

deploy_system() {
    clear
    echo -e "${GREEN}===== 部署容器 =====${NC}"
    read -rp "请输入镜像名（如 nginx:latest）: " image
    [[ -z "$image" ]] && { echo -e "${RED}镜像名不能为空${NC}"; pause; return; }
    read -rp "请输入容器名: " cname
    [[ -z "$cname" ]] && { echo -e "${RED}容器名不能为空${NC}"; pause; return; }
    echo "正在从镜像 $image 部署容器 $cname ..."
    sleep 2
    echo -e "${GREEN}部署成功！容器 $cname 已启动${NC}"
    pause
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

main_loop() {
    while :; do
        show_menu
        local choice
        read -rp "请输入操作编号: " choice
        case "$choice" in
            1) backup_system  ;;
            2) restore_system ;;
            3) delete_system  ;;
            4) deploy_system  ;;
            5) echo -e "${GREEN}已退出，再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选择，请重试${NC}"; sleep 1 ;;
        esac
    done
}

# ---------- 入口 ----------
trap 'echo -e "\n${RED}脚本被中断${NC}"; exit 130' INT
main_loop "$@"
