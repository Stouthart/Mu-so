#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BASE="http://${MUSO_HOST:-mu-so}:15081"

# List, select, and play item — choose <endpoint> <jq_filter>
choose() {
  local id names=() nm PS3='Enter option: ' urls=()

  while read -r nm id; do
    names+=("$nm") urls+=("$id")
  done < <(fjson "$1" "$2|[.name,.ussi]|@tsv")

  select nm in "${names[@]}"; do
    [[ $nm ]] && break
    echo 'Invalid option.' >&2
  done

  fetch "${urls[REPLY - 1]}?cmd=play"
}

# Toggle/cycle numeric field — cycle <endpoint> <field> [mod]
cycle() {
  fetch "$1?$2=$(fjson "$1" "(.$2|tonumber+1)%${3:-2}")" PUT --silent
}

# Send HTTP request — fetch <path> [method] [--silent]
fetch() {
  local err opts=(-X "${2:-GET}") rc=0
  [[ -t 1 ]] && opts+=(-o /dev/null)

  curl "${opts[@]}" --http1.1 --tcp-nodelay --keepalive -fs -m2 --no-buffer "$BASE/$1" || rc=$?

  [[ $rc -gt 0 && ${3:-} != --silent ]] && {
    case $rc in
    7) err='Cannot connect to Mu-so.' ;;
    22) err='Mu-so is in standby.' ;;
    28) err='Operation timed out.' ;;
    *) err="curl error ($rc)." ;;
    esac

    echo "$err" >&2
  }

  return $rc
}

# Fetch JSON and filter with jq — fjson <endpoint> <jq_filter>
fjson() {
  jq -cr "$2" <(fetch "$1")
}

# Set power on/off — power <state>
power() {
  fetch "power?system=$1" PUT
}

# Help text — usage
usage() {
  local name=${0##*/}
  printf '%s v2.5 - Control Naim Mu-so over HTTP\nCopyright © 2025 Stouthart. All rights reserved.\n\n' "$name"
  printf 'Usage: %s <option> [argument]\n\n' "$name"
  printf 'Power:\n  standby | wake\n\n'
  printf 'Inputs:\n  input | radio\n\n'
  printf 'Playback:\n  next | pause | play | playpause | prev | stop\n  shuffle | repeat\n\n'
  printf 'Audio:\n  loudness | mono | mute | volume <0..100>\n\n'
  printf 'Status:\n  levels | multiroom | network | nowplaying\n  outputs | power | system | update\n'
}

# Option aliases
opt=${1:-}
case $opt in
now)
  opt=nowplaying
  ;;
pp)
  opt=playpause
  ;;
vol)
  opt=volume
  ;;
esac

# Main option handler
case $opt in
standby)
  power lona
  ;;
wake)
  power on
  ;;
input)
  choose inputs '.children[]|select(.disabled=="0")'
  ;;
radio)
  choose favourites \
    '.children|map(select(.favouriteClass|test("^object\\.stream\\.radio")))|sort_by(.presetID|tonumber)[]'
  ;;
next | pause | play | playpause | prev | stop)
  fetch "nowplaying?cmd=$opt"
  ;;
shuffle)
  cycle nowplaying "$opt"
  ;;
repeat)
  cycle nowplaying "$opt" 3
  ;;
loudness | mono)
  cycle outputs "$opt"
  ;;
mute)
  cycle levels "$opt"
  ;;
volume)
  if [[ ${2:-} =~ ^[0-9]+$ && $2 -le 100 ]]; then
    fetch "levels?$opt=$2" PUT
  else
    echo 'Missing or invalid argument.' >&2
    exit 1
  fi
  ;;
levels | multiroom | network | nowplaying | outputs | power | system | update)
  if [[ ${2:-} =~ ^[[:alnum:]]+$ ]]; then
    fjson "$opt" ".\"$2\"//empty"
  else
    fjson "$opt" 'to_entries[5:]|map(select(.key!="cpu"))[]|"\(.key)=\(.value)"'
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
