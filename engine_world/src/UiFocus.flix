// UiFocus — ポインタ hit-test（完全純粋）
//
// マウス座標が乗っている最前面の UI entity を返す。フォーカス scope の判定に使う。
// キールーティング規約（実装は Game 側 dispatch）: focus=Some(path) の間、方向キーや Z/X は
// その path の widget だけに届く（モーダル占有）。ここは「どの entity に当たったか」だけを解く。

mod UiFocus {

    /// `hitTest` が当たり判定に使う対象シーンの記述。
    /// `rects`: 各 entity の画面矩形。`vis`: 各 entity の可視（未登録は可視扱い）。
    /// `zOf`/`depthOf`: entity → zIndex / 階層深さ（最前面判定に使う）。
    pub type alias HitTestScene = {
        rects   = Map[EntityId, Rect2.Rect2],
        vis     = Map[EntityId, Bool],
        zOf     = EntityId -> Int32,
        depthOf = EntityId -> Int32
    }

    /// point を含む可視 entity のうち最前面のものを返す。
    /// 最前面判定は (zIndex, 階層深さ, id) の大きい方を優先する（z 同値なら深い方、深さも同値なら id 大）。
    /// vis 未登録の entity は可視扱い。当たりが無ければ None。
    pub def hitTest(scene: HitTestScene, point: Vec2.Vec2): Option[EntityId] =
        scene#rects |> Map.foldLeftWithKey((best, id, rect) ->
            if (Rect2.hasPoint(point, rect) and Option.getWithDefault(true, Map.get(id, scene#vis)))
                betterHit(best, id, scene#zOf, scene#depthOf)
            else best,
            None)

    /// 既存の当たり best と候補 candidate を比べ、(zIndex, 深さ, id) が大きい方を残す。
    def betterHit(best: Option[EntityId], candidate: EntityId,
                  zOf: EntityId -> Int32, depthOf: EntityId -> Int32): Option[EntityId] =
        match best {
            case None => Some(candidate)
            case Some(current) =>
                let currentKey = (zOf(current), depthOf(current), current);
                let candidateKey = (zOf(candidate), depthOf(candidate), candidate);
                if (candidateKey > currentKey) Some(candidate) else Some(current)
        }
}
