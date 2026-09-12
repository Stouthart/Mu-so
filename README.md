<!-- 10.5 - Copyright (C) 2025-2026 Stouthart. All rights reserved. -->

# Control Naim Mu-so 2nd generation over HTTP

A small Bash script that controls a **Naim Mu-so 2** from the command line, over your local network. It talks to the speaker's built-in HTTP API on port `15081` - and, for the format of a Spotify lossless stream, its player API on port `80` - no app, no cloud, no account. Handy for shell aliases, Apple Shortcuts, Stream Deck buttons, or Home Assistant `shell_command`.

Two interchangeable versions are included:

| Script        | Uses   | Best for                                                |
| ------------- | ------ | ------------------------------------------------------- |
| `msc.sh`      | `wget` | Linux, and macOS with Homebrew `wget` (slightly faster) |
| `msc-curl.sh` | `curl` | macOS and Git Bash on Windows (`curl` is preinstalled)  |

Both take the same options and behave identically - pick whichever tool you already have.

This is **version 10.5**, and it is the version to start from. The [release notes](RELEASE.md) record how the scripts got here; the upgrade warnings in them apply to earlier copies, so there is nothing there to act on if you are new.

## Requirements

- **Bash** 3.2 or newer (the version macOS ships is fine)
- **jq** - see [Installing jq](#installing-jq)
- **GNU Wget** 1.19.2 or newer (for `msc.sh`) or **curl** (for `msc-curl.sh`) - BusyBox `wget` is not compatible
- A Naim Mu-so 2 reachable on your network

## Installation

```bash
git clone https://github.com/Stouthart/Mu-so.git
cd Mu-so
chmod +x msc.sh msc-curl.sh
```

Optionally put it on your `PATH` under a shorter name:

```bash
sudo install -m 755 msc-curl.sh /usr/local/bin/msc
```

## Configuration

The script looks for the host name `mu-so` by default. If that doesn't resolve, set `MUSO_IP` to your speaker's IP address or host name:

```bash
export MUSO_IP=192.168.1.42        # or: mu-so.local
```

Add that line to your `~/.zshrc` or `~/.bashrc` to make it permanent. To find the address, check your router's client list or the Naim app under **Settings → About**.

An IP address is also the quickest of the three: it skips name resolution entirely, where `mu-so` and `mu-so.local` cost a lookup on every request. Reserve the address in your router first, so the speaker keeps it.

## Usage

```
msc.sh <option> [argument]
```

Numeric options print the current value when called without an argument, and accept a **relative** value prefixed with `+` or `-` - `sleep` being the one exception. Write numbers without leading zeros - `vol 8`, not `vol 08`. Information options accept a key to print a single field.

Options that only act - `wake`, `play`, `vol 40` - print nothing at all, whether to a terminal or into a pipe; the exit code tells you whether they worked. An option that takes no argument rejects one instead of ignoring it, so `stop now` fails rather than stopping.

Ranges written as `0..n` are settings; ranges written as `1..n` are positions in a list.

### Power

| Option                 | Description                                               |
| ---------------------- | --------------------------------------------------------- |
| `autostandby [0..120]` | Get or set the idle standby timeout in minutes            |
| `sleep [0..120]`       | Show the sleep timer, set it in minutes, or cancel it (0) |
| `standby`              | Put the speaker in standby                                |
| `wake`                 | Turn the speaker on                                       |

`autostandby` is the Naim app's **Auto Standby Time**, the number of minutes of inactivity after which the speaker puts itself into standby (long-form alias: `standbyTimeout`).

A bare `sleep` prints `sleepActive` and `sleepPeriod` (the period in seconds). The timer takes whole minutes only - unlike the other numeric options it does not accept a relative `+` or `-` value. It is a one-off countdown, unrelated to the idle standby timeout set with `autostandby`.

### Inputs

| Option             | Description                                    |
| ------------------ | ---------------------------------------------- |
| `inputs [1..n]`    | List selectable inputs, or select input _n_    |
| `playlists [1..n]` | List playlist favourites, or play playlist _n_ |
| `stations [1..n]`  | List radio favourites, or play station _n_     |

`inputs` lists the inputs the speaker reports as selectable and not disabled, numbered from 1. The numbering follows that list, so it shifts if you enable or disable an input in the Naim app. Services the speaker doesn't mark selectable - Qobuz and Tidal, typically - are not listed and cannot be selected this way; use `qobuz` or `tidal` to inspect their state.

`playlists` and `stations` both read the favourites list, each filtered to its own kind: the favourites whose class ends in `Playlist` - the playlists you saved from a streaming service or a UPnP server - and the radio favourites. Passing an index plays that entry, the same way `stations 2` starts a station.

Both list their favourites in the order you added them, oldest first, so adding one appends it to the end and leaves the existing numbers alone. Deleting one, on the other hand, renumbers everything after it. Lists print in full, but the index you pass back tops out at 99.

### Playback

| Option                    | Description                                |
| ------------------------- | ------------------------------------------ |
| `now`                     | Show formatted now playing info            |
| `artwork`                 | Show the artwork URL for the current track |
| `description`             | Show the description of the current track  |
| `play` / `pause` / `stop` | Transport control                          |
| `next` / `prev`           | Skip track                                 |
| `seek [0..3599]`          | Get the position in seconds, or seek to it |
| `shuffle [0..1]`          | Get or set shuffle                         |
| `repeat [0..2]`           | Get or set repeat                          |

`now` prints artist, title and album on the first line, and position, duration, format, sample rate, bit depth, bit rate and source on the second. Fields the speaker leaves empty are dropped from the first line rather than filled with a placeholder, so a track with no album prints as `Artist / Title`, and one with no artist as the bare title. On radio, where there is no album, the station name is printed in the brackets instead.

On the second line, a format or source the speaker doesn't report shows as `UNKNOWN`. When it reports no codec - on HDMI, typically - the format is taken from the stream's MIME type instead, with the `audio/` prefix stripped, so `audio/mpeg` reads as `mpeg` and `audio/x-flac` as `x-flac`. Bit rate is read as bits per second and printed in kb/s, unrounded, so a stream can read `320.5kb/s`.

Spotify lossless streams are the exception the speaker's API gets wrong: it reports them as `UNKNOWN CODEC`, or as `FLAC` with a bit rate of 0. When `now` sees either, it asks the speaker's player API on port `80` - a second, read-only request - for the codec, the bit depth when it is 24-bit, and the bit rate, so a 24-bit track reads `FLAC 0kHz 24bit 1675.81kb/s`. Neither API reports Spotify's sample rate, so that stays `0kHz`. Any other source makes the extra request only in those same two cases, and if port `80` doesn't answer, the line is printed as the main API gave it.

`description` prints the description embedded in the comments of the track that is playing - the show notes, which on a podcast is often the full tracklist. When there is nothing to show, `description` prints nothing and succeeds. Carriage returns and the other control characters in that text (the C0 controls, DEL and the C1 range U+0080 to U+009F) are stripped - line breaks and tabs survive here, so a tracklist keeps its shape - and the text pastes cleanly into a terminal or a pipe. That stripping applies to every option, not just this one: any text arriving from the speaker is cleaned the same way. Where the output is one entry per line - the numbered lists, `queue`, `sleep` and the `key=value` information output - a line break inside a name or value is folded to a space as well, so an entry can never spill onto a second line. `description` covers the current track only - there is no per-entry equivalent for the playqueue.

`artwork` prints the URL of the current track's artwork - an image the speaker serves itself, or the streaming service's own link - so it can be opened straight away, with `open -u "$(msc.sh artwork)"` on macOS. With no artwork to show it prints nothing and succeeds.

A bare `seek` prints the position in whole seconds. To move, pass either a number of seconds or a `min:sec` position - `seek 219` and `seek 3:39` are the same jump - and either form takes a relative `+` or `-`, so `seek +30` skips forward half a minute and `seek -1:30` rewinds a minute and a half. Both top out just under the hour, at `3599` and `59:59`; `seek 3600` is rejected. In the `min:sec` form the seconds are always two digits (`3:09`, not `3:9`), while the minutes may be written either way.

A target past the end of the track is clamped to just short of it, and one before the start to `0`, so `seek -600` rewinds to the beginning rather than failing. Seeking when nothing is playing does nothing and succeeds: with no duration to seek within, the request is not sent at all.

### Playqueue

| Option         | Description                                                   |
| -------------- | ------------------------------------------------------------- |
| `queue [1..n]` | List the playqueue, or jump to track _n_ (alias: `playqueue`) |
| `clear`        | Empty the playqueue                                           |

The queue is numbered from 1, and the current track is marked with a leading `>`. `queue 5` makes track 5 the current one, so playback continues from there. Entries are laid out like the first line of `now`, missing fields and all: an entry the speaker gives no album for is printed without the trailing brackets.

### Audio

| Option            | Description                         |
| ----------------- | ----------------------------------- |
| `vol [0..100]`    | Get or set volume (alias: `volume`) |
| `mute [0..1]`     | Get or set mute                     |
| `loudness [0..1]` | Get or set loudness                 |
| `mono [0..1]`     | Sum both channels to mono           |

`loudness` is the Naim app's **Loudness** switch: it boosts the low frequencies at lower volumes. Note that `capabilities` may report `supportsLoudness=0` while the key on `outputs` is nonetheless live and writable.

### Other

| Option              | Description                                      |
| ------------------- | ------------------------------------------------ |
| `autoswitch [0..2]` | Get or set HDMI auto switching                   |
| `lighting [0..2]`   | Get or set the lighting level                    |
| `lipsync [0..50]`   | Get or set the HDMI audio delay                  |
| `maxvol [0..100]`   | Get or set the power amp maximum volume          |
| `pairing [0..1]`    | Get or set Bluetooth open pairing                |
| `roomcomp [0..2]`   | Get or set room compensation (alias: `position`) |

`maxvol` is the app's **Max Volume**, the upper limit of the volume control - useful to keep a stray `vol 100` from shaking the room.

`lipsync` is the app's **Lip Sync**, under the HDMI input's settings - not **Auto Lip Sync**, which is a separate automatic correction: it delays the audio to line it up with the picture on a TV connected over HDMI. It writes the `delay` key on the HDMI input, in milliseconds, in the same 0..50 steps the app's slider uses, so it applies to that input only (long-form alias: `delay`).

`pairing 1` is the app's **Open pairing**: with it enabled any Bluetooth device can connect without first having to put the speaker into pairing mode, and `pairing 0` closes it again. It writes the `open` key on the Bluetooth input (long-form alias: `open`); `bluetooth` reports it back next to the device name and the connection state.

`lighting` is the app's **Lighting**, which adjusts the level of the Mu-so illumination (long-form alias: `lightTheme`, the key the API uses).

`autoswitch` controls whether the speaker selects the HDMI input by itself when the TV starts sending audio (long-form alias: `autoSwitching`). Use `hdmi` to see the input's state, including the value `autoswitch` and `lipsync` write.

#### roomcomp - Room Compensation

The app's **Room position**: it configures room compensation, adjusting the sound to compensate for the room characteristics, which can noticeably improve the bass.

| Value | Label       | Meaning                                                                         |
| ----- | ----------- | ------------------------------------------------------------------------------- |
| `0`   | Normal      | Mu-so is positioned 25cm or more away from a wall                               |
| `1`   | Near wall   | Optimal when the Mu-so is positioned close to a wall (less than 25cm)           |
| `2`   | Near corner | Optimal when the Mu-so is positioned near the corner of a room (less than 45cm) |

#### autoswitch - HDMI Auto Switching

Chooses when the speaker should respond to a connected TV powering on and off.

| Value | Label         | Meaning                                                                         |
| ----- | ------------- | ------------------------------------------------------------------------------- |
| `0`   | Off           | Mu-so will not power on or switch to the HDMI input in response to the TV       |
| `1`   | On HDMI input | Mu-so will power on and off in response to the TV if the HDMI input is selected |
| `2`   | On any input  | Mu-so will always power on or switch to the HDMI input in response to the TV    |

This only takes effect when the TV powers on or off, so changing it produces no immediately observable result.

### Information

Print all fields, or a single field when given a key.

| Option         | Description                                                          |
| -------------- | -------------------------------------------------------------------- |
| `bluetooth`    | Bluetooth name, pairing and connection state                         |
| `capabilities` | System capabilities                                                  |
| `hdmi`         | HDMI input state                                                     |
| `levels`       | Volume, mute and related levels                                      |
| `network`      | Network status                                                       |
| `nowplaying`   | Raw now playing data                                                 |
| `outputs`      | Output settings                                                      |
| `power`        | Power state and standby timeout                                      |
| `poweramp`     | Power amp settings                                                   |
| `qobuz`        | Qobuz input state                                                    |
| `spotify`      | Spotify input state                                                  |
| `system`       | System and firmware details                                          |
| `tidal`        | Tidal input state                                                    |
| `update`       | Firmware update status                                               |
| `wifi`         | Wi-Fi interface details, signal and link quality (alias: `wireless`) |
| `wired`        | Ethernet interface details                                           |

Housekeeping keys the API repeats on every node (`version`, `changestamp`, `name`, `ussi`, `class`, `cpu`, `children`) are left out; everything else the node returns is printed as `key=value`.

`help` - or no arguments at all - prints the built-in usage screen. `-h` and `--help` do the same. Like the other options that take no argument, all three reject a stray one, so `help stop` fails rather than printing the usage.

## Examples

```bash
msc.sh wake                  # turn the speaker on
msc.sh vol                   # -> 32
msc.sh vol 40                # set volume to 40
msc.sh vol +5                # five louder
msc.sh vol -10               # and back down
msc.sh mute 1                # mute
msc.sh mute                  # -> 1

msc.sh stations              # 1) NPO Radio 2
                             # 2) BBC Radio 6 Music
                             # 3) FIP
msc.sh stations 2            # play BBC Radio 6 Music

msc.sh playlists             # 1) Sunday Morning
                             # 2) Late Night Jazz
msc.sh playlists 1           # play Sunday Morning

msc.sh inputs                # 1) HDMI
                             # 2) Internet Radio
                             # 3) Spotify
                             # 4) Playqueue
msc.sh inputs 3              # switch to Spotify

msc.sh seek                  # -> 83
msc.sh seek 90               # jump to 1:30
msc.sh seek 1:30             # the same jump, written as min:sec
msc.sh seek +30              # skip forward half a minute
msc.sh seek -1:30            # and back a minute and a half
msc.sh next                  # next track

msc.sh queue                 # 1) > Nick Cave / Red Right Hand [Let Love In]
                             # 2) Portishead / Roads [Dummy]
msc.sh queue 2               # jump to Roads

msc.sh description           # the episode's tracklist, if Naim has it
msc.sh artwork               # https://i.scdn.co/image/ab67616d...
msc.sh clear                 # empty the queue

msc.sh now
# Nick Cave & The Bad Seeds / Red Right Hand [Let Love In]
# 1:23 / 6:11 - FLAC 44.1kHz 16bit 1004kb/s [Qobuz]

msc.sh now                   # Spotify lossless: format from the player API
# Ezra Collective / Blow Your Trumpet [Here Because of Hope]
# 0:25 / 4:20 - FLAC 0kHz 24bit 1675.81kb/s [spotify]

msc.sh now                   # on radio, the station fills the brackets
# Kate Bush / Running Up That Hill [NPO Radio 2]

msc.sh levels volume         # single field -> 40
msc.sh system                # every field as key=value
msc.sh system hostCpuTemp    # -> 4319 (43.2 degrees)
msc.sh wifi                  # Wi-Fi signal, link quality, SSID
msc.sh autostandby 30        # standby after 30 minutes idle
msc.sh lipsync 12            # delay the HDMI audio
msc.sh autoswitch            # -> 1
msc.sh roomcomp 1            # the speaker sits close to a wall

msc.sh pairing 1             # open for Bluetooth pairing
msc.sh bluetooth             # btName, btConnectState, open, ...
msc.sh pairing 0             # close it again

msc.sh sleep 45              # standby in 45 minutes
msc.sh sleep                 # -> sleepActive=1
                             #    sleepPeriod=2700
msc.sh sleep 0               # cancel the sleep timer
msc.sh standby               # goodnight
```

Useful shell aliases:

```bash
alias vol='msc-curl.sh vol'
alias np='msc-curl.sh now'
```

## Installing jq

`jq` parses the JSON the speaker returns, and is the script's only real dependency.

### macOS

With [Homebrew](https://brew.sh) - the easy route, and it gets you `wget` too:

```bash
brew install jq
brew install wget          # only needed for msc.sh
```

Without Homebrew, `jq` is a single self-contained binary you can drop into your `PATH`. Download the build for your Mac from the [jq releases page](https://github.com/jqlang/jq/releases) - `jq-macos-arm64` for Apple Silicon, `jq-macos-amd64` for Intel:

```bash
curl -Lo jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-arm64
chmod +x jq
xattr -d com.apple.quarantine jq      # clear the Gatekeeper flag
sudo mv jq /usr/local/bin/
jq --version                          # -> jq-1.7.1
```

On very old macOS (10.6–10.11) use an older release such as jq 1.6, where the asset is named `jq-osx-amd64`.

### Windows

Bash isn't native to Windows, so first install one of:

- **[Git for Windows](https://git-scm.com/download/win)** - includes Git Bash and `curl`, so use `msc-curl.sh`
- **WSL** (`wsl --install`) - a full Linux environment with both `wget` and `curl`

Then install `jq` from PowerShell with a package manager:

```powershell
winget install jqlang.jq
```

```powershell
scoop install jq            # or: choco install jq
```

Or manually: download `jq-windows-amd64.exe` from the [releases page](https://github.com/jqlang/jq/releases), rename it to `jq.exe`, and put it in a folder that is on your `PATH` (for example `C:\Users\<you>\bin`).

Inside WSL, install it the Linux way instead:

```bash
sudo apt install jq
```

## Exit codes

| Code                                                 | Meaning                                                                                 |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `0`                                                  | Success                                                                                 |
| `4` (wget) / `6`, `7`, `18`, `28`, `52`, `56` (curl) | Network failure - speaker offline, timed out, wrong address or reply cut off            |
| `8` (wget) / `22`, `47` (curl)                       | Server error - the speaker is probably in standby                                       |
| `200`                                                | Missing or invalid option                                                               |
| `201`                                                | Missing or invalid argument                                                             |
| `202`                                                | The speaker returned nothing, invalid JSON, more than one JSON value, or an empty value |

Redirects are refused rather than followed: the API never issues one, so a redirect means the reply did not come from the speaker. Both report it as a server error: `msc.sh` exits `8`, `msc-curl.sh` `47`.

## Debugging

Pass `--xdbg` as the very first argument to trace execution with per-line timings. The trace runs on any Bash the scripts support; the millisecond column needs Bash 5.0 or newer and reads `0` below it:

```bash
./msc.sh --xdbg vol +5
```

## Notes

- The API is undocumented and unofficial. It may change with a firmware update.
- Requests are plain HTTP on the local network; there is no authentication. Anything on the same network can control the speaker.
- Waking from standby takes a few seconds - a command issued immediately after `wake` may still report a server error.

### Device quirks

Behaviour worth knowing about before you build anything on top of these scripts:

- **A `200` response does not mean the write was applied.** The speaker silently discards read-only keys when they are mixed with writable ones, and still answers `200`. Verify by reading the value back.
- **Reads lag behind writes**, sometimes by several seconds. Volume, seek position, queue position and favourite state all keep reporting the old value for a moment, so a read-back issued immediately after a write will mislead you.
- **The device can be overwhelmed** by rapid API calls. The warning signs are the `network` node going hollow and `inputs/radio` returning 503. Recovery needs a power cycle - a standby/wake cycle in that state only makes it worse. Space out loops and polling.
- `stations` and `playlists` fetch roughly 80 KB each, because the speaker offers no server-side filter for favourites and ignores `Accept-Encoding: gzip`. Filtering happens locally, in `jq`.

## Credits

Setting names and descriptions are quoted from the Focal & Naim iOS/macOS app's own localisation file, so the wording here matches what you see in the app.

## License

Copyright (C) 2025-2026 Stouthart. All rights reserved.

_The scripts in this repository are free for personal use. However, they are NOT published under a software license. This implies - as stated in the [GitHub Docs] - that standard copyright law applies, meaning the owner retains all rights to the source code and no one may reproduce, distribute, or create derivative works from this work._

[GitHub Docs]: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
