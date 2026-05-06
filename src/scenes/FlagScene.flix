/// FlagScene — PlayerAutoMove の目印として立てる旗ノード
///
/// FE 風の「自動移動先マーカー」。空マスでカーソル決定すると `plant` で立ち、
/// 自動移動が終わると `clear` で消える。
///
/// ノード構造（Cursor と並列のトップレベル）:
///   Flag (Marker2D, NodeTag.Flag(Data))
///     └─ Sprite (Sprite2D, flag.png)
///
/// 設計:
///   - 親 Marker2D に位置と planted フラグを持たせる
///   - 立てていない間は親 Marker2D を invisible にする（add 直後・clear 後）
///   - planted = false の時は `getTargetPos` が None を返すので、AutoMove が
///     空回りせずフェーズを抜ける防御に使える
mod FlagScene {

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// `gridPos`: 旗を立てたグリッド座標（planted = false のときは未使用）
    /// `planted`: 旗が立っているか。false の時は描画されず、`getTargetPos` も None を返す
    pub type alias Data = {
        gridPos = Vec2.Vec2i,
        planted = Bool
    }

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def name(): String = "Flag"
    pub def flagPath(): NodePath = name() :: Nil
    def spriteName(): String = "Sprite"

    /// `flag.png` テクスチャ名（Main.flix の textureManifest と整合）
    def textureName(): String = "flag"

    /// LDTK タイルサイズ（ピクセル）。MapScene と揃える
    def tileSize(): Float64 = 16.0

    /// 旗の描画 zIndex。床より上、味方/敵 (= 10) よりは下。
    /// 駒の上に被る位置に立てた場合でも駒が前面に表示される。
    def spriteZIndex(): Int32 = 5

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// MapScene 登録済みの scene に旗ノードを追加する。
    /// 初期は planted = false（非表示）。`plant` を呼んで初めて表示される。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let initial: Vec2.Vec2i = {x = 0, y = 0};
        let pos = cellCenter(initial);
        let marker = Marker2D.make(pos)
                        |> CanvasItem.setVisible(false);
        let sprite = Sprite2D.make(textureName(), Vec2.zero(), Vec2.one())
                        |> CanvasItem.setZIndex(spriteZIndex());
        let data: Data = {gridPos = initial, planted = false};
        scene
            |> Scene.addNode(name(),
                              EngineNode.Marker2DWithState(marker, NodeTag.Flag(data)))
            |> Scene.addChild(name(), spriteName(),
                               EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// `target` セルに旗を立てる。位置を更新して可視化する。
    /// 既に立っていた場合は新しい位置に「立て直す」。
    pub def plant(target: Vec2.Vec2i, scene: Scene[NodeTag]): Scene[NodeTag] =
        let world = cellCenter(target);
        scene
            |> Scene.setGlobalPositionAt(flagPath(), world)
            |> mapFlag((m, _) ->
                (CanvasItem.setVisible(true, m),
                 ({gridPos = target, planted = true}: Data)))

    /// 旗を消す（不可視 + planted = false）。AutoMove 終了時に呼ぶ。
    pub def clear(scene: Scene[NodeTag]): Scene[NodeTag] =
        mapFlag((m, d) ->
            (CanvasItem.setVisible(false, m),
             ({planted = false | d}: Data)),
            scene)

    /// 旗の現在のターゲット位置。立っていなければ None。
    pub def getTargetPos(scene: Scene[NodeTag]): Option[Vec2.Vec2i] =
        match Scene.getState(flagPath(), scene) {
            case Some(NodeTag.Flag(d)) =>
                if (d#planted) Some(d#gridPos) else None
            case _ => None
        }

    /// 旗が立っているか。
    pub def isPlanted(scene: Scene[NodeTag]): Bool =
        match Scene.getState(flagPath(), scene) {
            case Some(NodeTag.Flag(d)) => d#planted
            case _ => false
        }

    // ────────────────────────────────────────────────────────
    // (E) ボイラプレート
    // ────────────────────────────────────────────────────────

    /// Flag の Marker2D + Data をまとめて変換する。
    def mapFlag(f: (Marker2D, Data) -> (Marker2D, Data),
                 scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(flagPath(), engineNode -> match engineNode {
            case EngineNode.Marker2DWithState(marker, NodeTag.Flag(data)) =>
                let (newMarker, newData) = f(marker, data);
                EngineNode.Marker2DWithState(newMarker, NodeTag.Flag(newData))
            case other => other
        }, scene)

    /// グリッド座標 → セル中心ピクセル座標。MapScene の `mapToLocal` 慣習に揃える。
    def cellCenter(cell: Vec2.Vec2i): Vec2.Vec2 =
        let s = tileSize();
        let v = Vec2.fromI(cell);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}
}
