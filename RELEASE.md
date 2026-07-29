<!-- v8.0 - Copyright © 2026 Stouthart. All rights reserved. -->

# Release notes

Highlights per major version, newest first. Point releases are listed where they changed behaviour; releases marked _code improvements_ changed nothing a user would notice.

## 8.0 — July 2026

Error handling done right, plus a friendlier first run.

- Any failure now stops the script immediately and exits with a meaningful code. Errors no longer slip through, and messages are no longer printed twice.
- Clearer diagnostics in both versions: an unreachable speaker ("Mu-so offline?") is now distinguished from one in standby ("Mu-so in standby?"). A connection the speaker drops or resets is reported as a network failure too, instead of an unexplained error code.
- A reply that isn't valid JSON is reported as "Invalid response from Mu-so." with its own exit code, rather than failing with a raw `jq` parse error.
- Running the script with no arguments, or with `-h` / `--help`, prints the usage screen instead of failing.
- The usage screen documents commands that already worked but were hidden: `info`, and the direct inputs `qobuz`, `spotify` and `tidal`. It also explains relative values (`volume +5`) and single-key lookups (`levels volume`).
- Numbers with a leading zero (`volume 08`) are accepted — previously they were misread as octal and rejected.
- Now playing shows `?` for fields the speaker reports as empty, instead of leaving gaps.
- Passing more than one argument is rejected up front rather than silently ignored.
- Faster station and input selection: the item is resolved in a single filtered request instead of fetching the whole list first.
- `wget` no longer reads `~/.netrc` or writes cookie and HSTS state.

## 7.x — May–July 2026

Naming cleanup and a more predictable `seek`.

- **7.0** — `standby` became `sleep`, with `standby` kept as an alias. Short and long names now both work throughout: `vol`/`volume`, `radio`/`stations`, `queue`/`playqueue`, `lighting`, `max`, `timeout`.
- **7.1** — `seek` rewritten: relative jumps are clamped to the track boundaries, and seeking is silently skipped on live streams with no duration.
- **7.2** — Fixed an error-handling bug that could mask a failed request.
- **7.3** — Faster failure reporting and a rewritten debug trace (`--xdbg`) with per-line timings.
- **7.4** — Leaner jq filters, fewer round trips.

## 6.x — March–May 2026

Streaming services in one word.

- **6.0** — Direct input selection: `qobuz`, `spotify` and `tidal` switch the speaker straight to that service.
- Radio favourites moved from `radio` to `stations`, and inputs from `input` to `inputs`, matching the plural listing they produce.
- The formatted `info` view became a documented, first-class command.
- **6.1–6.4** — Code improvements only.

## 5.x — November 2025–March 2026

The release that made the script scriptable.

- **5.0** — The interactive picker is gone. `stations` and `inputs` now print a numbered list, and `stations 2` plays an entry directly. Commands no longer block waiting for input, so they work from Shortcuts, cron and Home Assistant.
- **5.0** — Unified error handling with distinct exit codes per failure type.
- **5.1** — `poweramp` reports the power amplifier settings.
- **5.2** — `max` sets the maximum volume, `timeout` sets the standby timeout in minutes.
- **5.5** — Toggling removed. A bare `mute`, `shuffle` or `loudness` now _reports_ the current value instead of flipping it; set it explicitly with `0` or `1`. Toggles made the result depend on unknown state, which is wrong in a script.

## 4.x — November 2025

First public release, and the one that made it run anywhere.

- **4.0** — Public release.
- **4.2** — `seek <sec>`, absolute or relative.
- **4.3** — Missing or empty values now count as a failure rather than printing nothing and reporting success.
- **4.4** — Faster requests by asking only for headers where the body isn't needed.
- **4.5** — Runs on Bash 3.2, the version macOS ships, so no Homebrew Bash required.
- **4.5** — `position` sets room compensation.
- **4.5** — The host override environment variable became `MUSO_IP` (previously `MUSO_HOST`).

## 3.x — October–November 2025

Values instead of toggles, and a second flavour of the script.

- **3.0** — Refactored, with proper error handling.
- **3.1** — Options can be set directly, e.g. `mute 1`, instead of only cycling.
- **3.2** — A second version added, so the script works with either `wget` or `curl` depending on what's installed. `msc.sh` became the `wget` variant and `msc-curl.sh` the `curl` one.
- **3.3** — Relative volume: `volume +5`, `volume -10`.
- **3.4** — Formatted now playing output: artist, title, album, position, duration, codec, sample rate, bit depth, bit rate and source.
- **3.5** — `capabilities` reports what the speaker supports.

## 2.x — October 2025

Complete rewrite of the first version.

- **2.1** — `shuffle`, `repeat` and `mute`.
- **2.3** — Human-readable error messages instead of raw `curl` exit codes.
- **2.5** — `loudness`, `mono` and the `lighting` theme setting.
- The host override environment variable became `MUSO_HOST` (previously `NAIM_HOST`).

## 1.0 — October 2025

First version. Power, transport control, volume, and an interactive picker for inputs and radio presets, over plain HTTP with `curl` and `jq`.
