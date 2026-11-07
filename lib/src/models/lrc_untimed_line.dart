part of lrc;

/// A line without a timestamp, like a section header (`[Chorus]`), a note, or an empty line between verses.
class LrcUntimedLine {
  /// Empty for an empty line.
  final String text;

  /// The [LrcLine.originalIndex] of the line it was written above, null when it came after the last line.
  final int? beforeIndex;

  const LrcUntimedLine({
    required this.text,
    required this.beforeIndex,
  });

  @override
  String toString() => 'LrcUntimedLine($beforeIndex, "$text")';
}
