/// CameraProjection — ワールド座標と画面（viewport）座標を相互変換する純投影（状態なし）。
/// カメラが「どこをどれだけ拡大して映すか」を offset と scale だけで表し、描画時に各点へ掛ける。
/// 追従の仕組み（`CameraFollow`）とは独立で、視点の中心さえ決まれば単独で使える再利用部品。
/// 語彙は Bevy `Camera` に合わせる（`world_to_viewport` / `viewport_to_world_2d` 直訳）。
/// 利用例: 追従カメラが出した中心で駒のワールド座標を viewport px に写す / マウス座標をワールドへ戻す /
///         固定カメラや別方式の追従からも同じ変換を使う。
mod CameraProjection {

    /// カメラが映す可視矩形の px サイズ（Bevy の `Camera` viewport に対応）。
    /// zoom を反映したワールド単位の半幅・半高への換算に使う。
    pub type alias Viewport = { width = Float64, height = Float64 }

    /// 投影値。`scale` は拡大率（zoom）、`offset` は画面原点を合わせる平行移動量。
    /// 変換は `viewport = world * scale - offset`。
    pub type alias Projection = { offset = Vec2.Vec2, scale = Vec2.Vec2 }

    /// 何も動かさない単位投影（カメラ未設定時のフォールバック）。
    pub def identity(): Projection =
        { offset = Vec2.zero(), scale = {x = 1.0, y = 1.0} }

    /// 視点の中心 `center`（world 座標）が viewport 中央に来る投影を作る。
    /// `viewport = world * zoom - (center * zoom - 画面半分)`。
    pub def toProjection(center: Vec2.Vec2, zoom: Vec2.Vec2, viewport: Viewport): Projection =
        let halfW = viewport#width / 2.0;
        let halfH = viewport#height / 2.0;
        { scale = zoom,
          offset = {x = center#x * zoom#x - halfW,
                    y = center#y * zoom#y - halfH} }

    /// world 座標を viewport 座標へ写す: `viewport = world * scale - offset`（Bevy `world_to_viewport`）。
    pub def worldToViewport(proj: Projection, worldPos: Vec2.Vec2): Vec2.Vec2 =
        {x = worldPos#x * proj#scale#x - proj#offset#x,
         y = worldPos#y * proj#scale#y - proj#offset#y}

    /// viewport 座標を world 座標へ戻す（`worldToViewport` の逆・Bevy `viewport_to_world_2d`）。
    /// scale が 0 の軸は zoom 無し扱い。
    pub def viewportToWorld(proj: Projection, viewportPos: Vec2.Vec2): Vec2.Vec2 =
        let sx = proj#scale#x;
        let sy = proj#scale#y;
        {x = if (sx == 0.0) viewportPos#x + proj#offset#x
             else (viewportPos#x + proj#offset#x) / sx,
         y = if (sy == 0.0) viewportPos#y + proj#offset#y
             else (viewportPos#y + proj#offset#y) / sy}

    /// world 単位のサイズを viewport 単位へ写す（zoom で寄った分だけ大きく見える）。
    pub def worldToViewportSize(proj: Projection, worldSize: Vec2.Vec2): Vec2.Vec2 =
        {x = worldSize#x * proj#scale#x,
         y = worldSize#y * proj#scale#y}

    /// viewport 単位のサイズを world 単位へ戻す。scale が 0 の軸は元のまま。
    pub def viewportToWorldSize(proj: Projection, viewportSize: Vec2.Vec2): Vec2.Vec2 =
        let sx = proj#scale#x;
        let sy = proj#scale#y;
        {x = if (sx == 0.0) viewportSize#x else viewportSize#x / sx,
         y = if (sy == 0.0) viewportSize#y else viewportSize#y / sy}
}
