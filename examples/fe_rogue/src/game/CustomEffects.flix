/// CustomEffects — fe_rogue 固有のカスタム effect 集約
///
/// 複数モジュールを跨ぐ操作だが、emit 元では要求を出すだけで完結したいケースを
/// effect として宣言する。実体 (handler) は `Game.start` で 1 か所に注入される。
///
/// engine-guide スキルの規約: handler は **1〜3 行で本体関数を呼ぶだけ**。
/// 条件判定・計算は emit 元が済ませる。
mod CustomEffects {

    /// ゲームオーバー時のフルリビルドを要求する。
    /// emit 元 (PlayerDriver.removeDeadAndCheckGameOver) は「全員脱落」を検知したら
    /// `request()` を呼ぶ。
    /// handler は `WorldSetup.buildCurrentFloor` 系で起動時と同じ
    /// フルリビルドを行い、state 4 種 (EnemyTurn.Queue / TurnPhase / SelectedPlayer /
    /// InitialSpawns) を一斉に書き換える。
    /// `Math.Random` / `Fs.FileRead` / `IO` が必要なので start でしか handler 注入できない。
    pub eff GameOverRequest {
        /// 味方の死亡位置（id → グリッド座標）を記録する。`removeDeadAndCheckGameOver` が
        /// 除去の**前**に呼び、女神の加護の「その場復活」で各員を最後の位置に戻すために使う。
        /// handler 側で蓄積し、`reviveInPlace` 時に参照する。
        def markDeaths(positions: Map[Int32, {x = Int32, y = Int32}]): Unit
        /// 全滅検知時に呼ぶ。盤面をフリーズして選択メニュー（最初から / そのフロアの最初から）を出す。
        def request(): Unit
        /// 「最初から」確定。新ラン（1F・パーティ再抽選）でフルリビルドする（`resetForGameOver`）。
        def restartBeginning(): Unit
        /// 「そのフロアの最初から」確定。進入時スナップショットから同フロアを決定論再構築する
        /// （`restartFromFloorSnapshot`）。
        def restartFloor(): Unit
        /// 「女神の加護」確定。現フロアそのままに全員その場復活・HP全快・3ターン無敵にする
        /// （`reviveWithGoddess`）。
        def reviveInPlace(): Unit
    }

    /// 次フロアへの進行（または最終フロアクリア）を要求する。
    /// emit 元 (ActionMenuUi.applyStairs 等) は「生存味方が全員階段を使った」を検知したら
    /// `advance()` を呼ぶ。
    /// handler は `GameLifecycle.advanceFloor` で HP / 武器 / 持ち物を引き継いで次フロアを
    /// 組み立てる（次が無ければクリア → 1F ループ）。`GameOverRequest` と同じく
    /// `Math.Random` / `Fs.FileRead` / `IO` 等が必要なので start でしか handler 注入できない。
    pub eff FloorAdvanceRequest {
        def advance(): Unit
    }

    /// 敵ターン終端でシレン型の通路湧き（Wanderer タイプ）を試みることを要求する。
    /// emit 元 (EnemyTurnDriver.endTurn) は「敵ターンが 1 巡終わった」タイミングで
    /// `maybeSpawn()` を呼ぶ。実際に湧くかは低確率 + フロア上限 + 視界外通路セルの有無で
    /// handler 側（実体は EnemyDriver）が判断する（条件を満たさなければ何もしない）。
    /// 現在フロアを `FloorProgress` で解決し `Math.Random` で抽選するため、catalog を
    /// クロージャに閉じ込められる `Game.start` でしか handler 注入できない。
    pub eff WandererSpawnRequest {
        def maybeSpawn(): Unit
    }

    /// ringman の特殊行動「相手の持ち物を指輪に変える」を要求する。
    /// emit 元 (EnemyTurnDriver の通常 AI・攻撃枝) は「ringman が隣接して 30% を引き、
    /// 対象に装備外の持ち物がある」と判定したら `transform(敵の兵種名, 対象味方 id)` を呼ぶ。
    /// 実体 (handler) は `GameLifecycle.applyRingTransform` で、装備外アイテムを 1 つ無作為に選び
    /// 確率分布（7割ただの・1割サビ・2割その他）で選んだ指輪に変える。
    /// 変化先の指輪解決に Ring カタログが要るため、catalog をクロージャに閉じ込められる
    /// `Game.start` でしか handler 注入できない（WandererSpawnRequest と同じ理由）。
    pub eff RingTransformRequest {
        def transform(enemyName: String, targetPlayerId: Int32): Unit
    }

    /// 盗人の剣（ローグ装備時）の「敵がアイテムを落とす」を要求する。
    /// emit 元 (CombatDriver の攻撃解決) は「ローグが盗人の剣で命中して 20% を引いた」と判定したら
    /// `drop(セル)` を呼ぶ。実体 (handler) は現在フロアの items ドロップ表から重み付き抽選し、
    /// `GroundItems.respawn` で指定セルにアイテムを落とす。フロア表 + 各カタログ + Math.Random が要るため、
    /// catalog をクロージャに閉じ込められる `Game.start` でしか handler 注入できない。
    pub eff ThiefDropRequest {
        def drop(cell: {x = Int32, y = Int32}): Unit
    }

    /// 中断セーブを要求する。emit 元（ActionMenuUi の空マスメニュー「中断」項目）は
    /// 確定時に `save()` を呼ぶ。実体（handler）は `GameLifecycle.suspendAndQuit` で、
    /// 現在フロアを `SuspendSave` として slot に書き出し、タイトル画面へ戻す。
    /// `Fs.FileWrite` / `FloorProgress.State` / `GamePhaseState` が要るため `Game.start` でのみ注入。
    pub eff SuspendRequest {
        def save(): Unit
    }

    /// 中断セーブからの再開を要求する。emit 元（TitleMenuUi の「中断から再開」）は
    /// 中断データがある（resumable）ときだけ `resume()` を呼ぶ。実体（handler）は
    /// `GameLifecycle.resumeFromSuspend` で、slot を読み・パーティ / フロア / ターン系を整え・
    /// セーブを使用済みで上書き（save-scum 防止）してから Playing へ遷移する。
    /// 実際の画面構築は `Game.applyPhaseChange(Playing, from=Title)` が担う。
    pub eff ResumeRequest {
        def resume(): Unit
    }
}
