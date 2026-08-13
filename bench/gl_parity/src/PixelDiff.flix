// 2 枚の PNG を RGB で画素比較する（alpha は見ない — pass の alpha は GL のブレンド副産物で
// 一致保証が無いため。docs/backend-parity.md の tex 場の行を参照）。
// 不一致があれば「GL | Soft | 違いヒート」を横に並べた 1 枚を debug/diff/ に描き出す。
// 画像の合成は Graphics2D を使わず Raster 直コピーだけ — macOS の -XstartOnFirstThread 下で
// AWT Toolkit の初期化待ちにハングしうるため（ReferenceDiff.sideBySide と同じ理由）。
mod PixelDiff {
    import java.awt.image.BufferedImage
    import java.io.File
    import javax.imageio.ImageIO

    /// 1 scene ぶんの比較結果。diffPx = RGB が違う画素数（読めない・寸法違いは -1）、
    /// maxDelta = チャンネル差の最大値。
    pub type alias Outcome = { name = String, diffPx = Int32, maxDelta = Int32 }

    def gap(): Int32 = 4

    def gapColor(): Int32 = 0x00FF00FF

    pub def compare(name: String, glPath: String, softPath: String,
                    diffPath: String): Outcome \ IO =
        match (readPng(glPath), readPng(softPath)) {
            case (Some(gl), Some(soft)) =>
                let w = gl.getWidth();
                let h = gl.getHeight();
                if (w != soft.getWidth() or h != soft.getHeight()) {
                    println("[parity] ${name}: 寸法が違う gl=${w}x${h} soft=${soft.getWidth()}x${soft.getHeight()}");
                    { name = name, diffPx = -1, maxDelta = 0 }
                } else {
                    let (diffPx, maxDelta) = diffStats(gl, soft, w, h);
                    if (diffPx > 0) writeTriptych(gl, soft, w, h, diffPath) else ();
                    { name = name, diffPx = diffPx, maxDelta = maxDelta }
                }
            case (None, _) =>
                println("[parity] ${name}: GL の絵が無い (${glPath})");
                { name = name, diffPx = -1, maxDelta = 0 }
            case (_, None) =>
                println("[parity] ${name}: SoftRaster の絵が無い (${softPath})");
                { name = name, diffPx = -1, maxDelta = 0 }
        }

    def readPng(path: String): Option[BufferedImage] \ IO =
        let file = new File(path);
        if (not file.exists()) None
        else {
            let img = ImageIO.read(file);
            if (Object.isNull(img)) None else Some(img)
        }

    def chan(v: Int32, sh: Int32): Int32 =
        Int32.bitwiseAnd(Int32.rightShift(v, sh), 255)

    def pixelDelta(a: Int32, b: Int32): Int32 =
        let dr = Int32.abs(chan(a, 16) - chan(b, 16));
        let dg = Int32.abs(chan(a, 8) - chan(b, 8));
        let db = Int32.abs(chan(a, 0) - chan(b, 0));
        Int32.max(dr, Int32.max(dg, db))

    def diffStats(gl: BufferedImage, soft: BufferedImage,
                  w: Int32, h: Int32): (Int32, Int32) \ IO =
        region rc {
            let ga: Array[Int32, rc] = Array.empty(rc, w * h);
            let sa: Array[Int32, rc] = Array.empty(rc, w * h);
            discard gl.getRGB(0, 0, w, h, ga, 0, w);
            discard soft.getRGB(0, 0, w, h, sa, 0, w);
            List.range(0, w * h) |> List.foldLeft((acc, i) -> {
                let (cnt, mx) = acc;
                let d = pixelDelta(Array.get(i, ga), Array.get(i, sa));
                if (d == 0) acc else (cnt + 1, Int32.max(mx, d))
            }, (0, 0))
        }

    /// 「GL | Soft | ヒート」の 1 枚。ヒートは 同一 = 黒 / 差 ±1 = 暗い黄 / ±2 以上 = 赤。
    def writeTriptych(gl: BufferedImage, soft: BufferedImage,
                      w: Int32, h: Int32, path: String): Unit \ IO =
        region rc {
            let sheet = new BufferedImage(w * 3 + gap() * 2, h, 1i32);
            let ga: Array[Int32, rc] = Array.empty(rc, w * h);
            let sa: Array[Int32, rc] = Array.empty(rc, w * h);
            discard gl.getRGB(0, 0, w, h, ga, 0, w);
            discard soft.getRGB(0, 0, w, h, sa, 0, w);
            sheet.setRGB(0, 0, w, h, ga, 0, w);
            sheet.setRGB(w + gap(), 0, w, h, sa, 0, w);
            let heat: Array[Int32, rc] = Array.empty(rc, w * h);
            List.forEach(i -> {
                let d = pixelDelta(Array.get(i, ga), Array.get(i, sa));
                let c = if (d == 0) 0x000000 else if (d == 1) 0x807000 else 0xFF2020;
                Array.put(c, i, heat)
            }, List.range(0, w * h));
            sheet.setRGB((w + gap()) * 2, 0, w, h, heat, 0, w);
            let bar: Array[Int32, rc] = Array.repeat(rc, gap() * h, gapColor());
            sheet.setRGB(w, 0, gap(), h, bar, 0, gap());
            sheet.setRGB(w * 2 + gap(), 0, gap(), h, bar, 0, gap());
            writePng(sheet, path)
        }

    /// 親フォルダを掘ってから PNG を書く（gl_parity 内の唯一の書き口 — Main も使う）。
    pub def writePng(img: BufferedImage, path: String): Unit \ IO =
        let file = new File(path);
        let parent = file.getParentFile();
        if (not Object.isNull(parent)) discard parent.mkdirs() else ();
        discard ImageIO.write(img, "png", file)
}
