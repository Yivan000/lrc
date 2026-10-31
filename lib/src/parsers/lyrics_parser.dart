// by claude
part of lrc;

/// Parses lyrics of any supported format. The format is guessed from the start of the content so only its parser runs,
/// the rest are tried in [_LyricsFormat.fallbacks] order only when that one fails, and plain text is rejected without running any.
class LyricsParser {
  static const _FormatGuess _kNoTimings = (format: null, hasTimings: false);

  static bool isValid(String content) {
    final (format: guess, :hasTimings) = _guessFormat(content);
    if (guess != null && guess.isValid(content)) return true;
    final mayHaveTimings = hasTimings ?? _mayHaveTimings(content);
    if (!mayHaveTimings) return false;
    for (final format in _LyricsFormat.fallbacks) {
      if (format != guess && format.isValid(content)) return true;
    }
    return false;
  }

  /// Returns null when [content] has no timed lines in any supported format.
  static Lrc? parse(String content) {
    final (format: guess, :hasTimings) = _guessFormat(content);
    if (guess != null) {
      final lrc = guess.tryParse(content);
      if (lrc != null) return lrc;
    }
    final mayHaveTimings = hasTimings ?? _mayHaveTimings(content);
    if (!mayHaveTimings) return null;
    for (final format in _LyricsFormat.fallbacks) {
      if (format == guess) continue;
      final lrc = format.tryParse(content);
      if (lrc != null) return lrc;
    }
    return null;
  }

  /// Content starting with text is guessed from its first timing, found by the same pass that rejects plain text.
  static _FormatGuess _guessFormat(String content) {
    final start = LrcParser._contentStart(content);
    if (start == content.length) return _kNoTimings;
    final first = content.codeUnitAt(start);
    if (first == 0x7B /* { */ || first == 0x5B /* [ */) {
      if (PaxsenixJsonParser._jsonStart(content) >= 0) return (format: _LyricsFormat.paxsenixJson, hasTimings: null);
    }
    if (first == 0x3C /* < */) {
      final isQrcXml = content.contains(QrcParser._kXmlContentAttribute, start);
      final format = isQrcXml ? _LyricsFormat.qrc : _LyricsFormat.ttml;
      return (format: format, hasTimings: null);
    }
    final isSubtitle = _isDigit(first) || // srt, sbv
        content.startsWith('WEBVTT', start) ||
        content.startsWith('[Script Info]', start);
    if (isSubtitle) return (format: _LyricsFormat.subtitle, hasTimings: null);

    if (first == 0x5B /* [ */) {
      final timingOpen = _indexOfTimingOpen(content, start);
      if (timingOpen >= 0) {
        final format = _guessBracketFormat(content, timingOpen);
        return (format: format, hasTimings: true);
      }
    }
    final timingStart = _indexOfFirstTiming(content);
    if (timingStart < 0) return _kNoTimings;
    final isBracketTiming = content.codeUnitAt(timingStart) == 0x5B /* [ */;
    final format = isBracketTiming ? _guessBracketFormat(content, timingStart) : null;
    return (format: format, hasTimings: true);
  }

  static _LyricsFormat _guessBracketFormat(String content, int timingOpen) {
    final qrcTiming = QrcParser._scanTiming(content, timingOpen + 1, 0x5D /* ] */);
    if (qrcTiming.end >= 0) return _LyricsFormat.qrc;
    final wordTiming = WlrcParser._scanWordTiming(content, timingOpen);
    return wordTiming.end >= 0 ? _LyricsFormat.wlrc : _LyricsFormat.lrc;
  }

  static bool _mayHaveTimings(String content) => _indexOfFirstTiming(content) >= 0;

  /// Start of something every format needs before it can have a timed line, looked for in a single pass.
  static int _indexOfFirstTiming(String content) {
    final length = content.length;
    for (var i = 0; i < length; i++) {
      final isTimingStart = switch (content.codeUnitAt(i)) {
        0x5B /* [ */ => i + 1 < length && _isDigit(content.codeUnitAt(i + 1)), // lrc, wlrc, qrc
        0x2D /* - */ => content.startsWith('-->', i), // srt, vtt
        0x62 /* b */ => content.startsWith('begin', i), // ttml
        0x44 /* D */ => content.startsWith('Dialogue:', i), // ssa
        0x3A /* : */ => _isClockMinutesAt(content, i), // sbv
        _ => false,
      };
      if (isTimingStart) return i;
    }
    return -1;
  }

  /// `[` followed by a digit.
  static int _indexOfTimingOpen(String content, int from) {
    final lastIndex = content.length - 1;
    var open = content.indexOf('[', from);
    while (open >= 0 && open < lastIndex) {
      final next = content.codeUnitAt(open + 1);
      if (_isDigit(next)) return open;
      open = content.indexOf('[', open + 1);
    }
    return -1;
  }

  /// `:mm:` of a `h:mm:ss` timestamp.
  static bool _isClockMinutesAt(String content, int colon) {
    if (colon + 3 >= content.length) return false;
    return _isDigit(content.codeUnitAt(colon + 1)) && _isDigit(content.codeUnitAt(colon + 2)) && content.codeUnitAt(colon + 3) == 0x3A /* : */;
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
}

/// Declared in the order [LyricsParser] falls back through.
enum _LyricsFormat {
  lrc(isFallback: true),
  ttml(isFallback: true),
  subtitle(isFallback: true),
  paxsenixJson(isFallback: true),
  qrc(isFallback: true),
  wlrc(isFallback: false),
  ;

  const _LyricsFormat({required this.isFallback});

  /// false when lrc parses everything this format does, so it can only be reached by the guess.
  final bool isFallback;

  static final fallbacks = values.where((e) => e.isFallback).toList(growable: false);

  bool isValid(String content) => switch (this) {
        _LyricsFormat.lrc => LrcParser.isValid(content),
        _LyricsFormat.ttml => TtmlParser.isValid(content),
        _LyricsFormat.subtitle => SubtitleParser.isValid(content),
        _LyricsFormat.paxsenixJson => PaxsenixJsonParser.isValid(content),
        _LyricsFormat.qrc => QrcParser.isValid(content),
        _LyricsFormat.wlrc => WlrcParser.isValid(content),
      };

  /// Null when [content] is not of this format or has no lines.
  Lrc? tryParse(String content) {
    try {
      final lrc = switch (this) {
        _LyricsFormat.lrc => LrcParser.parse(content),
        _LyricsFormat.ttml => TtmlParser.parse(content),
        _LyricsFormat.subtitle => SubtitleParser.parse(content),
        _LyricsFormat.paxsenixJson => PaxsenixJsonParser.parse(content),
        _LyricsFormat.qrc => QrcParser.parse(content),
        _LyricsFormat.wlrc => WlrcParser.parse(content),
      };
      if (lrc != null && lrc.lyrics.isNotEmpty) return lrc;
    } catch (_) {}
    return null;
  }
}

/// [hasTimings] is null when the content was not scanned for timings.
typedef _FormatGuess = ({_LyricsFormat? format, bool? hasTimings});
