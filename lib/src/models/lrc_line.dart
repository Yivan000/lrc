part of lrc;

///A line of lyrics, with its defined duration and raw lyrics
class LrcLine {
  ///timestamp for the lyrics wherein it'll be displayed
  final Duration timestamp;

  final num originalIndex;

  ///the raw lyrics for the line
  final String lyrics;

  final String readableText;

  final List<LrcLinePart>? parts;

  ///the type of lrc for this line
  final LrcTypes type;

  final int? person;

  final bool isRTL;

  /// a row for an [LrcUntimedLine], only in `forUiDisplay` with `withUntimedLines`.
  final bool isUntimed;

  bool get isBGLyrics => person == 0;

  const LrcLine({
    required this.timestamp,
    required this.originalIndex,
    required this.lyrics,
    required this.readableText,
    required this.type,
    required this.parts,
    required this.person,
    required this.isRTL,
    this.isUntimed = false,
  });

  LrcLine withTimeStamp({
    required Duration newTimestamp,
    List<LrcLinePart>? parts,
  }) {
    return LrcLine(
      timestamp: newTimestamp,
      originalIndex: originalIndex,
      lyrics: lyrics,
      readableText: readableText,
      type: type,
      person: person,
      parts: parts ?? this.parts,
      isRTL: isRTL,
      isUntimed: isUntimed,
    );
  }

  /// the line as written in an lrc file, word timestamps are written from [parts].
  String format() {
    final person = this.person;
    final text = _formatText();
    if (person == 0) return '[bg:$text]';
    final hasPersonPrefix = person != null && type != LrcTypes.extended;
    final personPrefix = hasPersonPrefix ? 'v$person: ' : '';
    final timestampText = formatTimestamp(timestamp);
    return '[$timestampText]$personPrefix$text';
  }

  String _formatText() {
    final parts = this.parts;
    if (type != LrcTypes.enhanced || parts == null || parts.isEmpty) return lyrics;
    final buffer = StringBuffer();
    for (final part in parts) {
      buffer.write('<${formatTimestamp(part.startTimestamp)}>');
      buffer.write(part.lyrics);
    }
    buffer.write('<${formatTimestamp(parts.last.endTimestamp)}>');
    return buffer.toString();
  }

  /// `mm:ss.xx`, minutes keep going past 59 since lrc has no hours.
  static String formatTimestamp(Duration timestamp) {
    if (timestamp.isNegative) timestamp = Duration.zero;
    final minutes = timestamp.inMinutes;
    final seconds = timestamp.inSeconds % 60;
    final centiseconds = timestamp.inMilliseconds % 1000 ~/ 10;
    return '${_pad2(minutes)}:${_pad2(seconds)}.${_pad2(centiseconds)}';
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  @override
  String toString() {
    return '''
      Timestamp: '$timestamp'
      OriginalIndex: '$originalIndex'
      Lyrics: '$lyrics'
      Parts: '$parts'
      Person: '$person'
    ''';
  }
}
