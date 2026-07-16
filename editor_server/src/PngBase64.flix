// PngBase64 — 描き上がった画像 (BufferedImage) を PNG の base64 文字列にする。
// ファイルに書かずメモリ上で符号化するのは、プレビュー画像を JSON 応答に
// そのまま載せて運ぶため (ディスクに一時ファイルを増やさない)。

mod PngBase64 {
    import java.awt.image.BufferedImage
    import java.io.ByteArrayOutputStream
    import java.io.OutputStream
    import java.util.{Base64 => JBase64}
    import javax.imageio.ImageIO

    /// 画像を PNG に符号化して base64 文字列で返す。
    pub def encode(image: BufferedImage): String \ IO =
        let buffer = new ByteArrayOutputStream();
        let out: OutputStream = checked_cast(buffer);
        discard ImageIO.write(image, "png", out);
        JBase64.getEncoder().encodeToString(buffer.toByteArray())
}
