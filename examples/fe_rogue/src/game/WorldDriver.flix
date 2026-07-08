/// WorldDriver — アプリ内 ECS glue。ゲーム側から World（各 store の単一権威）へ触れる
/// 経路を 1 か所に集約する。役割は 2 つ:
///   1. store の掃除 / seed choke — フロア再構築やダンジョン退場で走らせる `World.Cmd` を
///      名前付き関数にまとめ、`WorldSetup` / `Game.applyPhaseChange` から宣言的に呼ぶ。
///      これにより「どのタイミングで World を掃除 / 焼くか」だけが呼び出し側に残る
///      （マップ系の seed / 掃除 Cmd は `MapSetup` が持つ）。
///   2. 毎フレームの World System パイプライン（`stepFrame`）— gameLoop から `World -> World`
///      の System 実行を切り出し、gameLoop を固定パイプラインの純配線に保つ。
///   3. World ランタイム handler の注入（`withWorld`）と TurnPhase↔World の境界写像（`simPhaseOf`）。
mod WorldDriver {

    /// 19-case `TurnPhase.Phase`（World 権威）から 3-case `SimPhase` を導出する写像。
    /// メニュー遷移・演出待ち系は全て「味方ターン」配下＝`PlayerTurn`（細分は 19-case が持つ）。
    /// `World.PhaseQuery.phase`（3-case read seam）が使う。
    pub def simPhaseOf(phase: TurnPhase.Phase): SimPhase = match phase {
        case TurnPhase.Phase.EnemyTurn => SimPhase.EnemyTurn
        case TurnPhase.Phase.GameOver  => SimPhase.GameOver
        case _                          => SimPhase.PlayerTurn
    }

    /// World ランタイムの読み書き seam をまとめて注入する handler コンビネータ
    /// （`Tween.withScheduler` / `EnemyTurn.withQueue` と同流儀）。thunk のスコープ内で
    /// `BoardQuery` / `World.Command` / `World.StatusQuery` / `World.PhaseQuery` / `World.WorldQuery` /
    /// `World.RngDraw` が解決される。`worldRef`（各 store の単一権威）は `Game.start` が region で確保し、
    /// gameLoop が毎フレーム頭で最新化する共有窓口ゆえ、コンビネータ内では作らず引数で受け取る。
    /// CustomEffects handler（深部の emit 元）より **外側** に置くこと。
    pub def withWorld(worldRef: Ref[World, r]):
            (Unit -> a \ ef) -> a \
            (ef - BoardQuery - World.Command - World.StatusQuery - World.PhaseQuery
                - World.WorldQuery - World.RngDraw) + r + Math.Random =
        thunk -> run {
            thunk()
        } with handler BoardQuery {
            // 盤面読み取りを World 由来に（位置権威＝World）。pieces は worldRef（`Cmd.Move` のみ由来・
            // mid-frame 最新）、map（地形）は World.mapSnapshot（build choke の SetMapSnapshot 由来）。
            // 盤面レス画面での board() 呼び出しは配線ミスとして即落とす（読み手は存在ゲートを先に通す約束）。
            def board(k) = match World.boardOf(Ref.get(worldRef)) {
                case Some(b) => k(b)
                case None    => bug!("BoardQuery.board: terrain not seeded (board-less screen)")
            }
        } with handler World.Command {
            // store 書き込み（Bevy Commands）。深い scene コードの emit を worldRef へ即時適用。
            def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(worldRef)), worldRef); k() }
        } with handler World.StatusQuery {
            // statusEffects 読み込み（Bevy Query）。EntityRef で引く faction 非依存の read seam。
            def statusEffects(ref, k) = k(World.statusEffectsOf(ref, Ref.get(worldRef)))
        } with handler World.PhaseQuery {
            // turn phase の 3-case sim-phase を worldRef の 19-case 権威から導出する read seam。
            def phase(k) = k(simPhaseOf(World.turnPhaseOf(Ref.get(worldRef))))
        } with handler World.WorldQuery {
            // 現 World スナップショット（worldRef）を返す汎用 read seam。フラグ reader 共通窓口。
            def get(k) = k(Ref.get(worldRef))
        } with handler World.RngDraw {
            // live combat ロールの chokepoint。0..99 reduction は `Prng.unitToPercent` 一本に集約
            // （live も Prng/oracle も同一本体＝数値 bit-identical を型で保証）。source だけ live=Math.Random。
            // worldRef の seeded PRNG は進めない（PRNG は test/trace 専用）。
            def nextPercent(k) = k(Prng.unitToPercent(Math.Random.randomFloat64()))
        }

    /// フロア配置物（宝箱 / 床アイテム）・探索記憶（ミニマップ）・ユニット store を掃除する。
    /// フロア再構築（通常生成 / スナップショット復元）の前段で呼ぶ。
    /// 明示 Cmd で掃除し、この直後の spawn が seed し直す。
    pub def clearFloorStores(): Unit \ World.Command =
        World.Command.emit(World.Cmd.ClearChests);
        World.Command.emit(World.Cmd.ClearItems);
        World.Command.emit(World.Cmd.ClearVisited);
        World.Command.emit(World.Cmd.ClearUnits)

    /// ダンジョン退場（Title / CharacterSelect へ抜ける）時に走らせる掃除。
    /// ユニット store を落とし、マップ store（地形 read-model / Plan / タイルハンドル）も無効化する。
    pub def exitDungeon(): Unit \ World.Command =
        World.Command.emit(World.Cmd.ClearUnits);
        MapSetup.clear()

    /// 毎フレームの World System パイプラインを 1 本にまとめる。mid-frame 権威 World
    /// （`current`＝worldRef 値）を受け、次フレームへ持ち越す world を返す。
    /// region の worldRef は top-level から触れないため値渡し。
    ///
    /// パイプライン: refreshMirror → stepWorld
    pub def stepFrame(current: World, dt: Duration.Duration): World =
        // refreshMirror は frame カウンタを進めるだけ。タイルハンドルは build choke の
        // `Cmd.SetTileLayers` が直接 seed する（フレーム内の差分 bake は無い）。
        let world1 = World.refreshMirror(current);
        // **System パイプライン段**。ロジックを `World -> World` の System で回す seam。
        // stepWorld は現在 moveAnim を実時間 dt で進める＝engine tween と lockstep 同期。
        // 補間結果（MarkerMove）は捨てる: 描画位置は render 側が `World.visualPosOf` で
        // renderPos store から直接導出する（marker への書き戻しは持たない）。
        // 以後の World→World System はここに足す。
        // phase は World 単一権威（`TurnPhase.State` facade が World.turnPhase へ直接書く）ゆえ
        // 乖離の余地が無く parity 検査は不要（かつて 3-case mirror と dual-write していた頃の名残を撤去）。
        let (world2, _moved) = World.stepWorld(world1, Duration.toSeconds(dt));
        world2
}
