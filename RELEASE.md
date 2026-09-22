<!-- 11.0 - Copyright (C) 2025-2026 Stouthart. All rights reserved. -->

# Release notes

Highlights per major version, newest first. Point releases are listed where they changed behaviour; releases marked _code improvements_ changed nothing a user would notice.

11.0 is the version distributed. Everything below it is how the scripts got there: the bold upgrade warnings in those entries concern copies of earlier versions, and there is nothing in them to act on if 11.0 is where you started.

## 11.0 - September 2026

The main focus is performance, and fixing the final safety and security issues - what the speaker sends back is now checked before the script acts on it. A regression that stopped 10.5 running on the Bash macOS ships is fixed along the way.

- **The scripts run on Bash 3.2 again.** 10.5 checked the options that take no argument with an extended glob - `@(-h|--help|artwork|...)` - inside `[[ ]]`. Bash 4.1 and newer enable that syntax there on their own; 3.2 does not, so it is a parse error, and the script dies on "syntax error in conditional expression" before it runs a single line. Every option was affected, on stock macOS and anywhere else without a newer Bash. The check is a `case` again. **Anyone who took 10.5 without a Homebrew Bash needs this release.**
- **Commands that make two requests are faster.** A relative setting such as `vol +5`, `seek`, and `inputs`, `playlists`, `stations` or `queue` with a number read from the speaker first and build the second request from the reply. The second `wget` or `curl` now starts alongside the first and takes its URL from `jq`, so its start-up - around 5 ms on a current Mac - overlaps the first request instead of following it. The write still waits for the whole reply: one cut short sends nothing, even when the part that did arrive is valid JSON. A server error on either request names the endpoint that was read - `levels` rather than `levels?volume=30`.
- Smaller savings elsewhere: `now` hands the reply straight to its formatting instead of capturing it first, so its request starts sooner; `help` prints without starting a separate program; and `wget` and `curl` run in the C locale, which spares them loading locale data on every request.
- **`now` prints `44.1kHz` under every locale, which 10.4 only half managed.** The figures were formatted by putting `LC_NUMERIC=C` in front of `printf`. `LC_ALL` in the environment outranks `LC_NUMERIC`, so a shell with `LC_ALL=de_DE.UTF-8` still read `44,1kHz` - and on Bash 3.2 the prefix never took effect at all, because that release does not reload the locale for an assignment made in front of a builtin. The locale is now set for the duration of the function, which both versions honour.
- **A relative setting no longer writes the offset on its own.** If the reply is missing the key, or holds something that is not a number, the current value read as `0`, so `vol +5` sent `volume=5` - a drop to near-silence from whatever was playing, reported as success. It is now "Invalid response from Mu-so.", exit 202, and nothing is written.
- **A relative setting no longer jumps to the limit on a current value it cannot trust.** `NaN`, `Infinity` or a number outside the setting's range was clamped like any other, so a reply of `Infinity` made `vol -5` write `volume=100`. It now reports 202 and writes nothing.
- **An identifier from the speaker is checked before it goes into a URL.** `inputs 1`, `stations 1`, `playlists 1` and `queue 1` look up the item's `ussi` and paste it into the next request. A `?` in that identifier silently restructured the query string - `cmd=play` became part of a value instead of a command, so the item was never played and the script still exited 0. Identifiers are now held to the characters the API uses, and anything else reports 202.
- A value the speaker returns as a JSON boolean prints and succeeds. `mute` and the information options printed `false` and then reported "Invalid response from Mu-so." with exit 202, because the value was correct but false.
- A reply the script cannot use reports "Invalid response from Mu-so." on its own; `jq`'s error message no longer comes first.
- A server error names the endpoint without its query string on every command, so `vol 25` reports `Server error on levels` rather than `levels?volume=25`.
- A number too large for Bash arithmetic no longer stops `now` and `seek`. A position or duration beyond the integer range reached the arithmetic in scientific notation and ended the command on a Bash error; out-of-range and negative figures now read as `0`, the way an unreadable one already did.
- `now` copes with a figure sent in scientific notation and a bit depth with a leading zero: `4.41E4` printed `0kHz` behind a `printf` error, and a Spotify bit depth of `08` a Bash arithmetic error.
- A line break inside a track title no longer makes `now` print three lines. 10.4 folded line breaks in the numbered lists, `queue`, `sleep` and the `key=value` output, but the `now` line was left out.
- An option that takes no argument rejects an empty one. `stop ""` ran, because the check asked whether the argument was empty rather than whether one was given.

## 10.x - August–September 2026

The scripts read line by line, and what comes back from the speaker treated as untrusted.

- **10.0** - **`lipsync` and `pairing` gained the long-form aliases `delay` and `open`**, each the name of the key it writes, so every option in the script now has one.
- **10.1** - **New `notes`** (later renamed `description`), printing the description embedded in the current track's comments - show notes, and on a podcast often the full tracklist. **A network failure while resolving `stations 2`, `playlists 1` or `queue 5` reports what actually went wrong**, instead of the lookup's subshell swallowing it and reporting 201.
- **10.2** - **`seek` takes a `min:sec` position as well as seconds**, so `seek 3:39` is `seek 219` and `seek -1:30` rewinds a minute and a half. **The upper bound became `3599`, where it was `3600`.**
- **10.3** - A full read-through of both scripts, with three models reading independently. **Options that take no argument reject one instead of ignoring it**, so `stop now` fails rather than stopping. Redirects are refused rather than followed. Control characters are stripped from the description, and information options take a key of 3 to 32 characters. **`msc-curl.sh` no longer passes `--tcp-fastopen`, which had been failing every request under Git Bash on Windows with "Unexpected curl error 4."**
- **10.4** - **Control characters are stripped from everything the speaker returns**, not just the description, and a line break inside a name no longer splits a listed entry across two lines. An empty reply reports 202 rather than printing nothing and succeeding, `help` rejects a stray argument, and `--xdbg` traces again on the later Bash 4 releases.
- **10.5** - **`now` shows the format of a Spotify lossless stream**, taking the codec, bit depth and bit rate from a second read-only request to the player API on port `80` where the main API reports `UNKNOWN CODEC`. New `artwork`, printing the current track's artwork URL. **`notes` became `description`**, the word the Naim app uses. A reply must be exactly one JSON value, and the C1 control characters are stripped alongside the C0 ones.

## 9.x - August 2026

More of the speaker readable, and option names that say what they do.

- **9.0** - **`qobuz`, `spotify` and `tidal` report their input's state instead of switching to it**; inputs are selected through `inputs 1..n`. New information options `bluetooth`, `wired` and `wireless`. **`max` became `maxvol`**, `position` became `roomcomp` and `info` became `now`. A bare `seek` prints the position, and information options print every field except the housekeeping keys.
- **9.1** - New `hdmi`. `now` takes the format from the MIME type when the speaker reports no codec, and bit rate is always read as bits per second.
- **9.2** - `queue 1..n` jumps to a track in the playqueue. **`radio` removed in favour of `stations`**, which now lists favourites oldest first, so the numbering changed.
- **9.3** - New `playlists`, `lipsync` and `autoswitch`. **The current track in `queue` is marked with `>`.**
- **9.4** - New `pairing`, the app's **Open pairing** switch.
- **9.5** - **`timeout` became `autostandby`, `info` was removed, and exit codes `200` and `201` swapped.** `now` and `queue` no longer pad missing fields with `?`, a radio station fills the album brackets, and `vol` became the documented name.

## 8.x - July–August 2026

Error handling done right, and a real sleep timer.

- **8.0** - Any failure stops the script with a meaningful exit code, an offline speaker is told apart from one in standby, and invalid JSON reports "Invalid response from Mu-so." No arguments or `-h` prints the usage screen, extra arguments are rejected, a station or input is resolved in a single request, and `wget` no longer reads `~/.netrc` or writes cookies.
- **8.1** - `seek 0` works again, and numbers with a leading zero are rejected.
- **8.3** - `info` falls back to zero for a field it can't read as a number, options that only act print nothing even in a pipe, a missing value exits 202, and a `curl` timeout counts as a network failure.
- **8.5** - **`sleep` became the speaker's sleep timer** (`sleep 45`, `sleep 0`, a bare `sleep` to report it); `standby` puts it in standby straight away.

## 7.x - May–July 2026

Naming cleanup and a more predictable `seek`.

- **7.0** - `standby` became `sleep`, with `standby` kept as an alias. Short and long names now both work throughout: `vol`/`volume`, `radio`/`stations`, `queue`/`playqueue`, `lighting`, `max`, `timeout`.
- **7.1** - `seek` rewritten: relative jumps are clamped to the track boundaries, and seeking is silently skipped on live streams with no duration.
- **7.2** - Fixed an error-handling bug that could mask a failed request.
- **7.3** - Faster failure reporting and a rewritten debug trace (`--xdbg`) with per-line timings.
- **7.4** - Leaner jq filters, fewer round trips.

## 6.x - March–May 2026

Streaming services in one word.

- **6.0** - Direct input selection: `qobuz`, `spotify` and `tidal` switch the speaker straight to that service.
- Radio favourites moved from `radio` to `stations`, and inputs from `input` to `inputs`, matching the plural listing they produce.
- The formatted `info` view became a documented, first-class command.
- **6.1–6.4** - Code improvements only.

## 5.x - November 2025–March 2026

The release that made the script scriptable.

- **5.0** - The interactive picker is gone. `stations` and `inputs` now print a numbered list, and `stations 2` plays an entry directly. Commands no longer block waiting for input, so they work from Shortcuts and Home Assistant.
- **5.0** - Unified error handling with distinct exit codes per failure type.
- **5.1** - `poweramp` reports the power amplifier settings.
- **5.2** - `max` sets the maximum volume, `timeout` sets the standby timeout in minutes.
- **5.5** - Toggling removed. A bare `mute`, `shuffle` or `loudness` now _reports_ the current value instead of flipping it; set it explicitly with `0` or `1`. Toggles made the result depend on unknown state, which is wrong in a script.

## 4.x - November 2025

First public release, and the one that made it run anywhere.

- **4.0** - Public release.
- **4.2** - `seek <sec>`, absolute or relative.
- **4.3** - Missing or empty values now count as a failure rather than printing nothing and reporting success.
- **4.4** - Faster requests by asking only for headers where the body isn't needed.
- **4.5** - Runs on Bash 3.2, the version macOS ships, so no Homebrew Bash required.
- **4.5** - `position` sets room compensation.
- **4.5** - The host override environment variable became `MUSO_IP` (previously `MUSO_HOST`).

## 3.x - October–November 2025

Values instead of toggles, and a second flavour of the script.

- **3.0** - Refactored, with proper error handling.
- **3.1** - Options can be set directly, e.g. `mute 1`, instead of only cycling.
- **3.2** - A second version added, so the script works with either `wget` or `curl` depending on what's installed. `msc.sh` became the `wget` variant and `msc-curl.sh` the `curl` one.
- **3.3** - Relative volume: `volume +5`, `volume -10`.
- **3.4** - Formatted now playing output: artist, title, album, position, duration, codec, sample rate, bit depth, bit rate and source.
- **3.5** - `capabilities` reports what the speaker supports.

## 2.x - October 2025

Complete rewrite of the first version.

- **2.1** - `shuffle`, `repeat` and `mute`.
- **2.3** - Human-readable error messages instead of raw `curl` exit codes.
- **2.5** - `loudness`, `mono` and the `lighting` level setting.
- The host override environment variable became `MUSO_HOST` (previously `NAIM_HOST`).

## 1.0 - October 2025

First version. Power, transport control, volume, and an interactive picker for inputs and radio presets, over plain HTTP with `curl` and `jq`.
