part of lrc;

/// The parsed LRC class.
///
/// You can instantiate this class directly
/// or parse a string using `Lrc.parse()`.
class Lrc {
  /// The overall type of LRC for this object
  final LrcTypes type;

  /// The name of the artist of the song (optional)
  ///
  /// This corresponds to the ID tag `[ar:]`.
  final String? artist;

  /// The name of the album of the song (optional)
  ///
  /// This corresponds to the ID tag `[al:]`.
  final String? album;

  /// The title of the song (optional)
  ///
  /// This corresponds to the ID tag `[ti:]`.
  final String? title;

  /// The name of the author of the lyrics (optional)
  ///
  /// This corresponds to the ID tag `[au:]`.
  final String? author;

  /// The name of the creator of the LRC file (optional)
  ///
  /// This corresponds to the ID tag `[by:]`.
  final String? creator;

  /// The name of the program that created the LRC file (optional)
  ///
  /// This corresponds to the ID tag `[re:]`.
  final String? program;

  /// The version of the program that created the LRC file (optional)
  ///
  /// This corresponds to the ID tag `[ve:]`.
  final String? version;

  /// The length of the song (optional)
  ///
  /// This corresponds to the ID tag `[length:]`.
  final String? length;

  /// The language of the song, using an IETF BCP 47 language tag (optional)
  ///
  /// This corresponds to the ID tag `[la:]`.
  final String? language;

  /// Offset of time in milliseconds, can be positive [shifts time up]
  /// or negative [shifts time down] (optional)
  ///
  /// This corresponds to the ID tag `[offset:]`.
  final int? offset;

  /// The list of lyric lines
  final List<LrcLine> lyrics;

  final int personCount;

  /// Handy parameter to get a stream of the lyrics.
  /// See `List<LrcLine>.toStream()`.
  Stream<LrcStream> get stream => lyrics.toStream();

  /// Use this constructor if you want to manually create an LRC from scratch.
  /// Otherwise, parse an LRC string using [Lrc.parse].
  const Lrc({
    this.type = LrcTypes.simple,
    required this.lyrics,
    this.artist,
    this.album,
    this.title,
    this.creator,
    this.author,
    this.program,
    this.version,
    this.length,
    this.offset,
    this.language,
    this.personCount = 1,
  });

  static Lrc parse(String text) => LrcParser.parse(text);

  /// Format the lrc to a readable string that can then be
  /// outputted to an LRC file.
  String format() {
    var buffer = StringBuffer();

    if (artist != null) buffer.writeln('[ar:$artist]');
    if (album != null) buffer.writeln('[al:$album]');
    if (title != null) buffer.writeln('[ti:$title]');
    if (length != null) buffer.writeln('[length:$length]');
    if (creator != null) buffer.writeln('[by:$creator]');
    if (author != null) buffer.writeln('[au:$author]');
    if (offset != null) buffer.writeln('[offset:${offset.toString()}]');
    if (program != null) buffer.writeln('[re:$program]');
    if (version != null) buffer.writeln('[ve:$version]');
    if (language != null) buffer.writeln('[la:$language]');

    final lrcLength = lyrics.length;
    for (var i = 0; i < lrcLength; i++) {
      buffer.writeln(lyrics[i].formattedLine);
    }

    return buffer.toString();
  }

  @override
  String toString() {
    var lyrics = this.lyrics.join('\n');

    return '''
    Type: '$type'
    Artist: '$artist'
    Album: '$album'
    Title: '$title'
    Author: '$author'
    Creator: '$creator'
    Program: '$program'
    Length: '$length'
    Language: '$language'
    Offset: '$offset'
    Lyrics: $lyrics
    ''';
  }
}
