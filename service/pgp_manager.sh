#!/usr/bin/env bash
# pgp_mini_v2.sh  服务器 GPG 最小管理工具（带流式 tar+加密/解密）
set -euo pipefail

R=$'\033[0;31m';G=$'\033[0;32m';Y=$'\033[1;33m';B=$'\033[1;34m';N=$'\033[0m'

########  公钥列表 -> 序号菜单  ########
# 返回 0 且 stdout = KeyID；1 = 无钥
pick_key(){
  local line n=1 uid kid out IFS=$'\t'
  echo -e "${Y}=== 选择接收方公钥 ===${N}"
  gpg --list-keys --keyid-format LONG --with-colons |
  awk -F: '$1=="pub"{kid=$5} $1=="uid"{printf "%d\t%s\t%s\n",nr++,$10,kid}' nr=1 > /tmp/k$$
  [[ -s /tmp/k$$ ]] || { echo -e "${R}本地无公钥！${N}"; return 1; }
  while read -r n uid kid; do
    printf "%2d  %-30s  %s\n" "$n" "$uid" "$kid"
  done </tmp/k$$
  read -p "序号: " idx
  out=$(awk -F'\t' -v v="$idx" '$1==v{print $3}' /tmp/k$$)
  rm -f /tmp/k$$
  [[ -n $out ]] && { echo "$out"; return 0; } ||
    { echo -e "${R}无效序号${N}"; return 1; }
}

########  导入  ########
import_key(){
  local f
  read -p "密钥文件路径: " f
  [[ -f $f ]] && gpg --import "$f" &&
    echo -e "${G}导入完成${N}" ||
    echo -e "${R}文件不存在${N}"
}

########  删除  ########
delete_key(){
  local kid t
  kid=$(pick_key) || return 1
  read -p "删除公钥(1) / 私钥(2) / 全部(3): " t
  case $t in
    1) gpg --delete-keys "$kid" ;;
    2) gpg --delete-secret-keys "$kid" ;;
    3) gpg --delete-secret-keys "$kid"; gpg --delete-keys "$kid" ;;
    *) echo -e "${R}无效选择${N}" ;;
  esac
}

########  流式加密（tar+cz+GPG）  ########
enc_tar(){
  local src=$1 kid dst
  [[ -e $src ]] || { echo -e "${R}路径不存在${N}"; return 1; }
  kid=$(pick_key) || return 1
  dst="${src%/}.tar.gz.gpg"          # 去掉末尾/再拼后缀
  echo -e "${Y}正在压缩+加密 → ${dst}${N}"
  # 核心：tar 相对路径打包，管道给 gpg
  tar -czf - -C "$(dirname "$src")" "$(basename "$src")" |
    gpg --encrypt --recipient "$kid" --output "$dst"
  echo -e "${G}完成！加密包：${dst}${N}"
}

########  流式解密（GPG+tar+xz）  ########
dec_tar(){
  local enc=$1 dst_dir
  [[ -f $enc" ]] || { echo -e "${R}文件不存在${N}"; return 1; }
  # 默认解压到同目录，也可手动输入
  dst_dir=$(dirname "$enc")
  read -p "解压到目录（默认：${dst_dir}）： " ans
  [[ -n $ans ]] && dst_dir="$ans"
  [[ -d $dst_dir ]] || mkdir -p "$dst_dir"
  echo -e "${Y}正在解密+解压 ...${N}"
  gpg --decrypt "$enc" | tar -xzf - -C "$dst_dir"
  echo -e "${G}完成！已解压到：${dst_dir}${N}"
}

########  原有单文件加解密（保留）  ########
enc(){
  local src=$1 dst kid
  [[ -d $src ]] && { tar -czf "${src}.tar.gz" -C "$(dirname "$src")" "$(basename "$src")"; src="${src}.tar.gz"; }
  kid=$(pick_key) || return 1
  dst="${src}.gpg"
  gpg --encrypt --recipient "$kid" --output "$dst" "$src" &&
  echo -e "${G}加密完成 → $dst${N}"
}

dec(){
  local enc=$1 out="${enc%.gpg}"
  gpg --decrypt --output "$out" "$enc" &&
  if [[ $out == *.tar.gz ]]; then
    tar -xzf "$out" -C "$(dirname "$out")" && rm -f "$out"
    echo -e "${G}解密并解压完成 → $(dirname "$out")${N}"
  else
    echo -e "${G}解密完成 → $out${N}"
  fi
}

########  主菜单  ########
while :; do
  echo -e "\n${B}=== GPG 小工具 v2（tar 流式加/解密） ===${N}"
  echo "1) 列出密钥      2) 导入密钥      3) 删除密钥"
  echo "4) 加密文件      5) 解密文件"
  echo "6) tar+加密目录  7) tar+解密.gpg  8) 退出"
  read -p "选: " c
  case $c in
    1) gpg --list-keys --keyid-format LONG; gpg --list-secret-keys --keyid-format LONG ;;
    2) import_key ;;
    3) delete_key ;;
    4) read -p "路径: " p; [[ -e $p ]] && enc "$p" || echo -e "${R}路径不存在${N}" ;;
    5) read -p "*.gpg 路径: " p; [[ -f $p ]] && dec "$p" || echo -e "${R}文件不存在${N}" ;;
    6) read -p "目录路径: " p; [[ -e $p ]] && enc_tar "$p" || echo -e "${R}目录不存在${N}" ;;
    7) read -p "*.tar.gz.gpg 路径: " p; [[ -f $p ]] && dec_tar "$p" || echo -e "${R}文件不存在${N}" ;;
    8) echo -e "${G}Bye~${N}"; exit 0 ;;
    *) echo -e "${R}无效选择${N}" ;;
  esac
done
