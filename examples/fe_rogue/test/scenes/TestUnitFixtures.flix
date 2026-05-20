// テスト用 UnitResource フィクスチャ
//
// 各 Test*Scene が `NodeTag.Player(...)` / `NodeTag.Enemy(...)` を直接構築する場面で
// `Data#resource` フィールド（UnitResource）を埋めるためのヘルパ。
// 値は「テスト対象ロジックに直接影響しない仮値」であり、本番カタログとは無関係。

mod TestUnitFixtures {

    /// 任意の moveTiles / hp を持つテスト用 UnitResource。
    /// 戦闘 4 値はバランス調整に直結しないテスト用の中庸値（atk=3, def=1, spd=3）。
    /// sprite は character_sheet 既存テクスチャを使い frame=0（実描画は確認しない想定）。
    /// `initialWeapon` はテスト用カタログに普段は登録しない仮 id（ID 解決を踏まないテストでの埋め値）。
    pub def testResource(moveTiles: Int32, hp: Int32): UnitCatalog.UnitResource = {
        moveTiles     = moveTiles,
        hp            = hp,
        attack        = 3,
        defense       = 1,
        speed         = 3,
        initialWeapon = "test-weapon",
        sprite        = {
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
        moveTiles     = moveTiles,
        hp            = hp,
        attack        = attack,
        defense       = defense,
        speed         = speed,
        initialWeapon = "test-weapon",
        sprite        = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0
        }
    }

    /// テスト用 WeaponResource。中庸な攻撃力 2 / 耐久度 10。
    /// 攻撃力や耐久度を変えたい時は `testWeaponFull` を使う。
    pub def testWeapon(): UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = 2,
        durability = 10
    }

    /// 攻撃力 / 耐久度を明示したい時用のテスト用 WeaponResource。
    pub def testWeaponFull(attack: Int32, durability: Int32): UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = attack,
        durability = durability
    }
}
