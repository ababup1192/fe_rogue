// AudioUtil — pure utility functions for audio file parsing

mod AudioUtil {

    // ========================================================================
    // OpenAL format constants
    // ========================================================================

    pub def alFormatMono8(): Int32 = 0x1100
    pub def alFormatMono16(): Int32 = 0x1101
    pub def alFormatStereo8(): Int32 = 0x1102
    pub def alFormatStereo16(): Int32 = 0x1103

    /// Determine OpenAL buffer format from channel count and bits per sample.
    pub def alFormat(channels: Int32, bitsPerSample: Int32): Int32 =
        if (channels == 1) {
            if (bitsPerSample == 8) alFormatMono8() else alFormatMono16()
        } else {
            if (bitsPerSample == 8) alFormatStereo8() else alFormatStereo16()
        }

    // ========================================================================
    // WAV chunk parsing
    // ========================================================================

    /// Find the byte offset of the "data" chunk in WAV byte data.
    /// Searches from `offset`, skipping unknown chunks using their size fields.
    /// `getByte(i)` reads one byte at index i.
    /// `getInt32LE(i)` reads a little-endian Int32 at index i.
    /// Returns None if the data chunk is not found before `limit`.
    pub def findDataChunkOffset(getByte: Int32 -> Int8 \ ef, getInt32LE: Int32 -> Int32 \ ef, limit: Int32, offset: Int32): Option[Int32] \ ef =
        if (offset >= limit - 8) None
        else if (getByte(offset) == 100i8 and      // 'd'
                 getByte(offset + 1) == 97i8 and   // 'a'
                 getByte(offset + 2) == 116i8 and  // 't'
                 getByte(offset + 3) == 97i8)      // 'a'
            Some(offset)
        else {
            let chunkSize = getInt32LE(offset + 4);
            findDataChunkOffset(getByte, getInt32LE, limit, offset + 8 + chunkSize)
        }

}
