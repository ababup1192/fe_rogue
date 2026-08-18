// RenderTexture.withArgbBuffer が寄りかかっている前提を固定する。
//
// 画素を GPU へ送る所は Vector[Int32] をそのまま int[] とみなして IntBuffer へ一括で写す。
// これは Flix の Vector と Array が同じ JVM 配列だから成り立つ(stdlib の Array.toVector も
// 同じ向きの cast をしている)。コンパイラを上げてこの前提が崩れたら、絵が黙って壊れる前に
// ここで落ちてほしい。GL を開けないので、GL へ渡す直前の IntBuffer までを見る。
mod TestTextureUpload {
    import org.lwjgl.system.MemoryUtil

    def argb(n: Int32): Vector[Int32] =
        Vector.range(0, n) |> Vector.map(i -> i * 1103515245 + 12345)

    /// 画素を送る所と同じ写し方。
    def copyThrough(px: Vector[Int32]): List[Int32] \ IO =
        let arr = unchecked_cast(px as Array[Int32, Static]);
        let buf = MemoryUtil.memAllocInt(Int32.max(1, Vector.length(px)));
        discard buf.put(arr);
        discard buf.flip();
        let out = List.range(0, buf.limit()) |> List.map(i -> buf.get(i));
        MemoryUtil.memFree(buf);
        out

    @Test
    def testArgbVectorCopiesThroughIntBufferUnchanged(): Unit \ Assert =
        let px = argb(1024);
        Assert.assertTrue(unchecked_cast(copyThrough(px) as _ \ {}) == Vector.toList(px))
}
