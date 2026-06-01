/// Sprite — 静止スプライト情報 (Sprite2D 用) の汎用型。
///
/// Unit / Weapon / Staff の各 catalog が ItemMenu アイコンや HUD / popup の
/// 単一フレーム表示に使う共通リソース型。以前は `UnitCatalog.SpriteResource` として
/// 定義されており、`WeaponCatalog` / `Staff` がそれを逆向き参照していた。
/// 依存方向を下向き (Unit/Weapon/Staff → Sprite) に揃えるため、ここに中立化した。
///
/// フィールド構成は旧 `UnitCatalog.SpriteResource` と完全一致:
///   `offset` は描画時の x/y シフト（px）。スプライトシートに padding がある場合
///   （例: Kenney 系で 16 px 絵 + 1 px gutter で cellW=17 となるケース）の
///   視覚的中央寄せ補正に使う。デフォルトは {0, 0}。
///   `scale` は board 表示時の拡大倍率。既定 {1, 1} = 画像ピクセル等倍。
mod Sprite {
    pub type alias SpriteResource = {
        texture = String,
        hframes = Int32,
        vframes = Int32,
        frame   = Int32,
        offset  = Vec2.Vec2,
        scale   = Vec2.Vec2
    }
}
