/// PartySelection — 出撃メンバー（ロード + ランダム抽選分）をゲーム全体で 1 つ保持する effect
///
/// キャラクターのシャッフルは **ゲーム開始時 / 全滅リスタート / 全クリア周回時のみ** 行い、
/// フロア間の移動では同じメンバーを維持する、という要件のための保持場所。
///
/// `PlayerScene.add` は構築のたびに呼ばれる（フロアごとに再 build される）が、
/// すでに選抜済み（`Some`）ならそれを再利用し、未選抜（`None`）のときだけ抽選して `put` する。
/// 「フレッシュな party で始めたい」経路（ゲームオーバー復帰 / クリアループ）は `clear()` を
/// 呼んで `None` に戻すことで、次の build で再抽選させる。
///
/// ゲーム起動時に一箇所で handler を注入することで、どの Scene からも同じ Ref を参照できる。
/// 初期値は `None`（= 最初の build で抽選される）。
mod PartySelection {

    /// 選抜済み出撃メンバーの読み書き effect。中身は `(クラス id, PlayerResource)` のリスト
    /// （先頭がロード）。id を併せ持つのは、スポーンした味方の `classId` をスナップショット保存できる
    /// ようにするため（PlayerResource は name を持たず resource から id を逆引きできない）。
    pub eff State {
        /// 選抜済みなら `Some(party)`、未選抜なら `None` を返す。
        def get(): Option[List[(String, UnitCatalog.PlayerResource)]]
        /// 選抜結果を保存する（以降の build はこれを再利用する）。
        def put(sel: List[(String, UnitCatalog.PlayerResource)]): Unit
        /// 選抜をリセットして `None` に戻す（次の build で再抽選させる）。
        def clear(): Unit
    }

    /// Ref を closure に閉じ込めた handler 注入パターン。
    /// 内部 `selRef` は closure に閉じ込められ、外からは見えない。初期値は `None`。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let selRef: Ref[Option[List[(String, UnitCatalog.PlayerResource)]], r] =
                Ref.fresh(rc, None);
            run {
                thunk()
            } with handler State {
                def get(k)      = k(Ref.get(selRef))
                def put(sel, k) = { Ref.put(Some(sel), selRef); k() }
                def clear(k)    = { Ref.put(None, selRef); k() }
            }
        }
}
