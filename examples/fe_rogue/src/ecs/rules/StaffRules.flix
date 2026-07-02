/// StaffRules — 杖 / 投擲アイテムの純粋 leaf rules（Scene / effect 非依存）
///
/// `StaffCast` の適用 orchestration から切り出した、Scene も乱数も持たない純関数群。
/// ワープ先セル選定（`warpCellFor`）・完全停止 Status 付与（`bindStatuses`）・
/// 投擲デバフ Status 生成（`directionalStatus`）。数値・盤面・カタログだけでテストできる。
/// 効果の実適用（HP 変更・ノード移動・ログ）は StaffCast 側（effectful）に残す。
mod StaffRules {

    /// 中心セルに隣接する 4 マスのうち、歩けて空いているマスを 1 つ返す（無ければ None）。
    def adjacentFreeCell(center: {x = Int32, y = Int32}, board: Board):
            Option[{x = Int32, y = Int32}] =
        let dirs = Staff.Direction.Up :: Staff.Direction.Down
                    :: Staff.Direction.Left :: Staff.Direction.Right :: Nil;
        dirs
            |> List.map(d -> Board.stepTarget(center, Staff.toVec2i(d)))
            |> List.filter(c -> Board.isWalkable(board, c) and not Board.isOccupied(c, board))
            |> List.head

    /// ワープ先セルを選ぶ純粋関数。階段が空いていれば階段、埋まっていれば階段に隣接する
    /// 歩ける空きマス、どちらも無ければ None（停止だけ適用してワープしない）。
    pub def warpCellFor(stairs: Option[{x = Int32, y = Int32}], board: Board):
            Option[{x = Int32, y = Int32}] =
        match stairs {
            case None     => None
            case Some(st) =>
                if (not Board.isOccupied(st, board)) Some(st)
                else adjacentFreeCell(st, board)
        }

    /// 完全停止を `turns` ターンで 1 件付与する純粋関数。`add` が重ねがけを防ぐので、既に停止中なら据え置かれる。
    pub def bindStatuses(turns: Int32, xs: List[StatusSystem.Status]): List[StatusSystem.Status] =
        StatusSystem.add(StatusSystem.immobilizeFor(turns), xs)

    /// 投擲系アイテムが付与する時限デバフ Status を作る。投擲系でなければ None。
    pub def directionalStatus(item: Consumable.ConsumableResource): Option[StatusSystem.Status] =
        match item#effect {
            case Consumable.ConsumableEffect.BlindHit   =>
                Some({effect = StatusSystem.StatusEffect.HitDown,
                      magnitude = item#magnitude, remaining = item#duration})
            case Consumable.ConsumableEffect.SpdDownHit =>
                Some({effect = StatusSystem.StatusEffect.SpdDown,
                      magnitude = item#magnitude, remaining = item#duration})
            case Consumable.ConsumableEffect.DefDownHit =>
                Some({effect = StatusSystem.StatusEffect.DefDown,
                      magnitude = item#magnitude, remaining = item#duration})
            case _                                      => None
        }

}
