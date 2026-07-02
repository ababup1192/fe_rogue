/// ArrowCursorScene — 杖発射の方向を視覚化する矢印カーソル
///
/// `StaffAim` フェーズだけ visible になり、選択中プレイヤーの隣接 4 セルの
/// いずれか（現在指している `direction` 側）に矢印スプライトを置く。方向キー
/// を押すと向きが切り替わり、Z で発射、X / Esc でキャンセル。
///
/// ノード構造（CursorScene と並列のトップレベル）:
///   ArrowCursor (Marker2D, NodeTag.ArrowCursor)
///     └─ Sprite (Sprite2D, arrow.png)
///
/// 親 Marker2D の `position` で隣接マスを指し、子 Sprite の `rotation` で矢の向きを表す
/// （arrow.png は上向きに描かれている前提）。論理状態（anchor/direction/gridPos）は
/// `ArrowCursorState.State` resource が権威で、ノードは識別用のペイロードレスタグだけ持つ。
mod ArrowCursorScene {

    /// 矢印カーソルの論理状態。resource 側の型に委譲する。
    pub type alias Data = ArrowCursorState.Data

    def name(): String = "ArrowCursor"
    pub def arrowPath():  NodePath = name() :: Nil
    def spriteName(): String = "Sprite"
    pub def spritePath(): NodePath = name() :: spriteName() :: Nil

    def scenePath(): String = AssetPath.resolve("src/scenes/ArrowCursorScene.scene.json")

    /// 各方向の回転角（ラジアン）。arrow.png は **上向き** に描かれている前提。
    ///   - Up    →   0°
    ///   - Right →  90°
    ///   - Down  → 180°
    ///   - Left  → 270° (= -90°)
    def rotationOf(direction: Staff.Direction): Float64 = match direction {
        case Staff.Direction.Up    => 0.0
        case Staff.Direction.Right => 1.5707963267948966
        case Staff.Direction.Down  => 3.141592653589793
        case Staff.Direction.Left  => -1.5707963267948966
    }

    /// anchor から direction だけ進めた隣接セル。
    /// `Staff.toVec2i` と同等の計算だが、`gridPos` への代入前に cell 値を名前付きで保持できるよう、
    /// また `rotationOf` と対称に関数として独立させている。
    def cellOf(anchor: {x = Int32, y = Int32},
                direction: Staff.Direction): {x = Int32, y = Int32} =
        let offset = Staff.toVec2i(direction);
        {x = anchor#x + offset#x, y = anchor#y + offset#y}

    /// scene に矢印カーソルを追加する。初期は非表示 (visible は scene.json 側で false)。
    /// add 直後は anchor/gridPos が未設定のため、StaffAim 開始前に必ず `showFor` を呼ぶこと。
    pub def add(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead, ArrowCursorState.State} =
        ArrowCursorState.State.put(ArrowCursorState.initial());
        SceneLoader.loadScene(scenePath(),
                              SceneLoader.constTagParser(NodeTag.NoTag),
                              scene)
            |> Scene.setState(arrowPath(), NodeTag.ArrowCursor)

    /// フェーズが `StaffAim` のときだけ visible にし、それ以外では hidden にする。
    /// 実質的な描画更新（位置・回転）は `StaffAim` 開始時の `showFor` と方向キー毎の `aim` が担い、
    /// ここでは visibility 切替のみ行う（`showFor` / `aim` で設定済みの値を毎フレーム上書きしない）。
    /// gameLoop が 1 回呼ぶ frame-paced System。
    pub def step(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        applyVisibility(TurnPhase.State.get(), scene)

    /// `StaffAim` 中だけ親 Marker2D + 子 Sprite を visible にする。
    pub def applyVisibility(phase: TurnPhase.Phase,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.StaffAim or phase == TurnPhase.Phase.ThrowAim;
        scene
            |> Marker2D.mapAt(arrowPath(), CanvasItem.setVisible(visible))
            |> Sprite2D.mapAt(spritePath(), CanvasItem.setVisible(visible))

    /// `StaffAim` に入った瞬間に呼ぶ。`anchor` をプレイヤー位置に、`direction` を Up に
    /// セットし、矢印を player の上隣接マスに表示する。
    pub def showFor(playerCell: {x = Int32, y = Int32},
                      scene: Scene[NodeTag]): Scene[NodeTag] \ ArrowCursorState.State =
        setPositionAndRotation(playerCell, Staff.Direction.Up, scene)

    /// StaffAim 中に方向キーを受けるたびに呼ぶ。`showFor` で固定された `anchor` は変えず、
    /// `direction` と矢印の表示位置だけを更新する。
    pub def aim(direction: Staff.Direction,
                  scene: Scene[NodeTag]): Scene[NodeTag] \ ArrowCursorState.State =
        let anchor = ArrowCursorState.State.get()#anchor;
        setPositionAndRotation(anchor, direction, scene)

    /// 現在指している direction を取り出す。発射確定時（Z キー押下後）に呼び出し元が方向を取得するために公開している。
    pub def getDirection(): Staff.Direction \ ArrowCursorState.State =
        ArrowCursorState.State.get()#direction

    /// 親 Marker2D の位置と子 Sprite の回転を direction に合わせて更新し、
    /// resource の Data も新しい anchor / direction / gridPos で書き換える。
    def setPositionAndRotation(anchor: {x = Int32, y = Int32},
                                 direction: Staff.Direction,
                                 scene: Scene[NodeTag]): Scene[NodeTag] \ ArrowCursorState.State =
        let cell = cellOf(anchor, direction);
        let world = MapSnapshot.cellCenter(cell);
        let rotation = rotationOf(direction);
        ArrowCursorState.State.put({anchor = anchor, direction = direction, gridPos = cell});
        scene
            |> Marker2D.mapAt(arrowPath(), Node2D.setPosition(world))
            |> Sprite2D.mapAt(spritePath(), Node2D.setRotation(rotation))
}
