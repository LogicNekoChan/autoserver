#!/usr/bin/env bash
# pgp_mini.sh  服务器 GPG 最小管理工具  老 Bash 兼容
set -euo pipefail

R=$'\033[0;31m';G=$'\033[0;32m';Y=$'\033[1;33m';B=$'\033[1;34m';N=$'\033[0m'

########  公钥列表 -> 序号菜单  ########
# 返回 0 且 stdout = KeyID；1 = 无钥
pick_key(){
  local line n=1 uid kid out IFS=$'\t'
  echo -e "${Y}=== 选择接收方公钥 ===${N}"
  # 一行一个: 序号<tab>UID<tab>KeyID   （顺序别改）
  gpg --list-keys --keyid-format LONG --with-colons |
  awk -F: '$1=="pub"{kid=$5} $1=="uid"{printf "%d\t%s\t%s\n",nr++,$10,kid}' nr=1 > /tmp/k$$
  [[ -s /tmp/k$$ ]] || { echo -e "${R}本地无公钥！${N}"; return 1; }
  while read -r n uid kid; do          # 顺序对应：序号 UID KeyID
    printf "%2d  %-30s  %s\n" "$n" "$uid" "$kid"
  done </tmp/k$$
  read -p "序号: " idx
  out=$(awk -F'\t' -v v="$idx" '$1==v{print $3}' /tmp/k$$)   # $3 才是 KeyID
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

########  加密  ########
enc(){
  local src=$1 dst kid
  [[ -d $src ]] && { tar -czf "${src}.tar.gz" -C "$(dirname "$src")" "$(basename "$src")"; src="${src}.tar.gz"; }
  kid=$(pick_key) || return 1
  dst="${src}.gpg"
  gpg --encrypt --recipient "$kid" --output "$dst" "$src" &&
  echo -e "${G}加密完成 → $dst${N}"
}

########  解密  ########
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
  echo -e "\n${B}=== GPG 小工具 ===${N}"
  echo "1) 列出密钥   2) 导入密钥   3) 删除密钥"
  echo "4) 加密文件   5) 解密文件   6) 退出"
  read -p "选: " c
  case $c in
    1) gpg --list-keys --keyid-format LONG; gpg --list-secret-keys --keyid-format LONG;;
    2) import_key;;
    3) delete_key;;
    4) read -p "路径: " p; [[ -e $p ]] && enc "$p" || echo -e "${R}路径不存在${N}";;
    5) read -p "*.gpg 路径: " p; [[ -f $p ]] && dec "$p" || echo -e "${R}文件不存在${N}";;
    6) echo -e "${G}Bye~${N}"; exit 0;;
    *) echo -e "${R}无效选择${N}";;
  esac
done
