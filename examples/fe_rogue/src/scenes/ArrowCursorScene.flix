/// ArrowCursorScene — 杖・投擲の照準矢印の状態書き込み口
///
/// `StaffAim` / `ThrowAim` フェーズで、選択中プレイヤーの隣接 4 セルのいずれか
/// （現在指している `direction` 側）を指す照準矢印を出す。方向キーで向きが切り替わり、
/// Z で発射、X / Esc でキャンセル。
///
/// この module はシーンノードを持たず、照準の論理状態（anchor / direction / gridPos）を
/// `ArrowCursorState.State` resource に書くだけの入口。矢印スプライトの描画は
/// `RenderWorld.renderArrowCursor` が resource の gridPos（セル中心）と direction（回転）から
/// 直描きし、表示条件（`StaffAim` / `ThrowAim` のときだけ出す）も render 側が phase で判定する。
mod ArrowCursorScene {

    /// 矢印カーソルの論理状態。resource 側の型に委譲する。
    pub type alias Data = ArrowCursorState.Data

    /// 照準矢印スプライトのテクスチャ名（上向きに描かれている前提）。`RenderWorld.renderArrowCursor` が使う。
    pub def texture(): String = "arrow"
    /// 照準矢印スプライトの拡大率。
    pub def spriteScale(): Vec2.Vec2 = {x = 1.625, y = 1.625}
    /// 照準矢印の描画 zIndex。
    pub def spriteZIndex(): Int32 = 20

    /// 各方向の回転角（ラジアン）。矢印テクスチャは **上向き** に描かれている前提。
    ///   - Up    →   0°
    ///   - Right →  90°
    ///   - Down  → 180°
    ///   - Left  → 270° (= -90°)
    /// `RenderWorld.renderArrowCursor` がスプライトの回転として使う。
    pub def rotationOf(direction: Staff.Direction): Float64 = match direction {
        case Staff.Direction.Up    => 0.0
        case Staff.Direction.Right => 1.5707963267948966
        case Staff.Direction.Down  => 3.141592653589793
        case Staff.Direction.Left  => -1.5707963267948966
    }

    /// anchor から direction だけ進めた隣接セル。
    /// `Staff.toVec2i` と同等の計算だが、`gridPos` への代入前に cell 値を名前付きで保持できるよう
    /// 関数として独立させている。
    def cellOf(anchor: {x = Int32, y = Int32},
                direction: Staff.Direction): {x = Int32, y = Int32} =
        let offset = Staff.toVec2i(direction);
        {x = anchor#x + offset#x, y = anchor#y + offset#y}

    /// 照準状態を初期化する。ノードは持たないため scene はそのまま返す。
    /// add 直後は anchor/gridPos が未設定のため、StaffAim 開始前に必ず `showFor` を呼ぶこと。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ ArrowCursorState.State =
        ArrowCursorState.State.put(ArrowCursorState.initial());
        scene

    /// `StaffAim` に入った瞬間に呼ぶ。`anchor` をプレイヤー位置に、`direction` を Up に
    /// セットし、矢印を player の上隣接マスに置く。
    pub def showFor(playerCell: {x = Int32, y = Int32},
                      scene: Scene[NodeTag]): Scene[NodeTag] \ ArrowCursorState.State =
        putState(playerCell, Staff.Direction.Up, scene)

    /// StaffAim 中に方向キーを受けるたびに呼ぶ。`showFor` で固定された `anchor` は変えず、
    /// `direction` と矢印の指すセルだけを更新する。
    pub def aim(direction: Staff.Direction,
                  scene: Scene[NodeTag]): Scene[NodeTag] \ ArrowCursorState.State =
        let anchor = ArrowCursorState.State.get()#anchor;
        putState(anchor, direction, scene)

    /// 現在指している direction を取り出す。発射確定時（Z キー押下後）に呼び出し元が方向を取得するために公開している。
    pub def getDirection(): Staff.Direction \ ArrowCursorState.State =
        ArrowCursorState.State.get()#direction

    /// resource の Data を新しい anchor / direction / gridPos で書き換える（描画はしない）。
    def putState(anchor: {x = Int32, y = Int32},
                   direction: Staff.Direction,
                   scene: Scene[NodeTag]): Scene[NodeTag] \ ArrowCursorState.State =
        ArrowCursorState.State.put({anchor = anchor, direction = direction,
                                    gridPos = cellOf(anchor, direction)});
        scene
}
