// UiWidget — UI 要素の「見た目の中身」（箱・文字・スプライト）を表す属性と、その操作。
// 色や文字といった描画パラメタだけを持たせ、位置や大きさは持たないので、配置は UiLayout に任せられる。
// 利用例: 項目の背景色を決める / ラベルの文字を差し替える / アイコン画像を指定する。

mod UiWidget {

    /// 単色塗り矩形の描画属性。サイズは layout が決める。
    /// `color`: 塗り色。`alpha`: 不透明度。`zIndex`: 重なり順。
    /// `cornerRadius`: 角丸半径（px、既定 0.0=角丸なし）。
    /// `borderWidth`: 枠線幅（px、既定 0.0=枠なし）。`borderColor`: 枠線色（既定 白）。
    pub type alias BoxComp = { color = Color, alpha = Float32, zIndex = Int32,
                               cornerRadius = Float64, borderWidth = Float64, borderColor = Color }

    /// テキストの描画属性。
    /// `text`: 表示文字列。`font`: フォント名（atlas 引き当てキー）。`fontSize`: 表示サイズ。
    /// `tint`: 文字色。`zIndex`: 重なり順。
    pub type alias TextComp = { text = String, font = String, fontSize = Float64, tint = Color, zIndex = Int32 }

    /// スプライトの描画属性。
    /// `texture`: テクスチャ名。`regionRect`: アトラス切り出し矩形（None で全体）。
    /// `scale`: 拡大率。`flipH`/`flipV`: 反転。`tint`: 着色。`zIndex`: 重なり順。
    /// `hframes`/`vframes`: スプライトシートの格子分割（列数/行数、既定 1/1）。
    /// `frame`: 表示セル index = row * hframes + col（既定 0）。regionRect=None かつ
    /// hframes*vframes>1 のとき extract が frame からセル矩形を導く（engine Sprite と同じ規則）。
    pub type alias SpriteComp = { texture = String, regionRect = Option[Rect2.Rect2],
                                  scale = Vec2.Vec2, flipH = Bool, flipV = Bool, tint = Color, zIndex = Int32,
                                  hframes = Int32, vframes = Int32, frame = Int32 }

    /// 塗り潰し凸多角形（の集合）の描画属性。サイズは layout が決め、頂点はその矩形内へ置く。
    /// `polys`: 凸サブポリゴンの列。各サブポリは頂点列（ノードのレイアウト矩形左上を原点とする
    ///   ローカル design px・3 点以上・凸）で、1 サブポリ = 1 PolygonRenderCmd として塗る。
    ///   レンダラは GL_TRIANGLE_FAN（凸前提）なので、凹形状は凸単位に割った複数サブポリで表す
    ///   （中空リング＝アヌラスは外周 2 点＋内周 2 点の凸クアッド列など）。単純な三角形は 1 要素。
    /// `color`: 塗り色。`alpha`: 不透明度。`zIndex`: 重なり順（全サブポリ共通）。
    pub type alias PolyComp = { polys = List[List[Vec2.Vec2]], color = Color, alpha = Float32, zIndex = Int32 }

    /// リスト選択カーソルを delta だけ動かす（端で反対側へ回り込む）。
    /// count<=0 は選択肢が無いので 0 を返す。
    /// 例: count=3 のとき 2 から +1 で 0、0 から -1 で 2。
    pub def selectionMove(count: Int32, delta: Int32, current: Int32): Int32 =
        if (count <= 0) 0
        else {
            let raw = Int32.modulo(current + delta, count);
            if (raw < 0) raw + count else raw
        }

    /// disabled 項目を飛ばしてカーソルを 1 つ動かす（端で反対側へ回り込む）。
    /// `delta` は向き（<0 で上／>0 で下、大きさは無視）。`disabledAt(i)` が true の index は
    /// 選べないので飛ばす。移動方向に選べる項目が 1 つも無ければ（全 disabled 含む）`current`
    /// を保つ。count<=0 は選択肢が無いので 0。
    /// 例: count=4 で index1・2 が disabled のとき、0 から +1 で 3、3 から -1 で 0。
    pub def selectionMoveSkipping(count: Int32, delta: Int32, current: Int32, disabledAt: Int32 -> Bool): Int32 =
        if (count <= 0) 0
        else {
            // step は +1 方向へ正規化（-1 は count-1 ≡ -1 mod count で表す→負 modulo を避ける）。
            let step = if (delta < 0) count - 1 else 1;
            skipFrom(count, step, current, current, disabledAt, count)
        }

    /// `cursor` から step 方向へ最大 budget 回進み、最初に見つかる非 disabled の index を返す。
    /// budget を使い切ったら（全て disabled で移動先が無い）`original` を返す。
    def skipFrom(count: Int32, step: Int32, cursor: Int32, original: Int32,
                 disabledAt: Int32 -> Bool, budget: Int32): Int32 =
        if (budget <= 0) original
        else {
            let next = Int32.modulo(cursor + step, count);
            if (not disabledAt(next)) next
            else skipFrom(count, step, next, original, disabledAt, budget - 1)
        }
}
