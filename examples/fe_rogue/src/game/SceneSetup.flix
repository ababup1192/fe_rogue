/// SceneSetup — UI / Scene ツリー組み立ての単一の家。ゲームの全画面（ダンジョン本編 /
/// 進入時スナップショット記録）の scene 構築をここに集約する。`GameLifecycle`（フロア遷移 /
/// 全滅復帰 / 中断再開）と `Game.applyPhaseChange`（画面分岐）は、いつ何を組むかだけを決めて
/// 本ファイルの外向き API を呼ぶ。
///
/// 外向き API は `buildCurrentFloor`（乱数生成）/ `rebuildFloorFromSnapshot`（決定論復元）/
/// `buildAndRecord`（構築 + spawn 記録）。`buildPlayingScene` を直接呼ぶと snapshot が記録
/// されないため、通常は `buildAndRecord` 経由を使う。
///
/// 各 Scene の `add` は **順序が意味を持つ**:
///   - MapScene が先 (他 Scene が `worldPath()` / `getMapLayer()` を参照する)
///   - DamagePopupFx は World 配下の親ノードを必要とするため Map の直後
///   - PlayerScene / EnemyScene は MapScene の placements に従ってスポーン
///   - MoveRangeScene は SelectedPlayer 状態を読むが起動時は未選択なので no-op
///   - Camera は最後に追加して全プレイヤー出揃った後に追従開始
///   - UI 系 (WeaponMenu / ActionMenu / BattlePanel / UnitCard) は最後 (描画前面)
///
/// カタログ束 (`GameLifecycle.Catalogs`) は `Game.start` でロード済みのユニット / 敵 / フロア
/// 定義。PlayerScene と EnemyScene にプール定義 (`party` / `enemyTier1`) を辿らせる。
mod SceneSetup {

    /// プレイ用シーンを 1 回で組み立てる。`MapScene.add` が `IO` を要求するため
    /// 戻り値の Aef にも `IO` を含める。
    /// **直接呼ぶのは `buildAndRecord` だけ** にする (起動 / リビルド時の snapshot 記録漏れ
    /// を防ぐため、外向き API は `buildAndRecord` を使う)。
    pub def buildPlayingScene(catalogs: GameLifecycle.Catalogs,
                                floor: FloorCatalog.FloorResource): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, CursorState.State, ArrowCursorState.State, PartySelection.State, World.Command, World.WorldQuery,
                TopBarState.State, UiWorldState.State} =
        // 前フロアの配置物（宝箱/床アイテム）・探索記憶（ミニマップ）・ユニット store を掃除する
        // （scene 再構築での自動 prune は廃止＝明示 Cmd。この直後の spawn が seed し直す）。
        WorldDriver.clearFloorStores();
        Scene.empty()
            |> MapScene.add(floor)
            |> FogScene.add             // 常駐 FogDriver（暗幕は renderFog 直描き）
            // ↑ FogDriver は EnemyTurnDriver より先に追加する（preorder で同フレーム先に process される）。
            //   EnemyTurnDriver.endTurn の集合自動継続判定 anyVisibleEnemy が「同フレーム最新の
            //   フォグ可視（applyFog 適用後）」を読めるのはこの add 順前提。順序を入れ替えると 1 フレーム
            //   古い可視値で判定してしまうので注意。
            |> PlayerScene.add(catalogs#players, catalogs#staves, catalogs#consumables)
            |> EnemyScene.add(catalogs#enemies, catalogs#weapons, catalogs#rings, floor)
            |> GroundItems.add(catalogs#players, catalogs#staves, catalogs#consumables, catalogs#rings, floor)   // 部屋の床に武器/杖/消耗品/指輪をランダムドロップ
            |> addHudAndDrivers(floor#label, floor#name)  // 駒非依存の HUD / 常駐ドライバ / メニュー群（rebuild と共有）
            // 全ノード配置後に階段を床のランダムセルへ置く (駒・アイテムを避けるため最後)
            |> Stairs.placeRandom
            // 階段確定後に宝箱を配置 (駒・アイテム・階段を避けるため階段の後)
            |> Chests.add(catalogs#chests, catalogs#players, catalogs#staves, catalogs#consumables, catalogs#rings, floor)
            // players/stairs 確定後に初回フォグ適用 (スポーン部屋を点灯。以降は FogScene.process が毎フレーム更新)
            |> FogScene.applyFog
            // ミニマップ (最終 placements / 階段を読むため末尾)。訪問記憶は World 権威で ClearVisited が掃除。
            |> MinimapScene.add
            // 世代 +1（gameLoop の tile bake トリガ＝新フロアのタイルを World へ焼く）と地形 read-model
            //（toBoard の壁/サイズ源）の seed を build choke で World へ。
            |> WorldDriver.bakeMap

    /// 駒（味方 / 敵 / アイテム / 宝箱 / 階段）に依存しない HUD・常駐ドライバ・メニュー群をまとめて追加する。
    /// `buildPlayingScene`（通常生成）と `rebuildFloorFromSnapshot`（スナップショット復元）が共有し、
    /// **ノード追加順序とメンバーを 1 か所に固定**する（追加漏れ・順序ズレ・二重追加を防ぐ）。
    /// MapScene / Fog / DamagePopup / Explosion の後、駒配置の後に呼ぶ前提。
    /// `label` はフロア番号表示（"1F" 等）、`name` はフロア名（"始まりの洞窟" 等。空可）。
    def addHudAndDrivers(label: String, name: String, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, SelectedPlayer.State, CursorState.State, ArrowCursorState.State, World.WorldQuery, TopBarState.State, UiWorldState.State} =
        scene
            |> MoveRangeScene.add       // SelectedPlayer 未設定なら no-op
            |> CursorScene.add
            |> ArrowCursorScene.add     // 杖発射方向の矢印カーソル (初期は非表示)
            |> CameraScene.add
            |> EnemyTurnDriver.add // 敵ターン進行の常駐タグノード (process で phase 判定)
            |> StairsExitDriver.add      // 集合「階段で離脱」の順次退場ドライバ (process で phase 判定)
            |> ItemMenuScene.add        // アイテム選択ウィンドウ (初期は非表示)
            // ユニット簡易カード（味方左 / 敵右）は World-entity UI（UnitCardUi / UiWorldState）へ移行済み。scene には積まない。
            |> ActionMenuScene.add      // 行動選択ウィンドウ (初期は非表示)
            |> WeaponSelectScene.add    // 武器選択ウィンドウ (ActionMenu「攻撃」確定で右隣に出る。初期は非表示)
            // 全滅モーダルは World-entity UI（GameOverMenuUi / UiWorldState）へ移行済み。scene には積まない。
            |> SuspendConfirmScene.add  // 中断確認のモーダル (初期は非表示)
            |> TradeMenuScene.add       // 物交換ウィンドウ (2 ペイン、初期は非表示)
            |> BattlePanelScene.add     // 戦闘予報ミニウィンドウ (World 配下・初期は非表示)
            |> LevelUpPanelScene.add    // レベルアップのステータス変化パネル (初期は非表示)
            // ユニット簡易カード（選択/カーソル上ユニット・攻撃対象敵）は World-entity UI（UnitCardUi）が
            // 起動時 spawn ＋ frameStep 表示するため、ここでは scene に積まない。
            |> TopBarUi.enter(label, name)   // 上部フェイズバー（World-entity UI・フロア設定 + 可視化 + 状態初期化）
            |> LogScene.add             // 右下の3行一時ログ (5秒で消える)
            |> ItemPickupPopupScene.add // アイテム取得ポップアップ (初期は非表示)
            |> TurnEndHoldScene.add     // Shift 長押しでターンエンドする中央ゲージ (初期は非表示)
            |> BgmScene.add             // BGM (AudioStreamPlayer, autoplay=true)

    /// プレイ用シーンを組み立て + 初期 spawn 一覧 (敵 / 味方) を `InitialSpawns` に保存する。
    /// 起動時と GameOver リビルド時の両方が必ず通る経路。これで「scene 構築」と
    /// 「ゲームオーバー復帰用のスポーン記録」が必ず同じタイミングで揃う。
    pub def buildAndRecord(catalogs: GameLifecycle.Catalogs,
                            floor: FloorCatalog.FloorResource): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, CursorState.State, ArrowCursorState.State, InitialSpawns.State, PartySelection.State, World.Command,
                World.WorldQuery, TopBarState.State, UiWorldState.State} =
        let scene = buildPlayingScene(catalogs, floor);
        InitialSpawns.State.put({
            enemies = EnemyScene.snapshotSpawns(scene),
            players = PlayerScene.snapshotSpawns(scene)
        });
        // AudioStreamPlayer ノード (BGM 等) の volume / loop / autoplay を OpenAL に反映する。
        // scene を組み立てただけでは Audio ノードが有効にならないため、構築後に必ず呼ぶ。
        SceneLoader.applyAudioAttach(scene);
        scene

    /// `FloorProgress` が指す現在フロアを解決して build + spawn snapshot 保存する。
    /// 起動時 / 全滅リスタート / クリア後ループの共通エントリ。
    pub def buildCurrentFloor(catalogs: GameLifecycle.Catalogs): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, CursorState.State, ArrowCursorState.State, InitialSpawns.State, FloorProgress.State,
                PartySelection.State, FloorSnapshot.State, World.Command, World.WorldQuery,
                TopBarState.State, UiWorldState.State} =
        let floor = FloorCatalog.get(FloorProgress.State.get(), catalogs#floors);
        recordFloorEntry(catalogs, buildAndRecord(catalogs, floor))

    // ────────────────────────────────────────────────────────
    // フロアスナップショット（全滅時の「そのフロアの最初から」復元 / 中断土台）
    // ────────────────────────────────────────────────────────

    /// 現在のフロア状態を `FloorSnapshot.T`（カタログ id ＋ 動的値の純粋データ）に射影する。
    /// マップは Plan、駒/アイテム/宝箱/階段は各 Scene の captureSnaps で id 化して集約する。
    pub def captureFloorSnapshot(catalogs: GameLifecycle.Catalogs, scene: Scene[NodeTag]): FloorSnapshot.T
            \ {FloorProgress.State, World.WorldQuery} =
        ({floorId = FloorProgress.State.get(),
          mapPlan  = MapScene.getPlan(scene),
          players  = PlayerScene.captureSnaps(scene, catalogs#weapons, catalogs#staves,
                                               catalogs#consumables, catalogs#rings),
          enemies  = EnemyScene.captureSnaps(scene, catalogs#weapons, catalogs#rings),
          items    = GroundItems.captureSnaps(scene),
          chests   = Chests.captureSnaps(scene),
          // 階段セルは World.stairsPos（World 権威）から読む。
          stairs   = World.stairsPosOf(World.WorldQuery.get())}: FloorSnapshot.T)

    /// 進入時スナップショットを `FloorSnapshot.State` に保存して scene をそのまま返す。
    /// 各フロア進入点（`buildCurrentFloor` / `GameLifecycle.advanceFloor`）の末尾で呼ぶ。
    pub def recordFloorEntry(catalogs: GameLifecycle.Catalogs, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {FloorProgress.State, FloorSnapshot.State, World.WorldQuery} =
        FloorSnapshot.State.put(captureFloorSnapshot(catalogs, scene));
        scene

    /// 保存済みスナップショットから **乱数を使わず** フロアを再構築する。`buildPlayingScene` と同じ
    /// スキャフォールド順序で、マップ/駒/アイテム/宝箱/階段だけを from-snapshot の決定論配置に差し替える。
    /// audio は `applyAudioAttach` で再アタッチ（BGM 再生）。
    pub def rebuildFloorFromSnapshot(catalogs: GameLifecycle.Catalogs, snap: FloorSnapshot.T): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, SelectedPlayer.State, CursorState.State, ArrowCursorState.State, World.Command,
                World.WorldQuery, TopBarState.State, UiWorldState.State} =
        let floor = FloorCatalog.get(snap#floorId, catalogs#floors);
        // 前フロア/前 run の配置物・探索記憶・ユニット store を掃除してから addFromSnaps で再 spawn する
        // （scene 再構築での自動 prune は廃止＝明示 Cmd。addFromSnaps より前が必須）。
        WorldDriver.clearFloorStores();
        let scene = Scene.empty()
            |> MapScene.addFromPlan(snap#mapPlan)
            |> FogScene.add
            |> PlayerScene.addFromSnaps(snap#players, catalogs#players, catalogs#staves,
                                         catalogs#consumables, catalogs#rings)
            |> EnemyScene.addFromSnaps(snap#enemies, catalogs#enemies, catalogs#weapons, catalogs#rings)
            |> GroundItems.addFromSnaps(snap#items, catalogs#players, catalogs#staves,
                                       catalogs#consumables, catalogs#rings)
            |> addHudAndDrivers(floor#label, floor#name)  // buildPlayingScene と同じ HUD/driver 群を共有
            |> placeStairsFromSnap(snap#stairs)
            |> Chests.addFromSnaps(snap#chests, catalogs#chests, catalogs#players,
                                        catalogs#staves, catalogs#consumables, catalogs#rings)
            |> FogScene.applyFog
            |> MinimapScene.add;
        SceneLoader.applyAudioAttach(scene);
        // 世代 +1（gameLoop の tile bake トリガ＝復元/restartFloor のタイルを World へ焼く）と地形
        // read-model の seed を build choke で World へ。
        WorldDriver.bakeMap(scene)

    /// 保存済み階段位置があればそのセルに階段を確定配置する（無ければ何もしない）。
    def placeStairsFromSnap(stairs: Option[{x = Int32, y = Int32}],
                             scene: Scene[NodeTag]): Scene[NodeTag] \ World.Command =
        match stairs {
            case Some(cell) => Stairs.placeAt(cell, scene)   // placeAt が Cmd.SetStairs を emit（World 権威）
            case None       => scene
        }

    // ────────────────────────────────────────────────────────
    // 画面（GamePhase）ごとの組み立て。`Game.applyPhaseChange` が phase 差分で 1 つを呼ぶ。
    // ────────────────────────────────────────────────────────

    /// タイトル画面を組む。ダンジョン外へ出るので World のユニット store と地形 read-model を掃除する。
    pub def buildTitle(): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, World.Command, TitleMenuScene.State, UiWorldState.State} =
        WorldDriver.exitDungeon();
        TitleMenuScene.add(Scene.empty())
            |> TopBarUi.leave   // ダンジョン外では上部バーを隠す

    /// 出撃メンバー選択画面を組む。タイトルと同じくダンジョン外なので World を掃除する。
    pub def buildCharacterSelect(catalogs: GameLifecycle.Catalogs): Scene[NodeTag]
            \ {GameEngine.Game, World.Command, CharacterSelectState.State, UiWorldState.State} =
        WorldDriver.exitDungeon();
        CharacterSelectScene.add(UnitCatalog.pool("players", catalogs#players), Scene.empty())
            |> TopBarUi.leave   // ダンジョン外では上部バーを隠す

    /// 現在フロアのダンジョンを組む。タイトル由来 ＋ スナップショット有り ＝ 中断再開で、
    /// `FloorSnapshot.State` の snapshot から **乱数なし** で決定論再構築する（`buildCurrentFloor` は
    /// 乱数を消費して別マップになるため通さない）。それ以外（CharacterSelect 由来 ＝ 新規ラン、または
    /// 防御的に snapshot 無し）は通常生成。`prevPhase` は遷移元画面。
    pub def buildPlaying(catalogs: GameLifecycle.Catalogs, prevPhase: GamePhase): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, SelectedPlayer.State, CursorState.State, ArrowCursorState.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State, FloorSnapshot.State,
                World.Command, World.WorldQuery, TopBarState.State, UiWorldState.State} =
        match (prevPhase, FloorSnapshot.State.get()) {
            case (GamePhase.Title, Some(snap)) =>
                GameLogger.playerLog("中断データから再開");
                rebuildFloorFromSnapshot(catalogs, snap)
            case _ =>
                GameLogger.playerLog("T1 味方のターン");
                buildCurrentFloor(catalogs)
        }
}
