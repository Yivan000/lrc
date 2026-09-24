part of lrc;

class LrcLinePart {
  final Duration startTimestamp;
  final Duration endTimestamp;
  final String lyrics;

  const LrcLinePart({
    required this.startTimestamp,
    required this.endTimestamp,
    required this.lyrics,
  });

  @override
  String toString() {
    return '''
      startTimestamp: '$startTimestamp'
      endTimestamp: '$endTimestamp'
      Lyrics: '$lyrics'
    ''';
  }
}
