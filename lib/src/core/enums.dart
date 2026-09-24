part of lrc;

///The types of LRC
enum LrcTypes {
  ///A simple LRC, with no extra formatting, etc
  simple,

  ///LRC with modifiers at the start in the form `A: foo`
  extended,

  ///LRC with additional timestamps per line in the form `<00:00.00> foo`
  enhanced,

  ///LRC that some lines are extended and some are enhanced
  extended_enhanced
}
