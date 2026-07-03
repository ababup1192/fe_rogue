// UiWidget — 描画コンポーネントと挙動純関数
//
// Bevy の細粒度 component 群に相当。ノードは box / text / sprite のいずれかの描画属性を持つ。
// サイズと位置は UiLayout が決めるため、ここには持たない（見た目のパラメタだけ）。

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
    /// hframes*vframes>1 のとき extract が frame からセル矩形を導く（engine Sprite2D と同じ規則）。
    pub type alias SpriteComp = { texture = String, regionRect = Option[Rect2.Rect2],
                                  scale = Vec2.Vec2, flipH = Bool, flipV = Bool, tint = Color, zIndex = Int32,
                                  hframes = Int32, vframes = Int32, frame = Int32 }

    /// 塗り潰し凸多角形の描画属性。サイズは layout が決め、頂点はその矩形内へ置く。
    /// `points`: 頂点列。ノードのレイアウト矩形左上を原点とするローカル design px（3 点以上）。
    /// `color`: 塗り色。`alpha`: 不透明度。`zIndex`: 重なり順。
    pub type alias PolyComp = { points = List[Vec2.Vec2], color = Color, alpha = Float32, zIndex = Int32 }

    /// リスト選択カーソルを delta だけ動かす（端で反対側へ回り込む）。
    /// count<=0 は選択肢が無いので 0 を返す。
    /// 例: count=3 のとき 2 から +1 で 0、0 から -1 で 2。
    pub def selectionMove(count: Int32, delta: Int32, current: Int32): Int32 =
        if (count <= 0) 0
        else {
            let raw = Int32.modulo(current + delta, count);
            if (raw < 0) raw + count else raw
        }
}
