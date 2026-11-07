// by claude
import 'package:test/test.dart';

import 'package:lrc/lrc.dart';

void main() {
  List<(String, int?)> untimedOf(Lrc lrc) => lrc.untimedLines.map((e) => (e.text, e.beforeIndex)).toList();

  List<String> rowsOf(Lrc lrc) => lrc.forUiDisplay(0, withUntimedLines: true).uiLyricsLines.map((e) => e.isUntimed ? '# ${e.readableText}' : e.readableText).toList();

  group('parsing', () {
    test('lines without a timestamp belong to the line below them, the ones after the last line to none', () {
      const content = '[ar:Someone]\n[Chorus]\n[00:01.00]a\n[00:02.00]b\n\n[Verse]\n[00:03.00]c\n\nend note';
      final lrc = Lrc.parse(content);
      expect(lrc.lyrics.map((e) => e.readableText), ['a', 'b', 'c']);
      expect(untimedOf(lrc), [('[Chorus]', 0), ('', 2), ('[Verse]', 2), ('', null), ('end note', null)]);
      expect(lrc.tags, {'ar': 'Someone'});
    });

    test('tags, unknown tags and background lines are not text, headers with a colon are', () {
      const content = '[id:abc1]\n[tool:x]\n[ar:first]\n[ar:second]\n[Verse 1: Name]\n[00:01.00]<00:01.00>a<00:02.00>\n[bg:<00:01.50>ooh<00:01.80>] \n[00:03.00]<00:03.00>b<00:04.00>';
      final lrc = Lrc.parse(content);
      expect(lrc.tags, {'id': 'abc1', 'tool': 'x', 'ar': 'first'});
      expect(untimedOf(lrc), [('[Verse 1: Name]', 0)]);
      expect(lrc.lyrics.where((e) => e.isBGLyrics).map((e) => e.readableText), ['ooh']);
    });

    test('a byte order mark does not hide the first tag', () {
      final lrc = Lrc.parse('﻿[ar:x]\n[00:01.00]a');
      expect(lrc.artist, 'x');
      expect(lrc.untimedLines, isEmpty);
    });

    test('tag getters read the tags', () {
      final lrc = Lrc.parse('[ti:t]\n[offset:-250]\n[length: 03:21]\n[00:01.00]a');
      expect(lrc.title, 't');
      expect(lrc.offset, -250);
      expect(lrc.length, '03:21');
      expect(Lrc.parse('[00:01.00]a').offset, null);
    });

    test('a ttml div is a verse, an empty line goes above its first line', () {
      const content = '<tt><body>'
          '<div><p begin="1s" end="2s">a</p><p begin="2s" end="3s">b</p></div>'
          '<div><p begin="4s" end="5s">c</p></div>'
          '</body></tt>';
      final lrc = TtmlParser.parse(content);
      expect(untimedOf(lrc), [('', 2)]);
      expect(rowsOf(lrc), ['a', 'b', '# ', 'c']);
    });

    test('a single ttml div has no empty lines', () {
      const content = '<tt><body><div><p begin="1s" end="2s">a</p><p begin="2s" end="3s">b</p></div></body></tt>';
      expect(TtmlParser.parse(content).untimedLines, isEmpty);
    });
  });

  group('format', () {
    test('writes everything back where it was', () {
      const content = '[ar:A]\n[id:x1]\n[Chorus]\n[00:01.00]a\n\n[00:02.00]b\nend\n';
      expect(Lrc.parse(content).format(), content);
    });

    test('a line with several timestamps keeps its header once', () {
      const content = '[Chorus]\n[00:01.00][00:10.00]x\n[00:05.00]y';
      final formatted = Lrc.parse(content).format();
      expect(formatted, '[Chorus]\n[00:01.00]x\n[00:05.00]y\n[00:10.00]x\n');
      expect(rowsOf(Lrc.parse(formatted)), ['# [Chorus]', 'x', 'y', 'x']);
    });

    test('a translation block shows the same after being written back', () {
      final lrc = Lrc.parse(_kTranslationBlocks);
      final formatted = Lrc.parse(lrc.format());
      expect(rowsOf(formatted), rowsOf(lrc));
      expect(formatted.tags, lrc.tags);
    });
  });

  group('forUiDisplay', () {
    test('no rows unless asked for', () {
      const content = '[Chorus]\n[00:01.00]a\n\n[00:02.00]b';
      final lines = Lrc.parse(content).forUiDisplay(0).uiLyricsLines;
      expect(lines.map((e) => e.readableText), ['a', 'b']);
    });

    test('rows sit above their line with its timestamp and are never highlighted', () {
      const content = '[00:01.00]a\n\n\n[Verse]\n[00:02.00]b\n\nthe end\n\n';
      final ui = Lrc.parse(content).forUiDisplay(0, withUntimedLines: true);
      final lines = ui.uiLyricsLines;
      expect(lines.map((e) => e.isUntimed ? '# ${e.readableText}' : e.readableText), ['a', '# ', '# [Verse]', 'b', '# ', '# the end']);
      expect(lines[2].timestamp, const Duration(seconds: 2));
      expect(lines[5].timestamp, const Duration(seconds: 2));
      expect(ui.highlightTimestampsMap.values.expand((e) => e), [0, 3]);
      expect(ui.lineResolver.lineIndices, [0, 3]);
      expect(ui.lineResolver.indexAt(2000), 3);
    });

    test('no empty row at the top', () {
      const content = '\n[ar:x]\n\n[00:01.00]a\n[00:02.00]b\n[00:03.00]c';
      expect(rowsOf(Lrc.parse(content)), ['a', 'b', 'c']);
    });

    test('a translation written as its own block keeps the rows of the first block only', () {
      expect(rowsOf(Lrc.parse(_kTranslationBlocks)), [
        '# --- ENGLISH ---', '# [Chorus]', 'First line', 'Première ligne', 'Another line', 'Une autre ligne', //
        '# ', 'More lines', 'Plus de lignes', 'Even more lines', 'Encore plus de lignes',
        '# ', '# [Verse]', 'More singing', 'Plus de chant',
      ]);
    });

    test('an empty line above every line is formatting, not verses', () {
      const content = '[00:01.00]a\n\n[00:02.00]b\n\n[00:03.00]c\n\n[00:04.00]d';
      expect(rowsOf(Lrc.parse(content)), ['a', 'b', 'c', 'd']);
      const crcrlf = '[00:01.00]a\r\r\n[00:02.00]b\r\r\n[Verse]\r\r\n[00:03.00]c\r\r\n';
      expect(rowsOf(Lrc.parse(crcrlf)), ['a', 'b', '# [Verse]', 'c']);
    });

    test('verses of two lines keep their empty lines', () {
      const content = '[00:01.00]a\n[00:02.00]b\n\n[00:03.00]c\n[00:04.00]d\n\n[00:05.00]e\n[00:06.00]f';
      expect(rowsOf(Lrc.parse(content)), ['a', 'b', '# ', 'c', 'd', '# ', 'e', 'f']);
    });

    test('an empty line above every translated line is formatting too', () {
      const content = '[00:01.00]a\n[00:01.00]A\n\n[00:02.00]b\n[00:02.00]B\n\n[00:03.00]c\n[00:03.00]C';
      expect(rowsOf(Lrc.parse(content)), ['a', 'A', 'b', 'B', 'c', 'C']);
    });
  });

  group('setLrcTag', () {
    test('replaces the tag where it is and keeps the rest as written', () {
      const content = '[ar:x]\r\n[offset: 100]\r\n[Chorus]\r\n[00:01.00][00:05.00]a\r\n\r\n[00:02.00]b';
      expect(LyricsParser.setLrcTag(content, Lrc.kOffsetTag, '-50'), '[ar:x]\r\n[offset:-50]\r\n[Chorus]\r\n[00:01.00][00:05.00]a\r\n\r\n[00:02.00]b');
    });

    test('adds a missing tag at the top, after the byte order mark', () {
      expect(LyricsParser.setLrcTag('[00:01.00]a\n', Lrc.kOffsetTag, '20'), '[offset:20]\n[00:01.00]a\n');
      expect(LyricsParser.setLrcTag('﻿[00:01.00]a\r\n', Lrc.kOffsetTag, '20'), '﻿[offset:20]\r\n[00:01.00]a\r\n');
    });

    test('null removes the tag line', () {
      expect(LyricsParser.setLrcTag('[offset:5]\n[00:01.00]a', Lrc.kOffsetTag, null), '[00:01.00]a');
      expect(LyricsParser.setLrcTag('[00:01.00]a', Lrc.kOffsetTag, null), '[00:01.00]a');
    });

    test('a tag with a longer name is another tag', () {
      expect(LyricsParser.setLrcTag('[offsets:1]\n[00:01.00]a', Lrc.kOffsetTag, '2'), '[offset:2]\n[offsets:1]\n[00:01.00]a');
    });

    test('other formats have no tag lines', () {
      const ttml = '<tt><body><div><p begin="1s" end="2s">a</p></div></body></tt>';
      const srt = '1\n00:00:01,000 --> 00:00:02,000\na\n';
      expect(LyricsParser.setLrcTag(ttml, Lrc.kOffsetTag, '5'), null);
      expect(LyricsParser.setLrcTag(srt, Lrc.kOffsetTag, '5'), null);
    });
  });
}

const _kTranslationBlocks = '''--- ENGLISH ---
[Chorus]
[00:01.23] First line
[00:02.31] Another line

[00:03.25] More lines
[00:05.35] Even more lines

[Verse]
[00:07.23] More singing

--- FRENCH ---
[Refrain]
[00:01.23] Première ligne
[00:02.31] Une autre ligne

[00:03.25] Plus de lignes
[00:05.35] Encore plus de lignes

[Couplet]
[00:07.23] Plus de chant
''';
