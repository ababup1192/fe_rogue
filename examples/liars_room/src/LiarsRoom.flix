// LiarsRoom — ゲームのルールの中心: フェーズ機械込みの 1 フレーム（tick）と Session 型。
// キー読み・描画・音の再生は App（engine_world）が引き受けるので、ここは値から値への
// 純粋関数だけでできている。フェーズは Room.Phase の 1 段の match で捌く。
mod LiarsRoom {

    /// App が回すゲーム 1 本ぶんの状態: UI ページの Store と部屋の World。
    pub type alias Session = {
        ui = UiStore.UiWorld,
        world = Room.World
    }

    /// 1 マスのスライドにかかる秒数（sokoban と同じ歩き心地）。
    def slideDuration(): Float64 = 0.125

    /// 歩行サイクルは 1 マス滑るごとにサイクルの 0.25 だけ進む。
    def strideBeat(): Float64 = 0.25

    /// 静止中の歩行サイクル（秒あたり）。
    def idleBeat(): Float64 = 0.75

    /// 発言の文字送りの速さ（1 秒あたりの文字数）。
    pub def dialogCps(): Float64 = 30.0

    /// 不正解の画面シェイクが続く秒数。
    pub def shakeDuration(): Float64 = 0.3

    // ── tick: フェーズ機械込みの 1 フレーム ──

    pub def tick(input: Room.Input, dt: Float64, w: Room.World): Room.World =
        let Room.World.World(s0) = w;
        let s = age(dt, s0);
        match s#phase {
            case Room.Phase.Title =>
                // 出題はプールからのくじ引き: entropy（経過フレーム数）は実時間で変わるので、
                // 同じステージでも起動のたびに違う問題が出る。
                if (input#enter)
                    Room.stageWorld(1, Map.empty(), Stage.pickSeed(1, s#entropy))
                else
                    Room.World.World(s)
            case Room.Phase.Exploring =>
                if (input#esc)
                    Room.titleWorld()
                else if (input#hint)
                    Room.World.World(Room.applyHint(s))
                else {
                    let s1 = debugTick(input, dt, s);
                    if (s1#memoOpen)
                        Room.World.World(memoTick(input, s1))
                    else
                        Room.World.World(exploreTick(input, dt, s1))
                }
            case Room.Phase.Talking =>
                Room.World.World(talkTick(input, dt, s))
            case Room.Phase.Confirming =>
                confirmTick(input, s)
            case Room.Phase.Wrong =>
                // やり直し: 同じシード = 同じ発言のまま。メモは持ち越す。
                if (input#enter)
                    Room.stageWorld(s#stage, s#memo, s#puzzleSeed)
                else
                    Room.World.World(s)
            case Room.Phase.Cleared =>
                if (input#enter)
                    (if (s#stage < Stage.stageCount())
                        Room.stageWorld(s#stage + 1, Map.empty(),
                            Stage.pickSeed(s#stage + 1, s#entropy))
                     else
                        Room.World.World({ phase = Room.Phase.Ending | s }))
                else
                    Room.World.World({ resultElapsed = s#resultElapsed + dt | s })
            case Room.Phase.Ending =>
                if (input#enter) Room.titleWorld() else Room.World.World(s)
        }

    /// どのフェーズでも進む時計: NPC のアイドルボブ、不正解シェイクの減衰、
    /// そして出題のくじ引きに使う entropy（毎フレーム +1）。
    def age(dt: Float64, s: Room.State): Room.State =
        { idlePhase = fract(s#idlePhase + dt),
          shakeT = Float64.max(0.0, s#shakeT - dt),
          entropy = s#entropy + 1 | s }

    /// 小数部分だけを残す（アイドルボブは 0..1 で繰り返す）。
    def fract(x: Float64): Float64 = x - Float64.floor(x)

    /// デバッグモード: D を押し続けた秒数を数え、5 秒に達したら全メモを正解で埋める
    /// （後半ステージの動作確認用の裏コマンド）。離すと数え直し。
    pub def debugHoldSeconds(): Float64 = 5.0

    def debugTick(input: Room.Input, dt: Float64, s: Room.State): Room.State =
        if (input#debug) {
            let held = s#debugHold + dt;
            if (held >= debugHoldSeconds())
                Room.debugFillMemo({ debugHold = 0.0 | s })
            else
                { debugHold = held | s }
        } else if (s#debugHold > 0.0)
            { debugHold = 0.0 | s }
        else
            s

    // ── Exploring: 歩き回り・話しかけ・メモ開閉 ──

    /// スライド中はキーを無視して絵を進め、着地したフレームからキーが効く（sokoban と同じ）。
    def exploreTick(input: Room.Input, dt: Float64, s: Room.State): Room.State =
        match s#slide {
            case Some(slide) =>
                let progress = dt / slideDuration();
                let t = slide#t + progress;
                let walked = { walkPhase = fract(s#walkPhase + strideBeat() * progress) | s };
                if (t < 1.0)
                    { slide = Some({ t = t | slide }) | walked }
                else
                    Room.beginHop(input, { slide = None | walked })
            case None =>
                let marched = { walkPhase = fract(s#walkPhase + idleBeat() * dt) | s };
                if (input#memo)
                    { memoOpen = true, memoSel = 0 | marched }
                else if (input#talk)
                    tryTalk(marched)
                else
                    Room.beginHop(input, marched)
        }

    /// 正面に NPC が居れば発言ウィンドウを開く（NPC はこちらを向く）。居なければ何もしない。
    /// 発言が複数あっても「〜で、〜だよ」と 1 つの文に繋いで 1 ウィンドウに納める。
    /// 名前はその NPC の色、嘘つき/正直者は太字のスパンにして渡す。
    def tryTalk(s: Room.State): Room.State =
        match Room.facingNpc(s) {
            case None      => s
            case Some(npc) =>
                let segs = Stmt.speech(speaker = npc#id, suffix = suffixOf(npc#id),
                                       Room.statementsOf(npc#id, s));
                let body = segs |> List.map(seg -> match seg {
                    case Stmt.Seg.Plain(text)  => RichText.plain(text)
                    case Stmt.Seg.Name(id)     =>
                        RichText.colored(Palette.nameOf(id), Palette.npcText(Palette.colorOf(id)))
                    case Stmt.Seg.Strong(text) => RichText.strong(text)
                });
                let line: UiDialog.Line = { speaker = "${Palette.nameOf(npc#id)}の人", body = body };
                { phase = Room.Phase.Talking, talkingTo = Some(npc#id),
                  dialog = UiDialog.openWith(line :: Nil)
                  | Room.turnNpcToPlayer(npc#id, s) }
        }

    // ── メモ（Exploring 中のオーバーレイ。開いている間は移動キーを取り上げる）──

    def memoTick(input: Room.Input, s: Room.State): Room.State =
        let count = List.length(s#npcs);
        if (input#memo or input#cancel)
            { memoOpen = false | s }
        else if (input#upTap)
            { memoSel = UiMenu.clampIndex(count, s#memoSel - 1) | s }
        else if (input#downTap)
            { memoSel = UiMenu.clampIndex(count, s#memoSel + 1) | s }
        else if (input#talk)
            { memo = cycleAt(s#memoSel, s#memo) | s }
        else
            s

    /// memoSel の NPC のマークを 1 つ進める（未定 → 嘘つき → 本物 → 未定）。
    def cycleAt(id: Int32, memo: Map[Int32, Room.Mark]): Map[Int32, Room.Mark] =
        let current = Map.get(id, memo) |> Option.getWithDefault(Room.Mark.Unknown);
        Map.insert(id, Room.cycleMark(current), memo)

    // ── Talking: 発言ウィンドウ ──

    /// 文字送りを進める。決定キーは「タイプ中 → 全文へ / 続きの行 → 次へ / 最終行 → 確認へ」。
    def talkTick(input: Room.Input, dt: Float64, s: Room.State): Room.State =
        let stepped = { dialog = UiDialog.step(cps = dialogCps(), dt, s#dialog) | s };
        if (input#cancel or input#esc)
            closeDialog(stepped)
        else if (input#talk) {
            if (not UiDialog.lineDone(stepped#dialog))
                { dialog = UiDialog.advance(stepped#dialog) | stepped }
            else if (List.length((stepped#dialog)#lines) > 1)
                { dialog = UiDialog.advance(stepped#dialog) | stepped }
            else
                // 最終行を読み終えて決定 → 「この人を信じる？」へ。カーソルは「やめる」側から。
                { phase = Room.Phase.Confirming, confirmSel = 1 | stepped }
        }
        else
            stepped

    /// 発言ウィンドウを閉じて歩き回りに戻る。
    def closeDialog(s: Room.State): Room.State =
        { phase = Room.Phase.Exploring, talkingTo = None,
          dialog = UiDialog.closed(), confirmSel = 1 | s }

    // ── Confirming: 「この人を信じる？」 ──

    def confirmTick(input: Room.Input, s: Room.State): Room.World =
        if (input#cancel or input#esc)
            Room.World.World(closeDialog(s))
        else if (input#upTap or input#downTap)
            Room.World.World({ confirmSel = 1 - s#confirmSel | s })
        else if (input#talk) {
            if (s#confirmSel == 0)
                answer(s)
            else
                // やめる → 会話を閉じて歩き回りに戻る（もう一度読みたければ話しかけ直す）。
                Room.World.World(closeDialog(s))
        }
        else
            Room.World.World(s)

    /// 回答の確定: 信じた相手が唯一解の正直者なら正解、嘘つきなら不正解。
    def answer(s: Room.State): Room.World =
        match s#talkingTo {
            case None     => bug!("LiarsRoom.answer: 会話相手なしで Confirming に居る")
            case Some(id) =>
                if (Set.memberOf(id, s#honestSet))
                    Room.World.World({ phase = Room.Phase.Cleared, resultElapsed = 0.0,
                                       dialog = UiDialog.closed() | s })
                else
                    Room.World.World({ phase = Room.Phase.Wrong, shakeT = shakeDuration(),
                                       dialog = UiDialog.closed() | s })
        }

    // ── 音: 耳のための投影 ──

    /// このフレームがどう聞こえるか: フェーズの変わり目（会話・確認・正解・不正解）と、
    /// 確定した 1 マスの移動、メモの書き込み。実際に鳴らす行為は App が引き受ける。
    pub def sfxEvent(before: Room.World, after: Room.World): Option[String] =
        let Room.World.World(b) = before;
        let Room.World.World(a) = after;
        if (a#phase != b#phase)
            phaseSound(a)
        else if (a#stage == b#stage and a#player != b#player)
            Some("move")
        else if (a#memo != b#memo)
            Some("memo")
        else
            None

    def phaseSound(a: Room.State): Option[String] = match a#phase {
        case Room.Phase.Talking    => Some(voiceOf(a#talkingTo))
        case Room.Phase.Confirming => Some("confirm")
        case Room.Phase.Wrong      => Some("wrong")
        case Room.Phase.Cleared    => Some("clear")
        case _                     => None
    }

    /// NPC の声の高さ（3 種の talk 音を id で使い分けて個性を出す）。
    pub def voiceOf(talkingTo: Option[Int32]): String =
        let id = talkingTo |> Option.getWithDefault(0);
        match Int32.modulo(id, 3) {
            case 0 => "talk_mid"
            case 1 => "talk_high"
            case _ => "talk_low"
        }

    /// NPC の語尾（声のトーンと同じ 3 分類: ふつう / 高い声は元気に / 低い声は断定調に）。
    pub def suffixOf(id: Int32): String =
        match Int32.modulo(id, 3) {
            case 0 => "だよ"
            case 1 => "だね！"
            case _ => "だぞ"
        }

    /// BGM（時計の針のループ）はタイトルからゲームへ入る瞬間に一度だけ火を入れる
    /// （looping = true の音は一度 play すれば鳴り続ける）。
    pub def bgmStarts(before: Room.World, after: Room.World): Bool =
        let Room.World.World(b) = before;
        let Room.World.World(a) = after;
        b#phase == Room.Phase.Title and a#phase == Room.Phase.Exploring
}
