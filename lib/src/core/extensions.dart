part of lrc;

/// Handy extensions on lists of LrcLine
extension LrcLineExtensions on List<LrcLine> {
  /// Creates a stream for each lyric using their durations
  Stream<LrcStream> toStream() async* {
    for (var i = 0; i < length; i++) {
      var lineCurrent = this[i];
      var lineNext = (i + 1 < length) ? this[i + 1] : null;
      var durationToNext = (lineNext != null)
          ? Duration(
              milliseconds: lineNext.timestamp.inMilliseconds -
                  lineCurrent.timestamp.inMilliseconds)
          : null;
      yield LrcStream(
          duration: durationToNext,
          previous: (i != 0) ? this[i - 1] : null,
          current: lineCurrent,
          next: lineNext,
          position: i,
          length: length - 1);
      if (durationToNext != null) {
        await Future.delayed(durationToNext);
      }
    }
  }
}

extension LrcExtensions on Lrc {
  ({
    List<LrcLine> uiLyricsLines,
    Map<Duration, List<int>> highlightTimestampsMap,
  }) forUiDisplay(
    double multiplier, {
    Duration durationDifferenceToInsertEmptyLine = const Duration(seconds: 1),
    Duration extraOffsetDuration = Duration.zero,
    String Function(String text)? romanizer,
  }) {
    final originalLyrics = lyrics;
    final offsetDuration =
        Duration(milliseconds: this.offset ?? 0) - extraOffsetDuration;
    final offsetValid = offsetDuration != Duration.zero;
    final uiLyricsLines = <LrcLine>[];
    final highlightTimestampsMap =
        <Duration, List<int>>{}; // timestamp: [index]
    var indexExtra = 0;
    for (var index = 0; index < originalLyrics.length; index++) {
      final ogItem = originalLyrics[index];

      var lineTimeStampEdited = ogItem.timestamp;
      if (offsetValid) lineTimeStampEdited -= offsetDuration;
      if (multiplier != 0) lineTimeStampEdited *= multiplier;

      final newLrcLine = ogItem.withTimeStamp(
        newTimestamp: lineTimeStampEdited,
        parts: _mergeParts(ogItem.parts),
      );
      final indicesList = highlightTimestampsMap[lineTimeStampEdited] ??= [];
      indicesList.add(index + indexExtra);
      uiLyricsLines.add(newLrcLine);
      if (romanizer != null) {
        final romanized =
            _romanized(newLrcLine, index, lineTimeStampEdited, romanizer);
        if (romanized != null) {
          indexExtra++;
          indicesList.add(index + indexExtra);
          uiLyricsLines.add(romanized);
        }
      }
      final newParts = newLrcLine.parts;
      if (newParts != null) {
        try {
          final nextLine = index == originalLyrics.length - 1
              ? null
              : originalLyrics[index + 1];
          if (nextLine != null) {
            final partEndTimestamp = newParts.last.endTimestamp;
            if ((nextLine.timestamp - partEndTimestamp) >
                durationDifferenceToInsertEmptyLine) {
              // -- insert empty line to allow dynamic lrc view to hide lrc during long transitions
              indexExtra++;
              final emptyLineIndex = index + indexExtra;

              uiLyricsLines.add(
                LrcLine(
                  timestamp: partEndTimestamp,
                  originalIndex: emptyLineIndex + 0.1,
                  lyrics: '',
                  readableText: '',
                  type: LrcTypes.simple,
                  parts: const [],
                  person: null,
                  isRTL: false,
                ),
              );
              final indicesList =
                  highlightTimestampsMap[partEndTimestamp] ??= [];
              indicesList.add(emptyLineIndex);
            }
          }
        } catch (_) {}
      }
    }
    return (
      uiLyricsLines: uiLyricsLines,
      highlightTimestampsMap: highlightTimestampsMap,
    );
  }
}

List<LrcLinePart>? _mergeParts(
  List<LrcLinePart>? parts, {
  int minDurationMs = 250,
}) {
  if (parts == null || parts.isEmpty) return parts;

  final merged = <LrcLinePart>[];
  var current = parts[0];

  for (var i = 1; i < parts.length; i++) {
    final next = parts[i];
    final duration = current.endTimestamp.inMilliseconds -
        current.startTimestamp.inMilliseconds;

    if (duration < minDurationMs) {
      current = LrcLinePart(
        startTimestamp: current.startTimestamp,
        endTimestamp: next.endTimestamp,
        lyrics: current.lyrics + next.lyrics,
      );
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}

LrcLine? _romanized(
  LrcLine line,
  int index,
  Duration lineTimestamp,
  String Function(String text) romanizer,
) {
  final parts = line.parts;
  final txt = parts != null && parts.isNotEmpty
      ? parts.map((e) => e.lyrics).join()
      : line.lyrics;
  if (txt.isEmpty) return null;
  final romanized = romanizer(txt);
  if (romanized == txt) return null;
  return LrcLine(
    timestamp: lineTimestamp,
    originalIndex: index + 0.05,
    lyrics: romanized,
    readableText: romanized,
    type: line.type,
    parts: null,
    person: line.person,
    isRTL: LrcParser.isLrcLineRTL(romanized),
  );
}

/// Handy extensions on strings
extension StringExtensions on String {
  /// Handy extension method that parses the string to an [Lrc]
  Lrc toLrc() => LrcParser.parse(this);

  /// Handy extension getter if the given string is a valid LRC
  bool get isValidLrc => LrcParser.isValid(this);
}

extension LrcFileExtensions on File {
  String readLrcStringSync() {
    try {
      return readAsStringSync(encoding: utf8);
    } on FileSystemException catch (_) {
      try {
        return readAsStringSync(encoding: utf16);
      } catch (_) {}
    }
    return '';
  }

  Future<String> readLrcString() async {
    try {
      return await readAsString(encoding: utf8);
    } on FileSystemException catch (_) {
      try {
        return await readAsString(encoding: utf16);
      } catch (_) {}
    }
    return '';
  }
}
