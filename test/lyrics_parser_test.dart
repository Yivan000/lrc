// by claude
import 'dart:io';

import 'package:test/test.dart';

import 'package:lrc/lrc.dart';

void main() {
  final fixtures = {
    for (final file in Directory('test/files').listSync(recursive: true).whereType<File>())
      if (!file.path.endsWith('.m4a')) file.path: file.readLrcStringSync(),
  };
  const edgeCases = {
    'empty': '',
    'whitespace': ' \n\t\n',
    'plain text': 'first line\nsecond line, with a comma\nthird line',
    'plain text with sections': '[Chorus]\nla la la\n[Verse 2]\nJohn 3:16',
    'plain text with html': '<i>la la</i><br>la',
    'tags only': '[ar:Someone]\n[ti:Something]',
    'lrc after junk lines': 'Lyrics from somewhere\n\n[00:01.00]first\n[00:02.50]second',
    'lrc with a qrc looking word': '[00:01.00]line [1,2]\n[00:02.00]next',
    'qrc after tags': '[ti:x]\n[ar:y]\n[1000,1000]a(1000,500)b(1500,500)',
    'wlrc after offset': '[offset:500]\n[00:01.000]-[00:01.500]a\n[00:01.600]-[00:02.000]b',
    'wlrc after junk lines': 'Lyrics from somewhere\n[00:01.000]-[00:01.500]a\n[00:01.600]-[00:02.000]b',
    'lrc with a wlrc looking word': '[00:01.00]line [00:01.500]-[00:02.000]\n[00:02.00]next',
    'plain text with a digit bracket': 'Chorus [2x]\nla la la',
    'lrc after junk lines with a timing like word': 'the beginning\n[00:01.00]first\n[00:02.50]second',
    'qrc xml': '<?xml version="1.0"?>\n<Lyric_1 LyricContent="[ti:x]\n[1000,1000]a(1000,1000)\n"/>',
    'json without endtime': '[{"text": [{"text": "a", "timestamp": 1}]}]',
    'json object': '{"type": "Syllable", "content": [{"timestamp": 1000, "text": [{"text": "a", "part": false, "timestamp": 1000, "endtime": 2000}]}]}',
    'srt after junk line': 'junk\n1\n00:00:01,000 --> 00:00:02,000\nhello\n',
    'sbv': '0:00:01.000,0:00:02.000\nhello\n\n0:00:03.000,0:00:04.000\nworld\n',
    'ssa without script info first':
        '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,hello',
    'ttml p without begin first': '<tt><body><div><p end="2.0s" begin="1.0s">hello</p></div></body></tt>',
    'ttml p without end': '<tt><body><div><p xml:id="p1" begin="1.5s">hello</p></div></body></tt>',
  };
  final contents = {...fixtures, ...edgeCases};

  test('parse matches trying every parser in order', () {
    for (final MapEntry(key: name, value: content) in contents.entries) {
      final expected = _parseByTryingAll(content);
      final lrc = LyricsParser.parse(content);
      expect(lrc?.type, expected?.type, reason: name);
      expect(lrc?.format(), expected?.format(), reason: name);
    }
  });

  test('isValid matches checking every parser', () {
    for (final MapEntry(key: name, value: content) in contents.entries) {
      expect(LyricsParser.isValid(content), _isValidByCheckingAll(content), reason: name);
    }
  });

  test('every fixture parses', () {
    for (final MapEntry(key: name, value: content) in fixtures.entries) {
      expect(LyricsParser.parse(content)?.lyrics, isNotEmpty, reason: name);
    }
  });

  test('plain text is rejected and odd files still parse', () {
    expect(LyricsParser.parse(edgeCases['plain text']!), null);
    expect(LyricsParser.parse(edgeCases['plain text with sections']!), null);
    expect(LyricsParser.parse(edgeCases['plain text with a digit bracket']!), null);
    expect(LyricsParser.parse(edgeCases['lrc after junk lines']!)!.lyrics.map((e) => e.readableText), ['first', 'second']);
    expect(LyricsParser.parse(edgeCases['lrc after junk lines with a timing like word']!)!.lyrics.map((e) => e.readableText), ['first', 'second']);
    expect(LyricsParser.parse(edgeCases['qrc after tags']!)!.lyrics.single.readableText, 'ab');
    expect(LyricsParser.parse(edgeCases['wlrc after offset']!)!.lyrics.single.readableText, 'a b');
    expect(LyricsParser.parse(edgeCases['wlrc after junk lines']!)!.lyrics.single.readableText, 'a b');
    expect(LyricsParser.parse(edgeCases['srt after junk line']!)!.lyrics.single.readableText, 'hello');
    expect(LyricsParser.parse(edgeCases['ttml p without end']!)!.lyrics.single.readableText, 'hello');
  });
}

Lrc? _parseByTryingAll(String content) {
  final wlrc = WlrcParser.parse(content);
  if (wlrc != null) return wlrc;
  try {
    final lrc = LrcParser.parse(content);
    if (lrc.lyrics.isNotEmpty) return lrc;
  } catch (_) {}
  try {
    final lrc = TtmlParser.parse(content);
    if (lrc.lyrics.isNotEmpty) return lrc;
  } catch (_) {}
  try {
    final lrc = SubtitleParser.parse(content);
    if (lrc.lyrics.isNotEmpty) return lrc;
  } catch (_) {}
  final paxsenixLrc = PaxsenixJsonParser.parse(content);
  if (paxsenixLrc != null) return paxsenixLrc;
  return QrcParser.parse(content);
}

bool _isValidByCheckingAll(String content) {
  return WlrcParser.isValid(content) ||
      LrcParser.isValid(content) ||
      TtmlParser.isValid(content) ||
      SubtitleParser.isValid(content) ||
      PaxsenixJsonParser.isValid(content) ||
      QrcParser.isValid(content);
}
