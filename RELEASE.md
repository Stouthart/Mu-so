<!-- v10.2 - Copyright (c) 2025-2026 Stouthart. All rights reserved. -->

# Release notes

Highlights per major version, newest first. Point releases are listed where they changed behaviour; releases marked _code improvements_ changed nothing a user would notice.

10.2 is the version distributed. Everything below it is how the scripts got there: the bold upgrade warnings in those entries concern copies of earlier versions, and there is nothing in them to act on if 10.2 is where you started.

## 10.2 - August 2026

A track position written the way it is read back.

- **`seek` now takes a `min:sec` position as well as a number of seconds.** `seek 3:39` is `seek 219`, so the figure `now` prints as `3:39` can be typed straight back in without doing the arithmetic. The seconds are always two digits (`3:09`, not `3:9`); the minutes may be written either way.
- **The relative `+` and `-` work on that form too**, so `seek -1:30` rewinds a minute and a half and `seek +0:30` skips forward half a minute. Both forms clamp the same way they always did - past the end of the track lands just short of it, before the start lands at `0` - and seeking with nothing playing still does nothing and succeeds.
- **The upper bound is `3599`, where it was `3600`.** `seek 3600` is now rejected with "Missing or invalid argument.", which keeps the two forms to the same range: one second short of the hour, matching `59:59`. It only ever mattered on a track over an hour long, where the second was clamped away in any case. **Scripts passing a literal `3600` need changing.**
- The position lookup, the relative arithmetic and the clamping moved out of the seconds branch and now run once for whichever form was given, and the usage screen gained a line for the new syntax - _code improvements_.

## 10.1 - August 2026

Two things the speaker already knew and the script never asked it for: any URL it can reach, played on the spot, and the notes behind the track that is playing.

- **New `add URL`**, which empties the playqueue, puts one URL in it and starts playing - the call the Naim app makes to play a file from a UPnP server, and the reason the playqueue can now hold something the app didn't put there. It is a single request rather than a clear, an append and a play. The display name comes from the last segment of the URL, with the extension dropped, minimServer's `*XX` byte escapes decoded and underscores turned into spaces. The URL itself is sent as given - it has to arrive escaped the way the serving side expects, which for minimServer means `*XX` and not percent-encoding.
- **The MIME type behind `add` is derived from the file extension**, because the speaker needs one: `.flac`, `.dsf`, `.m4a`, `.wav`, `.aif`/`.aiff` and `.dff` each get their own, and everything else falls back to `audio/mpeg`, which covers `.mp3`. A track sent with the wrong type still plays, but reports a `0:00` duration and won't seek.
- **New `notes`** (long-form alias: `description`), printing the description the speaker holds for the current track - show notes, and on a podcast often the full tracklist. It doesn't come from the file or from the server that served it: the speaker enriches it from Naim's own online metadata service, so it appears a moment into playback and only for content that service recognises. Nothing to show prints nothing and succeeds, and the carriage returns the speaker embeds are stripped.
- **A network failure while resolving `stations 2`, `playlists 1` or `queue 5` is reported for what it is.** The lookup runs in a subshell, so the `exit` that should have ended the script only ended the subshell: the real message ("Mu-so offline?") was printed, then followed by "Missing or invalid argument." and exit 201, whatever had actually gone wrong. The genuine exit code now propagates, and 201 is left to mean what it says - an index outside the list. **Scripts that read 201 from those three options as "unreachable" need changing.**
- The internal `sleep` helper renamed to `timer`, so it no longer shadows the shell's own `sleep`; the HTTP helper in both versions gained a fourth parameter for a request body, which is what `add` posts; the `wget` and `curl` invocations were cut back to the flags that measurably earn their place, `curl` no longer pinning `--http1.1` and `wget` no longer passing `--no-iri`, neither of which changed what goes over the wire to the speaker; and the `--xdbg` trace rounds its millisecond timings instead of truncating them - _code improvements_.

## 10.0 - August 2026

**The version that goes out.** 9.5 was meant to be the end of it, and in behaviour it nearly was. What was left is the naming: the last two options without a long-form name now have one, so every option in the script reads the same way.

- **`lipsync` and `pairing` now have long-form aliases: `delay` and `open`.** Each is the name of the key the option writes - `delay` on the HDMI input, `open` on the Bluetooth input - the way `roomcomp`/`position` and `autostandby`/`standbyTimeout` already read. The short names remain the documented ones, and both spellings work, so nothing breaks.
- Error messages collected into one variable and printed with a single `printf` rather than a `case` of `echo`s, and the option aliases put in dispatcher order - _code improvements_.

## 9.5 - August 2026

The scripts do what they set out to do, and this is the round of polish that says so: cleaner now playing lines, and names that match the app.

- **`timeout` is now `autostandby`.** `standbyTimeout` still works as a long-form alias, but a bare `timeout` is rejected with "Missing or invalid option." The new name says which standby it means - the idle timer the app calls **Auto Standby Time**, not the one-off countdown `sleep` arms. **Aliases and Shortcuts still calling `timeout` must switch.** It also moves to the usage screen's **Power** section, next to `sleep` and `standby`.
- **`info` is gone; the option is `now`.** It has been an alias since 9.0 renamed it, and is now rejected with "Missing or invalid option."
- **Exit codes `200` and `201` swapped.** An unknown option now exits `200` and a missing or invalid argument `201`, the order the two are checked in - the option is read before whatever follows it. The messages themselves are unchanged. **Scripts and Shortcuts that branch on the exit code to tell the two apart must switch.**
- **`now` and `queue` no longer pad missing fields with `?`.** A track the speaker reports no album for prints as `Artist / Title`, without the empty brackets, and one with no artist prints as the bare title. Both are built by one shared jq helper, so a playqueue entry and the first line of `now` are laid out identically. **Scripts that split those lines on `/` or on the brackets need changing.**
- **On radio, the station name now fills the album brackets** in `now` and `queue`, where a `?` stood before.
- The second line of `now` reads `UNKNOWN` for the two fields that can genuinely be missing - format and source - rather than `?`.
- **A format read from the MIME type is no longer upper-cased.** Only the `audio/` prefix is stripped now, so `audio/mpeg` reads as `mpeg` instead of `MPEG`, and `audio/x-flac` keeps its `x-`. It only affects streams the speaker reports no codec for, HDMI in practice.
- Bit rate is no longer rounded to whole kb/s. A stream reporting 320500 bits per second prints `320.5kb/s` instead of `321kb/s`; rates that are already whole, like `1004kb/s`, are unchanged.
- `vol` is the documented name for the volume option and `volume` the long-form alias, reading the way `maxvol`/`maxVolume` and `roomcomp`/`position` already do. Both still work, so nothing breaks.
- `lipsync` moved from the usage screen's **Audio** section to **Other**. It is a setting on the HDMI input, not a speaker-wide audio control, and it sits with `autoswitch`, the other HDMI setting. Behaviour is unchanged.
- Option aliases collapsed into grouped patterns, the dispatcher put in the same order as the usage screen, the MIME type and `inputs/` prefix stripping moved out of jq into Bash, and the usage screen's title spelled out as "Naim Mu-so 2nd generation" - _code improvements_.

## 9.4 - August 2026

Bluetooth pairing without reaching for the app.

- New `pairing 0..1`, putting the speaker into Bluetooth pairing mode so a phone or laptop can discover it, and taking it back out. It writes the `open` key on the Bluetooth input, the one the Naim app's pairing switch uses, and `bluetooth` reports it back alongside the device name and connection state.
- The `start` helper - renamed from `play` only in 9.0 - is gone again: its single caller now plays the resolved item directly. The usage screen's **Other** section wraps onto a second line to fit the new option - _code improvements_.

## 9.3 - August 2026

Playlists from the favourites list, and the HDMI input's own two settings.

- New `playlists 1..n`, listing the playlist favourites and playing one by number, alongside `stations`. It reads the same favourites list, filtered to the entries whose class ends in `Playlist` - the playlists saved from a streaming service or a UPnP server - and numbers them oldest first, as `stations` does.
- New `lipsync 0..50`, the HDMI audio delay, for lining the sound up with the picture on a connected TV. It writes the `delay` key on the HDMI input, in the same steps the Naim app's lip sync slider uses.
- New `autoswitch 0..2` (long-form alias: `autoSwitching`), controlling whether the speaker selects the HDMI input by itself when the TV starts sending audio.
- **The current track in `queue` is now marked with a leading `>` instead of `▶`.** The arrow needed a font that has it and a terminal in the right encoding; a plain `>` survives being piped into anything. **Scripts that pick the playing entry out of the list by the arrow need changing.**
- The usage screen now says that relative values work everywhere except `sleep`, rather than implying every numeric option takes them - _code improvements_.

## 9.2 - August 2026

A playqueue you can navigate, and favourites in the order you added them.

- `queue 1..n` jumps to a track in the playqueue, the way `inputs` and `stations` already select by number. A bare `queue` still prints the list.
- **The current track in `queue` is now marked with a leading `▶`** in front of the artist, instead of a trailing `*`. Scripts that pick the playing entry out of the list by its trailing marker need changing.
- **`radio` is gone; the option is `stations`.** It has been an alias since 6.0 moved radio favourites to the plural name, and is now rejected with "Missing or invalid option." **Aliases and Shortcuts still calling `radio` must switch.**
- **`stations` lists favourites oldest first, in the order they were added, instead of by descending preset ID - so the numbering changes.** Adding a favourite now appends it to the end and leaves the existing numbers alone; previously the highest preset ID came first, so a new favourite could shift everything below it.
- The helper behind the numeric options renamed from `number` to `setting`, `signed` to `isnum`, and the queue listing moved out of the dispatcher into its own function - _code improvements_.

## 9.1 - August 2026

The HDMI input, and a now playing line that copes without a codec.

- New information option `hdmi`, reporting the state of the HDMI input alongside the other input nodes.
- `now` no longer shows the format as `?` when the speaker reports no codec, as it does on HDMI. The stream's MIME type is used instead, stripped of its `audio/` and `x-` prefixes and upper-cased, so `audio/mpeg` reads as `MPEG`.
- Bit rate is now always read as bits per second. Values below 16000 were previously printed unchanged, on the assumption that they were already in kb/s, which turned a genuinely low-bitrate stream into a figure like `15000kb/s`.
- The internal `call` helper renamed to `http`, and a corrected comment on the sleep timer - _code improvements_.

## 9.0 - August 2026

More of the speaker readable, and option names that say what they do.

- **`qobuz`, `spotify` and `tidal` no longer switch the input.** They are now information options that report that input's state, in line with the other nodes. Input selection goes through the list instead - `inputs`, then `inputs 1..n`. **Aliases and Shortcuts that call `qobuz`, `spotify` or `tidal` to start playing must be changed**, or they will merely print a block of `key=value` lines. Note that only inputs the speaker marks as selectable are listed: Spotify is, Qobuz and Tidal are not, so for those two there is no direct replacement for the old shortcut.
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
- `standby` - until now an alias for `sleep` - is the way to put the speaker in standby immediately. **Aliases and Shortcuts that call `sleep` for that must switch to `standby`**, or they will merely arm a timer.
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
- **2.5** - `loudness`, `mono` and the `lighting` theme setting.
- The host override environment variable became `MUSO_HOST` (previously `NAIM_HOST`).

## 1.0 - October 2025

First version. Power, transport control, volume, and an interactive picker for inputs and radio presets, over plain HTTP with `curl` and `jq`.
