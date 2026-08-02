<!-- v8.2 - Copyright © 2026 Stouthart. All rights reserved. -->

# Control Naim Mu-so 2nd generation over HTTP

A small Bash script that controls a **Naim Mu-so 2** from the command line, over your local network. It talks to the speaker's built-in HTTP API on port `15081` — no app, no cloud, no account. Handy for shell aliases, Apple Shortcuts, Stream Deck buttons, Home Assistant `shell_command`, or a cron job that puts the speaker to sleep at midnight.

Two interchangeable versions are included:

| Script        | Uses   | Best for                                                |
| ------------- | ------ | ------------------------------------------------------- |
| `msc.sh`      | `wget` | Linux, and macOS with Homebrew `wget` (slightly faster) |
| `msc-curl.sh` | `curl` | macOS and Git Bash on Windows (`curl` is preinstalled)  |

Both take the same options and behave identically — pick whichever tool you already have.

## Requirements

- **Bash** 3.2 or newer (the version macOS ships is fine)
- **jq** — see [Installing jq](#installing-jq)
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

Numeric options print the current value when called without an argument, and accept a **relative** value prefixed with `+` or `-`. Write numbers without leading zeros — `volume 8`, not `volume 08`. Information options accept a key to print a single field.

### Power

| Option  | Description                                   |
| ------- | --------------------------------------------- |
| `sleep` | Put the speaker in standby (alias: `standby`) |
| `wake`  | Turn the speaker on                           |

### Inputs

| Option         | Description                                                 |
| -------------- | ----------------------------------------------------------- |
| `inputs [n]`   | List available inputs, or select input _n_                  |
| `stations [n]` | List radio favourites, or play station _n_ (alias: `radio`) |
| `qobuz`        | Switch to the Qobuz input                                   |
| `spotify`      | Switch to the Spotify input                                 |
| `tidal`        | Switch to the Tidal input                                   |

### Playback

| Option                    | Description                                 |
| ------------------------- | ------------------------------------------- |
| `info`                    | Show formatted now playing information      |
| `play` / `pause` / `stop` | Transport control                           |
| `next` / `prev`           | Skip track                                  |
| `seek <sec>`              | Seek to a position in seconds, or ±relative |
| `shuffle [0\|1]`          | Get or set shuffle                          |
| `repeat [0..2]`           | Get or set repeat                           |

### Playqueue

| Option  | Description                                     |
| ------- | ----------------------------------------------- |
| `queue` | List the current playqueue (alias: `playqueue`) |
| `clear` | Empty the playqueue                             |

### Audio

| Option            | Description                      |
| ----------------- | -------------------------------- |
| `volume [0..100]` | Get or set volume (alias: `vol`) |
| `mute [0\|1]`     | Get or set mute                  |
| `loudness [0\|1]` | Get or set loudness              |
| `mono [0\|1]`     | Get or set mono                  |

### Other

| Option             | Description                               |
| ------------------ | ----------------------------------------- |
| `lighting [0..2]`  | Get or set the light theme                |
| `max [0..100]`     | Get or set the power amp maximum volume   |
| `position [0..2]`  | Get or set room compensation              |
| `timeout [0..120]` | Get or set the standby timeout in minutes |

### Information

Print all fields, or a single field when given a key.

| Option         | Description                     |
| -------------- | ------------------------------- |
| `capabilities` | System capabilities             |
| `levels`       | Volume, mute and related levels |
| `network`      | Network status                  |
| `nowplaying`   | Raw now playing data            |
| `outputs`      | Output settings                 |
| `power`        | Power state and standby timeout |
| `poweramp`     | Power amp settings              |
| `system`       | System and firmware details     |
| `update`       | Firmware update status          |

`help` — or no arguments at all — prints the built-in usage screen.

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

msc.sh inputs                # list the enabled inputs
msc.sh spotify               # switch straight to Spotify

msc.sh seek 90               # jump to 1:30
msc.sh seek +30              # skip forward half a minute
msc.sh next                  # next track

msc.sh info
# Nick Cave & The Bad Seeds / Red Right Hand [Let Love In]
# 1:23 / 6:11 - FLAC 44.1kHz 16bit 1004kb/s [Qobuz]

msc.sh levels volume         # single field -> 40
msc.sh system                # every field as key=value
msc.sh timeout 30            # standby after 30 minutes idle
msc.sh sleep                 # goodnight
```

Useful shell aliases:

```bash
alias vol='msc-curl.sh volume'
alias np='msc-curl.sh info'
```

## Installing jq

`jq` parses the JSON the speaker returns, and is the script's only real dependency.

### macOS

With [Homebrew](https://brew.sh) — the easy route, and it gets you `wget` too:

```bash
brew install jq
brew install wget          # only needed for msc.sh
```

Without Homebrew, `jq` is a single self-contained binary you can drop into your `PATH`. Download the build for your Mac from the [jq releases page](https://github.com/jqlang/jq/releases) — `jq-macos-arm64` for Apple Silicon, `jq-macos-amd64` for Intel:

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

- **[Git for Windows](https://git-scm.com/download/win)** — includes Git Bash and `curl`, so use `msc-curl.sh`
- **WSL** (`wsl --install`) — a full Linux environment with both `wget` and `curl`

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

| Code                                     | Meaning                                              |
| ---------------------------------------- | ---------------------------------------------------- |
| `0`                                      | Success                                              |
| `4` (wget) / `6`, `7`, `52`, `56` (curl) | Network failure — speaker offline or wrong address   |
| `8` (wget) / `22` (curl)                 | Server error — the speaker is probably in standby    |
| `28`                                     | Operation timed out (curl only)                      |
| `200`                                    | Missing or invalid argument                          |
| `201`                                    | Missing or invalid option                            |
| `202` / `1` (curl)                       | The speaker returned something that isn't valid JSON |

## Debugging

Pass `--xdbg` as the very first argument to trace execution with per-line timings. Requires Bash 5.0 or newer:

```bash
./msc.sh --xdbg volume +5
```

## Notes

- The API is undocumented and unofficial. It may change with a firmware update.
- Requests are plain HTTP on the local network; there is no authentication.
- Waking from standby takes a few seconds — a command issued immediately after `wake` may still report a server error.

## License

Copyright © 2026 Stouthart. All rights reserved.

_The scripts in this repository are free for personal use. However, they are NOT published under a software license. This implies - as stated in the [GitHub Docs] - that standard copyright law applies, meaning the owner retains all rights to the source code and no one may reproduce, distribute, or create derivative works from this work._

[GitHub Docs]: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
