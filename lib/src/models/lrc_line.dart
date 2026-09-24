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
    );
  }

  ///get the string for a formatted line
  String get formattedLine {
    ///function to add leading zeros
    String f(int x) => x.toString().padLeft(2, '0');

    // LRC format doesn't accept hours.
    final minutes = timestamp.inMinutes % 60,
        seconds = timestamp.inSeconds % 60,
        hundreds = timestamp.inMilliseconds % 1000 ~/ 10;

    return '[${f(minutes)}:${f(seconds)}.${f(hundreds)}]$lyrics';
  }

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
