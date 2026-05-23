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

    /// プレイ用シーンを 1 回で組み立てる。`MapScene.add` が `IO` を要求するため
    /// 戻り値の Aef にも `IO` を含める。
    /// **直接呼ぶのは `buildAndRecord` だけ** にする (起動 / リビルド時の snapshot 記録漏れ
    /// を防ぐため、外向き API は `buildAndRecord` を使う)。
    pub def buildPlayingScene(catalog: UnitCatalog.UnitCatalog,
                                staffCatalog: Staff.StaffCatalog,
                                floor: FloorCatalog.FloorResource): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State} =
        Scene.empty()
            |> MapScene.add(floor)
            |> DamagePopupScene.add     // World 配下に空の Marker2D 親を 1 つ生やす
            |> PlayerScene.add(catalog, staffCatalog)
            |> EnemyScene.add(catalog, floor)
            |> ItemScene.add(catalog, floor)   // 部屋の床に武器をランダムドロップ
            |> MoveRangeScene.add       // SelectedPlayer 未設定なら no-op
            |> CursorScene.add
            |> FlagScene.add            // 自動移動先マーカー (初期は非表示)
            |> CameraScene.add
            |> EnemyTurnDriverScene.add // 敵ターン進行の常駐タグノード (process で phase 判定)
            |> AutoMoveScene.add        // AutoMove 駆動の常駐タグノード (process で phase 判定)
            |> ItemMenuScene.add        // アイテム選択ウィンドウ (初期は非表示)
            |> ActionMenuScene.add      // 行動選択ウィンドウ (初期は非表示)
            |> BattlePanelScene.add   // 戦闘予報パネル (初期は非表示)
            |> UnitInfoPopupScene.add   // カーソル上のユニット情報パネル (初期は非表示)

    /// プレイ用シーンを組み立て + 初期 spawn 一覧 (敵 / 味方) を `InitialSpawns` に保存する。
    /// 起動時と GameOver リビルド時の両方が必ず通る経路。これで「scene 構築」と
    /// 「ゲームオーバー復帰用のスポーン記録」が必ず同じタイミングで揃う。
    pub def buildAndRecord(catalog: UnitCatalog.UnitCatalog,
                            staffCatalog: Staff.StaffCatalog,
                            floor: FloorCatalog.FloorResource): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State, InitialSpawns.State} =
        let scene = buildPlayingScene(catalog, staffCatalog, floor);
        InitialSpawns.State.put({
            enemies = EnemyScene.snapshotSpawns(scene),
            players = PlayerScene.snapshotSpawns(scene)
        });
        scene

    /// ゲームオーバー時のターン進行系 state を初期化する。
    /// 敵キューを空に / フェーズを PlayerCursor に / 選択中味方を解除 / ゲームオーバーログを出力。
    /// scene 書き換えは含まないので **副作用は effect のみ**。スポーンや scene の再構築は
    /// `resetForGameOver` が `buildAndRecord` 経由で行う。
    /// この関数を切り出すことで、テストが scene 構築 (LDTK / LWJGL 要求) を経由せずに
    /// 「リセットセマンティクス」だけを観測できるようになる。
    pub def resetTurnState(): Unit \ {GameLogger.GameLogger, EnemyTurn.Queue,
                                       TurnPhase.State, SelectedPlayer.State} =
        GameLogger.gameOverLog("ゲームオーバー");
        EnemyTurn.Queue.replace(Nil);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        SelectedPlayer.State.put(SelectedPlayer.cleared())

    /// `CustomEffects.GameOverRequest` handler の本体。
    /// ターン進行系を初期化してから scene をリビルド + spawn snapshot 更新して返す。
    /// handler 側は `k(GameLifecycle.resetForGameOver(catalog, staffCatalog, floor))` の 1 行で済む。
    pub def resetForGameOver(catalog: UnitCatalog.UnitCatalog,
                              staffCatalog: Staff.StaffCatalog,
                              floor: FloorCatalog.FloorResource): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State,
                InitialSpawns.State} =
        resetTurnState();
        buildAndRecord(catalog, staffCatalog, floor)
}
