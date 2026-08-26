#!/bin/bash
#
# Regenerates /etc/issue with each configured zone's device, link state,
# and IP, colored to match Smoothwall's own zone colors. agetty shows
# /etc/issue automatically right before the login prompt on the physical
# console (tty1-6), so no getty/inittab changes are needed - only this
# file needs to stay current.
#
# Zones with no device configured (PURPLE_DEV empty, etc.) are skipped -
# only zones actually in use on this box are shown.
#
# Also prints a DISK line: green OK, or red with a reason, based on
# smartctl's own overall-health verdict, a few universally-bad-if-nonzero
# raw SMART attributes (reallocated/pending sectors, uncorrectable errors,
# program/erase fail counts - checked in addition to the overall verdict
# since it can lag actual reallocation onset on some drives), and whether
# any real filesystem is close to full.

ETH_SETTINGS=/var/smoothwall/ethernet/settings
ISSUE=/etc/issue

# Primary disk device, auto-detected from /proc/partitions (first whole-disk
# sd*/hd*/vd* entry, i.e. no trailing partition number). Falls back to
# /dev/sda, the overwhelmingly common case on this platform, if detection
# comes up empty.
DISK=$(awk 'NR>2 && $4 ~ /^(sd|hd|vd)[a-z]+$/ {print "/dev/"$4; exit}' /proc/partitions)
[ -z "$DISK" ] && DISK=/dev/sda

. "$ETH_SETTINGS"

RESET='\033[0m'
declare -A COLOR=( [RED]='\033[1;31m' [GREEN]='\033[1;32m' [ORANGE]='\033[1;33m' [PURPLE]='\033[1;35m' )

TMP="$(mktemp /etc/issue.XXXXXX)"

{
  echo -e "\033[1;37m$(hostname) - Smoothwall Express${RESET}"
  echo

  for zone in RED GREEN ORANGE PURPLE; do
    dev_var="${zone}_DEV"
    dev="${!dev_var}"
    [ -z "$dev" ] && continue

    if ip link show dev "$dev" &>/dev/null; then
      if ip link show dev "$dev" | grep -q 'LOWER_UP'; then
        state="UP"
      else
        state="DOWN"
      fi
      addr=$(ip -4 -o addr show dev "$dev" | awk '{print $4}')
      [ -z "$addr" ] && addr="(no address)"
    else
      state="MISSING"
      addr="(no such device)"
    fi

    printf "${COLOR[$zone]}%-8s %-6s %-7s %-20s${RESET}\n" "$zone" "$dev" "$state" "$addr"
  done
  echo

  disk_ok=1
  disk_reason=""

  if command -v smartctl &>/dev/null; then
    health=$(smartctl -H "$DISK" 2>/dev/null | awk -F: '/overall-health/ {print $2}' | xargs)
    if [ "$health" != "PASSED" ]; then
      disk_ok=0
      disk_reason="SMART ${health:-unknown}"
    fi

    bad_attrs=$(smartctl -A "$DISK" 2>/dev/null | awk '
      $1==5 || $1==187 || $1==197 || $1==198 || $1==171 || $1==172 { if ($NF+0 > 0) print $2"="$NF }
    ')
    if [ -n "$bad_attrs" ]; then
      disk_ok=0
      disk_reason="${disk_reason:+$disk_reason, }$bad_attrs"
    fi
  else
    disk_ok=0
    disk_reason="smartctl missing"
  fi

  full_reason=""
  while read -r _fs _size _used _avail pct mount; do
    pct_num="${pct%\%}"
    if [ "$pct_num" -ge 90 ] 2>/dev/null; then
      full_reason="${full_reason:+$full_reason, }$mount $pct"
    fi
  done < <(df -P -x tmpfs -x devtmpfs | tail -n +2)

  if [ -n "$full_reason" ]; then
    disk_ok=0
    disk_reason="${disk_reason:+$disk_reason; }Disk full: $full_reason"
  fi

  if [ "$disk_ok" -eq 1 ]; then
    printf '\033[1;32m%-8s %-38s\033[0m\n' "DISK" "OK (SMART passed, disk space OK)"
  else
    printf '\033[1;31m%-8s %-38s\033[0m\n' "DISK" "ERROR: $disk_reason"
  fi
  echo
} > "$TMP"

mv "$TMP" "$ISSUE"
chmod 644 "$ISSUE"
