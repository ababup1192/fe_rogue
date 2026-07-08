/// WorldSetup — World / UI 組み立ての単一の家。ゲームの全画面（ダンジョン本編 /
/// 進入時スナップショット記録）の構築をここに集約する。`GameLifecycle`（フロア遷移 /
/// 全滅復帰 / 中断再開）と `Game.applyPhaseChange`（画面分岐）は、いつ何を組むかだけを決めて
/// 本ファイルの外向き API を呼ぶ。
///
/// 外向き API は `buildCurrentFloor`（乱数生成）/ `rebuildFloorFromSnapshot`（決定論復元）/
/// `buildAndRecord`（構築 + spawn 記録）。`buildPlayingFloor` を直接呼ぶと snapshot が記録
/// されないため、通常は `buildAndRecord` 経由を使う。
///
/// 各 spawn は **順序が意味を持つ**:
///   - マップは build 冒頭で `MapSetup` が値として確定し World へ seed する。
///     以降の spawn 系は World（terrainOf / placementsOf / spawnGridOf）を読む
///   - PlayerScene / EnemyScene は World の placements に従ってスポーン
///   - MoveRangeScene は SelectedPlayer 状態を読むが起動時は未選択なので no-op
///   - カメラの状態は World の cameraSmoothPos。`setupHudAndDrivers` が駒 spawn 後に
///     `CameraScene.snapToParty` でパーティ先頭へスナップする
///   - 階段は全ユニット・アイテム配置後（避けるため最後）、宝箱は階段確定後
///
/// カタログ束 (`GameLifecycle.Catalogs`) は `Game.start` でロード済みのユニット / 敵 / フロア
/// 定義。PlayerScene と EnemyScene にプール定義 (`party` / `enemyTier1`) を辿らせる。
mod WorldSetup {

    /// プレイ用フロアを 1 回で組み立てる。`MapSetup.build` が `IO` を要求するため
    /// 戻り値の Aef にも `IO` を含める。
    /// **直接呼ぶのは `buildAndRecord` だけ** にする (起動 / リビルド時の snapshot 記録漏れ
    /// を防ぐため、外向き API は `buildAndRecord` を使う)。
    pub def buildPlayingFloor(catalogs: GameLifecycle.Catalogs,
                                floor: FloorCatalog.FloorResource): Unit
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, CursorState.State, ArrowCursorState.State, PartySelection.State, World.Command, World.WorldQuery,
                TopBarState.State, UiWorldState.State, RangeOverlayState.State} =
        // 前フロアの配置物（宝箱/床アイテム）・探索記憶（ミニマップ）・ユニット store を掃除する
        // （明示 Cmd。この直後の spawn が seed し直す）。
        WorldDriver.clearFloorStores();
        // マップを値として確定して World へ seed する。以降の spawn 系（Player / Enemy /
        // アイテム / 宝箱 / 階段）とフォグは World の地形 / placements / spawnGrid を読む。
        MapSetup.seed(MapSetup.build(floor));
        PlayerScene.add(catalogs#players, catalogs#staves, catalogs#consumables);
        EnemyScene.add(catalogs#enemies, catalogs#weapons, catalogs#rings, floor);
        // 部屋の床に武器/杖/消耗品/指輪をランダムドロップ
        GroundItems.add(catalogs#players, catalogs#staves, catalogs#consumables, catalogs#rings, floor);
        // 駒非依存の HUD / メニュー群（rebuild と共有）
        setupHudAndDrivers(floor#label, floor#name);
        // 全ユニット配置後に階段を床のランダムセルへ置く (駒・アイテムを避けるため最後)
        Stairs.placeRandom();
        // 階段確定後に宝箱を配置 (駒・アイテム・階段を避けるため階段の後)
        Chests.add(catalogs#chests, catalogs#players, catalogs#staves, catalogs#consumables, catalogs#rings, floor)
        // フォグの点灯（スポーン部屋の明るさ・敵可視）は描画/判定時に holesNow から導出する。
        // ミニマップは `RenderWorld.renderMinimap` が World から直描きする。

    /// 駒（味方 / 敵 / アイテム / 宝箱 / 階段）に依存しない HUD・メニュー群をまとめて初期化する。
    /// `buildPlayingFloor`（通常生成）と `rebuildFloorFromSnapshot`（スナップショット復元）が共有し、
    /// **初期化順序とメンバーを 1 か所に固定**する（漏れ・順序ズレ・二重初期化を防ぐ）。
    /// マップ seed の後、駒配置の後に呼ぶ前提。
    /// `label` はフロア番号表示（"1F" 等）、`name` はフロア名（"始まりの洞窟" 等。空可）。
    def setupHudAndDrivers(label: String, name: String): Unit
            \ {SelectedPlayer.State, CursorState.State, ArrowCursorState.State, World.WorldQuery, World.Command, TopBarState.State, UiWorldState.State, RangeOverlayState.State} =
        // 範囲オーバーレイ resource を空へ（前フロアの残存を一掃してから MoveRange を組み直す）。
        RangeOverlayState.State.put(RangeOverlayState.empty());
        // カメラをパーティ先頭へスナップする（カメラの状態は World の cameraSmoothPos）。
        // PlayerScene.add が World へ位置を seed した後なので、パーティ先頭の位置を World から読める。
        CameraScene.snapToParty();
        MoveRangeScene.add();       // SelectedPlayer 未設定なら no-op
        CursorScene.add();
        ArrowCursorScene.add();     // 杖発射方向の矢印カーソル (初期は非表示)
        // 敵ターン進行（EnemyTurnDriver）と集合「階段で離脱」（StairsExitDriver）は
        // gameLoop が明示 System として毎フレーム step を呼ぶ。
        // ユニット簡易カード・行動選択ウィンドウ・武器選択ウィンドウ・アイテム選択ウィンドウ・
        // 物交換ウィンドウ・中断確認モーダル・戦闘予報ミニウィンドウ・レベルアップ演出パネル・
        // ログ HUD・アイテム取得ポップアップ・ターンスキップゲージは World-entity UI
        // （起動時 spawn ＋ 各 frameStep 駆動）。
        TopBarUi.enter(label, name)   // 上部フェイズバー（World-entity UI・フロア設定 + 可視化 + 状態初期化）
        // BGM は attachBgm（フロア構築後の直接 Audio 呼び出し）が設定する。

    /// プレイ用フロアを組み立て + 初期 spawn 一覧 (敵 / 味方) を `InitialSpawns` に保存する。
    /// 起動時と GameOver リビルド時の両方が必ず通る経路。これで「フロア構築」と
    /// 「ゲームオーバー復帰用のスポーン記録」が必ず同じタイミングで揃う。
    pub def buildAndRecord(catalogs: GameLifecycle.Catalogs,
                            floor: FloorCatalog.FloorResource): Unit
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, CursorState.State, ArrowCursorState.State, InitialSpawns.State, PartySelection.State, World.Command,
                World.WorldQuery, TopBarState.State, UiWorldState.State, RangeOverlayState.State} =
        buildPlayingFloor(catalogs, floor);
        InitialSpawns.State.put({
            enemies = EnemyScene.snapshotSpawns(),
            players = PlayerScene.snapshotSpawns()
        });
        attachBgm()

    /// BGM の音量 / ループを OpenAL に反映する。フロア構築のたびに呼ぶ（冪等）。
    /// 自動再生はしない（プレイ中の BGM 再生開始は現状使っていない）。
    def attachBgm(): Unit \ GameEngine.Audio =
        GameEngine.Audio.setVolume("bgm", 0.02f32);
        GameEngine.Audio.setLooping("bgm", true)

    /// `FloorProgress` が指す現在フロアを解決して build + spawn snapshot 保存する。
    /// 起動時 / 全滅リスタート / クリア後ループの共通エントリ。
    pub def buildCurrentFloor(catalogs: GameLifecycle.Catalogs): Unit
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, CursorState.State, ArrowCursorState.State, InitialSpawns.State, FloorProgress.State,
                PartySelection.State, FloorSnapshot.State, World.Command, World.WorldQuery,
                TopBarState.State, UiWorldState.State, RangeOverlayState.State} =
        let floor = FloorCatalog.get(FloorProgress.State.get(), catalogs#floors);
        buildAndRecord(catalogs, floor);
        recordFloorEntry(catalogs)

    // ────────────────────────────────────────────────────────
    // フロアスナップショット（全滅時の「そのフロアの最初から」復元 / 中断土台）
    // ────────────────────────────────────────────────────────

    /// 現在のフロア状態を `FloorSnapshot.T`（カタログ id ＋ 動的値の純粋データ）に射影する。
    /// マップは Plan、駒/アイテム/宝箱/階段は各モジュールの captureSnaps で id 化して集約する。
    pub def captureFloorSnapshot(catalogs: GameLifecycle.Catalogs): FloorSnapshot.T
            \ {FloorProgress.State, World.WorldQuery} =
        ({floorId = FloorProgress.State.get(),
          // マップの Plan は World.mapLayout（build choke の SetMapLayout 由来）から読む。
          mapPlan  = World.mapPlanOf(World.WorldQuery.get()),
          players  = PlayerScene.captureSnaps(catalogs#weapons, catalogs#staves,
                                               catalogs#consumables, catalogs#rings),
          enemies  = EnemyScene.captureSnaps(catalogs#weapons, catalogs#rings),
          items    = GroundItems.captureSnaps(),
          chests   = Chests.captureSnaps(),
          // 階段セルは World.stairsPos（World 権威）から読む。
          stairs   = World.stairsPosOf(World.WorldQuery.get())}: FloorSnapshot.T)

    /// 進入時スナップショットを `FloorSnapshot.State` に保存する。
    /// 各フロア進入点（`buildCurrentFloor` / `GameLifecycle.advanceFloor`）の末尾で呼ぶ。
    pub def recordFloorEntry(catalogs: GameLifecycle.Catalogs): Unit
            \ {FloorProgress.State, FloorSnapshot.State, World.WorldQuery} =
        FloorSnapshot.State.put(captureFloorSnapshot(catalogs))

    /// 保存済みスナップショットから **乱数を使わず** フロアを再構築する。`buildPlayingFloor` と同じ
    /// スキャフォールド順序で、マップ/駒/アイテム/宝箱/階段だけを from-snapshot の決定論配置に差し替える。
    /// audio は `attachBgm` で再設定する。
    pub def rebuildFloorFromSnapshot(catalogs: GameLifecycle.Catalogs, snap: FloorSnapshot.T): Unit
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, SelectedPlayer.State, CursorState.State, ArrowCursorState.State, World.Command,
                World.WorldQuery, TopBarState.State, UiWorldState.State, RangeOverlayState.State} =
        let floor = FloorCatalog.get(snap#floorId, catalogs#floors);
        // 前フロア/前 run の配置物・探索記憶・ユニット store を掃除してから addFromSnaps で再 spawn する
        // （明示 Cmd。addFromSnaps より前が必須）。
        WorldDriver.clearFloorStores();
        // 保存済み Plan からマップを乱数なしで確定して World へ seed する（buildPlayingFloor と同じ choke）。
        MapSetup.seed(MapSetup.buildFromPlan(snap#mapPlan));
        PlayerScene.addFromSnaps(snap#players, catalogs#players, catalogs#staves,
                                  catalogs#consumables, catalogs#rings);
        EnemyScene.addFromSnaps(snap#enemies, catalogs#enemies, catalogs#weapons, catalogs#rings);
        GroundItems.addFromSnaps(snap#items, catalogs#players, catalogs#staves,
                                 catalogs#consumables, catalogs#rings);
        setupHudAndDrivers(floor#label, floor#name);  // buildPlayingFloor と同じ HUD 群を共有
        placeStairsFromSnap(snap#stairs);
        Chests.addFromSnaps(snap#chests, catalogs#chests, catalogs#players,
                            catalogs#staves, catalogs#consumables, catalogs#rings);
        attachBgm()

    /// 保存済み階段位置があればそのセルに階段を確定配置する（無ければ何もしない）。
    def placeStairsFromSnap(stairs: Option[{x = Int32, y = Int32}]): Unit \ World.Command =
        match stairs {
            case Some(cell) => Stairs.placeAt(cell)   // placeAt が Cmd.SetStairs を emit（World 権威）
            case None       => ()
        }

    // ────────────────────────────────────────────────────────
    // 画面（GamePhase）ごとの組み立て。`Game.applyPhaseChange` が phase 差分で 1 つを呼ぶ。
    // ────────────────────────────────────────────────────────

    /// タイトル画面を組む。ダンジョン外へ出るので World のユニット store と地形 read-model を掃除する。
    /// 見た目は World-entity UI（TitleMenuUi）が持ち、進入処理（再開可否の再判定 +
    /// 可視化）を `TitleMenuUi.enter` に任せる。
    pub def buildTitle(): Unit
            \ {Fs.FileRead, World.Command, TitleMenuState.State, UiWorldState.State} =
        WorldDriver.exitDungeon();
        TitleMenuUi.enter();   // タイトル画面（World-entity UI・再開可否の確定 + 可視化）
        TopBarUi.leave()       // ダンジョン外では上部バーを隠す

    /// 出撃メンバー選択画面を組む。タイトルと同じくダンジョン外なので World を掃除する。
    /// 見た目は World-entity UI（CharacterSelectUi）が持ち、進入処理（候補の
    /// 初期化 + 可視化 + 初期描画）を `CharacterSelectUi.enter` に任せる。
    pub def buildCharacterSelect(catalogs: GameLifecycle.Catalogs): Unit
            \ {GameEngine.Game, World.Command, CharacterSelectState.State, UiWorldState.State} =
        WorldDriver.exitDungeon();
        CharacterSelectUi.enter(UnitCatalog.pool("players", catalogs#players));  // 選択画面（候補 put + 可視化 + 初期描画）
        TopBarUi.leave();      // ダンジョン外では上部バーを隠す
        TitleMenuUi.leave()    // タイトル画面（World-entity UI）を隠す

    /// 現在フロアのダンジョンを組む。タイトル由来 ＋ スナップショット有り ＝ 中断再開で、
    /// `FloorSnapshot.State` の snapshot から **乱数なし** で決定論再構築する（`buildCurrentFloor` は
    /// 乱数を消費して別マップになるため通さない）。それ以外（CharacterSelect 由来 ＝ 新規ラン、または
    /// 防御的に snapshot 無し）は通常生成。`prevPhase` は遷移元画面。
    pub def buildPlaying(catalogs: GameLifecycle.Catalogs, prevPhase: GamePhase): Unit
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, SelectedPlayer.State, CursorState.State, ArrowCursorState.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State, FloorSnapshot.State,
                World.Command, World.WorldQuery,
                TopBarState.State, UiWorldState.State, RangeOverlayState.State} =
        // タイトル / 選択画面（World-entity UI）を隠してからダンジョンを組む（Title 由来の中断再開・
        // CharacterSelect 由来の新規ランのどちらでも前画面が残らないように）。
        match (prevPhase, FloorSnapshot.State.get()) {
            case (GamePhase.Title, Some(snap)) =>
                GameLogger.playerLog("中断データから再開");
                rebuildFloorFromSnapshot(catalogs, snap)
            case _ =>
                GameLogger.playerLog("T1 味方のターン");
                buildCurrentFloor(catalogs)
        };
        TitleMenuUi.leave();
        CharacterSelectUi.leave()
}
