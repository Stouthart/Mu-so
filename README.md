<!-- v9.2 - Copyright (c) 2025-2026 Stouthart. All rights reserved. -->

# Control Naim Mu-so 2nd generation over HTTP

A small Bash script that controls a **Naim Mu-so 2** from the command line, over your local network. It talks to the speaker's built-in HTTP API on port `15081` - no app, no cloud, no account. Handy for shell aliases, Apple Shortcuts, Stream Deck buttons, Home Assistant `shell_command`, or a cron job that puts the speaker in standby at midnight.

Two interchangeable versions are included:

| Script        | Uses   | Best for                                                |
| ------------- | ------ | ------------------------------------------------------- |
| `msc.sh`      | `wget` | Linux, and macOS with Homebrew `wget` (slightly faster) |
| `msc-curl.sh` | `curl` | macOS and Git Bash on Windows (`curl` is preinstalled)  |

Both take the same options and behave identically - pick whichever tool you already have.

## Requirements

- **Bash** 3.2 or newer (the version macOS ships is fine)
- **jq** - see [Installing jq](#installing-jq)
- **wget** (for `msc.sh`) or **curl** (for `msc-curl.sh`)
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

## Usage

```
msc.sh <option> [argument]
```

Numeric options print the current value when called without an argument, and accept a **relative** value prefixed with `+` or `-`. Write numbers without leading zeros - `volume 8`, not `volume 08`. Information options accept a key to print a single field.

Options that only act - `wake`, `play`, `volume 40` - print nothing at all, whether to a terminal or into a pipe; the exit code tells you whether they worked.

### Power

| Option           | Description                                               |
| ---------------- | --------------------------------------------------------- |
| `sleep [0..120]` | Show the sleep timer, set it in minutes, or cancel it (0) |
| `standby`        | Put the speaker in standby                                |
| `wake`           | Turn the speaker on                                       |

A bare `sleep` prints `sleepActive` and `sleepPeriod` (the period in seconds). The timer takes whole minutes only - unlike the other numeric options it does not accept a relative `+` or `-` value. It is a one-off countdown, unrelated to the idle standby timeout set with `timeout`.

### Inputs

| Option            | Description                                 |
| ----------------- | ------------------------------------------- |
| `inputs [1..n]`   | List selectable inputs, or select input _n_ |
| `stations [1..n]` | List radio favourites, or play station _n_  |

`inputs` lists the inputs the speaker reports as selectable and not disabled, numbered from 1. The numbering follows that list, so it shifts if you enable or disable an input in the Naim app. Services the speaker doesn't mark selectable - Qobuz and Tidal, typically - are not listed and cannot be selected this way; use `qobuz` or `tidal` to inspect their state.

`stations` lists the radio favourites in the order you added them, oldest first, so adding one appends it to the end and leaves the existing numbers alone. Lists print in full, but the index you pass back tops out at 99.

### Playback

| Option                    | Description                                     |
| ------------------------- | ----------------------------------------------- |
| `now`                     | Show formatted now playing info (alias: `info`) |
| `play` / `pause` / `stop` | Transport control                               |
| `next` / `prev`           | Skip track                                      |
| `seek [0..3600]`          | Get the position in seconds, or seek to it      |
| `shuffle [0..1]`          | Get or set shuffle                              |
| `repeat [0..2]`           | Get or set repeat                               |

`now` prints artist, title and album on the first line, and position, duration, format, sample rate, bit depth, bit rate and source on the second. Fields the speaker leaves empty show as `?`. When it reports no codec - on HDMI, typically - the format is taken from the stream's MIME type instead, so `audio/mpeg` reads as `MPEG`. Bit rate is read as bits per second and printed in kb/s.

### Playqueue

| Option         | Description                                                   |
| -------------- | ------------------------------------------------------------- |
| `queue [1..n]` | List the playqueue, or jump to track _n_ (alias: `playqueue`) |
| `clear`        | Empty the playqueue                                           |

The queue is numbered from 1, and the current track is marked with a leading `▶`. `queue 5` makes track 5 the current one, so playback continues from there.

### Audio

| Option            | Description                      |
| ----------------- | -------------------------------- |
| `volume [0..100]` | Get or set volume (alias: `vol`) |
| `mute [0..1]`     | Get or set mute                  |
| `loudness [0..1]` | Get or set loudness              |
| `mono [0..1]`     | Get or set mono                  |

### Other

| Option             | Description                                      |
| ------------------ | ------------------------------------------------ |
| `lighting [0..2]`  | Get or set the light theme                       |
| `maxvol [0..100]`  | Get or set the power amp maximum volume          |
| `roomcomp [0..2]`  | Get or set room compensation (alias: `position`) |
| `timeout [0..120]` | Get or set the standby timeout in minutes        |

### Information

Print all fields, or a single field when given a key.

| Option         | Description                                      |
| -------------- | ------------------------------------------------ |
| `bluetooth`    | Bluetooth name, pairing and connection state     |
| `capabilities` | System capabilities                              |
| `hdmi`         | HDMI input state                                 |
| `levels`       | Volume, mute and related levels                  |
| `network`      | Network status                                   |
| `nowplaying`   | Raw now playing data                             |
| `outputs`      | Output settings                                  |
| `power`        | Power state and standby timeout                  |
| `poweramp`     | Power amp settings                               |
| `qobuz`        | Qobuz input state                                |
| `spotify`      | Spotify input state                              |
| `system`       | System and firmware details                      |
| `tidal`        | Tidal input state                                |
| `update`       | Firmware update status                           |
| `wired`        | Ethernet interface details                       |
| `wireless`     | Wi-Fi interface details, signal and link quality |

Housekeeping keys the API repeats on every node (`version`, `changestamp`, `name`, `ussi`, `class`, `cpu`, `children`) are left out; everything else the node returns is printed as `key=value`.

`help` - or no arguments at all - prints the built-in usage screen.

## Examples

```bash
msc.sh wake                  # turn the speaker on
msc.sh volume                # -> 32
msc.sh volume 40             # set volume to 40
msc.sh volume +5             # five louder
msc.sh volume -10            # and back down
msc.sh mute 1                # mute
msc.sh mute                  # -> 1

msc.sh stations              # 1) NPO Radio 2
                             # 2) BBC Radio 6 Music
                             # 3) FIP
msc.sh stations 2            # play BBC Radio 6 Music

msc.sh inputs                # 1) HDMI
                             # 2) Internet Radio
                             # 3) Spotify
                             # 4) Playqueue
msc.sh inputs 3              # switch to Spotify

msc.sh seek                  # -> 83
msc.sh seek 90               # jump to 1:30
msc.sh seek +30              # skip forward half a minute
msc.sh next                  # next track

msc.sh queue                 # 1) ▶ Nick Cave / Red Right Hand [Let Love In]
                             # 2) Portishead / Roads [Dummy]
msc.sh queue 2               # jump to Roads

msc.sh now
# Nick Cave & The Bad Seeds / Red Right Hand [Let Love In]
# 1:23 / 6:11 - FLAC 44.1kHz 16bit 1004kb/s [Qobuz]

msc.sh levels volume         # single field -> 40
msc.sh system                # every field as key=value
msc.sh system hostCpuTemp    # -> 4319 (43.2 degrees)
msc.sh wireless              # Wi-Fi signal, link quality, SSID
msc.sh timeout 30            # standby after 30 minutes idle

msc.sh sleep 45              # standby in 45 minutes
msc.sh sleep                 # -> sleepActive=1
                             #    sleepPeriod=2700
msc.sh sleep 0               # cancel the sleep timer
msc.sh standby               # goodnight
```

Useful shell aliases:

```bash
alias vol='msc-curl.sh volume'
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

| Code                                           | Meaning                                                       |
| ---------------------------------------------- | ------------------------------------------------------------- |
| `0`                                            | Success                                                       |
| `4` (wget) / `6`, `7`, `28`, `52`, `56` (curl) | Network failure - speaker offline, timed out or wrong address |
| `8` (wget) / `22` (curl)                       | Server error - the speaker is probably in standby             |
| `200`                                          | Missing or invalid argument                                   |
| `201`                                          | Missing or invalid option                                     |
| `202`                                          | The speaker returned something that isn't valid JSON          |

## Debugging

Pass `--xdbg` as the very first argument to trace execution with per-line timings. Requires Bash 5.0 or newer:

```bash
./msc.sh --xdbg volume +5
```

## Notes

- The API is undocumented and unofficial. It may change with a firmware update.
- Requests are plain HTTP on the local network; there is no authentication.
- Waking from standby takes a few seconds - a command issued immediately after `wake` may still report a server error.

## License

Copyright © 2025-2026 Stouthart. All rights reserved.

_The scripts in this repository are free for personal use. However, they are NOT published under a software license. This implies - as stated in the [GitHub Docs] - that standard copyright law applies, meaning the owner retains all rights to the source code and no one may reproduce, distribute, or create derivative works from this work._

[GitHub Docs]: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
