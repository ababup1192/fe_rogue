/// ArrowCursorScene — 杖発射の方向を視覚化する矢印カーソル
///
/// `StaffAim` フェーズだけ visible になり、選択中プレイヤーの隣接 4 セルの
/// いずれか（現在指している `direction` 側）に矢印スプライトを置く。方向キー
/// を押すと向きが切り替わり、Z で発射、X / Esc でキャンセル。
///
/// ノード構造（CursorScene と並列のトップレベル）:
///   ArrowCursor (Marker2D, NodeTag.ArrowCursor(Data))
///     └─ Sprite (Sprite2D, arrow.png)
///
/// 親 Marker2D の `position` で隣接マスを指し、子 Sprite の `rotation` で矢の向きを表す
/// （arrow.png は上向きに描かれている前提）。
mod ArrowCursorScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 矢印カーソルの状態。
    /// `anchor` は選択中プレイヤーの位置（隣接 4 マスの中心）。
    /// `direction` は現在の発射方向。
    /// `gridPos` は anchor から direction だけ進めた隣接セル（= 矢印の論理位置）。
    pub type alias Data = {
        anchor    = {x = Int32, y = Int32},
        direction = Staff.Direction,
        gridPos   = {x = Int32, y = Int32}
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

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

    /// anchor から direction だけ進めた隣接セル。`Staff.toVec2i` と等価だがログ目的で残す。
    def cellOf(anchor: {x = Int32, y = Int32},
                direction: Staff.Direction): {x = Int32, y = Int32} =
        let offset = Staff.toVec2i(direction);
        {x = anchor#x + offset#x, y = anchor#y + offset#y}

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// scene に矢印カーソルを追加する。初期は非表示 (visible は scene.json 側で false)。
    /// `anchor` は (0, 0) で初期化し、`showFor` で正しい位置に動かす。
    pub def add(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let data: Data = {
            anchor    = {x = 0, y = 0},
            direction = Staff.Direction.Up,
            gridPos   = {x = 0, y = 0}
        };
        SceneLoader.loadScene(scenePath(),
                              SceneLoader.constTagParser(NodeTag.NoTag),
                              scene)
            |> Scene.setState(arrowPath(), NodeTag.ArrowCursor(data))

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// 毎フレーム呼ばれる process（Game.flix の dispatch から）。
    /// フェーズが `StaffAim` のときだけ visible にし、それ以外では hidden。
    /// 位置・回転は `showFor` / `aim` が呼ばれた時点で設定済みなので、ここでは触らない。
    pub def process(_delta: Duration.Duration, node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ TurnPhase.State =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        match Scene.getEngineNode(arrowPath(), withVisibility) {
            case Some(latest) => (latest, withVisibility)
            case None         => (node, withVisibility)
        }

    /// `StaffAim` 中だけ親 Marker2D + 子 Sprite を visible にする。
    pub def applyVisibility(phase: TurnPhase.Phase,
                              scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.StaffAim;
        scene
            |> Scene.mapEngineNode(arrowPath(), n -> match n {
                case EngineNode.Marker2DWithState(marker, st) =>
                    EngineNode.Marker2DWithState(
                        CanvasItem.setVisible(visible, marker), st)
                case other => other
            })
            |> Sprite2D.mapAt(spritePath(), CanvasItem.setVisible(visible))

    /// `StaffAim` に入った瞬間に呼ぶ。`anchor` をプレイヤー位置に、`direction` を Up に
    /// セットし、矢印を player の上隣接マスに表示する。
    pub def showFor(playerCell: {x = Int32, y = Int32},
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        setPositionAndRotation(playerCell, Staff.Direction.Up, scene)

    /// 方向キー押下で矢印の向きを変える。`anchor` は変えず direction だけ更新。
    pub def aim(direction: Staff.Direction,
                  scene: Scene[NodeTag]): Scene[NodeTag] =
        let anchor = getData(scene)#anchor;
        setPositionAndRotation(anchor, direction, scene)

    /// 現在指している direction を取り出す。`applyStaffCast` の発射方向に使う。
    pub def getDirection(scene: Scene[NodeTag]): Staff.Direction =
        getData(scene)#direction

    /// 矢印の Data を取り出す（無ければデフォルト値で safe-default）。
    def getData(scene: Scene[NodeTag]): Data =
        match Scene.getState(arrowPath(), scene) {
            case Some(NodeTag.ArrowCursor(data)) => data
            case _ =>
                ({anchor = {x = 0, y = 0}, direction = Staff.Direction.Up,
                  gridPos = {x = 0, y = 0}}: Data)
        }

    /// 親 Marker2D の位置と子 Sprite の回転を direction に合わせて更新し、
    /// `Data` も新しい anchor / direction / gridPos で書き換える。
    def setPositionAndRotation(anchor: {x = Int32, y = Int32},
                                 direction: Staff.Direction,
                                 scene: Scene[NodeTag]): Scene[NodeTag] =
        let cell = cellOf(anchor, direction);
        let world = MapSnapshot.cellCenter(cell);
        let rotation = rotationOf(direction);
        let nextData: Data = {anchor = anchor, direction = direction, gridPos = cell};
        scene
            |> Scene.mapEngineNode(arrowPath(), n -> match n {
                case EngineNode.Marker2DWithState(marker, _) =>
                    EngineNode.Marker2DWithState(
                        Node2D.setPosition(world, marker),
                        NodeTag.ArrowCursor(nextData))
                case other => other
            })
            |> Sprite2D.mapAt(spritePath(), Node2D.setRotation(rotation))
}
