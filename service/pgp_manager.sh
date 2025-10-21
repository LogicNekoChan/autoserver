#!/usr/bin/env bash
# ==========================================
# PGP Key Manager for Ubuntu
# Author: Austin Hang
# Usage: ./pgp-manager.sh [command] [args...]
# ==========================================
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log() { echo -e "${GREEN}[INFO]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die() { err "$*"; exit 1; }

# Helpers
quote() { printf '%q' "$1"; }

# Validate dependencies
command -v gpg >/dev/null || die "gpg not found. Install with: sudo apt install gnupg"
command -v tar >/dev/null || die "tar not found."

# ==========================================
# Commands
# ==========================================

cmd_create_key() {
    log "Creating new PGP key..."
    gpg --full-generate-key
}

cmd_import_key() {
    local file="${1:?Usage: import <file.asc>}"
    [[ -f "$file" ]] || die "File not found: $file"
    gpg --import "$file"
    log "Key imported from $file"
}

cmd_export_key() {
    local email="${1:?Usage: export <email>}"
    local output="${2:-${email}.asc}"
    gpg --armor --export "$email" > "$output"
    log "Public key exported to $output"
}

cmd_delete_key() {
    local email="${1:?Usage: delete <email>}"
    log "Deleting key for $email"
    gpg --delete-secret-and-public-keys "$email"
}

cmd_encrypt() {
    local target="${1:?Usage: encrypt <file_or_dir> [recipient]}"
    local recipient="${2:-}"
    [[ -e "$target" ]] || die "Target not found: $target"

    # Ask for recipient if not provided
    if [[ -z "$recipient" ]]; then
        read -rp "Enter recipient email: " recipient
    fi

    local target_dir
    target_dir=$(dirname "$(realpath "$target")")
    local basename
    basename=$(basename "$target")

    cd "$target_dir"

    if [[ -d "$basename" ]]; then
        log "Encrypting directory: $basename"
        tar czf - "$basename" | gpg -e -r "$recipient" > "${basename}.tar.gz.gpg"
    else
        log "Encrypting file: $basename"
        gpg -e -r "$recipient" -o "${basename}.gpg" "$basename"
    fi

    log "Encrypted output: ${target_dir}/${basename}.tar.gz.gpg or ${basename}.gpg"
}

cmd_decrypt() {
    local file="${1:?Usage: decrypt <file.gpg>}"
    [[ -f "$file" ]] || die "File not found: $file"

    local target_dir
    target_dir=$(dirname "$(realpath "$file")")
    local basename
    basename=$(basename "$file")

    cd "$target_dir"

    if [[ "$basename" == *.tar.gz.gpg ]]; then
        log "Decrypting and extracting directory: $basename"
        gpg -d "$basename" | tar xzf -
    else
        local output="${basename%.gpg}"
        log "Decrypting file: $basename -> $output"
        gpg -d "$basename" > "$output"
    fi

    log "Decryption complete in $target_dir"
}

# ==========================================
# Main CLI
# ==========================================

usage() {
    cat <<EOF
Usage: $0 <command> [args...]

Commands:
  create                        Create a new PGP key
  import <file.asc>             Import public/private key
  export <email> [output.asc]   Export public key
  delete <email>                Delete key pair
  encrypt <path> [recipient]    Encrypt file or folder
  decrypt <file.gpg>            Decrypt file or folder

Examples:
  $0 encrypt "My Folder" user@example.com
  $0 decrypt "My Folder.tar.gz.gpg"
EOF
    exit 1
}

main() {
    [[ $# -eq 0 ]] && usage
    local cmd="$1"; shift
    case "$cmd" in
        create) cmd_create_key ;;
        import) cmd_import_key "$@" ;;
        export) cmd_export_key "$@" ;;
        delete) cmd_delete_key "$@" ;;
        encrypt) cmd_encrypt "$@" ;;
        decrypt) cmd_decrypt "$@" ;;
        *) usage ;;
    esac
}

main "$@"
