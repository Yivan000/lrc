part of lrc;

/// A data class to store each yielding of the stream
class LrcStream {
  /// The previous line. Is null if the current line is the fist position.
  LrcLine? previous;

  /// Tthe current line
  LrcLine current;

  /// The next line. Is null if the current line is the last position.
  LrcLine? next;

  /// The duration from the current to the next. Is null if the current line is the last position.
  Duration? duration;

  /// The position of the current line
  int position;

  /// The total number of lines in the stream
  int length;

  /// The main constructor for a LrcStream
  LrcStream(
      {this.previous,
      required this.current,
      this.next,
      this.duration,
      required this.position,
      required this.length})
      //position should be greater than or equal to 0
      : assert(position >= 0),
        //the length should be greater than or equal to the position
        assert(length >= position),
        //previous is null only if position is 0
        assert((previous == null) ? position == 0 : true),
        //next is null only if position is the last
        assert((next == null) ? position == length : true);
}
