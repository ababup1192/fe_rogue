/// CameraView — 追従カメラの「定数設定」と「描画投影の作り方」を 1 箇所に集める。
///
/// カメラの状態は World の `cameraSmoothPos`（実際に映している点）ただ 1 つ。狙う点や追従設定は
/// 状態として持たず、設定はここの定数 `config`、狙う点は `CameraScene` が毎フレーム再計算する。
/// 描画側（`RenderWorld` / `BattlePanelUi`）は `projectionOf` で World から投影を作って world→screen 変換に使う。
mod CameraView {

    /// 追従カメラ設定の唯一の宣言点。zoom 0.32（引き）で、ゆるやか追従プリセット（smoothSpeed 5 / deadZone 0.3）を使う。
    pub def config(): Camera.Config =
        Camera.smooth({x = 0.32, y = 0.32})

    /// World の `cameraSmoothPos` から描画用の投影（world → screen 変換）を作る。
    /// `RenderWorld.viewTransform` と `BattlePanelUi` が読む描画変換の単一入口。
    pub def projectionOf(world: World, viewport: Camera.Viewport): Camera.Projection =
        Camera.projectionOf(World.cameraSmoothPosOf(world), config(), viewport)
}
