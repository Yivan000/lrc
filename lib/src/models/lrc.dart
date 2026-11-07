part of lrc;

/// The parsed LRC class.
///
/// You can instantiate this class directly
/// or parse a string using `Lrc.parse()`.
class Lrc {
  static const kOffsetTag = 'offset';
  static const kLengthTag = 'length';

  /// The overall type of LRC for this object
  final LrcTypes type;

  /// The ID tags, `[ar:Artist]` is `{'ar': 'Artist'}`, in the order they were written.
  /// Unknown tags are kept too, so writing the lrc back keeps them.
  final Map<String, String> tags;

  /// The name of the artist of the song, ID tag `[ar:]`.
  String? get artist => tags['ar'];

  /// The name of the album of the song, ID tag `[al:]`.
  String? get album => tags['al'];

  /// The title of the song, ID tag `[ti:]`.
  String? get title => tags['ti'];

  /// The name of the author of the lyrics, ID tag `[au:]`.
  String? get author => tags['au'];

  /// The name of the creator of the LRC file, ID tag `[by:]`.
  String? get creator => tags['by'];

  /// The name of the program that created the LRC file, ID tag `[re:]`.
  String? get program => tags['re'];

  /// The version of the program that created the LRC file, ID tag `[ve:]`.
  String? get version => tags['ve'];

  /// The length of the song, ID tag `[length:]`.
  String? get length => tags[kLengthTag];

  /// The language of the song, using an IETF BCP 47 language tag, ID tag `[la:]`.
  String? get language => tags['la'];

  /// Offset of time in milliseconds, can be positive [shifts time up]
  /// or negative [shifts time down], ID tag `[offset:]`.
  late final int? offset = _parseOffset(tags[kOffsetTag]);

  static int? _parseOffset(String? offsetText) {
    if (offsetText == null) return null;
    return int.tryParse(offsetText);
  }

  /// The list of lyric lines, every one has a timestamp.
  final List<LrcLine> lyrics;

  /// The lines without a timestamp (section headers, notes, empty lines between verses), in the order they were written,
  /// so the ones after the last line come last.
  final List<LrcUntimedLine> untimedLines;

  final int personCount;

  /// Handy parameter to get a stream of the lyrics.
  /// See `List<LrcLine>.toStream()`.
  Stream<LrcStream> get stream => lyrics.toStream();

  /// Use this constructor if you want to manually create an LRC from scratch.
  /// Otherwise, parse an LRC string using [Lrc.parse].
  Lrc({
    this.type = LrcTypes.simple,
    required this.lyrics,
    this.tags = const {},
    this.untimedLines = const [],
    this.personCount = 1,
  });

  static Lrc parse(String text) => LrcParser.parse(text);

  Lrc withTags(Map<String, String> tags) {
    return Lrc(
      type: type,
      lyrics: lyrics,
      tags: tags,
      untimedLines: untimedLines,
      personCount: personCount,
    );
  }

  /// Format the lrc to a readable string that can then be
  /// outputted to an LRC file.
  ///
  /// Every untimed line is written right above the line it was above, lines are written in time order.
  String format() {
    final buffer = StringBuffer();

    for (final e in tags.entries) {
      final tag = e.key;
      final value = e.value;
      buffer.writeln('[$tag:$value]');
    }

    if (untimedLines.isEmpty) {
      for (final line in lyrics) {
        buffer.writeln(line.format());
      }
      return buffer.toString();
    }

    final untimedTextsByIndex = groupUntimedTexts();
    for (final line in lyrics) {
      final texts = untimedTextsByIndex.remove(line.originalIndex);
      if (texts != null) {
        for (final text in texts) {
          buffer.writeln(text);
        }
      }
      buffer.writeln(line.format());
    }

    // -- the ones after the last line, and the ones whose line is gone
    for (final texts in untimedTextsByIndex.values) {
      for (final text in texts) {
        buffer.writeln(text);
      }
    }

    return buffer.toString();
  }

  /// The [untimedLines] texts by the [LrcLine.originalIndex] they are above, in order.
  /// The ones after the last line are keyed by null.
  Map<int?, List<String>> groupUntimedTexts() {
    final textsByIndex = <int?, List<String>>{};
    for (final untimed in untimedLines) {
      final texts = textsByIndex[untimed.beforeIndex] ??= [];
      texts.add(untimed.text);
    }
    return textsByIndex;
  }

  @override
  String toString() {
    var lyrics = this.lyrics.join('\n');

    return '''
    Type: '$type'
    Tags: '$tags'
    Lyrics: $lyrics
    ''';
  }
}
