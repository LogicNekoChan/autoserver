#!/usr/bin/env bash
# pgp_manager.sh  Ubuntu Server 本地 PGP 管理  老 Bash 兼容版
set -euo pipefail

command -v gpg >/dev/null || { echo "安装 gnupg"; exit 1; }
command -v tar >/dev/null || { echo "安装 tar";  exit 1; }

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[1;34m'; NC=$'\033[0m'

######## 列出钥匙 ########
list_keys(){
  echo -e "\n${BLUE}=== 本地公钥 ===${NC}"
  gpg --list-keys --keyid-format LONG
  echo -e "\n${GREEN}=== 本地私钥 ===${NC}"
  gpg --list-secret-keys --keyid-format LONG
}

######## 选钥匙 ########
select_keys(){
  local prompt="$1" raw idx=1
  # 直接让 gpg 打印“序号<tab>KeyID<tab>UID”，一行一个
  raw=$(gpg --list-keys --keyid-format LONG --with-colons |
        awk -F: '$1=="pub"{kid=$5}
                $1=="uid"{printf "%d\t%s\t%s\n",idx++,kid,$10}' idx=1)
  [[ -z $raw ]] && { echo -e "${RED}本地没有公钥！${NC}"; return 1; }

  echo -e "${YELLOW}${prompt}${NC}"
  printf "%2s  %-35s  %s\n" "序号" "UID" "KeyID"
  echo "$raw" | while IFS=$'\t' read -r n kid uid; do
    printf "%2d  %-35s  %s\n" "$n" "$uid" "$kid"
  done

  echo "$raw" > /tmp/.gpg_keys  # 临时表，下面再读
  read -p "请选择序号（多个用逗号分隔）: " picks
  local ok=1 p
  for p in ${picks//,/ }; do
    kid=$(awk -F'\t' -v p="$p" '$1==p{print $2}' /tmp/.gpg_keys)
    [[ -n $kid ]] && echo "$kid" || { echo -e "${RED}无效序号: $p${NC}" >&2; ok=0; }
  done
  rm -f /tmp/.gpg_keys
  return $ok
}

######## 加密 ########
encrypt_file(){
  local src=$1
  [[ -d $src ]] && { tar -czf "${src}.tar.gz" -C "$(dirname "$src")" "$(basename "$src")"; src="${src}.tar.gz"; }
  mapfile -t recipients < <(select_keys "请选择接收方公钥（加密给谁）")
  ((${#recipients[@]})) || return 1
  read -p "是否签名？(y/n): " sign
  local sign_args=()
  [[ $sign =~ ^[Yy]$ ]] && { read -p "签名用的私钥ID/邮箱: " signer; sign_args=(--sign --default-key "$signer"); }
  local out="${src}.gpg" rec_args=()
  for r in "${recipients[@]}"; do rec_args+=(--recipient "$r"); done
  gpg --encrypt "${rec_args[@]}" "${sign_args[@]}" --output "$out" "$src" &&
  echo -e "${GREEN}加密完成 → $out ${NC}"
}

######## 解密 ########
decrypt_file(){
  local enc=$1 out="${enc%.gpg}"
  gpg --decrypt --output "$out" "$enc" &&
  if [[ $out == *.tar.gz ]]; then
    tar -xzf "$out" -C "$(dirname "$out")" && rm -f "$out"
    echo -e "${GREEN}解密并解压完成 → $(dirname "$out") ${NC}"
  else
    echo -e "${GREEN}解密完成 → $out ${NC}"
  fi
}

######## 菜单 ########
while true; do
  echo -e "\n${YELLOW}==== PGP 本地管理 ====${NC}"
  echo "1) 列出密钥  2) 导入密钥  3) 导出密钥  4) 生成密钥"
  echo "5) 删除密钥  6) 加密文件  7) 解密文件  8) 退出"
  read -p "请选择 [1-8]: " op
  case $op in
    1) list_keys ;;
    2) read -p "密钥文件路径: " f; [[ -f $f ]] && gpg --import "$f" && echo -e "${GREEN}导入完成${NC}" || echo -e "${RED}文件不存在${NC}" ;;
    3) list_keys; read -p "导出ID/邮箱: " k; read -p "公钥(1)/私钥(2)? " t; [[ $t == 1 ]] && gpg --armor --export "$k" >"${k}_public.asc" && echo "公钥已导出" || gpg --armor --export-secret-keys "$k" >"${k}_private.asc" && echo "私钥已导出" ;;
    4) gpg --full-generate-key ;;
    5) list_keys; read -p "删除ID/邮箱: " k; read -p "公钥(1)/私钥(2)/全部(3)? " t; [[ $t == 1 ]] && gpg --delete-keys "$k" || [[ $t == 2 ]] && gpg --delete-secret-keys "$k" || { gpg --delete-secret-keys "$k"; gpg --delete-keys "$k"; } ;;
    6) read -p "待加密路径: " src; [[ -e $src ]] && encrypt_file "$src" || echo -e "${RED}路径不存在${NC}" ;;
    7) read -p "待解密.gpg路径: " enc; [[ -f $enc ]] && decrypt_file "$enc" || echo -e "${RED}文件不存在${NC}" ;;
    8) echo -e "${GREEN}Bye~${NC}"; exit 0 ;;
    *) echo -e "${RED}无效选择${NC}" ;;
  esac
done
