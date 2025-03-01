#!/bin/bash

# Cron 模块功能函数

# 获取当前的 Cron 任务
get_cron_jobs() {
    crontab -l 2>/dev/null
}

# 查看当前 Cron 任务
list_cron_jobs() {
    echo "==============================="
    echo "    当前的 Cron 任务列表       "
    echo "==============================="
    cron_jobs=$(get_cron_jobs)
    if [ -z "$cron_jobs" ]; then
        echo "当前没有任何 Cron 任务。"
    else
        echo "$cron_jobs" | nl  # 显示带行号的 Cron 任务
    fi
    pause
}

# 验证输入是否符合规则
validate_input() {
    local input_value
    local pattern="$1"
    local prompt="$2"

    while true; do
        read -p "$prompt" input_value
        if [[ "$input_value" =~ $pattern ]]; then
            echo "$input_value"
            return
        else
            echo "无效输入，请重新输入！"
        fi
    done
}

# 添加新任务
add_cron_job() {
    echo "==============================="
    echo "       添加 Cron 任务          "
    echo "==============================="
    
    # 交互式获取 Cron 时间参数
    minute=$(validate_input "^[0-5]?[0-9]$" "分钟 (0-59): ")
    hour=$(validate_input "^[0-1]?[0-9]$|^2[0-3]$" "小时 (0-23): ")
    day=$(validate_input "^([1-9]|[12][0-9]|3[01]|\*)$" "日期 (1-31, * 表示任意): ")
    month=$(validate_input "^([1-9]|1[0-2]|\*)$" "月份 (1-12, * 表示任意): ")
    week=$(validate_input "^[0-6]$|^\*$" "星期 (0-6, * 表示任意，0=星期天): ")

    read -p "请输入要执行的命令: " command
    if [[ -z "$command" ]]; then
        echo "命令不能为空！"
        pause
        return
    fi

    # 组合 Cron 任务
    cron_expr="$minute $hour $day $month $week $command"
    (crontab -l 2>/dev/null; echo "$cron_expr") | crontab -
    
    echo "新任务已添加：$cron_expr"
    pause
}

# 删除任务
delete_cron_job() {
    echo "==============================="
    echo "       删除 Cron 任务          "
    echo "==============================="

    cron_jobs=$(get_cron_jobs)
    if [ -z "$cron_jobs" ]; then
        echo "当前没有任何 Cron 任务。"
        pause
        return
    fi

    echo "$cron_jobs" | nl  # 显示带行号的任务列表
    read -p "请输入要删除的任务序号: " job_index

    if ! [[ "$job_index" =~ ^[0-9]+$ ]]; then
        echo "无效的序号，请重新输入！"
        pause
        return
    fi

    # 通过序号获取需要删除的任务
    job_to_remove=$(echo "$cron_jobs" | sed -n "${job_index}p" | sed 's/^[0-9]*[[:space:]]*//')

    if [[ -z "$job_to_remove" ]]; then
        echo "没有找到该任务。"
        pause
        return
    fi

    # 删除任务
    (crontab -l | grep -vF "$job_to_remove") | crontab -
    echo "任务已删除：$job_to_remove"
    pause
}

# Cron 任务管理菜单
cron_task_menu() {
    while true; do
        echo "==============================="
        echo "      Cron 任务管理菜单       "
        echo "==============================="
        echo "1. 查看当前 Cron 任务"
        echo "2. 添加新 Cron 任务"
        echo "3. 删除 Cron 任务"
        echo "4. 返回主菜单"
        echo "==============================="
        read -p "请选择一个选项 (1-4): " choice

        case $choice in
            1) list_cron_jobs ;;     # 查看当前 Cron 任务
            2) add_cron_job ;;       # 添加新任务
            3) delete_cron_job ;;    # 删除任务
            4) break ;;              # 返回主菜单
            *) echo "无效选项，请重试"; sleep 2 ;;
        esac
    done
}

# 暂停等待用户操作
pause() {
    read -p "按 Enter 键继续..."
}

# 运行菜单
cron_task_menu
