// テスト用 UnitResource / WeaponResource フィクスチャと共通モック handler。
//
// 各 Test*Scene が `NodeTag.Player(...)` / `NodeTag.Enemy(...)` を直接構築する場面で
// `Data#resource` フィールド（UnitResource）を埋めるためのフィクスチャ群と、
// 副作用 effect (Tween / AnimationPlayer / GameEngine.Game / PartyQuery / RosterQuery)
// を打ち消す「動かない」モック handler を提供する。
//
// quality-assurance SKILL の指針: テスト本体に `run f() with handler X { ... }` を
// 直書きせず、必ずここの `withXxx` 経由で副作用を剥がす。

mod TestUnitFixtures {

    // ════════════════════════════════════════════════════════
    // UnitResource / WeaponResource フィクスチャ
    // ════════════════════════════════════════════════════════

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
            frame   = 0,
            offset  = {x = 0.0, y = 0.0}
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
            frame   = 0,
            offset  = {x = 0.0, y = 0.0}
        }
    }

    /// テスト用 WeaponResource。中庸な攻撃力 2 / 耐久度 10 / 直接攻撃 (range 1-1)。
    /// 攻撃力や耐久度を変えたい時は `testWeaponFull` を使う。
    pub def testWeapon(): UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = 2,
        durability = 10,
        range      = { min = 1, max = 1 },
        sprite     = testSprite()
    }

    /// 攻撃力 / 耐久度を明示したい時用のテスト用 WeaponResource。射程は 1-1 固定。
    pub def testWeaponFull(attack: Int32, durability: Int32): UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = attack,
        durability = durability,
        range      = { min = 1, max = 1 },
        sprite     = testSprite()
    }

    /// テスト用の sprite。テクスチャ名やフレームは戦闘ロジックに影響しないのでダミー値。
    def testSprite(): UnitCatalog.SpriteResource = {
        texture = "test-texture",
        hframes = 1,
        vframes = 1,
        frame   = 0,
        offset  = {x = 0.0, y = 0.0}
    }

    /// テスト用 FontAtlas。`loadScene` が実際に getFontAtlas を呼び出すのは Label2D 系の
    /// ノードを含むシーンだけだが、`withMockGame` が必ず返す必要があるためダミー値を用意する。
    pub def testFontAtlas(): FontAtlas = {
        textureName = "font_test",
        fontSize    = 16.0,
        textureSize = 256.0,
        ascent      = 0.0,
        descent     = 0.0,
        lineGap     = 0.0,
        glyphs      = Map.empty()
    }

    // ════════════════════════════════════════════════════════
    // 共通モック handler
    // ════════════════════════════════════════════════════════
    //
    // 全 helper は effect 多相 (Unit -> a \ ef → a \ (ef - 対象Effect)) で書き、
    // 呼び出し元の他の effect は `ef` で透過させる。テストでは入れ子にせず合成して使う。

    /// Tween.Scheduler のスタブ。schedule / cancel を捨てて何もしない。
    /// gridPos を即更新するロジックの検証で Tween 実体を立ち上げないために使う。
    pub def withNoopTween(thunk: Unit -> a \ ef): a \ (ef - Tween.Scheduler) =
        run { thunk() } with handler Tween.Scheduler {
            def schedule(_, k) = k()
            def isActive(_, k) = k(false)
            def cancel(_, k) = k()
            def consumeUpdates(_, k) = k(Nil)
        }

    /// AnimationPlayer.Scheduler のスタブ。snag / 攻撃アニメは流さず、すべて停止扱い。
    /// physicsProcess の入力 gating が `isPlaying` で行われるため、デフォルトは false 固定。
    pub def withNoopAnim(thunk: Unit -> a \ ef): a \ (ef - AnimationPlayer.Scheduler) =
        run { thunk() } with handler AnimationPlayer.Scheduler {
            def schedule(_, k) = k()
            def isPlaying(_, k) = k(false)
            def stop(_, k) = k()
            def cancelAll(k) = k()
            def activeOwners(k) = k(Nil)
            def consumeTick(_, k) = k(({propertyUpdates = Nil}: AnimationPlayer.Tick))
            def drainSignals(_, k) = k(({methods = Nil, finished = Nil}: AnimationPlayer.EventBundle))
        }

    /// GameEngine.Game のスタブ。renderCommands / 入力系は何もせず、`getFontAtlas` は
    /// `testFontAtlas()` を返す。`getViewportRect` は design 解像度 (128×128) を返す。
    /// SceneLoader.loadSceneWithFont を経由する `XxxScene.add` のテストで使う。
    pub def withMockGame(thunk: Unit -> a \ ef): a \ (ef - GameEngine.Game) =
        run { thunk() } with handler GameEngine.Game {
            def renderCommands(_, _, k)     = k(())
            def initTileBuffer(_, k)        = k((0i32, 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.016))
            def isKeyPressed(_, k)          = k(false)
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(testFontAtlas())
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 128.0, y = 128.0}})
            def getTextureInfo(_, k)        = k(None)
            def setCursor(_, k)             = k(())
        }

    /// PlayerScene.PartyQuery のスタブ。クロージャに閉じ込めた `scene` を読みに行く。
    /// `Game.start` の handler と同じ実装で、`sceneRef` の代わりに引数の scene を使う。
    /// テスト中に「PartyQuery が古い snapshot を返す」状況を再現したい場合は、
    /// このヘルパーに渡す scene を意図的に古い状態にする。
    pub def withMockPartyQuery(scene: Scene[NodeTag], thunk: Unit -> a \ ef):
            a \ (ef - PlayerScene.PartyQuery) =
        run { thunk() } with handler PlayerScene.PartyQuery {
            def get(id, k)          = k(PlayerScene.get(id, scene))
            def getAll(k)           = k(PlayerScene.getAll(scene))
            def getGridPos(id, k)   = k(PlayerScene.getGridPos(id, scene))
            def getMoveTiles(id, k) = k(PlayerScene.getMoveTiles(id, scene))
        }

    /// EnemyScene.RosterQuery のスタブ。クロージャに閉じ込めた `scene` を読みに行く。
    /// `Game.start` の handler と同じ実装で、`sceneRef` の代わりに引数の scene を使う。
    pub def withMockRosterQuery(scene: Scene[NodeTag], thunk: Unit -> a \ ef):
            a \ (ef - EnemyScene.RosterQuery) =
        run { thunk() } with handler EnemyScene.RosterQuery {
            def get(id, k)         = k(EnemyScene.get(id, scene))
            def getAll(k)          = k(EnemyScene.getAll(scene))
            def findIdAt(coord, k) = k(EnemyScene.findIdAt(coord, scene))
            def anyAttacking(k)    = k(EnemyScene.anyAttacking(scene))
        }
}
