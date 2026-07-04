// TextDraw — 文字列を、左端ではなく「中心をここに置きたい」で配置する。
// 幅を測って半分だけ左へずらす手間を一度だけ名付けるので、文字を中央に揃えるたびに
// 同じ計算を書かずに済む。
// 利用例: 盤の上のタイトル / アイコンの下のラベル / 画面中央の見出し。

mod TextDraw {

    /// `centered` の引数一式。並べると順序を誤りやすい値を名前で束ねるための入れ物
    /// （centerX に中心を合わせ、y を一行の上端にする）。
    pub type alias Centered = { text = String, atlas = FontAtlas, size = Float64,
                                color = Color, z = Int32, centerX = Float64, y = Float64 }

    /// 一行が `centerX` に水平中央で揃い、上端が `y` になるよう配置したテキスト描画
    /// アイテム。左上の描画位置と tint 済みテキストアイテムの組を返し、そのまま描画
    /// リストへ追加できる。幅は与えた atlas 上の `text` を `size` で測るため、プロポー
    /// ショナルフォントでも正しく中央に来る。
    pub def centered(a: Centered): (Vec2.Vec2, Render.RenderItem) =
        let width = Label2D.measure(Label2D.make(a#text, a#atlas, a#size))#x;
        ({ x = a#centerX - width / 2.0, y = a#y }, Render.textTinted(a#text, a#atlas, a#size, a#color, a#z))
}
