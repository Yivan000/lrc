// by claude
part of lrc;

/// Parses word synced lyrics that have each word on its own `[mm:ss.xxx]-[mm:ss.xxx]word` line (deezer and musixmatch exports, `.wlrc`).
///
/// A lyrics line ends at an empty line or `[newline]`. `[offset:ms]` lines add up and the total is added to every word after them.
class WlrcParser {
  static const _ScannedWordTiming _kNoWordTiming = (end: -1, startMicros: 0, endMicros: 0);
  static const _kNewLineTag = '[newline]';
  static const _kOffsetTagStart = '[offset:';

  /// Cheap check for a word timing, [parse] can still return null.
  static bool isValid(String content) {
    var open = content.indexOf('[');
    while (open >= 0) {
      final wordTiming = _scanWordTiming(content, open);
      if (wordTiming.end >= 0) return true;
      open = content.indexOf('[', open + 1);
    }
    return false;
  }

  /// Returns null if [content] has no word timing lines.
  static Lrc? parse(String content) {
    final lines = LrcParser._splitLines(content);

    final lyrics = <LrcLine>[];
    final words = <_WlrcWord>[];
    var offsetMicros = 0;
    var latestTimestamp = Duration.zero;
    var shouldSortLyrics = false;

    void endLine() {
      if (words.isEmpty) return;
      final line = _toLine(words, lyrics.length);
      words.clear();
      if (line.timestamp < latestTimestamp) shouldSortLyrics = true;
      latestTimestamp = line.timestamp;
      lyrics.add(line);
    }

    for (final rawLine in lines) {
      final l = rawLine.trim();
      if (l.isEmpty) {
        endLine();
        continue;
      }

      final (:end, :startMicros, :endMicros) = _scanWordTiming(l, 0);
      if (end >= 0) {
        final text = l.substring(end).trim();
        if (text.isEmpty) continue;
        words.add((
          start: Duration(microseconds: startMicros + offsetMicros),
          end: Duration(microseconds: endMicros + offsetMicros),
          text: text,
        ));
        continue;
      }

      final isNewLineTag = l.length == _kNewLineTag.length && l.toLowerCase() == _kNewLineTag;
      if (isNewLineTag) {
        endLine();
        continue;
      }

      final isOffsetTag = l.startsWith(_kOffsetTagStart) && l.endsWith(']');
      if (isOffsetTag) {
        final offsetText = LrcParser._tagValue(l, _kOffsetTagStart.length - 1);
        final offsetMS = int.tryParse(offsetText);
        if (offsetMS != null) offsetMicros += offsetMS * Duration.microsecondsPerMillisecond;
      }
    }
    endLine();
    if (lyrics.isEmpty) return null;

    if (shouldSortLyrics) lyrics.sort(LrcParser._compareLines);

    return Lrc(
      type: LrcTypes.enhanced,
      lyrics: lyrics,
    );
  }

  static LrcLine _toLine(List<_WlrcWord> words, int originalIndex) {
    final parts = <LrcLinePart>[];
    final readableBuffer = StringBuffer();
    final taggedBuffer = StringBuffer();
    final lastIndex = words.length - 1;
    for (var i = 0; i <= lastIndex; i++) {
      final (:start, :end, :text) = words[i];
      final partText = i == lastIndex ? text : '$text ';
      final startText = SubtitleParser._msToInlineTimestamp(start.inMilliseconds);
      readableBuffer.write(partText);
      taggedBuffer.write('<$startText>');
      taggedBuffer.write(partText);
      parts.add(LrcLinePart(
        startTimestamp: start,
        endTimestamp: end,
        lyrics: partText,
      ));
    }
    final lineEndMS = words[lastIndex].end.inMilliseconds;
    final lineEndText = SubtitleParser._msToInlineTimestamp(lineEndMS);
    taggedBuffer.write('<$lineEndText>');

    final readableText = readableBuffer.toString();
    return LrcLine(
      timestamp: words[0].start,
      originalIndex: originalIndex,
      lyrics: taggedBuffer.toString(),
      readableText: readableText,
      type: LrcTypes.enhanced,
      parts: parts,
      person: null,
      isRTL: LrcParser.isLrcLineRTL(readableText),
    );
  }

  /// `[mm:ss.xxx]-[mm:ss.xxx]` starting at [open], spaces are allowed around `-`.
  static _ScannedWordTiming _scanWordTiming(String s, int open) {
    if (s.codeUnitAt(open) != 0x5B /* [ */) return _kNoWordTiming;
    final startScan = _LRCMultiTimestampParser._scanTimestamp(s, open + 1, 0x5D /* ] */);
    if (startScan.end < 0) return _kNoWordTiming;

    final length = s.length;
    var i = _skipSpaces(s, startScan.end);
    if (i >= length || s.codeUnitAt(i) != 0x2D /* - */) return _kNoWordTiming;
    i = _skipSpaces(s, i + 1);
    if (i >= length || s.codeUnitAt(i) != 0x5B /* [ */) return _kNoWordTiming;

    final endScan = _LRCMultiTimestampParser._scanTimestamp(s, i + 1, 0x5D /* ] */);
    if (endScan.end < 0) return _kNoWordTiming;
    return (end: endScan.end, startMicros: startScan.micros, endMicros: endScan.micros);
  }

  static int _skipSpaces(String s, int from) {
    final length = s.length;
    var i = from;
    while (i < length && s.codeUnitAt(i) == 0x20) {
      i++;
    }
    return i;
  }
}

typedef _WlrcWord = ({Duration start, Duration end, String text});
typedef _ScannedWordTiming = ({int end, int startMicros, int endMicros});
