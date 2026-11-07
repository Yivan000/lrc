// rewritten by claude, new one is a single pass scanner without an xml tree, and reads agents, background vocals, translations, romanizations and metadata
part of lrc;

/// Parses TTML lyrics (Apple Music, AMLL, ...) in a single pass, no xml tree is built.
///
/// - a `<p>` is a line and its timed `<span>`s are words, words not separated by a space join as syllables.
/// - `ttm:agent` of a `<p>` or its `<div>` is the [LrcLine.person], `v1` is 1 and `v2` is 2, other ids go by declaration order.
/// - `ttm:role="x-bg"` spans are a background vocals line, person 0.
/// - `x-translation` & `x-roman` spans and the head `<translation>`/`<transliteration>` texts of a line's `itunes:key`
///   are lines sharing the timestamp of their line.
/// - lrc text with word timestamps inside a `<p>` (`v1:&lt;00:18.653&gt;They ...`) is read as an enhanced lrc line.
class TtmlParser {
  static const _kDefaultFrameRate = 30.0;

  final String _content;

  TtmlParser._(this._content);

  /// Cheap check for a `<p>` or `<span>` with a `begin`, [parse] can still return no lines.
  static bool isValid(String content) {
    var open = content.indexOf('<');
    while (open >= 0) {
      final nameStart = open + 1;
      final nameEnd = _nameEnd(content, nameStart);
      final element = _elementOf(content, nameStart, nameEnd);
      if (element == _TtmlElement.p || element == _TtmlElement.span) {
        final close = content.indexOf('>', nameEnd);
        if (close < 0) return false;
        if (_hasBeginAttribute(content, nameEnd, close)) return true;
      }
      open = content.indexOf('<', nameStart);
    }
    return false;
  }

  static Lrc parse(String content) => TtmlParser._(content)._read();

  var _frameRate = _kDefaultFrameRate;
  var _tickRate = 1.0;
  var _isTickRateDeclared = false;
  var _isWordSynced = false;
  String? _title, _album, _creator, _language;
  var _lengthMS = -1;
  final _artists = <String>[];
  final _songwriters = <String>[];
  final _agentPersons = <String, int>{};
  final _divPersons = <int?>[];
  var _divsCount = 0;
  final _lines = <_TtmlLine>[];
  final _extrasByKey = <String, List<_TtmlLine>>{};

  Lrc _read() {
    final s = _content;
    final length = s.length;
    var textStart = 0;
    var open = s.indexOf('<');
    while (open >= 0 && open + 1 < length) {
      final next = s.codeUnitAt(open + 1);
      if (_isNameStartCodeUnit(next)) {
        final nameEnd = _nameEnd(s, open + 1);
        final element = _elementOf(s, open + 1, nameEnd);
        final tagEnd = _readAttributes(element, nameEnd);
        if (tagEnd < 0) break;
        _onText(textStart, open);
        final isSelfClosing = s.codeUnitAt(tagEnd - 2) == 0x2F /* / */;
        _onStartTag(element, isSelfClosing);
        textStart = tagEnd;
      } else if (next == 0x2F /* / */) {
        final nameEnd = _nameEnd(s, open + 2);
        final close = s.indexOf('>', nameEnd);
        if (close < 0) break;
        _onText(textStart, open);
        final element = _elementOf(s, open + 2, nameEnd);
        _onEndTag(element);
        textStart = close + 1;
      } else if (next == 0x21 /* ! */ || next == 0x3F /* ? */) {
        final isCData = s.startsWith('[CDATA[', open + 2);
        final terminator = switch (next) {
          0x3F => '?>',
          _ when isCData => ']]>',
          _ when s.startsWith('--', open + 2) => '-->',
          _ => '>',
        };
        final close = s.indexOf(terminator, open + 2);
        if (close < 0) break;
        _onText(textStart, open);
        if (isCData) _onText(open + 9, close, isRaw: true);
        textStart = close + terminator.length;
      } else {
        // -- a literal `<`, like the word timestamps of lrc text
        open = s.indexOf('<', open + 1);
        continue;
      }
      open = s.indexOf('<', textStart);
    }
    final textEnd = open >= 0 ? open : length;
    _onText(textStart, textEnd);
    if (_line != null) _closeLine();
    return _buildLrc();
  }

  var _tagBeginMS = -1;
  var _tagEndMS = -1;
  var _tagDurMS = -1;
  var _tagRole = _TtmlRole.none;
  String? _tagAgent, _tagKey, _tagValue;

  /// The index after the tag's `>`, -1 when it is never closed.
  int _readAttributes(_TtmlElement element, int start) {
    final s = _content;
    final length = s.length;
    final isTracked = element != _TtmlElement.other;
    if (isTracked) {
      _tagBeginMS = -1;
      _tagEndMS = -1;
      _tagDurMS = -1;
      _tagRole = _TtmlRole.none;
      _tagAgent = null;
      _tagKey = null;
      _tagValue = null;
    }
    var i = start;
    while (i < length) {
      final c = s.codeUnitAt(i);
      if (c == 0x3E /* > */) return i + 1;
      if (c <= 0x20 || c == 0x2F /* / */) {
        i++;
        continue;
      }
      final nameStart = i;
      while (i < length) {
        final nameCodeUnit = s.codeUnitAt(i);
        if (nameCodeUnit == 0x3D /* = */ || nameCodeUnit == 0x3E /* > */ || nameCodeUnit == 0x2F /* / */ || nameCodeUnit <= 0x20) break;
        i++;
      }
      final nameEnd = i;
      while (i < length && s.codeUnitAt(i) <= 0x20) {
        i++;
      }
      if (i >= length || s.codeUnitAt(i) != 0x3D /* = */) continue;
      i++;
      while (i < length && s.codeUnitAt(i) <= 0x20) {
        i++;
      }
      if (i >= length) return -1;
      final quote = s.codeUnitAt(i);
      final int valueStart;
      final int valueEnd;
      if (quote == 0x22 /* " */ || quote == 0x27 /* ' */) {
        valueStart = i + 1;
        final quoteText = quote == 0x22 ? '"' : "'";
        valueEnd = s.indexOf(quoteText, valueStart);
        if (valueEnd < 0) return -1;
        i = valueEnd + 1;
      } else {
        valueStart = i;
        while (i < length) {
          final valueCodeUnit = s.codeUnitAt(i);
          if (valueCodeUnit == 0x3E /* > */ || valueCodeUnit <= 0x20) break;
          i++;
        }
        valueEnd = i;
      }
      if (isTracked) _readAttribute(element, nameStart, nameEnd, valueStart, valueEnd);
    }
    return -1;
  }

  void _readAttribute(_TtmlElement element, int nameStart, int nameEnd, int valueStart, int valueEnd) {
    final attribute = _attributeOf(_content, nameStart, nameEnd);
    switch (attribute) {
      case _TtmlAttribute.begin:
        _tagBeginMS = _timeMS(valueStart, valueEnd);
      case _TtmlAttribute.end:
        _tagEndMS = _timeMS(valueStart, valueEnd);
      case _TtmlAttribute.dur:
        _tagDurMS = _timeMS(valueStart, valueEnd);
      case _TtmlAttribute.agent:
        _tagAgent = _textOf(valueStart, valueEnd);
      case _TtmlAttribute.key || _TtmlAttribute.forKey:
        _tagKey = _textOf(valueStart, valueEnd);
      case _TtmlAttribute.id:
        if (element == _TtmlElement.agent) _tagKey = _textOf(valueStart, valueEnd);
      case _TtmlAttribute.value:
        _tagValue = _textOf(valueStart, valueEnd);
      case _TtmlAttribute.role:
        _tagRole = _roleOf(valueStart, valueEnd);
      case _TtmlAttribute.ruby:
        final isRubyText = _valueEquals(valueStart, valueEnd, 'text') || _valueEquals(valueStart, valueEnd, 'textContainer');
        if (isRubyText) _tagRole = _TtmlRole.ignored;
      case _TtmlAttribute.lang:
        if (element == _TtmlElement.tt) _language = _textOf(valueStart, valueEnd);
      case _TtmlAttribute.timing:
        if (element == _TtmlElement.tt) _isWordSynced = _valueEquals(valueStart, valueEnd, 'Word');
      case _TtmlAttribute.frameRate:
        if (element != _TtmlElement.tt) return;
        final frameRate = double.tryParse(_content.substring(valueStart, valueEnd));
        if (frameRate == null || frameRate <= 0) return;
        _frameRate = frameRate;
        if (!_isTickRateDeclared) _tickRate = frameRate;
      case _TtmlAttribute.tickRate:
        if (element != _TtmlElement.tt) return;
        final tickRate = double.tryParse(_content.substring(valueStart, valueEnd));
        if (tickRate == null || tickRate <= 0) return;
        _tickRate = tickRate;
        _isTickRateDeclared = true;
      case _TtmlAttribute.other:
        break;
    }
  }

  int _resolvedTagEndMS() {
    if (_tagEndMS >= 0) return _tagEndMS;
    if (_tagBeginMS < 0 || _tagDurMS < 0) return -1;
    return _tagBeginMS + _tagDurMS;
  }

  // -- [_track] is null inside ignored text like ruby annotations
  _TtmlLine? _line;
  var _lineElement = _TtmlElement.p;
  _TtmlTrack? _track;
  _TtmlWord? _word;
  final _frames = <_TtmlFrame>[];

  StringBuffer? _capture;

  void _onStartTag(_TtmlElement element, bool isSelfClosing) {
    final line = _line;
    if (line != null) {
      if (element != _lineElement) {
        _onStartTagInLine(line, element, isSelfClosing);
        return;
      }
      // -- the previous line was never closed
      _closeLine();
    }
    switch (element) {
      case _TtmlElement.p:
        final agent = _tagAgent;
        final person = agent == null ? _divPersons.lastOrNull : _personOf(agent);
        final ttmlLine = _TtmlLine(
          beginMS: _tagBeginMS,
          endMS: _resolvedTagEndMS(),
          person: person,
          key: _tagKey,
          isBackground: _tagRole == _TtmlRole.background,
          divNumber: _divsCount,
        );
        _openLine(ttmlLine, element, isSelfClosing);
      case _TtmlElement.text:
        final key = _tagKey;
        if (key == null) return;
        final ttmlLine = _TtmlLine(beginMS: -1, endMS: -1, person: null, key: key, isBackground: false, divNumber: _divsCount);
        _openLine(ttmlLine, element, isSelfClosing);
      case _TtmlElement.div:
        if (isSelfClosing) return;
        final agent = _tagAgent;
        final person = agent == null ? _divPersons.lastOrNull : _personOf(agent);
        _divPersons.add(person);
        _divsCount++;
      case _TtmlElement.body:
        if (_tagDurMS >= 0) _lengthMS = _tagDurMS;
      case _TtmlElement.agent:
        final id = _tagKey;
        if (id != null) _personOf(id);
      case _TtmlElement.meta:
        _readMeta(_tagKey, _tagValue);
      case _TtmlElement.title || _TtmlElement.songwriter:
        if (!isSelfClosing) _capture = StringBuffer();
      case _TtmlElement.tt || _TtmlElement.span || _TtmlElement.br || _TtmlElement.other:
        break;
    }
  }

  void _onStartTagInLine(_TtmlLine line, _TtmlElement element, bool isSelfClosing) {
    if (!isSelfClosing) _frames.add((track: _track, word: _word));
    if (element == _TtmlElement.br) {
      _onLineBreak();
      return;
    }
    if (element != _TtmlElement.span || isSelfClosing) return;
    final track = _track;
    if (track == null) return;
    switch (_tagRole) {
      case _TtmlRole.none:
        final beginMS = _tagBeginMS;
        if (beginMS < 0) return;
        final word = _TtmlWord(beginMS, _resolvedTagEndMS());
        track.words.add(word);
        _word = word;
      case _TtmlRole.background:
        final background = line.background ??= _TtmlTrack();
        background.extendTiming(_tagBeginMS, _resolvedTagEndMS());
        _track = background;
        _word = null;
      case _TtmlRole.translationOrRoman:
        final extra = _TtmlTrack();
        final extras = track.extras ??= [];
        extras.add(extra);
        _track = extra;
        _word = null;
      case _TtmlRole.ignored:
        _track = null;
        _word = null;
    }
  }

  void _onEndTag(_TtmlElement element) {
    if (_line != null) {
      if (element == _lineElement) {
        _closeLine();
        return;
      }
      if (_frames.isEmpty) return;
      final frame = _frames.removeLast();
      _track = frame.track;
      _word = frame.word;
      return;
    }
    switch (element) {
      case _TtmlElement.div:
        if (_divPersons.isNotEmpty) _divPersons.removeLast();
      case _TtmlElement.title:
        final title = _takeCapture();
        if (title != null) _title ??= title;
      case _TtmlElement.songwriter:
        final songwriter = _takeCapture();
        if (songwriter != null) _songwriters.add(songwriter);
      default:
        break;
    }
  }

  void _onText(int start, int end, {bool isRaw = false}) {
    if (start >= end) return;
    if (_line == null) {
      _capture?.write(_textOf(start, end, isRaw: isRaw));
      return;
    }
    final track = _track;
    if (track == null) return;
    final word = _word;
    if (word != null) {
      word.append(_textOf(start, end, isRaw: isRaw));
      return;
    }
    final words = track.words;
    if (words.isEmpty) {
      track.appendTextBeforeWords(_textOf(start, end, isRaw: isRaw));
      return;
    }
    // -- blank text between words separates them, unless it holds a line break, which is only indentation
    final s = _content;
    var hasLineBreak = false;
    for (var i = start; i < end; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x0A || c == 0x0D) {
        hasLineBreak = true;
      } else if (c != 0x20 && c != 0x09) {
        words.last.append(_textOf(start, end, isRaw: isRaw));
        return;
      }
    }
    if (!hasLineBreak) words.last.append(' ');
  }

  void _onLineBreak() {
    final word = _word;
    if (word != null) {
      word.append(' ');
      return;
    }
    final track = _track;
    if (track == null) return;
    final words = track.words;
    if (words.isEmpty) {
      track.appendTextBeforeWords(' ');
    } else {
      words.last.append(' ');
    }
  }

  void _openLine(_TtmlLine line, _TtmlElement element, bool isSelfClosing) {
    _line = line;
    _lineElement = element;
    _track = line.main;
    _word = null;
    _frames.clear();
    if (isSelfClosing) _closeLine();
  }

  void _closeLine() {
    final line = _line;
    _line = null;
    _track = null;
    _word = null;
    if (line == null) return;
    final backgroundWordsCount = line.background?.words.length ?? 0;
    if (line.main.words.length > 1 || backgroundWordsCount > 1) _isWordSynced = true;
    if (_lineElement == _TtmlElement.p) {
      _lines.add(line);
      return;
    }
    final key = line.key;
    if (key == null) return;
    final extras = _extrasByKey[key] ??= [];
    extras.add(line);
  }

  void _readMeta(String? key, String? value) {
    if (key == null || value == null || value.isEmpty) return;
    switch (key) {
      case 'musicName':
        _title ??= value;
      case 'artists':
        _artists.add(value);
      case 'album':
        _album ??= value;
      case 'ttmlAuthorGithubLogin':
        _creator ??= value;
    }
  }

  String? _takeCapture() {
    final capture = _capture;
    _capture = null;
    if (capture == null) return null;
    final text = _collapseWhitespace(capture.toString()).trim();
    return text.isEmpty ? null : text;
  }

  int _personOf(String agentId) {
    final cached = _agentPersons[agentId];
    if (cached != null) return cached;
    final voiceNumber = PaxsenixJsonParser._agentToPerson(agentId);
    final isVoiceNumber = voiceNumber != null && voiceNumber > 0;
    final person = isVoiceNumber ? voiceNumber : _agentPersons.length + 1;
    _agentPersons[agentId] = person;
    return person;
  }

  final _lyrics = <LrcLine>[];
  final _persons = <int>{};
  var _type = LrcTypes.simple;
  var _latestTimestamp = Duration.zero;
  var _shouldSortLyrics = false;

  /// a `<div>` is a verse, its first line gets an empty untimed line above it.
  Lrc _buildLrc() {
    List<LrcUntimedLine>? untimedLines;
    var previousDivNumber = -1;
    for (final line in _lines) {
      final firstLineIndex = _lyrics.length;
      _addLinesOf(line);
      if (_lyrics.length == firstLineIndex) continue;
      final divNumber = line.divNumber;
      final isNewDiv = previousDivNumber >= 0 && divNumber != previousDivNumber;
      previousDivNumber = divNumber;
      if (isNewDiv) (untimedLines ??= []).add(LrcUntimedLine(text: '', beforeIndex: firstLineIndex));
    }
    if (_shouldSortLyrics) _lyrics.sort(LrcParser._compareLines);

    final artist = _artists.isEmpty ? null : _artists.join(', ');
    final author = _songwriters.isEmpty ? null : _songwriters.join(', ');
    final length = _lengthMS < 0 ? null : LrcLine.formatTimestamp(Duration(milliseconds: _lengthMS));
    final personCount = _persons.isEmpty ? 1 : _persons.length;
    final title = _title;
    final album = _album;
    final creator = _creator;
    final language = _language;
    return Lrc(
      type: _type,
      lyrics: _lyrics,
      tags: {
        if (artist != null) 'ar': artist,
        if (album != null) 'al': album,
        if (title != null) 'ti': title,
        if (author != null) 'au': author,
        if (creator != null) 'by': creator,
        if (length != null) Lrc.kLengthTag: length,
        if (language != null) 'la': language,
      },
      untimedLines: untimedLines ?? const [],
      personCount: personCount,
    );
  }

  void _addLinesOf(_TtmlLine line) {
    final main = line.main;
    final background = line.background;
    final backgroundWordStartMS = background?.firstWordStartMS ?? -1;
    final backgroundBeginMS = background?.beginMS ?? -1;
    final backgroundStartMS = backgroundWordStartMS >= 0 ? backgroundWordStartMS : backgroundBeginMS;
    final mainWordStartMS = main.firstWordStartMS;
    final mainStartMS = line.beginMS >= 0 ? line.beginMS : mainWordStartMS;
    final timestampMS = mainStartMS >= 0 ? mainStartMS : backgroundStartMS;
    if (timestampMS < 0) return;

    final key = line.key;
    final headExtras = key == null ? null : _extrasByKey[key];
    final person = line.isBackground ? 0 : line.person;
    final mainLine = _toLrcLine(main, timestampMS, line.endMS, person);
    if (mainLine != null) {
      _addLine(mainLine);
      _addExtraLines(main.extras, headExtras, timestampMS, line.endMS, person, isBackground: false);
    } else if (background == null) {
      _addLine(_emptyLine(timestampMS));
    }

    if (background == null) return;
    final backgroundTimestampMS = backgroundStartMS >= 0 ? backgroundStartMS : timestampMS;
    final backgroundEndMS = background.endMS >= 0 ? background.endMS : line.endMS;
    final backgroundLine = _toLrcLine(background, backgroundTimestampMS, backgroundEndMS, 0);
    if (backgroundLine == null) return;
    _addLine(backgroundLine);
    _addExtraLines(background.extras, headExtras, backgroundTimestampMS, backgroundEndMS, 0, isBackground: true);
  }

  void _addExtraLines(List<_TtmlTrack>? inlineExtras, List<_TtmlLine>? headExtras, int timestampMS, int endMS, int? person, {required bool isBackground}) {
    if (inlineExtras != null) {
      for (final extra in inlineExtras) {
        final extraLine = _toLrcLine(extra, timestampMS, endMS, person);
        if (extraLine != null) _addLine(extraLine);
      }
    }
    if (headExtras != null) {
      for (final headExtra in headExtras) {
        final extra = isBackground ? headExtra.background : headExtra.main;
        if (extra == null) continue;
        final extraLine = _toLrcLine(extra, timestampMS, endMS, person);
        if (extraLine != null) _addLine(extraLine);
      }
    }
  }

  void _addLine(LrcLine line) {
    final timestamp = line.timestamp;
    if (timestamp < _latestTimestamp) _shouldSortLyrics = true;
    _latestTimestamp = timestamp;
    if (line.type == LrcTypes.enhanced) _type = LrcTypes.enhanced;
    final person = line.person;
    if (person != null && person > 0) _persons.add(person);
    _lyrics.add(line);
  }

  /// Null when [track] has no text.
  LrcLine? _toLrcLine(_TtmlTrack track, int timestampMS, int lineEndMS, int? person) {
    final words = track.words;
    final leadingText = _collapseWhitespace(track.textBeforeWords).trimLeft();
    if (words.isEmpty) return _toPlainLrcLine(leadingText.trimRight(), timestampMS, person);

    final trackEndMS = track.endMS >= 0 ? track.endMS : lineEndMS;
    final parts = _isWordSynced ? <LrcLinePart>[] : null;
    final readableBuffer = StringBuffer();
    void writeWord(String text, int startMS, int endMS) {
      readableBuffer.write(text);
      parts?.add(LrcLinePart(
        startTimestamp: Duration(milliseconds: startMS),
        endTimestamp: Duration(milliseconds: endMS),
        lyrics: text,
      ));
    }

    // -- a word is written once the next one is known, it may still get the space leading the next one
    var pendingText = '';
    var pendingStartMS = 0;
    var pendingEndMS = -1;
    var hasPending = false;
    for (final word in words) {
      var text = _collapseWhitespace(word.text);
      if (!hasPending) text = '$leadingText$text'.trimLeft();
      if (text.isEmpty) continue;
      if (text.codeUnitAt(0) == 0x20 /* space */) {
        if (!pendingText.endsWith(' ')) pendingText = '$pendingText ';
        text = text.substring(1);
        if (text.isEmpty) continue;
      }
      if (hasPending) {
        final pendingResolvedEndMS = pendingEndMS >= 0 ? pendingEndMS : word.startMS;
        writeWord(pendingText, pendingStartMS, pendingResolvedEndMS);
      }
      pendingText = text;
      pendingStartMS = word.startMS;
      pendingEndMS = word.endMS;
      hasPending = true;
    }
    if (!hasPending) return _toPlainLrcLine(leadingText.trimRight(), timestampMS, person);
    final lastFallbackEndMS = trackEndMS >= pendingStartMS ? trackEndMS : pendingStartMS;
    final lastEndMS = pendingEndMS >= 0 ? pendingEndMS : lastFallbackEndMS;
    writeWord(pendingText.trimRight(), pendingStartMS, lastEndMS);

    final readableText = readableBuffer.toString();
    return LrcLine(
      timestamp: Duration(milliseconds: timestampMS),
      originalIndex: _lyrics.length,
      lyrics: readableText,
      readableText: readableText,
      type: parts == null ? LrcTypes.simple : LrcTypes.enhanced,
      parts: parts,
      person: person,
      isRTL: LrcParser.isLrcLineRTL(readableText),
    );
  }

  LrcLine? _toPlainLrcLine(String text, int timestampMS, int? person) {
    if (text.isEmpty) return null;
    if (LrcParser._hasWordTimestamp(text)) {
      final lrcLine = _toLrcTextLine(text, timestampMS, person);
      if (lrcLine != null) return lrcLine;
    }
    return LrcLine(
      timestamp: Duration(milliseconds: timestampMS),
      originalIndex: _lyrics.length,
      lyrics: text,
      readableText: text,
      type: LrcTypes.simple,
      parts: null,
      person: person,
      isRTL: LrcParser.isLrcLineRTL(text),
    );
  }

  /// `v1:<00:18.653>They <00:18.900>say ...`, a `v1:` like prefix is the person when there is no agent.
  LrcLine? _toLrcTextLine(String text, int timestampMS, int? person) {
    final parts = LrcParser.extractTimeStampPartFromLine(text).toList();
    if (parts.isEmpty) return null;
    var linePerson = person;
    if (linePerson == null) {
      final prefixEnd = text.indexOf('<');
      final colonIndex = text.lastIndexOf(':', prefixEnd);
      if (colonIndex > 0) {
        final agentId = text.substring(0, colonIndex).trim();
        if (agentId.isNotEmpty) linePerson = _personOf(agentId);
      }
    }
    final readableText = parts.map((e) => e.lyrics).join();
    return LrcLine(
      timestamp: Duration(milliseconds: timestampMS),
      originalIndex: _lyrics.length,
      lyrics: text,
      readableText: readableText,
      type: LrcTypes.enhanced,
      parts: parts,
      person: linePerson,
      isRTL: LrcParser.isLrcLineRTL(readableText),
    );
  }

  LrcLine _emptyLine(int timestampMS) {
    return LrcLine(
      timestamp: Duration(milliseconds: timestampMS),
      originalIndex: _lyrics.length,
      lyrics: '',
      readableText: '',
      type: LrcTypes.simple,
      parts: null,
      person: null,
      isRTL: false,
    );
  }

  String _textOf(int start, int end, {bool isRaw = false}) {
    final text = _content.substring(start, end);
    return isRaw ? text : _HtmlEntities.decode(text);
  }

  bool _valueEquals(int start, int end, String expected) => end - start == expected.length && _content.startsWith(expected, start);

  _TtmlRole _roleOf(int start, int end) {
    if (_valueEquals(start, end, 'x-bg')) return _TtmlRole.background;
    if (_valueEquals(start, end, 'x-translation') || _valueEquals(start, end, 'x-roman')) return _TtmlRole.translationOrRoman;
    return _TtmlRole.none;
  }

  int _timeMS(int start, int end) => _parseTimeMS(_content, start, end, _frameRate, _tickRate);

  /// Clock time (`01:02:03.456`, `01:02:03:12` with frames, also `02:03.456` and `3.456`)
  /// or offset time (`3.456s`, `120ms`, `2m`, `1h`, `30f`, `9000t`), -1 when invalid.
  static int _parseTimeMS(String s, int start, int end, double frameRate, double tickRate) {
    var i = start;
    while (i < end && s.codeUnitAt(i) <= 0x20) {
      i++;
    }
    var clockSeconds = 0;
    var colonsCount = 0;
    var whole = 0;
    while (true) {
      final digitsStart = i;
      whole = 0;
      while (i < end) {
        final digit = s.codeUnitAt(i) - 0x30;
        if (digit < 0 || digit > 9) break;
        whole = whole * 10 + digit;
        i++;
      }
      if (i == digitsStart) return -1;
      if (i >= end || s.codeUnitAt(i) != 0x3A /* : */) break;
      i++;
      colonsCount++;
      if (colonsCount == 3) {
        final framesStart = i;
        var frames = 0;
        while (i < end) {
          final digit = s.codeUnitAt(i) - 0x30;
          if (digit < 0 || digit > 9) break;
          frames = frames * 10 + digit;
          i++;
        }
        if (i == framesStart) return -1;
        final framesMS = (frames * 1000 / frameRate).round();
        return (clockSeconds * 60 + whole) * 1000 + framesMS;
      }
      clockSeconds = clockSeconds * 60 + whole;
    }

    var fraction = 0;
    var fractionScale = 1;
    if (i < end) {
      final separator = s.codeUnitAt(i);
      if (separator == 0x2E /* . */ || separator == 0x2C /* , */) {
        i++;
        while (i < end) {
          final digit = s.codeUnitAt(i) - 0x30;
          if (digit < 0 || digit > 9) break;
          if (fractionScale < 1000000) {
            fraction = fraction * 10 + digit;
            fractionScale *= 10;
          }
          i++;
        }
      }
    }
    final fractionMS = (fraction * 1000 + (fractionScale >> 1)) ~/ fractionScale;
    if (colonsCount > 0) return (clockSeconds * 60 + whole) * 1000 + fractionMS;

    final unit = i < end ? s.codeUnitAt(i) : 0x73 /* s */;
    final isMilliseconds = unit == 0x6D /* m */ && i + 1 < end && s.codeUnitAt(i + 1) == 0x73 /* s */;
    final unitMS = switch (unit) {
      _ when isMilliseconds => 1.0,
      0x68 /* h */ => 3600000.0,
      0x6D /* m */ => 60000.0,
      0x66 /* f */ => 1000 / frameRate,
      0x74 /* t */ => 1000 / tickRate,
      _ => 0.0,
    };
    if (unitMS == 0) return whole * 1000 + fractionMS;
    final value = whole + fraction / fractionScale;
    return (value * unitMS).round();
  }

  /// Collapses every whitespace run into a single space, returning [s] itself when nothing needs collapsing.
  static String _collapseWhitespace(String s) {
    final length = s.length;
    var i = 0;
    for (; i < length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 /* space */) {
        final isRun = i + 1 < length && LrcParser._isEmptyCodeUnit(s.codeUnitAt(i + 1));
        if (isRun) break;
      } else if (LrcParser._isEmptyCodeUnit(c)) {
        break;
      }
    }
    if (i == length) return s;
    final buffer = StringBuffer(s.substring(0, i));
    var isPreviousSpace = false;
    for (; i < length; i++) {
      final c = s.codeUnitAt(i);
      if (LrcParser._isEmptyCodeUnit(c)) {
        if (isPreviousSpace) continue;
        isPreviousSpace = true;
        buffer.writeCharCode(0x20);
      } else {
        isPreviousSpace = false;
        buffer.writeCharCode(c);
      }
    }
    return buffer.toString();
  }

  static bool _isNameStartCodeUnit(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F /* _ */ || c >= 0x80;

  static int _nameEnd(String s, int start) {
    final length = s.length;
    var i = start;
    while (i < length) {
      final c = s.codeUnitAt(i);
      if (c == 0x3E /* > */ || c == 0x2F /* / */ || c <= 0x20) break;
      i++;
    }
    return i;
  }

  static int _localNameStart(String s, int start, int end) {
    for (var i = end - 1; i > start; i--) {
      if (s.codeUnitAt(i) == 0x3A /* : */) return i + 1;
    }
    return start;
  }

  static _TtmlElement _elementOf(String s, int start, int end) {
    final localStart = _localNameStart(s, start, end);
    final localLength = end - localStart;
    const elements = _TtmlElement.values;
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      final localName = element.localName;
      if (localName.length == localLength && s.startsWith(localName, localStart)) return element;
    }
    return _TtmlElement.other;
  }

  static _TtmlAttribute _attributeOf(String s, int start, int end) {
    final localStart = _localNameStart(s, start, end);
    final localLength = end - localStart;
    const attributes = _TtmlAttribute.values;
    for (var i = 0; i < attributes.length; i++) {
      final attribute = attributes[i];
      final localName = attribute.localName;
      if (localName.length == localLength && s.startsWith(localName, localStart)) return attribute;
    }
    return _TtmlAttribute.other;
  }

  static bool _hasBeginAttribute(String s, int start, int end) {
    var i = s.indexOf('begin', start);
    while (i >= 0 && i < end) {
      final previous = s.codeUnitAt(i - 1);
      if (previous <= 0x20 || previous == 0x3A /* : */) return true;
      i = s.indexOf('begin', i + 5);
    }
    return false;
  }
}

class _TtmlLine {
  final int beginMS;
  final int endMS;
  final int? person;
  final String? key;
  final bool isBackground;
  final int divNumber;
  final main = _TtmlTrack();
  _TtmlTrack? background;

  _TtmlLine({
    required this.beginMS,
    required this.endMS,
    required this.person,
    required this.key,
    required this.isBackground,
    required this.divNumber,
  });
}

class _TtmlTrack {
  final words = <_TtmlWord>[];
  var textBeforeWords = '';
  var beginMS = -1;
  var endMS = -1;
  List<_TtmlTrack>? extras;

  int get firstWordStartMS => words.isEmpty ? -1 : words[0].startMS;

  void appendTextBeforeWords(String value) => textBeforeWords = textBeforeWords.isEmpty ? value : '$textBeforeWords$value';

  void extendTiming(int beginMS, int endMS) {
    if (beginMS >= 0 && (this.beginMS < 0 || beginMS < this.beginMS)) this.beginMS = beginMS;
    if (endMS > this.endMS) this.endMS = endMS;
  }
}

class _TtmlWord {
  final int startMS;
  final int endMS;
  var text = '';

  _TtmlWord(this.startMS, this.endMS);

  void append(String value) => text = text.isEmpty ? value : '$text$value';
}

enum _TtmlElement {
  tt('tt'),
  body('body'),
  div('div'),
  p('p'),
  span('span'),
  br('br'),
  agent('agent'),
  title('title'),
  meta('meta'),
  songwriter('songwriter'),
  text('text'),
  other(''),
  ;

  const _TtmlElement(this.localName);
  final String localName;
}

enum _TtmlAttribute {
  begin('begin'),
  end('end'),
  dur('dur'),
  agent('agent'),
  key('key'),
  forKey('for'),
  id('id'),
  value('value'),
  role('role'),
  ruby('ruby'),
  lang('lang'),
  timing('timing'),
  frameRate('frameRate'),
  tickRate('tickRate'),
  other(''),
  ;

  const _TtmlAttribute(this.localName);
  final String localName;
}

enum _TtmlRole {
  none,
  background,
  translationOrRoman,
  ignored,
  ;
}

typedef _TtmlFrame = ({_TtmlTrack? track, _TtmlWord? word});
