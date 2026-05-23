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
    /// 魔力・魔防はデフォルト 0（物理武器主体のテスト用デフォルト）。
    /// sprite は character_sheet 既存テクスチャを使い frame=0（実描画は確認しない想定）。
    /// `initialWeapon` はテスト用カタログに普段は登録しない仮 id（ID 解決を踏まないテストでの埋め値）。
    pub def testResource(moveTiles: Int32, hp: Int32): UnitCatalog.UnitResource = {
        moveTiles     = moveTiles,
        hp            = hp,
        attack        = 3,
        defense       = 1,
        magicAttack   = 0,
        magicDefense  = 0,
        speed         = 3,
        initialWeapon = "test-weapon",
        initialStaves = Nil,
        sprite        = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0,
            offset  = {x = 0.0, y = 0.0}
        }
    }

    /// 戦闘パラメータも明示的に指定したいケース用。
    /// 魔力・魔防はデフォルト 0（物理戦闘のテスト用）。魔法戦闘を組みたい場合は
    /// `testResourceMagic` を使う。
    pub def testResourceFull(moveTiles: Int32, hp: Int32,
                              attack: Int32, defense: Int32, speed: Int32):
                              UnitCatalog.UnitResource = {
        moveTiles     = moveTiles,
        hp            = hp,
        attack        = attack,
        defense       = defense,
        magicAttack   = 0,
        magicDefense  = 0,
        speed         = speed,
        initialWeapon = "test-weapon",
        initialStaves = Nil,
        sprite        = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0,
            offset  = {x = 0.0, y = 0.0}
        }
    }

    /// 魔力・魔防まで明示したいケース用。物理ステ・魔法ステを両方検証したいときに使う。
    pub def testResourceMagic(moveTiles: Int32, hp: Int32,
                               attack: Int32, defense: Int32,
                               magicAttack: Int32, magicDefense: Int32,
                               speed: Int32): UnitCatalog.UnitResource = {
        moveTiles     = moveTiles,
        hp            = hp,
        attack        = attack,
        defense       = defense,
        magicAttack   = magicAttack,
        magicDefense  = magicDefense,
        speed         = speed,
        initialWeapon = "test-weapon",
        initialStaves = Nil,
        sprite        = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0,
            offset  = {x = 0.0, y = 0.0}
        }
    }

    /// テスト用 WeaponResource。中庸な攻撃力 2 / 耐久度 10 / 直接攻撃 (range 1-1)。
    /// デフォルトは物理武器。
    /// 攻撃力や耐久度を変えたい時は `testWeaponFull` を、武器タイプを切り替えたい時は
    /// `testWeaponWithType` を使う。
    pub def testWeapon(): UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = 2,
        durability = 10,
        range      = { min = 1, max = 1 },
        weaponType = UnitCatalog.WeaponType.Physical,
        sprite     = testSprite()
    }

    /// 攻撃力 / 耐久度を明示したい時用のテスト用 WeaponResource。射程は 1-1 固定、物理武器扱い。
    pub def testWeaponFull(attack: Int32, durability: Int32): UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = attack,
        durability = durability,
        range      = { min = 1, max = 1 },
        weaponType = UnitCatalog.WeaponType.Physical,
        sprite     = testSprite()
    }

    /// 物理/魔法トグルを切り替えたい時用のテスト用 WeaponResource。射程は 1-1 固定、耐久 10。
    pub def testWeaponWithType(attack: Int32, weaponType: UnitCatalog.WeaponType):
            UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = attack,
        durability = 10,
        range      = { min = 1, max = 1 },
        weaponType = weaponType,
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

    /// `withMockGame` のキー押下を指定述語に切り替えるバリエーション。
    /// 例: `withMockGameKeys(k -> k == GameEngine.Key.Up, () -> ...)` で「Up キーだけ押下中」を再現。
    /// 他の Game メソッドは `withMockGame` と同じデフォルト挙動。
    pub def withMockGameKeys(pressed: GameEngine.Key -> Bool,
                              thunk: Unit -> a \ ef): a \ (ef - GameEngine.Game) =
        run { thunk() } with handler GameEngine.Game {
            def renderCommands(_, _, k)     = k(())
            def initTileBuffer(_, k)        = k((0i32, 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.016))
            def isKeyPressed(key, k)        = k(pressed(key))
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(testFontAtlas())
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 128.0, y = 128.0}})
            def getTextureInfo(_, k)        = k(None)
            def setCursor(_, k)             = k(())
        }

    /// AnimationPlayer.Scheduler のスタブで **`isPlaying` を true 固定**。
    /// `physicsProcess` などの「アニメ再生中は入力捨てる」分岐を観測するためのテストヘルパー。
    pub def withPlayingAnim(thunk: Unit -> a \ ef): a \ (ef - AnimationPlayer.Scheduler) =
        run { thunk() } with handler AnimationPlayer.Scheduler {
            def schedule(_, k) = k()
            def isPlaying(_, k) = k(true)
            def stop(_, k) = k()
            def cancelAll(k) = k()
            def activeOwners(k) = k(Nil)
            def consumeTick(_, k) = k(({propertyUpdates = Nil}: AnimationPlayer.Tick))
            def drainSignals(_, k) = k(({methods = Nil, finished = Nil}: AnimationPlayer.EventBundle))
        }

    /// BoardQuery のスタブ。指定 `board` を毎回返す。
    /// テストで盤面を 1 つ用意して、その盤面の上での挙動を検証する用途。
    pub def withMockBoard(board: Board, thunk: Unit -> a \ ef): a \ (ef - BoardQuery) =
        run { thunk() } with handler BoardQuery {
            def board(k) = k(board)
        }

    /// GameLogger.GameLogger の no-op スタブ。
    /// ログの中身を検証しないテストで、ログ出力の effect だけ剥がす用途に使う。
    pub def withMockGameLogger(thunk: Unit -> a \ ef):
            a \ (ef - GameLogger.GameLogger) =
        run { thunk() } with handler GameLogger.GameLogger {
            def playerLog(_, k)    = k()
            def enemyLog(_, k)     = k()
            def gameOverLog(_, k)  = k()
            def endTurn(k)         = k()
            def drainEntries(k)    = k(Nil)
        }

    /// EnemyTurn.Queue の no-op スタブ。`isEmpty` は true、その他の操作は捨てる。
    /// 「敵ターンの駆動」までは見ないテスト（味方ターンの挙動だけ確認する系）で使う。
    pub def withMockEnemyTurnQueue(thunk: Unit -> a \ ef):
            a \ (ef - EnemyTurn.Queue) =
        run { thunk() } with handler EnemyTurn.Queue {
            def popFront(k)     = k(None)
            def pushFront(_, k) = k()
            def replace(_, k)   = k()
            def peekFront(k)    = k(None)
            def isEmpty(k)      = k(true)
        }
}
