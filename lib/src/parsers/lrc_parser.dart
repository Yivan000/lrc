part of lrc;

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

  static List<String> splitMultiLanguageLine(String lyric) {
    return lyric.split(RegExp(r'(\s{2,}|\|)(?=\S)'));
  }

  static final _partRegex =
      RegExp(r'([^<\]]*)<(([0-9]{1,}):([0-9]{1,})(?:\.([0-9]{1,}))?)>');

  /// Collapses runs of whitespace into a single space,
  /// returning [s] itself when nothing needs collapsing.
  static String _collapseSpaces(String s) {
    final length = s.length;
    var i = 0;
    for (; i < length - 1; i++) {
      if (_isEmptyCodeUnit(s.codeUnitAt(i)) &&
          _isEmptyCodeUnit(s.codeUnitAt(i + 1))) {
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

  static Iterable<LrcLinePart> extractTimeStampPartFromLine(String line,
      {Duration? startTimeStamp}) sync* {
    var isFirst = true;
    var latestTimeStamp = startTimeStamp;
    for (var j in _partRegex.allMatches(line)) {
      final lyrics = _collapseSpaces(j.group(1) ?? '');
      final endTimestamp = _LRCMultiTimestampParser._durationFromStrings(
        minutes: j.group(3),
        seconds: j.group(4),
        hundreds: j.group(5),
      );
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
        if (lyrics.length < 5 &&
            lyrics.startsWith('v') &&
            (lyrics.endsWith(':') || lyrics.endsWith(': '))) {
          continue;
        }
      }
      yield LrcLinePart(
        startTimestamp: startTimestamp,
        endTimestamp: endTimestamp,
        lyrics: lyrics,
      );
      isFirst = false;
    }
  }

  /// Parses an LRC from a string. Throws a `FormatExeption`
  /// if the inputted string is not valid.
  static Lrc parse(String content) {
    if (!isValid(content)) {
      throw FormatException('The inputted string is not a valid LRC file');
    }

    // split string into lines, code from Linesplitter().convert(data)
    var lines = _splitLines(content);

    // temporary storer variables
    String? artist,
        album,
        title,
        length,
        author,
        creator,
        offset,
        program,
        version,
        language;
    LrcTypes? type;
    var lyrics = <LrcLine>[];

    final personToIndex = <String, int>{};
    var registeredTimestamps = <Duration>{};
    var shouldSortLyrics = false;

    String? setIfMatchTag(String toMatch, String tag) =>
        (RegExp(r'^\[' + tag + r':.*\]$').hasMatch(toMatch))
            ? toMatch.substring(tag.length + 2, toMatch.length - 1).trim()
            : null;

    // loop thru each lines
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      var l = lines[lineIndex];
      artist ??= setIfMatchTag(l, 'ar');
      album ??= setIfMatchTag(l, 'al');
      title ??= setIfMatchTag(l, 'ti');
      author ??= setIfMatchTag(l, 'au');
      length ??= setIfMatchTag(l, 'length');
      creator ??= setIfMatchTag(l, 'by');
      offset ??= setIfMatchTag(l, 'offset');
      program ??= setIfMatchTag(l, 're');
      version ??= setIfMatchTag(l, 've');
      language ??= setIfMatchTag(l, 'la');

      if (_LRCMultiTimestampParser._durRegex.hasMatch(l)) {
        var lineType = LrcTypes.simple;
        List<LrcLinePart>? parts;

        final lrclineDetails = _LRCMultiTimestampParser.parseLine(l);
        var lyric = lrclineDetails.lineText;
        final timestamps = lrclineDetails.timestamps;

        if (shouldSortLyrics == false) {
          if (timestamps.length > 1) {
            // -- means it has multi timestamps
            shouldSortLyrics = true;
          }
          if (timestamps
              .any((element) => registeredTimestamps.contains(element))) {
            // -- means it has multi language in the end of the file
            shouldSortLyrics = true;
          }
        }

        int? person;

        // checkers for different types of LRCs
        if (lyric.contains(RegExp(r'<[0-9]{1,}:[0-9]{1,}(\.[0-9]{1,})?>'))) {
          // if enhanced
          type = (type == LrcTypes.extended)
              ? LrcTypes.extended_enhanced
              : LrcTypes.enhanced;
          parts = [];
          lineType = LrcTypes.enhanced;

          final indexOfLT = lyric.indexOf('<');
          final personText = indexOfLT < 0 ? '' : lyric.substring(0, indexOfLT);
          if (personText.contains(':')) {
            person = personToIndex[personText];
            if (person == null) {
              try {
                final numberString =
                    RegExp(r'v(\d+):').firstMatch(personText)?[1];
                if (numberString != null) {
                  person = int.tryParse(numberString);
                }
              } catch (_) {}
            }
            person ??= personToIndex.length + 1;
            personToIndex[personText] = person;
            lyric = lyric.substring(indexOfLT); // ensure
          }

          if (!lyric.endsWith('>')) {
            for (var next = lineIndex + 1; next < lines.length; next++) {
              final nextTimestamp =
                  _LRCMultiTimestampParser.extractMainTimestamp(lines[next]);
              if (nextTimestamp != null) {
                lyric = '$lyric<$nextTimestamp>';
                break;
              }
            }
          }
          parts.addAll(
            extractTimeStampPartFromLine(
              lyric,
              startTimeStamp: timestamps.first,
            ),
          );
        } else if (lyric.contains(RegExp(r'^\w:'))) {
          //if extended
          type = (type == LrcTypes.enhanced)
              ? LrcTypes.extended_enhanced
              : LrcTypes.extended;

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
            while (
                prefixEnd < lyric.length && lyric.codeUnitAt(prefixEnd) == 32) {
              prefixEnd++;
            }
            lyric = lyric.substring(prefixEnd);
          }
        }

        final lyricSplit = parts != null && parts.length > 1
            ? List.filled(1, lyric, growable: false)
            : splitMultiLanguageLine(lyric);
        for (var lyric in lyricSplit) {
          final readableTextPre = parts != null && parts.isNotEmpty
              ? parts.map((e) => e.lyrics).join()
              : lyric;
          for (final linetimestamp in timestamps) {
            registeredTimestamps.add(linetimestamp);
            final readableText =
                readableTextPre.isNotEmpty ? readableTextPre : lyric;
            lyrics.add(LrcLine(
              timestamp: linetimestamp,
              originalIndex: lyrics.length,
              lyrics: lyric,
              readableText: readableText,
              type: lineType,
              parts: parts,
              person: person,
              isRTL: LrcParser.isLrcLineRTL(readableText),
            ));
          }
        }
      }
    }

    if (type == LrcTypes.enhanced || type == LrcTypes.extended_enhanced) {
      // extract bg tags
      for (final m in RegExp(r'\[bg:(.*)\]').allMatches(content)) {
        final text = m.group(1);
        if (text == null) continue;
        final parts = extractTimeStampPartFromLine(text).toList();
        if (parts.isEmpty) continue;
        final readableText = parts.map((e) => e.lyrics).join();
        lyrics.add(LrcLine(
          timestamp: parts[0].startTimestamp,
          originalIndex: lyrics.length,
          lyrics: text,
          readableText: readableText,
          type: type ?? LrcTypes.enhanced,
          parts: parts,
          person: 0,
          isRTL: LrcParser.isLrcLineRTL(readableText),
        ));
        shouldSortLyrics = true;
      }
    }

    if (shouldSortLyrics) {
      lyrics.sort((a, b) {
        final res =
            a.timestamp.inMicroseconds.compareTo(b.timestamp.inMicroseconds);
        if (res == 0) {
          return a.originalIndex.compareTo(b.originalIndex);
        }
        return res;
      });
    }

    var personCount =
        personToIndex.values.where((element) => element > 0).length;
    if (personCount <= 0) personCount = 1;

    return Lrc(
      type: type ?? LrcTypes.simple,
      artist: artist,
      album: album,
      title: title,
      author: author,
      length: length,
      creator: creator,
      offset: (offset != null) ? int.tryParse(offset) : null,
      program: program,
      version: version,
      lyrics: lyrics,
      language: language,
      personCount: personCount,
    );
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

  /// Checks if the string [input] is a valid LRC using Regex.
  static bool isValid(String input) =>
      RegExp(r'\[(\d{1,}).+\]').hasMatch(input);

  static String cleanPlainLyrics(String input) {
    final regex = RegExp(
        r'([\r\n]*\[((ti)|(a[rlu])|(by)|([rv]e)|(length)|(offset)|(la)):.+\][\r\n]*)');
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

  // by claude
  static bool _isEmptyCodeUnit(int codeUnit) {
    return codeUnit == 0x20 || // space
        codeUnit == 0x09 || // tab
        codeUnit == 0x0A || // line feed
        codeUnit == 0x0D; // carriage return
  }
}
