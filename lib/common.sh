#!/bin/bash
# Shared helpers for the panel installer. Sourced by install.sh and every module.
# Requires env: LOG, NON_INTERACTIVE

# Answers collected by 10-prompt persist across module processes via this file.
if [ -n "${TMPDIR_WORK:-}" ] && [ -f "$TMPDIR_WORK/answers.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$TMPDIR_WORK/answers.env"
  set +a
fi

log()  { echo "* $1" | tee -a "$LOG"; }
warn() { echo "! WARNING: $1" | tee -a "$LOG" >&2; }
die()  { echo "ERROR: $1" | tee -a "$LOG" >&2; exit 1; }

fetch() { # fetch <repo-path> <local-path> - works with https:// or file:// REPO_RAW
  # NOTE: -f is silent on HTTP errors, so log the URL first (a failed fetch
  # under `set -e` would otherwise kill the run with no explanation).
  log "Downloading $REPO_RAW/$1 ..."
  curl -fsSL --retry 3 --retry-delay 5 --retry-all-errors --max-time 180 \
    "$REPO_RAW/$1" -o "$2" \
    || die "Download failed after retries: $REPO_RAW/$1"
}

gen_pass() { # gen_pass <length>
  tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"; echo
}

# ask VAR "Prompt" "default" — honors preset env, or non-interactive defaults.
ask() {
  local var="$1" prompt="$2" def="$3" cur
  eval "cur=\${$var:-}"
  if [ -n "$cur" ]; then
    return 0
  fi
  if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
    eval "$var=\"\$def\""
    return 0
  fi
  if [ -n "$def" ]; then
    printf "* %s [%s]: " "$prompt" "$def"
  else
    printf "* %s: " "$prompt"
  fi
  read -r cur || true
  if [ -z "$cur" ]; then
    cur="$def"
  fi
  eval "$var=\"\$cur\""
}

# ask_port VAR "Prompt" "default" "recommendation/warning text"
# Loops until the user picks a valid, free port (dies in non-interactive mode).
ask_port() {
  local var="$1" prompt="$2" def="$3" note="$4" cur owner
  while true; do
    eval "cur=\${$var:-}"
    if [ -z "$cur" ] && [ "${NON_INTERACTIVE:-0}" != "1" ]; then
      echo "* $prompt"
      echo "  Note: $note"
      printf "  Port [%s]: " "$def"
      read -r cur || true
      if [ -z "$cur" ]; then
        cur="$def"
      fi
      eval "$var=\"\$cur\""
    elif [ -z "$cur" ]; then
      eval "$var=\"\$def\""
      eval "cur=\${$var:-}"
    fi
    if ! [[ "$cur" =~ ^[0-9]+$ ]] || [ "$cur" -lt 1 ] || [ "$cur" -gt 65535 ]; then
      if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
        die "Invalid port for $prompt: $cur"
      fi
      echo "  '$cur' is not a valid port (1-65535). Try again."
      eval "$var=''"
      continue
    fi
    if port_in_use "$cur"; then
      owner="$(port_owner "$cur")"
      if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
        die "Port $cur ($prompt) is already in use${owner:+ by $owner}."
      fi
      echo "  Port $cur is ALREADY IN USE${owner:+ by $owner}. Pick another one."
      eval "$var=''"
      continue
    fi
    case "$cur" in
      443|80|8080|2053|2096|2083)
        warn "Port $cur ($prompt) is commonly used by x-ui / proxies. It is free right now, but if you install x-ui later it will clash. Prefer the recommended default."
        ;;
    esac
    break
  done
}

port_owner() { # port_owner <port> -> "process" or empty
  (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) \
    | grep -E "[:.]$1[[:space:]]" | head -1 \
    | sed -n 's/.*users:(("\([^",]*\)".*/\1/p'
}

detect_pubip() { # prints public IP or nothing; tries several services
  local url ip
  for url in https://api.ipify.org https://icanhazip.com https://checkip.amazonaws.com https://ifconfig.me; do
    ip="$(curl -fsSL --max-time 8 "$url" 2>/dev/null | tr -d ' \r\n' || true)"
    case "$ip" in
      *.*.*.*|*:*:*) echo "$ip"; return 0 ;;
    esac
  done
  return 1
}

# show_port_table: live scan shown BEFORE the user picks ports.
show_port_table() {
  echo ""
  echo "=== Live port scan on this machine ==="
  printf "  %-7s %-6s %s\n" "PORT" "STATE" "USED BY"
  local p
  for p in 22 80 443 3306 6379 8080 8081 8443 8444 2022 25565; do
    if port_in_use "$p"; then
      printf "  %-7s %-6s %s\n" "$p" "TAKEN" "$(port_owner "$p")"
    else
      printf "  %-7s %-6s %s\n" "$p" "free" "-"
    fi
  done
  echo "  (Pick free ports below. Taken ports are rejected automatically.)"
  echo ""
}

port_in_use() { # port_in_use <port> -> 0 if something listens
  (ss -tln 2>/dev/null || netstat -tln 2>/dev/null) | grep -qE "[:.]$1[[:space:]]"
}

total_mem_mb() {
  free -m | awk '/^Mem:/ {print $2}'
}

free_disk_mb() { # free MB on /
  df -m / | awk 'NR==2 {print $4}'
}
