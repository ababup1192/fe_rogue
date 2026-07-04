// EcsTween — 汎用 ECS tween（B/m2・動きの統一抽象）。
//
// 設計（レビュー 91/100）: lib は **「値の補間」だけ**を知り、「何を動かすか（Position/Alpha…）」は
// ゲームの `Channel` が持つ（Bevy Lens の no-reflection 版＝Flix idiomatic な typed enum）。
// engine scene `Tween`（NodePath バインド・Scheduler 効果）の ECS-native 版＝EntityId キー・純粋・World
// component 出力・**実時間 dt 秒**で進む（fps 非依存）。複合キー `(entity, channel)` で 1 entity が複数
// チャンネル（移動＋フェード等）を同時に持てる。`Out` を返し、対象 component への書き込みは呼び出し側が行う。
//
// 名前は engine scene `Tween`（cursor/popup 用に存続）との衝突回避で `EcsTween`。
// 共有パッケージ flix_engine_world の一部。どの ECS ゲームも import して `(entity, channel)` の
// tween を進め、返る `Out` を対象 component へ書き戻す。
mod EcsTween {

    /// Vec2 の線形補間（start→target）。Position/Knockback 等のベクトル軌道。
    pub type alias VecLerp   = { start = Vec2.Vec2, target = Vec2.Vec2 }
    /// スカラの線形補間（start→target）。Alpha/Scale 等。全 Float64・narrow は適用境界（Sprite 書込時）で。
    pub type alias FloatLerp = { start = Float64, target = Float64 }

    /// 補間カーブ。0→0・1→1 を保つ（完了時の exact スナップを保証）。
    pub enum Easing with Eq {
        case Linear
        case EaseIn
        case EaseOut
        case EaseInOut
    }

    /// 補間する**値の型**だけを表す（意味＝チャンネルは持たない）。
    pub enum Track {
        case Vec(VecLerp)
        case Scalar(FloatLerp)
    }

    /// 補間の**出力値**（呼び出し側が対象 component へ書く）。
    pub enum Out {
        case VecOut(Vec2.Vec2)
        case ScalarOut(Float64)
    }

    /// 進行中の 1 tween。elapsed/duration は実時間秒。
    /// yoyo=false=単発(0→1 で done)・true=1往復(0→1→0 で done・無限ループにしない＝isActive ゲートの意味を保つ)。
    pub type alias Entry = { track = Track, elapsed = Float64, duration = Float64, easing = Easing, yoyo = Bool }

    /// 複合キー (entity, channel) → Entry。1 entity が複数チャンネルを同時に持てる。
    /// キーの Order は stdlib `instance Order[(a,b)]` から `with Order[k], Order[c]` で導出。
    pub type alias Tweens[k, c] = Map[(k, c), Entry]

    /// 0 除算回避の最小 duration（秒）。dur=0 でも step の t=elapsed/duration が発散しない下限。
    def minDuration(): Float64 = 0.001

    /// tween を開始（既存の同キーは置換）。dur は 0 除算回避で minDuration() にクランプ。
    pub def start(key: (k, c), track: Track, dur: Float64, easing: Easing, yoyo: Bool, ts: Tweens[k, c]): Tweens[k, c] with Order[k], Order[c] =
        Map.insert(key, {track = track, elapsed = 0.0, duration = Float64.max(minDuration(), dur), easing = easing, yoyo = yoyo}, ts)

    /// 当該キーが進行中か（input gate 用）。
    pub def isActive(key: (k, c), ts: Tweens[k, c]): Bool with Order[k], Order[c] =
        Map.memberOf(key, ts)

    /// 全 tween を dt 秒進める。返り: (更新後 tweens, 補間出力, 今フレーム完了キー)。
    /// ★`outs` は当フレーム進めた**全キー**を含み、**完了キーは t=1.0 に clamp した exact スナップ値**
    ///   （yoyo=false→target / yoyo=true→start・lerp(t<1) ではない）。完了フレームの最終位置正しさの全荷重。
    pub def step(dt: Float64, ts: Tweens[k, c]): (Tweens[k, c], List[((k, c), Out)], List[(k, c)]) with Order[k], Order[c] =
        Map.foldLeftWithKey((acc, key, entry) -> {
            let (accTs, accOuts, accDone) = acc;
            let nextElapsed = entry#elapsed + dt;
            let done        = nextElapsed >= entry#duration;
            // 完了フレームは t=1.0 へ clamp＝exact スナップ（yoyo は paramOf 内の三角波で start に戻る）。
            let t           = if (done) 1.0 else nextElapsed / entry#duration;
            let out         = outAt(entry#track, paramOf(entry, t));
            let nextTs      = if (done) Map.remove(key, accTs)
                              else Map.insert(key, {elapsed = nextElapsed | entry}, accTs);
            let nextDone    = if (done) key :: accDone else accDone;
            (nextTs, (key, out) :: accOuts, nextDone)
        }, (ts, Nil, Nil), ts)

    /// t∈[0,1]（経過率）→ 補間パラメータ。yoyo は三角波（0→1→0）に畳んでから easing。
    def paramOf(entry: Entry, t: Float64): Float64 =
        let raw = if (entry#yoyo) (if (t < 0.5) 2.0 * t else 2.0 * (1.0 - t)) else t;
        ease(entry#easing, raw)

    /// パラメータ p∈[0,1] での Track 出力値。
    def outAt(track: Track, p: Float64): Out = match track {
        case Track.Vec(vl)    => Out.VecOut(Vec2.lerp(vl#start, vl#target, p))
        case Track.Scalar(fl) => Out.ScalarOut(fl#start + (fl#target - fl#start) * p)
    }

    /// 補間カーブ（全て 0→0・1→1 を保つ）。
    def ease(e: Easing, t: Float64): Float64 = match e {
        case Easing.Linear    => t
        case Easing.EaseIn    => t * t
        case Easing.EaseOut   => t * (2.0 - t)
        case Easing.EaseInOut => if (t < 0.5) 2.0 * t * t else -1.0 + (4.0 - 2.0 * t) * t
    }

}
