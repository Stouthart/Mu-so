#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

[[ ${1-} == --xdbg ]] && { # Bash >= v5.0
  shift
  PS4='+\e[4G\e[36m$(((${EPOCHREALTIME/./}-_ERT)/1000))\e[9G\e[33m$LINENO\e[13G\e[90m>\e[15G\e[m'
  declare -ir _ERT=${EPOCHREALTIME/./}
  set -x
}

# Show error message, return failure
error() {
  echo "$1" >&2
  exit 1
}

BASE="http://${MUSO_HOST:-mu-so}:15081"

# Send HTTP request — <path> [method]
fetch() {
  local out=-
  [[ -t 1 ]] && out=/dev/null

  curl -o"$out" -fs -m4 -X"${2:-GET}" --http1.1 -H'User-Agent:' --tcp-nodelay "$BASE/$1" || {
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
  fetch "$1" | jq -cre "$2"
}

# Show now playing status
info() {
  local arr sec i

  read -ra arr < <(fjson nowplaying '[.artistName,.title,.albumName,.transportPosition//0,.duration//0,.codec,
    (.sampleRate//0|tonumber/1000),.bitDepth//0,(.bitRate//0|tonumber|if.<16000then. else./1000|round end),
    .sourceDetail//(.source//"?"|sub("^inputs/";""))]|map(.//"?")|@tsv')

  for i in 3 4; do
    printf -v sec '%02d' $(((arr[i] / 1000) % 60))
    arr[i]=$((arr[i] / 60000)):$sec
  done

  printf '%s / %s [%s]\n%s / %s - %s %skHz %sbit %skb/s [%s]\n' "${arr[@]}"
}

# List options, prompt user, and play — <endpoint> <filter>
prompt() {
  local data id names=() nm urls=()
  data=$(fjson "$1" "$2|[.name,.ussi]|@tsv")

  while read -r nm id; do
    names+=("$nm")
    urls+=("$id")
  done <<<"$data"

  PS3='Enter option: '
  select nm in "${names[@]}"; do
    [[ $nm ]] && break
    echo 'Invalid option.' >&2
  done

  fetch "${urls[REPLY - 1]}?cmd=play"
}

# Seek to playback position - <arg>
seek() {
  local -i dur pos val

  if [[ $arg =~ ^([+-]?)([0-9]{1,4})$ ]] && ((BASH_REMATCH[2] <= 3600)); then
    read -r pos dur < <(fjson nowplaying '[.transportPosition,.duration]|map((.//0|tonumber/1000|round))|@tsv')
    ((dur == 0)) && return

    val=${BASH_REMATCH[2]}

    case ${BASH_REMATCH[1]} in
    +) ((val += pos)) ;;
    -) ((val = pos - val)) ;;
    esac

    ((val < 0)) && val=0
    ((val >= dur)) && ((val = dur - 1))

    fetch "nowplaying?cmd=seek&position=$((val * 1000))"
  else
    error 'Missing or invalid argument.'
  fi
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
$name v4.5 - Control Naim Mu-so 2 over HTTP
Copyright (C) 2025 Stouthart. All rights reserved.

Usage: $name <option> [argument]

Power:
  standby | wake

Inputs:
  input | radio

Playback:
  next | pause | play | prev | stop
  seek <sec> | shuffle | repeat

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

opt=${1-}
arg=${2-}

# Option aliases/mappings
case $opt in
capabilities) opt=system/capabilities ;;
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
seek)
  seek "$arg"
  ;;
shuffle)
  state nowplaying shuffle "$arg"
  ;;
repeat)
  state nowplaying repeat "$arg" 3
  ;;
clear)
  fetch inputs/playqueue?clear=true POST
  ;;
playqueue)
  fjson inputs/playqueue '.children[]?|"\(.artistName//"?") / \(.name) [\(.albumName//"?")]"' || true
  ;;
loudness | mono)
  state outputs "$opt" "$arg"
  ;;
mute)
  state levels mute "$arg"
  ;;
volume)
  if [[ $arg == \? ]]; then
    fjson levels ".\"$opt\"//empty"
  elif [[ $arg =~ ^([+-]?)([0-9]{1,3})$ ]] && ((BASH_REMATCH[2] <= 100)); then
    [[ -n ${BASH_REMATCH[1]} ]] && arg=$(fjson levels "[.volume|0,tonumber${BASH_REMATCH[0]},100]|sort|.[1]")
    fetch "levels?volume=$arg" PUT
  else
    error 'Missing or invalid argument.'
  fi
  ;;
lighting)
  state userinterface lightTheme "$arg" 3
  ;;
info)
  info
  ;;
system/capabilities | levels | network | nowplaying | outputs | power | system | update)
  if [[ -z $arg ]]; then
    fjson "$opt" 'to_entries[5:][]|select(.key!="cpu"and.key!="children")|"\(.key)=\(.value)"'
  elif [[ $arg =~ ^[[:alnum:]]{3,24}$ ]]; then
    fjson "$opt" ".\"$arg\"//empty" || true
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

exit
