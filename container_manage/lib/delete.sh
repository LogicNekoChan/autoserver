graceful_stop() {
    local cid=$1
    log "停止容器: $cid"
    docker stop "$cid" >/dev/null 2>&1 || docker kill "$cid" >/dev/null || die "无法停止 $cid"
}

safe_clean_mounts() {
    local cid=$1
    local mounts
    mapfile -t mounts < <(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{end}}{{end}}' "$cid")
    for m in "${mounts[@]}"; do
        [[ -d $m ]] || continue
        if mountpoint -q "$m"; then umount "$m" 2>/dev/null || log "无法卸载: $m"; fi
        rm -rf "$m" && log "已清理目录: $m" || log "警告: 无法删除 $m"
    done
}

delete_named_volumes() {
    local cid=$1
    local volumes
    mapfile -t volumes < <(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$cid")
    for v in "${volumes[@]}"; do
        [[ -n $v ]] || continue
        docker volume rm "$v" 2>/dev/null && log "已删除卷: $v" || log "卷 $v 仍被占用，跳过"
    done
}

delete_system() {
    local containers=($(docker ps -a --format '{{.Names}}'))
    [[ ${#containers[@]} -eq 0 ]] && die "没有可删除的容器"

    echo "选择要删除的容器："
    for i in "${!containers[@]}"; do
        printf "%3d) %s\n" $((i+1)) "${containers[i]}"
    done

    local choice
    read -rp "请输入编号 [1-${#containers[@]}]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#containers[@]} )) || die "无效编号"
    local target="${containers[$((choice-1))]}"

    read -rp "确认删除 $target 及其所有数据？[y/N] " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { echo "已取消"; return; }

    graceful_stop "$target"
    safe_clean_mounts "$target"
    delete_named_volumes "$target"
    docker rm -f "$target" >/dev/null && log "已删除容器: $target" && echo -e "\n[√] 删除成功"
}
