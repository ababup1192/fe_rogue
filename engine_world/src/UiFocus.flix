// UiFocus — マウス座標の下にある一番手前の UI 要素を見つけて返す。
// クリックやホバーがどの要素に当たったかを一箇所で判定できるので、各所で当たり判定を書かずに済む。
// 利用例: ボタンのクリック先を決める / ホバー中の項目を知る / メニューを掴んでいるか調べる。
// 注意: 当たった要素を返すだけ。当たった後にどう反応するか（キー入力の宛先など）はゲーム側の仕事。

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
