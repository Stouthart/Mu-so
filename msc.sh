#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BASE="http://${MUSO_HOST:-mu-so}:15081"

# Send HTTP request — <path> [method]
fetch() {
  local msg opts=(-X "${2:-GET}") rc=0
  [[ -t 1 ]] && opts+=(-o /dev/null)

  curl "${opts[@]}" --http1.1 --tcp-nodelay --keepalive-time 15 -fs -m3 --no-buffer "$BASE/$1" || rc=$?

  if ((rc > 0)); then
    case $rc in
    7) msg='Cannot connect to Mu-so.' ;;
    22) msg='Mu-so is in standby.' ;;
    28) msg='Operation timed out.' ;;
    *) msg="curl error ($rc)." ;;
    esac

    echo "$msg" >&2
    return $rc
  fi
}

# Fetch JSON and filter with jq — <endpoint> <jq_filter>
fjson() {
  local data
  data=$(fetch "$1") || return $?
  jq -cr "$2" <<<"$data"
}

# List options, prompt user, play — <endpoint> <jq_filter>
prompt() {
  local id names=() nm PS3='Enter option: ' urls=()

  while read -r nm id; do
    names+=("$nm")
    urls+=("$id")
  done < <(fjson "$1" "$2|[.name,.ussi]|@tsv")

  select nm in "${names[@]}"; do
    [[ $nm ]] && break
    echo 'Invalid option.' >&2
  done

  fetch "${urls[REPLY - 1]}?cmd=play"
}

# Get or toggle state — <endpoint> <key> <get> [mod]
state() {
  if [[ $3 == ? ]]; then
    fjson "$1" ".\"$2\"//empty"
  else
    local val
    val=$(fjson "$1" "(.$2|tonumber+1)%${4:-2}") || return $?
    fetch "$1?$2=$val" PUT --silent
  fi
}

# Display help text
usage() {
  local name=${0##*/}

  printf '%s v3.0 - Control Naim Mu-so over HTTP\nCopyright © 2025 Stouthart. All rights reserved.\n\n' "$name"
  printf 'Usage: %s <option> [argument]\n\n' "$name"
  printf 'Power:\n standby | wake\n\n'
  printf 'Inputs:\n input | radio\n\n'
  printf 'Playback:\n next | pause | play | prev | stop\n shuffle | repeat\n\n'
  printf 'Audio:\n loudness | mono | mute | volume <0..100>\n\n'
  printf 'Other:\n lighting\n\n'
  printf 'Status:\n levels | network | nowplaying [key]\n outputs | power | system | update\n'
}

opt=${1:-}
arg=${2:-}

# Option aliases/mappings
case $opt in
now) opt=nowplaying ;;
pause) opt=playpause ;;
sleep) opt=standby ;;
vol) opt=volume ;;
esac

# Main option handler
case $opt in
standby)
  fetch 'power?system=lona' PUT
  ;;
wake)
  fetch 'power?system=on' PUT
  ;;
input)
  prompt inputs '.children[]|select(.disabled=="0")'
  ;;
radio)
  prompt favourites \
    '.children|map(select(.favouriteClass|test("^object\\.stream\\.radio")))|sort_by(.presetID|tonumber)[]'
  ;;
next | play | playpause | prev | stop)
  fetch "nowplaying?cmd=$opt"
  ;;
shuffle)
  state nowplaying "$opt" "$arg"
  ;;
repeat)
  state nowplaying "$opt" "$arg" 3
  ;;
loudness | mono)
  state outputs "$opt" "$arg"
  ;;
mute)
  state levels "$opt" "$arg"
  ;;
volume)
  if [[ $arg == ? ]]; then
    fjson levels ".\"$opt\"//empty"
  elif [[ $arg =~ ^[0-9]+$ && $arg -le 100 ]]; then
    fetch "levels?$opt=$arg" PUT
  else
    echo 'Missing or invalid argument.' >&2
    exit 1
  fi
  ;;
lighting)
  state userinterface lightTheme "$arg" 3
  ;;
levels | network | nowplaying | outputs | power | system | update)
  if [[ ${arg:-} =~ ^[[:alnum:]]+$ ]]; then
    fjson "$opt" ".\"$arg\"//empty"
  else
    fjson "$opt" 'to_entries[5:][]|select(.key|IN("children","cpu")|not)|"\(.key)=\(.value)"'
  fi
  ;;
help | -h | --help)
  usage
  ;;
*)
  echo 'Missing or invalid option.' >&2
  exit 1
  ;;
esac
