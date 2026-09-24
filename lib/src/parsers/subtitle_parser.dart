/// this file is built by claude
part of lrc;

/// The supported subtitle formats.
enum SubtitleFormat {
  /// SubRip (.srt)
  srt,

  /// WebVTT (.vtt)
  vtt,

  /// SubViewer / YouTube (.sbv)
  sbv,

  /// SubStation Alpha (.ssa) & Advanced SubStation Alpha (.ass)
  ssa,
}

/// Parses subtitle formats (SRT, WebVTT, SBV, SSA/ASS) into an [Lrc].
///
/// Each cue becomes an [LrcLine] with a single [LrcLinePart] spanning the
/// cue's start & end. Karaoke timings (WebVTT inline timestamps & SSA/ASS
/// `{\k}` tags) produce enhanced lines with a part per segment.
/// Speaker names (WebVTT `<v Name>` tags & SSA/ASS `Name` field) are
/// mapped to [LrcLine.person].
class SubtitleParser {
  static final _htmlUnescape = HtmlUnescape();

  static final _tagRegex = RegExp(r'</?[a-zA-Z][^>]*>');
  static final _braceTagRegex = RegExp(r'\{[^{}]*\}');

  static final _srtTimingRegex = RegExp(
      r'(\d{1,2}:\d{1,2}:\d{1,2}[,.]\d{1,3})\s*-->\s*(\d{1,2}:\d{1,2}:\d{1,2}[,.]\d{1,3})');
  static final _vttTimingRegex = RegExp(
      r'((?:\d{1,2}:)?\d{1,2}:\d{2}\.\d{1,3})\s*-->\s*((?:\d{1,2}:)?\d{1,2}:\d{2}\.\d{1,3})');
  static final _vttInlineTimestampRegex =
      RegExp(r'<((?:\d{1,2}:)?\d{1,2}:\d{2}\.\d{1,3})>');
  static final _vttVoiceRegex = RegExp(r'<v(?:\.[^\s>]*)?\s+([^>]+)>');
  static final _sbvTimingRegex = RegExp(
      r'^\s*(\d{1,2}:\d{2}:\d{2}\.\d{1,3})\s*,\s*(\d{1,2}:\d{2}:\d{2}\.\d{1,3})\s*$');
  static final _assKaraokeRegex = RegExp(r'\\[kK][fo]?(\d+)');

  static bool isValid(String content) => detectFormat(content) != null;

  /// Detects the subtitle format of [content], or null if unknown.
  static SubtitleFormat? detectFormat(String content) {
    var start = 0;
    final length = content.length;
    while (start < length) {
      final c = content.codeUnitAt(start);
      if (c == 0xFEFF /* BOM */ || LrcParser._isEmptyCodeUnit(c)) {
        start++;
      } else {
        break;
      }
    }
    if (content.startsWith('WEBVTT', start)) return SubtitleFormat.vtt;
    if (content.contains('Dialogue:') &&
        (content.contains('[Events]') || content.contains('[Script Info]'))) {
      return SubtitleFormat.ssa;
    }
    if (_srtTimingRegex.hasMatch(content)) return SubtitleFormat.srt;
    if (RegExp(_sbvTimingRegex.pattern, multiLine: true).hasMatch(content)) {
      return SubtitleFormat.sbv;
    }
    return null;
  }

  /// Parses a subtitle string of any supported format, detecting the
  /// format automatically. Throws a `FormatException` if the format
  /// is not recognized.
  static Lrc parse(String content) {
    final format = detectFormat(content);
    return switch (format) {
      SubtitleFormat.srt => parseSrt(content),
      SubtitleFormat.vtt => parseVtt(content),
      SubtitleFormat.sbv => parseSbv(content),
      SubtitleFormat.ssa => parseSsa(content),
      null => throw const FormatException(
          'The inputted string is not a valid subtitle format'),
    };
  }

  static Lrc parseSrt(String content) {
    final lines = LrcParser._splitLines(content);
    final cues = <_SubtitleCue>[];
    for (var i = 0; i < lines.length; i++) {
      final m = _srtTimingRegex.firstMatch(lines[i]);
      if (m == null) continue;
      final startMs = _timestampToMs(m.group(1)!);
      final endMs = _timestampToMs(m.group(2)!);
      final textBuffer = StringBuffer();
      while (++i < lines.length) {
        final textLine = lines[i].trim();
        if (textLine.isEmpty) break;
        // -- tolerate a missing blank line before the next cue
        if (int.tryParse(textLine) != null &&
            i + 1 < lines.length &&
            _srtTimingRegex.hasMatch(lines[i + 1])) {
          i--;
          break;
        }
        if (textBuffer.isNotEmpty) textBuffer.write(' ');
        textBuffer.write(textLine);
      }
      cues.add(_SubtitleCue(
        startMs: startMs,
        endMs: endMs,
        text: _cleanMarkup(textBuffer.toString()),
      ));
    }
    return _buildLrc(cues);
  }

  static Lrc parseVtt(String content) {
    final lines = LrcParser._splitLines(content);
    final cues = <_SubtitleCue>[];
    var skipBlock = false;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (skipBlock) {
        if (trimmed.isEmpty) skipBlock = false;
        continue;
      }
      if (trimmed.startsWith('NOTE') ||
          trimmed.startsWith('STYLE') ||
          trimmed.startsWith('REGION')) {
        skipBlock = true;
        continue;
      }
      final m = _vttTimingRegex.firstMatch(lines[i]);
      if (m == null) continue;
      final startMs = _timestampToMs(m.group(1)!);
      final endMs = _timestampToMs(m.group(2)!);
      final textBuffer = StringBuffer();
      while (++i < lines.length && lines[i].trim().isNotEmpty) {
        if (textBuffer.isNotEmpty) textBuffer.write(' ');
        textBuffer.write(lines[i].trim());
      }
      final text = textBuffer.toString();

      final speaker = _vttVoiceRegex.firstMatch(text)?.group(1)?.trim();

      List<LrcLinePart>? parts;
      if (_vttInlineTimestampRegex.hasMatch(text)) {
        parts = [];
        var lastIndex = 0;
        var segStartMs = startMs;
        for (final im in _vttInlineTimestampRegex.allMatches(text)) {
          final segText =
              _cleanMarkup(text.substring(lastIndex, im.start), trim: false);
          final stampMs = _timestampToMs(im.group(1)!);
          if (segText.isNotEmpty) {
            parts.add(LrcLinePart(
              startTimestamp: Duration(milliseconds: segStartMs),
              endTimestamp: Duration(milliseconds: stampMs),
              lyrics: segText,
            ));
          }
          segStartMs = stampMs;
          lastIndex = im.end;
        }
        final tail = _cleanMarkup(text.substring(lastIndex), trim: false);
        if (tail.isNotEmpty) {
          parts.add(LrcLinePart(
            startTimestamp: Duration(milliseconds: segStartMs),
            endTimestamp: Duration(milliseconds: endMs),
            lyrics: tail,
          ));
        }
      }

      cues.add(_SubtitleCue(
        startMs: startMs,
        endMs: endMs,
        text: _cleanMarkup(text),
        speaker: speaker,
        karaokeParts: parts,
      ));
    }
    return _buildLrc(cues);
  }

  static Lrc parseSbv(String content) {
    final lines = LrcParser._splitLines(content);
    final cues = <_SubtitleCue>[];
    for (var i = 0; i < lines.length; i++) {
      final m = _sbvTimingRegex.firstMatch(lines[i]);
      if (m == null) continue;
      final startMs = _timestampToMs(m.group(1)!);
      final endMs = _timestampToMs(m.group(2)!);
      final textBuffer = StringBuffer();
      while (++i < lines.length && lines[i].trim().isNotEmpty) {
        if (textBuffer.isNotEmpty) textBuffer.write(' ');
        textBuffer.write(lines[i].trim());
      }
      cues.add(_SubtitleCue(
        startMs: startMs,
        endMs: endMs,
        text: _cleanMarkup(textBuffer.toString().replaceAll('[br]', ' ')),
      ));
    }
    return _buildLrc(cues);
  }

  static Lrc parseSsa(String content) {
    final lines = LrcParser._splitLines(content);
    final cues = <_SubtitleCue>[];
    String? title, author;

    // default v4+ events field order
    var startIdx = 1, endIdx = 2, nameIdx = 4, textIdx = 9;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (title == null && line.startsWith('Title:')) {
        title = line.substring(6).trim();
        continue;
      }
      if (author == null && line.startsWith('Original Script:')) {
        author = line.substring(16).trim();
        continue;
      }
      if (line.startsWith('Format:')) {
        final fields = line
            .substring(7)
            .split(',')
            .map((f) => f.trim().toLowerCase())
            .toList();
        final s = fields.indexOf('start');
        final e = fields.indexOf('end');
        final t = fields.indexOf('text');
        // -- only apply the events format, not the styles one
        if (s >= 0 && e >= 0 && t >= 0) {
          startIdx = s;
          endIdx = e;
          nameIdx = fields.indexOf('name');
          textIdx = t;
        }
        continue;
      }
      if (!line.startsWith('Dialogue:')) continue;
      try {
        final fields = line.substring(9).split(',');
        if (fields.length <= textIdx) continue;
        final startMs = _timestampToMs(fields[startIdx].trim());
        final endMs = _timestampToMs(fields[endIdx].trim());
        final speaker = nameIdx >= 0 && nameIdx < fields.length
            ? fields[nameIdx].trim()
            : null;
        // -- the text field is always last, commas inside it are allowed
        final text = fields.sublist(textIdx).join(',');
        cues.add(_SubtitleCue(
          startMs: startMs,
          endMs: endMs,
          text: _cleanAssText(text.replaceAll(_braceTagRegex, '')),
          speaker: speaker,
          karaokeParts: _extractAssKaraoke(text, startMs),
        ));
      } catch (_) {}
    }
    return _buildLrc(cues, title: title, author: author);
  }

  /// Converts SSA/ASS `{\k<centiseconds>}` karaoke tags into parts,
  /// or null if [text] has no karaoke tags.
  static List<LrcLinePart>? _extractAssKaraoke(String text, int startMs) {
    if (!_assKaraokeRegex.hasMatch(text)) return null;

    final parts = <LrcLinePart>[];
    var lastIndex = 0;
    var segStartMs = startMs;
    int? segDurMs;
    final segText = StringBuffer();

    void flush() {
      final t = _cleanAssText(segText.toString(), trim: false);
      segText.clear();
      final dur = segDurMs;
      if (dur != null) {
        if (t.isNotEmpty) {
          parts.add(LrcLinePart(
            startTimestamp: Duration(milliseconds: segStartMs),
            endTimestamp: Duration(milliseconds: segStartMs + dur),
            lyrics: t,
          ));
        }
        segStartMs += dur;
      } else if (t.isNotEmpty) {
        // -- text before the first karaoke tag
        parts.add(LrcLinePart(
          startTimestamp: Duration(milliseconds: segStartMs),
          endTimestamp: Duration(milliseconds: segStartMs),
          lyrics: t,
        ));
      }
    }

    for (final m in _braceTagRegex.allMatches(text)) {
      segText.write(text.substring(lastIndex, m.start));
      lastIndex = m.end;
      final k = _assKaraokeRegex.firstMatch(m.group(0)!);
      if (k != null) {
        flush();
        segDurMs = (int.tryParse(k.group(1)!) ?? 0) * 10;
      }
    }
    segText.write(text.substring(lastIndex));
    flush();
    return parts;
  }

  static Lrc _buildLrc(
    List<_SubtitleCue> cues, {
    String? title,
    String? author,
  }) {
    final personToIndex = <String, int>{};
    final lines = <LrcLine>[];
    var type = LrcTypes.simple;

    for (final cue in cues) {
      final karaokeParts = cue.karaokeParts;
      final hasKaraoke = karaokeParts != null && karaokeParts.isNotEmpty;
      if (!hasKaraoke && cue.text.isEmpty) continue;

      List<LrcLinePart> parts;
      var lineType = LrcTypes.simple;
      String lyrics, readableText;
      if (hasKaraoke) {
        parts = karaokeParts;
        lineType = LrcTypes.enhanced;
        type = LrcTypes.enhanced;
        readableText = parts.map((e) => e.lyrics).join();
        final buffer = StringBuffer();
        for (final p in parts) {
          buffer.write(
              '<${_msToInlineTimestamp(p.startTimestamp.inMilliseconds)}>${p.lyrics}');
        }
        buffer.write('<${_msToInlineTimestamp(cue.endMs)}>');
        lyrics = buffer.toString();
      } else {
        parts = [
          LrcLinePart(
            startTimestamp: Duration(milliseconds: cue.startMs),
            endTimestamp: Duration(milliseconds: cue.endMs),
            lyrics: cue.text,
          )
        ];
        lyrics = cue.text;
        readableText = cue.text;
      }

      int? person;
      final speaker = cue.speaker;
      if (speaker != null && speaker.isNotEmpty) {
        person = personToIndex[speaker] ??= personToIndex.length + 1;
      }

      lines.add(LrcLine(
        timestamp: Duration(milliseconds: cue.startMs),
        originalIndex: lines.length,
        lyrics: lyrics,
        readableText: readableText,
        type: lineType,
        parts: parts,
        person: person,
        isRTL: LrcParser.isLrcLineRTL(readableText),
      ));
    }

    // -- ssa/ass dialogues are not guaranteed to be in order
    lines.sort((a, b) {
      final res =
          a.timestamp.inMicroseconds.compareTo(b.timestamp.inMicroseconds);
      if (res == 0) return a.originalIndex.compareTo(b.originalIndex);
      return res;
    });

    var personCount = personToIndex.length;
    if (personCount <= 0) personCount = 1;

    return Lrc(
      type: type,
      lyrics: lines,
      title: title,
      author: author,
      personCount: personCount,
    );
  }

  static int _timestampToMs(String raw) =>
      _TtmlLineExtractorXml._timestampToMilliseconds(raw.replaceAll(',', '.'));

  static String _msToInlineTimestamp(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  static String _cleanMarkup(String text, {bool trim = true}) {
    var t = text.replaceAll(_tagRegex, '').replaceAll(_braceTagRegex, '');
    if (t.contains('&')) t = _htmlUnescape.convert(t);
    return trim ? t.trim() : t;
  }

  static String _cleanAssText(String text, {bool trim = true}) {
    var t = text
        .replaceAll(r'\N', ' ')
        .replaceAll(r'\n', ' ')
        .replaceAll(r'\h', ' ');
    return trim ? t.trim() : t;
  }
}

class _SubtitleCue {
  final int startMs;
  final int endMs;
  final String text;
  final String? speaker;
  final List<LrcLinePart>? karaokeParts;

  const _SubtitleCue({
    required this.startMs,
    required this.endMs,
    required this.text,
    this.speaker,
    this.karaokeParts,
  });
}
