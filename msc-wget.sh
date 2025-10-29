#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BASE="http://${MUSO_HOST:-mu-so}:15081"

# Print error message, return failure
error() {
  echo "$1" >&2
  return 1
}

# Send HTTP request — <path> [method]
fetch() {
  local out=-
  [[ -t 1 ]] && out=/dev/null

  wget -O "$out" --method "${2:-GET}" --no-cookies -qT2 --tries=1 "$BASE/$1" || {
    case $? in
    4) error 'Network failure.' ;;
    8) error 'Failed, Mu-so in standby?' ;;
    *) error "wget error ($?)." ;;
    esac
  }
}

# Fetch JSON, filter with jq — <endpoint> <filter>
fjson() {
  fetch "$1" | jq -cr "$2"
}

# List options, prompt user, and play — <endpoint> <filter>
prompt() {
  local data id names=() nm PS3='Enter option: ' urls=()
  data=$(fjson "$1" "$2|[.name,.ussi]|@tsv")

  while read -r nm id; do
    names+=("$nm")
    urls+=("$id")
  done <<<"$data"

  select nm in "${names[@]}"; do
    [[ $nm ]] && break
    echo 'Invalid option.' >&2
  done

  fetch "${urls[REPLY - 1]}?cmd=play"
}

# Toggle, get, or set state — <endpoint> <key> <arg> [mod]
state() {
  local mod=${4:-2} val

  if [[ -z $3 ]]; then
    val=$(fjson "$1" "(.$2|tonumber+1)%$mod")
  elif [[ $3 == \? ]]; then
    fjson "$1" ".\"$2\"//empty"
    return
  elif [[ $3 =~ ^[0-9]$ && $3 -lt $mod ]]; then
    val=$3
  else
    error 'Invalid argument.'
  fi

  fetch "$1?$2=$val" PUT
}

# Display help text
usage() {
  local name=${0##*/} ver=v3.2

  cat <<EOF
$name $ver - Control Naim Mu-so over HTTP
Copyright © 2025 Stouthart. All rights reserved.

Usage: $name <option> [argument]

Power:
 standby | wake

Inputs:
 input | radio

Playback:
 next | pause | play | prev | stop
 shuffle | repeat

Audio:
 loudness | mono | mute | volume <0..100>

Other:
 lighting <0..2>

Status:
 levels | network | nowplaying [key]
 outputs | power | system | update
EOF
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
  if [[ $arg == \? ]]; then
    fjson levels ".\"$opt\"//empty"
  elif [[ $arg =~ ^[0-9]+$ && $arg -le 100 ]]; then
    fetch "levels?$opt=$arg" PUT
  else
    error 'Missing or invalid argument.'
  fi
  ;;
lighting)
  state userinterface lightTheme "$arg" 3
  ;;
levels | network | nowplaying | outputs | power | system | update)
  if [[ -z $arg ]]; then
    fjson "$opt" 'to_entries[5:][]|select(.key|IN("children","cpu")|not)|"\(.key)=\(.value)"'
  elif [[ $arg =~ ^[[:alnum:]]+$ ]]; then
    fjson "$opt" ".\"$arg\"//empty"
  else
    error 'Invalid argument.'
  fi
  ;;
help | -h | --help)
  usage
  ;;
*)
  error 'Missing or invalid option.'
  ;;
esac
