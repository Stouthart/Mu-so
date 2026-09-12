<!-- 10.5 - Copyright (C) 2025-2026 Stouthart. All rights reserved. -->

# Release notes

Highlights per major version, newest first. Point releases are listed where they changed behaviour; releases marked _code improvements_ changed nothing a user would notice.

10.5 is the version distributed. Everything below it is how the scripts got there: the bold upgrade warnings in those entries concern copies of earlier versions, and there is nothing in them to act on if 10.5 is where you started.

## 10.5 - September 2026

The format of a Spotify lossless stream on the `now` line, the current track's artwork, names that match the app, replies held to exactly what the speaker should send, and less work per command.

- **`now` shows the format of a Spotify lossless stream.** The speaker's API reports these as `UNKNOWN CODEC`, or as `FLAC` with a bit rate of 0. When `now` sees either, it makes a second, read-only request to the speaker's player API on port `80`, which names the codec, the bit depth when it is 24-bit, and the bit rate - so the line reads `FLAC 0kHz 24bit 1675.81kb/s [spotify]` instead of `UNKNOWN CODEC 0kHz 0bit 0kb/s [spotify]`. Neither API reports the sample rate, which stays `0kHz`. Other sources make that request only in the same two cases, and if port `80` doesn't answer the line is printed as before.
- **New `artwork`**, printing the URL of the current track's artwork, ready to open.
- **`notes` is now `description`**, the word the Naim app uses and the key the option reads. `notes` is rejected with "Missing or invalid option." **Aliases and Shortcuts still calling `notes` must switch.**
- `wifi` is the documented name for the Wi-Fi interface, the app's own word for it; `wireless` still works as the long-form alias, so nothing breaks.
- **A reply must be exactly one JSON value.** Two values run together, which 10.4 processed one after the other, are now reported as "Invalid response from Mu-so." and exit 202, so a corrupted reply can no longer produce two list entries to play or two values for a relative setting.
- **C1 control characters are stripped as well.** 10.4 removed the C0 controls and DEL, but not U+0080 to U+009F, which include the 8-bit forms of CSI and OSC that some terminals act on. They are now stripped from every string the speaker returns, and from the value an information option prints for a single key when that value is an object or an array.
- A fractional number from the speaker no longer breaks the integer arithmetic. A position or duration such as `1000.5` stopped `now` and `seek` with a Bash arithmetic error, and a relative setting took the current value as-is, so `vol +5` on `30.5` would have sent `35.5`. Position, duration, bit depth, the Spotify bit rate and the value a relative setting starts from are now rounded down. The API sends whole numbers, so in practice nothing changes.
- A server error names the endpoint the request went to: "Server error on levels, Mu-so in standby?" instead of "Server error, Mu-so in standby?". The exit code is unchanged - `8` for `msc.sh`, `22` or `47` for `msc-curl.sh` - and the other messages are untouched.
- An invalid JSON reply prints only "Invalid response from Mu-so." - jq's own parse error no longer appears above it. The exit code is 202, as before.
- `msc-curl.sh` names two failures it used to report as "Unexpected curl error". A reply cut off partway (`18`) is a network failure, as `msc.sh` already reported it, and a refused redirect (`47`) is a server error, matching `msc.sh`'s `8`. The exit codes themselves are unchanged.
- Each reply is streamed straight into `jq` instead of being captured first, `wget` or `curl` replaces the pipeline's subshell instead of running under it, fields are split without here-strings (which Bash 3.2 writes to a temporary file), and each call references only the jq definitions its output needs - together typically 2 to 6 ms less per command - _code improvements_.
- The jq definitions consolidated: shared `int`, `num`, `line` and `kv` helpers, `desc` moved into the preamble, definitions used only once inlined, and the rest ordered by the stage they serve. The check that walks structured output looks for C1 only, since jq already escapes DEL. The preamble is now assigned before `--xdbg` turns tracing on, so the trace no longer starts with it - _code improvements_.
- `artwork` and `description` share one branch, `inputs`, `playlists`, `stations` and `queue` resolve an index through one shared lookup, the `wifi` alias is folded into `wired` and `wireless`, and the options that take no argument are checked with a single test that skips the name match when no argument is given - _code improvements_.

## 10.4 - September 2026

A second read-through of both scripts, narrower than 10.3 and aimed at what the speaker sends back rather than what is typed in.

- **Control characters are stripped from everything the speaker returns, not just `notes`.** 10.3 cleaned the description alone, but names reach the terminal through `inputs`, `playlists`, `stations`, `queue` and `now` as well, and a name carrying control characters could still move the cursor or set colours there. The stripping now happens once, where the reply is parsed, so every option is covered. Tabs survive, and so do the line breaks in `notes`.
- **A line break inside a name or value no longer splits a listed entry across two lines.** Where the output is one entry per line - the numbered lists, `queue`, `sleep` and the `key=value` information output - a line break is folded to a space, so the numbering stays readable and a line can still be split on its first `=` or `)`. `notes` is untouched: a podcast tracklist keeps its line breaks.
- **`now` prints `44.1kHz` under every locale.** Where `LC_NUMERIC` asked for a comma - `de_DE.UTF-8` and `fr_FR.UTF-8` among others - the sample rate and bit rate read `44,1kHz` and `1,411kb/s`. The figures are now formatted in the C locale regardless of the environment.
- A track known only by its album or station no longer gains a leading space. `now` and `queue` printed `" [Kind of Blue]"` where the artist and title were both missing or empty.
- An empty reply from the speaker is reported as "Invalid response from Mu-so." and exits 202, where it used to print nothing and succeed. A reply that parses but holds no matching keys is unchanged: a bare `sleep` with no timer keys and an empty list still print nothing and exit 0.
- Reading a setting that comes back as an empty string reports 202, which is what the missing-value case already did, rather than printing a blank line and succeeding.
- `help`, `-h` and `--help` reject a stray argument, the way the other options that take none have since 10.3. `help stop` now prints "Missing or invalid argument." and exits 201 instead of printing the usage.
- `--xdbg` no longer exits before it traces anything on the later Bash 4 releases. `EPOCHREALTIME`, which the trace reads for its timings, arrived in Bash 5.0, and by the end of the Bash 4 line `set -u` had come to treat a substitution on an unset name as a fatal error rather than an empty string - so the flag ended the script on "EPOCHREALTIME: unbound variable" instead of tracing. It now falls back to a fixed `0.0` where the shell has no clock of its own, which leaves the trace running and the millisecond column reading `0` throughout - what Bash 3.2 has shown all along.
- The sign of a relative `seek` is now captured with the value instead of being read back from the match state after the position has been fetched - a regex added anywhere in between would have silently changed which way `seek +30` moved - _code improvements_.

## 10.3 - August 2026

A full read-through of both scripts, and the edge cases it turned up closed - two of them worth reading before you upgrade.

- Every option, argument form and error path was checked line by line against the rest, with three models reading independently (GPT-5.6 Sol, Kimi K3 and Claude Opus 5), and the edge cases they turned up closed.
- **An option that takes no argument now rejects one instead of ignoring it.** `clear`, `next`, `notes`, `now`, `play`, `pause`, `prev`, `standby`, `stop` and `wake` used to run whatever followed them, so `stop now` stopped and `clear queue` cleared, both exiting 0. They now print "Missing or invalid argument." and exit 201. **Aliases and Shortcuts that pass a stray word to one of these must drop it.**
- A redirect is refused rather than followed, in both versions. The API never issues one, so a redirect means the reply did not come from the speaker - and the two versions disagreed about it: `wget` followed it, while `curl` sent writes to the redirecting address and reported success without ever reaching the target. `msc.sh` now reports it as `8`, `msc-curl.sh` as `47`.
- `notes` strips the control characters in the description, not just the carriage returns, so text embedded in a file's comments cannot move the cursor or set colours in the terminal it is printed to. Line breaks and tabs survive.
- `now` and `queue` treat an empty string from the speaker the way they already treated a missing key. A station reported with an empty `albumName` keeps its name in the brackets, and an empty `codec` or `sourceDetail` falls back to the MIME type and the source instead of reading `UNKNOWN`.
- Information options take a key of 3 to 32 characters and accept `_` and `-` in it, where the check was 3 to 24 alphanumerics - the "any key" the documentation describes, rather than a narrower set it never mentioned. Three is the shortest key the speaker returns on any node (`cpu`, `uri`, `wac`).
- The README now names the `wget` the script needs: GNU Wget 1.19.2 or newer, for `--no-netrc`, `--no-config` and `--method`. BusyBox's `wget` takes none of the three.
- A bare `sleep` with no timer keys in the reply prints nothing and succeeds, the way a bare `queue`, `notes` and the empty lists already did, rather than exiting on the empty result.
- The query strings passed to the request helper are quoted, so a `?` or `*` in an option's URI is never matched against filenames in the working directory.
- `msc-curl.sh` no longer passes `--tcp-fastopen`. It saved no measurable time against the speaker, needed curl 7.49 or newer, and is left out of the Windows builds the script is documented for - where curl refuses the option outright and exits `4`, a code the script had no message for. **A Git Bash install that was failing every request with "Unexpected curl error 4." now works.**

## 10.2 - August 2026

A track position written the way it is read back.

- **`seek` now takes a `min:sec` position as well as a number of seconds.** `seek 3:39` is `seek 219`, so the figure `now` prints as `3:39` can be typed straight back in without doing the arithmetic. The seconds are always two digits (`3:09`, not `3:9`); the minutes may be written either way.
- **The relative `+` and `-` work on that form too**, so `seek -1:30` rewinds a minute and a half and `seek +0:30` skips forward half a minute. Both forms clamp the same way they always did - past the end of the track lands just short of it, before the start lands at `0` - and seeking with nothing playing still does nothing and succeeds.
- **The upper bound is `3599`, where it was `3600`.** `seek 3600` is now rejected with "Missing or invalid argument.", which keeps the two forms to the same range: one second short of the hour, matching `59:59`. It only ever mattered on a track over an hour long, where the second was clamped away in any case. **Scripts passing a literal `3600` need changing.**
- The position lookup, the relative arithmetic and the clamping moved out of the seconds branch and now run once for whichever form was given, and the usage screen gained a line for the new syntax - _code improvements_.

## 10.1 - August 2026

Something the speaker already knew and the script never asked it for: the notes behind the track that is playing.

- **New `notes`** (long-form alias: `description`), printing the description embedded in the current track's comments - show notes, and on a podcast often the full tracklist. Nothing to show prints nothing and succeeds, and the carriage returns in the text are stripped.
- **A network failure while resolving `stations 2`, `playlists 1` or `queue 5` is reported for what it is.** The lookup runs in a subshell, so the `exit` that should have ended the script only ended the subshell: the real message ("Mu-so offline?") was printed, then followed by "Missing or invalid argument." and exit 201, whatever had actually gone wrong. The genuine exit code now propagates, and 201 is left to mean what it says - an index outside the list. **Scripts that read 201 from those three options as "unreachable" need changing.**
- The internal `sleep` helper renamed to `timer`, so it no longer shadows the shell's own `sleep`; the `wget` and `curl` invocations were cut back to the flags that measurably earn their place, `curl` no longer pinning `--http1.1` and `wget` no longer passing `--no-iri`, neither of which changed what goes over the wire to the speaker; and the `--xdbg` trace rounds its millisecond timings instead of truncating them - _code improvements_.

## 10.0 - August 2026

**The version that goes out.** 9.5 was meant to be the end of it, and in behaviour it nearly was. What was left is the naming: the last two options without a long-form name now have one, so every option in the script reads the same way.

- **`lipsync` and `pairing` now have long-form aliases: `delay` and `open`.** Each is the name of the key the option writes - `delay` on the HDMI input, `open` on the Bluetooth input - the way `roomcomp`/`position` and `autostandby`/`standbyTimeout` already read. The short names remain the documented ones, and both spellings work, so nothing breaks.
- Error messages collected into one variable and printed with a single `printf` rather than a `case` of `echo`s, and the option aliases put in dispatcher order - _code improvements_.

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
