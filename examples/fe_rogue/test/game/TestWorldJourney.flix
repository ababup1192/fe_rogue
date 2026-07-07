// TestWorldJourney — 実機フル経路の統合 pin。
//
// 注意: モジュール名は実行順（アルファベット順）で snapshot 系（TestUiSnapshots ほか
// AWT フォント初期化を伴うテスト）より **後** に走るように選んでいる。本テストが先に走ると、
// 後続の AWT（java.awt.Toolkit）初期化が -XstartOnFirstThread 環境でまれにデッドロックする
// 事象を観測したため（JVM/AWT 側の制約。先に AWT を初期化させれば回避できる）。
//
// `Game.start()`（本番の handler 配線・BoardQuery 遅延 handler・入力ルータ・gameLoop の
// 固定パイプライン）を、台本（1 フレーム = 押下キー集合）を返す GameEngine.Game handler で
// headless 駆動する。dispatch 関数の直呼びではなく、
//   handleInput（キー差分 → onKeyPressed ルータ）→ physicsProcess → 各 frameStep → renderFrame
// の実経路をフレームごとに通すのが本旨。
//
// 観測は本番の出力チャンネルだけを使う（Game.start の内部状態は外から見えないため）:
//   - renderCommands に渡った描画リスト（タイルが描かれた = ダンジョン到達）
//   - GameEngine.Audio に流れた効果音名（"confirm" = メニュー確定 / "damage"・"miss" 等 = 戦闘発生 /
//     "phase_change" = ターン交代）
//
// 乱数（ダンジョン生成・戦闘ロール）は seed 固定の Math.Random handler で決定論化する。
mod TestWorldJourney {
    import java.util.{Random => JRandom}

    /// 1 フレームぶんの押下キー集合（台本の 1 コマ）。
    type alias FrameKeys = List[GameEngine.Key]

    /// 台本を最後まで回した観測結果。
    ///   frames        — 実際に回ったフレーム数（台本を消化しきった = 途中で落ちていない）。
    ///   sounds        — 鳴った効果音の (フレーム番号, 名前)（時系列）。
    ///   tileFrames    — 背景タイルが 1 枚以上描かれたフレーム数（ダンジョン画面に居た証拠）。
    ///   tilePan       — タイル層スクリーン位置の振れ幅 (x, y)。カメラが動いた（ユニット移動 /
    ///                   敵ターンの注視移動があった）ことの証拠。
    ///   lastDrawables — 最終フレームの sprite/box 描画数（画面が空でない確認用）。
    type alias Journey = {
        frames        = Int32,
        sounds        = List[(Int32, String)],
        tileFrames    = Int32,
        tilePan       = (Float64, Float64),
        lastDrawables = Int32,
        slotAfter     = Option[String]
    }

    // ════════════════════════════════════════════════════════
    // 台本ビルダー（キー押下は「押す 1 フレーム + 離す 1 フレーム」で 1 押下 = 1 発火）
    // ════════════════════════════════════════════════════════

    /// 何も押さないフレームを n 個。
    def idle(n: Int32): List[FrameKeys] =
        List.range(0, n) |> List.map(_ -> (Nil: FrameKeys))

    /// キーを 1 回押す（押下エッジ 1 フレーム + 離す 1 フレーム）。
    def press(key: GameEngine.Key): List[FrameKeys] =
        (key :: Nil) :: (Nil: FrameKeys) :: Nil

    /// キーを n フレーム押しっぱなしにする（長押し / 方向キーのポーリング移動用）。
    def hold(key: GameEngine.Key, n: Int32): List[FrameKeys] =
        List.range(0, n) |> List.map(_ -> key :: Nil)

    // ════════════════════════════════════════════════════════
    // ハーネス（Game.start を台本で headless 駆動する）
    // ════════════════════════════════════════════════════════

    /// 中断セーブのスロットファイル。台本が万一「中断」を確定しても実データを壊さないよう、
    /// runJourney が実行前に内容を退避し、実行後に書き戻す。
    def saveSlotPath(): String = SaveManager.slotPath(SuspendSave.slot())

    /// スロットの現内容（無ければ None）。
    def readSaveSlot(): Option[String] \ Fs.FileRead =
        let result = run { Fs.ReadFile.read(saveSlotPath()) } with Fs.ReadFile.runWithFileRead;
        Result.toOption(result)

    /// スロットへ内容を書き戻す（退避が None = 元々無ければ何もしない）。
    def restoreSaveSlot(saved: Option[String]): Unit \ Fs.FileWrite =
        match saved {
            case Some(content) =>
                run { discard Fs.WriteFile.write({str = content}, saveSlotPath()) }
                    with Fs.WriteFile.runWithFileWrite
            case None => ()
        }

    /// 本番 `Game.start()` を台本で駆動する。フレームの進みは gameLoop 先頭の shouldClose 呼び出しに
    /// 同期させる（台本を 1 コマ消費して false、尽きたら true = 正常終了）。テクスチャ実寸表は
    /// 実 PNG から読む（sprite 描画がテクスチャ登録を要求するため）。
    /// 中断セーブのスロットは実行前に退避し、実行後に書き戻す（実データ保護）。
    def runJourney(seed: Int64, script: List[List[FrameKeys]]): Journey \ {IO, Fs.FileRead, Fs.FileWrite} =
        region rc {
            let savedSlot = readSaveSlot();
            let scriptRef: Ref[List[FrameKeys], rc] = Ref.fresh(rc, List.flatten(script));
            let keysRef: Ref[FrameKeys, rc]         = Ref.fresh(rc, Nil);
            let framesRef: Ref[Int32, rc]           = Ref.fresh(rc, 0);
            let soundsRef: Ref[List[(Int32, String)], rc] = Ref.fresh(rc, Nil);
            let tileFramesRef: Ref[Int32, rc]       = Ref.fresh(rc, 0);
            let lastDrawRef: Ref[Int32, rc]         = Ref.fresh(rc, 0);
            let tileMinRef: Ref[(Float64, Float64), rc] = Ref.fresh(rc, (1.0e9, 1.0e9));
            let tileMaxRef: Ref[(Float64, Float64), rc] = Ref.fresh(rc, (-1.0e9, -1.0e9));
            let texInfo = SnapshotSupport.buildTextureInfo(
                SnapshotSupport.buildTexturePaths(), RenderDescribe.atlasDim());
            let rng = new JRandom(seed);
            run {
                Game.start()
            } with handler GameEngine.Game {
                def shouldClose(k) = match Ref.get(scriptRef) {
                    case Nil        => k(true)
                    case ks :: rest => {
                        Ref.put(rest, scriptRef);
                        Ref.put(ks, keysRef);
                        Ref.put(Ref.get(framesRef) + 1, framesRef);
                        k(false)
                    }
                }
                def getDeltaTime(k)             = k(Duration.millis(16))
                def isKeyPressed(key, k)        = k(List.memberOf(key, Ref.get(keysRef)))
                def renderCommands(sprites, tiles, _polys, k) = {
                    Ref.put(List.length(sprites), lastDrawRef);
                    if (not List.isEmpty(tiles))
                        Ref.put(Ref.get(tileFramesRef) + 1, tileFramesRef)
                    else ();
                    // タイル層のスクリーン位置＝カメラ位置の写し。振れ幅で「カメラが動いた」を観測する。
                    match List.head(tiles) {
                        case Some(t) =>
                            let (mnx, mny) = Ref.get(tileMinRef);
                            let (mxx, mxy) = Ref.get(tileMaxRef);
                            Ref.put((Float64.min(mnx, t#position#x), Float64.min(mny, t#position#y)), tileMinRef);
                            Ref.put((Float64.max(mxx, t#position#x), Float64.max(mxy, t#position#y)), tileMaxRef)
                        case None => ()
                    };
                    k(())
                }
                def initTileBuffer(_, k)        = k((0i32, 0i32))
                def getMousePosition(k)         = k({x = 0.0, y = 0.0})
                def isMouseButtonPressed(_, k)  = k(false)
                def consumeScrollDelta(k)       = k(0.0)
                def getFontAtlas(_, k)          = k(TestUnitFixtures.testFontAtlas())
                def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 240.0, y = 128.0}})
                def getTextureInfo(name, k)     = k(Map.get(name, texInfo))
                def setCursor(_, k)             = k(())
            } with handler GameEngine.Audio {
                def playAudio(name, k)  = {
                    Ref.put((Ref.get(framesRef), name) :: Ref.get(soundsRef), soundsRef);
                    k()
                }
                def stopAudio(_, k)     = k()
                def setVolume(_, _, k)  = k()
                def setLooping(_, _, k) = k()
            } with handler Math.Random {
                def randomFloat64(k) = k(rng.nextDouble())
                def randomInt64(k)   = k(rng.nextLong())
            };
            // 台本が中断セーブを書いた場合の内容（実行後・復元前に読む。退避時と同一なら「書かれていない」）。
            let after = readSaveSlot();
            let slotAfter = if (after != savedSlot) after else None;
            restoreSaveSlot(savedSlot);
            let (mnx, mny) = Ref.get(tileMinRef);
            let (mxx, mxy) = Ref.get(tileMaxRef);
            {frames        = Ref.get(framesRef),
             sounds        = List.reverse(Ref.get(soundsRef)),
             tileFrames    = Ref.get(tileFramesRef),
             tilePan       = (Float64.max(0.0, mxx - mnx), Float64.max(0.0, mxy - mny)),
             lastDrawables = Ref.get(lastDrawRef),
             slotAfter     = slotAfter}
        }

    /// 戦闘でしか鳴らない SE のどれかが鳴ったか（命中 / 回避 / ガード / 必殺 / 魔法 / 撃破）。
    def hasCombatSound(sounds: List[(Int32, String)]): Bool =
        List.exists(pair -> {
            let (_, s) = pair;
            s == "damage" or s == "miss" or s == "guard"
                or s == "critical" or s == "magic" or s == "down_enemy"
        }, sounds)

    // ════════════════════════════════════════════════════════
    // (a) Title 画面で数フレーム回して落ちない
    // ════════════════════════════════════════════════════════

    /// タイトル画面（盤面レス）で 10 フレーム、全 step / Projection / renderFrame が本番配線のまま
    /// 安全に走ることを pin する。タイルは 1 フレームも描かれず（盤面が無い画面でタイル描画ゼロ）、
    /// 画面には描画物がある（タイトル UI が出ている）。
    @Test
    def testTitleFramesRunSafely(): Unit \ {Assert, IO, Fs.FileRead, Fs.FileWrite} =
        let j = runJourney(2026i64, idle(10) :: Nil);
        Assert.assertEq(
            expected = (10, 0, true),
            (j#frames, j#tileFrames, j#lastDrawables > 0))

    // ════════════════════════════════════════════════════════
    // (b) Title → CharacterSelect → Playing → 移動 → 戦闘 が完走する
    // ════════════════════════════════════════════════════════

    /// タイトル確定 → 出撃メンバー 3 人選択 → リーダー確定 → ダンジョン突入 → リーダーを選択して
    /// 盤上を移動 → 行動終了 → ターンスキップ長押しで敵ターンを回す、を数ターン繰り返す台本。
    /// seed 固定で敵（Aggressive）が接近してくるため、途中で戦闘（攻撃 SE）が発生する。
    def journeyScript(): List[List[FrameKeys]] =
        // タイトル: 「はじめから」確定。
        idle(5)
            :: press(GameEngine.Key.Z)
            :: idle(5)
            // 出撃メンバー選択: カード 0/1/2 を選んで出撃ボタン → リーダー確定 → Playing。
            :: press(GameEngine.Key.Z)
            :: press(GameEngine.Key.Right) :: press(GameEngine.Key.Z)
            :: press(GameEngine.Key.Right) :: press(GameEngine.Key.Z)
            :: press(GameEngine.Key.Down)  :: press(GameEngine.Key.Z)
            :: press(GameEngine.Key.Z)
            // ダンジョン構築 + 上部バー演出を待つ。
            :: idle(60)
            // リーダーを選択（PlayerMoving へ）→ 方向キーのポーリング移動で数マス歩く →
            // 移動 tween の完了を待ってから（tween 中の Z は Stay で無視されるため idle を挟む）
            // Z で行動選択ウィンドウ → ↑ で末尾の「たいき」へ回り込み → Z で行動終了。
            :: press(GameEngine.Key.Z)
            :: hold(GameEngine.Key.Right, 30) :: hold(GameEngine.Key.Down, 30)
            :: idle(30)
            :: press(GameEngine.Key.Z)
            :: idle(5)
            :: press(GameEngine.Key.Up)
            :: press(GameEngine.Key.Z)
            :: idle(30)
            // 1 ターン目を締める（ターンスキップ長押し → 敵ターン消化）。
            :: turnSkipRounds(1)
            // 2 ターン目以降: C で集合（行軍）モードに入り、毎ターン「方向キー長押しで移動範囲ぶん歩く →
            // ターンエンド長押し → 敵ターン消化」を方向を変えながら繰り返す（集合はターンを跨いで
            // 自動継続）。盤面を大きく歩き回るうちに敵の部屋へ踏み込み、検知した Aggressive（移動 5）が
            // 追跡してきて、隣接 / 射程に入ると敵の攻撃で戦闘 SE（damage / miss 等）が鳴る。
            :: press(GameEngine.Key.C)
            // seed=2026 の盤面では敵（Wanderer rogue_t1）が党の南西（下の部屋）に居る。
            // 下・左へ行軍して敵の部屋へ踏み込む（壁に当たったターンはその分だけ進まない）。
            :: marchRounds(GameEngine.Key.Down, 2)
            :: marchRounds(GameEngine.Key.Left, 2)
            :: marchRounds(GameEngine.Key.Down, 3)
            :: marchRounds(GameEngine.Key.Left, 1)
            :: marchRounds(GameEngine.Key.Down, 2)
            // 検知した敵が追跡・攻撃してくるのをターンスキップで待つ（戦闘 SE がここで鳴る）。
            :: turnSkipRounds(4)
            // 締め: X で集合を解除（集合中なら開始位置へ巻き戻して個別行動へ・素のカーソル中なら無反応）
            // → カーソルを空マスへ → 空マスメニュー → ↑ で末尾「ちゅうだん」→ 確認モーダル「はい」で
            // 中断セーブ（SuspendSave 経路の完走）。スロットの実ファイルは runJourney が退避・復元する。
            :: press(GameEngine.Key.X)
            :: idle(10)
            :: hold(GameEngine.Key.Right, 25)
            :: idle(10)
            :: press(GameEngine.Key.Z)
            :: idle(5)
            :: press(GameEngine.Key.Up)
            :: press(GameEngine.Key.Z)
            :: idle(5)
            :: press(GameEngine.Key.Z)
            :: idle(30)
            :: Nil

    /// ターンスキップ長押し（LeftShift）+ 敵ターン消化待ち、を n ラウンドぶん並べる。
    /// 敵ターンは 1 体ずつ演出込みで進むため、待ちは長め（400 フレーム ≒ 6.4 秒）に取る。
    def turnSkipRounds(n: Int32): List[FrameKeys] =
        List.range(0, n) |> List.flatMap(_ ->
            List.flatten(hold(GameEngine.Key.LeftShift, 60) :: idle(400) :: Nil))

    /// 集合（行軍）中の 1 ターンぶんの行軍ラウンド × n。
    /// 方向キー長押しで移動範囲ぶん歩く → 少し待つ → ターンエンド長押し → 敵ターン消化待ち。
    def marchRounds(dir: GameEngine.Key, n: Int32): List[FrameKeys] =
        List.range(0, n) |> List.flatMap(_ ->
            List.flatten(hold(dir, 80) :: idle(20)
                :: hold(GameEngine.Key.LeftShift, 60) :: idle(400) :: Nil))

    /// 実機フル経路の完走 pin: 台本を最後まで消化し（途中で落ちない）、ダンジョンに到達して
    /// タイルが描かれ、メニュー確定音が鳴り、行軍で敵の部屋へ踏み込んだ後のどこかのターンで
    /// 戦闘 SE が鳴り、最後に中断セーブ（SuspendSave 経路）が書ける。
    @Test
    def testJourneyTitleToCombatCompletes(): Unit \ {Assert, IO, Fs.FileRead, Fs.FileWrite} =
        let script = journeyScript();
        let total = List.length(List.flatten(script));
        let j = runJourney(2026i64, script);
        Assert.assertEq(
            expected = (total, true, true, true, true),
            (j#frames,
             j#tileFrames > 0,
             List.exists(pair -> snd(pair) == "confirm", j#sounds),
             hasCombatSound(j#sounds),
             Option.nonEmpty(j#slotAfter)))
}
