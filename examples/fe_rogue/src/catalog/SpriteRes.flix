/// Sprite ノードにアタッチする単一フレーム表示設定の共通型。
///
/// Unit / Weapon / Staff の各 catalog が ItemMenu アイコンや HUD / popup の
/// 単一フレーム表示に使う。Unit/Weapon/Staff → Sprite の依存方向を一方向に保つため
/// 中立モジュールとして切り出している。
///
///   `offset` は描画時の x/y シフト（px）。スプライトシートに padding がある場合
///   （例: Kenney 系で 16 px 絵 + 1 px gutter で cellW=17 となるケース）の
///   視覚的中央寄せ補正に使う。デフォルトは {0, 0}。
///   `scale` は board 表示時の拡大倍率。既定 {1, 1} = 画像ピクセル等倍。
///   `flipForFacing` は「左向きの絵しか無い」スプライト用のフラグ。true の駒は
///   右方向へ移動したとき Sprite を水平反転 (flipH) して右向きに見せる。
///   既定 false（既存の前向き character_sheet 等は反転しない）。反転の実適用は
///   PlayerScene / EnemyScene の移動処理が担う。
mod SpriteRes {
    pub type alias SpriteResource = {
        texture = String,
        hframes = Int32,
        vframes = Int32,
        frame   = Int32,
        offset  = Vec2.Vec2,
        scale   = Vec2.Vec2,
        flipForFacing = Bool
    }
}
