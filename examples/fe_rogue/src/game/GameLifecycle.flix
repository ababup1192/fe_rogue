/// GameLifecycle — ゲーム起動 / リスタート時のシーン全体構築
///
/// `Game.start` の初回起動と `CustomEffects.GameOverRequest` handler のフルリビルドの
/// 2 経路から呼ばれる。各 Scene の `add` を順に pipe で繋ぐだけだが、**順序が意味を持つ**:
///   - MapScene が先 (他 Scene が `worldPath()` / `getMapLayer()` を参照する)
///   - DamagePopupScene は World 配下の親ノードを必要とするため Map の直後
///   - PlayerScene / EnemyScene は MapScene の placements に従ってスポーン
///   - MoveRangeScene は SelectedPlayer 状態を読むが起動時は未選択なので no-op
///   - Camera は最後に追加して全プレイヤー出揃った後に追従開始
///   - UI 系 (WeaponMenu / ActionMenu / ForecastPanel / UnitInfoPopup) は最後 (描画前面)
///
/// `catalog` は `Game.start` でロード済みのユニット定義。PlayerScene と EnemyScene に
/// プール定義 (`party` / `enemyTier1`) を辿らせる。
mod GameLifecycle {

    /// プレイ用シーンを 1 回で組み立てる。`MapScene.add` が `IO` を要求するため
    /// 戻り値の Aef にも `IO` を含める。
    pub def buildPlayingScene(catalog: UnitCatalog.UnitCatalog): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State} =
        Scene.empty()
            |> MapScene.add
            |> DamagePopupScene.add     // World 配下に空の Marker2D 親を 1 つ生やす
            |> PlayerScene.add(catalog)
            |> EnemyScene.add(catalog)
            |> ItemScene.add(catalog)   // 部屋の床に武器をランダムドロップ
            |> MoveRangeScene.add       // SelectedPlayer 未設定なら no-op
            |> CursorScene.add
            |> FlagScene.add            // 自動移動先マーカー (初期は非表示)
            |> CameraScene.add
            |> EnemyTurnDriverScene.add // 敵ターン進行の常駐タグノード (process で phase 判定)
            |> AutoMoveDriverScene.add  // AutoMove 駆動の常駐タグノード (process で phase 判定)
            |> WeaponMenuScene.add      // 武器選択ウィンドウ (初期は非表示)
            |> ActionMenuScene.add      // 行動選択ウィンドウ (初期は非表示)
            |> ForecastPanelScene.add   // 戦闘予報パネル (初期は非表示)
            |> UnitInfoPopupScene.add   // カーソル上のユニット情報パネル (初期は非表示)
}
