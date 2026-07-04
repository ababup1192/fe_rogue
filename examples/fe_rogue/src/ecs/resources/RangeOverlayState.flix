/// RangeOverlayState — グリッド範囲オーバーレイ（移動 / 攻撃 / 敵移動 / 敵攻撃 / 味方攻撃 /
/// 交換 / 危険範囲）のセル集合を保持する resource
///
/// 7 種の範囲は「そのフェーズ限定で画面に出る view 状態」であり、駒（id）に属さない世界に 1 つの
/// 状態＝Resource が権威。表示トグルは **1 record の Option フィールドの在/不在** で表し、
/// `RenderWorld.renderRangeOverlays` が cells から直描きする（scene に Tile ノードは積まない）。
///
/// ## なぜ Map[kind, cells] でなく 1 record か
/// 7 種はペイロード形が異なる:
///   - MoveRange       … {reachable（clamp 判定用）, drawCells（描画用・味方マス除外）}
///   - EnemyRange      … {enemyId（対象敵）, reachable}
///   - EnemyAttackRange … {enemyId, cells}
///   - MoveAttack / PlayerAttack / Trade / DangerZone … {cells} のみ
/// `Map[kind, List[cell]]` に均すと reachable/drawCells の 2 面性や enemyId が失われる。各 mod の
/// `Data` alias をそのまま Option フィールドに持つことで形を保ち、Option の在/不在が表示トグルになる。
///
/// フレーム内 read-after-build のペア（MoveRange→MoveAttackRange / EnemyRange→EnemyAttackRange）は、
/// 前者が put した resource を後者が同フレームで get する順序で解ける。
/// ライフサイクル（clear/refresh/show/toggle）は各 range mod が持つ。
///
/// TurnPhase / CursorState と同じ Ref-based handler 注入パターンに揃える。
mod RangeOverlayState {

    /// 全 7 範囲のセル集合を 1 つに束ねた状態。各フィールドは Option で、None=非表示 / Some=表示。
    /// 形は各 range mod の `Data` alias に一致させる（reachable/drawCells/enemyId を温存）。
    pub type alias Data = {
        moveRange         = Option[MoveRangeScene.Data],
        moveAttackRange   = Option[MoveAttackRangeScene.Data],
        enemyRange        = Option[EnemyRangeScene.Data],
        enemyAttackRange  = Option[EnemyAttackRangeScene.Data],
        playerAttackRange = Option[PlayerAttackRangeScene.Data],
        tradeRange        = Option[TradeRangeScene.Data],
        dangerZone        = Option[DangerZoneScene.Data]
    }

    /// 初期状態（全範囲非表示）。フロア構築（`SceneSetup.addHudAndDrivers`）で put し直して
    /// 前フロアの残存オーバーレイを一掃する。
    pub def empty(): Data =
        {moveRange = None, moveAttackRange = None, enemyRange = None,
         enemyAttackRange = None, playerAttackRange = None, tradeRange = None,
         dangerZone = None}

    /// `withState` が提供する handler 1 つで処理する。
    pub eff State {
        def get(): Data
        def put(target: Data): Unit
    }

    /// 内部 `overlayRef` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let overlayRef: Ref[Data, r] = Ref.fresh(rc, empty());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(overlayRef))
                def put(target, k) = {
                    Ref.put(target, overlayRef);
                    k()
                }
            }
        }
}
