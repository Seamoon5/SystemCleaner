#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/SystemCleaner-linux.log"

CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
DARK=$'\033[90m'
NONE=$'\033[0m'

is_wsl="false"
if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
    is_wsl="true"
fi

bytes_h() {
    local b="$1"
    if [ "$b" -ge 1073741824 ]; then
        awk -v v="$b" 'BEGIN { printf "%.2f GB", v/1073741824 }'
    elif [ "$b" -ge 1048576 ]; then
        awk -v v="$b" 'BEGIN { printf "%.1f MB", v/1048576 }'
    elif [ "$b" -ge 1024 ]; then
        awk -v v="$b" 'BEGIN { printf "%.0f KB", v/1024 }'
    else
        echo "0 KB"
    fi
}

du_bytes() {
    local path="$1"
    if [ ! -e "$path" ]; then echo 0; return; fi
    du -sb "$path" 2>/dev/null | awk '{print $1}'
}

count_files() {
    local path="$1"
    if [ ! -e "$path" ]; then echo 0; return; fi
    find "$path" -type f 2>/dev/null | wc -l
}

log_msg() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S')  $1"
    echo "$line" >> "$LOG_FILE"
}

scan_categories() {
    cat_apt_bytes=$(du_bytes /var/cache/apt/archives)
    cat_apt_files=$(count_files /var/cache/apt/archives)

    cat_cache_bytes=$(du_bytes "$HOME/.cache")
    cat_cache_files=$(count_files "$HOME/.cache")

    cat_pkgmgr_bytes=0
    cat_pkgmgr_files=0
    for p in "$HOME/.cache/pip" "$HOME/.npm/_cacache" "$HOME/.bun/install/cache" "$HOME/.cargo/registry/cache" "$HOME/go/pkg/mod/cache"; do
        if [ -e "$p" ]; then
            cat_pkgmgr_bytes=$((cat_pkgmgr_bytes + $(du_bytes "$p")))
            cat_pkgmgr_files=$((cat_pkgmgr_files + $(count_files "$p")))
        fi
    done

    cat_trash_bytes=$(du_bytes "$HOME/.local/share/Trash")
    cat_trash_files=$(count_files "$HOME/.local/share/Trash")

    cat_tmp_bytes=0
    cat_tmp_files=0
    if [ -d /tmp ]; then
        while IFS= read -r -d '' f; do
            s=$(stat -c %s "$f" 2>/dev/null || echo 0)
            cat_tmp_bytes=$((cat_tmp_bytes + s))
            cat_tmp_files=$((cat_tmp_files + 1))
        done < <(find /tmp -type f -mtime +7 -user "$USER" -print0 2>/dev/null)
    fi

    if command -v journalctl >/dev/null 2>&1; then
        cat_journal_boot=$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]' | head -1 || echo "?")
        cat_journal_text="${cat_journal_boot:-unknown}"
    else
        cat_journal_text="n/a"
    fi
}

print_journal_hint() {
    echo "  journal logs: systemd journals (old boot logs). To see usage size: journalctl --disk-usage"
    echo "  "
}

show_scan() {
    scan_categories
    local total
    total=$((cat_apt_bytes + cat_cache_bytes + cat_pkgmgr_bytes + cat_trash_bytes + cat_tmp_bytes))
    echo ""
    echo -e "${CYAN}===== SystemCleaner - Linux scan report (nothing deleted yet) =====${NONE}"
    printf "%-28s %10s  %10s files\n" "apt package cache" "$(bytes_h "$cat_apt_bytes")" "$cat_apt_files"
    echo -e "  ${DARK}Downloaded .deb installers already installed; safe to purge${NONE}"
    printf "%-28s %10s  %10s files\n" "user cache (~/.cache)" "$(bytes_h "$cat_cache_bytes")" "$cat_cache_files"
    echo -e "  ${DARK}App caches (older file previews, etc.); apps rebuild them${NONE}"
    printf "%-28s %10s  %10s files\n" "package-manager caches" "$(bytes_h "$cat_pkgmgr_bytes")" "$cat_pkgmgr_files"
    echo -e "  ${DARK}pip / npm / bun / cargo / go caches; safe, redownloaded when needed${NONE}"
    printf "%-28s %10s  %10s files\n" "trash" "$(bytes_h "$cat_trash_bytes")" "$cat_trash_files"
    echo -e "  ${DARK}Your deleted files still waiting in the trash${NONE}"
    printf "%-28s %10s  %10s files\n" "old temp files (>7 days)" "$(bytes_h "$cat_tmp_bytes")" "$cat_tmp_files"
    echo -e "  ${DARK}Empty leftovers in /tmp owned by you and older than 7 days${NONE}"
    printf "%-28s %10s\n" "old system journals" "$(bytes_h 0)"
    echo -e "  ${DARK}${cat_journal_text}${NONE}"
    echo ""
    echo -e "${YELLOW}TOTAL recoverable: $(bytes_h "$total")${NONE}"
    echo ""
}

clean_category_apt() {
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "  ${GREEN}cleaned apt package cache${NONE}"
        (sudo apt-get clean) >/dev/null 2>&1 || echo -e "  ${YELLOW}could not clean apt cache (need sudo?)${NONE}"
        log_msg "Cleaned apt package cache"
    fi
}

clean_category_cache() {
    if [ -d "$HOME/.cache" ]; then
        find "$HOME/.cache" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
        echo -e "  ${GREEN}cleaned user cache (~/.cache)${NONE}"
        log_msg "Cleaned user cache ~/.cache"
    fi
}

clean_category_pkgmgr() {
    for p in "$HOME/.cache/pip" "$HOME/.npm/_cacache" "$HOME/.bun/install/cache" "$HOME/.cargo/registry/cache" "$HOME/go/pkg/mod/cache"; do
        if [ -e "$p" ]; then
            rm -rf "$p" 2>/dev/null
        fi
    done
    echo -e "  ${GREEN}cleaned package-manager caches${NONE}"
    log_msg "Cleaned package-manager caches"
}

clean_category_trash() {
    if [ -d "$HOME/.local/share/Trash" ]; then
        rm -rf "$HOME/.local/share/Trash/files" "$HOME/.local/share/Trash/info" 2>/dev/null
        echo -e "  ${GREEN}cleaned trash${NONE}"
        log_msg "Cleaned trash"
    fi
}

clean_category_tmp() {
    find /tmp -type f -mtime +7 -user "$USER" -delete 2>/dev/null
    find /tmp -type d -mtime +7 -user "$USER" -empty -delete 2>/dev/null
    echo -e "  ${GREEN}cleaned old temp files (>7 days)${NONE}"
    log_msg "Cleaned old /tmp files (owned by user, >7 days old)"
}

CLEANERS=(apt cache pkgmgr trash tmp)
CLEANER_NAMES=("apt package cache" "user cache (~/.cache)" "package-manager caches" "trash" "old temp files (>7 days)")

clean_one() {
    case "$1" in
        apt) clean_category_apt ;;
        cache) clean_category_cache ;;
        pkgmgr) clean_category_pkgmgr ;;
        trash) clean_category_trash ;;
        tmp) clean_category_tmp ;;
        *) echo -e "  ${YELLOW}unknown category '$1', skipping${NONE}" ;;
    esac
}

clean_all() {
    echo ""
    echo -e "${CYAN}===== SystemCleaner - cleaning =====${NONE}"
    for c in "${CLEANERS[@]}"; do
        clean_one "$c"
    done
    echo -e "${GREEN}Done. Log: $LOG_FILE${NONE}"
    echo ""

    if [ "$is_wsl" = "true" ]; then
        echo -e "${MAGENTA}WSL tip:${NONE} cleaning WSL files does not by itself give disk space back to Windows."
        echo -e "${MAGENTA}To reclaim the space completely, shut down WSL and compact the disk image.${NONE}"
        echo -e "  wsl.exe --shutdown   then in PowerShell:  Optimize-VHD -Path <path-to-ext4.vhdx> -Mode Full"
        echo -e "  (or in your Windows Settings > Apps > ... > WSL > Disk freeing tool)"
        echo ""
    fi
}

clean_select() {
    local targets=("$@")
    if [ "${#targets[@]}" -eq 0 ]; then
        echo ""
        echo -e "${YELLOW}Type the category names to clean exactly as shown in the scan above,${NONE}"
        echo -e "${YELLOW}separated by spaces, or 'all' to clean everything safe.${NONE}"
        echo -e "${YELLOW}Available: apt cache pkgmgr trash tmp${NONE}"
        echo ""
        show_scan
        read -r -p "Clean: " -a picked
        targets=("${picked[@]}")
    fi
    if [ "${#targets[@]}" -eq 0 ]; then
        echo "Nothing selected."
        return
    fi
    if [ "${targets[0]}" = "all" ]; then
        clean_all
        return
    fi
    echo ""
    echo -e "${CYAN}===== SystemCleaner - cleaning =====${NONE}"
    for t in "${targets[@]}"; do
        clean_one "$t"
    done
    echo -e "${GREEN}Done. Log: $LOG_FILE${NONE}"
    echo ""
}

dry_run() {
    echo ""
    echo -e "${MAGENTA}DRY RUN: showing what a full clean would remove. Nothing deleted.${NONE}"
    show_scan
}

cmd_schedule() {
    local cron_exists
    cron_exists=$(crontab -l 2>/dev/null | grep -c "clean-linux.sh")
    if [ "$cron_exists" -gt 0 ]; then
        echo -e "${YELLOW}Schedule already exists (daily task is already installed).${NONE}"
        return
    fi
    ( crontab -l 2>/dev/null | grep -v "clean-linux.sh" ; echo "0 9 * * * /bin/bash $SCRIPT_DIR/clean-linux.sh clean all >>$LOG_FILE 2>&1" ) | crontab -
    echo -e "${GREEN}Scheduled: this cleaner now runs every day at 09:00 automatically.${NONE}"
    log_msg "Scheduled daily clean via cron (09:00)"
}

cmd_unschedule() {
    ( crontab -l 2>/dev/null | grep -v "clean-linux.sh" ) | crontab -
    echo -e "${GREEN}Auto-run removed. You can still run it manually anytime.${NONE}"
    log_msg "Removed auto-run schedule"
}

usage() {
    echo "SystemCleaner for WSL/Linux"
    echo ""
    echo "  ./clean-linux.sh scan                show junk report (nothing deleted)"
    echo "  ./clean-linux.sh clean all           clean every safe category"
    echo "  ./clean-linux.sh clean apt cache     clean only the listed categories"
    echo "  ./clean-linux.sh clean               ask which categories to clean"
    echo "  ./clean-linux.sh dry-run             preview without deleting"
    echo "  ./clean-linux.sh schedule            auto-run every day at 09:00"
    echo "  ./clean-linux.sh unschedule          stop the auto-run"
    echo "  ./clean-linux.sh log                 show the cleaner log"
    echo "  ./clean-linux.sh help                show this help"
    echo ""
    echo "Log file: $LOG_FILE"
}

cmd="${1:-scan}"
shift 2>/dev/null || true

case "$cmd" in
    scan) show_scan ;;
    clean) clean_select "$@" ;;
    dry-run) dry_run ;;
    schedule) cmd_schedule ;;
    unschedule) cmd_unschedule ;;
    log) tail -n 50 "$LOG_FILE" 2>/dev/null || echo "No log entries yet." ;;
    help|--help|-h) usage ;;
    *)
        echo -e "${RED}Unknown command: $cmd${NONE}"
        usage
        exit 1
        ;;
esac