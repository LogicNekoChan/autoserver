#!/usr/bin/env bash
# pgp_manager.sh —— Ubuntu Server 本地 PGP 全流程管理工具
set -euo pipefail

############ 工具检测 ############
for cmd in gpg tar; do
  command -v "$cmd" >/dev/null || { echo "请先安装 $cmd"; exit 1; }
done

############ 颜色 ############
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[1;34m' NC='\033[0m'

############ 辅助函数 ############
list_keys(){
  echo -e "\n${BLUE}========== 本地公钥 ==========${NC}"
  gpg --list-keys --keyid-format LONG |
  awk '/^pub/ { getline; print "\n公钥: " $2 " 过期: "($6?$6:"永不"); print "  UID: " $0 }'
  echo -e "\n${GREEN}========== 本地私钥 ==========${NC}"
  gpg --list-secret-keys --keyid-format LONG |
  awk '/^sec/ { getline; print "\n*私钥*: " $2 " 过期: "($6?$6:"永不"); print "  UID: " $0 }'
}

# 返回值 0 且向标准输出打印选中的 16 位 KeyID
select_keys(){
  local prompt="$1"
  local map                       # 先普通 local
  declare -A map                  # 再声明关联数组
  local kid uid
  while IFS=: read -r _ _ _ _ kid _ _ _ _ uid _; do
    [[ $kid && $uid ]] && map[$kid]=$uid
  done < <(gpg --list-keys --keyid-format LONG --with-colons)

  ((${#map[@]})) || { echo -e "${RED}本地没有公钥，无法加密！${NC}"; return 1; }

  echo -e "${YELLOW}${prompt}${NC}"
  printf "%2s  %-35s  %s\n" "序号" "UID" "KeyID"
  local -a kids=("${!map[@]}")
  local i
  for i in "${!kids[@]}"; do
    printf "%2d  %-35s  %s\n" $((i+1)) "${map[${kids[i]}]}" "${kids[i]}"
  done

  read -p "请选择序号（多个用逗号分隔）: " picks
  local ok=1
  for p in ${picks//,/ }; do
    if [[ $p =~ ^[0-9]+$ && $p -ge 1 && $p -le ${#kids[@]} ]]; then
      echo "${kids[$((p-1))]}"
    else
      echo -e "${RED}无效序号: $p${NC}" >&2
      ok=0
    fi
  done
  return $ok
}

############ 菜单 ############
while true; do
  echo -e "\n${YELLOW}==== PGP 本地管理 ====${NC}"
  echo "1) 列出本地密钥"
  echo "2) 导入密钥"
  echo "3) 导出密钥"
  echo "4) 生成密钥"
  echo "5) 删除密钥"
  echo "6) 加密文件/文件夹"
  echo "7) 解密文件"
  echo "8) 退出"
  read -p "请选择 [1-8]: " op

  case $op in
    1) list_keys ;;
    2)
      read -p "密钥文件路径: " f
      [[ -f $f ]] && gpg --import "$f" && echo -e "${GREEN}导入完成${NC}" || echo -e "${RED}文件不存在${NC}"
      ;;
    3)
      list_keys
      read -p "请输入要导出的 KeyID 或邮箱: " kid
      read -p "导出公钥(1) 还是私钥(2)？ " t
      if [[ $t == 1 ]]; then
        gpg --armor --export "$kid" > "${kid}_public.asc" && echo -e "${GREEN}公钥已导出 ${kid}_public.asc${NC}"
      elif [[ $t == 2 ]]; then
        gpg --armor --export-secret-keys "$kid" > "${kid}_private.asc" && echo -e "${GREEN}私钥已导出 ${kid}_private.asc${NC}"
      else echo -e "${RED}无效选择${NC}"; fi
      ;;
    4)
      echo -e "${YELLOW}开始交互式生成密钥…${NC}"
      gpg --full-generate-key
      ;;
    5)
      list_keys
      read -p "请输入要删除的 KeyID 或邮箱: " kid
      read -p "删除公钥(1) 私钥(2) 全部(3)？ " t
      if [[ $t == 1 ]]; then gpg --delete-keys "$kid"
      elif [[ $t == 2 ]]; then gpg --delete-secret-keys "$kid"
      elif [[ $t == 3 ]]; then gpg --delete-secret-keys "$kid"; gpg --delete-keys "$kid"
      else echo -e "${RED}无效选择${NC}"; fi
      ;;
    6)
      read -p "待加密文件或文件夹路径: " src
      [[ -e $src ]] || { echo -e "${RED}路径不存在${NC}"; continue; }
      if [[ -d $src ]]; then
        tar -czf "${src}.tar.gz" -C "$(dirname "$src")" "$(basename "$src")"
        src="${src}.tar.gz"
        echo -e "${BLUE}已压缩为 ${src}${NC}"
      fi
      mapfile -t recipients < <(select_keys "请选择接收方公钥（加密给谁）")
      ((${#recipients[@]})) || continue
      read -p "是否签名？(y/n): " sign
      SIGN=()
      if [[ $sign =~ ^[Yy]$ ]]; then
        list_keys
        read -p "用于签名的私钥 KeyID 或邮箱: " signer
        SIGN=(--sign --default-key "$signer")
      fi
      REC=()
      for r in "${recipients[@]}"; do REC+=(--recipient "$r"); done
      out="${src}.gpg"
      gpg --encrypt "${REC[@]}" "${SIGN[@]}" --output "$out" "$src"
      echo -e "${GREEN}加密完成 → $out ${NC}"
      ;;
    7)
      read -p "待解密的 .gpg 文件路径: " enc
      [[ -f $enc ]] || { echo -e "${RED}文件不存在${NC}"; continue; }
      out="${enc%.gpg}"
      gpg --decrypt --output "$out" "$enc"
      if [[ $out == *.tar.gz ]]; then
        dir=$(dirname "$out")
        tar -xzf "$out" -C "$dir" && rm -f "$out"
        echo -e "${GREEN}解密并解压完成 → 目录 $dir ${NC}"
      else
        echo -e "${GREEN}解密完成 → $out ${NC}"
      fi
      ;;
    8) echo -e "${GREEN}Bye~${NC}"; exit 0 ;;
    *) echo -e "${RED}无效选择${NC}" ;;
  esac
done
