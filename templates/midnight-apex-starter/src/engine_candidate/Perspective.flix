// Perspective — 道路断面のサンプラーを後方視点の画面座標へ射影する純粋な変換。
// コースの保存形式を知らず、View、ライバル、ゲートへ同じ遠近空間を渡す。
mod Perspective {

    /// 射影に必要な画面側の値。ゲーム状態へ逆向きに依存しないため引数で受け取る。
    pub type alias Config = {
        screenWidth = Float64,
        horizonY = Float64,
        nearY = Float64,
        viewDistance = Float64
    }

    /// ゲーム側が返す道路断面。metaは射影せず、そのまま表示側へ運ぶ付帯情報。
    pub type alias Section[a] = {
        centerX = Float64,
        width = Float64,
        meta = a
    }

    /// 道の断面を画面へ写した結果。
    pub type alias Slice[a] = {
        progress = Float64,
        centerX = Float64,
        halfWidth = Float64,
        y = Float64,
        scale = Float64,
        depth = Float64,
        meta = a
    }

    /// 地平線から手前までを構成する台形の数。
    pub def sliceCount(): Int32 = 36

    /// 画面寸法だけを渡して作れる標準の後方視点。
    pub def config(screenWidth: Float64, screenHeight: Float64): Config =
        { screenWidth = screenWidth,
          horizonY = screenHeight * 0.25,
          nearY = screenHeight + 4.0,
          viewDistance = screenHeight * 2.75 }

    /// 0（手前）から1（地平線）までの奥行きを道路断面へ変換する。
    pub def atDepth(depth: Float64, baseProgress: Float64,
                    sampleAt: Float64 -> Section[a],
                    config: Config): Slice[a] =
        let d = clamp01(depth);
        let distance = Float64.pow(base = d, 1.62) * config#viewDistance;
        let sample = sampleAt(baseProgress + distance);
        let cameraSample = sampleAt(baseProgress);
        let scale = 1.0 - d * 0.86;
        let bend = (sample#centerX - cameraSample#centerX) * scale * 1.55;
        { progress = baseProgress + distance,
          centerX = config#screenWidth / 2.0 + bend,
          halfWidth = sample#width * scale * 0.68,
          y = config#nearY - Float64.pow(base = d, 0.72)
              * (config#nearY - config#horizonY),
          scale = scale,
          depth = d,
          meta = sample#meta }

    /// 前方距離を、atDepth と同じ曲線の奥行きへ戻す。
    pub def depthOfDistance(distance: Float64, config: Config): Float64 =
        Float64.pow(
            base = clamp01(distance / config#viewDistance),
            1.0 / 1.62)

    /// ライバルの車線位置を、道路断面の中央と幅から画面Xへ写す。
    pub def laneX(laneOffset: Float64, slice: Slice[a]): Float64 =
        slice#centerX + laneOffset * slice#halfWidth * 1.15

    /// 道路を作る全断面を、手前から奥の順で返す。
    pub def slices(baseProgress: Float64,
                   sampleAt: Float64 -> Section[a],
                   config: Config): List[Slice[a]] =
        List.range(0, sliceCount() + 1)
            |> List.map(index ->
                atDepth(
                    Int32.toFloat64(index) / Int32.toFloat64(sliceCount()),
                    baseProgress,
                    sampleAt,
                    config))

    /// 射影の入力を画面外へ逃がさない。
    def clamp01(value: Float64): Float64 =
        Float64.max(0.0, Float64.min(1.0, value))
}
