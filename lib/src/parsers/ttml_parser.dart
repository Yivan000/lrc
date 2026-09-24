part of lrc;

class TtmlParser {
  static final _extractors = <_TtmlLineExtractorBase>[
    _TtmlLineExtractorRegex(),
    _TtmlLineExtractorXml(),
  ];

  static bool isValid(String content) =>
      _extractors.any((extr) => extr.isValid(content));

  static Lrc parse(String content) {
    Lrc? lrc;
    for (final extr in _extractors) {
      lrc = _parseInternal(content, extr);
      if (lrc.lyrics.isNotEmpty) return lrc;
    }
    return lrc!;
  }

  static Lrc _parseInternal(String content, _TtmlLineExtractorBase extractor) {
    final lrcLines = <LrcLine>[];
    final personToIndex = <String, int>{};
    final htmlUnescape = HtmlUnescape();
    var type = LrcTypes.simple;

    for (final m in extractor.allMatches(content)) {
      int? startMS;
      // int? endMS;
      try {
        startMS = extractor.extractStartMS(m);
        // endMS = (double.parse(m.group(2)!) * 1000).round();
      } catch (_) {}
      if (startMS != null) {
        final textOriginal = extractor.extractText(m);
        String textNormalized;
        if (textOriginal != null && textOriginal.isNotEmpty) {
          textNormalized = htmlUnescape.convert(textOriginal);
        } else {
          textNormalized = '';
        }
        final indexOfPartStart = textNormalized.indexOf('<');
        final personText = indexOfPartStart > 0
            ? textNormalized.substring(0, indexOfPartStart)
            : '';
        final person = personToIndex[personText] ??= personToIndex.length + 1;
        var parts =
            LrcParser.extractTimeStampPartFromLine(textNormalized).toList();
        final lineType = parts.isNotEmpty ? LrcTypes.enhanced : LrcTypes.simple;
        if (lineType == LrcTypes.enhanced) type = LrcTypes.enhanced;
        final readableText = parts.isNotEmpty
            ? parts.map((e) => e.lyrics).join()
            : textNormalized;
        lrcLines.add(LrcLine(
          timestamp: Duration(milliseconds: startMS),
          originalIndex: lrcLines.length,
          lyrics: textNormalized,
          readableText: readableText,
          type: lineType,
          parts: parts,
          person: person,
          isRTL: LrcParser.isLrcLineRTL(readableText),
        ));
      }
    }

    return Lrc(
      lyrics: lrcLines,
      type: type,
    );
  }
}

class _TtmlLineExtractorXml extends _TtmlLineExtractorBase<XmlElement> {
  @override
  bool isValid(String content) => content.contains('<p begin=');

  @override
  Iterable<XmlElement> allMatches(String content) {
    final document = XmlDocument.parse(content);
    return document.findAllElements('p');
  }

  @override
  int? extractStartMS(XmlElement p) {
    try {
      final begin = p.getAttribute('begin');
      if (begin != null && begin.isNotEmpty) {
        return _timestampToMilliseconds(begin);
      }
    } catch (_) {}
    return null;
  }

  @override
  int? extractEndMS(XmlElement p) {
    try {
      final end = p.getAttribute('end');
      if (end != null && end.isNotEmpty) {
        return _timestampToMilliseconds(end);
      }
    } catch (_) {}
    return null;
  }

  static String _msToLrcTimestamp(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    final centiseconds = (ms % 1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${centiseconds.toString().padLeft(2, '0')}';
  }

  @override
  String? extractText(XmlElement p) {
    final spans = p
        .findElements('span')
        .where((s) =>
            s.getAttribute('ttm:role') != 'x-bg' &&
            s.getAttribute('begin') != null)
        .toList();

    if (spans.isEmpty) return p.innerText.trim();
    if (spans.length == 1) return spans.first.innerText.trim();

    final buffer = StringBuffer();
    for (final span in spans) {
      final beginMs = _timestampToMilliseconds(span.getAttribute('begin')!);
      buffer.write('<${_msToLrcTimestamp(beginMs)}>${span.innerText.trim()} ');
    }
    final end = p.getAttribute('end');
    if (end != null) {
      final endMs = _timestampToMilliseconds(end);
      buffer.write('<${_msToLrcTimestamp(endMs)}>');
    }
    return buffer.isEmpty ? null : buffer.toString();
  }

  static int _timestampToMilliseconds(String timestamp) {
    final colonParts = timestamp.split(':');

    var hours = 0, minutes = 0;
    String secondsRaw;

    if (colonParts.length == 3) {
      hours = int.tryParse(colonParts[0]) ?? 0;
      minutes = int.tryParse(colonParts[1]) ?? 0;
      secondsRaw = colonParts[2];
    } else if (colonParts.length == 2) {
      minutes = int.tryParse(colonParts[0]) ?? 0;
      secondsRaw = colonParts[1];
    } else {
      secondsRaw = colonParts[0];
    }

    final secondsParts = secondsRaw.split('.');
    final seconds = int.tryParse(secondsParts[0]) ?? 0;
    var milliseconds = 0;
    if (secondsParts.length > 1) {
      final msString = secondsParts[1].padRight(3, '0').substring(0, 3);
      milliseconds = int.tryParse(msString) ?? 0;
    }

    return (hours * 3_600_000) +
        (minutes * 60_000) +
        (seconds * 1_000) +
        milliseconds;
  }
}

class _TtmlLineExtractorRegex extends _TtmlLineExtractorBase<RegExpMatch> {
  static final _regexp = RegExp(
    r'<p[^>]*?begin="([\d:.]+)s?"[^>]*?end="([\d:.]+)s?"[^>]*?>(.*?)<\/p>',
    multiLine: true,
    dotAll: true,
  );

  @override
  bool isValid(String content) => _regexp.hasMatch(content);

  @override
  Iterable<RegExpMatch> allMatches(String content) {
    return _regexp.allMatches(content);
  }

  @override
  int? extractStartMS(RegExpMatch m) {
    try {
      final raw = m.group(1)!;
      return _TtmlLineExtractorXml._timestampToMilliseconds(raw);
    } catch (_) {}
    return null;
  }

  @override
  int? extractEndMS(RegExpMatch m) {
    try {
      final raw = m.group(2)!;
      return _TtmlLineExtractorXml._timestampToMilliseconds(raw);
    } catch (_) {}
    return null;
  }

  @override
  String? extractText(RegExpMatch m) {
    final raw = m.group(3) ?? '';
    final spanRegex = RegExp(r'<span[^>]*begin="([^"]+)"[^>]*>([^<]*)<\/span>');
    final spans = spanRegex.allMatches(raw).toList();

    if (spans.isEmpty) return raw;
    if (spans.length == 1) return spans.first.group(2)?.trim();

    final buffer = StringBuffer();
    for (final span in spans) {
      final beginMs =
          _TtmlLineExtractorXml._timestampToMilliseconds(span.group(1)!);
      buffer.write(
          '<${_TtmlLineExtractorXml._msToLrcTimestamp(beginMs)}>${span.group(2)?.trim()} ');
    }
    final end = m.group(2);
    if (end != null) {
      final endMs = _TtmlLineExtractorXml._timestampToMilliseconds(end);
      buffer.write('<${_TtmlLineExtractorXml._msToLrcTimestamp(endMs)}>');
    }
    return buffer.isEmpty ? null : buffer.toString();
  }
}

abstract class _TtmlLineExtractorBase<T> {
  bool isValid(String content);
  Iterable<T> allMatches(String content);
  int? extractStartMS(T item);
  int? extractEndMS(T item);
  String? extractText(T item);
}
