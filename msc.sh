#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

[[ ${1-} == --xdbg ]] && { # Bash >= v5.0
  shift
  PS4='+\e[5G\e[36m$(((${EPOCHREALTIME/./}-_ERT)/1000))\e[9G\e[33m$LINENO\e[13G\e[90m>\e[15G\e[m'
  readonly _ERT=${EPOCHREALTIME/./}
  set -x
}

BASE=http://${MUSO_IP:-mu-so}:15081

# HTTP request - <uri> [method] [output]
call() {
  wget --no-config --no-netrc --no-hsts --no-cookies --no-iri --no-proxy -4qt1 -T2 -U '' \
    --method="${2:-GET}" -O "${3:-/dev/null}" "$BASE/$1" || error $?
}

# Print error and exit - <code>
error() {
  case $1 in
  4) echo 'Network failure, Mu-so offline?' ;;
  8) echo 'Server error, Mu-so in standby?' ;;
  200) echo 'Missing or invalid argument.' ;;
  201) echo 'Missing or invalid option.' ;;
  202) echo 'Invalid response from Mu-so.' ;;
  *) echo "Unexpected wget error $1." ;;
  esac >&2

  exit "$1"
}

# Show now playing info
info() {
  local aFields sec tsv i

  tsv=$(query nowplaying '[.artistName,.title,.albumName,(.transportPosition|tonumber?)//0,(.duration|tonumber?)//0,
    .codec,((.sampleRate|tonumber?)//0)/1000,(.bitDepth|tonumber?)//0,
    ((.bitRate|tonumber?)//0|if.<16000then. else./1000|round end),
    .sourceDetail//(.source//"?"|ltrimstr("inputs/"))]|map(if.==null or.==""then"?"else. end)|@tsv')
  read -ra aFields <<<"$tsv"

  for i in 3 4; do
    printf -v sec '%02d' $(((aFields[i] / 1000) % 60))
    aFields[i]=$((aFields[i] / 60000)):$sec
  done

  printf '%s / %s [%s]\n%s / %s - %s %skHz %dbit %dkb/s [%s]\n' "${aFields[@]}"
}

# List or play items - <ussi> <filter> [index]
list() {
  if [[ -z $3 ]]; then
    query "$1" "[.children[]?|select($2)]|to_entries[]|\"\\(.key+1)) \\(.value.name)\"" || :
  elif [[ $3 =~ ^[1-9][0-9]?$ ]]; then
    local ussi
    ussi=$(query "$1" "[.children[]?|select($2)][$3-1].ussi//empty") || error 200
    start "$ussi"
  else
    error 200
  fi
}

# Get, set or adjust (±) value - <ussi> <key> <arg> <max>
number() {
  if [[ -z $3 ]]; then
    value "$1" "$2" || error 202
  elif signed "$3" "$4"; then
    local val=${BASH_REMATCH[2]}
    [[ -z ${BASH_REMATCH[1]} ]] || val=$(query "$1" "[((.\"$2\"|tonumber?)//0)${BASH_REMATCH[1]}$val,0,$4]|sort|.[1]")
    call "$1?$2=$val" PUT
  else
    error 200
  fi
}

# JSON request, exits on error - <ussi> <filter>
query() {
  call "$1" GET - | jq -cre "$2" || {
    set -- "${PIPESTATUS[@]}"
    (($1 == 0)) || exit "$1"

    case $2 in 2 | 3 | 5) error 202 ;; esac
    return "$2"
  }
}

# Get or seek to position (±relative) - [sec]
seek() {
  if [[ -z $1 ]]; then
    query nowplaying '((.transportPosition|tonumber?)//0)/1000|floor'
  elif signed "$1" 3600; then
    local tsv
    local -i dur pos val=$((BASH_REMATCH[2] * 1000))

    tsv=$(query nowplaying '[(.transportPosition|tonumber?)//0,(.duration|tonumber?)//0]|@tsv')
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

# Get, set (min) or cancel (0) sleep timer - <arg>
sleep() {
  if [[ -z $1 ]]; then
    query alarms 'to_entries[]|select(.key|startswith("sleep"))|"\(.key)=\(.value)"'
  elif signed "$1" 120 && [[ -z ${BASH_REMATCH[1]} ]]; then
    local min=${BASH_REMATCH[2]}
    if ((min)); then
      call "alarms?sleepPeriod=$((min * 60))&cmd=sleep"
    else
      call alarms?cmd=cancelSleep
    fi
  else
    error 200
  fi
}

# Start item - <ussi>
start() { call "$1?cmd=play"; }

# Usage instructions
usage() {
  local nm=${0##*/}

  cat <<EOF
$nm v9.0 - Control Naim Mu-so 2 over HTTP
Copyright (C) 2025-2026 Stouthart. All rights reserved.

Usage: $nm <option> [argument]

Power:
  sleep 0..120 | standby | wake

Inputs:
  inputs num | stations num

Playback:
  info | next | pause | play | prev | stop
  seek 0..3600 | shuffle 0..1 | repeat 0..2

Playqueue:
  clear | queue

Audio:
  loudness 0..1 | mono 0..1 | mute 0..1 | volume 0..100

Other:
  lighting 0..2 | maxvol 0..100 | roomcomp 0..2 | timeout 0..120

Information:
  bluetooth | capabilities | levels | network | nowplaying | outputs | power
  poweramp | qobuz | spotify | system | tidal | update | wired | wireless

Omit the argument to read the current value.
Numeric arguments accept a relative value (e.g. volume +5, seek -30).
Information options accept a key (e.g. levels volume).
EOF
}

# Get single JSON value - <ussi> <key>
value() { query "$1" ".\"$2\"//empty"; }

(($# < 3)) || error 200
opt=${1-}
arg=${2-}

# Option aliases
case $opt in
bluetooth) opt=inputs/bluetooth ;;
capabilities) opt=system/capabilities ;;
pause) opt=playpause ;;
poweramp) opt=outputs/poweramp ;;
qobuz) opt=inputs/qobuz ;;
spotify) opt=inputs/spotify ;;
tidal) opt=inputs/tidal ;;
wired) opt=network/wired ;;
wireless) opt=network/wireless ;;
esac

# Main dispatcher
case $opt in
sleep)
  sleep "$arg"
  ;;
standby)
  call power?system=lona PUT
  ;;
wake)
  call power?system=on PUT
  ;;
inputs)
  list inputs '.selectable=="1"and.disabled!="1"' "$arg"
  ;;
radio | stations)
  list favourites?sort=D:presetID '.stationKey!=null' "$arg"
  ;;
info)
  info
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
  query inputs/playqueue '[.children[]?+{c:.current}]|to_entries[]|
    "\(.key+1)) \(.value.artistName//"?") / \(.value.name) [\(.value.albumName//"?")]\(if
    .value.ussi==.value.c then" *"else""end)"' || :
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
maxvol | maxVolume)
  number outputs/poweramp maxVolume "$arg" 100
  ;;
roomcomp | position)
  number outputs position "$arg" 2
  ;;
timeout | standbyTimeout)
  number power standbyTimeout "$arg" 120
  ;;
inputs/bluetooth | system/capabilities | levels | network | nowplaying | outputs | power | outputs/poweramp | \
  inputs/qobuz | inputs/spotify | system | inputs/tidal | update | network/wired | network/wireless)
  if [[ -z $arg ]]; then
    query "$opt" 'del(.version,.changestamp,.name,.ussi,.class,.cpu,.children)|to_entries[]|"\(.key)=\(.value)"'
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
