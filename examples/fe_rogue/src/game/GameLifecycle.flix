/// GameLifecycle — ゲーム起動 / リスタート時のシーン全体構築 + 状態リセット
///
/// 2 つの呼び出し経路で同じ手順を踏む:
///   1. `Game.start` 初回起動: catalog → `buildAndRecord` → BGM / ログ → gameLoop
///   2. `CustomEffects.GameOverRequest` handler: `resetForGameOver` → 新 scene を継続
///
/// この 2 経路が共有するロジックを集約することで、snapshot 記録漏れや state 巻き戻し漏れを
/// 防ぐ。外向き API として `buildCurrentFloor` / `resetForGameOver` / `advanceFloor` を使い、
/// `buildPlayingScene` を直接呼ぶと snapshot が記録されない点に注意。
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
        consumables = Consumable.ConsumableCatalog,
        chests      = ChestCatalog.ChestCatalog,
        rings       = Ring.RingCatalog
    }

    /// プレイ用シーンを 1 回で組み立てる。`MapScene.add` が `IO` を要求するため
    /// 戻り値の Aef にも `IO` を含める。
    /// **直接呼ぶのは `buildAndRecord` だけ** にする (起動 / リビルド時の snapshot 記録漏れ
    /// を防ぐため、外向き API は `buildAndRecord` を使う)。
    pub def buildPlayingScene(catalogs: Catalogs,
                                floor: FloorCatalog.FloorResource): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, PartySelection.State, World.Command} =
        Scene.empty()
            |> MapScene.add(floor)
            |> FogScene.add             // 各 module の薄暗いモヤ矩形 + 常駐 FogDriver
            // ↑ FogDriver は EnemyTurnDriver より先に追加する（preorder で同フレーム先に process される）。
            //   EnemyTurnDriverScene.endTurn の集合自動継続判定 anyVisibleEnemy が「同フレーム最新の
            //   フォグ可視（applyFog 適用後）」を読めるのはこの add 順前提。順序を入れ替えると 1 フレーム
            //   古い可視値で判定してしまうので注意。
            |> DamagePopupScene.add     // World 配下に空の Marker2D 親を 1 つ生やす
            |> ExplosionScene.add       // 爆発エフェクト用の空 Marker2D 親（火炎瓶/爆発瓶/魔法着弾）
            |> PlayerScene.add(catalogs#players, catalogs#staves, catalogs#consumables)
            |> EnemyScene.add(catalogs#enemies, catalogs#weapons, catalogs#rings, floor)
            |> ItemScene.add(catalogs#players, catalogs#staves, catalogs#consumables, catalogs#rings, floor)   // 部屋の床に武器/杖/消耗品/指輪をランダムドロップ
            |> addHudAndDrivers(floor#label, floor#name)  // 駒非依存の HUD / 常駐ドライバ / メニュー群（rebuild と共有）
            // 全ノード配置後に階段を床のランダムセルへ置く (駒・アイテムを避けるため最後)
            |> StairsScene.placeRandom
            // 階段確定後に宝箱を配置 (駒・アイテム・階段を避けるため階段の後)
            |> ChestScene.add(catalogs#chests, catalogs#players, catalogs#staves, catalogs#consumables, catalogs#rings, floor)
            // players/stairs 確定後に初回フォグ適用 (スポーン部屋を点灯。以降は FogScene.process が毎フレーム更新)
            |> FogScene.applyFog
            // ミニマップ (最終 placements / 階段を読むため末尾)。訪問記憶はフロア再構築で自動リセット。
            |> MinimapScene.add
            // B/tiles: マップノード再構築の世代を +1（gameLoop の tile bake トリガ＝新フロアのタイルを World へ焼く）。
            |> (s -> { World.Command.emit(World.Cmd.BumpTileGen); s })

    /// 駒（味方 / 敵 / アイテム / 宝箱 / 階段）に依存しない HUD・常駐ドライバ・メニュー群をまとめて追加する。
    /// `buildPlayingScene`（通常生成）と `rebuildFloorFromSnapshot`（スナップショット復元）が共有し、
    /// **ノード追加順序とメンバーを 1 か所に固定**する（追加漏れ・順序ズレ・二重追加を防ぐ）。
    /// MapScene / Fog / DamagePopup / Explosion の後、駒配置の後に呼ぶ前提。
    /// `label` はフロア番号表示（"1F" 等）、`name` はフロア名（"始まりの洞窟" 等。空可）。
    def addHudAndDrivers(label: String, name: String, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, SelectedPlayer.State} =
        scene
            |> MoveRangeScene.add       // SelectedPlayer 未設定なら no-op
            |> CursorScene.add
            |> ArrowCursorScene.add     // 杖発射方向の矢印カーソル (初期は非表示)
            |> StairsScene.add          // 次フロアへの階段 (初期は非表示。配置は呼び出し側で確定)
            |> CameraScene.add
            |> EnemyTurnDriverScene.add // 敵ターン進行の常駐タグノード (process で phase 判定)
            |> StairsExitScene.add      // 集合「階段で離脱」の順次退場ドライバ (process で phase 判定)
            |> ItemMenuScene.add        // アイテム選択ウィンドウ (初期は非表示)
            |> UnitCardScene.add        // 左サイドの選択ユニット簡易カード (初期は非表示)
            |> EnemyCardScene.add       // 右サイドの攻撃対象敵カード (UnitCard と左右対称・初期は非表示)
            |> ActionMenuScene.add      // 行動選択ウィンドウ (初期は非表示)
            |> WeaponSelectScene.add    // 武器選択ウィンドウ (ActionMenu「攻撃」確定で右隣に出る。初期は非表示)
            |> GameOverMenuScene.add    // 全滅時のモーダル選択 (初期は非表示)
            |> SuspendConfirmScene.add  // 中断確認のモーダル (初期は非表示)
            |> TradeMenuScene.add       // 物交換ウィンドウ (2 ペイン、初期は非表示)
            |> BattlePanelScene.add     // 戦闘予報ミニウィンドウ (World 配下・初期は非表示)
            |> LevelUpPanelScene.add    // レベルアップのステータス変化パネル (初期は非表示)
            // UnitInfoPopupScene は廃止し、UnitCardScene（左サイドの常設カード）に統合。
            // カーソル下のユニット情報も UnitCardScene が PlayerCursor 中に表示する。
            |> TopBarScene.add(label, name)  // 上部フェイズバー（フロア番号+名前 / フェイズ / 下線）
            |> LogScene.add             // 右下の3行一時ログ (5秒で消える)
            |> ItemPickupPopupScene.add // アイテム取得ポップアップ (初期は非表示)
            |> TurnEndHoldScene.add     // Shift 長押しでターンエンドする中央ゲージ (初期は非表示)
            |> BgmScene.add             // BGM (AudioStreamPlayer, autoplay=true)

    /// プレイ用シーンを組み立て + 初期 spawn 一覧 (敵 / 味方) を `InitialSpawns` に保存する。
    /// 起動時と GameOver リビルド時の両方が必ず通る経路。これで「scene 構築」と
    /// 「ゲームオーバー復帰用のスポーン記録」が必ず同じタイミングで揃う。
    pub def buildAndRecord(catalogs: Catalogs,
                            floor: FloorCatalog.FloorResource): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, InitialSpawns.State, PartySelection.State, World.Command} =
        let scene = buildPlayingScene(catalogs, floor);
        InitialSpawns.State.put({
            enemies = EnemyScene.snapshotSpawns(scene),
            players = PlayerScene.snapshotSpawns(scene)
        });
        // AudioStreamPlayer ノード (BGM 等) の volume / loop / autoplay を OpenAL に反映する。
        // scene を組み立てただけでは Audio ノードが有効にならないため、構築後に必ず呼ぶ。
        SceneLoader.applyAudioAttach(scene);
        scene

    /// ターン進行系の effect だけを初期化する（ログは出さない）。
    /// 敵キューを空に / フェーズを PlayerCursor に / 選択中味方を解除 / 集合自動継続フラグを落とす。
    /// ゲームオーバー・フロア遷移・クリアで共通して使う「巻き戻し」の中身。
    /// `GatherResume` は通常 `endTurn` で毎ターン消費されるが、ゲームオーバー（敵ターン中に全滅して
    /// endTurn を経ない）やフロア遷移ではそこを通らないため、ここで明示クリアして前フロアの
    /// resume が新フロア初手で誤発火するのを防ぐ。
    pub def resetTurnQueues(): Unit \ {EnemyTurn.Queue, TurnPhase.State,
                                        SelectedPlayer.State, GatherResume.State} =
        EnemyTurn.Queue.replace(Nil);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        GatherResume.State.put(false)

    /// ゲームオーバー時のターン進行系 state を初期化する。
    /// ゲームオーバーログを出してから `resetTurnQueues` を呼ぶ。
    /// scene 書き換えは含まないので **副作用は effect のみ**。スポーンや scene の再構築は
    /// `resetForGameOver` が `buildAndRecord` 経由で行う。
    /// この関数を切り出すことで、テストが scene 構築 (LDTK / LWJGL 要求) を経由せずに
    /// 「リセットセマンティクス」だけを観測できるようになる。
    pub def resetTurnState(): Unit \ {GameLogger.GameLogger, EnemyTurn.Queue,
                                       TurnPhase.State, SelectedPlayer.State,
                                       GatherResume.State} =
        GameLogger.gameOverLog("ゲームオーバー");
        resetTurnQueues()

    /// `FloorProgress` が指す現在フロアを解決して build + spawn snapshot 保存する。
    /// 起動時 / 全滅リスタート / クリア後ループの共通エントリ。
    pub def buildCurrentFloor(catalogs: Catalogs): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, InitialSpawns.State, FloorProgress.State,
                PartySelection.State, FloorSnapshot.State, World.Command} =
        let floor = FloorCatalog.get(FloorProgress.State.get(), catalogs#floors);
        recordFloorEntry(catalogs, buildAndRecord(catalogs, floor))

    // ────────────────────────────────────────────────────────
    // フロアスナップショット（全滅時の「そのフロアの最初から」復元 / 中断土台）
    // ────────────────────────────────────────────────────────

    /// 現在のフロア状態を `FloorSnapshot.T`（カタログ id ＋ 動的値の純粋データ）に射影する。
    /// マップは Plan、駒/アイテム/宝箱/階段は各 Scene の captureSnaps で id 化して集約する。
    pub def captureFloorSnapshot(catalogs: Catalogs, scene: Scene[NodeTag]): FloorSnapshot.T
            \ FloorProgress.State =
        ({floorId = FloorProgress.State.get(),
          mapPlan  = MapScene.getPlan(scene),
          players  = PlayerScene.captureSnaps(scene, catalogs#weapons, catalogs#staves,
                                               catalogs#consumables, catalogs#rings),
          enemies  = EnemyScene.captureSnaps(scene, catalogs#weapons, catalogs#rings),
          items    = ItemScene.captureSnaps(scene),
          chests   = ChestScene.captureSnaps(scene),
          stairs   = StairsScene.getPos(scene)}: FloorSnapshot.T)

    /// 進入時スナップショットを `FloorSnapshot.State` に保存して scene をそのまま返す。
    /// 各フロア進入点（`buildCurrentFloor` / `advanceFloor`）の末尾で呼ぶ。
    pub def recordFloorEntry(catalogs: Catalogs, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {FloorProgress.State, FloorSnapshot.State} =
        FloorSnapshot.State.put(captureFloorSnapshot(catalogs, scene));
        scene

    /// 保存済みスナップショットから **乱数を使わず** フロアを再構築する。`buildPlayingScene` と同じ
    /// スキャフォールド順序で、マップ/駒/アイテム/宝箱/階段だけを from-snapshot の決定論配置に差し替える。
    /// audio は `applyAudioAttach` で再アタッチ（BGM 再生）。
    pub def rebuildFloorFromSnapshot(catalogs: Catalogs, snap: FloorSnapshot.T): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, SelectedPlayer.State, World.Command} =
        let floor = FloorCatalog.get(snap#floorId, catalogs#floors);
        let scene = Scene.empty()
            |> MapScene.addFromPlan(snap#mapPlan)
            |> FogScene.add
            |> DamagePopupScene.add
            |> ExplosionScene.add
            |> PlayerScene.addFromSnaps(snap#players, catalogs#players, catalogs#staves,
                                         catalogs#consumables, catalogs#rings)
            |> EnemyScene.addFromSnaps(snap#enemies, catalogs#enemies, catalogs#weapons, catalogs#rings)
            |> ItemScene.addFromSnaps(snap#items, catalogs#players, catalogs#staves,
                                       catalogs#consumables, catalogs#rings)
            |> addHudAndDrivers(floor#label, floor#name)  // buildPlayingScene と同じ HUD/driver 群を共有
            |> placeStairsFromSnap(snap#stairs)
            |> ChestScene.addFromSnaps(snap#chests, catalogs#chests, catalogs#players,
                                        catalogs#staves, catalogs#consumables, catalogs#rings)
            |> FogScene.applyFog
            |> MinimapScene.add;
        SceneLoader.applyAudioAttach(scene);
        // B/tiles: マップノード再構築の世代を +1（gameLoop の tile bake トリガ＝復元/restartFloor のタイルを World へ焼く）。
        World.Command.emit(World.Cmd.BumpTileGen);
        scene

    /// 保存済み階段位置があればそのセルに階段を確定配置する（無ければ何もしない）。
    def placeStairsFromSnap(stairs: Option[{x = Int32, y = Int32}],
                             scene: Scene[NodeTag]): Scene[NodeTag] =
        match stairs {
            case Some(cell) => StairsScene.placeAt(cell, scene)
            case None       => scene
        }

    /// 「そのフロアの最初から」復元。ターン進行系を初期化し、保存済みスナップショットから
    /// フロアを決定論再構築する。`FloorProgress` / `PartySelection` は変えない（同フロア・同パーティ維持）。
    /// スナップショット未保存（理論上 CharacterSelect 中のみ）なら防御的に `resetForGameOver` へ。
    pub def restartFromFloorSnapshot(catalogs: Catalogs): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                GatherResume.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State, FloorSnapshot.State,
                World.Command} =
        match FloorSnapshot.State.get() {
            case Some(snap) =>
                resetTurnQueues();
                rebuildFloorFromSnapshot(catalogs, snap)
            case None =>
                resetForGameOver(catalogs)
        }

    // ────────────────────────────────────────────────────────
    // 中断セーブ（suspend save / 再開で消費・1 スロット）
    // ────────────────────────────────────────────────────────

    /// 中断セーブから出撃メンバー（`PartySelection`）を復元する。snap の味方（id 昇順 = lord 先頭）の
    /// `classId` を `UnitCatalog.lookupUnit` で resource に解決し直して `PartySelection.State.put` する。
    /// 再開後の次フロア進行（`advanceFloor` → `PlayerScene.add`）が PartySelection を読むため必須。
    pub def restorePartySelection(snap: FloorSnapshot.T, catalogs: Catalogs): Unit
            \ PartySelection.State =
        let party = snap#players
            |> List.sortBy(p -> p#id)
            |> List.map(p -> (p#classId, UnitCatalog.lookupUnit(p#classId, catalogs#players)));
        PartySelection.State.put(party)

    /// 中断セーブ: 現在のフロアを `SuspendSave`（未使用）として slot に書き出し、タイトル画面へ戻す。
    /// `CustomEffects.SuspendRequest.save` の本体。次フレームで `applyPhaseChange(Title)` が
    /// タイトルを組む。保存失敗（saves/ 不在等）はログに出して握り潰す（盤面は壊さない）。
    pub def suspendAndQuit(catalogs: Catalogs, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Fs.FileWrite, FloorProgress.State, GameLogger.GameLogger, GamePhaseState} =
        let snap = captureFloorSnapshot(catalogs, scene);
        match SaveManager.write(SuspendSave.slot(), SuspendSave.make(false, snap)) {
            case Ok(_)   =>
                // 保存できたときだけタイトルへ戻す。
                GameLogger.playerLog("中断データを保存しました");
                GamePhaseState.put(GamePhase.Title)
            case Err(_e) =>
                // 保存失敗（saves/ 不在等）はタイトルへ戻さずプレイ続行（進行を失わせない）。
                GameLogger.playerLog("中断データの保存に失敗しました")
        };
        scene

    /// 中断セーブからの再開準備: slot を読み、未使用なら フロア / パーティ / ターン系を整え、
    /// セーブを「使用済み」で上書き（save-scum 防止）し、snapshot を `FloorSnapshot.State` へ渡してから
    /// Playing へ遷移する。実際の scene 構築は `applyPhaseChange(Playing, from=Title)` が
    /// `FloorSnapshot.State` の snapshot から `rebuildFloorFromSnapshot`（乱数なし）で行う。
    /// 使用済み / 不在なら何もしない（タイトル側で disable 済みなので通常来ない）。
    /// `CustomEffects.ResumeRequest.resume` の本体。
    pub def resumeFromSuspend(catalogs: Catalogs, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Fs.FileRead, Fs.FileWrite, EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                GatherResume.State,
                FloorProgress.State, PartySelection.State, FloorSnapshot.State, GamePhaseState,
                GameLogger.GameLogger} =
        let saved: Option[SuspendSave.Save] = SaveManager.read(SuspendSave.slot());
        match SuspendSave.resumable(saved) {
            case None       => scene
            case Some(snap) =>
                FloorProgress.State.put(snap#floorId);
                restorePartySelection(snap, catalogs);
                resetTurnQueues();
                // save-scum 防止: 読み出し直後に「使用済み」で上書きしてファイルを無効化する。
                // 上書き失敗（読めたのに書けない稀なケース）はログだけ出して再開は続行する
                // （握り潰すと無効化漏れ＝save-scum を見落とすため、痕跡を残す）。
                match SaveManager.write(SuspendSave.slot(), SuspendSave.make(true, snap)) {
                    case Ok(_)   => ()
                    case Err(_e) => GameLogger.playerLog("中断データの無効化に失敗しました")
                };
                FloorSnapshot.State.put(snap);
                GamePhaseState.put(GamePhase.Playing);
                scene
        }

    /// 「女神の加護（完全復活）」。**現フロアの敵を全て一掃**し、進入時編成の全員をリーダーの周りに
    /// 全快で再配置して味方ターンへ戻す（無敵は付与しない／マップ・アイテムは現在 scene のまま）。
    /// リーダーは倒れたその場（`marks` の死亡位置、無ければ進入時セル）に置き、仲間はその周囲へ。
    /// スナップショット未保存なら防御的に resetForGameOver へ。
    pub def reviveWithGoddess(catalogs: Catalogs,
                               marks: Map[Int32, {x = Int32, y = Int32}],
                               scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                GatherResume.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State, FloorSnapshot.State,
                World.Command} =
        match FloorSnapshot.State.get() {
            case Some(snap) =>
                resetTurnQueues();
                // 復活の効果音（暫定で回復音を流用。後で専用音に差し替え予定）。
                AudioStreamPlayer.play("cure");
                GameLogger.playerLog("女神の加護！ 敵を払い、全員が復活した");
                // リーダーの再配置中心。倒れた位置（marks）優先、無ければ進入時セル。
                let leaderFallback = snap#players
                    |> List.find(p -> p#id == PlayerScene.lordId())
                    |> Option.map(p -> p#gridPos)
                    |> Option.getWithDefault(({x = 0, y = 0}: {x = Int32, y = Int32}));
                let leaderPos = Map.get(PlayerScene.lordId(), marks)
                    |> Option.getWithDefault(leaderFallback);
                let cleared = EnemyScene.removeAll(scene);
                PlayerScene.reviveAroundLeader(snap#players, catalogs#players, catalogs#staves,
                                               catalogs#consumables, catalogs#rings, leaderPos, cleared)
            case None =>
                resetForGameOver(catalogs)
        }

    /// `CustomEffects.WandererSpawnRequest` handler の本体。
    /// 現在フロアを解決して、試練型の部屋湧き（Wanderer タイプ）を `EnemyScene` 側に委ねる。
    /// `tick` は handler が採番する湧きクロック。実際に湧くかの判断
    /// （周期 + フロア上限 + 視界外部屋セルの有無）は EnemyScene が行う。
    pub def maybeSpawnWanderer(catalogs: Catalogs, tick: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Math.Random, FloorProgress.State, World.Command} =
        let floor = FloorCatalog.get(FloorProgress.State.get(), catalogs#floors);
        EnemyScene.maybeSpawnWandererInRoom(catalogs#enemies, catalogs#weapons, catalogs#rings, floor, tick, scene)

    /// `CustomEffects.ThiefDropRequest` handler の本体。盗人の剣で敵がアイテムを落とす。
    /// 現在フロアの `items` ドロップ表から重み付き抽選し、解決したアイテムを `cell` に落とす。
    /// 抽選不能（表が空）なら no-op。
    pub def dropFloorItem(catalogs: Catalogs, cell: {x = Int32, y = Int32},
                           scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Math.Random, FloorProgress.State} =
        let floor = FloorCatalog.get(FloorProgress.State.get(), catalogs#floors);
        match FloorCatalog.pickWeighted(floor#items) {
            case None     => scene
            case Some(id) =>
                let kind = ItemScene.lookupItem(id, catalogs#players, catalogs#staves,
                                                 catalogs#consumables, catalogs#rings);
                ItemScene.respawn(cell, id, kind, scene)
        }

    /// `CustomEffects.RingTransformRequest` handler の本体。ringman の特殊行動。
    /// 対象味方の装備外アイテムを 1 つ無作為に選び、確率分布で選んだ指輪に変える
    /// （7割ただの・1割サビ・2割その他）。変える持ち物が無ければ scene をそのまま返す。
    /// 変化先の指輪解決に `Ring.lookup` が要るため、catalog を持つ handler からのみ呼ばれる。
    pub def applyRingTransform(catalogs: Catalogs, enemyName: String, targetId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Math.Random, GameLogger.GameLogger, World.Command} =
        match RandomUtil.pick(PlayerScene.transformableItems(targetId, scene)) {
            case None               => scene
            case Some((kind, name)) =>
                let ring = Ring.lookup(pickTransformRingId(catalogs#rings), catalogs#rings);
                GameLogger.enemyLog(
                    "${enemyName} は ${PlayerScene.displayName(targetId, scene)} の ${name} を ${ring#name} に変えた");
                PlayerScene.replaceItemWithRing(targetId, kind, ring, scene)
        }

    /// 変化先の指輪 id を確率で選ぶ。7割 plain_ring・1割 rusty_ring・2割 その他（plain/rusty 以外）。
    def pickTransformRingId(rings: Ring.RingCatalog): String \ Math.Random =
        let roll = Math.Random.randomFloat64();
        if (roll < 0.7) "plain_ring"
        else if (roll < 0.8) "rusty_ring"
        else otherTransformRingId(rings)

    /// plain_ring / rusty_ring 以外の指輪 id を 1 つ無作為に返す。候補が無ければ plain_ring。
    def otherTransformRingId(rings: Ring.RingCatalog): String \ Math.Random =
        let others = Ring.ringsOf(rings)
            |> Map.toList
            |> List.map(fst)
            |> List.filter(id -> id != "plain_ring" and id != "rusty_ring");
        RandomUtil.pick(others) |> Option.getWithDefault("plain_ring")

    /// `CustomEffects.GameOverRequest` handler の本体。
    /// フロアを 1F に戻し、ターン進行系を初期化してから scene をリビルドして返す。
    pub def resetForGameOver(catalogs: Catalogs): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State,
                FloorSnapshot.State, World.Command} =
        resetTurnState();
        FloorProgress.State.put(FloorCatalog.firstFloorId(catalogs#floors));
        // リスタートは新しい run 扱い: 前回の party 構成を引き継がず再抽選する。
        // PartySelection をクリアすると次の buildCurrentFloor 時に抽選が走る。
        PartySelection.State.clear();
        buildCurrentFloor(catalogs)

    /// `CustomEffects.FloorAdvanceRequest` handler の本体。
    /// 生存味方の HP / 武器 / 持ち物を引き継ぎつつ、次フロアを組み立てる。
    /// 最終フロアをクリアした（次が無い）場合はクリアログを出して 1F へループする。
    pub def advanceFloor(catalogs: Catalogs,
                          scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State,
                FloorSnapshot.State, World.Command} =
        // 引き継ぐステータスを「現フロア退場前」に確保しておく。
        let carry = PlayerScene.snapshotCarry(scene);
        match FloorCatalog.nextFloorId(FloorProgress.State.get(), catalogs#floors) {
            case Some(nextId) =>
                FloorProgress.State.put(nextId);
                let nextFloor = FloorCatalog.get(nextId, catalogs#floors);
                GameLogger.playerLog("${nextFloor#label} に進む");
                resetTurnQueues();
                let built = buildAndRecord(catalogs, nextFloor);
                // 構築直後の party に前フロアの HP / 武器 / 持ち物を反映（待機状態はリセット済み）。
                // 反映後の「進入時状態」をスナップショットに記録（全滅時の「そのフロアの最初から」用）。
                recordFloorEntry(catalogs, PlayerScene.reconcileWithCarry(carry, built))
            case None =>
                // 最終フロアクリア → クリアログ → 1F へループ（フレッシュな party で再開）
                GameLogger.playerLog("ゲームクリア！ 1F からもう一度");
                resetTurnQueues();
                FloorProgress.State.put(FloorCatalog.firstFloorId(catalogs#floors));
                // 周回も新しい run 扱い（リスタートと同じ理由: party 構成を再抽選）
                PartySelection.State.clear();
                buildCurrentFloor(catalogs)
        }
}
