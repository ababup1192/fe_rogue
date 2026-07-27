// RenderFontCache — 焼き上がったフォントアトラスをディスクに取っておき、次の起動で読むだけにする。
//
// 日本語フォントは 1 本で数千字あり、全部を距離場にするのに十数秒かかる。焼き上がりは
// 同じ TTF・同じ大きさ・同じ焼き方なら毎回まったく同じなので、1 度焼いたら取っておけばよい。
//
// **読めないときは黙って焼き直す。** 取っておいた物が壊れていても・古くても・書き込めなくても、
// 起動が止まることは無い（遅くなるだけ）。
mod RenderFontCache {
    import org.lwjgl.BufferUtils
    import java.io.File
    import java.io.FileInputStream
    import java.io.RandomAccessFile
    import java.io.ByteArrayOutputStream
    import java.io.ByteArrayInputStream
    import java.io.DataOutputStream
    import java.io.DataInputStream
    import java.lang.System
    import java.lang.Exception
    import java.nio.ByteBuffer
    import java.nio.channels.FileChannel
    import java.security.MessageDigest
    import java.util.zip.CRC32

    /// ファイルの目印。形を変えたらここも変える（前の形のファイルは読まずに捨てる）。
    def magic(): Int64 = 0x46474546_4F4E5402i64

    /// 1 字ぶんの記録の長さ: 文字番号(4) + 数値 9 個(8×9)。
    def glyphBytes(): Int32 = 76

    /// 取っておく場所。FLIX_GE_CACHE_DIR があればそこ、無ければ ~/.cache/flix_game_engine/font。
    /// 配布した .app の中はプロジェクト配下が書けないことがあるのでホーム側に置く。
    /// 同じ TTF を使う別のゲームどうしで使い回せるのも利点。
    /// テストは環境変数を後から差し替えられないので、システムプロパティ側の指定も見る。
    pub def dir(): String \ IO =
        let prop = System.getProperty("flix.ge.cacheDir");
        let custom = System.getenv("FLIX_GE_CACHE_DIR");
        if (not Object.isNull(prop)) prop
        else if (not Object.isNull(custom)) custom
        else "${System.getProperty("user.home")}/.cache/flix_game_engine/font"

    /// FLIX_GE_NO_FONT_CACHE=1 で取っておくのをやめる（焼き直しを確かめたいとき）。
    pub def enabled(): Bool \ IO =
        let value = System.getenv("FLIX_GE_NO_FONT_CACHE");
        Object.isNull(value) or value == "0"

    /// 取ってあれば読み、無ければ焼いて取っておく。
    pub def loadOrBake(entry: RenderAsset.FontEntry, wanted: Option[Set[Int32]],
                       onGlyph: (Int32, Int32) -> Unit \ IO): RenderFont.BakedFont \ IO =
        let fontBytes = readAllBytes(entry#path);
        // 焼く字も鍵に混ぜる。混ぜないと、文言を足したのに前の焼き上がりを読んでしまい、
        // 足したはずの字が出ないまま気付けない。
        let key = keyOf(fontBytes, entry#fontSize, wanted);
        let useCache = enabled();
        match (if (useCache) load(key, entry) else None) {
            case Some(baked) =>
                println("[RenderFont] '${entry#name}': 焼き上がりを取ってあったので読み込みました"
                    + "（${baked#side}x${baked#side}）");
                baked
            case None =>
                let baked = RenderFont.bakeFontCpu(entry, fontBytes, wanted, onGlyph);
                if (useCache) store(key, baked) else ();
                baked
        }

    /// TTF の中身・焼く大きさ・焼き方の版から決まる見分けの印。ファイルの置き場所は含めない —
    /// 同じ字形なら、どこに置いてあっても同じ物を使い回せる。
    /// 中身から作るので、起動のたびに TTF を読み直して数え直す手間はかかる（10MB 級で数十 ms）。
    pub def keyOf(fontBytes: Array[Int8, Static], fontSize: Float64,
                  wanted: Option[Set[Int32]]): String \ IO =
        let marks = match wanted {
            case None      => "all"
            case Some(cps) => "${Set.size(cps)}x${Set.foldLeft((acc, cp) -> acc + cp, 0, cps)}"
        };
        "${fontHash(fontBytes)}_${sanitize(Float64.toString(fontSize))}${sanitize(marks)}_${RenderFont.bakeVersion()}"

    /// 字形そのものを表す 16 桁。区切りに使う "_" を含まない形にしてある —
    /// 含むと、同じフォントの古い大きさを片付ける prefix 照合が他のフォントまで巻き込む。
    def fontHash(fontBytes: Array[Int8, Static]): String \ IO =
        let digest = MessageDigest.getInstance("SHA-256");
        let hash = digest.digest(fontBytes);
        List.range(0, 8) |> List.foldLeft((acc, i) -> {
            let b = Int32.bitwiseAnd(Int8.toInt32(Array.get(i, hash)), 255);
            "${acc}${hexDigit(b / 16)}${hexDigit(Int32.remainder(b, 16))}"
        }, "")

    def hexDigit(v: Int32): String =
        String.slice({ start = v }, { end = v + 1 }, "0123456789abcdef")

    def sanitize(s: String): String =
        s |> String.map(c -> if (Char.isLetter(c) or Char.isDigit(c)) c else 'x')

    /// 読めたら Some。無い・壊れている・食い違うときは None（そのまま焼き直せばよい）。
    pub def load(key: String, entry: RenderAsset.FontEntry): Option[RenderFont.BakedFont] \ IO =
        try {
            let path = pathOf(key);
            if (not new File(path).exists()) None
            else {
                let raf = new RandomAccessFile(path, "r");
                let ok = raf.readLong() == magic() and raf.readInt() == RenderFont.bakeVersion();
                if (not ok) { raf.close(); None }
                else {
                    let side = raf.readInt();
                    let fontSize = raf.readDouble();
                    let ascent = raf.readDouble();
                    let descent = raf.readDouble();
                    let lineGap = raf.readDouble();
                    let glyphCount = raf.readInt();
                    // 壊れたファイルの出鱈目な数でいきなり大きな置き場を取らないよう、
                    // ありえる範囲かどうかを先に見る。
                    if (side <= 0 or side > 8192 or glyphCount < 0 or glyphCount > 200000) {
                        raf.close();
                        None
                    } else {
                    let pixelBytes = side * side;
                    // 1 字ずつ読むと読み出しの回数が字数ぶん積み上がるので、字の表は一度に取る。
                    let table: Array[Int8, Static] = Array.empty(Static, glyphCount * glyphBytes());
                    raf.readFully(table);
                    let tableSum = checksumOf(table);
                    let glyphs = decodeGlyphs(table, glyphCount);
                    let pixels = BufferUtils.createByteBuffer(pixelBytes);
                    let channel = raf.getChannel();
                    readFully(channel, pixels);
                    discard pixels.position(0);
                    let storedTable = raf.readLong();
                    let storedPixels = raf.readLong();
                    raf.close();
                    discard pixels.position(0);
                    let crc = new CRC32();
                    crc.update(pixels);
                    discard pixels.position(0);
                    // 字の表の検算も見るのが肝。ここが壊れた物を通すと、絵は出るのに
                    // 字の置き場所だけがずれる — 2 回目の起動でだけ字が乱れる形になり、
                    // 一番気付きにくい。
                    if (tableSum != storedTable or crc.getValue() != storedPixels) None
                    else Some({
                        atlas = { textureName = "font_${entry#name}",
                                  fontSize = fontSize,
                                  textureSize = Int32.toFloat64(side),
                                  ascent = ascent, descent = descent, lineGap = lineGap,
                                  glyphs = glyphs },
                        side = side, pixels = pixels })
                    }
                }
            }
        } catch {
            case _: Exception => None
        }

    /// 焼き上がりを取っておく。書けなくても黙って諦める（次の起動が遅いだけ）。
    /// 途中まで書いたファイルが残らないよう、別名で書いてから置き換える。
    pub def store(key: String, baked: RenderFont.BakedFont): Unit \ IO =
        try {
            discard new File(dir()).mkdirs();
            let tmp = "${pathOf(key)}.${System.nanoTime()}.tmp";
            let raf = new RandomAccessFile(tmp, "rw");
            let head = headerBytes(baked);
            let table = glyphTableBytes(baked);
            raf.write(head);
            raf.write(table);
            discard baked#pixels.position(0);
            writeFully(raf.getChannel(), baked#pixels);
            discard baked#pixels.position(0);
            let crc = new CRC32();
            crc.update(baked#pixels);
            discard baked#pixels.position(0);
            raf.writeLong(checksumOf(table));
            raf.writeLong(crc.getValue());
            raf.close();
            // 書き終えてから名前を付け替える。途中まで書いたファイルを誰かが読むことが無い。
            let target = new File(pathOf(key));
            let tmpFile = new File(tmp);
            if (not tmpFile.renameTo(target)) {
                discard target.delete();
                discard tmpFile.renameTo(target)
            } else ();
            dropStaleSiblings(key, "${key}.fontatlas")
        } catch {
            case _: Exception => ()
        }

    // ── 内部 ──────────────────────────────────────────────────

    def pathOf(key: String): String \ IO = "${dir()}/${key}.fontatlas"

    def readAllBytes(path: String): Array[Int8, Static] \ IO =
        let fis = new FileInputStream(path);
        let bytes = fis.readAllBytes();
        fis.close();
        bytes

    def headerBytes(baked: RenderFont.BakedFont): Array[Int8, Static] \ IO =
        let bos = new ByteArrayOutputStream();
        let out = new DataOutputStream(bos);
        out.writeLong(magic());
        out.writeInt(RenderFont.bakeVersion());
        out.writeInt(baked#side);
        out.writeDouble(baked#atlas#fontSize);
        out.writeDouble(baked#atlas#ascent);
        out.writeDouble(baked#atlas#descent);
        out.writeDouble(baked#atlas#lineGap);
        out.writeInt(Map.size(baked#atlas#glyphs));
        out.flush();
        bos.toByteArray()

    def glyphTableBytes(baked: RenderFont.BakedFont): Array[Int8, Static] \ IO =
        let bos = new ByteArrayOutputStream();
        let out = new DataOutputStream(bos);
        Map.forEach((cp, gm) -> {
            out.writeInt(cp);
            out.writeDouble(gm#xOff); out.writeDouble(gm#yOff);
            out.writeDouble(gm#glyphW); out.writeDouble(gm#glyphH);
            out.writeDouble(gm#advance);
            out.writeDouble(gm#s0); out.writeDouble(gm#t0);
            out.writeDouble(gm#s1); out.writeDouble(gm#t1)
        }, baked#atlas#glyphs);
        out.flush();
        bos.toByteArray()

    def checksumOf(bytes: Array[Int8, Static]): Int64 \ IO =
        let crc = new CRC32();
        crc.update(bytes);
        crc.getValue()

    /// 同じフォントの、前の焼く大きさ・前の焼き方でできたファイルを片付ける。
    /// アトラス 1 枚は最大 64MB あり、project.json の大きさをいじるたびに積み上がると
    /// すぐ数百 MB になる。今しがた置いた物だけを残す。
    def dropStaleSiblings(key: String, keep: String): Unit \ IO =
        try {
            let prefix = String.takeWhile(c -> c != '_', key);
            if (String.isEmpty(prefix)) () else
            let files = new File(dir()).listFiles();
            if (Object.isNull(files)) ()
            else
                Array.forEach(f -> {
                    let name = f.getName();
                    if (String.startsWith({ prefix = "${prefix}_" }, name)
                            and String.endsWith({ suffix = ".fontatlas" }, name)
                            and name != keep)
                        discard f.delete()
                    else ()
                }, files)
        } catch {
            case _: Exception => ()
        }

    def decodeGlyphs(table: Array[Int8, Static], count: Int32): Map[Int32, TextLayout.GlyphMetrics] \ IO =
        let inp = new DataInputStream(new ByteArrayInputStream(table));
        // 読み出しは書いた順に 1 つずつ受け取る。レコードの中に並べて書くと、
        // どの欄から評価されるかが決まっていないぶん、順番が入れ替わりうる。
        List.range(0, count) |> List.foldLeft((acc, _i) -> {
            let cp = inp.readInt();
            let xOff = inp.readDouble();
            let yOff = inp.readDouble();
            let glyphW = inp.readDouble();
            let glyphH = inp.readDouble();
            let advance = inp.readDouble();
            let s0 = inp.readDouble();
            let t0 = inp.readDouble();
            let s1 = inp.readDouble();
            let t1 = inp.readDouble();
            let gm: TextLayout.GlyphMetrics = {
                xOff = xOff, yOff = yOff, glyphW = glyphW, glyphH = glyphH,
                advance = advance, s0 = s0, t0 = t0, s1 = s1, t1 = t1
            };
            Map.insert(cp, gm, acc)
        }, Map.empty())

    /// 1 回の read/write では全部運びきれないことがあるので、残りが無くなるまで繰り返す。
    def readFully(channel: FileChannel, buf: ByteBuffer): Unit \ IO =
        if (not buf.hasRemaining()) ()
        else if (channel.read(buf) < 0) ()
        else readFully(channel, buf)

    def writeFully(channel: FileChannel, buf: ByteBuffer): Unit \ IO =
        if (not buf.hasRemaining()) ()
        else { discard channel.write(buf); writeFully(channel, buf) }
}
