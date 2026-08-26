#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

[[ ${1-} == --xdbg ]] && { # Bash >= 5.0
  shift
  PS4='+\e[5G\e[36m$(((${EPOCHREALTIME/./}-_ERT+500)/1000))\e[9G\e[33m$LINENO\e[13G\e[90m>\e[15G\e[m'
  readonly _ERT=${EPOCHREALTIME/./}
  set -x
}

BASE=http://${MUSO_IP:-mu-so}:15081

# Format "artist / title [album]" - <title-key>
DESC='def desc(t):[([.artistName,t]-[null,""]|join(" / ")),(.albumName//.station|select(.>"")|"[\(.)]")]|join(" ");'

# Replace the playqueue with a URL and start it - <url>
add() {
  local mime name

  [[ $1 =~ ^https?://[^[:space:]]+\.[[:alnum:]]{2,4}$ ]] || error 201
  name=${1##*/} name=${name%.*}
  printf -v name '%b' "${name//\*/\\x}" # Display name only - minimServer escapes bytes as *XX

  case $1 in
  *.aif | *.aiff) mime=audio/x-aiff ;;
  *.dff) mime=audio/x-dff ;;
  *.dsf) mime=audio/x-dsf ;;
  *.flac) mime=audio/x-flac ;;
  *.m4a) mime=audio/mp4 ;;
  *.wav) mime=audio/x-wav ;;
  *) mime=audio/mpeg ;;
  esac

  http 'inputs/playqueue?where=end&clear=true&current=0&play=true' POST /dev/null "$(jq -cn --arg n "${name//_/ }" \
    --arg t "$mime" --arg u "$1" '[{class:"object.track.upnp",name:$n,mimeType:$t,uri:$u}]')"
}

# Print error and exit - <code>
error() {
  local msg

  case $1 in
  6 | 7 | 28 | 52 | 56) msg='Network failure, Mu-so offline?' ;;
  22) msg='Server error, Mu-so in standby?' ;;
  200) msg='Missing or invalid option.' ;;
  201) msg='Missing or invalid argument.' ;;
  202) msg='Invalid response from Mu-so.' ;;
  *) msg="Unexpected curl error $1." ;;
  esac

  printf '%s\n' "$msg" >&2
  exit "$1"
}

# HTTP request - <uri> [method] [output] [body]
http() {
  curl -q -s --noproxy '*' -4 --tcp-fastopen -m2 -HUser-Agent: -f \
    -X"${2:-GET}" -o "${3:-/dev/null}" ${4:+-d"$4"} "$BASE/$1" || error $?
}

# Valid number within max? Sets BASH_REMATCH - <arg> <max>
isnum() {
  [[ $1 =~ ^([+-]?)(0|[1-9][0-9]{0,3})$ && ${BASH_REMATCH[2]} -le $2 ]]
}

# List or start items - <uri> <filter> [index]
list() {
  if [[ -z $3 ]]; then
    query "$1" "[.children[]?|select($2)]|to_entries[]|\"\\(.key+1)) \\(.value.name)\"" || :
  elif [[ $3 =~ ^[1-9][0-9]?$ ]]; then
    local ussi
    ussi=$(query "$1" "[.children[]?|select($2)][$3-1].ussi//\"\"") || exit $?
    [[ -n $ussi ]] || error 201
    http "$ussi?cmd=play"
  else
    error 201
  fi
}

# Show now playing info
now() {
  local aFields i sec tsv

  tsv=$(query nowplaying "$DESC"'[desc(.title),(.transportPosition|tonumber?)//0,(.duration|tonumber?)//0,
    .codec//.mimeType,(.sampleRate|tonumber?)//0,(.bitDepth|tonumber?)//0,(.bitRate|tonumber?)//0,
    .sourceDetail//.source]|map(if.==null or.==""then"UNKNOWN"else. end)|@tsv')
  read -ra aFields <<<"$tsv"

  for i in 1 2; do
    printf -v sec '%02d' $(((aFields[i] / 1000) % 60))
    aFields[i]=$((aFields[i] / 60000)):$sec
  done

  aFields[3]=${aFields[3]#audio/}
  aFields[4]+=e-3 aFields[6]+=e-3
  aFields[7]=${aFields[7]#inputs/}
  printf '%s\n%s / %s - %s %gkHz %dbit %gkb/s [%s]\n' "${aFields[@]}"
}

# Fetch JSON, exit on error - <uri> <filter>
query() {
  local json rc
  json=$(http "$1" GET -) || exit $?

  jq -re "$2" <<<"$json" || {
    rc=$?
    case $rc in 2 | 3 | 5) error 202 ;; esac
    return $rc
  }
}

# List or jump to playqueue track - [index]
queue() {
  if [[ -z $1 ]]; then
    query inputs/playqueue "$DESC"'[.children[]?+{c:.current}]|to_entries[]|["\(.key+1))",
      (select(.value.ussi==.value.c)|">"),(.value|desc(.name))]|join(" ")' || :
  elif [[ $1 =~ ^[1-9][0-9]?$ ]]; then
    local ussi
    ussi=$(query inputs/playqueue "[.children[]?][$1-1].ussi//\"\"") || exit $?
    [[ -n $ussi ]] || error 201
    http "inputs/playqueue?current=$ussi" PUT
  else
    error 201
  fi
}

# Get or seek position (±) - [sec | min:sec]
seek() {
  local dur pos tsv val

  if [[ -z $1 ]]; then
    query nowplaying '((.transportPosition|tonumber?)//0)/1000|floor'
    return
  elif isnum "$1" 3599; then
    val=${BASH_REMATCH[2]}
  elif [[ $1 =~ ^([+-]?)([0-5]?[0-9]):([0-5][0-9])$ ]]; then
    val=$((10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]}))
  else
    error 201
  fi

  tsv=$(query nowplaying '[(.transportPosition|tonumber?)//0,(.duration|tonumber?)//0]|@tsv')
  read -r pos dur <<<"$tsv"
  ((dur)) || return 0
  val=$((val * 1000))

  case ${BASH_REMATCH[1]} in
  +) ((val += pos)) || : ;;
  -) ((val = pos - val)) || : ;;
  esac

  ((val = val < 0 ? 0 : val >= dur ? dur - 1 : val)) || :
  http "nowplaying?cmd=seek&position=$val"
}

# Get, set or adjust (±) a setting - <ussi> <key> [arg] <max>
setting() {
  if [[ -z $3 ]]; then
    value "$1" "$2" || error 202
  elif isnum "$3" "$4"; then
    local val=${BASH_REMATCH[2]}
    [[ -z ${BASH_REMATCH[1]} ]] || val=$(query "$1" "[((.\"$2\"|tonumber?)//0)${BASH_REMATCH[0]},0,$4]|sort|.[1]")
    http "$1?$2=$val" PUT
  else
    error 201
  fi
}

# Get, set (min) or cancel (0) sleep timer - [arg]
timer() {
  if [[ -z $1 ]]; then
    query alarms 'to_entries[]|select(.key|startswith("sleep"))|"\(.key)=\(.value)"'
  elif isnum "$1" 120 && [[ -z ${BASH_REMATCH[1]} ]]; then
    local min=${BASH_REMATCH[2]}
    if ((min)); then
      http "alarms?sleepPeriod=$((min * 60))&cmd=sleep"
    else
      http alarms?cmd=cancelSleep
    fi
  else
    error 201
  fi
}

# Show usage
usage() {
  local nm=${0##*/}

  cat <<EOF
$nm v10.2 - Control Naim Mu-so 2nd generation over HTTP
Copyright (C) 2025-2026 Stouthart. All rights reserved.

Usage: $nm <option> [argument]

Power:
  autostandby 0..120 | sleep 0..120 | standby | wake

Inputs:
  inputs 1..n | playlists 1..n | stations 1..n

Playback:
  next | notes | now | pause | play | prev | stop
  repeat 0..2 | seek 0..3599 | shuffle 0..1

Playqueue:
  add URL | clear | queue 1..n

Audio:
  loudness 0..1 | mono 0..1 | mute 0..1 | vol 0..100

Other:
  autoswitch 0..2 | lighting 0..2 | lipsync 0..50
  maxvol 0..100 | pairing 0..1 | roomcomp 0..2

Information:
  bluetooth | capabilities | hdmi | levels | network | nowplaying | outputs
  power | poweramp | qobuz | spotify | system | tidal | update | wired | wireless

Omit the argument to read the current value.
Numeric settings accept a relative value (e.g. vol +5, seek -30), except sleep.
Seek also accepts a min:sec position or offset (e.g. 3:39, -1:30).
Add replaces the playqueue with an escaped URL and starts it.
Information options accept a key (e.g. levels volume).
EOF
}

# Get single JSON value - <ussi> <key>
value() { query "$1" ".\"$2\"//empty"; }

(($# < 3)) || error 201
opt=${1-}
arg=${2-}

# Option aliases
case $opt in
pause)
  opt=playpause
  ;;
bluetooth | hdmi | qobuz | spotify | tidal)
  opt=inputs/$opt
  ;;
capabilities)
  opt=system/capabilities
  ;;
poweramp)
  opt=outputs/poweramp
  ;;
wired | wireless)
  opt=network/$opt
  ;;
esac

# Main dispatcher
case $opt in
autostandby | standbyTimeout)
  setting power standbyTimeout "$arg" 120
  ;;
sleep)
  timer "$arg"
  ;;
standby)
  http power?system=lona PUT
  ;;
wake)
  http power?system=on PUT
  ;;
inputs)
  list inputs '.selectable=="1"and.disabled!="1"' "$arg"
  ;;
playlists)
  list favourites?sort=A:timeStamp '.favouriteClass//""|endswith("Playlist")' "$arg"
  ;;
stations)
  list favourites?sort=A:timeStamp '.stationKey!=null' "$arg"
  ;;
next | play | playpause | prev | stop)
  http "nowplaying?cmd=$opt"
  ;;
notes | description)
  query nowplaying '.description//empty|gsub("\r";"")' || :
  ;;
now)
  now
  ;;
repeat)
  setting nowplaying repeat "$arg" 2
  ;;
seek)
  seek "$arg"
  ;;
shuffle)
  setting nowplaying shuffle "$arg" 1
  ;;
add)
  add "$arg"
  ;;
clear)
  http inputs/playqueue?clear=true POST
  ;;
queue | playqueue)
  queue "$arg"
  ;;
loudness | mono)
  setting outputs "$opt" "$arg" 1
  ;;
mute)
  setting levels mute "$arg" 1
  ;;
vol | volume)
  setting levels volume "$arg" 100
  ;;
autoswitch | autoSwitching)
  setting inputs/hdmi autoSwitching "$arg" 2
  ;;
lighting | lightTheme)
  setting userinterface lightTheme "$arg" 2
  ;;
lipsync | delay)
  setting inputs/hdmi delay "$arg" 50
  ;;
maxvol | maxVolume)
  setting outputs/poweramp maxVolume "$arg" 100
  ;;
pairing | open)
  setting inputs/bluetooth open "$arg" 1
  ;;
roomcomp | position)
  setting outputs position "$arg" 2
  ;;
inputs/bluetooth | system/capabilities | inputs/hdmi | levels | network | nowplaying | outputs | power | \
  outputs/poweramp | inputs/qobuz | inputs/spotify | system | inputs/tidal | update | network/wired | network/wireless)
  if [[ -z $arg ]]; then
    query "$opt" 'del(.version,.changestamp,.name,.ussi,.class,.cpu,.children)|to_entries[]|"\(.key)=\(.value)"'
  elif [[ $arg =~ ^[[:alnum:]]{3,24}$ ]]; then
    value "$opt" "$arg" || :
  else
    error 201
  fi
  ;;
'' | -h | --help | help)
  usage
  ;;
--dump)
  [[ $arg =~ ^[[:alnum:]/:_-]+$ ]] || error 201
  query "$arg" . || error 202
  ;;
*)
  error 200
  ;;
esac

exit
