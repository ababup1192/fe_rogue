// Tests for AudioUtil — pure audio utility functions

// ========================================================================
// alFormat
// ========================================================================

@Test
def testAlFormatMono8(): Unit \ Assert =
    Assert.assertEq(expected = AudioUtil.alFormatMono8(), AudioUtil.alFormat(1, 8))

@Test
def testAlFormatMono16(): Unit \ Assert =
    Assert.assertEq(expected = AudioUtil.alFormatMono16(), AudioUtil.alFormat(1, 16))

@Test
def testAlFormatStereo8(): Unit \ Assert =
    Assert.assertEq(expected = AudioUtil.alFormatStereo8(), AudioUtil.alFormat(2, 8))

@Test
def testAlFormatStereo16(): Unit \ Assert =
    Assert.assertEq(expected = AudioUtil.alFormatStereo16(), AudioUtil.alFormat(2, 16))

// ========================================================================
// findDataChunkOffset
// ========================================================================

@Test
def testFindDataChunkAtStart(): Unit \ Assert =
    // "data" chunk immediately at the search offset
    let getByte = i -> match i {
        case 12 => 100i8   // 'd'
        case 13 => 97i8    // 'a'
        case 14 => 116i8   // 't'
        case 15 => 97i8    // 'a'
        case _  => 0i8
    };
    let getInt = _i -> 0;
    let result = AudioUtil.findDataChunkOffset(getByte, getInt, 64, 12);
    Assert.assertEq(expected = Some(12), result)

@Test
def testFindDataChunkAfterFmt(): Unit \ Assert =
    // "fmt " chunk (size=16) at offset 12, then "data" at offset 36
    let getByte = i -> match i {
        case 12 => 102i8   // 'f'
        case 13 => 109i8   // 'm'
        case 14 => 116i8   // 't'
        case 15 => 32i8    // ' '
        case 36 => 100i8   // 'd'
        case 37 => 97i8    // 'a'
        case 38 => 116i8   // 't'
        case 39 => 97i8    // 'a'
        case _  => 0i8
    };
    let getInt = i -> match i {
        case 16 => 16      // fmt chunk size
        case _  => 0
    };
    let result = AudioUtil.findDataChunkOffset(getByte, getInt, 64, 12);
    Assert.assertEq(expected = Some(36), result)

@Test
def testFindDataChunkSkipsMultipleChunks(): Unit \ Assert =
    // "fmt " (size=16) at 12, "LIST" (size=8) at 36, "data" at 52
    let getByte = i -> match i {
        case 12 => 102i8   // 'f'
        case 13 => 109i8   // 'm'
        case 14 => 116i8   // 't'
        case 15 => 32i8    // ' '
        case 36 => 76i8    // 'L'
        case 37 => 73i8    // 'I'
        case 38 => 83i8    // 'S'
        case 39 => 84i8    // 'T'
        case 52 => 100i8   // 'd'
        case 53 => 97i8    // 'a'
        case 54 => 116i8   // 't'
        case 55 => 97i8    // 'a'
        case _  => 0i8
    };
    let getInt = i -> match i {
        case 16 => 16      // fmt chunk size
        case 40 => 8       // LIST chunk size
        case _  => 0
    };
    let result = AudioUtil.findDataChunkOffset(getByte, getInt, 64, 12);
    Assert.assertEq(expected = Some(52), result)

@Test
def testFindDataChunkNotFound(): Unit \ Assert =
    // No "data" chunk within limit
    let getByte = _i -> 0i8;
    let getInt = _i -> 0;
    let result = AudioUtil.findDataChunkOffset(getByte, getInt, 12, 12);
    Assert.assertEq(expected = (None: Option[Int32]), result)

