// RenderAudio — OpenAL バッファ読み込みとサウンドレジストリ構築
//
// LwjglLayer.flix の loadOggToALBuffer / loadWavToALBuffer / loadAudioRegistry を移植。
// OpenAL の初期化 (alcOpenDevice 等) や再生制御は外周 (engine/ide 側) が担当する。

mod RenderAudio {
    import org.lwjgl.openal.AL10
    import org.lwjgl.stb.STBVorbis
    import org.lwjgl.system.MemoryStack
    import org.lwjgl.system.MemoryUtil
    import java.nio.ByteBuffer
    import java.nio.ByteOrder
    import java.nio.file.Files
    import java.nio.file.Paths

    /// OGG ファイルを STBVorbis でデコードし、OpenAL バッファにアップロードする
    pub def loadOggToALBuffer(path: String): Int32 \ IO =
        let stack = MemoryStack.stackPush();
        let channelsBuf = stack.mallocInt(1);
        let sampleRateBuf = stack.mallocInt(1);
        let pcm = STBVorbis.stb_vorbis_decode_filename(path, channelsBuf, sampleRateBuf);
        if (Object.isNull(pcm)) {
            discard MemoryStack.stackPop();
            bug!("Failed to decode OGG: ${path}")
        } else {
            let channels = channelsBuf.get(0);
            let sampleRate = sampleRateBuf.get(0);
            discard MemoryStack.stackPop();
            let format = if (channels == 1) AL10.AL_FORMAT_MONO16 else AL10.AL_FORMAT_STEREO16;
            let buffer = AL10.alGenBuffers();
            AL10.alBufferData(buffer, format, pcm, sampleRate);
            MemoryUtil.memFree(pcm);
            buffer
        }

    /// WAV ファイルをパースし、OpenAL バッファにアップロードする
    pub def loadWavToALBuffer(path: String): Int32 \ IO =
        let wavBytes = Files.readAllBytes(Paths.get(path));
        let hdr = ByteBuffer.wrap(wavBytes);
        discard hdr.order(ByteOrder.LITTLE_ENDIAN);
        let channels = Int16.toInt32(hdr.getShort(22));
        let sampleRate = hdr.getInt(24);
        let bitsPerSample = Int16.toInt32(hdr.getShort(34));
        let dataOffset = match AudioUtil.findDataChunkOffset(i -> hdr.get(i), i -> hdr.getInt(i), hdr.limit(), 12) {
            case Some(off) => off
            case None      => bug!("WAV data chunk not found: ${path}")
        };
        let dataSize = hdr.getInt(dataOffset + 4);
        let pcmStart = dataOffset + 8;
        let pcmBuf = MemoryUtil.memAlloc(dataSize);
        discard pcmBuf.put(wavBytes, pcmStart, dataSize);
        discard pcmBuf.flip();
        let format = AudioUtil.alFormat(channels, bitsPerSample);
        let buffer = AL10.alGenBuffers();
        AL10.alBufferData(buffer, format, pcmBuf, sampleRate);
        MemoryUtil.memFree(pcmBuf);
        buffer

    /// サウンドマニフェストから全音声を読み込み、AudioRegistry (名前 → OpenAL ソース ID) を返す
    pub def loadAudioRegistry(manifest: List[RenderAsset.AudioEntry]): RenderAsset.AudioRegistry \ IO =
        List.foldLeft((registry, entry) -> {
            let buffer = if (String.endsWith({suffix = ".ogg"}, entry#path))
                loadOggToALBuffer(entry#path)
            else
                loadWavToALBuffer(entry#path);
            let source = AL10.alGenSources();
            AL10.alSourcei(source, AL10.AL_BUFFER, buffer);
            AL10.alSourcei(source, AL10.AL_LOOPING, if (entry#looping) AL10.AL_TRUE else AL10.AL_FALSE);
            println("  ${entry#path} loaded");
            Map.insert(entry#name, source, registry)
        }, Map.empty(), manifest)

}
