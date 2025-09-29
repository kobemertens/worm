#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HOME}/.cache/worm"
mkdir -p "$CACHE_DIR"

REFRESH=false
SEARCH=""
PORTS=""
P_ARG=""
R_ARG=""
CONTAINER=""

IGNORE_FILE="${SCRIPT_DIR}/ignore-hosts.txt"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh)
      REFRESH=true
      shift
      ;;
    -p|--ports)
      PORTS="$2"
      shift 2
      ;;
    -c|--container)
      CONTAINER="$2"
      shift 2
      ;;
    *)
      SEARCH="$1"
      shift
      ;;
  esac
done

# Handle ports if given
if [[ -n "$PORTS" ]]; then
  P_ARG="-p ${PORTS%%:*}"
  R_ARG="-r ${PORTS##*:}"
fi

# --- Collect hosts from SSH config ---
HOSTS=($(grep -E '^Host ' ~/.ssh/config | awk '{print $2}'))

# Remove ignored hosts if ignore file exists
if [[ -f "$IGNORE_FILE" ]]; then
  IGNORED=($(<"$IGNORE_FILE"))
  for ignore in "${IGNORED[@]}"; do
    HOSTS=("${HOSTS[@]/$ignore}")
  done
fi

options=()

for host in "${HOSTS[@]}"; do
  [[ -z "$host" ]] && continue
  cache_file="${CACHE_DIR}/${host}.txt"

  if [[ "$REFRESH" == true || ! -f "$cache_file" ]]; then
    echo "Fetching folders from $host..."
    folders=$(ssh "$host" "ls -1 /data 2>/dev/null" | grep -v '^$' || true)
    echo "$folders" > "$cache_file"
  else
    folders=$(<"$cache_file")
  fi

  for folder in $folders; do
    options+=("$host:$folder")
  done
done

# Apply search filter if provided
if [[ -n "$SEARCH" ]]; then
  options=($(printf "%s\n" "${options[@]}" | grep -i "$SEARCH" || true))
fi

# Handle no matches
if [[ ${#options[@]} -eq 0 ]]; then
  echo "No matches found."
  exit 1
fi

# If only one match -> skip fzf
if [[ ${#options[@]} -eq 1 ]]; then
  selected="${options[0]}"
  echo "Auto-selected: $selected"
else
  selected=$(printf "%s\n" "${options[@]}" | fzf --prompt="Select host:folder > ")
fi

if [[ -n "$selected" ]]; then
  host="${selected%%:*}"
  folder="${selected#*:}"

  echo "Connecting to $host, folder: $folder $P_ARG $R_ARG ${CONTAINER:+container: $CONTAINER}"

  if [[ -n "$CONTAINER" ]]; then
    $SCRIPT_DIR/container-tunnel $P_ARG $R_ARG "$host" "$folder" "$CONTAINER"
  else
    $SCRIPT_DIR/container-tunnel $P_ARG $R_ARG "$host" "$folder"
  fi
fi
