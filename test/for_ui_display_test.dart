// by claude
import 'dart:io';

import 'package:test/test.dart';

import 'package:lrc/lrc.dart';

import 'fixtures.dart';

void main() {
  group('empty lines', () {
    test('an empty line is keyed by the timestamp it is shown at', () {
      const content = '[00:01.00]<00:01.00>a <00:02.00>b<00:03.00>\n[00:10.00]c';
      final ui = Lrc.parse(content).forUiDisplay(0);
      expect(ui.uiLyricsLines.map((e) => e.readableText), ['a b', '', 'c']);
      expect(ui.uiLyricsLines[1].timestamp, const Duration(seconds: 3));
      expect(ui.highlightTimestampsMap[const Duration(seconds: 3)], [1]);
    });

    test('a word line followed by its translation gets the empty line after the translation', () {
      const content = '[00:01.00]<00:01.00>a <00:02.00>b<00:03.00>\n[00:01.00]translated\n[00:10.00]c';
      final ui = Lrc.parse(content).forUiDisplay(0);
      expect(ui.uiLyricsLines.map((e) => e.readableText), ['a b', 'translated', '', 'c']);
      expect(ui.highlightTimestampsMap[const Duration(seconds: 1)], [0, 1]);
      expect(ui.highlightTimestampsMap[const Duration(seconds: 3)], [2]);
    });

    test('duet lines sharing a timestamp get the empty line once the last singer ends', () {
      const content = '[00:01.00]v1:<00:01.00>long <00:06.00>line<00:07.00>\n[00:01.00]v2:<00:01.00>short<00:02.00>\n[00:10.00]c';
      final ui = Lrc.parse(content).forUiDisplay(0);
      expect(ui.uiLyricsLines.map((e) => e.readableText), ['long line', 'short', '', 'c']);
      expect(ui.uiLyricsLines[2].timestamp, const Duration(seconds: 7));
    });

    test('background vocals ending before their main line do not hide it, the empty line waits for the main line end', () {
      const content = '[00:01.00]<00:01.00>a <00:02.00>b<00:03.00>\n[bg:<00:01.20>ooh<00:01.50>]\n[00:10.00]c';
      final ui = Lrc.parse(content).forUiDisplay(0);
      expect(ui.uiLyricsLines.map((e) => e.readableText), ['a b', 'ooh', '', 'c']);
      expect(ui.uiLyricsLines[2].timestamp, const Duration(seconds: 3));
      expect(ui.lineResolver.indexAt(2000), 0);
      expect(ui.lineResolver.indexAt(3000), 2);
    });

    test('no empty line when the next line comes within a second', () {
      const content = '[00:01.00]<00:01.00>a <00:02.00>b<00:03.00>\n[00:03.80]c';
      final ui = Lrc.parse(content).forUiDisplay(0);
      expect(ui.uiLyricsLines.map((e) => e.readableText), ['a b', 'c']);
    });

    test('a plain line starting where the words before it end gets no empty line', () {
      final content = File('test/files/timed_lrc_10.lrc').readLrcStringSync();
      final ui = Lrc.parse(content).forUiDisplay(0);
      expect(ui.highlightTimestampsMap[const Duration(milliseconds: 11680)], [2]);
      expect(ui.uiLyricsLines[2].readableText, 'Yeah!');
      expect(ui.uiLyricsLines[3].timestamp, const Duration(milliseconds: 13640));
    });

    test('a blank line right after a word line is not doubled', () {
      const withEndTimestamp = '[00:01.00]<00:01.00>a <00:02.00>b<00:03.00>\n[00:03.00]\n[00:10.00]c';
      const withoutEndTimestamp = '[00:01.00]<00:01.00>a <00:02.00>b\n[00:03.00]\n[00:10.00]c';
      for (final content in [withEndTimestamp, withoutEndTimestamp]) {
        final ui = Lrc.parse(content).forUiDisplay(0);
        expect(ui.uiLyricsLines.map((e) => e.readableText), ['a b', '', 'c'], reason: content);
        expect(ui.highlightTimestampsMap[const Duration(seconds: 3)], [1], reason: content);
      }
    });

    test('words running past the start of a plain line do not hide it', () {
      const content = '<tt><body><div>'
          '<p begin="00:05.000" end="00:10.400"><span begin="00:05.000" end="00:07.000">I</span> <span begin="00:07.000" end="00:10.400">know</span></p>'
          '<p begin="00:10.000" end="00:11.500">Yeah!</p>'
          '<p begin="00:20.000" end="00:22.000"><span begin="00:20.000" end="00:21.000">next</span> <span begin="00:21.000" end="00:22.000">line</span></p>'
          '</div></body></tt>';
      final ui = TtmlParser.parse(content).forUiDisplay(0);
      expect(ui.uiLyricsLines, hasLength(3));
      expect(ui.uiLyricsLines[1].readableText, 'Yeah!');
      expect(ui.lineResolver.indexAt(15000), 1);
    });

    test('an extended line gets no empty line sharing its timestamp', () {
      const content = '[00:01.00]M: hello\n[00:05.00]F: world';
      final ui = Lrc.parse(content).forUiDisplay(0);
      expect(ui.uiLyricsLines, hasLength(2));
      expect(ui.highlightTimestampsMap[const Duration(seconds: 1)], [0]);
    });
  });

  test('romanized copies sit right after their line and shift the later indices', () {
    const content = '[00:01.00]<00:01.00>a <00:02.00>b<00:03.00>\n[00:10.00]c';
    final ui = Lrc.parse(content).forUiDisplay(0, romanizer: (index, text) => text.toUpperCase());
    expect(ui.uiLyricsLines.map((e) => e.readableText), ['a b', 'A B', '', 'c', 'C']);
    expect(ui.highlightTimestampsMap.values, [
      [0, 1],
      [2],
      [3, 4],
    ]);
  });

  test('translations share a key, background vocals get their own', () {
    const content = '[00:01.00]<00:01.00>a <00:02.00>b<00:03.00>\n[bg:<00:02.50>ooh<00:03.50>]\n[00:01.00]translated\n[00:10.00]c';
    final ui = Lrc.parse(content).forUiDisplay(0);
    expect(ui.uiLyricsLines.map((e) => e.readableText), ['a b', 'translated', 'ooh', '', 'c']);
    expect(ui.highlightTimestampsMap[const Duration(seconds: 1)], [0, 1]);
    expect(ui.highlightTimestampsMap[const Duration(milliseconds: 2500)], [2]);
  });

  test('offset, visual delay and stretch apply to lines and words alike', () {
    const content = '[offset:500]\n[00:10.00]<00:10.00>la <00:11.00>la<00:12.00>\n[00:20.00]next';
    final ui = Lrc.parse(content).forUiDisplay(0.8, extraOffsetDuration: const Duration(seconds: 1));
    final first = ui.uiLyricsLines.first;
    expect(first.timestamp, const Duration(milliseconds: 8400));
    expect(first.parts!.first.startTimestamp, const Duration(milliseconds: 8400));
    expect(first.parts!.first.endTimestamp, const Duration(milliseconds: 9200));
    expect(first.parts!.last.endTimestamp, const Duration(milliseconds: 10000));
    expect(ui.uiLyricsLines.last.timestamp, const Duration(milliseconds: 16400));
  });

  test('words shorter than 250ms merge into the next one, the last word never merges', () {
    const content = '[00:01.00]<00:01.00>a<00:01.10>b <00:02.00>c<00:02.10>';
    final parts = Lrc.parse(content).forUiDisplay(0).uiLyricsLines.first.parts!;
    expect(parts.map((e) => e.lyrics), ['ab ', 'c']);
    expect(parts.first.startTimestamp, const Duration(seconds: 1));
    expect(parts.first.endTimestamp, const Duration(seconds: 2));
    expect(parts.last.endTimestamp, const Duration(milliseconds: 2100));
  });

  test('every fixture keeps the index map and the lines in time order', () {
    for (final (:name, :lrc) in parseAllFixtures()) {
      final shifted = lrc.withTags({...lrc.tags, Lrc.kOffsetTag: '500'});
      final ui = shifted.forUiDisplay(
        0.8,
        extraOffsetDuration: const Duration(milliseconds: 700),
        romanizer: (index, text) => text.toUpperCase(),
        withUntimedLines: true,
      );
      final lines = ui.uiLyricsLines;
      final map = ui.highlightTimestampsMap;

      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].timestamp >= lines[i - 1].timestamp, true, reason: '$name line $i goes back in time');
      }

      final seenCounts = List.filled(lines.length, 0);
      Duration? previousKey;
      for (final MapEntry(key: timestamp, value: indices) in map.entries) {
        if (previousKey != null) expect(timestamp > previousKey, true, reason: '$name key $timestamp after $previousKey');
        previousKey = timestamp;
        for (final index in indices) {
          seenCounts[index]++;
          expect(lines[index].timestamp, timestamp, reason: '$name index $index');
        }
      }
      for (var i = 0; i < lines.length; i++) {
        final expectedCount = lines[i].isUntimed ? 0 : 1;
        expect(seenCounts[i], expectedCount, reason: '$name line $i missing or repeated in the map');
      }

      final resolver = ui.lineResolver;
      final expectedLineIndices = [
        for (final indices in map.values)
          if (indices.any((index) => !lines[index].isBGLyrics)) indices.first,
      ];
      expect(resolver.lineIndices, expectedLineIndices, reason: name);
      for (var slot = 0; slot < resolver.length; slot++) {
        final startMicros = lines[resolver.lineIndices[slot]].timestamp.inMicroseconds;
        final startMS = resolver.startsMS[slot];
        expect(startMS * 1000 >= startMicros && (startMS - 1) * 1000 < startMicros, true, reason: '$name slot $slot');
      }
    }
  });
}
