#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BASE="http://${MUSO_HOST:-mu-so}:15081"

# Show error message, return failure
error() {
  echo "$1" >&2
  return 1
}

# Send HTTP request — <path> [method]
fetch() {
  local out=-
  [[ -t 1 ]] && out=/dev/null

  curl -o "$out" -X "${2:-GET}" --http1.1 --no-buffer -fs --tcp-nodelay --keepalive-time 10 -m5 "$BASE/$1" || {
    case $? in
    7) error 'Network failure.' ;;
    8) error 'Failed, Mu-so in standby?' ;;
    28) error 'Operation timeout.' ;;
    *) error "curl error ($?)." ;;
    esac
  }
}

# Fetch JSON, filter with jq — <endpoint> <filter>
fjson() {
  fetch "$1" | jq -cr "$2"
}

# Show now playing information
info() {
  local arr data
  data=$(fjson nowplaying '[.artistName,.title,.albumName,.transportPosition//0,.duration//0,.codec,.sampleRate,
    if (.bitRate//0|tonumber)>=64000 then .bitRate|tonumber/1000|tostring+"kb/s" else .bitDepth//"?"+"-bit" end,
    .sourceDetail//(.source|sub("^inputs/";""))]|map(.//"?")|@tsv')
  read -ra arr <<<"$data"

  fmt() { printf '%d:%02d' "$(($1 / 60000))" "$((($1 / 1000) % 60))"; }
  arr[3]=$(fmt "${arr[3]}")
  arr[4]=$(fmt "${arr[4]}")

  printf '%s / %s [%s]\n%s / %s - %s %s %s [%s]\n' "${arr[@]}"
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
    val=$(fjson "$1" ".$2|(tonumber+1)%$mod")
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

# Show help/usage text
usage() {
  local name=${0##*/}

  cat <<EOF
$name v3.5 - Control Naim Mu-so 2nd Gen. over HTTP
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

Info:
  capabilities | levels | network | nowplaying
  outputs | power | system | update
EOF
}

opt=${1:-}
arg=${2:-}

# Option aliases/mappings
case $opt in
capabilities) opt='system/capabilities' ;;
info) opt=nowplaying ;;
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
  elif [[ $arg =~ ^[+-]([0-9]+)$ && ${BASH_REMATCH[1]} -le 100 ]]; then
    arg=$(fjson levels "[.volume|tonumber${BASH_REMATCH[0]},0,100]|sort|.[1]")
    fetch "levels?$opt=$arg" PUT
  else
    error 'Missing or invalid argument.'
  fi
  ;;
lighting)
  state userinterface lightTheme "$arg" 3
  ;;
nowplaying)
  info
  ;;
levels | network | outputs | power | system | system/capabilities | update)
  if [[ -z $arg ]]; then
    fjson "$opt" 'to_entries[5:][]|select(.key!="cpu" and .key!="children")|"\(.key)=\(.value)"'
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
