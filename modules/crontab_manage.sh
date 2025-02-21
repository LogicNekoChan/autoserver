#!/bin/bash
# Crontab 任务管理模块

function list_crontab() {
    crontab -l 2>/dev/null || echo "当前无 Crontab 任务"
}

function add_crontab_task() {
    read -p "请输入定时表达式（例如：*/5 * * * *）： " schedule
    read -p "请输入需要执行的命令： " command
    (crontab -l 2>/dev/null; echo "$schedule $command") | crontab -
    echo "任务已添加。"
}

function delete_crontab_task() {
    echo "当前 Crontab 任务："
    crontab -l | nl
    read -p "请输入需要删除任务的行号： " line
    # 将原 crontab 文件保存并过滤掉指定行，再导入新任务
    tmp=$(mktemp)
    crontab -l | sed "${line}d" > "$tmp"
    crontab "$tmp"
    rm -f "$tmp"
    echo "任务已删除。"
}

echo "======== Crontab 管理 ========"
echo "1. 查看任务"
echo "2. 添加任务"
echo "3. 删除任务"
read -p "请选择操作: " option
case "$option" in
    1) list_crontab ;;
    2) add_crontab_task ;;
    3) delete_crontab_task ;;
    *) echo "[ERROR] 无效选择！" ;;
esac
