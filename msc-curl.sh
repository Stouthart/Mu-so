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
now() {
  local arr data

  data=$(fjson nowplaying '[.artistName,.title,.albumName,.transportPosition//0,.duration//0,.codec,
    (.sampleRate//0|tonumber/1000),.bitDepth//0,(.bitRate//0|tonumber|if.<16000then. else./1000|round end),
    .sourceDetail//(.source//"?"|sub("^inputs/";""))]|map(.//"?")|@tsv')

  read -ra arr <<<"$data"

  fmt() { printf '%d:%02d' "$(($1 / 60000))" "$((($1 / 1000) % 60))"; }
  arr[3]=$(fmt "${arr[3]}")
  arr[4]=$(fmt "${arr[4]}")

  printf '%s / %s [%s]\n%s / %s - %s %skHz %sbit %skb/s [%s]\n' "${arr[@]}"
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

  if [[ -z $1 ]]; then
    val=$(fjson "$2" ".$3|(tonumber+1)%$mod")
  elif [[ $1 == \? ]]; then
    fjson "$2" ".\"$3\"//empty"
    return
  elif [[ $1 =~ ^[0-9]$ && $1 -lt $mod ]]; then
    val=$1
  else
    error 'Invalid argument.'
  fi

  fetch "$2?$3=$val" PUT
}

# Show help/usage text
usage() {
  local name=${0##*/}

  cat <<EOF
$name v4.1 - Control Naim Mu-so 2nd Gen. over HTTP
Copyright © 2025 Stouthart. All rights reserved.

Usage: $name <option> [argument]

Power:
  standby | wake

Inputs:
  input | radio

Playback:
  next | pause | play | prev | stop
  shuffle | repeat

Playqueue:
  clear | queue

Audio:
  loudness | mono | mute | volume <0..100>

Other:
  lighting <0..2>

Information:
  capabilities | levels | network | nowplaying
  outputs | power | system | update
EOF
}

opt=${1:-}
arg=${2:-}

# Option aliases/mappings
case $opt in
capabilities) opt=system/capabilities ;;
now) opt=nowplaying ;;
pause) opt=playpause ;;
queue) opt=playqueue ;;
sleep) opt=standby ;;
vol) opt=volume ;;
esac

# Main option handler
case $opt in
standby)
  fetch power?system=lona PUT
  ;;
wake)
  fetch power?system=on PUT
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
  state "$arg" nowplaying shuffle
  ;;
repeat)
  state "$arg" nowplaying repeat 3
  ;;
clear)
  fetch inputs/playqueue?clear=true POST
  ;;
playqueue)
  fjson inputs/playqueue '.children[]?|"\(.artistName//"?") / \(.name) [\(.albumName//"?")]"'
  ;;
loudness | mono)
  state "$arg" outputs "$opt"
  ;;
mute)
  state "$arg" levels mute
  ;;
volume)
  if [[ $arg == \? ]]; then
    fjson levels ".\"$opt\"//empty"
  elif [[ $arg =~ ^([+-]?)([0-9]+)$ && ${BASH_REMATCH[2]} -le 100 ]]; then
    [[ ${BASH_REMATCH[1]:-} ]] && arg=$(fjson levels "[.volume|tonumber${BASH_REMATCH[0]},0,100]|sort|.[1]")
    fetch "levels?volume=$arg" PUT
  else
    error 'Missing or invalid argument.'
  fi
  ;;
lighting)
  state "$arg" userinterface lightTheme 3
  ;;
nowplaying)
  now
  ;;
system/capabilities | levels | network | outputs | power | system | update)
  if [[ -z $arg ]]; then
    fjson "$opt" 'to_entries[5:][]|select(.key!="cpu"and.key!="children")|"\(.key)=\(.value)"'
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
