#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BASE=http://${MUSO_IP:-mu-so}:15081
# --no-iri avoids charset conversion in the C locale
WGET=(wget -q --no-config --no-netrc --no-hsts --no-cookies --no-proxy --no-iri --max-redirect=0 -4 -T2 -U '' -t1)

# jq: reply(f) filters one JSON value; missing/invalid/multiple values or filter errors exit 5 silently.
# sealed(f): reply on raw JSON followed by NUL and reader status 0.
# int/num: integer/number or 0; some: drop null/empty; ctl/rec: strip C0/C1 controls (string/recursive).
# safe: ctl for any type, rec only for C1 (jq -r escapes C0/DEL in JSON); line: fold breaks, strip controls.
# kv: key=value line; val: printable value, booleans as text; desc(t): "artist / title [album]", t is the title.
# Unused defs cost nothing; callers append only the sanitizer their output needs.
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
  : "${EPOCHREALTIME=0}" # Bash <5: avoid set -u failure; timing stays 0
  readonly _ERT=${EPOCHREALTIME/./}
  set -x
}

# Report and exit - <code> [uri]
error() {
  local msg

  case $1 in
  4) msg='Network failure, Mu-so offline?' ;;
  8) msg="Server error on ${2-request}, Mu-so in standby?" ;;
  200) msg='Missing or invalid option.' ;;
  201) msg='Missing or invalid argument.' ;;
  202) msg='Invalid response from Mu-so.' ;;
  *) msg="Unexpected wget error $1." ;;
  esac

  printf '%s\n' "$msg" >&2
  exit "$1"
}

# <uri> [method] [output]; explicit output uses exec (pipe only); C locale speeds startup
http() {
  LC_ALL=C ${3+exec} "${WGET[@]}" --method="${2:-GET}" -O "${3:-/dev/null}" "$BASE/$1" || error $? "${1%%[?]*}"
}

# Number within max; sets BASH_REMATCH - <arg> <max>
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

now() {
  local rc

  # Piping to show starts the HTTP client a fork sooner
  http nowplaying GET - | jq -nre "${JQP}reply("'[desc(.title),(.transportPosition|int),(.duration|int),
    (.codec|some)//.mimeType,(.sampleRate|num/1000),(.bitDepth|int),(.bitRate|num/1000),
    (.sourceDetail|some)//.source]|map(if.==null or.==""then"UNKNOWN"else. end)|@sh|line)' | show || {
    rc=("${PIPESTATUS[@]}")
    ((rc[0])) && error "${rc[0]}" nowplaying
    ((rc[1])) && error 202
    return "${rc[2]}"
  }
}

# Fetch JSON; exit on error, return 4 on no output - <uri> <filter ending in sanitizer> [jq args]
query() {
  local rc uri=$1 filter=$2

  # Bash 3.2 joins "${@:3}" under this IFS
  shift 2
  http "$uri" GET - | jq -nre "${JQP}reply($filter)" "$@" || {
    rc=("${PIPESTATUS[@]}")
    ((rc[0])) && error "${rc[0]}" "$uri"
    case ${rc[1]} in 1 | 2 | 3 | 5) error 202 ;; 4) return 4 ;; esac
    exit "${rc[1]}"
  }
}

# List or start inputs; mark nowplaying's source - [index]
inputs() {
  local f='.selectable=="1"and.disabled!="1"'

  if [[ -z $1 ]]; then
    # Fetch nowplaying concurrently; failure leaves inputs unmarked.
    # fd 3 keeps Bash 3.2 from closing the substitution before query runs.
    exec 3< <(http nowplaying GET -)
    query inputs "(try(\$n|fromjson|.source)catch null)as\$s|[.children[]?|select($f)]|to_entries[]|
      \"\\(.key+1))\\(if\$s!=null and.value.ussi==\$s then\" >\"else\"\"end) \\(.value.name)\"|line" --rawfile n /dev/fd/3 || :
  else
    list inputs "$f" "$1"
  fi
}

# List or jump to playqueue track - [index]
queue() {
  if [[ -z $1 ]]; then
    query inputs/playqueue '[.children[]?+{c:.current}]|to_entries[]|
      "\(.key+1))\(if.value.c!=null and.value.ussi==.value.c then" >"else""end) \(.value|desc(.name))"|line' || :
  else
    ussi inputs/playqueue true "$1" 'inputs/playqueue?current=\(.)' PUT
  fi
}

# Fetch JSON, request URI from filter; no URI exits [code] or 0 - <uri> <filter> <method> [code]
relay() {
  local rc

  # Start both clients together; jq supplies the second's URL only for replies sealed with status 0
  {
    LC_ALL=C "${WGET[@]}" -O - "$BASE/$1" && rc=0 || rc=$?
    printf '\0%d' "$rc"
    exit "$rc"
  } | jq -Rrse --arg b "$BASE" "${JQP}sealed($2|\"\\(\$b)/\\(.)\")" |
    LC_ALL=C "${WGET[@]}" --method="$3" -O /dev/null -i - || {
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
    relay "$1" "((.\"$2\"|tonumber?|select(.>=0 and .<=$4))//(\"\"|halt_error(5))|floor)as\$v|
      \"$1?$2=\\([\$v${BASH_REMATCH[0]},0,$4]|sort|.[1])\"" PUT
  fi
}

# Format nowplaying's @sh word list from stdin
show() {
  local LC_ALL=C aFields bits=0 codec='' dur pos rate=0 tsv

  # Empty input: now reports fetch failures
  read -r -d '' tsv || [[ -n $tsv ]] || return 0
  eval "aFields=($tsv)"

  # Spotify: try player API for codec, depth and bit rate on UNKNOWN codec or FLAC without bit rate
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

usage() {
  local nm=${0##*/}

  printf '%s\n' "$nm 11.1 - Control Naim Mu-so 2nd generation over HTTP
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

# Resolve index to ussi, then request - <uri> <filter> <index> <uri, ussi as \(.)> <method>
ussi() {
  [[ $3 =~ ^[1-9][0-9]?$ ]] || error 201
  relay "$1" "[.children[]?|select($2)][$3-1].ussi|some|
    if type==\"string\"and test(\"\\\\A[[:alnum:]/:._~-]+\\\\z\")then\"$4\"else\"\"|halt_error(5)end" "$5" 201
}

# <ussi> <key>
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

# No-argument options
case $opt in
'' | -h | --help | artwork | clear | description | help | next | now | play | playpause | prev | standby | stop | wake)
  (($# < 2)) || error 201
  ;;
esac

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
  inputs "$arg"
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
    query "$opt" 'del(.version,.changestamp,.name,.ussi,.class,.cpu,.children)|to_entries[]|kv' || :
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
