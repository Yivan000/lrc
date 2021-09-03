This package parses and handles LRC strings, along with handy methods for them.


## Features
* It can parse LRC strings or create new ones from scratch
* Simple and intuitive
* Adds handy extension methods for strings specific to LRCs
* Ability to stream the lyrics at the set durations

## Usage
### Installing
Installation instructions can be found on the "Installing" tab on pub.dev.

### Importing
As always, import first this package:
```dart
import 'package:lrc/lrc.dart';
```

### Parsing
This package only accepts strings so that this can be used for Dart JS and for the web. To accept from files, parse and extract the contents of the file yourself and put it into a string.

You can parse strings using the following:

```dart
//this string contains a LRC that can be parsed
String unparsedLrc = """
[ti:Never Gonna Give You Up]
[ar:Rick Astley]
[la:en]
[00:18.78]We're no strangers to love
[00:22.83]You know the rules and so do I
[00:27.11]A full commitment's what I'm thinking of
[00:31.25]You wouldn't get this from any other guy
"""; 

//parse the string using the static method
Lrc parsedLrc = Lrc.parse(unparsedLrc);

//parse the string using the handy extension method
Lrc parsedLrc = unparsedLrc.toLrc();
```

Parsing will return a `Lrc` object if successful. If the string is not a valid LRC, then a `FormatExeption` will be thrown.

You can check if the string is valid using the following:

```dart
//we don't know if this is valid lrc
String idk = ...; 

//check using the static method
bool isValid = Lrc.isValid(idk);

//check using the handy extension getter
bool isValid = idk.isValidLrc;
```
Checking will return a `bool`.

### Creating
If you want to create a LRC from scratch, you can do that by creating a new `Lrc` object with its parameters.

```dart
Lrc(
  type: //[LrcTypes] The type of the lrc. See below for more details. (required)
  lyrics: //[List<LrcLine>] The lyrics themselves. See below for more details. (required)
  artist: //[String] The artist of the song (optional)
  album: //[String] The album of the song (optional)
  title: //[String] The title of the song (optional)
  author: //[String] The author of the lyrics (optional)
  creator: //[String] The creator of the LRC file (optional)
  program: //[String] The program that created the LRC file (optional)
  version: //[String] The version of the program that created the LRC file (optional)
  length: //[String] The length/duration of the song  (optional)
  language: //[String] The IETF BCP 47 language tag of the song (optional)
  offset: //[int] The offset of the timing in milliseconds (optional)
)
```

#### Types
LRC comes with three types, simple, extended, and enhanced. See the Wikipedia article on LRCs for more information on these types. In this package, the types are stored in an enum class called `LrcTypes`.

```dart
LrcTypes.simple
LrcTypes.extended
LrcTypes.enhanced
LrcTypes.extended_enhanced //some lines are extended while some are enhanced
```

#### Lyrics
The lyrics are encoded in a `List<LrcLine>`, which are basically a list of `LrcLine` in which has the following properties:

```dart
LrcLine(
  timestamp: //[Duration] the timestamp wherein this lyric will show (required)
  lyrics: //[String] the actual raw lyrics in this line (required)
  args: //[Map<String, Object>] addition arguments if the type is not simple (optional)
)
```

If the LRC is extended, then that particular line will have these as arguments:

```dart
<String, Object>{
  'letter': //[String] a string containing the letter modifier
  'lyrics': //[String] a string containing the lyrics for that line
}
```

If the LRC is enhanced, then that line will have these as arguments:

```dart
//The key string is the timestamp in angle brackets as seen in the raw lyrics. There will be a key-value pair for each timestamp-lyric pair in the raw line.
<String, Object>{
  '<00:00,00>': <String, Object>{
    'duration': //[Duration] the timestamp of the lyrics
	'lyrics': //[String] the lyrics for that timestamp
  }
}
```

### Formatting
To format the stored `Lrc` into an actual string that can be saved into a file later on:

```dart
Lrc parsedLrc = ...; //the Lrc object to format

//format using the format() method
String raw = parsedLrc.format();
```

#### Formatting a single line
To format just a single `LrcLine`:
```dart
LrcLine line = ...; //the LrcLine object to format

//format using the `formattedLine` property
String raw = line.formattedLine;
```

### Streaming
You can stream each lyric at their set duration. To do this:

```dart
streamLrc(Lrc lrc) async {
  // subscribe using the `stream` property
  await for (LrcStream i in lrc.stream) {
    ...
  }

  // subscribe using the handy `toStream()` extension method on List<LrcLine>
  await for (LrcStream i in lrc.lyrics.toStream()) {
    ...
  }
}

//You can also do this with a List<LrcLine>
async streamLrc(List<LrcLine> lines){
	// subscribe using the handy `toStream()` extension method
  await for (LrcStream i in lines.toStream()){
	  ...
  }
}
```
The `LrcStream` class that outputs from each yielding of a stream stores the following:
```dart
LrcStream(
  previous: //[LrcLine] the previous line. Is null if its the first line
  current: //[LrcLine] the current line
  next: //[LrcLine] the next line. Is null if its the last line
  duration: //[Duration] the duration from the current to the next. Is null if its the last line
  position: //[int] the position of the current line
  length: //[int] the number of lines
)
```

## License
This package is licensed under the 3 clause BSD license.
```
Copyright 2021 Yivan's Creations

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```