// Trace (sokoban) — engine_world の Replay fold に流し込む、ゲーム固有の入力と
// 同梱の解答。汎用の仕組み（Replay.Cue、Replay.play、Replay.timeline）は
// engine_world に住み、このファイルは Board.Input の値、固定の時計、そして両レ
// ベルの解答をデータとして供給するだけである。
//
// Cue は1つの Input をいくつかのフレーム分保持する；Trace は Cue のリストであ
// る。Trace を駆動することは純粋な tick 上の fold（Replay.play / Replay.timeline）
// なので、1つの解答は同時に3つのものになる —— ユニットテスト（結末を固定す
// る）、フィルム（すべてのフレームを描画する）、そしてバグレポート（失敗する
// Trace はそのまま再現手順である）。
mod Trace {

    /// すべてのリプレイが走る固定の時計: 1フレームあたり 1/64 秒 —— 2進小数なの
    /// で、固定された結末に現れるすべてのスライド t と歩行位相は誤差なく正確で
    /// ある。
    pub def dt(): Float64 = 1.0 / 64.0

    /// 何も押していない 1 フレーム（Board.noKeys の別名。Trace の語彙として置く）。
    pub def idle(): Board.Input = Board.noKeys()

    def dirInput(d: Dir4.Dir4): Board.Input = match d {
        case Dir4.Up    => { up = true | idle() }
        case Dir4.Down  => { down = true | idle() }
        case Dir4.Left  => { left = true | idle() }
        case Dir4.Right => { right = true | idle() }
    }

    /// 1つの入力を n フレームの間保持する。
    pub def hold(input: Board.Input, frames: Int32): Replay.Cue[Board.Input] =
        { input = input, frames = frames }

    /// 歩いた1手: キーを1フレーム叩き、それからスライドが着地するのを待つ
    /// （このクロックでは1スライドは0.125秒 = 8フレーム）。
    pub def walk(d: Dir4.Dir4): List[Replay.Cue[Board.Input]] =
        hold(dirInput(d), 1) :: hold(idle(), 8) :: Nil

    /// n フレームの間 Z を押し続ける —— 着地した逆スライドはそれぞれ次の巻き戻し
    /// を連鎖させるので、1回の長い押しっぱなしが履歴を手ごとに歩いて戻る。
    pub def rewind(frames: Int32): Replay.Cue[Board.Input] =
        hold({ undo = true | idle() }, frames)

    /// レベル1の同梱の解答、データとして: 7手。2回の押しは3手目（下のクレート
    /// をゴールへ）と最後（上のクレートを家へ —— CLEAR）。
    pub def solveLevelOne(): List[Replay.Cue[Board.Input]] =
        List.flatMap(walk,
            Dir4.Left :: Dir4.Up :: Dir4.Right ::
            Dir4.Up :: Dir4.Right :: Dir4.Up ::
            Dir4.Left :: Nil)

    /// レベル2の同梱の解答、データとして: 21手。内部の壁が迂回を強いる ——
    /// 下のクレートを左へ押し、上の通路を回ってその上へ回り込み、それを
    /// (1,5) へ下向きに押し、通路を通って戻り、上のクレートを (6,2) へ右向き
    /// に押す: CLEAR。
    pub def solveLevelTwo(): List[Replay.Cue[Board.Input]] =
        List.flatMap(walk,
            Dir4.Up :: Dir4.Left ::
            Dir4.Right :: Dir4.Up :: Dir4.Right ::
            Dir4.Up :: Dir4.Up ::
            Dir4.Left :: Dir4.Left :: Dir4.Left ::
            Dir4.Down :: Dir4.Down :: Dir4.Down ::
            Dir4.Up :: Dir4.Up :: Dir4.Up ::
            Dir4.Right :: Dir4.Right :: Dir4.Right ::
            Dir4.Down :: Dir4.Right :: Nil)
}
