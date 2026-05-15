// テスト用 UnitResource フィクスチャ
//
// 各 Test*Scene が `NodeTag.Player(...)` / `NodeTag.Enemy(...)` を直接構築する場面で
// `Data#resource` フィールド（UnitResource）を埋めるためのヘルパ。
// 値は「テスト対象ロジックに直接影響しない仮値」であり、本番カタログとは無関係。

mod TestUnitFixtures {

    /// 任意の moveTiles / hp を持つテスト用 UnitResource。
    /// 戦闘 4 値はバランス調整に直結しないテスト用の中庸値（atk=3, def=1, spd=3）。
    /// sprite は character_sheet 既存テクスチャを使い frame=0（実描画は確認しない想定）。
    pub def testResource(moveTiles: Int32, hp: Int32): UnitCatalog.UnitResource = {
        moveTiles = moveTiles,
        hp        = hp,
        attack    = 3,
        defense   = 1,
        speed     = 3,
        sprite    = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0
        }
    }

    /// 戦闘パラメータも明示的に指定したいケース用。
    pub def testResourceFull(moveTiles: Int32, hp: Int32,
                              attack: Int32, defense: Int32, speed: Int32):
                              UnitCatalog.UnitResource = {
        moveTiles = moveTiles,
        hp        = hp,
        attack    = attack,
        defense   = defense,
        speed     = speed,
        sprite    = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0
        }
    }
}
