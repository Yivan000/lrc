import 'package:lrc/lrc.dart';

void main() {
  ///String to be parsed
  var song = """
[ti:Never Gonna Give You Up]
[ar:Rick Astley]
[la:en]
[00:18.78]We're no strangers to love
[00:22.83]You know the rules and so do I
[00:27.11]A full commitment's what I'm thinking of
[00:31.25]You wouldn't get this from any other guy
""";

  ///Parse LRC
  var lrc = Lrc.parse(song);
  //printLyrics(lrc);
  print(lrc.format());
}

///Prints the lyrics on their specified timestamp
void printLyrics(Lrc lrc) async {
  await for (LrcStream i in lrc.stream) {
    print('${i.current.lyrics}');
  }
}
