///|
/// `length` reporting one part and `parts` producing two would send a caller
/// chasing a bug in their own code. Both have to agree on where the boundary
/// is, and the boundary is the single-message capacity, not the concatenated
/// part capacity.
test "a message that fits one part produces one part" {
  let cases : Array[(String, @src.Encoding)] = [
    ("a".repeat(160), @src.Gsm7),
    ("a".repeat(161), @src.Gsm7),
    ("中".repeat(70), @src.Ucs2),
    ("中".repeat(71), @src.Ucs2),
  ]
  for pair in cases {
    let (text, encoding) = pair
    let expected = if @src.fits_single(text, encoding) { 1 } else { 2 }
    let submits = @src.build_submits(
      @src.Number(@src.International, @src.Isdn, "8613800138000"),
      text,
      1,
      encoding~,
    ) catch {
      e => fail(e.to_message())
    }
    inspect(submits.length(), content=expected.to_string())
  }
}

///|
test "the single part limits match the standard" {
  inspect(@src.single_capacity(@src.Gsm7), content="160")
  inspect(@src.single_capacity(@src.Ucs2), content="140")
  inspect(@src.single_capacity(@src.EightBit), content="140")
  inspect(@src.part_capacity(@src.Gsm7), content="153")
  inspect(@src.part_capacity(@src.Ucs2), content="134")
}

///|
test "fits_single agrees with the capacity numbers" {
  inspect(@src.fits_single("a".repeat(160), @src.Gsm7), content="true")
  inspect(@src.fits_single("a".repeat(161), @src.Gsm7), content="false")
  inspect(@src.fits_single("中".repeat(70), @src.Ucs2), content="true")
  inspect(@src.fits_single("中".repeat(71), @src.Ucs2), content="false")
  // An escaped character costs two septets, so 80 euros fill the message.
  inspect(@src.fits_single("€".repeat(80), @src.Gsm7), content="true")
  inspect(@src.fits_single("€".repeat(81), @src.Gsm7), content="false")
}
