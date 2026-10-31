/// The main library for support for LRCs.
library lrc;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:html_unescape/html_unescape.dart';

part 'src/core/enums.dart';
part 'src/core/extensions.dart';
part 'src/core/html_entities.dart';
part 'src/core/line_resolver.dart';
part 'src/models/lrc.dart';
part 'src/models/lrc_line.dart';
part 'src/models/lrc_line_part.dart';
part 'src/models/lrc_stream.dart';
part 'src/parsers/lrc_parser.dart';
part 'src/parsers/lyrics_parser.dart';
part 'src/parsers/multi_timestamp_parser.dart';
part 'src/parsers/paxsenix_json_parser.dart';
part 'src/parsers/qrc_parser.dart';
part 'src/parsers/subtitle_parser.dart';
part 'src/parsers/ttml_parser.dart';
part 'src/parsers/wlrc_parser.dart';
