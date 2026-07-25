// Daylight — 1 日の進み（0.0〜1.0）から「空気の色」を決め、画面全体に薄く掛ける。
// 朝の青白さ・昼の素通し・夕方の橙・夜の紺を、節（Key）を並べるだけで滑らかにつなぐ。
// 一周して戻るので、日付が変わる瞬間も色が飛ばない。
// 利用例: 時刻で野外の色が変わる / 洞窟だけ常夜にする / 天気で 1 段暗くする。
// 注意: 掛けるのは色だけ。時計そのものは Calendar、明かりの穴あけは Light の仕事。
//
// 掛け方は乗算（Multiply）— 自分より奥（小さい zIndex）に描かれた物だけが染まる。
// HUD や会話窓を染めたくないときは、それらを overlay の z より大きい z に置くこと。
mod Daylight {

    /// 空気の色の節。at = 1 日のどこか（0.0〜1.0）、color = そのときの色、
    /// strength = どれだけ染めるか（0 = 素通し、1 = その色そのもの）。
    pub type alias Key = { at = Float64, color = Color, strength = Float64 }

    /// よくある一日（夜明け前の紺 → 朝の淡い青 → 昼は素通し → 夕方の橙 → 夜の紺）。
    pub def defaults(): List[Key] =
        { at = 0.00, color = { r = 0.24f32, g = 0.30f32, b = 0.60f32 }, strength = 0.90 }
     :: { at = 0.22, color = { r = 0.50f32, g = 0.56f32, b = 0.78f32 }, strength = 0.58 }
     :: { at = 0.30, color = { r = 0.94f32, g = 0.90f32, b = 0.86f32 }, strength = 0.18 }
     :: { at = 0.50, color = { r = 1.00f32, g = 1.00f32, b = 1.00f32 }, strength = 0.00 }
     :: { at = 0.72, color = { r = 1.00f32, g = 0.82f32, b = 0.62f32 }, strength = 0.34 }
     :: { at = 0.80, color = { r = 0.98f32, g = 0.60f32, b = 0.44f32 }, strength = 0.52 }
     :: { at = 0.88, color = { r = 0.36f32, g = 0.36f32, b = 0.68f32 }, strength = 0.80 }
     :: { at = 0.95, color = { r = 0.24f32, g = 0.30f32, b = 0.60f32 }, strength = 0.90 }
     :: Nil

    /// t（1 日の進み）のときの空気の色と濃さ。節が 1 つも無ければ素通し。
    pub def sample(keys: List[Key], t: Float64): Key =
        let sorted = List.sortBy(k -> k#at, keys);
        match sorted {
            case Nil       => { at = t, color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, strength = 0.0 }
            case one :: Nil => { at = t | one }
            case first :: _ =>
                let u = wrap01(t);
                // u の手前にある最後の節と、その次の節（無ければ一周して先頭）で混ぜる。
                let before = List.filter(k -> k#at <= u, sorted) |> List.last;
                let after  = List.filter(k -> k#at > u, sorted) |> List.head;
                let lo = Option.getWithDefault(shifted(-1.0, lastOf(sorted, first)), before);
                let hi = Option.getWithDefault(shifted(1.0, first), after);
                let span = hi#at - lo#at;
                let f = if (Float64.abs(span) < 0.000001) 0.0 else clamp01((u - lo#at) / span);
                { at = u,
                  color = mixColor(lo#color, hi#color, f),
                  strength = lo#strength + (hi#strength - lo#strength) * f }
        }

    /// いまの空気を画面いっぱいに掛ける 1 枚。size = design 解像度、z = 掛かる境目。
    /// 濃さは色を白へ薄めることで表すので、重ね方は素直な乗算 1 回で済む。
    pub def overlay(spec: { keys = List[Key], size = Vec2.Vec2, z = Int32 },
                    t: Float64): List[Render.PlacedItem] =
        let air = sample(spec#keys, t);
        if (air#strength <= 0.001) Nil
        else
            let white = { r = 1.0f32, g = 1.0f32, b = 1.0f32 };
            { at = { x = 0.0, y = 0.0 },
              item = Render.box(spec#size, mixColor(white, air#color, clamp01(air#strength)), spec#z)
                  |> Render.blended(DrawCmd.BlendMode.Multiply) } :: Nil

    /// 空気の色を 1 つの色に掛ける。空そのものや遠景など、乗算の幕より手前に置きたい物を
    /// 手で染めるときに使う。
    pub def tint(keys: List[Key], t: Float64, base: Color): Color =
        let air = sample(keys, t);
        let mixed = mixColor({ r = 1.0f32, g = 1.0f32, b = 1.0f32 }, air#color, clamp01(air#strength));
        { r = base#r * mixed#r, g = base#g * mixed#g, b = base#b * mixed#b }

    // ── 内部 ──

    /// 一周ぶん at をずらした節（0 の手前・1 の先へ節を延長して、日またぎを継ぎ目なくする）。
    def shifted(delta: Float64, k: Key): Key = { at = k#at + delta | k }

    def lastOf(sorted: List[Key], fallback: Key): Key =
        List.last(sorted) |> Option.getWithDefault(fallback)

    def mixColor(a: Color, b: Color, f: Float64): Color =
        let t = Float64.truncateToFloat32(clamp01(f));
        { r = a#r + (b#r - a#r) * t,
          g = a#g + (b#g - a#g) * t,
          b = a#b + (b#b - a#b) * t }

    def wrap01(v: Float64): Float64 =
        let f = v - Float64.floor(v);
        if (f < 0.0) f + 1.0 else f

    def clamp01(v: Float64): Float64 =
        Float64.max(0.0, Float64.min(1.0, v))
}
