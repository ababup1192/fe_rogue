// Sokoban —心臓部: ボードを dt だけ進める純粋な step、セッション全体（時間機械
// 込み）を回す tick、そして境界を越えるランチャーの loop —— キーが入り、ピクセル
// と音が出る。
//
// セッションの履歴は Worldline（engine_world の Worlds のジッパー）: 確定した
// 各手が移動前の World を記録し、Z がそこへ巻き戻す。Worldline 自体は World の
// 外、loop の中に住む —— 時間機械は時間の中にはない。Board とそのルールは
// Board に、描画は View に、ページは GameUi に住む。

mod Sokoban {

    /// 保持するスナップショット数。エンジンのベンチマークでは1レコードあたり
    /// 約172バイトなので、これでも2MB未満: 無制限アンドゥは事実上タダである。
    pub def historyCap(): Int32 = 10000

    // ── step: ボードを dt 秒だけ進める ──
    // 純粋: キーと時計（dt、このフレームの経過秒）は引数として渡される。スライド
    // が移動している間はキーは無視され、着地した瞬間、まだ押されているキーが次の
    // 1マスを始める —— タップはちょうど1セル動き、押しっぱなしはリズムよくセルか
    // らセルへ滑る、どの画面でも同じ速さで。

    /// 1マスのスライドにかかる秒数: 移動速度を決めるただ1つのつまみ。
    def slideDuration(): Float64 = 0.125

    /// 巻き戻された1手の逆スライドにかかる秒数 —— 歩行スライドの2倍。ゆっくりし
    /// た巻き戻しは重みとして読め、余分な時間は針が回っている間もアラーム時計を
    /// 見やすく保つ。
    def undoDuration(): Float64 = 0.25

    /// 歩行サイクルは1マス滑るごとに1拍（サイクルの0.25）進む。
    def strideBeat(): Float64 = 0.25

    /// 静止中の歩行サイクル（秒あたり）: その場でのゆっくりした行進 —— 歩行時の
    /// 約3分の1のレートで、忙しなくではなく生きているように見せる。
    def idleBeat(): Float64 = 0.75

    pub def step(input: Board.Input, dt: Float64, w: Board.World): Board.World =
        let Board.World.World(b0) = w;
        match b0#slide {
            case Some(s) =>
                // 巻き戻しスライドは独自の、より遅い時計で動く。針は絵が移動する
                // のとちょうど同じだけ回る。
                let dur = if (s#reverse) undoDuration() else slideDuration();
                let progress = dt / dur;
                let b = tickFx(dt, if (s#reverse) progress else 0.0, b0);
                let t = s#t + progress;
                let walked = { walkPhase = fract(b#walkPhase + strideBeat() * progress) | b };
                if (t < 1.0)
                    Board.World.World({ slide = Some({ t = t | s }) | walked })
                else
                    // スライドが着地した: ここで初めてキーボードに発言権が戻る。
                    Board.World.World(Board.beginHop(input, { slide = None | walked }))
            case None =>
                // 立ち止まっているロボットはその場でゆっくり行進する；ホップの開
                // 始は位相を引き継ぐので、脚がカクつかない。
                let b = tickFx(dt, 0.0, b0);
                let marched = { walkPhase = fract(b#walkPhase + idleBeat() * dt) | b };
                Board.World.World(Board.beginHop(input, marched))
        }

    /// 小数部分だけを残す（歩行サイクルは 0..1 で繰り返す）。
    def fract(x: Float64): Float64 = x - Float64.floor(x)

    // ── 巻き戻し時計の経年変化 ──

    /// 時計の経年変化。逆スライドが走っている間は針もそれと共に回り
    /// （spinAdvance = このフレームでのスライドの進捗）、時計は新鮮なまま保たれ
    /// る；そうでなければ、フェードするまでただ古くなっていく。
    def tickFx(dt: Float64, spinAdvance: Float64, b: Board.Board): Board.Board =
        match b#undoFx {
            case None    => b
            case Some(f) =>
                if (spinAdvance > 0.0)
                    { undoFx = Some({ spin = f#spin + spinAdvance, linger = 0.0 }) | b }
                else if (f#linger + dt > Board.clockLinger())
                    { undoFx = None | b }
                else
                    { undoFx = Some({ spin = f#spin, linger = f#linger + dt }) | b }
        }

    def spinOf(fx: Option[Board.UndoFx]): Float64 =
        match fx {
            case Some(f) => f#spin
            case None    => 0.0
        }

    // ── tick: 時間機械込みの、セッション全体の1フレーム ──
    // Worldline は確定した手ごとに1スナップショットを記録する —— これがゲームの
    // 自然な拍であり、決してフレームごとではない。Z は手を1つずつ巻き戻す；巻き
    // 戻しのたびにその手のスライドを逆再生し、次のコマンド（歩行でも巻き戻しで
    // も同様に）は絵が着地したときにだけ受け付けられる: 時間のどちら向きにも共
    // 通の1つの門。

    pub def tick(input: Board.Input, dt: Float64, line: Worldline[Board.World]): Worldline[Board.World] =
        let Board.World.World(b) = Worldline.current(line);
        match b#screen {
            case Board.Screen.Title =>
                if (input#enter) freshLine(Board.playingWorld(1)) else line
            case Board.Screen.Playing =>
                let world = Worldline.current(line);
                if (Board.won(world))
                    // CLEAR はモーダル: Enter と Escape しか聞こえない。絵はまだ
                    // 息をしている —— 勝利のスライドは着地し、時計はフェードする
                    // —— が、歩行と巻き戻しは沈黙する。
                    if (input#enter)
                        (if (b#level < Board.levelCount()) freshLine(Board.playingWorld(b#level + 1))
                         else freshLine(Board.titleWorld()))
                    else if (input#esc)
                        freshLine(Board.titleWorld())
                    else {
                        // お祝いの時計: 紙吹雪はボードが解かれてからどれだけ経っ
                        // たかの純粋な関数である。
                        let Board.World.World(b1) = step(Board.noKeys(), dt, world);
                        Worldline.replaceCurrent(
                            Board.World.World({ clearElapsed = b1#clearElapsed + dt | b1 }), line)
                    }
                else if (input#back)
                    freshLine(Board.titleWorld())
                else
                    playTick(input, dt, line)
        }

    /// 1つの World を巡る真新しい Worldline: どの画面遷移もこうして始まる。以前
    /// の履歴は以前の画面と共に捨てられる。
    def freshLine(w: Board.World): Worldline[Board.World] =
        Worldline.make(w, historyCap())

    /// 実プレイの1フレーム: 移動、履歴へ確定していく手、Z によるその履歴の巻き
    /// 戻し。
    def playTick(input: Board.Input, dt: Float64, line: Worldline[Board.World]): Worldline[Board.World] =
        let world = Worldline.current(line);
        // Z を押している間は歩行キーを取り上げる；巻き戻しが優先権を持つ。
        let moveInput = if (input#undo) Board.noKeys() else input;
        let next = step(moveInput, dt, world);
        if (hopStarted(world, next))
            // 手が確定した: 移動前の World を過去に記録する。
            Worldline.record(next, Worldline.replaceCurrent(normalize(world), line))
        else if (input#undo and not inFlight(next))
            // 門は開いている（何も滑っていない）状態で Z が押されている: 1手巻き
            // 戻す。
            fireUndo(Worldline.replaceCurrent(next, line))
        else
            // ただの移動；現在地点をその場で調整するだけで、履歴は作らない。
            Worldline.replaceCurrent(next, line)

    /// 1手巻き戻す: Store は即座にスナップショットへ戻り、逆スライドが絵を後ろへ
    /// 運ぶ —— ロボットは巻き戻された手の向きを着たまま後ろ向きに滑り、足を引き
    /// ずるように、その間時計は回る；スナップショット自身の向きは着地の瞬間まで
    /// 待つ。
    def fireUndo(line: Worldline[Board.World]): Worldline[Board.World] =
        if (not Worldline.canUndo(line)) line
        else {
            let Board.World.World(l) = Worldline.current(line);
            let line1 = Worldline.undo(line);
            let Board.World.World(r) = Worldline.current(line1);
            let back = Board.World.World({
                slide = Some({ fromCell = l#robot, pushing = l#crates != r#crates,
                               reverse = true, t = 0.0 }),
                walkPhase = l#walkPhase,
                undoFx = Some({ spin = spinOf(l#undoFx), linger = 0.0 })
                | r });
            Worldline.replaceCurrent(back, line1)
        }

    /// 手が確定するのは、ちょうどロボットのセルが変わったときだけ（合法な手はす
    /// べてロボットを動かし、ブロックされた手は何も動かさない）。
    def hopStarted(before: Board.World, after: Board.World): Bool =
        let Board.World.World(a) = before;
        let Board.World.World(z) = after;
        a#robot != z#robot

    def inFlight(w: Board.World): Bool =
        let Board.World.World(b) = w;
        not Option.isEmpty(b#slide)

    /// 履歴に入るもの: 論理的な状態。絵の移動量と巻き戻し時計は過去には残らない。
    def normalize(w: Board.World): Board.World =
        let Board.World.World(b) = w;
        Board.World.World({ slide = None, undoFx = None | b })

    // ── 音: 耳のための投影 ──
    // 4つの生成された wav のうちどれを鳴らすかは純粋であり、両方の Worldline から
    // 読み取れる、このフレームの手についての導出である。実際に鳴らす行為だけが
    // 副作用であり、それは他の境界越えと共に loop に住む。

    /// このフレームがどう聞こえるか: 勝利の一押しはファンファーレ、巻き戻しは
    /// チッと鳴り、確定した手はクレートを押していればドン、歩いただけならピッと
    /// 鳴る。1つのレベルの1ページに限定されるので、画面遷移では無音のまま。
    pub def sfxEvent(before: Worldline[Board.World], after: Worldline[Board.World]): Option[String] =
        let wb = Worldline.current(before);
        let wa = Worldline.current(after);
        let Board.World.World(b) = wb;
        let Board.World.World(a) = wa;
        let samePage = b#screen == Board.Screen.Playing and a#screen == Board.Screen.Playing
            and b#level == a#level;
        if (not samePage) None
        else if (Board.won(wa) and not Board.won(wb)) Some("clear")
        else if (Worldline.pastLength(after) == Worldline.pastLength(before) - 1) Some("undo")
        else if (Worldline.pastLength(after) == Worldline.pastLength(before) + 1)
            (if (a#crates != b#crates) Some("push") else Some("move"))
        else None

    // ── ランチャー: 入力と時計を読む |> tick |> frame、ウィンドウが閉じるまで ──

    pub def start(atlas: FontAtlas): Unit \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead} =
        loop(atlas, GameUi.loadUi(), Worldline.make(Board.initialWorld(), historyCap()),
             { enter = true, esc = true, f1 = false })

    /// キーボードを読むことはプログラムの外側にある何かに触れることであり、シグ
    /// ネチャがそれを語る: `\ GameEngine.Game`。キーが読まれるのはここだけであ
    /// り、この先はただの値である。Enter と Escape のエッジは loop（前フレーム
    /// の状態を保持している）が計算し、判定結果としてここに届く。
    def readInput(enterEdge: Bool, escEdge: Bool): Board.Input \ GameEngine.Game =
        { up    = GameEngine.Game.isKeyPressed(GameEngine.Key.Up),
          down  = GameEngine.Game.isKeyPressed(GameEngine.Key.Down),
          left  = GameEngine.Game.isKeyPressed(GameEngine.Key.Left),
          right = GameEngine.Game.isKeyPressed(GameEngine.Key.Right),
          undo  = GameEngine.Game.isKeyPressed(GameEngine.Key.Z),
          enter = enterEdge,
          back  = GameEngine.Game.isKeyPressed(GameEngine.Key.X),
          esc   = escEdge }

    /// 時計も World の外に住む。エンジンが値をクランプするので、長いカクつき
    /// （あるいは最初のフレーム）がゲームを先へワープさせることは決してない。
    def readDt(): Float64 \ GameEngine.Game =
        Duration.toSeconds(GameEngine.Game.getDeltaTime())

    /// CLEAR パネルが出ている間は、Escape はウィンドウではなくパネルを閉じる
    /// （タイトルへ戻る）。
    def clearModal(w: Board.World): Bool =
        let Board.World.World(b) = w;
        b#screen == Board.Screen.Playing and Board.won(w)

    /// このフレームの音があれば、それを鳴らす。
    def playSfx(before: Worldline[Board.World], after: Worldline[Board.World]): Unit \ GameEngine.Audio =
        match sfxEvent(before, after) {
            case Some(name) => GameEngine.Audio.playAudio(name)
            case None       => ()
        }

    /// ボードの絵と UI ページを合成し、エンジンに渡す。
    def renderFrame(atlas: FontAtlas, ui: UiStore.UiWorld, world: Board.World): Unit \ GameEngine.Game =
        let (drawables, polys) = View.frame(atlas, world);
        let out = UiRender.renderUi(ui, GameUi.designSize());
        GameEngine.Game.renderCommands(
            List.append(drawables, out#drawables), Nil,
            List.append(polys, out#polygons))

    /// loop は3つの値を糸のようにつなぐ: UI store、Worldline、そして前フレームの
    /// キー状態（enter と esc は true から始まるので、起動時にすでに押されてい
    /// るキーは一度離されるまで何も語らない）。1周は: キーを読み、セッションを
    /// tick し、鳴らし、ページを投影し、描く。
    def loop(atlas: FontAtlas, ui: UiStore.UiWorld, line: Worldline[Board.World],
             prev: { enter = Bool, esc = Bool, f1 = Bool }): Unit \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead} =
        let enterDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Enter);
        let escDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Escape);
        let f1Down = GameEngine.Game.isKeyPressed(GameEngine.Key.F1);
        let escEdge = InputEdge.pressed(prev#esc, escDown);
        if (GameEngine.Game.shouldClose()
            or (escEdge and not clearModal(Worldline.current(line)))) ()
        else {
            let advanced = tick(readInput(InputEdge.pressed(prev#enter, enterDown), escEdge), readDt(), line);
            playSfx(line, advanced);
            // F1 は生成済みの Spec を1つ残らずディスクから読み直す: ゲーム実行中
            // に json を編集し、F1 を押せば、その場でページが変わる。
            let uiReloaded = if (InputEdge.pressed(prev#f1, f1Down)) UiSpec.reloadAll(ui) else ui;
            let world = Worldline.current(advanced);
            let uiProjected = GameUi.projectUi(Worldline.pastLength(advanced), world, uiReloaded);
            renderFrame(atlas, uiProjected, world);
            loop(atlas, uiProjected, advanced, { enter = enterDown, esc = escDown, f1 = f1Down })
        }
}
