#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

[[ ${1-} == --xdbg ]] && { # Bash >= v5.0
  shift
  PS4='+\e[4G\e[36m$(((${EPOCHREALTIME/./}-_ERT)/1000))\e[9G\e[33m$LINENO\e[13G\e[90m>\e[15G\e[m'
  declare -ir _ERT=${EPOCHREALTIME/./}
  set -x
}

BASE="http://${MUSO_IP:-mu-so}:15081"

# HTTP request — <uri> [method]
call() {
  local out=-
  [[ -t 1 ]] && out=/dev/null
  curl -fs --retry 1 -m2 -o"$out" -H'User-Agent:' -X"${2:-GET}" --http1.1 --tcp-nodelay "$BASE/$1" || error $?
}

# Print error and return
error() {
  local msg

  case $1 in
  6 | 7) msg='Network failure.' ;;
  22) msg='Error, Mu-so in standby?' ;;
  28) msg='Operation timeout.' ;;
  200) msg='Invalid argument.' ;;
  201) msg='Missing or invalid argument.' ;;
  202) msg='Missing or invalid option.' ;;
  *) msg="(curl) error $1." ;;
  esac

  printf '%s\n' "$msg" >&2
  return "$1"
}

# Now playing info
info() {
  local arr sec i

  read -ra arr < <(query nowplaying '[.artistName,.title,.albumName,.transportPosition//0,.duration//0,.codec,
    (.sampleRate//0|tonumber/1000),.bitDepth//0,(.bitRate//0|tonumber|if.<16000then. else./1000|round end),
    .sourceDetail//(.source//"?"|sub("^inputs/";""))]|map(.//"?")|@tsv')

  for i in 3 4; do
    printf -v sec '%02d' $(((arr[i] / 1000) % 60))
    arr[i]=$((arr[i] / 60000)):$sec
  done

  printf '%s / %s [%s]\n%s / %s - %s %skHz %sbit %skb/s [%s]\n' "${arr[@]}"
}

# List or play items — <endpoint> <filter> <arg>
play() {
  local data id nm names=() urls=()
  data=$(query "$1" ".children[]|select($2)|[.name,.ussi]|@tsv")

  while read -r nm id; do
    names+=("$nm")
    urls+=("$id")
  done <<<"$data"

  if [[ -z $3 ]]; then
    id=1
    for nm in "${names[@]}"; do
      printf '%d) %s\n' $((id++)) "$nm"
    done
  elif [[ $3 =~ ^[0-9]{1,2}$ ]] && (($3 > 0 && $3 <= ${#urls[@]})); then
    call "${urls[$3 - 1]}?cmd=play"
  else
    error 200
  fi
}

# JSON request — <endpoint> <filter>
query() {
  call "$1" | jq -cre "$2"
}

# Seek to position - <arg>
seek() {
  local -i dur pos val

  if [[ $1 =~ ^([+-]?)([0-9]{1,4})$ ]] && ((BASH_REMATCH[2] <= 3600)); then
    read -r pos dur < <(query nowplaying '[.transportPosition,.duration]|map((.//0|tonumber/1000|round))|@tsv')
    ((dur == 0)) && return

    val=${BASH_REMATCH[2]}

    case ${BASH_REMATCH[1]} in
    +) ((val += pos)) ;;
    -) ((val = pos - val)) ;;
    esac

    ((val = val < 0 ? 0 : val >= dur ? dur - 1 : val))
    call "nowplaying?cmd=seek&position=$((val * 1000))"
  else
    error 201
  fi
}

# Get, toggle or set state — <endpoint> <setting> <arg> [mod]
state() {
  local mod=${4:-2} val

  if [[ $3 == - ]]; then
    query "$1" ".\"$2\"//empty"
    return
  elif [[ -z $3 ]]; then
    val=$(query "$1" ".$2|(tonumber+1)%$mod")
  elif [[ $3 =~ ^[0-9]$ && $3 -lt $mod ]]; then
    val=$3
  else
    error 200
  fi

  call "$1?$2=$val" PUT
}

# Usage instructions
usage() {
  cat <<EOF
${0##*/} v5.0 - Control Naim Mu-so 2 over HTTP
Copyright (C) 2025 Stouthart. All rights reserved.

Usage: ${0##*/} <option> [argument]

Power:
  standby | wake

Inputs:
  inputs | presets

Playback:
  next | pause | play | prev | stop
  seek <sec> | shuffle | repeat

Playqueue:
  clear | queue

Audio:
  loudness | mono | mute | volume <0..100>

Other:
  lighting <0..2> | position <0..2>

Information:
  capabilities | levels | network | nowplaying
  outputs | power | system | update
EOF
}

opt=${1-}
arg=${2-}

# Option aliases
case $opt in
capabilities) opt=system/capabilities ;;
lighting) opt=lightTheme ;;
pause) opt=playpause ;;
queue) opt=playqueue ;;
vol) opt=volume ;;
esac

# Main dispatcher
case $opt in
standby)
  call power?system=lona PUT
  ;;
wake)
  call power?system=on PUT
  ;;
inputs)
  play inputs '.disabled=="0"' "$arg"
  ;;
presets)
  play favourites?sort=D:presetID .stationKey!=null "$arg"
  ;;
next | play | playpause | prev | stop)
  call "nowplaying?cmd=$opt"
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
  call inputs/playqueue?clear=true POST
  ;;
playqueue)
  query inputs/playqueue '.children[]?|"\(.artistName//"?") / \(.name) [\(.albumName//"?")]"' || true
  ;;
loudness | mono)
  state outputs "$opt" "$arg"
  ;;
mute)
  state levels mute "$arg"
  ;;
volume)
  if [[ $arg == - ]]; then
    query levels '."volume"//empty'
  elif [[ $arg =~ ^([+-]?)([0-9]{1,3})$ ]] && ((BASH_REMATCH[2] <= 100)); then
    [[ -n ${BASH_REMATCH[1]} ]] && arg=$(query levels "[.volume|tonumber${BASH_REMATCH[0]},0,100]|sort|.[1]")
    call "levels?volume=$arg" PUT
  else
    error 201
  fi
  ;;
lightTheme)
  state userinterface lightTheme "$arg" 3
  ;;
position)
  state outputs position "$arg" 3
  ;;
info)
  info
  ;;
system/capabilities | levels | network | nowplaying | outputs | power | system | update)
  if [[ -z $arg ]]; then
    query "$opt" 'to_entries[5:][]|select(.key!="cpu"and.key!="children")|"\(.key)=\(.value)"'
  elif [[ $arg =~ ^[[:alnum:]]{3,24}$ ]]; then
    query "$opt" ".\"$arg\"//empty" || true
  else
    error 200
  fi
  ;;
help)
  usage
  ;;
*)
  error 202
  ;;
esac

exit
