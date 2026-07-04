// Worldline — World の軌跡（履歴・巻き戻し・リプレイ・分岐の土台）
//
// World は状態の点、Worldline はその点がたどる線。巻き戻しとは世界線を遡ること、
// やり直しとは遡った線を再び下ること。ここは特定の World 型に依存しない `List[a]` 上の
// 純粋な zipper で、過去(past)・現在(current)・未来(future) の三つ組で「今どこにいるか」を保つ。
//
//   past    : 現在より前の状態。先頭が「1つ前」（most-recent-first）。undo で1つ current へ昇る。
//   current : 今の状態（世界線上の現在地）。
//   future  : undo で遡って手放した状態。先頭が「1つ先」。redo で1つ current へ戻す。
//   cap     : past に保つ最大数。record が古い端から捨てる（世界線は無限には遡れない）。
//
// 契約:
//   - record は「新しい現在へ進む」= 現在を past へ積み、future を捨てる（分岐したら未来は無効）。
//   - undo/redo は current と past/future の間で1状態を移すだけ（構造共有ゆえ安価）。
//   - undoBy(k) は k 段遡る。past が尽きたら最古で止まる（clamp）。手放した分は future に積む。
//   - future は cap で刈らない（redo は record までの一時的な線で、次の record で必ず消える）。
//
// 永続 List ゆえ past は tail を構造共有する。N 段の履歴を持っても各 record は先頭 1 セル追加＋
// cap 超過時の切り詰めだけで、World を丸ごと複製しない — これが巻き戻しが安い理由。

mod Worldline {

    pub enum Worldline[a] {
        case Worldline({ past = List[a], current = a, future = List[a], cap = Int32 })
    }

    /// 初期状態 1 点だけの世界線を作る。past/future は空、cap は past の最大保持数。
    /// cap <= 0 は「過去を残さない」= record しても遡れない世界線になる。
    pub def make(initial: a, cap: Int32): Worldline[a] =
        Worldline.Worldline({ past = Nil, current = initial, future = Nil, cap = cap })

    /// 今の状態（世界線上の現在地）。
    pub def current(wl: Worldline[a]): a =
        let Worldline.Worldline(r) = wl;
        r#current

    /// current だけを差し替える（past/future は不動 = 履歴を刻まない補正）。
    /// 遡った現在地に瞬間的な調整（入力エッジ状態の引き継ぎ等）を乗せる時に使う。record と違い
    /// 新しい一手にはならない — 世界線上の位置は変えず、その点の値だけを置き換える。
    pub def replaceCurrent(a: a, wl: Worldline[a]): Worldline[a] =
        let Worldline.Worldline(r) = wl;
        Worldline.Worldline({ current = a | r })

    /// 新しい現在へ進む。今の current を past へ積み（cap で古い端を切り詰め）、future を捨てる。
    /// future を捨てるのは「遡った先で別の一手を指したら、辿らなかった未来は無効になる」ため。
    pub def record(a: a, wl: Worldline[a]): Worldline[a] =
        let Worldline.Worldline(r) = wl;
        Worldline.Worldline({
            past = List.take(r#cap, r#current :: r#past),
            current = a,
            future = Nil
            | r
        })

    /// 1 段遡る。past が空なら何もしない（最古で止まる）。手放した current は future へ積む。
    pub def undo(wl: Worldline[a]): Worldline[a] =
        let Worldline.Worldline(r) = wl;
        match r#past {
            case Nil     => wl
            case p :: ps =>
                Worldline.Worldline({ past = ps, current = p, future = r#current :: r#future | r })
        }

    /// 1 段下る（やり直し）。future が空なら何もしない。手放した current は past へ戻す。
    pub def redo(wl: Worldline[a]): Worldline[a] =
        let Worldline.Worldline(r) = wl;
        match r#future {
            case Nil     => wl
            case f :: fs =>
                Worldline.Worldline({ past = r#current :: r#past, current = f, future = fs | r })
        }

    /// k 段遡る。past が尽きたら最古で止まる（k が履歴長を超えても最古に clamp）。
    /// k <= 0 は現状維持。dodge の popHistory(k) と同じ端条件を、undo の反復で表す。
    pub def undoBy(k: Int32, wl: Worldline[a]): Worldline[a] =
        if (k <= 0 or not canUndo(wl)) wl
        else undoBy(k - 1, undo(wl))

    /// k 段下る。future が尽きたら最新で止まる。undoBy の対。
    pub def redoBy(k: Int32, wl: Worldline[a]): Worldline[a] =
        if (k <= 0 or not canRedo(wl)) wl
        else redoBy(k - 1, redo(wl))

    /// 遡れるか（past が空でないか）。
    pub def canUndo(wl: Worldline[a]): Bool =
        let Worldline.Worldline(r) = wl;
        not List.isEmpty(r#past)

    /// 下れるか（future が空でないか）。
    pub def canRedo(wl: Worldline[a]): Bool =
        let Worldline.Worldline(r) = wl;
        not List.isEmpty(r#future)

    /// 遡れる段数（past の長さ）。
    pub def pastLength(wl: Worldline[a]): Int32 =
        let Worldline.Worldline(r) = wl;
        List.length(r#past)

    /// 下れる段数（future の長さ）。
    pub def futureLength(wl: Worldline[a]): Int32 =
        let Worldline.Worldline(r) = wl;
        List.length(r#future)

    /// 世界線上の総状態数（past + current + future）。
    pub def length(wl: Worldline[a]): Int32 =
        let Worldline.Worldline(r) = wl;
        List.length(r#past) + 1 + List.length(r#future)
}
