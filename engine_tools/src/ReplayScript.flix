// ReplayScript — 操作リプレイ GIF の入力スクリプト表現と実行器。
//
// GIF は「宣言データ（Step 列）」を本物の入力処理 / frameStep で 1 フレームずつ実行して撮る。
// ここは *何が起きるか* を持たず、*順番* だけを持つ:
//   - Key      : 意味入力（Up/Down/Left/Right/Confirm/Cancel/Shift）。物理キーではなく
//                 「メニューを 1 つ上へ」等の意味で、呼び側が Game.flix の dispatch を写して
//                 各 Ui の pub API（moveSelection / confirm…）へ束ねる。
//   - Step     : KeyPress(Key)（1 入力）/ Wait(frames)（入力なしで frames ぶん進める）。
//   - execute  : 各 KeyPress で applyKey→betweenFrames フィラー、Wait(n) で n フィラーを回す。
//                最初に 1 フレーム収録してから steps を消化する。
//
// applyKey（入力→Ui API）と tick（frameStep→renderUi→フレーム収録）は効果を持つので、
// record 越しでなく HOF 引数で直接渡す（closure 保存は subeffecting が効かないため）。
// applyKey と tick は別々の効果多相変数を取り、結果効果はその和になる。
mod ReplayScript {

    /// 意味入力。メニューの ↑↓←→ と決定 / 取消 / 印付け。
    pub enum Key with Eq, ToString {
        case Up
        case Down
        case Left
        case Right
        case Confirm
        case Cancel
        case Shift
    }

    /// スクリプトの 1 手。KeyPress は 1 入力＋間フレーム、Wait は入力なしで n フレーム進める。
    pub enum Step {
        case KeyPress(Key)
        case Wait(Int32)
    }

    /// スクリプトを実行する。
    ///   betweenFrames : 1 入力の後に挟むフィラーフレーム数（遷移やワイプが見えるように進める）。
    ///   script        : Step 列。
    ///   applyKey      : 意味入力を対応する Ui API 呼びへ束ねる（Game.flix の dispatch を写す）。
    ///   tick          : 1 フレーム進めて収録する（frameStep → renderUi → フレーム追加）。
    /// 先頭で 1 フレーム収録してから Step を消化する（初期状態も動画に入れる）。
    pub def execute(betweenFrames: Int32, script: List[Step],
                    applyKey: Key -> Unit \ ef1, tick: Unit -> Unit \ ef2): Unit \ ef1 + ef2 =
        tick();
        List.forEach(step -> match step {
            case Step.KeyPress(k) => applyKey(k); fillFrames(betweenFrames, tick)
            case Step.Wait(n)     => fillFrames(n, tick)
        }, script)

    /// tick を n 回呼ぶ（n<=0 は何もしない）。
    def fillFrames(n: Int32, tick: Unit -> Unit \ ef): Unit \ ef =
        if (n <= 0) () else { tick(); fillFrames(n - 1, tick) }
}
