/// GameLifecycle — ゲーム起動 / リスタート時のシーン全体構築 + 状態リセット
///
/// 2 つの呼び出し経路で同じ手順を踏む:
///   1. `Game.start` 初回起動: catalog → `buildAndRecord` → BGM / ログ → gameLoop
///   2. `CustomEffects.GameOverRequest` handler: `resetForGameOver` → 新 scene を継続
///
/// 重複を避けるため、この 2 経路が共有する部分を以下の関数に集約する:
///   - `buildAndRecord(catalog)` — シーン構築 + 初期 spawn の snapshot 保存 (起動 / リビルド両方)
///   - `resetTurnState()`        — ゲームオーバー時に巻き戻す 3 effect (Queue / Phase / Selection)
///   - `resetForGameOver(catalog)` — handler 用の 1 行エントリ (両方を結合)
///
/// 各 Scene の `add` は **順序が意味を持つ**:
///   - MapScene が先 (他 Scene が `worldPath()` / `getMapLayer()` を参照する)
///   - DamagePopupScene は World 配下の親ノードを必要とするため Map の直後
///   - PlayerScene / EnemyScene は MapScene の placements に従ってスポーン
///   - MoveRangeScene は SelectedPlayer 状態を読むが起動時は未選択なので no-op
///   - Camera は最後に追加して全プレイヤー出揃った後に追従開始
///   - UI 系 (WeaponMenu / ActionMenu / BattlePanel / UnitInfoPopup) は最後 (描画前面)
///
/// `catalog` は `Game.start` でロード済みのユニット定義。PlayerScene と EnemyScene に
/// プール定義 (`party` / `enemyTier1`) を辿らせる。
mod GameLifecycle {

    /// 5 つのカタログを 1 つに束ねた引き回し用 record。`Game.start` で 1 度ロードして
    /// 構築 / リビルド経路 (buildAndRecord / resetForGameOver / advanceFloor) を貫通する。
    /// 味方 (`players`) と敵 (`enemies`) はここで別カタログとして分かれて入る。
    pub type alias Catalogs = {
        weapons     = WeaponCatalog.WeaponCatalog,
        players     = UnitCatalog.UnitCatalog,
        enemies     = EnemyCatalog.EnemyCatalog,
        floors      = FloorCatalog.FloorCatalog,
        staves      = Staff.StaffCatalog,
        consumables = Consumable.ConsumableCatalog
    }

    /// プレイ用シーンを 1 回で組み立てる。`MapScene.add` が `IO` を要求するため
    /// 戻り値の Aef にも `IO` を含める。
    /// **直接呼ぶのは `buildAndRecord` だけ** にする (起動 / リビルド時の snapshot 記録漏れ
    /// を防ぐため、外向き API は `buildAndRecord` を使う)。
    pub def buildPlayingScene(catalogs: Catalogs,
                                floor: FloorCatalog.FloorResource): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, PartySelection.State} =
        Scene.empty()
            |> MapScene.add(floor)
            |> FogScene.add             // 各 module の薄暗いモヤ矩形 + 常駐 FogDriver。placements 確定後
            |> DamagePopupScene.add     // World 配下に空の Marker2D 親を 1 つ生やす
            |> PlayerScene.add(catalogs#players, catalogs#staves, catalogs#consumables)
            |> EnemyScene.add(catalogs#enemies, catalogs#weapons, floor)
            |> ItemScene.add(catalogs#players, catalogs#staves, floor)   // 部屋の床に武器/杖をランダムドロップ
            |> MoveRangeScene.add       // SelectedPlayer 未設定なら no-op
            |> CursorScene.add
            |> ArrowCursorScene.add     // 杖発射方向の矢印カーソル (初期は非表示)
            |> StairsScene.add          // 次フロアへの階段 (初期は非表示。配置は末尾の placeRandom)
            |> CameraScene.add
            |> EnemyTurnDriverScene.add // 敵ターン進行の常駐タグノード (process で phase 判定)
            |> AutoMoveScene.add        // AutoMove 駆動の常駐タグノード (process で phase 判定)
            |> ItemMenuScene.add        // アイテム選択ウィンドウ (初期は非表示)
            |> ActionMenuScene.add      // 行動選択ウィンドウ (初期は非表示)
            |> TradeMenuScene.add       // 物交換ウィンドウ (2 ペイン、初期は非表示)
            |> BattlePanelScene.add   // 戦闘予報パネル (初期は非表示)
            |> LevelUpPanelScene.add  // レベルアップのステータス変化パネル (初期は非表示)
            |> UnitInfoPopupScene.add   // カーソル上のユニット情報パネル (初期は非表示)
            |> PhaseBannerScene.add     // ターン切替バナー (最前面。起動直後に味方ターンを表示)
            |> BgmScene.add             // BGM (AudioStreamPlayer, autoplay=true で起動時から再生)
            // 全ノード配置後に階段を床のランダムセルへ置く (駒・アイテムを避けるため最後)
            |> StairsScene.placeRandom
            // players/stairs 確定後に初回フォグ適用 (スポーン部屋を点灯。以降は FogScene.process が毎フレーム更新)
            // 起動時は通常モード (集合モードではない) なので torchCorridors=false
            |> FogScene.applyFog(false)
            // ミニマップ (最終 placements / 階段を読むため末尾)。訪問記憶はフロア再構築で自動リセット。
            |> MinimapScene.add

    /// プレイ用シーンを組み立て + 初期 spawn 一覧 (敵 / 味方) を `InitialSpawns` に保存する。
    /// 起動時と GameOver リビルド時の両方が必ず通る経路。これで「scene 構築」と
    /// 「ゲームオーバー復帰用のスポーン記録」が必ず同じタイミングで揃う。
    pub def buildAndRecord(catalogs: Catalogs,
                            floor: FloorCatalog.FloorResource): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, InitialSpawns.State, PartySelection.State} =
        let scene = buildPlayingScene(catalogs, floor);
        InitialSpawns.State.put({
            enemies = EnemyScene.snapshotSpawns(scene),
            players = PlayerScene.snapshotSpawns(scene)
        });
        // AudioStreamPlayer ノード (BGM 等) の volume / loop / autoplay を OpenAL に反映する。
        // 初回起動時と GameOver 後のリビルド時の両方でこの経路を通る
        SceneLoader.applyAudioAttach(scene);
        scene

    /// ターン進行系の effect だけを初期化する（ログは出さない）。
    /// 敵キューを空に / フェーズを PlayerCursor に / 選択中味方を解除。
    /// ゲームオーバー・フロア遷移・クリアで共通して使う「巻き戻し」の中身。
    pub def resetTurnQueues(): Unit \ {EnemyTurn.Queue, TurnPhase.State,
                                        SelectedPlayer.State} =
        EnemyTurn.Queue.replace(Nil);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        SelectedPlayer.State.put(SelectedPlayer.cleared())

    /// ゲームオーバー時のターン進行系 state を初期化する。
    /// ゲームオーバーログを出してから `resetTurnQueues` を呼ぶ。
    /// scene 書き換えは含まないので **副作用は effect のみ**。スポーンや scene の再構築は
    /// `resetForGameOver` が `buildAndRecord` 経由で行う。
    /// この関数を切り出すことで、テストが scene 構築 (LDTK / LWJGL 要求) を経由せずに
    /// 「リセットセマンティクス」だけを観測できるようになる。
    pub def resetTurnState(): Unit \ {GameLogger.GameLogger, EnemyTurn.Queue,
                                       TurnPhase.State, SelectedPlayer.State} =
        GameLogger.gameOverLog("ゲームオーバー");
        resetTurnQueues()

    /// `FloorProgress` が指す現在フロアを解決して build + spawn snapshot 保存する。
    /// 起動時 / 全滅リスタート / クリア後ループの共通エントリ。
    pub def buildCurrentFloor(catalogs: Catalogs): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, InitialSpawns.State, FloorProgress.State,
                PartySelection.State} =
        let floor = FloorCatalog.get(FloorProgress.State.get(), catalogs#floors);
        buildAndRecord(catalogs, floor)

    /// `CustomEffects.GameOverRequest` handler の本体。
    /// フロアを 1F に戻し、ターン進行系を初期化してから scene をリビルドして返す。
    /// handler 側は `k(GameLifecycle.resetForGameOver(catalog, staffCatalog, floors))` の 1 行で済む。
    pub def resetForGameOver(catalogs: Catalogs): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State} =
        resetTurnState();
        FloorProgress.State.put(FloorCatalog.firstFloorId(catalogs#floors));
        // リスタートは新しい run 扱い: メンバーを再抽選する（次の build で抽選される）
        PartySelection.State.clear();
        buildCurrentFloor(catalogs)

    /// `CustomEffects.FloorAdvanceRequest` handler の本体。
    /// 生存味方の HP / 武器 / 持ち物を引き継ぎつつ、次フロアを組み立てる。
    /// 最終フロアをクリアした（次が無い）場合はクリアログを出して 1F へループする。
    pub def advanceFloor(catalogs: Catalogs,
                          scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State} =
        // 引き継ぐステータスを「現フロア退場前」に確保しておく。
        let carry = PlayerScene.snapshotCarry(scene);
        match FloorCatalog.nextFloorId(FloorProgress.State.get(), catalogs#floors) {
            case Some(nextId) =>
                FloorProgress.State.put(nextId);
                let nextFloor = FloorCatalog.get(nextId, catalogs#floors);
                GameLogger.playerLog("${nextFloor#label} に進む");
                resetTurnQueues();
                let built = buildAndRecord(catalogs, nextFloor);
                // 構築直後の party に前フロアの HP / 武器 / 持ち物を反映（たいきはリセット済み）
                PlayerScene.reconcileWithCarry(carry, built)
            case None =>
                // 最終フロアクリア → クリアログ → 1F へループ（フレッシュな party で再開）
                GameLogger.playerLog("ゲームクリア！ 1F からもう一度");
                resetTurnQueues();
                FloorProgress.State.put(FloorCatalog.firstFloorId(catalogs#floors));
                // 周回は新しい run 扱い: メンバーを再抽選する
                PartySelection.State.clear();
                buildCurrentFloor(catalogs)
        }
}
