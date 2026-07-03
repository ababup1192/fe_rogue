/// GameLifecycle — ゲームの流れ（フロア遷移 / 全滅復帰 / 中断再開 / 特殊効果）を担う層。
/// `Game.start` の各 `CustomEffects.*Request` handler 本体がここに集約され、状態（ターン系 /
/// フロア進行 / パーティ / スナップショット）を巻き戻し・整えたうえで、実際の scene 構築は
/// `SceneSetup`（UI 組み立て）へ委譲する。
///
/// 外向き API:
///   - `resetForGameOver` — 1F へ戻して新ラン開始（GameOverRequest.restartBeginning）
///   - `restartFromFloorSnapshot` — 同フロアの進入時から再構築（restartFloor）
///   - `reviveWithGoddess` — 現フロアの敵一掃 + 全員その場復活（reviveInPlace）
///   - `advanceFloor` — 次フロアへ引き継ぎ（FloorAdvanceRequest）
///   - `suspendAndQuit` / `resumeFromSuspend` — 中断セーブ書き出し / 再開
///   - `maybeSpawnWanderer` / `dropFloorItem` / `applyRingTransform` — 敵の特殊行動
///
/// ターン系の巻き戻し（`resetTurnQueues` / `resetTurnState`）は敵キュー・TurnPhase・選択中味方・
/// 集合自動継続フラグをまとめて初期化し、フロア遷移・全滅・クリアで共通に使う。
mod GameLifecycle {

    /// 8 つのカタログを 1 つに束ねた引き回し用 record。`Game.start` で 1 度ロードして
    /// 構築 / リビルド経路（`SceneSetup.buildAndRecord` / `resetForGameOver` / `advanceFloor`）を
    /// 貫通する。味方 (`players`) と敵 (`enemies`) はここで別カタログとして分かれて入る。
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
    /// `resetForGameOver` が `SceneSetup.buildCurrentFloor` 経由で行う。
    /// この関数を切り出すことで、テストが scene 構築 (LDTK / LWJGL 要求) を経由せずに
    /// 「リセットセマンティクス」だけを観測できるようになる。
    pub def resetTurnState(): Unit \ {GameLogger.GameLogger, EnemyTurn.Queue,
                                       TurnPhase.State, SelectedPlayer.State,
                                       GatherResume.State} =
        GameLogger.gameOverLog("ゲームオーバー");
        resetTurnQueues()

    /// 「そのフロアの最初から」復元。ターン進行系を初期化し、保存済みスナップショットから
    /// フロアを決定論再構築する。`FloorProgress` / `PartySelection` は変えない（同フロア・同パーティ維持）。
    /// スナップショット未保存（理論上 CharacterSelect 中のみ）なら防御的に `resetForGameOver` へ。
    pub def restartFromFloorSnapshot(catalogs: Catalogs): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                CursorState.State, ArrowCursorState.State, GatherResume.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State, FloorSnapshot.State,
                World.Command, World.WorldQuery, TopBarState.State, UiWorldState.State} =
        match FloorSnapshot.State.get() {
            case Some(snap) =>
                resetTurnQueues();
                SceneSetup.rebuildFloorFromSnapshot(catalogs, snap)
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
            \ {Fs.FileWrite, FloorProgress.State, GameLogger.GameLogger, GamePhaseState,
                World.WorldQuery} =
        let snap = SceneSetup.captureFloorSnapshot(catalogs, scene);
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
    /// `FloorSnapshot.State` の snapshot から `SceneSetup.rebuildFloorFromSnapshot`（乱数なし）で行う。
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
                CursorState.State, ArrowCursorState.State, GatherResume.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State, FloorSnapshot.State,
                World.Command, World.WorldQuery, TopBarState.State, UiWorldState.State} =
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
            \ {Math.Random, FloorProgress.State, World.Command, World.WorldQuery} =
        let floor = FloorCatalog.get(FloorProgress.State.get(), catalogs#floors);
        EnemyScene.maybeSpawnWandererInRoom(catalogs#enemies, catalogs#weapons, catalogs#rings, floor, tick, scene)

    /// `CustomEffects.ThiefDropRequest` handler の本体。盗人の剣で敵がアイテムを落とす。
    /// 現在フロアの `items` ドロップ表から重み付き抽選し、解決したアイテムを `cell` に落とす。
    /// 抽選不能（表が空）なら no-op。
    pub def dropFloorItem(catalogs: Catalogs, cell: {x = Int32, y = Int32},
                           scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Math.Random, FloorProgress.State, World.Command} =
        let floor = FloorCatalog.get(FloorProgress.State.get(), catalogs#floors);
        match FloorCatalog.pickWeighted(floor#items) {
            case None     => scene
            case Some(id) =>
                let kind = GroundItems.lookupItem(id, catalogs#players, catalogs#staves,
                                                 catalogs#consumables, catalogs#rings);
                GroundItems.respawn(cell, id, kind, scene)
        }

    /// `CustomEffects.RingTransformRequest` handler の本体。ringman の特殊行動。
    /// 対象味方の装備外アイテムを 1 つ無作為に選び、確率分布で選んだ指輪に変える
    /// （7割ただの・1割サビ・2割その他）。変える持ち物が無ければ scene をそのまま返す。
    /// 変化先の指輪解決に `Ring.lookup` が要るため、catalog を持つ handler からのみ呼ばれる。
    pub def applyRingTransform(catalogs: Catalogs, enemyName: String, targetId: Int32,
                                scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Math.Random, GameLogger.GameLogger, World.Command, PlayerData.PartyQuery} =
        match RandomUtil.pick(PlayerScene.transformableItems(targetId)) {
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
                TurnPhase.State, SelectedPlayer.State, CursorState.State, ArrowCursorState.State, GatherResume.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State,
                FloorSnapshot.State, World.Command, World.WorldQuery, TopBarState.State, UiWorldState.State} =
        resetTurnState();
        FloorProgress.State.put(FloorCatalog.firstFloorId(catalogs#floors));
        // リスタートは新しい run 扱い: 前回の party 構成を引き継がず再抽選する。
        // PartySelection をクリアすると次の buildCurrentFloor 時に抽選が走る。
        PartySelection.State.clear();
        SceneSetup.buildCurrentFloor(catalogs)

    /// `CustomEffects.FloorAdvanceRequest` handler の本体。
    /// 生存味方の HP / 武器 / 持ち物を引き継ぎつつ、次フロアを組み立てる。
    /// 最終フロアをクリアした（次が無い）場合はクリアログを出して 1F へループする。
    pub def advanceFloor(catalogs: Catalogs,
                          scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State, CursorState.State, ArrowCursorState.State, GatherResume.State,
                InitialSpawns.State, FloorProgress.State, PartySelection.State,
                FloorSnapshot.State, World.Command, World.WorldQuery, TopBarState.State, UiWorldState.State} =
        // 引き継ぐステータスを「現フロア退場前」に確保しておく。
        let carry = PlayerScene.snapshotCarry(scene);
        match FloorCatalog.nextFloorId(FloorProgress.State.get(), catalogs#floors) {
            case Some(nextId) =>
                FloorProgress.State.put(nextId);
                let nextFloor = FloorCatalog.get(nextId, catalogs#floors);
                GameLogger.playerLog("${nextFloor#label} に進む");
                resetTurnQueues();
                let built = SceneSetup.buildAndRecord(catalogs, nextFloor);
                // 構築直後の party に前フロアの HP / 武器 / 持ち物を反映（待機状態はリセット済み）。
                // 反映後の「進入時状態」をスナップショットに記録（全滅時の「そのフロアの最初から」用）。
                SceneSetup.recordFloorEntry(catalogs, PlayerScene.reconcileWithCarry(carry, built))
            case None =>
                // 最終フロアクリア → クリアログ → 1F へループ（フレッシュな party で再開）
                GameLogger.playerLog("ゲームクリア！ 1F からもう一度");
                resetTurnQueues();
                FloorProgress.State.put(FloorCatalog.firstFloorId(catalogs#floors));
                // 周回も新しい run 扱い（リスタートと同じ理由: party 構成を再抽選）
                PartySelection.State.clear();
                SceneSetup.buildCurrentFloor(catalogs)
        }
}
