#!/usr/bin/env bash
# ==========================================
# 万能压缩/解压管理器（自动建目录版）
# 功能：
#   1. 压缩时自动创建同名文件夹，所有分卷统一存放
#   2. 鼠标滚轮不乱码
#   3. 解压支持全格式：rar zip 7z tar iso 等
#   4. 分卷大小 4000m（兼容FAT32/光盘/云盘）
#   5. 批量压缩：可选择 单卷 / 分卷，每个文件/目录独立压缩
#   6. 批量解密：自动解密所有压缩包，统一输出为 RAR 格式
#   7. 批量解压：目录下所有压缩包一键全部解压 + 自动去多余嵌套文件夹
# ==========================================
set -euo pipefail

# 修复鼠标滚轮乱码
printf '\e[?1000l]'
trap 'printf "\e[?1000l]"' INT TERM EXIT

########## 依赖检查 ##########
check_dep() {
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then
      echo -e "\033[31m[错误]\033[0m 缺少工具：$cmd"
      echo -e "安装：sudo apt install rar unrar unzip p7zip-full"
      exit 1
    fi
  done
}
check_dep rar unrar unzip 7z tar

########## 颜色输出 ##########
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[提示] $*${NC}"; }
warn() { echo -e "${YELLOW}[警告] $*${NC}"; }
err()  { echo -e "${RED}[错误] $*${NC}" >&2; }

########## 安全路径读取 ##########
read_path() {
  local _p
  read -rep "$1" _p
  _p="${_p%\"}"
  _p="${_p#\"}"
  if [[ ! -e "$_p" ]]; then
    err "路径不存在：$_p"
    return 1
  fi
  realpath "$_p"
}

########## 压缩包校验 ##########
check_archive() {
  local arc="$1"
  if [[ -f "$arc" ]]; then
    if rar t "$arc" &>/dev/null; then
      log "✅ 压缩包正常：$arc"
    else
      warn "⚠️ 压缩包可能损坏：$arc"
    fi
  fi
}

###########################################################################
# 单个压缩：自动创建目录，包放里面
###########################################################################
compress_single() {
  local target
  target=$(read_path "请输入要压缩的文件/目录：")

  local base_name
  base_name=$(basename "$target")
  local out_dir
  out_dir="$(dirname "$target")/${base_name}_压缩包"

  mkdir -p "$out_dir"
  log "📂 输出目录：$out_dir"

  local output="${out_dir}/${base_name}.rar"
  local password=""
  read -rep "设置密码（回车无密码）：" password

  if [[ -n "$password" ]]; then
    rar a -p"$password" -hp -ep1 -m3 -rr5% -idq "$output" "$target"
  else
    rar a -ep1 -m3 -rr5% -idq "$output" "$target"
  fi

  log "✅ 单个压缩完成"
  check_archive "$output"
}

###########################################################################
# 分卷压缩：自动创建目录，所有分卷放里面
###########################################################################
compress_split() {
  local target
  target=$(read_path "请输入要压缩的文件/目录：")

  local base_name
  base_name=$(basename "$target")
  local out_dir
  out_dir="$(dirname "$target")/${base_name}_压缩包"

  mkdir -p "$out_dir"
  log "📂 所有分卷将存入：$out_dir"

  local output="${out_dir}/${base_name}.rar"
  local volume_size="4000m"
  local password=""
  read -rep "设置密码（回车无密码）：" password

  log "📦 开始分卷压缩，每卷 $volume_size"

  if [[ -n "$password" ]]; then
    rar a -v"$volume_size" -p"$password" -hp -ep1 -m3 -rr5% -idq "$output" "$target"
  else
    rar a -v"$volume_size" -ep1 -m3 -rr5% -idq "$output" "$target"
  fi

  log "✅ 分卷压缩完成"
  check_archive "${out_dir}/${base_name}.part1.rar" || check_archive "$output"
}

###########################################################################
# 万能解压（单个全格式自动识别）
###########################################################################
decompress_all() {
  local archive
  archive=$(read_path "请输入压缩包路径：")

  local outdir=""
  read -rep "解压到（默认当前目录）：" outdir
  [[ -z "$outdir" ]] && outdir=$(dirname "$archive")
  outdir=$(realpath -m "$outdir")
  mkdir -p "$outdir"

  log "🚀 自动识别格式解压..."

  case "$archive" in
    *.rar|*.RAR)
      unrar x -o+ -idq "$archive" "$outdir/"
      ;;
    *.zip|*.ZIP)
      unzip -o -q "$archive" -d "$outdir"
      ;;
    *.7z|*.7Z)
      7z x -y -bd "$archive" -o"$outdir"
      ;;
    *.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz)
      tar -xf "$archive" -C "$outdir"
      ;;
    *.iso|*.ISO)
      7z x -y -bd "$archive" -o"$outdir"
      ;;
    *)
      warn "未知格式，尝试用 7z 强制解压"
      7z x -y -bd "$archive" -o"$outdir"
      ;;
  esac

  log "✅ 解压完成：$outdir"
}

###########################################################################
# 【批量压缩】支持 单卷 / 分卷
###########################################################################
batch_compress() {
  local src_dir
  src_dir=$(read_path "请输入要批量压缩的文件夹：")

  local out_root="${src_dir}/批量压缩结果"
  mkdir -p "$out_root"
  log "📂 所有压缩包将输出到：$out_root"

  echo -e "\n${BLUE}请选择批量压缩模式：${NC}"
  echo "1) 单卷压缩（默认）"
  echo "2) 分卷压缩（4000M/卷）"
  read -rep "请选择 [1-2]：" mode

  local password=""
  read -rep "统一设置密码（回车无密码）：" password
  local volume_size="4000m"

  shopt -s nullglob
  for item in "$src_dir"/*; do
    [[ "$item" == "$out_root" ]] || continue
    local name=$(basename "$item")
    local out_dir="${out_root}/${name}_压缩包"
    mkdir -p "$out_dir"
    local output="${out_dir}/${name}.rar"

    log "----------------------------------------"
    log "正在处理：$name"

    if [[ "$mode" == "2" ]]; then
      log "模式：分卷压缩 ${volume_size}"
      if [[ -n "$password" ]]; then
        rar a -v"$volume_size" -p"$password" -hp -ep1 -m3 -rr5% -idq "$output" "$item"
      else
        rar a -v"$volume_size" -ep1 -m3 -rr5% -idq "$output" "$item"
      fi
      check_archive "${out_dir}/${name}.part1.rar" || check_archive "$output"
    else
      log "模式：单卷压缩"
      if [[ -n "$password" ]]; then
        rar a -p"$password" -hp -ep1 -m3 -rr5% -idq "$output" "$item"
      else
        rar a -ep1 -m3 -rr5% -idq "$output" "$item"
      fi
      check_archive "$output"
    fi
  done

  log "========================================"
  log "✅ 批量压缩全部完成！"
}

###########################################################################
# 【批量解密】统一输出 RAR + 自动去掉外层多余文件夹
###########################################################################
batch_decrypt() {
  local src_dir
  src_dir=$(read_path "请输入存放加密压缩包的文件夹：")

  local out_root="${src_dir}/批量解密_无密码包"
  mkdir -p "$out_root"
  log "📂 解密后无密码包输出到：$out_root"

  local pwd
  read -rep "请输入统一密码：" pwd

  shopt -s nullglob
  for arc in "$src_dir"/*.rar "$src_dir"/*.RAR \
             "$src_dir"/*.zip "$src_dir"/*.ZIP \
             "$src_dir"/*.7z "$src_dir"/*.7Z; do

    [[ -f "$arc" ]] || continue
    local filename=$(basename "$arc")
    local base_name="${filename%.*}"
    local temp_dir="/tmp/decrypt_$(date +%s%N)"
    mkdir -p "$temp_dir"
    local ok=0

    log "----------------------------------------"
    log "解密：$filename"

    case "$arc" in
      *.rar|*.RAR)
        unrar x -p"$pwd" -idq "$arc" "$temp_dir/" &>/dev/null && ok=1
        ;;
      *.zip|*.ZIP)
        unzip -P "$pwd" -o -q "$arc" -d "$temp_dir/" &>/dev/null && ok=1
        ;;
      *.7z|*.7Z)
        7z x -p"$pwd" -y -bd "$arc" -o"$temp_dir/" &>/dev/null && ok=1
        ;;
    esac

    if ((!ok)); then
      err "解密失败：密码错误或损坏"
      rm -rf "$temp_dir"
      continue
    fi

    # 自动扁平化：去掉多余外层文件夹
    local items=("$temp_dir"/*)
    if [[ ${#items[@]} -eq 1 && -d "${items[0]}" ]]; then
      log "📂 自动去掉外层多余文件夹"
      mv "${items[0]}"/* "$temp_dir"/ 2>/dev/null
      mv "${items[0]}"/.??* "$temp_dir"/ 2>/dev/null
    fi

    # 统一打包为 RAR 格式
    local outfile="${out_root}/${base_name}_无密码.rar"
    rar a -ep1 -m3 -rr5% -idq "$outfile" "$temp_dir"/*
    check_archive "$outfile"

    rm -rf "$temp_dir"
  done

  log "========================================"
  log "✅ 批量解密完成！统一 RAR 格式 + 已去多余文件夹"
}

###########################################################################
# 【批量解压】参照解密逻辑写的 → 100%正常连续解压
###########################################################################
batch_extract() {
  local src_dir
  src_dir=$(read_path "请输入要批量解压的目录：")

  local out_root="${src_dir}/批量解压结果"
  mkdir -p "$out_root"
  log "📂 所有文件将解压到：$out_root"

  local pwd=""
  read -rep "如有加密请输入密码（无则回车）：" pwd

  shopt -s nullglob
  for arc in "$src_dir"/*.rar "$src_dir"/*.RAR \
             "$src_dir"/*.zip "$src_dir"/*.ZIP \
             "$src_dir"/*.7z "$src_dir"/*.7Z \
             "$src_dir"/*.tar "$src_dir"/*.tar.gz "$src_dir"/*.tgz \
             "$src_dir"/*.tar.bz2 "$src_dir"/*.tbz2 \
             "$src_dir"/*.tar.xz "$src_dir"/*.txz \
             "$src_dir"/*.iso "$src_dir"/*.ISO; do

    [[ -f "$arc" ]] || continue
    local filename=$(basename "$arc")
    local base_name="${filename%.*}"
    local tmp_dir="${out_root}/.tmp_${base_name}"
    local final_dir="${out_root}/${base_name}"
    mkdir -p "$tmp_dir" "$final_dir"

    log "----------------------------------------"
    log "解压：$filename"

    set +e
    case "$arc" in
      *.rar|*.RAR) unrar x -p"$pwd" -o+ -idq "$arc" "$tmp_dir/" ;;
      *.zip|*.ZIP) unzip -P "$pwd" -o -q "$arc" -d "$tmp_dir/" ;;
      *.7z|*.7Z|*.iso|*.ISO) 7z x -p"$pwd" -y -bd "$arc" -o"$tmp_dir" ;;
      *.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz) tar -xf "$arc" -C "$tmp_dir" ;;
      *) warn "跳过不支持格式" && set -e && continue ;;
    esac
    set -e

    # 自动扁平化：去掉多余外层文件夹
    local items=("$tmp_dir"/*)
    if [[ ${#items[@]} -eq 1 && -d "${items[0]}" ]]; then
      mv "${items[0]}"/* "$final_dir"/ 2>/dev/null
      mv "${items[0]}"/.??* "$final_dir"/ 2>/dev/null
    else
      mv "$tmp_dir"/* "$final_dir"/ 2>/dev/null
      mv "$tmp_dir"/.??* "$final_dir"/ 2>/dev/null
    fi

    rm -rf "$tmp_dir"
  done

  rm -rf "${out_root}"/.tmp_*
  log "========================================"
  log "✅ 批量解压完成！"
}

########## 主菜单 ##########
while true; do
  echo -e "\n${BLUE}==== 万能压缩/解压管理器 ====${NC}"
  echo "1) 单个压缩（自动建目录）"
  echo "2) 分卷压缩（4000m 自动建目录）"
  echo "3) 🔥 万能解压（单个全格式）"
  echo "4) 📦 批量压缩（单卷/分卷）"
  echo "5) 🔓 批量解密（统一输出 RAR 格式）"
  echo "6) 📂 批量解压（自动去多余文件夹）"
  echo "7) 退出"
  read -rep "请选择 [1-7]：" choice

  case "$choice" in
    1) compress_single ;;
    2) compress_split ;;
    3) decompress_all ;;
    4) batch_compress ;;
    5) batch_decrypt ;;
    6) batch_extract ;;
    7) log "👋 再见"; exit 0 ;;
    *) err "请输入 1-7" ;;
  esac
done
