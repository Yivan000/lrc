## 2.5.0

- `WlrcParser` reads word synced `.wlrc` lyrics (deezer and musixmatch exports), `LyricsParser` no longer reads their words as separate lines
- `LyricsParser` guesses the format of content starting with text lines from its first timing, so their parser runs directly

## 2.4.0

- `TtmlParser` is a single pass scanner now, ~2-5x faster and ~30x for lrc text inside `<p>`, the `xml` dependency is gone
- TTML agents (`ttm:agent` on `<p>` or `<div>`) are persons, background vocals (`x-bg`) are lines
- TTML translations and romanizations (`x-translation`, `x-roman`, head `<translations>`/`<transliterations>`) are lines sharing their line's timestamp
- TTML syllables are no longer split by spaces, and every time expression is read (`h`, `m`, `s`, `ms`, frames, ticks)
- TTML metadata fills title, artist, album, songwriters, language and length
- Html entities in TTML, QRC and subtitles are decoded without `HtmlUnescape` unless needed (~200x faster)

## 2.3.1

- `LyricsParser` parses any supported format, guessing it from the content so only its parser runs, plain text is rejected in a single pass (~50x faster than trying every parser)
- `SubtitleParser.isValid` no longer compiles a regex per call

## 2.3.0

- `QrcParser` reads the word synced QRC lyrics of QQ Music

## 2.2.0

- `LrcLineResolver` finds the line at a position, `forUiDisplay` takes it through `lineResolver`
- Lines with unique out of order timestamps are sorted
- `PaxsenixJsonParser` reads the word synced json of the Lyrically (paxsenix) api
- Interlude empty lines are no longer skipped after a translated line, and background vocals no longer hide their main line
- Extended lines (`M: ...`) no longer get an interlude empty line sharing their timestamp

## 2.1.0

- Parsing is ~6x faster for word synced lyrics and ~10x faster for plain synced lyrics, regexes were replaced with hand written scanners producing identical output
- The last word of a word synced line without an end timestamp now ends at the next line that starts after it, skipping translation and overlapping duet lines instead of snapping to an earlier timestamp
- The last word of the final line is no longer dropped when it has no end timestamp, it gets the line's average word duration
- Word parts of lines with multiple timestamps (`[00:10.00][01:20.00]...`) are now shifted to each timestamp
- `Lrc.forUiDisplay` now applies offset, `extraOffsetDuration` and the multiplier to word parts too, not only to line timestamps

| file (AOT, µs per `Lrc.parse`)            | 2.0.2 | 2.1.0 | speedup |
| ----------------------------------------- | ----- | ----- | ------- |
| word synced, 154 lines, duets             | 1850  | 314   | 5.9x    |
| word synced, 117 lines, no end timestamps | 1356  | 228   | 5.9x    |
| plain synced, 117 lines                   | 1253  | 123   | 10.2x   |

## 2.0.2

TODO

## 1.0.0

- Initial version.

## 1.0.1

- Fixed a bug that causes `Lrc.format` to return an invalid LRC string [[#3](https://github.com/Yivan000/lrc/pull/3)]
- Added more and fixed some documentation

## 1.0.2

- Fixed a bug where the hundreds of a second time is being saved as thousands of a second [[#4](https://github.com/Yivan000/lrc/pull/4)]
