// Items — 4方向に出る品物アイコンの手続き描画。16 ユニットのグリッドに描き、
// 要求サイズでスケールされる（UI のスロットにもギャラリーの一覧にも同じ関数を使う）。
mod Items {

    /// 品物の種類。前半 = 持ち場に対応する正解系、後半 = ネタ系ハズレ。
    pub enum Kind with Eq, Order, ToString {
        case Flour      // 小麦粉の袋（ボール）
        case Egg        // たまご（ボール）
        case Sugar      // さとうの瓶（ボール）
        case Butter     // バター（ボール）
        case Milk       // ぎゅうにゅう（ボール）
        case StarCutter // 星の抜き型（型抜き）
        case HeartCutter// ハートの抜き型（型抜き）
        case Tray       // 天板（オーブン）
        case Mitten     // ミトン（オーブン）
        case Fish       // さかな（ネタ）
        case Soap       // せっけん（ネタ）
        case Boot       // ながぐつ（ネタ）
    }

    pub def allKinds(): List[Kind] =
        Kind.Flour :: Kind.Egg :: Kind.Sugar :: Kind.Butter :: Kind.Milk ::
        Kind.StarCutter :: Kind.HeartCutter :: Kind.Tray :: Kind.Mitten ::
        Kind.Fish :: Kind.Soap :: Kind.Boot :: Nil

    /// 表示名（ギャラリーのラベル・後でゲームの読み上げにも）。
    pub def nameOf(kind: Kind): String = match kind {
        case Kind.Flour       => "こむぎこ"
        case Kind.Egg         => "たまご"
        case Kind.Sugar       => "さとう"
        case Kind.Butter      => "バター"
        case Kind.Milk        => "ぎゅうにゅう"
        case Kind.StarCutter  => "ほしの型"
        case Kind.HeartCutter => "ハートの型"
        case Kind.Tray        => "てんばん"
        case Kind.Mitten      => "ミトン"
        case Kind.Fish        => "さかな"
        case Kind.Soap        => "せっけん"
        case Kind.Boot        => "ながぐつ"
    }

    /// `center` を中心に `size` px でアイコン一式を返す（角丸ボックス + 曲線 + 文字の混成）。
    pub def icon(kind: Kind, center: Vec2.Vec2, size: Float64, atlas: FontAtlas): List[Render.PlacedItem] =
        let s = size / 16.0;
        let tl = { x = center#x - size / 2.0, y = center#y - size / 2.0 };
        let gp = p -> ({ x = tl#x + fst(p) * s, y = tl#y + snd(p) * s }: Vec2.Vec2);
        List.flatten(
            (parts(kind) |> List.map(toItem(center, size))) ::
            curves(kind, gp, s) ::
            letters(kind, gp, s, atlas) :: Nil)

    /// 文字で意味を補強する品物（牛乳パックの MILK ロゴ）。
    def letters(kind: Kind, gp: ((Float64, Float64)) -> Vec2.Vec2, s: Float64,
                atlas: FontAtlas): List[Render.PlacedItem] =
        match kind {
            case Kind.Milk =>
                { at = gp((4.8, 7.8)), item = Render.textTinted("MILK", atlas, 3.1 * s, Palette.milkCap(), 3) } :: Nil
            case _ => Nil
        }

    /// 曲線でしか描けないぶん（卵の楕円・魚の尾・ハートと星の本体）。
    def curves(kind: Kind, gp: ((Float64, Float64)) -> Vec2.Vec2, s: Float64): List[Render.PlacedItem] =
        match kind {
            case Kind.Egg =>
                List.append(
                    Bezier.convexFill(Bezier.ellipse(gp((8.0, 8.0)), 4.2 * s, 5.4 * s, 18),
                        Palette.eggShell(), 1),
                    Bezier.convexFill(Bezier.ellipse(gp((6.6, 5.8)), 1.2 * s, 1.6 * s, 10),
                        Palette.paperShade(), 2))
            case Kind.Fish =>
                // 定番の魚アイコン: 横長の楕円の体 + 二叉の尾 + 小さな背びれ +
                // 体の中の胸びれ + 点の目と小さな口。
                List.flatten(
                    Bezier.convexFill(Bezier.ellipse(gp((7.0, 8.5)), 4.3 * s, 2.6 * s, 18),
                        Palette.fish(), 1) ::
                    Bezier.convexFill(gp((10.9, 8.5)) :: gp((14.0, 6.6)) :: gp((13.5, 8.5)) :: Nil,
                        Palette.fish(), 1) ::
                    Bezier.convexFill(gp((10.9, 8.5)) :: gp((14.0, 10.4)) :: gp((13.5, 8.5)) :: Nil,
                        Palette.fish(), 1) ::
                    Bezier.convexFill(gp((6.0, 6.3)) :: gp((7.5, 4.7)) :: gp((8.9, 6.4)) :: Nil,
                        Palette.fish(), 1) ::
                    Bezier.convexFill(gp((6.4, 8.7)) :: gp((7.9, 9.7)) :: gp((8.1, 8.5)) :: Nil,
                        Palette.fishTail(), 2) ::
                    Bezier.convexFill(Bezier.ellipse(gp((4.5, 7.9)), 0.55 * s, 0.55 * s, 8),
                        Palette.hudBg(), 2) ::
                    Bezier.convexFill(Bezier.ellipse(gp((4.35, 7.75)), 0.18 * s, 0.18 * s, 6),
                        Palette.paper(), 3) ::
                    Bezier.convexFill(Bezier.ellipse(gp((2.9, 9.1)), 0.32 * s, 0.32 * s, 6),
                        Palette.fishTail(), 2) :: Nil)
            case Kind.HeartCutter =>
                // 抜き型 = 真ん中が空洞のリング。ハート曲線を閉ループのストロークでなぞる。
                strokeLoop(heartOutline(gp, 8.0, 7.6, 0.33), 1.15 * s, Palette.heart(), 1)
            case Kind.StarCutter =>
                // 抜き型 = 星のリング。外側の星と、それを相似縮小した内側の星を
                // 辺ごとのクアッドで結ぶ（数式そのままの対称形。ストロークは使わない）。
                starRing(gp((8.0, 8.2)), 6.4 * s, 2.9 * s, 0.74, Palette.star(), 1)
            case Kind.Sugar =>
                // フタを開けた瓶から砂糖の山が見える + こぼれた粒。
                List.flatten(
                    Bezier.convexFill(sugarMound(gp, 8.0, 5.2, 3.2), Palette.paper(), 2) ::
                    Bezier.convexFill(Bezier.ellipse(gp((4.6, 3.6)), 0.5 * s, 0.5 * s, 8),
                        Palette.paper(), 2) ::
                    Bezier.convexFill(Bezier.ellipse(gp((11.6, 3.2)), 0.45 * s, 0.45 * s, 8),
                        Palette.paper(), 2) ::
                    Bezier.convexFill(Bezier.ellipse(gp((12.6, 5.4)), 0.4 * s, 0.4 * s, 8),
                        Palette.paper(), 2) :: Nil)
            case Kind.Soap =>
                // 定番の石鹸: 角丸のバー + 面取りのラベル楕円 + 上に浮かぶ泡 3 つ
                //（それぞれ左上にハイライトの点）。
                List.flatten(
                    Bezier.convexFill(Bezier.ellipse(gp((8.0, 10.2)), 5.4 * s, 2.6 * s, 18),
                        Palette.soap(), 1) ::
                    Bezier.convexFill(Bezier.ellipse(gp((8.0, 10.2)), 3.4 * s, 1.4 * s, 14),
                        Palette.dough(), 2) ::
                    bubble(gp, s, 10.6, 4.6, 1.9) ::
                    bubble(gp, s, 7.2, 3.0, 1.3) ::
                    bubble(gp, s, 12.9, 2.7, 0.9) :: Nil)
            case _ => Nil
        }

    /// 泡 1 つ（白い丸 + 左上のハイライト）。
    def bubble(gp: ((Float64, Float64)) -> Vec2.Vec2, s: Float64,
               cx: Float64, cy: Float64, r: Float64): List[Render.PlacedItem] =
        List.append(
            Bezier.convexFill(Bezier.ellipse(gp((cx, cy)), r * s, r * s, 12), Palette.paper(), 2),
            Bezier.convexFill(Bezier.ellipse(gp((cx - r * 0.35, cy - r * 0.35)), r * 0.28 * s,
                r * 0.28 * s, 8), Palette.milkCap(), 3))

    /// 星のリング（外側の星の各辺と、中心へ shrink 倍で縮めた内側の星を結ぶクアッド 10 枚）。
    def starRing(center: Vec2.Vec2, rOut: Float64, rIn: Float64, shrink: Float64,
                 color: Color, z: Int32): List[Render.PlacedItem] =
        let outer = List.toVector(Bezier.star(center, rOut = rOut, rIn = rIn));
        let inner = outer |> Vector.map(p ->
            ({ x = center#x + (p#x - center#x) * shrink,
               y = center#y + (p#y - center#y) * shrink }: Vec2.Vec2));
        List.range(0, 10) |> List.flatMap(i -> {
            let j = Int32.modulo(i + 1, 10);
            Bezier.convexFill(
                Vector.get(i, outer) :: Vector.get(j, outer) ::
                Vector.get(j, inner) :: Vector.get(i, inner) :: Nil, color, z)
        })

    /// 閉じた輪郭をぐるりとなぞる一定幅のリング（クッキーの抜き型用）。
    def strokeLoop(points: List[Vec2.Vec2], width: Float64, color: Color,
                   z: Int32): List[Render.PlacedItem] =
        Bezier.stroke({ spine = List.append(points, List.take(2, points)), color = color, z = z },
            _ -> width)

    /// ハート曲線（古典的なパラメトリックハート。k で大きさを調整）。
    def heartOutline(gp: ((Float64, Float64)) -> Vec2.Vec2, cx: Float64, cy: Float64,
                     k: Float64): List[Vec2.Vec2] =
        List.range(0, 24) |> List.map(i -> {
            let t = 6.283185307179586 * Int32.toFloat64(i) / 24.0;
            let sx = RenderUtil.sinF(t);
            let hx = 16.0 * sx * sx * sx * k;
            let hy = -1.0 * (13.0 * RenderUtil.cosF(t) - 5.0 * RenderUtil.cosF(2.0 * t)
                - 2.0 * RenderUtil.cosF(3.0 * t) - RenderUtil.cosF(4.0 * t)) * k;
            gp((cx + hx, cy + hy))
        })

    /// 瓶の口からのぞく砂糖の山（上向きの半円）。
    def sugarMound(gp: ((Float64, Float64)) -> Vec2.Vec2, cx: Float64, cy: Float64,
                   r: Float64): List[Vec2.Vec2] =
        List.range(0, 13) |> List.map(i -> {
            let a = 3.14159265 * Int32.toFloat64(i) / 12.0;
            gp((cx - r * RenderUtil.cosF(a), cy - r * 0.62 * RenderUtil.sinF(a)))
        })

    type alias Part = {
        x = Float64, y = Float64, w = Float64, h = Float64,
        r = Float64, color = Color, z = Int32
    }

    def parts(kind: Kind): List[Part] = match kind {
        case Kind.Flour =>
            // 四角い紙袋 + 折り返した口 + 茶色のラベル。
            rr(3.5, 3.5, 9.0, 10.5, 0.8, Palette.paper(), 1) ::
            rr(3.5, 3.5, 9.0, 2.2, 0.6, Palette.paperShade(), 2) ::
            rr(5.0, 7.6, 6.0, 3.4, 0.6, Palette.cookie(), 2) :: Nil
        case Kind.Egg => Nil  // 楕円は curves 側で描く
        case Kind.Sugar =>
            // フタ無しの瓶（口の縁だけ）。中身の山と粒は curves 側。
            rr(4.5, 5.5, 7.0, 8.0, 1.6, Palette.sugar(), 1) ::
            rr(4.0, 4.8, 8.0, 1.3, 0.6, Palette.metalDark(), 1) :: Nil
        case Kind.Butter =>
            rr(3.0, 6.0, 10.0, 6.0, 1.5, Palette.butter(), 1) ::
            rr(3.0, 6.0, 10.0, 2.0, 1.0, Palette.paper(), 2) :: Nil
        case Kind.Milk =>
            // 紙パック + 青い屋根。胴には MILK の文字（letters 側）。
            rr(4.5, 4.0, 7.0, 9.5, 1.2, Palette.milk(), 1) ::
            rr(4.5, 2.5, 7.0, 3.0, 1.2, Palette.milkCap(), 2) :: Nil
        case Kind.StarCutter => Nil   // 本物の 5 芒星を curves 側で描く
        case Kind.HeartCutter => Nil  // 丸 2 つ + 三角のハートを curves 側で描く
        case Kind.Tray =>
            // フチの立った焼き板 + 載っているクッキー 2 枚（=オーブン用とわかる）。
            rr(0.8, 4.2, 14.4, 8.2, 2.2, Palette.metalDark(), 1) ::
            rr(2.2, 5.6, 11.6, 5.4, 1.5, Palette.metal(), 2) ::
            rr(3.6, 6.6, 3.4, 3.4, 1.7, Palette.cookie(), 3) ::
            rr(8.8, 6.8, 3.4, 3.4, 1.7, Palette.cookie(), 3) :: Nil
        case Kind.Mitten =>
            rr(4.0, 3.5, 8.0, 8.0, 3.0, Palette.mitten(), 1) ::
            rr(2.5, 7.0, 4.0, 4.0, 2.0, Palette.mitten(), 1) ::
            rr(5.0, 11.0, 6.0, 3.0, 1.0, Palette.paper(), 2) :: Nil
        case Kind.Fish => Nil  // 楕円 + 三角の尾びれを curves 側で描く
        case Kind.Soap => Nil  // 曲線側で描く（バー + ラベル楕円 + 泡）
        case Kind.Boot =>
            rr(5.0, 2.5, 5.0, 9.0, 1.2, Palette.boot(), 1) ::
            rr(5.0, 9.5, 8.5, 4.0, 1.5, Palette.boot(), 1) ::
            rr(5.0, 12.0, 8.5, 1.5, 0.7, Palette.hudBg(), 2) :: Nil
    }

    def rr(x: Float64, y: Float64, w: Float64, h: Float64, r: Float64,
           c: Color, z: Int32): Part =
        { x = x, y = y, w = w, h = h, r = Float64.min(r, Float64.min(w, h) / 2.0), color = c, z = z }

    def toItem(center: Vec2.Vec2, size: Float64, p: Part): Render.PlacedItem =
        let s = size / 16.0;
        let tlx = center#x - size / 2.0;
        let tly = center#y - size / 2.0;
        let pos = {x = tlx + p#x * s, y = tly + p#y * s};
        let dim = {x = p#w * s, y = p#h * s};
        if (p#r <= 0.0)
            { at = pos, item = Render.box(dim, p#color, p#z) }
        else
            { at = pos, item = Render.box(dim, p#color, p#z) |> Render.rounded(p#r * s) }
}
