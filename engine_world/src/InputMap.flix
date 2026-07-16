// InputMap — 生の入力（キー）を「操作の意図」へ写す。意図の型はゲームが自分の enum で
// 決め、ここは「W と ↑ は同じ意味」という表に従って写すだけ。軸への合成など意図の解釈は
// 受け取ったゲーム側（ハンドリング時）が行う — 写像と解釈を分ける。
// 単発の操作（決定・キャンセル）は firstTap、列を消費する操作（移動の fold）は taps / held。

mod InputMap {

    /// (キー, 意図) の表。同じ意図を複数キーに割り当ててよい（WASD と矢印、Z と Enter）。
    pub type alias Table[a] = List[(GameEngine.Key, a)]

    /// 押した瞬間に発火した意図（表の順・同じ意図は 1 回）。決定・キャンセルなどの単発操作用。
    pub def taps(table: Table[a], frame: App.Frame): List[a] with Eq[a] =
        firedIn(table, frame#justPressed)

    /// 発火した意図の先頭だけ（同時押しは表の順で先勝ち）。メニュー操作はこれで十分。
    pub def firstTap(table: Table[a], frame: App.Frame): Option[a] with Eq[a] =
        List.head(taps(table, frame))

    /// 押している間ずっと発火する意図（表の順・同じ意図は 1 回）。移動などの連続操作用。
    /// 空リスト = 何も押していない（軸の fold なら初期値がそのまま残る）。
    pub def held(table: Table[a], frame: App.Frame): List[a] with Eq[a] =
        firedIn(table, frame#down)

    /// 表とキー集合から発火した意図を引く芯（テストはここを直接叩く）。
    /// 同じ意図が複数キーで同時に立っても 1 回にする — 二重加速のような事故を作らない。
    pub def firedIn(table: Table[a], keys: Set[GameEngine.Key]): List[a] with Eq[a] =
        table
            |> List.filterMap(match (key, intent) ->
                if (Set.memberOf(key, keys)) Some(intent) else None)
            |> List.distinct

    /// ホイールの生 delta を「目盛り」へ畳む。マウスは 1 目盛りで ±1.0 が届くが、
    /// トラックパッドは 1 未満の細かい値が毎フレーム届くので、そのまま使うと速度が
    /// フレームレート依存になる。carry に貯めて ±1.0 を超えたぶんだけを目盛り数として
    /// 返し、端数は次フレームへ持ち越す。carry は呼び側が World に持つ — Frame は
    /// 毎フレーム作り直しで、ここに状態は持てない。
    /// バックエンド由来の不正値(NaN / ∞)や Int32 に収まらない蓄積は (0, 0.0) に戻す —
    /// 一度 carry に混ざると以後ずっと 0 目盛りのまま直らないので、黙って捨てて回復を取る。
    pub def wheelSteps(carry: Float64, delta: Float64): (Int32, Float64) =
        let total = carry + delta;
        if (Float64.isNan(total) or Float64.abs(total) > 2147483000.0)
            (0, 0.0)
        else {
            let whole = if (total >= 0.0) Float64.floor(total) else Float64.ceil(total);
            let steps = Float64.tryToInt32(whole) |> Option.getWithDefault(0);
            (steps, total - Int32.toFloat64(steps))
        }
}
