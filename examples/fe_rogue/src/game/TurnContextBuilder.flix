/// TurnContextBuilder — Scene[NodeTag] + 各 effect から `TurnRules.Context` を組み立てる
///
/// `TurnRules.decide` は純粋関数だが、その入力 (Context) を作るには:
///   - `TurnPhase.State.get()` (現フェーズ)
///   - `SelectedPlayer.State.get()` (選択中味方 id)
///   - `BoardQuery.board()` (盤面スナップショット)
///   - `CursorScene.getGridPos(scene)` (カーソル位置)
///   - `PlayerScene.getAll` / `EnemyScene.getAll` (waited / dying の id 集合)
///   - `Tween.Scheduler.isActive(...)` (選択中味方が Tween 中か)
/// と複数の窓口を引く必要がある。これを 1 関数に集約して、GameManager / TurnInputBridge
/// が `decide` を呼ぶ前段だけ受け持つようにする。
mod TurnContextBuilder {

    /// 現在のシーンと各 effect から `TurnRules.Context` を組み立てる。
    /// 「判断に必要な値だけ」を抜き出し、判断ロジック (TurnRules.decide) を純粋に保つ入口。
    pub def build(input: TurnRules.Input, scene: Scene[NodeTag]):
            TurnRules.Context \ {BoardQuery, Tween.Scheduler,
                                  TurnPhase.State, SelectedPlayer.State} =
        let selected = SelectedPlayer.State.get()#id;
        let busy = match selected {
            case Some(id) => Tween.Scheduler.isActive(PlayerScene.playerPath(id))
            case None     => false
        };
        let waitedIds = PlayerScene.getAll(scene)
            |> List.filterMap(d -> if (d#waited) Some(d#id) else None);
        let dyingIds = EnemyScene.getAll(scene)
            |> List.filterMap(e -> if (e#isDying) Some(e#id) else None);
        {
            phase           = TurnPhase.State.get(),
            input           = input,
            board           = BoardQuery.board(),
            cursor          = CursorScene.getGridPos(scene),
            selected        = selected,
            waitedPlayerIds = waitedIds,
            dyingEnemyIds   = dyingIds,
            playerBusy      = busy
        }
}
