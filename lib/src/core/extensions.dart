part of lrc;

/// Handy extensions on lists of LrcLine
extension LrcLineExtensions on List<LrcLine> {
  /// Creates a stream for each lyric using their durations
  Stream<LrcStream> toStream() async* {
    for (var i = 0; i < length; i++) {
      var lineCurrent = this[i];
      var lineNext = (i + 1 < length) ? this[i + 1] : null;
      var durationToNext = (lineNext != null) ? Duration(milliseconds: lineNext.timestamp.inMilliseconds - lineCurrent.timestamp.inMilliseconds) : null;
      yield LrcStream(duration: durationToNext, previous: (i != 0) ? this[i - 1] : null, current: lineCurrent, next: lineNext, position: i, length: length - 1);
      if (durationToNext != null) {
        await Future.delayed(durationToNext);
      }
    }
  }
}

extension LrcExtensions on Lrc {
  /// [withUntimedLines] adds the [Lrc.untimedLines] as rows ([LrcLine.isUntimed]) above their line, with its timestamp and never highlighted.
  /// Only the ones above the first line of a timestamp are added, the others belong to a translation written as its own block.
  ({
    List<LrcLine> uiLyricsLines,
    Map<Duration, List<int>> highlightTimestampsMap,
    LrcLineResolver lineResolver,
  }) forUiDisplay(
    double multiplier, {
    Duration durationDifferenceToInsertEmptyLine = const Duration(seconds: 1),
    Duration extraOffsetDuration = Duration.zero,
    String Function(int index, String text)? romanizer,
    bool withUntimedLines = false,
  }) {
    final originalLyrics = lyrics;
    final length = originalLyrics.length;
    final offsetDuration = Duration(milliseconds: this.offset ?? 0) - extraOffsetDuration;
    final offsetValid = offsetDuration != Duration.zero;
    final multiplierValid = multiplier != 0 && multiplier != 1;
    Duration toUiTimestamp(Duration timestamp) {
      var uiTimestamp = timestamp;
      if (offsetValid) uiTimestamp -= offsetDuration;
      if (multiplierValid) uiTimestamp *= multiplier;
      return uiTimestamp;
    }

    final partsToUiTimestamp = offsetValid || multiplierValid ? toUiTimestamp : null;
    final uiLyricsLines = <LrcLine>[];
    final highlightTimestampsMap = <Duration, List<int>>{}; // timestamp: [index]

    final untimedLines = withUntimedLines ? this.untimedLines : const <LrcUntimedLine>[];
    final untimed = untimedLines.isEmpty ? null : _UntimedLinesIndex.of(untimedLines, originalLyrics);

    // -- a slot per timestamp with a non background line, plus an empty line per group
    final slotStartsMS = Int32List(length * 2);
    final slotLineIndices = Int32List(length * 2);
    var slotsCount = 0;
    Duration? latestSlotTimestamp;
    void addSlot(Duration timestamp, int lineIndex) {
      // -- rounded up, so a slot is reached exactly when its timestamp is
      final micros = timestamp.inMicroseconds;
      final startMS = micros ~/ 1000;
      slotStartsMS[slotsCount] = startMS * 1000 < micros ? startMS + 1 : startMS;
      slotLineIndices[slotsCount] = lineIndex;
      slotsCount++;
      latestSlotTimestamp = timestamp;
    }

    Duration? latestPartsEnd;
    var isGroupStart = true;
    var isGroupWithParts = false;
    var nextLineTimestamp = length == 0 ? Duration.zero : toUiTimestamp(originalLyrics[0].timestamp);
    var lastLineTimestamp = Duration.zero;
    for (var index = 0; index < length; index++) {
      final ogItem = originalLyrics[index];
      final lineTimestamp = nextLineTimestamp;
      lastLineTimestamp = lineTimestamp;
      if (untimed != null && isGroupStart) untimed.addRowsAbove(ogItem.originalIndex, lineTimestamp, uiLyricsLines);

      final newLrcLine = ogItem.withTimeStamp(
        newTimestamp: lineTimestamp,
        parts: _mergeParts(ogItem.parts, partsToUiTimestamp),
      );
      final indicesList = highlightTimestampsMap[lineTimestamp] ??= [];
      indicesList.add(uiLyricsLines.length);
      uiLyricsLines.add(newLrcLine);
      if (!newLrcLine.isBGLyrics && lineTimestamp != latestSlotTimestamp) addSlot(lineTimestamp, indicesList.first);
      if (romanizer != null) {
        final romanized = _romanized(newLrcLine, index, lineTimestamp, romanizer);
        if (romanized != null) {
          indicesList.add(uiLyricsLines.length);
          uiLyricsLines.add(romanized);
        }
      }
      if (isGroupStart) isGroupWithParts = false;
      final newParts = newLrcLine.parts;
      if (newParts != null && newParts.isNotEmpty) {
        isGroupWithParts = true;
        final partsEnd = newParts.last.endTimestamp;
        if (latestPartsEnd == null || partsEnd > latestPartsEnd) latestPartsEnd = partsEnd;
      } else if (isGroupStart && !newLrcLine.isBGLyrics) {
        // -- a line without words has no end, it stays until the next line
        latestPartsEnd = null;
      }

      final nextIndex = index + 1;
      if (nextIndex == length) break;
      nextLineTimestamp = toUiTimestamp(originalLyrics[nextIndex].timestamp);
      isGroupStart = nextLineTimestamp != lineTimestamp;
      // -- the empty line waits for every line still singing: same-timestamp translations & duets, and lines that bg vocals interrupt
      if (!isGroupStart) continue;
      if (!isGroupWithParts) continue;
      final emptyLineTimestamp = latestPartsEnd;
      if (emptyLineTimestamp == null || emptyLineTimestamp <= lineTimestamp) continue;
      if (nextLineTimestamp - emptyLineTimestamp <= durationDifferenceToInsertEmptyLine) continue;

      // -- insert empty line to allow dynamic lrc view to hide lrc during long transitions
      final emptyLineIndex = uiLyricsLines.length;
      uiLyricsLines.add(
        LrcLine(
          timestamp: emptyLineTimestamp,
          originalIndex: emptyLineIndex + 0.1,
          lyrics: '',
          readableText: '',
          type: LrcTypes.simple,
          parts: const [],
          person: null,
          isRTL: false,
        ),
      );
      final emptyLineIndices = highlightTimestampsMap[emptyLineTimestamp] ??= [];
      emptyLineIndices.add(emptyLineIndex);
      if (emptyLineTimestamp != latestSlotTimestamp) addSlot(emptyLineTimestamp, emptyLineIndices.first);
    }
    if (untimed != null) untimed.addTrailingRows(lastLineTimestamp, uiLyricsLines);
    final lineStartsMS = slotStartsMS.sublist(0, slotsCount);
    final lineIndices = slotLineIndices.sublist(0, slotsCount);
    return (
      uiLyricsLines: uiLyricsLines,
      highlightTimestampsMap: highlightTimestampsMap,
      lineResolver: LrcLineResolver(lineStartsMS, lineIndices),
    );
  }
}

// by claude
class _UntimedLinesIndex {
  final List<LrcUntimedLine> untimedLines;

  /// [LrcUntimedLine.beforeIndex] to the first of its untimed lines.
  final Map<int, int> firstByBeforeIndex;

  final int trailingStart;
  final bool keepsEmptyLines;

  const _UntimedLinesIndex._(this.untimedLines, this.firstByBeforeIndex, this.trailingStart, this.keepsEmptyLines);

  /// [lyrics] sorted by time, like [Lrc.lyrics].
  factory _UntimedLinesIndex.of(List<LrcUntimedLine> untimedLines, List<LrcLine> lyrics) {
    final firstByBeforeIndex = <int, int>{};
    var trailingStart = untimedLines.length;
    for (var i = untimedLines.length - 1; i >= 0; i--) {
      final beforeIndex = untimedLines[i].beforeIndex;
      if (beforeIndex == null) {
        trailingStart = i;
      } else {
        firstByBeforeIndex[beforeIndex] = i;
      }
    }

    // -- an empty line above every line is file formatting (double spaced, CR CR LF), not verses
    var timestampsCount = 0;
    var timestampsWithEmptyLineCount = 0;
    Duration? previousTimestamp;
    for (final line in lyrics) {
      if (line.isBGLyrics) continue;
      final timestamp = line.timestamp;
      if (timestamp == previousTimestamp) continue;
      previousTimestamp = timestamp;
      timestampsCount++;
      final first = firstByBeforeIndex[line.originalIndex];
      if (first != null && _hasEmptyLineFrom(untimedLines, first)) timestampsWithEmptyLineCount++;
    }
    final keepsEmptyLines = timestampsWithEmptyLineCount * 2 <= timestampsCount;
    return _UntimedLinesIndex._(untimedLines, firstByBeforeIndex, trailingStart, keepsEmptyLines);
  }

  static bool _hasEmptyLineFrom(List<LrcUntimedLine> untimedLines, int first) {
    final beforeIndex = untimedLines[first].beforeIndex;
    for (var i = first; i < untimedLines.length; i++) {
      final untimed = untimedLines[i];
      if (untimed.beforeIndex != beforeIndex) return false;
      if (untimed.text.isEmpty) return true;
    }
    return false;
  }

  void addRowsAbove(num originalIndex, Duration timestamp, List<LrcLine> uiLyricsLines) {
    final first = firstByBeforeIndex[originalIndex];
    if (first == null) return;
    _addRows(first, untimedLines[first].beforeIndex, timestamp, uiLyricsLines);
  }

  void addTrailingRows(Duration timestamp, List<LrcLine> uiLyricsLines) {
    _addRows(trailingStart, null, timestamp, uiLyricsLines);
    while (uiLyricsLines.isNotEmpty && _isEmptyRow(uiLyricsLines.last)) {
      uiLyricsLines.removeLast();
    }
  }

  /// runs of empty lines are one row, and there is none at the top.
  void _addRows(int first, int? beforeIndex, Duration timestamp, List<LrcLine> uiLyricsLines) {
    for (var i = first; i < untimedLines.length; i++) {
      final untimed = untimedLines[i];
      if (untimed.beforeIndex != beforeIndex) break;
      final text = untimed.text;
      if (text.isEmpty) {
        if (!keepsEmptyLines) continue;
        final previous = uiLyricsLines.lastOrNull;
        if (previous == null || _isEmptyRow(previous)) continue;
      }
      uiLyricsLines.add(
        LrcLine(
          timestamp: timestamp,
          originalIndex: uiLyricsLines.length + 0.2,
          lyrics: text,
          readableText: text,
          type: LrcTypes.simple,
          parts: null,
          person: null,
          isRTL: LrcParser.isLrcLineRTL(text),
          isUntimed: true,
        ),
      );
    }
  }

  static bool _isEmptyRow(LrcLine line) => line.isUntimed && line.readableText.isEmpty;
}

List<LrcLinePart>? _mergeParts(
  List<LrcLinePart>? parts,
  Duration Function(Duration timestamp)? toUiTimestamp, {
  int minDurationMs = 250,
}) {
  if (parts == null || parts.isEmpty) return parts;

  final merged = <LrcLinePart>[];
  var current = parts[0];

  for (var i = 1; i < parts.length; i++) {
    final next = parts[i];
    final duration = current.endTimestamp.inMilliseconds - current.startTimestamp.inMilliseconds;

    if (duration < minDurationMs) {
      current = LrcLinePart(
        startTimestamp: current.startTimestamp,
        endTimestamp: next.endTimestamp,
        lyrics: current.lyrics + next.lyrics,
      );
    } else {
      merged.add(_partToUi(current, toUiTimestamp));
      current = next;
    }
  }
  merged.add(_partToUi(current, toUiTimestamp));
  return merged;
}

LrcLinePart _partToUi(
  LrcLinePart part,
  Duration Function(Duration timestamp)? toUiTimestamp,
) {
  if (toUiTimestamp == null) return part;
  return LrcLinePart(
    startTimestamp: toUiTimestamp(part.startTimestamp),
    endTimestamp: toUiTimestamp(part.endTimestamp),
    lyrics: part.lyrics,
  );
}

LrcLine? _romanized(
  LrcLine line,
  int index,
  Duration lineTimestamp,
  String Function(int index, String text) romanizer,
) {
  final txt = line.readableText;
  if (txt.isEmpty) return null;
  final romanized = romanizer(index, txt);
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
