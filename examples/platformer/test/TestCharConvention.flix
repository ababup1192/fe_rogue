// TestCharConvention — キャラ描画の座標規約 pin: 全キャラの draw は
// 「足元中心・地面 y = 0 のローカル座標」で Placed を返す（CharStage のヘッダ参照）。
// 呼ぶ側（ラボの laneItems / 本編の View.playerItems）が世界座標へ平行移動する。
// pos#y に世界座標を足し込むキャラが混ざると本編で画面外へ消えるので、
// 「pos = (100, 0) で描いた全パーツが足元近傍の帯に収まる」ことを 15 体まとめて検査する。
// パーツの実効位置は種類ごとに違う: Poly は頂点が置き場所からの相対（置き場所 (0,0) +
// 絶対頂点の流儀も正規）・Box/円は左上原点 + サイズ。頂点とサイズを畳んで帯と比べる。

mod TestCharConvention {

    def stageWith(mode: CharStage.Mode): CharStage.Stage =
        { t = 0.5, pos = { x = 100.0, y = 0.0 }, vx = 0.0, facing = 1.0,
          mode = mode, modeT = 0.25 }

    /// パーツ 1 個が占める範囲 (xLo, xHi, yLo, yHi)。置き場所 + 形の広がり。
    def partBounds(placed: Render.Placed): (Float64, Float64, Float64, Float64) =
        let pos = placed#at;
        match placed#item {
            case Render.RenderItem.Poly(p) =>
                let xs = p#vertices |> List.map(v -> pos#x + v#x);
                let ys = p#vertices |> List.map(v -> pos#y + v#y);
                (Option.getWithDefault(pos#x, List.minimum(xs)),
                 Option.getWithDefault(pos#x, List.maximum(xs)),
                 Option.getWithDefault(pos#y, List.minimum(ys)),
                 Option.getWithDefault(pos#y, List.maximum(ys)))
            case Render.RenderItem.Box(b) =>
                (pos#x, pos#x + b#size#x, pos#y, pos#y + b#size#y)
            case _ =>
                (pos#x, pos#x, pos#y, pos#y)
        }

    /// 全 15 キャラを mode で描き、パーツが 1 つ以上あり、全パーツの実効範囲が
    /// x ∈ [30, 170]・y ∈ [yLo, yHi]（足元 0 の近傍帯）に収まるか。
    def allPartsInBand(mode: CharStage.Mode, yLo: Float64, yHi: Float64): Bool =
        List.range(1, 16) |> List.forAll(i -> {
            let parts = Roster.drawOf(i)(stageWith(mode));
            let nonEmpty = not List.isEmpty(parts);
            nonEmpty and (parts |> List.forAll(placed -> {
                let (xLo, xHi, pyLo, pyHi) = partBounds(placed);
                xLo >= 30.0 and xHi <= 170.0 and pyLo >= yLo and pyHi <= yHi
            }))
        })

    // 待機: 体は足元 0 から上へ生える（頭上の飾りを見込んでも 80px 以内）。
    @Test
    def testIdleDrawsFeetLocal(): Unit \ Assert =
        Assert.assertEq(expected = true,
            allPartsInBand(CharStage.Mode.IdleMode, -80.0, 26.0))

    // ジャンプ: 高さは呼ぶ側の平行移動が担うので、pos#y = 0 なら帯に収まったまま
    // （キャラ内部のポーズ変形ぶんだけ余裕を広めに取る）。
    @Test
    def testJumpDrawsFeetLocal(): Unit \ Assert =
        Assert.assertEq(expected = true,
            allPartsInBand(CharStage.Mode.JumpMode, -110.0, 26.0))

    // 走り: 進行方向の傾き・尾羽のはためき（vx = 0 でも形は出る）込みで帯の中。
    @Test
    def testRunDrawsFeetLocal(): Unit \ Assert =
        Assert.assertEq(expected = true,
            allPartsInBand(CharStage.Mode.RunMode, -90.0, 26.0))
}
