/// SuspendSave — 中断セーブのディスク表現（`FloorSnapshot.T` ＋ 使用済みフラグ）。
///
/// 中断セーブは「再開すると消える」（save-scum 防止）。`Fs`（flix_render_core 由来）に
/// ファイル削除 API が無いため、**削除の代わりに `consumed = true` で上書き**する。
///   - 保存時:  `make(false, 現在のフロア)`
///   - 再開時:  snapshot を使って復元したあと `make(true, snapshot)` で上書き
///   - タイトル: `resumable` が `Some` のときだけ「中断から再開」を有効化する
///
/// `Saveable` instance は nominal 型にしか付けられない（`FloorSnapshot.T` は type alias で不可）ため、
/// レコードを `enum Save` でラップする（catalog 群が `CatalogContainer` を enum で包むのと同じ理由）。
/// codec は `FloorSnapshotCodec` に委譲し、ここでは consumed の Bool だけを足す薄い wrap。
mod SuspendSave {

    /// ディスクに書く中断セーブ 1 件を nominal 型で包む。`consumed = true` は「使用済み（再開不可）」。
    pub enum Save {
        case Save({consumed = Bool, snapshot = FloorSnapshot.T})
    }

    /// 中断セーブのスロット番号（1 スロット固定 → `saves/slot1.json`）。
    pub def slot(): Int32 = 1

    /// セーブを組み立てる。
    pub def make(consumed: Bool, snapshot: FloorSnapshot.T): Save =
        Save.Save({consumed = consumed, snapshot = snapshot})

    /// 使用済みフラグ。
    pub def consumedOf(save: Save): Bool =
        let Save.Save(rec) = save;
        rec#consumed

    /// 内包するフロアスナップショット。
    pub def snapshotOf(save: Save): FloorSnapshot.T =
        let Save.Save(rec) = save;
        rec#snapshot

    /// 中断セーブとして再開できるか（未使用なら `Some(snapshot)`、使用済み / 不在なら `None`）。
    /// `SaveManager.read` の結果（不在・パース失敗は既に `None`）をそのまま受けて判定する。
    pub def resumable(save: Option[Save]): Option[FloorSnapshot.T] =
        save |> Option.flatMap(s -> if (consumedOf(s)) None else Some(snapshotOf(s)))
}

// ════════════════════════════════════════════════════════════════════════
// Saveable[SuspendSave.Save] — slot1 の JSON round-trip（snapshot は FloorSnapshot codec へ委譲）
// ════════════════════════════════════════════════════════════════════════

instance Saveable[SuspendSave.Save] {
    pub def toJson(value: SuspendSave.Save): Util.Json.Json =
        Util.Json.Json.JObject(Map#{
            "consumed" => Util.Json.Json.JBool(SuspendSave.consumedOf(value)),
            "snapshot" => FloorSnapshotCodec.encode(SuspendSave.snapshotOf(value))
        })

    pub def fromJson(element: Util.Json.Json): Option[SuspendSave.Save] =
        forM (
            obj      <- JsonCodec.expectObject(element);
            consJ    <- Map.get("consumed", obj);
            snapJ    <- Map.get("snapshot", obj);
            consumed <- JsonCodec.expectBool(consJ);
            snapshot <- FloorSnapshotCodec.decode(snapJ)
        ) yield SuspendSave.make(consumed, snapshot)
}
