// by claude
import 'dart:io';

import 'package:test/test.dart';

import 'package:lrc/lrc.dart';

void main() {
  group('wlrc_lrc.wlrc', () {
    final content = File('test/files/wlrc_lrc.wlrc').readAsStringSync();

    test('lines snapshot', () {
      final lrc = WlrcParser.parse(content)!;
      expect(lrc.type, LrcTypes.enhanced);
      expect(lrc.offset, null);
      final snapshot = lrc.lyrics.map((e) => (e.timestamp.inMilliseconds, e.parts!.last.endTimestamp.inMilliseconds, e.parts!.length, e.readableText)).toList();
      expect(snapshot, [
        (1500, 3100, 3, 'First line, here'),
        (4000, 5000, 2, 'Second one'),
        (6250, 7900, 2, 'Third line?'),
      ]);
      for (final line in lrc.lyrics) {
        expect(line.type, LrcTypes.enhanced, reason: line.readableText);
        expect(line.person, null, reason: line.readableText);
      }
    });

    test('first line words', () {
      final first = WlrcParser.parse(content)!.lyrics.first;
      expect(first.lyrics, '<00:01.500>First <00:02.000>line, <00:02.400>here<00:03.100>');
      final parts = first.parts!.map((e) => (e.startTimestamp.inMilliseconds, e.endTimestamp.inMilliseconds, e.lyrics)).toList();
      expect(parts, [
        (1500, 1900, 'First '),
        (2000, 2350, 'line, '),
        (2400, 3100, 'here'),
      ]);
    });

    test('LyricsParser picks wlrc instead of reading words as lrc lines', () {
      final lrc = LyricsParser.parse(content)!;
      expect(lrc.lyrics.map((e) => e.readableText), ['First line, here', 'Second one', 'Third line?']);
    });

    test('formatted lrc parses back to the same lines', () {
      final lrc = WlrcParser.parse(content)!;
      final reparsed = Lrc.parse(lrc.format());
      expect(reparsed.lyrics.map((e) => e.readableText), lrc.lyrics.map((e) => e.readableText));
      expect(reparsed.lyrics.map((e) => e.parts!.length), lrc.lyrics.map((e) => e.parts!.length));
    });
  });

  test('[newline] ends a line, crlf and spaces around the timings are allowed', () {
    const content = '  [00:01.000] - [00:01.500] a \r\n[00:01.600]-[00:02.000]b\r\n[NewLine]\r\n[00:03.000]-[00:03.500]c\r\n\r\n\r\n';
    final lines = WlrcParser.parse(content)!.lyrics.map((e) => (e.timestamp.inMilliseconds, e.readableText)).toList();
    expect(lines, [
      (1000, 'a b'),
      (3000, 'c'),
    ]);
  });

  test('offsets add up and apply to the words after them', () {
    const content = '[offset:1000]\n[00:01.000]-[00:01.500]a\n[offset:+500]\n[00:02.000]-[00:02.500]b\n\n[offset:-1500]\n[00:05.000]-[00:05.500]c';
    final lines = WlrcParser.parse(content)!.lyrics;
    final parts = lines.map((line) => line.parts!.map((e) => (e.startTimestamp.inMilliseconds, e.endTimestamp.inMilliseconds)).toList()).toList();
    expect(parts, [
      [(2000, 2500), (3500, 4000)],
      [(5000, 5500)],
    ]);
  });

  test('empty words, untimed lines and stray separators are skipped', () {
    const content = '\n\n[00:01.000]-[00:01.500]\n[00:01.600]-[00:02.000]a\nnot timed\n[00:00.500]plain lrc\n\n\n[newline]\n[00:03.000]-[00:03.500]b';
    final lines = WlrcParser.parse(content)!.lyrics.map((e) => e.readableText).toList();
    expect(lines, ['a', 'b']);
  });

  test('out of order lines are sorted', () {
    const content = '[00:05.000]-[00:05.500]late\n\n[00:01.000]-[00:01.500]early';
    final lines = WlrcParser.parse(content)!.lyrics.map((e) => e.readableText).toList();
    expect(lines, ['early', 'late']);
  });

  test('content without word timings', () {
    expect(WlrcParser.isValid('[00:01.00]line\n[00:02.00]next'), false);
    expect(WlrcParser.parse('[00:01.00]line\n[00:02.00]next'), null);
    expect(WlrcParser.isValid('[00:01.000]-[00:02.000]word'), true);
  });
}
