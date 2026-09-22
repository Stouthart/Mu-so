#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# API base, and curl with the options every request shares
BASE=http://${MUSO_IP:-mu-so}:15081
CURL=(curl -q -s --noproxy '*' -4 -m2 -HUser-Agent: -f -L --max-redirs 0)

# jq preamble - reply: filter the one JSON value read; none, invalid JSON, more than one or a failing filter exits 5
# quietly - <filter>; sealed: reply on a raw read that ends in NUL and the reader's exit status, only when that is 0;
# int: whole number or 0, num: number or 0, some: drop null/empty;
# ctl: strip C0/C1 controls from a string, rec: ctl throughout, safe: ctl for any type (jq -r escapes C0 and DEL
# in JSON, so it walks only on C1); line: fold line breaks and strip controls, kv: key=value line;
# val: a value to print, booleans as text; desc: format "artist / title [album]" - <title-key>
# Unreferenced defs cost nothing; each caller appends only the sanitizer its output needs
JQP='def reply(f):try([inputs]|if length==1 then .[0] else error end|f)catch(""|halt_error(5));
def sealed(f):try(split("\u0000")|if length==2 and .[1]=="0" then .[0]|fromjson else error end|f)catch(""|halt_error(5));
def num:(tonumber?|select(.>=0 and .<9007199254740992))//0;
def int:num|floor;
def some:select(.!=null and .!="");
def ctl:gsub("[\\x00-\\x08\\x0b-\\x1f\u007f-\u009f]";"");
def rec:if type=="string"then ctl elif type=="array"then map(rec)elif type=="object"then with_entries(.key|=rec|.value|=rec)else. end;
def safe:if type=="string"then ctl elif(tojson|test("[\u0080-\u009f]"))then rec else. end;
def line:gsub("(?<l>\\x0a)|[\\x00-\\x08\\x0b-\\x1f\u007f-\u009f]";if.l then" "else""end);
def kv:"\(.key)=\(.value)"|line;
def val:some|if type=="boolean"then tostring else safe end;
def desc(t):[([.artistName,t]-[null,""]|join(" / ")),((.albumName|some)//(.station|some)|"[\(.)]")]|map(some)|join(" ");'

[[ ${1-} == --xdbg ]] && {
  shift
  PS4='+\e[5G\e[36m$(((${EPOCHREALTIME/./}-_ERT+500)/1000))\e[9G\e[33m$LINENO\e[13G\e[90m>\e[15G\e[m'
  : "${EPOCHREALTIME=0}" # Unset before bash 5: set -u aborts the strip below on bash 4; the timing column reads 0
  readonly _ERT=${EPOCHREALTIME/./}
  set -x
}

# Print error and exit - <code> [uri]
error() {
  local msg

  case $1 in
  6 | 7 | 18 | 28 | 52 | 56) msg='Network failure, Mu-so offline?' ;;
  22 | 47) msg="Server error on ${2-request}, Mu-so in standby?" ;;
  200) msg='Missing or invalid option.' ;;
  201) msg='Missing or invalid argument.' ;;
  202) msg='Invalid response from Mu-so.' ;;
  *) msg="Unexpected curl error $1." ;;
  esac

  printf '%s\n' "$msg" >&2
  exit "$1"
}

# Send HTTP request, exec'd with output (pipe only); curl starts faster in the C locale - <uri> [method] [output]
http() {
  LC_ALL=C ${3+exec} "${CURL[@]}" -X "${2:-GET}" -o "${3:-/dev/null}" "$BASE/$1" || error $? "${1%%[?]*}"
}

# Valid number within max? Sets BASH_REMATCH - <arg> <max>
isnum() {
  [[ $1 =~ ^([+-]?)(0|[1-9][0-9]{0,3})$ && ${BASH_REMATCH[2]} -le $2 ]]
}

# List or start items - <uri> <filter> [index]
list() {
  if [[ -z $3 ]]; then
    query "$1" "[.children[]?|select($2)]|to_entries[]|\"\\(.key+1)) \\(.value.name)\"|line" || :
  else
    ussi "$1" "$2" "$3" '\(.)?cmd=play' GET
  fi
}

# Show now playing info
now() {
  local rc

  # Piped into show rather than captured, so wget starts a fork sooner
  http nowplaying GET - | jq -nre "${JQP}reply("'[desc(.title),(.transportPosition|int),(.duration|int),
    (.codec|some)//.mimeType,(.sampleRate|num/1000),(.bitDepth|int),(.bitRate|num/1000),
    (.sourceDetail|some)//.source]|map(if.==null or.==""then"UNKNOWN"else. end)|@sh|line)' | show || {
    rc=("${PIPESTATUS[@]}")
    ((rc[0])) && error "${rc[0]}" nowplaying
    ((rc[1])) && error 202
    return "${rc[2]}"
  }
}

# Fetch JSON, exit on error; returns 4 when the filter prints nothing - <uri> <filter, ending in its sanitizer>
query() {
  local rc

  # Streamed, not captured
  http "$1" GET - | jq -nre "${JQP}reply($2)" || {
    rc=("${PIPESTATUS[@]}")
    ((rc[0])) && error "${rc[0]}" "$1"
    case ${rc[1]} in 1 | 2 | 3 | 5) error 202 ;; 4) return 4 ;; esac
    exit "${rc[1]}"
  }
}

# List or jump to playqueue track - [index]
queue() {
  if [[ -z $1 ]]; then
    query inputs/playqueue '[.children[]?+{c:.current}]|to_entries[]|
      "\(.key+1))\(if.value.ussi==.value.c then" >"else""end) \(.value|desc(.name))"|line' || :
  else
    ussi inputs/playqueue true "$1" 'inputs/playqueue?current=\(.)' PUT
  fi
}

# Fetch JSON and send the request to the uri its filter builds; no uri exits <code>, or 0 - <uri> <filter> <method> [code]
relay() {
  local rc

  # The second curl starts with the first and reads its URL from jq, silent when jq has none; jq takes the reply only when
  # it is sealed with status 0
  {
    LC_ALL=C "${CURL[@]}" -o - "$BASE/$1" && rc=0 || rc=$?
    printf '\0%d' "$rc"
    exit "$rc"
  } | jq -Rrse --arg b "$BASE" "${JQP}sealed($2|\"url=\\\"\\(\$b)/\\(.)\\\"\")" |
    LC_ALL=C "${CURL[@]}" -X"$3" -o /dev/null -K - 2>/dev/null || {
    rc=("${PIPESTATUS[@]}")
    ((rc[0])) && error "${rc[0]}" "$1"
    case ${rc[1]} in
    0) error "${rc[2]}" "$1" ;;
    4) ((${4-0})) && error "$4" || return 0 ;;
    esac
    error 202
  }
}

# Get or seek position (±) - [sec | min:sec]
seek() {
  local sign val

  if [[ -z $1 ]]; then
    query nowplaying '.transportPosition|int/1000|floor'
    return
  elif isnum "$1" 3599; then
    val=${BASH_REMATCH[2]} sign=${BASH_REMATCH[1]}
  elif [[ $1 =~ ^([+-]?)([0-5]?[0-9]):([0-5][0-9])$ ]]; then
    val=$((10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]})) sign=${BASH_REMATCH[1]}
  else
    error 201
  fi

  # Nothing to seek in without a duration
  relay nowplaying "(.duration|int)as\$d|select(\$d>0)|
    \"nowplaying?cmd=seek&position=\\([0,${sign:+(.transportPosition|int)$sign}$((val * 1000)),\$d-1]|sort|.[1])\"" GET
}

# Get, set or adjust (±) a setting - <ussi> <key> [arg] <max>
setting() {
  if [[ -z $3 ]]; then
    value "$1" "$2" || error 202
  elif ! isnum "$3" "$4"; then
    error 201
  elif [[ -z ${BASH_REMATCH[1]} ]]; then
    http "$1?$2=${BASH_REMATCH[2]}" PUT
  else
    relay "$1" "\"$1?$2=\\([((.\"$2\"|tonumber?|select(.>=0 and .<=$4))//(\"\"|halt_error(5))|floor)${BASH_REMATCH[0]},0,$4]|sort|.[1])\"" PUT
  fi
}

# Print now playing info from its @sh word list on stdin
show() {
  local LC_ALL=C aFields bits=0 codec='' dur pos rate=0 tsv

  # Nothing to read when the fetch failed; now reports it
  read -r -d '' tsv || [[ -n $tsv ]] || return 0
  eval "aFields=($tsv)"

  # Spotify: UNKNOWN CODEC, or FLAC without bit rate - take codec, depth and bit rate from the player API, best effort
  if [[ ${aFields[3]} == UNKNOWN* || ${aFields[3]} == FLAC && ${aFields[6]} == 0 ]]; then
    tsv=$(BASE=${BASE%:*}/api query "getData?path=player:player/data&roles=value" '.[0].trackRoles.mediaData|
      .resources[0]?|[(.codec|strings|capture("\\((?<c>[^()]+?)(?: (?<b>[0-9]+) ?bit)?\\)$"))//{},
      (.bitRate|int/1000)]|@sh "codec=\(.[0].c//"") bits=\(.[0].b|int) rate=\(.[1])"|line' 2>/dev/null) || tsv=
    eval "$tsv"

    [[ ${codec:-UNKNOWN} == UNKNOWN ]] || aFields[3]=$codec
    ((${bits:-0})) && aFields[5]=$bits || :
    [[ ${rate:-0} == 0 ]] || aFields[6]=$rate
  fi

  pos=$((aFields[1] / 1000 % 60 + 100)) dur=$((aFields[2] / 1000 % 60 + 100))
  aFields[1]=$((aFields[1] / 60000)):${pos#1} aFields[2]=$((aFields[2] / 60000)):${dur#1}

  aFields[3]=${aFields[3]#audio/}
  aFields[7]=${aFields[7]#inputs/}
  printf '%s\n%s / %s - %s %gkHz %dbit %gkb/s [%s]\n' "${aFields[@]}"
}

# Get, set (min) or cancel (0) sleep timer - [arg]
timer() {
  if [[ -z $1 ]]; then
    query alarms 'to_entries[]|select(.key|startswith("sleep"))|kv' || :
  elif isnum "$1" 120 && [[ -z ${BASH_REMATCH[1]} ]]; then
    local min=${BASH_REMATCH[2]}
    if ((min)); then
      http "alarms?sleepPeriod=$((min * 60))&cmd=sleep"
    else
      http 'alarms?cmd=cancelSleep'
    fi
  else
    error 201
  fi
}

# Show usage
usage() {
  local nm=${0##*/}

  printf '%s\n' "$nm 11.0 - Control Naim Mu-so 2nd generation over HTTP
Copyright (C) 2025-2026 Stouthart. All rights reserved.

Usage: $nm <option> [argument]

Power:
  autostandby 0..120 | sleep 0..120 | standby | wake

Inputs:
  inputs 1..n | playlists 1..n | stations 1..n

Playback:
  artwork | description | next | now | pause | play | prev | stop
  repeat 0..2 | seek 0..3599 | shuffle 0..1

Playqueue:
  clear | queue 1..n

Audio:
  loudness 0..1 | mono 0..1 | mute 0..1 | vol 0..100

Other:
  autoswitch 0..2 | lighting 0..2 | lipsync 0..50
  maxvol 0..100 | pairing 0..1 | roomcomp 0..2

Information:
  bluetooth | capabilities | hdmi | levels | network | nowplaying | outputs
  power | poweramp | qobuz | spotify | system | tidal | update | wifi | wired

Omit the argument to read the current value.
Numeric settings accept a relative value (e.g. vol +5, seek -30), except sleep.
Seek also accepts a min:sec position or offset (e.g. 3:39, -1:30).
Information options accept a key (e.g. levels volume)."
}

# Resolve item index to ussi and send a request with it - <uri> <filter> <index> <uri, ussi as \(.)> <method>
ussi() {
  [[ $3 =~ ^[1-9][0-9]?$ ]] || error 201
  relay "$1" "[.children[]?|select($2)][$3-1].ussi|some|
    if type==\"string\"and test(\"\\\\A[[:alnum:]/:._~-]+\\\\z\")then\"$4\"else\"\"|halt_error(5)end" "$5" 201
}

# Get single JSON value - <ussi> <key>
value() { query "$1" ".\"$2\"|val"; }

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
wifi | wired | wireless)
  opt=network/${opt/wifi/wireless}
  ;;
esac

# Options that take no argument
case $opt in
'' | -h | --help | artwork | clear | description | help | next | now | play | playpause | prev | standby | stop | wake)
  (($# < 2)) || error 201
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
  http 'power?system=lona' PUT
  ;;
wake)
  http 'power?system=on' PUT
  ;;
inputs)
  list inputs '.selectable=="1"and.disabled!="1"' "$arg"
  ;;
playlists)
  list 'favourites?sort=A:timeStamp' '.favouriteClass//""|endswith("Playlist")' "$arg"
  ;;
stations)
  list 'favourites?sort=A:timeStamp' '.stationKey!=null' "$arg"
  ;;
next | play | playpause | prev | stop)
  http "nowplaying?cmd=$opt"
  ;;
artwork | description)
  value nowplaying "$opt" || :
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
clear)
  http 'inputs/playqueue?clear=true' POST
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
    query "$opt" 'del(.version,.changestamp,.name,.ussi,.class,.cpu,.children)|to_entries[]|kv'
  elif [[ $arg =~ ^[[:alnum:]_-]{3,32}$ ]]; then
    value "$opt" "$arg" || :
  else
    error 201
  fi
  ;;
'' | -h | --help | help)
  usage
  ;;
--dump)
  [[ $arg =~ ^[[:alnum:]/:_-]{3,64}$ ]] || error 201
  query "$arg" val || error 202
  ;;
*)
  error 200
  ;;
esac

exit
