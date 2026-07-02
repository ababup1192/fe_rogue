/// WorldDriver — アプリ内 ECS glue。ゲーム側から World（各 store の単一権威）へ触れる
/// 経路を 1 か所に集約する。役割は 2 つ:
///   1. store の掃除 / seed choke — フロア再構築やダンジョン退場で走らせる `World.Cmd` を
///      名前付き関数にまとめ、`SceneSetup` / `Game.applyPhaseChange` から宣言的に呼ぶ。
///      これにより「どのタイミングで World を掃除 / 焼くか」だけが呼び出し側に残り、
///      `World.Cmd` の直書きは本ファイルに閉じる。
///   2. 毎フレームの World System パイプライン（`stepFrame`）— gameLoop から `World -> World`
///      の System 実行を切り出し、gameLoop を固定パイプラインの純配線に保つ。
mod WorldDriver {

    /// フロア配置物（宝箱 / 床アイテム）・探索記憶（ミニマップ）・ユニット store を掃除する。
    /// フロア再構築（通常生成 / スナップショット復元）の前段で呼ぶ。scene 再構築での自動 prune は
    /// 廃止＝明示 Cmd で掃除し、この直後の spawn が seed し直す。
    pub def clearFloorStores(): Unit \ World.Command =
        World.Command.emit(World.Cmd.ClearChests);
        World.Command.emit(World.Cmd.ClearItems);
        World.Command.emit(World.Cmd.ClearVisited);
        World.Command.emit(World.Cmd.ClearUnits)

    /// ダンジョン退場（Title / CharacterSelect へ抜ける）時に走らせる掃除。
    /// ユニット store を落とし、地形 read-model（toBoard の壁 / サイズ源）も無効化する。
    pub def exitDungeon(): Unit \ World.Command =
        World.Command.emit(World.Cmd.ClearUnits);
        World.Command.emit(World.Cmd.SetMapSnapshot(None))

    /// build choke の末尾で呼ぶ地形 seed。マップノード再構築の世代を +1（gameLoop の tile bake
    /// トリガ＝新フロアのタイルを World へ焼く）し、地形 read-model（toBoard の壁 / サイズ源）を
    /// 現在 scene から World へ入れる。scene をそのまま返す。
    pub def bakeMap(scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        World.Command.emit(World.Cmd.BumpTileGen);
        World.Command.emit(World.Cmd.SetMapSnapshot(Some(BoardSnapshot.mapSnapshotOf(scene))));
        scene

    /// 毎フレームの World System パイプラインを 1 本にまとめる。gameLoop の post-process scene
    /// （`next`）と mid-frame 権威 World（`current`＝worldRef 値）を受け、次フレームへ持ち越す
    /// `(world2, synced)` を返す。`prev` は前フレーム World で tileGen 差分判定（＝今フレーム
    /// マップ再構築が走ったか）に使う。region の worldRef は top-level から触れないため値渡し。
    ///
    /// パイプライン:
    ///   attackTarget parity 検査 → refreshMirror → tile bake（再構築時のみ）→ stepWorld
    ///   → phase parity 検査 → marker 同期 → player/enemy data parity 検査
    pub def stepFrame(current: World, prev: World, dt: Duration.Duration,
                       next: Scene[NodeTag]): (World, Scene[NodeTag]) \ {IO, TurnPhase.State} =
        // 位置・hp・isDying・alerted・progress・bottleUsed・prevPos・followUpUsed・waited は World 権威。
        // ATTACKTARGET DIFF（attackTargetId）は combat 解決の同期キャリアで恒久 dual-write ゆえ
        // invariant guard として残す。write 漏れ（Cmd.SetWaited 抜け）は「駒が灰色にならない/行動済みに
        // ならない」可視バグとして現れる。invariant は unit test でも継続検証する。
        match World.attackTargetMismatches(current, next) {
            case Nil => ()
            case ms  => println("[ATTACKTARGET DIFF] ${ms}")
        };
        // refreshMirror は frame カウンタを進めるだけ。
        let world1 = World.refreshMirror(current);
        // マップ再構築（tileGen 変化＝`BumpTileGen` が今フレーム走った）時のみ、新フロアのタイルハンドルを
        // scene から World へ bake する。`prev` は前フレームの gen・`world1` は今フレーム gen ゆえ、両者の差＝
        // 「今フレーム再構築された」。以後は preserve（毎フレーム走査なし）。階段降り / 全滅 restart /
        // 中断復元 / ダンジョン突入を漏れなく捕捉。
        let world1b = if (World.tileGenOf(world1) != World.tileGenOf(prev))
                          World.setTileLayers(MapScene.tileLayerHandles(next), world1)
                      else world1;
        // **System パイプライン段**。ロジックを `World -> World` の System で回す seam。
        // stepWorld は現在 moveAnim を実時間 dt で進める＝engine tween と lockstep 同期。
        // 以後の World→World System はここに足す。
        let (world2, moved) = World.stepWorld(world1b, Duration.toSeconds(dt));
        // phase は `TurnPhase.State` handler が `put` のたび `Cmd.SetPhase` で World へ dual-write 済み
        // ＝World.turnPhase は command 由来（全 put サイトを handler 1 箇所で被覆）。並走 assert は
        // command 由来 phase と State の乖離（write 漏れ）を検出する＝dual-write ゆえ無音だが、将来
        // dual-write を割る時のガード。
        if (World.turnPhaseOf(world2) != Game.simPhaseOf(TurnPhase.State.get()))
            println("[F2 PHASE DIFF] world=${World.turnPhaseOf(world2)} state=${Game.simPhaseOf(TurnPhase.State.get())}")
        else ();
        // 移動した entity の marker を renderPos に合わせる（marker 単一権威）。返す synced は次フレームへ
        // 永続。fx は renderPopups/renderExplosions が直描き（ノード無し）。
        let synced = RenderWorld.syncMarkers(moved, next);
        // twin parity 検査は scene が World 由来値で出揃った後に置く。dual-write 系（weapons/staves/
        // statuses 等）は scene が process 値のままゆえ「World store == scene」の coverage を維持する。
        match World.playerDataMismatches(world2, synced) {
            case Nil => ()
            case ms  => println("[PLAYERDATA DIFF] ${ms}")
        };
        match World.enemyDataMismatches(world2, synced) {
            case Nil => ()
            case ms  => println("[ENEMYDATA DIFF] ${ms}")
        };
        (world2, synced)
}
