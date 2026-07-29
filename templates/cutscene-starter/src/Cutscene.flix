// Cutscene — このゲームの動詞（歩く・話す・火の玉・幕）の演じ方（すべて純粋）。
//
// 骨格は SceneSeq（進行・報せ・安全弁）と Steering（マス目の 1 歩）が持ち、
// このファイルが書くのは **perform = カット 1 つを 1 コマ演じる関数** だけ。
// 「歩き終わった」「ふきだしが閉じた」は実際の World から判定する —
// フレーム数を先に数えないので、途中で道がふさがれても脚本と画がずれない。
// 演じている間、火の玉の追跡は凍らせる（World.calmWisp — 脚本で指した位置に必ず居る）。
mod Cutscene {
    use SceneSeq.Status

    /// 現在のカットの進み具合。動きの進捗は World 側の状態（マス・ふきだし）が
    /// そのまま持つので、ここに持つのは時間の払い出しだけ。
    pub enum Progress {
        /// Wait: 残りの秒。
        case Waiting(Float64)
        /// Say / Talk: いま出ている行を読ませる残りの秒（行が出切ってから数える）。
        case Reading(Float64)
        /// WispTo: 火の玉の次の 1 歩までの残り秒。
        case Gauge(Float64)
        /// Fade: 幕の滑り（中身は Shade）。
        case Fading(Shade)
    }

    /// 幕の滑り 1 回ぶん。origin の濃さから total 秒かけて目標（黒 or 無し）へ寄せる。
    pub type alias Shade = { origin = Float64, spent = Float64, total = Float64 }

    /// 演じる 1 コマの秒（30fps。GIF は 1 コマおきに間引いて 15fps になる）。
    pub def dt(): Float64 = 1.0 / 30.0

    /// 出切った行を読ませる間（秒）。演出の間なので Doc へは出さない。
    def readPause(): Float64 = 0.7

    /// 暴走の安全弁: 1 シーンに許す最大のコマ数（30fps で 2 分）。
    def maxFrames(): Int32 = 3600

    /// 脚本の始まりの状態に置く。場面の仕度（phase・ふきだし・幕）は World 自身が整える
    /// （World.stagedAt — 内臓の旗をここから触らない）。
    pub def stage(doc: CutsceneDoc.Doc, w0: World.World): World.World =
        World.stagedAt({ cell = doc#start, facing = doc#facing }, w0)

    /// シーンを最初から最後まで演じ、コマの列と報せを返す（bake の入口）。
    pub def framesOf(doc: CutsceneDoc.Doc, w0: World.World): SceneSeq.Played[World.World] =
        SceneSeq.play(perform, idle, maxFrames(), dt(), doc#cuts, stage(doc, w0))

    /// 演じ切った終わりの姿だけ（テストの検査用）。
    pub def finalWorld(doc: CutsceneDoc.Doc, w0: World.World): World.World =
        SceneSeq.finalWorld(perform, idle, maxFrames(), dt(), doc#cuts, stage(doc, w0))

    /// カットが尽きたあとの 1 コマ（時間だけを流す。火の玉は凍らせたまま —
    /// シーンの絵の中で勝手に追跡が始まらない）。
    def idle(dtv: Float64, w: World.World): World.World =
        World.step(None, dtv, World.calmWisp(w))

    // ── perform: カット 1 つを 1 コマ演じる（SceneSeq へ注入する唯一の関数） ──

    /// World.step をちょうど 1 回通す（文字送り・歩みの拍は全部この 1 回が担う）。
    /// カットの終わりは実際の World から判定する。
    /// 守衛（only / unless）に合わない行は**ただ黙って済む** — 分岐ではなく条件行なので、
    /// 飛ばした報せも出さない（事実ちがいの台本が毎回報されるとログが死ぬ）。
    pub def perform(row: CutsceneDoc.Guarded, progress: Option[Progress], dtv: Float64,
                    w0: World.World): (Status[Progress], World.World) =
        let w = World.calmWisp(w0);
        if ((row#only != "" and not World.holdsFact(row#only, w))
                or (row#unless != "" and World.holdsFact(row#unless, w)))
            (Status.Done, World.step(None, dtv, w))
        else match row#cut {
            case CutsceneDoc.Cut.Wait(sec)        => tickWait(dtv, sec, progress, w)
            case CutsceneDoc.Cut.WalkTo(walk)     => tickWalk(dtv, walk, w)
            case CutsceneDoc.Cut.Face(d)          =>
                (Status.Done, World.step(None, dtv, { facing = d | w }))
            case CutsceneDoc.Cut.Say(lines)       => tickSay(dtv, lines, progress, w)
            case CutsceneDoc.Cut.Talk(d)          => tickTalk(dtv, d, progress, w)
            case CutsceneDoc.Cut.WispTo(spec)     => tickWisp(dtv, spec, w)
            case CutsceneDoc.Cut.Flash(secs)      =>
                (Status.Done, World.step(None, dtv, { flash = secs | w }))
            case CutsceneDoc.Cut.Shake(secs)      =>
                (Status.Done, World.step(None, dtv, { quake = secs | w }))
            case CutsceneDoc.Cut.WispAppear(cell) =>
                if (World.wispCanFloat(cell, w) and not MapDoc.sameCell(cell, w#hero))
                    (Status.Done, World.step(None, dtv, { wisp = Some(cell) | w }))
                else
                    (Status.Skip("(${cell#x},${cell#y}) には火の玉を出せない(石垣か、主人公が居る)"),
                     World.step(None, dtv, w))
            case CutsceneDoc.Cut.WispVanish       =>
                (Status.Done, World.step(None, dtv, { wisp = None | w }))
            case CutsceneDoc.Cut.Fade(shade)      => tickFade(dtv, shade, progress, w)
            case CutsceneDoc.Cut.Broken           =>
                (Status.Skip("読めないカット(知らない鍵か、形が違う)"),
                 World.step(None, dtv, w))
        }

    // ── 待つ ──

    /// その場で待つ。時間だけが流れる（霧も灯りも生きたまま）。
    def tickWait(dtv: Float64, sec: Float64, progress: Option[Progress],
                 w: World.World): (Status[Progress], World.World) =
        let remaining = match progress {
            case Some(Progress.Waiting(r)) => r
            case _                         => sec
        };
        let stepped = World.step(None, dtv, w);
        if (remaining - dtv <= 0.0) (Status.Done, stepped)
        else (Status.Running(Progress.Waiting(remaining - dtv)), stepped)

    // ── 歩く（走る・後ずさり） ──

    /// 目的のマスへ移る。毎コマ、目的地への最短の 1 歩（Steering.chase）を引き直して
    /// 踏み出す — 途中で盤面が変わっても、その時の間取りから選び直す。
    /// 着けない（石垣の中・道が無い）ならこのカットは飛ぶ（fail-open）。
    def tickWalk(dtv: Float64, walk: CutsceneDoc.Stride,
                 w0: World.World): (Status[Progress], World.World) =
        // 意図（向かい先）を World に書き、歩きの規則は World.step に任せる。
        // 待たない歩き（noWait）は意図を書いた拍で済み — 以後のカットと同時に歩く。
        let w = { heading = Some(walk#cell) | w0 };
        if (not walk#waits)
            (Status.Done, World.step(None, dtv, w))
        else if (MapDoc.sameCell(w#hero, walk#cell))
            (Status.Done, World.step(None, dtv, { heading = None | w }))
        else if (Option.isEmpty(Steering.chase(
                     c -> { let (cx, cy) = c; World.walkable({ x = cx, y = cy }, w) },
                     (w#hero#x, w#hero#y), (walk#cell#x, walk#cell#y),
                     MapDoc.cols(w#map) * MapDoc.rowCount(w#map))))
            (Status.Skip("(${walk#cell#x},${walk#cell#y}) へ歩いて着けない(石垣の中か、道が無い)"),
             World.step(None, dtv, { heading = None | w }))
        else
            (Status.Running(Progress.Waiting(0.0)), strideStep(walk, dtv, w))

    /// 歩幅と向きを整えた 1 拍。走り（dash）は歩く速さを倍にして通し、済んだら元へ戻す
    /// （速さの絶対値は Doc に書かせない）。後ずさり（back）は踏み出しで変わった向きを
    /// 元へ戻す — 怖いものから目を離さずに下がる。
    def strideStep(walk: CutsceneDoc.Stride, dtv: Float64,
                   w: World.World): World.World =
        let paced = if (walk#dash) { kind = { walk = w#kind#walk * 2.0 | w#kind } | w } else w;
        let stepped = { kind = w#kind | World.step(None, dtv, paced) };
        if (walk#back) { facing = w#facing | stepped } else stepped

    // ── 言葉（ひとりごと・話しかける） ──

    /// 主人公のひとりごと。ふきだしを主人公の頭の上に開き、閉じるまで読ませる。
    def tickSay(dtv: Float64, lines: List[String], progress: Option[Progress],
                w: World.World): (Status[Progress], World.World) =
        match progress {
            case None =>
                if (List.isEmpty(lines)) (Status.Done, World.step(None, dtv, w))
                else {
                    let opened = { dialog = UiDialog.openWith(lines |> List.map(line ->
                                       { speaker = "", body = RichText.plain(line) :: Nil })),
                                   talkingTo = Some(w#hero) | w };
                    (Status.Running(Progress.Reading(readPause())),
                     World.step(None, dtv, opened))
                }
            case Some(p) => awaitClose(dtv, p, w)
        }

    /// その向きの相手に話しかける。どの言葉が出るか（いつもの 1 行・頼まれごと・扉が開く）
    /// は World.confirm の規則がそのまま決める — 脚本は「誰に」だけを書く。
    /// 相手が居なければ飛ぶ（fail-open）。
    def tickTalk(dtv: Float64, direction: Dir4.Dir4, progress: Option[Progress],
                 w: World.World): (Status[Progress], World.World) =
        match progress {
            case None => {
                let spoken = World.confirm({ facing = direction | w });
                if (UiDialog.isOpen(spoken#dialog))
                    (Status.Running(Progress.Reading(readPause())),
                     World.step(None, dtv, spoken))
                else
                    (Status.Skip("その向きに話し相手が居ない"), World.step(None, dtv, spoken))
            }
            case Some(p) => awaitClose(dtv, p, w)
        }

    /// 開いたふきだしを読ませて送る。文字が出切るのを待ち、読ませる間を置いて送り、
    /// 閉じた拍に Done — 行ごとの拍の数は数えないので、行が何行でもずれない。
    def awaitClose(dtv: Float64, p: Progress, w: World.World): (Status[Progress], World.World) =
        if (not UiDialog.isOpen(w#dialog))
            (Status.Done, World.step(None, dtv, w))
        else {
            let stepped = World.step(None, dtv, w);
            if (not UiDialog.lineDone(stepped#dialog))
                (Status.Running(Progress.Reading(readPause())), stepped)
            else {
                let remaining = match p {
                    case Progress.Reading(r) => r
                    case _                   => readPause()
                };
                if (remaining - dtv <= 0.0)
                    (Status.Running(Progress.Reading(readPause())), World.confirm(stepped))
                else
                    (Status.Running(Progress.Reading(remaining - dtv)), stepped)
            }
        }

    // ── 火の玉 ──

    /// 火の玉を目的のマスへ詰めさせる。歩の間隔は遊びと同じ（World.wispPace）。
    /// 経路は火の玉の規則（石垣だけが行き止まり・主人公のマスは避ける）の 1 歩ずつ。
    /// 居ない・着けないなら飛ぶ（fail-open）。
    def tickWisp(dtv: Float64, spec: { cell = Grid.Cell, waits = Bool },
                 w0: World.World): (Status[Progress], World.World) =
        // 指図（向かい先）を World に書き、詰め方は World.step（haunt）に任せる。
        // 待たない指図（noWait）は書いた拍で済み — 以後のカットと同時に詰めてくる。
        match w0#wisp {
            case None       =>
                (Status.Skip("火の玉が居ない(wispAppear で出すか、間取りの wisp を書く)"),
                 World.step(None, dtv, w0))
            case Some(cell) =>
                let w = { wispGoal = Some(spec#cell) | w0 };
                if (not spec#waits)
                    (Status.Done, World.step(None, dtv, w))
                else if (MapDoc.sameCell(cell, spec#cell))
                    (Status.Done, World.step(None, dtv, { wispGoal = None | w }))
                else if (Option.isEmpty(Steering.chase(
                             c -> { let (cx, cy) = c;
                                    World.wispCanFloat({ x = cx, y = cy }, w)
                                        and not MapDoc.sameCell({ x = cx, y = cy }, w#hero) },
                             (cell#x, cell#y), (spec#cell#x, spec#cell#y),
                             MapDoc.cols(w#map) * MapDoc.rowCount(w#map))))
                    (Status.Skip("火の玉が (${spec#cell#x},${spec#cell#y}) へ行けない"),
                     World.step(None, dtv, { wispGoal = None | w }))
                else
                    (Status.Running(Progress.Waiting(0.0)), World.step(None, dtv, w))
        }

    // ── 幕 ──

    /// 幕を掛ける・明ける。いまの濃さから目標（黒 or 無し）へ secs 秒かけて滑らかに寄せる。
    def tickFade(dtv: Float64, shade: { dark = Bool, secs = Float64 },
                 progress: Option[Progress], w: World.World): (Status[Progress], World.World) =
        let target = if (shade#dark) 1.0 else 0.0;
        match progress {
            case Some(Progress.Fading(f)) => fadeOn(dtv, f, target, w)
            case _ =>
                if (shade#secs <= 0.0)
                    (Status.Done, World.step(None, dtv, { curtain = target | w }))
                else
                    fadeOn(dtv, { origin = w#curtain, spent = 0.0, total = shade#secs },
                           target, w)
        }

    /// 幕の滑りを dt ぶん進める（なめらかな出入り = smoothstep）。
    def fadeOn(dtv: Float64, f: Shade, target: Float64,
               w: World.World): (Status[Progress], World.World) =
        let spent = f#spent + dtv;
        let u = Float64.min(1.0, spent / Float64.max(0.001, f#total));
        let eased = u * u * (3.0 - 2.0 * u);
        let level = f#origin + (target - f#origin) * eased;
        if (u >= 1.0)
            (Status.Done, World.step(None, dtv, { curtain = target | w }))
        else
            (Status.Running(Progress.Fading({ spent = spent | f })),
             World.step(None, dtv, { curtain = level | w }))
}
