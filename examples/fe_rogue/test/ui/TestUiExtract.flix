/// UiExtract.extractPolys の座標変換（レイアウト矩形左上をローカル頂点へ足して
/// design 空間の絶対座標へ移す）を固定する。
mod TestUiExtract {

    /// poly 1 枚だけの ui.json を spawn した UiWorld（失敗時 None）。root="Mark" は id=1。
    ///   points=[[0,0],[0,4],[3,2]]（整数＝加算の丸め誤差を避ける）/ color #ffd966 / zIndex 3。
    def spawnPoly(): Option[UiStore.UiWorld] =
        let json =
            "{\"root\":{\"name\":\"Mark\",\"widget\":\"poly\","
            + "\"points\":[[0,0],[0,4],[3,2]],\"color\":\"#ffd966\",\"zIndex\":3}}";
        JsonCompat.parse(json)
            |> Option.flatMap(json2 -> UiSpec.parse(json2) |> Result.toOption)
            |> Option.map(spec -> { let (_, ui) = UiSpec.spawnRoot(spec, UiStore.empty()); ui })

    // ════════════════════════════════════════════════════════
    // extractPolys: rect 左上をローカル頂点へ足して design 絶対座標へ移す
    //   rect 左上 = (10, 20) を全サブポリの各頂点へ加算（宣言 poly はサブポリ 1 個）
    //   local  [[[0,0],[0,4],[3,2]]]
    //   world  [[[10,20],[10,24],[13,22]]]
    //   tuple の Vec2 は適用した左上 (10,20)、zIndex は comp のまま 3。
    // ════════════════════════════════════════════════════════

    /// id=1 の poly を rect 左上 (10,20) で extract し、world サブポリ頂点・左上・zIndex を pin する。
    @Test
    def testExtractPolysOffsetsPointsByRectOrigin(): Unit \ Assert =
        let rects = Map#{1 => ({position = {x = 10.0, y = 20.0}, size = {x = 3.0, y = 4.0}}: Rect2.Rect2)};
        let vis = Map#{1 => true};
        let out = spawnPoly() |> Option.map(ui ->
            UiExtract.extractPolys(ui, rects, vis)
                |> List.map(entry -> {
                    let (id, origin, poly) = entry;
                    (id, (origin#x, origin#y),
                     poly#polys |> List.map(sub -> sub |> List.map(p -> (p#x, p#y))), poly#zIndex)
                }));
        Assert.assertEq(
            expected = Some(
                (1, (10.0, 20.0),
                 ((10.0, 20.0) :: (10.0, 24.0) :: (13.0, 22.0) :: Nil) :: Nil, 3) :: Nil),
            out)

    // ════════════════════════════════════════════════════════
    // extractPolys: 不可視 / rect 未確定は落とす
    // ════════════════════════════════════════════════════════

    /// vis=false の poly は出力に含まれない（空リスト）。
    @Test
    def testExtractPolysDropsInvisible(): Unit \ Assert =
        let rects = Map#{1 => ({position = {x = 0.0, y = 0.0}, size = {x = 3.0, y = 4.0}}: Rect2.Rect2)};
        let vis = Map#{1 => false};
        let count = spawnPoly() |> Option.map(ui -> List.length(UiExtract.extractPolys(ui, rects, vis)));
        Assert.assertEq(expected = Some(0), count)
}
