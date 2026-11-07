part of lrc;

// optimizations by claude
class LrcParser {
  static List<String> _splitLines(String data) {
    var lines = <String>[];
    var end = data.length;
    var sliceStart = 0;
    var char = 0;
    for (var i = 0; i < end; i++) {
      var previousChar = char;
      char = data.codeUnitAt(i);
      if (char != 13) {
        if (char != 10) continue;
        if (previousChar == 13) {
          sliceStart = i + 1;
          continue;
        }
      }
      lines.add(data.substring(sliceStart, i));
      sliceStart = i + 1;
    }
    if (sliceStart < end) lines.add(data.substring(sliceStart, end));
    return lines;
  }

  /// splits at `|` or 2+ spaces followed by a non-space, same as `split(RegExp(r'(\s{2,}|\|)(?=\S)'))`.
  static List<String> splitMultiLanguageLine(String lyric) {
    List<String>? pieces;
    final length = lyric.length;
    var pieceStart = 0;
    var i = 0;
    while (i < length) {
      final c = lyric.codeUnitAt(i);
      var separatorEnd = i + 1;
      if (_isRegexSpace(c)) {
        while (separatorEnd < length && _isRegexSpace(lyric.codeUnitAt(separatorEnd))) {
          separatorEnd++;
        }
        if (separatorEnd - i < 2) {
          i = separatorEnd;
          continue;
        }
      } else if (c != 0x7C /* | */) {
        i++;
        continue;
      }
      if (separatorEnd < length && !_isRegexSpace(lyric.codeUnitAt(separatorEnd))) {
        (pieces ??= <String>[]).add(lyric.substring(pieceStart, i));
        pieceStart = separatorEnd;
      }
      i = separatorEnd;
    }
    if (pieces == null) return [lyric];
    pieces.add(lyric.substring(pieceStart));
    return pieces;
  }

  /// Collapses runs of whitespace into a single space,
  /// returning [s] itself when nothing needs collapsing.
  static String _collapseSpaces(String s) {
    final length = s.length;
    var i = 0;
    for (; i < length - 1; i++) {
      if (_isEmptyCodeUnit(s.codeUnitAt(i)) && _isEmptyCodeUnit(s.codeUnitAt(i + 1))) {
        break;
      }
    }
    if (i >= length - 1) return s;
    final buffer = StringBuffer(s.substring(0, i + 1));
    var previousWasSpace = true;
    for (i++; i < length; i++) {
      final c = s.codeUnitAt(i);
      if (_isEmptyCodeUnit(c)) {
        if (previousWasSpace) continue;
        previousWasSpace = true;
        buffer.writeCharCode(0x20);
      } else {
        previousWasSpace = false;
        buffer.writeCharCode(c);
      }
    }
    return buffer.toString();
  }

  static const _kTrailingPartFallbackDuration = Duration(seconds: 1);

  /// `mm:ss` or `mm:ss.xx`, null when invalid.
  static Duration? parseTimestamp(String text) => _LRCMultiTimestampParser.extractMainTimestamp('[${text.trim()}]');

  static Iterable<LrcLinePart> extractTimeStampPartFromLine(String line, {Duration? startTimeStamp}) => _extractParts(line, startTimeStamp, null, 0);

  static Iterable<LrcLinePart> _extractParts(
    String line,
    Duration? startTimeStamp,
    List<String>? followingLines,
    int followingLinesStart,
  ) sync* {
    var isFirst = true;
    var latestTimeStamp = startTimeStamp;
    var trailingIndex = 0;
    Duration? firstPartStart;
    var partsCount = 0;
    var textStart = 0;
    final length = line.length;
    for (var i = 0; i < length; i++) {
      final c = line.codeUnitAt(i);
      if (c == 0x5D /* ] */) {
        textStart = i + 1;
        continue;
      }
      if (c != 0x3C /* < */) continue;
      final (:end, :micros) = _LRCMultiTimestampParser._scanTimestamp(line, i + 1, 0x3E /* > */);
      if (end < 0) {
        textStart = i + 1;
        continue;
      }
      final lyrics = _collapseSpaces(line.substring(textStart, i));
      final endTimestamp = Duration(microseconds: micros);
      textStart = end;
      trailingIndex = end;
      i = end - 1;
      final startTimestamp = latestTimeStamp;
      latestTimeStamp = endTimestamp;
      if (startTimestamp == null) {
        // we set the start for the next part
        continue;
      }
      if (isFirst) {
        // -- skip empty first part, happens when the line timestamp
        // -- is followed directly by the first word timestamp
        if (lyrics.isEmpty) {
          continue;
        }
        // -- skip first part that has `v1:` etc
        if (lyrics.length < 5 && lyrics.startsWith('v') && (lyrics.endsWith(':') || lyrics.endsWith(': '))) {
          continue;
        }
      }
      yield LrcLinePart(
        startTimestamp: startTimestamp,
        endTimestamp: endTimestamp,
        lyrics: lyrics,
      );
      firstPartStart ??= startTimestamp;
      partsCount++;
      isFirst = false;
    }

    if (trailingIndex == 0 || trailingIndex == line.length) return;
    if (latestTimeStamp == null) return;
    final trailingLyrics = _collapseSpaces(line.substring(trailingIndex));
    if (trailingLyrics.trim().isEmpty) return;
    final trailingStart = latestTimeStamp;
    var trailingEnd = followingLines == null ? null : _nextLineTimestampAfter(followingLines, followingLinesStart, trailingStart);
    if (trailingEnd == null) {
      final averageDuration = firstPartStart == null ? _kTrailingPartFallbackDuration : (trailingStart - firstPartStart) ~/ partsCount;
      trailingEnd = trailingStart + averageDuration;
    }
    yield LrcLinePart(
      startTimestamp: trailingStart,
      endTimestamp: trailingEnd,
      lyrics: trailingLyrics,
    );
  }

  // -- skips translations and overlapping duet lines that don't pass [minimum]
  static Duration? _nextLineTimestampAfter(
    List<String> lines,
    int fromIndex,
    Duration minimum,
  ) {
    for (var i = fromIndex; i < lines.length; i++) {
      final timestamp = _LRCMultiTimestampParser.extractMainTimestamp(lines[i]);
      if (timestamp != null && timestamp > minimum) return timestamp;
    }
    return null;
  }

  static List<LrcLinePart> _shiftParts(
    List<LrcLinePart> parts,
    Duration shift,
  ) {
    if (shift == Duration.zero) return parts;
    return [
      for (final part in parts)
        LrcLinePart(
          startTimestamp: part.startTimestamp + shift,
          endTimestamp: part.endTimestamp + shift,
          lyrics: part.lyrics,
        ),
    ];
  }

  /// Parses an LRC from a string. Throws a `FormatExeption`
  /// if the inputted string is not valid.
  static Lrc parse(String content) {
    if (!isValid(content)) {
      throw FormatException('The inputted string is not a valid LRC file');
    }

    // split string into lines, code from Linesplitter().convert(data)
    final contentWithoutBOM = content.startsWith('﻿') ? content.substring(1) : content;
    var lines = _splitLines(contentWithoutBOM);

    // temporary storer variables
    final tags = <String, String>{};
    LrcTypes? type;
    var lyrics = <LrcLine>[];
    List<LrcUntimedLine>? untimedLines;
    List<String>? pendingUntimedTexts;

    final personToIndex = <String, int>{};
    var latestTimestamp = Duration.zero;
    var shouldSortLyrics = false;

    // loop thru each lines
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      var l = lines[lineIndex];
      final trimmedLine = l.trim();
      final tagColonIndex = _tagColonIndex(trimmedLine);
      if (tagColonIndex > 0) {
        final tag = trimmedLine.substring(1, tagColonIndex);
        if (tag != _kBackgroundTag && !tags.containsKey(tag)) tags[tag] = _tagValue(trimmedLine, tagColonIndex);
      }

      final lrclineDetails = _LRCMultiTimestampParser.parseLine(l);
      if (lrclineDetails == null) {
        final isUntimedText = tagColonIndex < 0 && !trimmedLine.startsWith(_kBackgroundTagStart);
        if (isUntimedText) (pendingUntimedTexts ??= []).add(trimmedLine);
        continue;
      }
      if (pendingUntimedTexts != null) {
        final beforeIndex = lyrics.length;
        final untimed = untimedLines ??= [];
        for (final text in pendingUntimedTexts) {
          untimed.add(LrcUntimedLine(text: text, beforeIndex: beforeIndex));
        }
        pendingUntimedTexts = null;
      }
      var lineType = LrcTypes.simple;
      List<LrcLinePart>? parts;

      var lyric = lrclineDetails.lineText;
      final timestamps = lrclineDetails.timestamps;

      int? person;

      // checkers for different types of LRCs
      if (_hasWordTimestamp(lyric)) {
        // if enhanced
        type = (type == LrcTypes.extended) ? LrcTypes.extended_enhanced : LrcTypes.enhanced;
        parts = [];
        lineType = LrcTypes.enhanced;

        final indexOfLT = lyric.indexOf('<');
        final personText = indexOfLT < 0 ? '' : lyric.substring(0, indexOfLT);
        if (personText.contains(':')) {
          person = personToIndex[personText];
          if (person == null) {
            try {
              final numberString = RegExp(r'v(\d+):').firstMatch(personText)?[1];
              if (numberString != null) {
                person = int.tryParse(numberString);
              }
            } catch (_) {}
          }
          person ??= personToIndex.length + 1;
          personToIndex[personText] = person;
          lyric = lyric.substring(indexOfLT); // ensure
        }

        parts.addAll(
          _extractParts(lyric, timestamps.first, lines, lineIndex + 1),
        );
      } else if (_isExtendedLine(lyric)) {
        //if extended
        type = (type == LrcTypes.enhanced) ? LrcTypes.extended_enhanced : LrcTypes.extended;

        final personText = lyric[0];
        person = personToIndex[personText] ??= personToIndex.length + 1;

        parts = [];
        parts.add(LrcLinePart(
          startTimestamp: timestamps.first,
          endTimestamp: timestamps.first,
          lyrics: lyric.substring(2),
        ));

        lineType = LrcTypes.extended;
      } else {
        // -- plain line, strip `v1: ` etc prefix
        final prefix = _personPrefix(lyric);
        if (prefix != null) {
          final (vIndex, colonEnd) = prefix;
          final personText = lyric.substring(vIndex, colonEnd);
          person = personToIndex[personText];
          if (person == null) {
            person = int.tryParse(lyric.substring(vIndex + 1, colonEnd - 1));
            person ??= personToIndex.length + 1;
            personToIndex[personText] = person;
          }
          var prefixEnd = colonEnd;
          while (prefixEnd < lyric.length && lyric.codeUnitAt(prefixEnd) == 32) {
            prefixEnd++;
          }
          lyric = lyric.substring(prefixEnd);
        }
      }

      final lyricSplit = parts != null && parts.length > 1 ? List.filled(1, lyric, growable: false) : splitMultiLanguageLine(lyric);
      for (var lyric in lyricSplit) {
        final readableTextPre = parts != null && parts.isNotEmpty ? parts.map((e) => e.lyrics).join() : lyric;
        for (final linetimestamp in timestamps) {
          if (linetimestamp < latestTimestamp) shouldSortLyrics = true;
          latestTimestamp = linetimestamp;
          final readableText = readableTextPre.isNotEmpty ? readableTextPre : lyric;
          final partsShift = linetimestamp - timestamps.first;
          final lineParts = parts == null ? null : _shiftParts(parts, partsShift);
          lyrics.add(LrcLine(
            timestamp: linetimestamp,
            originalIndex: lyrics.length,
            lyrics: lyric,
            readableText: readableText,
            type: lineType,
            parts: lineParts,
            person: person,
            isRTL: LrcParser.isLrcLineRTL(readableText),
          ));
        }
      }
    }

    if (type == LrcTypes.enhanced || type == LrcTypes.extended_enhanced) {
      // extract bg tags
      var bgIndex = content.indexOf(_kBackgroundTagStart);
      while (bgIndex >= 0) {
        final textStart = bgIndex + 4;
        final textEnd = _lastIndexOnLine(content, 0x5D /* ] */, textStart);
        final nextSearchStart = textEnd < 0 ? bgIndex + 1 : textEnd + 1;
        bgIndex = content.indexOf(_kBackgroundTagStart, nextSearchStart);
        if (textEnd < 0) continue;
        final text = content.substring(textStart, textEnd);
        final parts = extractTimeStampPartFromLine(text).toList();
        if (parts.isEmpty) continue;
        final readableText = parts.map((e) => e.lyrics).join();
        final timestamp = parts[0].startTimestamp;
        lyrics.add(LrcLine(
          timestamp: timestamp,
          originalIndex: lyrics.length,
          lyrics: text,
          readableText: readableText,
          type: type ?? LrcTypes.enhanced,
          parts: parts,
          person: 0,
          isRTL: LrcParser.isLrcLineRTL(readableText),
        ));
        if (timestamp < latestTimestamp) shouldSortLyrics = true;
        latestTimestamp = timestamp;
      }
    }

    if (shouldSortLyrics) lyrics.sort(_compareLines);

    var personCount = personToIndex.values.where((element) => element > 0).length;
    if (personCount <= 0) personCount = 1;

    if (pendingUntimedTexts != null) {
      final untimed = untimedLines ??= [];
      for (final text in pendingUntimedTexts) {
        untimed.add(LrcUntimedLine(text: text, beforeIndex: null));
      }
    }

    return Lrc(
      type: type ?? LrcTypes.simple,
      tags: tags,
      lyrics: lyrics,
      untimedLines: untimedLines ?? const [],
      personCount: personCount,
    );
  }

  static int _compareLines(LrcLine a, LrcLine b) {
    final res = a.timestamp.inMicroseconds.compareTo(b.timestamp.inMicroseconds);
    if (res == 0) return a.originalIndex.compareTo(b.originalIndex);
    return res;
  }

  static int _contentStart(String content) {
    final length = content.length;
    var start = 0;
    while (start < length) {
      final c = content.codeUnitAt(start);
      if (c != 0xFEFF /* BOM */ && !_isEmptyCodeUnit(c)) break;
      start++;
    }
    return start;
  }

  /// Finds a `v<digits>:` person prefix at the start of [lyric],
  /// allowing leading spaces. Returns the index of `v` and the index
  /// right after `:`, or null if there is no such prefix.
  static (int, int)? _personPrefix(String lyric) {
    final length = lyric.length;
    var start = 0;
    while (start < length && lyric.codeUnitAt(start) == 0x20) {
      start++;
    }
    if (start + 3 > length || lyric.codeUnitAt(start) != 0x76 /* v */) {
      return null;
    }
    for (var i = start + 1; i < length; i++) {
      final c = lyric.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) continue; // digit
      return (c == 0x3A /* : */ && i > start + 1) ? (start, i + 1) : null;
    }
    return null;
  }

  static const _kBackgroundTag = 'bg';
  static const _kBackgroundTagStart = '[$_kBackgroundTag:';

  /// a tag key is lowercase `a-z`, digits, `_` or `-`, so `[Verse 1: Name]` stays a text line.
  static int _tagColonIndex(String l) {
    final length = l.length;
    if (length < 5) return -1;
    if (l.codeUnitAt(0) != 0x5B /* [ */ || l.codeUnitAt(length - 1) != 0x5D /* ] */) return -1;
    final c = l.codeUnitAt(1);
    if (c < 0x61 || c > 0x7A) return -1; // a-z
    for (var i = 2; i < length - 1; i++) {
      final k = l.codeUnitAt(i);
      if (k == 0x3A /* : */) return i;
      final isKeyCodeUnit = (k >= 0x61 && k <= 0x7A) || (k >= 0x30 && k <= 0x39) || k == 0x5F /* _ */ || k == 0x2D /* - */;
      if (!isKeyCodeUnit) return -1;
    }
    return -1;
  }

  static String _tagValue(String l, int tagColonIndex) => l.substring(tagColonIndex + 1, l.length - 1).trim();

  /// replaces the first `[tag:]` line, or adds one at the top. lines end like in [_splitLines].
  static String _setTagLine(String content, String tag, String? value) {
    final length = content.length;
    final contentStart = content.startsWith('﻿') ? 1 : 0;
    var lineStart = contentStart;
    while (lineStart < length) {
      var lineEnd = lineStart;
      while (lineEnd < length && !_isLineBreak(content.codeUnitAt(lineEnd))) {
        lineEnd++;
      }
      var nextLineStart = lineEnd;
      if (nextLineStart < length && content.codeUnitAt(nextLineStart) == 0x0D) nextLineStart++;
      if (nextLineStart < length && content.codeUnitAt(nextLineStart) == 0x0A) nextLineStart++;

      var textStart = lineStart;
      while (textStart < lineEnd && _isEmptyCodeUnit(content.codeUnitAt(textStart))) {
        textStart++;
      }
      final mayBeTag = textStart < lineEnd && content.codeUnitAt(textStart) == 0x5B /* [ */;
      if (mayBeTag) {
        final line = content.substring(textStart, lineEnd).trimRight();
        final tagColonIndex = _tagColonIndex(line);
        final isTheTag = tagColonIndex > 0 && tagColonIndex - 1 == tag.length && line.startsWith(tag, 1);
        if (isTheTag) {
          if (value == null) return content.replaceRange(lineStart, nextLineStart, '');
          return content.replaceRange(lineStart, lineEnd, '[$tag:$value]');
        }
      }
      lineStart = nextLineStart;
    }
    if (value == null) return content;
    final lineBreak = content.contains('\r\n') ? '\r\n' : '\n';
    return content.replaceRange(contentStart, contentStart, '[$tag:$value]$lineBreak');
  }

  static bool _isLineBreak(int c) => c == 0x0A || c == 0x0D;

  static bool _hasWordTimestamp(String lyric) {
    var open = lyric.indexOf('<');
    while (open >= 0) {
      final scanned = _LRCMultiTimestampParser._scanTimestamp(lyric, open + 1, 0x3E /* > */);
      if (scanned.end >= 0) return true;
      open = lyric.indexOf('<', open + 1);
    }
    return false;
  }

  /// same as `RegExp(r'^\w:')`.
  static bool _isExtendedLine(String lyric) {
    if (lyric.length < 2 || lyric.codeUnitAt(1) != 0x3A /* : */) return false;
    final c = lyric.codeUnitAt(0);
    return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
  }

  static int _lastIndexOnLine(String s, int codeUnit, int from) {
    var found = -1;
    for (var i = from; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (_isLineTerminator(c)) break;
      if (c == codeUnit) found = i;
    }
    return found;
  }

  /// Checks if the string [input] is a valid LRC, same as `RegExp(r'\[(\d{1,}).+\]').hasMatch(input)`.
  static bool isValid(String input) {
    final length = input.length;
    var open = input.indexOf('[');
    while (open >= 0 && open + 3 < length) {
      final c = input.codeUnitAt(open + 1);
      if (c < 0x30 || c > 0x39) {
        open = input.indexOf('[', open + 1);
        continue;
      }
      var i = open + 2;
      for (; i < length; i++) {
        final lineChar = input.codeUnitAt(i);
        if (_isLineTerminator(lineChar)) break;
        if (lineChar == 0x5D /* ] */ && i >= open + 3) return true;
      }
      // -- any other `[` before this line end would need the same missing `]`
      open = input.indexOf('[', i);
    }
    return false;
  }

  static String cleanPlainLyrics(String input) {
    final regex = RegExp(r'([\r\n]*\[((ti)|(a[rlu])|(by)|([rv]e)|(length)|(offset)|(la)):.+\][\r\n]*)');
    return input.replaceAll(regex, '');
  }

  static bool isLrcLineRTL(String part, {int maxChars = 3}) {
    var rtlMeter = 0; // increment for rtl, decrement for ltr

    var checkedCharsCount = 0;
    for (final codeUnit in part.codeUnits) {
      if (_isRTLCodeUnit(codeUnit)) {
        rtlMeter++;
      } else if (_isEmptyCodeUnit(codeUnit)) {
        if (rtlMeter != 0) break; // reached space and good enough
      } else {
        rtlMeter--;
      }

      checkedCharsCount++;
      if (checkedCharsCount >= maxChars) break;
    }

    final isRTL = rtlMeter > 0;
    return isRTL;
  }

  // by claude
  static bool _isRTLCodeUnit(int codeUnit) {
    // Arabic, Syriac, Arabic Supplement, Thaana
    if (codeUnit >= 0x0600 && codeUnit <= 0x07BF) return true;
    // Arabic Presentation Forms-A
    if (codeUnit >= 0xFB50 && codeUnit <= 0xFDFF) return true;
    // Arabic Presentation Forms-B
    if (codeUnit >= 0xFE70 && codeUnit <= 0xFEFF) return true;
    // Hebrew
    if (codeUnit >= 0x0591 && codeUnit <= 0x05F4) return true;
    return false;
  }

  static bool _isRegexSpace(int c) {
    if (c <= 0x20) return c == 0x20 || (c >= 0x09 && c <= 0x0D);
    if (c < 0xA0) return false;
    return c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF;
  }

  static bool _isLineTerminator(int c) => c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029;

  // by claude
  static bool _isEmptyCodeUnit(int codeUnit) {
    return codeUnit == 0x20 || // space
        codeUnit == 0x09 || // tab
        codeUnit == 0x0A || // line feed
        codeUnit == 0x0D; // carriage return
  }
}
