// TextDraw — 文字列を、左端ではなく「中心をここに置きたい」で配置する。
// 幅を測って半分だけ左へずらす手間を一度だけ名付けるので、文字を中央に揃えるたびに
// 同じ計算を書かずに済む。
// 利用例: 盤の上のタイトル / アイコンの下のラベル / 画面中央の見出し。

mod TextDraw {

    /// `centered` の引数一式。並べると順序を誤りやすい値を名前で束ねるための入れ物
    /// （centerX に中心を合わせ、y を一行の上端にする）。
    pub type alias Centered = { text = String, atlas = FontAtlas, size = Float64,
                                color = Color, z = Int32, centerX = Float64, y = Float64 }

    /// 与えた atlas 上で `text` を `size` で描いたときの横幅（ピクセル）。プロポーショナル
    /// フォントも字ごとの送り幅で正しく測る。描画までは要らず幅だけ欲しい配置計算に使う。
    pub def width(text: String, atlas: FontAtlas, size: Float64): Float64 =
        Text.measure(Text.make(text, atlas, size))#x

    /// 与えた atlas 上で `text` を `size` で描いたときの幅と高さ（ピクセル、Vec2）。
    /// `width` が横だけ返すのに対し、縦の位置合わせ（中央そろえ・下端そろえ）に要る高さも
    /// まとめて返す。描画までは要らず寸法だけ欲しい配置計算に使う。
    pub def size(text: String, atlas: FontAtlas, size: Float64): Vec2.Vec2 =
        Text.measure(Text.make(text, atlas, size))

    /// `text` を `centerX` に水平中央で揃えたときの左端 x。中央寄せは「幅の半分だけ左へ
    /// ずらす」だけなので、それを名付けて返す。描画アイテムを作らず座標だけ欲しい宣言 UI
    /// （setAbs 系で位置を渡す）から呼べる。
    pub def centerLeft(text: String, atlas: FontAtlas, size: Float64, centerX: Float64): Float64 =
        centerX - width(text, atlas, size) / 2.0

    /// 一行が `centerX` に水平中央で揃い、上端が `y` になるよう配置したテキスト描画
    /// アイテム。左上の描画位置と tint 済みテキストアイテムの組を返し、そのまま描画
    /// リストへ追加できる。左端 x は `centerLeft`、幅は `width` に一致する。
    pub def centered(a: Centered): Render.Placed =
        ({ x = centerLeft(a#text, a#atlas, a#size, a#centerX), y = a#y },
         Render.textTinted(a#text, a#atlas, a#size, a#color, a#z))
}
