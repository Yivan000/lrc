// by claude
part of lrc;

/// Parses the word synced QRC lyrics of QQ Music, either the decrypted xml or its `LyricContent` text alone.
///
/// A line is `[startMS,durationMS]` followed by its words, each one followed by its own `(startMS,durationMS)`.
class QrcParser {
  static const _kXmlContentAttribute = 'LyricContent="';
  static const _ScannedQrcTiming _kNoTiming = (end: -1, startMS: 0, durationMS: 0);

  /// Cheap check for a `[startMS,durationMS]` line timing, [parse] can still return null.
  static bool isValid(String content) => _findLineTiming(content).end >= 0;

  /// Returns null if [content] has no qrc lines.
  static Lrc? parse(String content) {
    final lyricContent = _extractLyricContent(content);
    final lines = LrcParser._splitLines(lyricContent);

    final tags = <String, String>{};
    var type = LrcTypes.simple;
    final lyrics = <LrcLine>[];
    var latestTimestamp = Duration.zero;
    var shouldSortLyrics = false;

    for (final l in lines) {
      final tagColonIndex = LrcParser._tagColonIndex(l);
      if (tagColonIndex > 0) {
        final tag = l.substring(1, tagColonIndex);
        if (!tags.containsKey(tag)) tags[tag] = LrcParser._tagValue(l, tagColonIndex);
        continue;
      }

      final (:end, :startMS, durationMS: _) = _findLineTiming(l);
      if (end < 0) continue;
      final lineTimestamp = Duration(milliseconds: startMS);
      final line = _parseLine(l, end, lineTimestamp, lyrics.length);
      if (line.type == LrcTypes.enhanced) type = LrcTypes.enhanced;
      if (lineTimestamp < latestTimestamp) shouldSortLyrics = true;
      latestTimestamp = lineTimestamp;
      lyrics.add(line);
    }
    if (lyrics.isEmpty) return null;

    if (shouldSortLyrics) lyrics.sort(LrcParser._compareLines);

    return Lrc(
      type: type,
      tags: tags,
      lyrics: lyrics,
    );
  }

  /// Text after the last word timing is dropped.
  static LrcLine _parseLine(String l, int textStart, Duration timestamp, int originalIndex) {
    final parts = <LrcLinePart>[];
    final readableBuffer = StringBuffer();
    final taggedBuffer = StringBuffer();
    var lastEndMS = 0;
    var wordStart = textStart;
    var open = l.indexOf('(', textStart);
    while (open >= 0) {
      final (:end, :startMS, :durationMS) = _scanTiming(l, open + 1, 0x29 /* ) */);
      if (end < 0) {
        open = l.indexOf('(', open + 1);
        continue;
      }
      final word = l.substring(wordStart, open);
      lastEndMS = startMS + durationMS;
      readableBuffer.write(word);
      taggedBuffer.write('<${SubtitleParser._msToInlineTimestamp(startMS)}>');
      taggedBuffer.write(word);
      parts.add(LrcLinePart(
        startTimestamp: Duration(milliseconds: startMS),
        endTimestamp: Duration(milliseconds: lastEndMS),
        lyrics: word,
      ));
      wordStart = end;
      open = l.indexOf('(', end);
    }

    if (parts.isEmpty) {
      final text = l.substring(textStart).trim();
      return LrcLine(
        timestamp: timestamp,
        originalIndex: originalIndex,
        lyrics: text,
        readableText: text,
        type: LrcTypes.simple,
        parts: null,
        person: null,
        isRTL: LrcParser.isLrcLineRTL(text),
      );
    }

    taggedBuffer.write('<${SubtitleParser._msToInlineTimestamp(lastEndMS)}>');
    final readableText = readableBuffer.toString();
    return LrcLine(
      timestamp: timestamp,
      originalIndex: originalIndex,
      lyrics: taggedBuffer.toString(),
      readableText: readableText,
      type: LrcTypes.enhanced,
      parts: parts,
      person: null,
      isRTL: LrcParser.isLrcLineRTL(readableText),
    );
  }

  static String _extractLyricContent(String content) {
    final attributeIndex = content.indexOf(_kXmlContentAttribute);
    if (attributeIndex < 0) return content;
    final contentStart = attributeIndex + _kXmlContentAttribute.length;
    final closingQuoteIndex = content.lastIndexOf('"');
    final contentEnd = closingQuoteIndex > contentStart ? closingQuoteIndex : content.length;
    final lyricContent = content.substring(contentStart, contentEnd);
    return _HtmlEntities.decode(lyricContent);
  }

  static _ScannedQrcTiming _findLineTiming(String line) {
    var open = line.indexOf('[');
    while (open >= 0) {
      final scanned = _scanTiming(line, open + 1, 0x5D /* ] */);
      if (scanned.end >= 0) return scanned;
      open = line.indexOf('[', open + 1);
    }
    return _kNoTiming;
  }

  static _ScannedQrcTiming _scanTiming(String s, int start, int closeCodeUnit) {
    final length = s.length;
    var i = start;
    var startMS = 0;
    while (i < length) {
      final digit = s.codeUnitAt(i) - 0x30;
      if (digit < 0 || digit > 9) break;
      startMS = startMS * 10 + digit;
      i++;
    }
    if (i == start || i >= length || s.codeUnitAt(i) != 0x2C /* , */) return _kNoTiming;

    final durationStart = ++i;
    var durationMS = 0;
    while (i < length) {
      final digit = s.codeUnitAt(i) - 0x30;
      if (digit < 0 || digit > 9) break;
      durationMS = durationMS * 10 + digit;
      i++;
    }
    if (i == durationStart || i >= length || s.codeUnitAt(i) != closeCodeUnit) return _kNoTiming;

    return (end: i + 1, startMS: startMS, durationMS: durationMS);
  }
}

typedef _ScannedQrcTiming = ({int end, int startMS, int durationMS});
