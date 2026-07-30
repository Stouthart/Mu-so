#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

[[ ${1-} == --xdbg ]] && { # Bash >= v5.0
  shift
  PS4='+\e[5G\e[36m$(((${EPOCHREALTIME/./}-_ERT)/1000))\e[9G\e[33m$LINENO\e[13G\e[90m>\e[15G\e[m'
  declare -ir _ERT=${EPOCHREALTIME/./}
  set -x
}

BASE="http://${MUSO_IP:-mu-so}:15081"

# HTTP request - <uri> [method]
call() {
  local out=-
  [[ -t 1 ]] && out=/dev/null
  curl -q4fsm2 --noproxy '*' --http1.1 --tcp-fastopen \
    -HUser-Agent: -X"${2:-GET}" -o "$out" "$BASE/$1" || error $?
}

# Print error and exit - <code>
error() {
  case $1 in
  1) echo 'Invalid response from Mu-so.' ;;
  6 | 7 | 52 | 56) echo 'Network failure, Mu-so offline?' ;;
  22) echo 'Server error, Mu-so in standby?' ;;
  28) echo 'Operation timeout.' ;;
  200) echo 'Missing or invalid argument.' ;;
  201) echo 'Missing or invalid option.' ;;
  202) echo 'Invalid response from Mu-so.' ;;
  *) echo "Unexpected curl error $1." ;;
  esac >&2

  exit "$1"
}

# Show now playing info
info() {
  local arr sec tsv i

  tsv=$(query nowplaying '[.artistName,.title,.albumName,.transportPosition//0,.duration//0,
    .codec,(.sampleRate//0|tonumber/1000),.bitDepth//0,(.bitRate//0|tonumber|if.<16000then. else./1000|round end),
    .sourceDetail//(.source//"?"|sub("^inputs/";""))]|map(if.==null or.==""then"?"else. end)|@tsv')
  read -ra arr <<<"$tsv"

  for i in 3 4; do
    printf -v sec '%02d' $(((arr[i] / 1000) % 60))
    arr[i]=$((arr[i] / 60000)):$sec
  done

  printf '%s / %s [%s]\n%s / %s - %s %skHz %dbit %dkb/s [%s]\n' "${arr[@]}"
}

# List or play items - <ussi> <filter> [index]
list() {
  if [[ -z $3 ]]; then
    query "$1" "[.children[]|select($2)]|to_entries[]|\"\\(.key+1)) \\(.value.name)\"" || :
  elif [[ $3 =~ ^[1-9][0-9]?$ ]]; then
    local ussi
    ussi=$(query "$1" "[.children[]|select($2)][$3-1].ussi//empty") || error 200
    play "$ussi"
  else
    error 200
  fi
}

# Get, set or adjust (±) value - <ussi> <key> <arg> <max>
number() {
  if [[ -z $3 ]]; then
    value "$1" "$2"
  elif signed "$3" "$4"; then
    local val=${BASH_REMATCH[2]}
    [[ -z ${BASH_REMATCH[1]} ]] || val=$(query "$1" "[.\"$2\"|tonumber${BASH_REMATCH[1]}$val,0,$4]|sort|.[1]")
    call "$1?$2=$val" PUT
  else
    error 200
  fi
}

# Play item - <ussi>
play() { call "$1?cmd=play"; }

# JSON request, exits on wget error - <ussi> <filter>
query() {
  call "$1" | jq -cre "$2" || {
    set -- "${PIPESTATUS[@]}"
    (($1 == 0)) || exit "$1"

    case $2 in 2 | 3 | 5) error 202 ;; esac
    return "$2"
  }
}

# Seek to position (±relative) - <sec>
seek() {
  if signed "$1" 3600; then
    local tsv
    local -i dur pos val=$((BASH_REMATCH[2] * 1000))

    tsv=$(query nowplaying '[.transportPosition//0,.duration//0]|@tsv')
    read -r pos dur <<<"$tsv"
    ((dur)) || return 0

    case ${BASH_REMATCH[1]} in
    +) ((val += pos)) || : ;;
    -) ((val = pos - val)) || : ;;
    esac

    ((val = val < 0 ? 0 : val >= dur ? dur - 1 : val)) || :
    call "nowplaying?cmd=seek&position=$val"
  else
    error 200
  fi
}

# Numeric, optionally signed? Sets BASH_REMATCH - <arg> <max>
signed() {
  [[ $1 =~ ^([+-]?)(0|[1-9][0-9]{0,3})$ && ${BASH_REMATCH[2]} -le $2 ]]
}

# Get single JSON value - <ussi> <key>
value() { query "$1" ".\"$2\"//empty"; }

# Usage instructions
usage() {
  local nm=${0##*/}

  cat <<EOF
$nm v8.1 - Control Naim Mu-so 2 over HTTP
Copyright (C) 2026 Stouthart. All rights reserved.

Usage: $nm <option> [argument]

Power:
  sleep | wake

Inputs:
  inputs | stations
  qobuz | spotify | tidal

Playback:
  info | next | pause | play | prev | stop
  seek <sec> | shuffle | repeat

Playqueue:
  clear | queue

Audio:
  loudness | mono | mute | volume <0..100>

Other:
  lighting | max | position | timeout <0..120>

Information:
  capabilities | levels | network | nowplaying
  outputs | power | poweramp | system | update

Numeric arguments accept a relative value (e.g. volume +5, seek -30).
Information options accept a key (e.g. levels volume).
EOF
}

opt=${1-}
arg=${2-}
(($# < 3)) || error 200

# Option aliases
case $opt in
capabilities) opt=system/capabilities ;;
pause) opt=playpause ;;
poweramp) opt=outputs/poweramp ;;
esac

# Main dispatcher
case $opt in
sleep | standby)
  call power?system=lona PUT
  ;;
wake)
  call power?system=on PUT
  ;;
inputs)
  list inputs '.disabled=="0"' "$arg"
  ;;
radio | stations)
  list favourites?sort=D:presetID '.stationKey!=null' "$arg"
  ;;
qobuz | spotify | tidal)
  play "inputs/$opt"
  ;;
next | play | playpause | prev | stop)
  call "nowplaying?cmd=$opt"
  ;;
seek)
  seek "$arg"
  ;;
shuffle)
  number nowplaying shuffle "$arg" 1
  ;;
repeat)
  number nowplaying repeat "$arg" 2
  ;;
clear)
  call inputs/playqueue?clear=true POST
  ;;
queue | playqueue)
  query inputs/playqueue '.children[]?|"\(.artistName//"?") / \(.name) [\(.albumName//"?")]"' || :
  ;;
loudness | mono)
  number outputs "$opt" "$arg" 1
  ;;
mute)
  number levels mute "$arg" 1
  ;;
vol | volume)
  number levels volume "$arg" 100
  ;;
lighting | lightTheme)
  number userinterface lightTheme "$arg" 2
  ;;
max | maxVolume)
  number outputs/poweramp maxVolume "$arg" 100
  ;;
position)
  number outputs position "$arg" 2
  ;;
timeout | standbyTimeout)
  number power standbyTimeout "$arg" 120
  ;;
info)
  info
  ;;
system/capabilities | levels | network | nowplaying | outputs | power | outputs/poweramp | system | update)
  if [[ -z $arg ]]; then
    query "$opt" 'to_entries[5:][]|select(.key!="cpu"and.key!="children")|"\(.key)=\(.value)"'
  elif [[ $arg =~ ^[[:alnum:]]{3,24}$ ]]; then
    value "$opt" "$arg" || :
  else
    error 200
  fi
  ;;
'' | -h | --help | help)
  usage
  ;;
*)
  error 201
  ;;
esac

exit
