<!-- v9.0 - Copyright (c) 2025-2026 Stouthart. All rights reserved. -->

# Release notes

Highlights per major version, newest first. Point releases are listed where they changed behaviour; releases marked _code improvements_ changed nothing a user would notice.

## 9.0 - August 2026

More of the speaker readable, and option names that say what they do.

- **`qobuz`, `spotify` and `tidal` no longer switch the input.** They are now information options that report that input's state, in line with the other nodes. Input selection goes through the list instead - `inputs`, then `inputs 1..n`. **Aliases, cron jobs and Shortcuts that call `qobuz`, `spotify` or `tidal` to start playing must be changed**, or they will merely print a block of `key=value` lines. Note that only inputs the speaker marks as selectable are listed: Spotify is, Qobuz and Tidal are not, so for those two there is no direct replacement for the old shortcut.
- Six new information options: `bluetooth` (name, pairing and connection state), `qobuz`, `spotify`, `tidal`, and `wired` / `wireless` for the two network interfaces - signal level, link quality, SSID and the rest.
- **`max` is now `maxvol`, and `position` is now `roomcomp`.** `maxVolume` and `position` still work as long-form aliases, but a bare `max` is rejected with "Missing or invalid option." The old names read as an adjective and a playback position; the new ones name the setting.
- `info` is now `now`, which names the `nowplaying` node it reads rather than promising information in general - the other nodes are the ones that print information. `info` still works as an alias, so nothing breaks.
- A bare `seek` prints the current playback position in seconds, instead of failing with "Missing or invalid argument." Every numeric option now reads as well as writes.
- `queue` numbers its entries from 1 and marks the track that is playing with a trailing `*`, matching the numbered lists `inputs` and `stations` already print.
- Information options print every field the node returns, minus the housekeeping keys the API repeats everywhere (`version`, `changestamp`, `name`, `ussi`, `class`, `cpu`, `children`). Previously the first five entries were dropped by position, which hid real fields on nodes that order their keys differently, and let housekeeping keys through on the others.
- `inputs` lists what the speaker reports as selectable rather than merely not disabled, so the numbering no longer includes inputs that cannot be chosen.
- A relative adjustment (`volume +5`, `timeout -10`) no longer aborts when the speaker leaves the current value out of its reply or returns it as something that isn't a number; it counts as zero and the new value is set from there.
- `inputs` and `stations` no longer fail with "Invalid response from Mu-so." when the speaker leaves the list out of its reply altogether; they print nothing and succeed, as `queue` already did.
- Usage screen rewritten to show each option's accepted range, and the internal `play` helper renamed to `start` - _code improvements_.

## 8.5 - August 2026

`sleep` became a real sleep timer.

- `sleep` no longer puts the speaker in standby straight away. It now drives the speaker's built-in sleep timer: `sleep 45` sends it to standby in 45 minutes, `sleep 0` cancels a running timer, and a bare `sleep` reports whether one is set and for how long (`sleepActive`, `sleepPeriod` in seconds).
- `standby` - until now an alias for `sleep` - is the way to put the speaker in standby immediately. **Aliases, cron jobs and Shortcuts that call `sleep` for that must switch to `standby`**, or they will merely arm a timer.
- The timer accepts whole minutes from 0 to 120. Relative values (`sleep +10`) are rejected with "Missing or invalid argument."

## 8.3 - August 2026

A sturdier `info`, and commands that keep quiet.

- `info` no longer gives up when the speaker reports a field it can't make a number of. Position, duration, sample rate, bit depth and bit rate now fall back to zero instead of aborting the whole line with "Invalid response from Mu-so."
- Commands that only act - `wake`, `play`, `volume 40` - no longer dump the raw JSON reply when their output is redirected or piped. The response body was previously discarded only when writing to a terminal, so the same command behaved differently inside a pipeline.
- Reading a value the speaker doesn't return (`volume`, `mute`, `timeout` and the rest) now says "Invalid response from Mu-so." and exits with 202, instead of exiting silently with an unexplained code.
- In the `curl` version, a request that times out is reported as a network failure ("Mu-so offline?") like any other unreachable speaker, rather than a bare "Operation timeout." The exit code, 28, is unchanged.
- Argument validation moved ahead of everything else, an unused error mapping dropped, and a simpler timer behind the debug trace - _code improvements_.

## 8.2 - August 2026

Tidying only - _code improvements_.

- Helper functions and the option dispatcher put back in alphabetical order, and a clearer name for the field array behind `info`. Behaviour is unchanged in both versions.

## 8.1 - July 2026

Argument handling tightened up.

- `seek` no longer bails out when the target position works out to zero. `seek 0`, and a relative jump that lands exactly at the start of the track, now seek as asked instead of exiting with an unexplained error code.
- Numbers with a leading zero (`volume 08`, `stations 02`) are rejected again, with the usual "Missing or invalid argument." message. Accepting them in 8.0 made `08` and `8` two spellings of one value; a numeric argument now has a single valid form.
- Leaner argument validation and a simplified error path in the JSON helper - _code improvements_.

## 8.0 - July 2026

Error handling done right, plus a friendlier first run.

- Any failure now stops the script immediately and exits with a meaningful code. Errors no longer slip through, and messages are no longer printed twice.
- Clearer diagnostics in both versions: an unreachable speaker ("Mu-so offline?") is now distinguished from one in standby ("Mu-so in standby?"). A connection the speaker drops or resets is reported as a network failure too, instead of an unexplained error code.
- A reply that isn't valid JSON is reported as "Invalid response from Mu-so." with its own exit code, rather than failing with a raw `jq` parse error.
- Running the script with no arguments, or with `-h` / `--help`, prints the usage screen instead of failing.
- The usage screen documents commands that already worked but were hidden: `info`, and the direct inputs `qobuz`, `spotify` and `tidal`. It also explains relative values (`volume +5`) and single-key lookups (`levels volume`).
- Numbers with a leading zero (`volume 08`) are accepted - previously they were misread as octal and rejected. (Reverted in 8.1.)
- Now playing shows `?` for fields the speaker reports as empty, instead of leaving gaps.
- Passing more than one argument is rejected up front rather than silently ignored.
- Faster station and input selection: the item is resolved in a single filtered request instead of fetching the whole list first.
- `wget` no longer reads `~/.netrc` or writes cookie and HSTS state.

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

- **5.0** - The interactive picker is gone. `stations` and `inputs` now print a numbered list, and `stations 2` plays an entry directly. Commands no longer block waiting for input, so they work from Shortcuts, cron and Home Assistant.
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
- **2.5** - `loudness`, `mono` and the `lighting` theme setting.
- The host override environment variable became `MUSO_HOST` (previously `NAIM_HOST`).

## 1.0 - October 2025

First version. Power, transport control, volume, and an interactive picker for inputs and radio presets, over plain HTTP with `curl` and `jq`.
