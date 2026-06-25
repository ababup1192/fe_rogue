// EditHistory — エディタ編集の履歴を保持し、Cmd+Z で巻き戻す仕組み
//
// algebraic effect として `Rewind` を切り出し、各編集箇所（ドラッグドロップ・矢印 nudge・
// リサイズハンドルドラッグ）が直前の状態を `save` する。Cmd+Z 押下時に `rewind` で
// 取り出して、ノードを記録された状態（位置 / スケール）に戻して JSON にも書き戻す。

mod EditHistory {

    /// 1 編集の巻き戻し情報。位置/リサイズ/回転は CommandEntry（EditCmd.Command）へ移行済み。
    /// 残る個別 Entry は scale-nudge（ScaleEntry）と構造変更（RemoveSubtree/AddedNode）のみ。
    /// nodePath は live scene 内の path、jsonNodePath は JSON 内の path（プレハブ由来で先頭名が違う）。
    pub enum Entry {
        /// scale nudge（Ctrl+Shift+矢印）専用。Phase B でまだ CommandEntry 未移行。
        case ScaleEntry({jsonPath = String, nodePath = NodePath,
                         jsonNodePath = NodePath,
                         prevWorldPos = Vec2.Vec2, prevScale = Vec2.Vec2})
        /// ノード削除の巻き戻し情報。除去したサブツリーの JSON 断片と、
        /// 親 path・配列 index を保持し、Undo 時に insertSubtree で同位置へ戻す。
        case RemoveSubtreeEntry({jsonPath = String, parentPath = NodePath,
                                 index = Int32,
                                 fragment = JsonOrdered.OrderedJson})
        /// ノード追加/複製の巻き戻し情報。追加したノードの path を保持し、
        /// Undo 時に removeChild で取り除く。
        case AddedNodeEntry({jsonPath = String, nodePath = NodePath})
        /// 統一 Edit Command（Phase B）。保持する命令を applyTo すれば undo になる。
        /// 命令自体が逆操作（適用前状態を捕捉済み）なので、種別ごとの巻き戻し分岐が不要。
        case CommandEntry(EditCmd.Command)
    }

    /// 編集履歴 stack を扱うエフェクト。
    ///   - save:   編集直前の状態を 1 件積む
    ///   - rewind: 直近の保存を取り出す（LIFO）。空ならば None
    pub eff Rewind {
        def save(entry: Entry): Unit
        def rewind(): Option[Entry]
    }
}
