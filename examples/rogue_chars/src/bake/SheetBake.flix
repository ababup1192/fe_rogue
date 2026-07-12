// SheetBake — キャラ 1 体を 8 列 × 16 行 × 32px = 256×512 のスプライトシート PNG
// （透明背景・TYPE_INT_ARGB）と、fe_rogue が読む JSON マニフェストに焼く。
// 行 = クリップ（RogueStage.clips() の並び）・列 = コマ番号。
// PixelCanvas の Map を setRGB で 1:1 blit するので、ラスタライザを通らず正確。
// 全キャラ共用の白骨（死亡後の差し替え絵）も skeleton.png / skeleton.json として焼く。

mod SheetBake {
    import java.awt.image.BufferedImage
    import java.io.File
    import javax.imageio.ImageIO

    def cell(): Int32 = 32

    /// シートの列数。全クリップの最大コマ数（現契約では Attack 系の 6）から導くが、
    /// 下限 8 列を敷いてシート幅を 256px（2 の冪）に保つ。コマ数が 8 を超える
    /// クリップが将来増えたときは自動で広がる。行数はクリップ数から導出（16 行 = 512px）。
    def hframes(): Int32 =
        RogueStage.clips()
            |> List.map(RogueStage.frameCount)
            |> List.maximum
            |> Option.getWithDefault(1)
            |> Int32.max(8)

    def outDir(): String = "gallery/sheets"

    /// 全登録キャラのシート PNG + JSON マニフェストと、共通白骨シートを焼く。
    pub def bakeAll(): Unit \ IO + Fs.FileWrite =
        Roster.entries() |> List.forEach(entry -> {
            let (info, drawFn) = entry;
            let base = "${outDir()}/${info#classId}_${info#variant}";
            writePng(sheetImage(drawFn), "${base}.png");
            writeText(manifestJson(info), "${base}.json")
        });
        writePng(skeletonImage(), "${outDir()}/skeleton.png");
        writeText(skeletonJson(), "${outDir()}/skeleton.json")

    // ── シート画像 ──

    def sheetImage(drawFn: (RogueStage.Clip, Int32) -> PixelCanvas.Canvas): BufferedImage \ IO =
        let w = hframes() * cell();
        let h = List.length(RogueStage.clips()) * cell();
        let img = new BufferedImage(w, h, 2i32);   // 2 = TYPE_INT_ARGB（未書き込み = 透明）
        RogueStage.clips() |> List.forEach(clip -> {
            let oy = RogueStage.sheetRow(clip) * cell();
            List.range(0, RogueStage.frameCount(clip)) |> List.forEach(f ->
                blitCell(img, f * cell(), oy, drawFn(clip, f)))
        });
        img

    /// 共通白骨のシート（2 コマ横並び = 64×32・透明背景）。
    def skeletonImage(): BufferedImage \ IO =
        let img = new BufferedImage(2 * cell(), cell(), 2i32);   // 2 = TYPE_INT_ARGB
        List.range(0, 2) |> List.forEach(f ->
            blitCell(img, f * cell(), 0, Skeleton.draw(f)));
        img

    /// Canvas をシートのセル (ox,oy) へ 1:1 で書き込む（アルファ 255・透明セルは触らない）。
    def blitCell(img: BufferedImage, ox: Int32, oy: Int32, cv: PixelCanvas.Canvas): Unit \ IO =
        Map.forEach((k, c) -> {
            let (x, y) = k;
            img.setRGB(ox + x, oy + y, argbOf(c))
        }, cv)

    /// Color（0..1 の Float32）→ ARGB の Int32（アルファ 255 = 上位バイト 0xFF）。
    def argbOf(c: Color): Int32 =
        -16777216 + byteOf(c#r) * 65536 + byteOf(c#g) * 256 + byteOf(c#b)

    def byteOf(x: Float32): Int32 =
        let v = Float64.tryToInt32(Float32.toFloat64(x) * 255.0 + 0.5) |> Option.getWithDefault(0);
        Int32.max(0, Int32.min(255, v))

    /// PNG 書き出し（親ディレクトリが無ければ作る）。SoftRaster の writer は不透明背景を
    /// 塗るので使わず、透明背景のまま自前で書く。
    def writePng(img: BufferedImage, path: String): Unit \ IO =
        let file = new File(path);
        let parent = file.getParentFile();
        if (not Object.isNull(parent)) discard parent.mkdirs() else ();
        discard ImageIO.write(img, "png", file)

    // ── JSON マニフェスト ──

    def writeText(content: String, path: String): Unit \ Fs.FileWrite =
        run {
            discard Fs.WriteFile.write({str = content}, path)
        } with Fs.WriteFile.runWithFileWrite

    /// クリップ表（行・コマ数・fps・ループ）つきのマニフェスト。ゲーム側はこれだけで
    /// シートを切り出せる。flipForFacing=true = 横向きは左向き作画で右向きは実行時反転。
    /// deathSequence = 死亡演出の配線手順（death 終了後に共通白骨へ差し替える）。
    def manifestJson(info: Roster.Entry): String =
        let clipLines = RogueStage.clips()
            |> List.map(clipJson)
            |> List.join(",\n");
        let texture = "${info#classId}_${info#variant}";
        "{\n"
            + "  \"texture\": \"${texture}\",\n"
            + "  \"cellW\": ${cell()}, \"cellH\": ${cell()},\n"
            + "  \"hframes\": ${hframes()}, \"vframes\": ${List.length(RogueStage.clips())},\n"
            + "  \"flipForFacing\": true,\n"
            + "  \"anchor\": {\"footY\": 29},\n"
            + "  \"deathSequence\": { \"note\": \"death 終了後に共通 skeleton へ差し替え+死亡SE→ゲーム側 modulate でフェードアウト\",\n"
            + "                     \"skeleton\": \"skeleton\", \"skeletonFps\": 8.0 },\n"
            + "  \"clips\": {\n"
            + clipLines + "\n"
            + "  }\n"
            + "}\n"

    /// 共通白骨のマニフェスト（1 クリップだけの小さなシート）。
    def skeletonJson(): String =
        "{\n"
            + "  \"texture\": \"skeleton\",\n"
            + "  \"cellW\": ${cell()}, \"cellH\": ${cell()},\n"
            + "  \"hframes\": 2, \"vframes\": 1,\n"
            + "  \"flipForFacing\": false,\n"
            + "  \"anchor\": {\"footY\": 29},\n"
            + "  \"clips\": {\n"
            + "    \"skeleton\": {\"row\": 0, \"frames\": 2, \"fps\": 8.0, \"loop\": false}\n"
            + "  }\n"
            + "}\n"

    def clipJson(c: RogueStage.Clip): String =
        let loopStr = if (RogueStage.loops(c)) "true" else "false";
        "    \"${clipName(c)}\": {\"row\": ${RogueStage.sheetRow(c)}, "
            + "\"frames\": ${RogueStage.frameCount(c)}, "
            + "\"fps\": ${RogueStage.fps(c)}.0, \"loop\": ${loopStr}}"

    /// マニフェスト内のクリップ名（lowerCamel）。
    pub def clipName(c: RogueStage.Clip): String = match c {
        case RogueStage.Clip.IdleDown    => "idleDown"
        case RogueStage.Clip.IdleUp      => "idleUp"
        case RogueStage.Clip.IdleSide    => "idleSide"
        case RogueStage.Clip.WalkDown    => "walkDown"
        case RogueStage.Clip.WalkUp      => "walkUp"
        case RogueStage.Clip.WalkSide    => "walkSide"
        case RogueStage.Clip.AttackDown  => "attackDown"
        case RogueStage.Clip.AttackUp    => "attackUp"
        case RogueStage.Clip.AttackSide  => "attackSide"
        case RogueStage.Clip.UseItemDown => "useItemDown"
        case RogueStage.Clip.UseItemUp   => "useItemUp"
        case RogueStage.Clip.UseItemSide => "useItemSide"
        case RogueStage.Clip.DamageDown  => "damageDown"
        case RogueStage.Clip.DamageUp    => "damageUp"
        case RogueStage.Clip.DamageSide  => "damageSide"
        case RogueStage.Clip.Death       => "death"
    }
}
