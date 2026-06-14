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
    /// `initialInventory` はテスト用カタログに普段は登録しない仮 id（ID 解決を踏まないテストでの埋め値）。
    pub def testResource(moveTiles: Int32, hp: Int32): UnitCatalog.UnitResource = {
        moveTiles     = moveTiles,
        level         = 1,
        hp            = hp,
        attack        = 3,
        defense       = 1,
        magicAttack   = 0,
        magicDefense  = 0,
        speed         = 3,
        skill         = 2,
        luck          = 2,
        initialInventory =
            ({kind = UnitBase.ItemKind.Weapon, id = "test-weapon"}:
               UnitBase.InventoryEntry) :: Nil,
        description   = "",
        sprite        = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0,
            offset  = {x = 0.0, y = 0.0},
            scale   = {x = 1.0, y = 1.0},
            flipForFacing = false
        },
        spriteFrames  = None,
        growthRates   = UnitCatalog.zeroGrowthRates(),
        // テストでは武器タイプ習熟による 80% 補正を起こさないよう全タイプ得意にする。
        proficientWeaponTypes = WeaponCatalog.allWeaponTypes(),
        canOpenChests = false
    }

    /// 任意の moveTiles / hp を持つテスト用 EnemyResource（敵カタログ）。
    /// `testResource` から **growthRates を除いた** 共有 14 フィールドのみ（敵は成長率を持たない）。
    /// `NodeTag.Enemy(...)` の `Data#resource` を埋める用途。値は `testResource` と揃える。
    pub def testEnemyResource(moveTiles: Int32, hp: Int32): EnemyCatalog.EnemyResource = {
        moveTiles     = moveTiles,
        level         = 1,
        hp            = hp,
        attack        = 3,
        defense       = 1,
        magicAttack   = 0,
        magicDefense  = 0,
        speed         = 3,
        skill         = 2,
        luck          = 2,
        initialInventory =
            ({kind = UnitBase.ItemKind.Weapon, id = "test-weapon"}:
               UnitBase.InventoryEntry) :: Nil,
        description   = "",
        sprite        = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0,
            offset  = {x = 0.0, y = 0.0},
            scale   = {x = 1.0, y = 1.0},
            flipForFacing = false
        },
        spriteFrames  = None,
        aiType        = EnemyAI.AiType.Aggressive,
        ring          = None
    }

    /// 戦闘パラメータも明示的に指定したいケース用。
    /// 魔力・魔防はデフォルト 0（物理戦闘のテスト用）。魔法戦闘を組みたい場合は
    /// `testResourceMagic` を使う。
    pub def testResourceFull(moveTiles: Int32, hp: Int32,
                              attack: Int32, defense: Int32, speed: Int32):
                              UnitCatalog.UnitResource = {
        moveTiles     = moveTiles,
        level         = 1,
        hp            = hp,
        attack        = attack,
        defense       = defense,
        magicAttack   = 0,
        magicDefense  = 0,
        speed         = speed,
        skill         = 2,
        luck          = 2,
        initialInventory =
            ({kind = UnitBase.ItemKind.Weapon, id = "test-weapon"}:
               UnitBase.InventoryEntry) :: Nil,
        description   = "",
        sprite        = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0,
            offset  = {x = 0.0, y = 0.0},
            scale   = {x = 1.0, y = 1.0},
            flipForFacing = false
        },
        spriteFrames  = None,
        growthRates   = UnitCatalog.zeroGrowthRates(),
        // テストでは武器タイプ習熟による 80% 補正を起こさないよう全タイプ得意にする。
        proficientWeaponTypes = WeaponCatalog.allWeaponTypes(),
        canOpenChests = false
    }

    /// 魔力・魔防まで明示したいケース用。物理ステ・魔法ステを両方検証したいときに使う。
    pub def testResourceMagic(moveTiles: Int32, hp: Int32,
                               attack: Int32, defense: Int32,
                               magicAttack: Int32, magicDefense: Int32,
                               speed: Int32): UnitCatalog.UnitResource = {
        moveTiles     = moveTiles,
        level         = 1,
        hp            = hp,
        attack        = attack,
        defense       = defense,
        magicAttack   = magicAttack,
        magicDefense  = magicDefense,
        speed         = speed,
        skill         = 2,
        luck          = 2,
        initialInventory =
            ({kind = UnitBase.ItemKind.Weapon, id = "test-weapon"}:
               UnitBase.InventoryEntry) :: Nil,
        description   = "",
        sprite        = {
            texture = "character_sheet",
            hframes = 5,
            vframes = 2,
            frame   = 0,
            offset  = {x = 0.0, y = 0.0},
            scale   = {x = 1.0, y = 1.0},
            flipForFacing = false
        },
        spriteFrames  = None,
        growthRates   = UnitCatalog.zeroGrowthRates(),
        // テストでは武器タイプ習熟による 80% 補正を起こさないよう全タイプ得意にする。
        proficientWeaponTypes = WeaponCatalog.allWeaponTypes(),
        canOpenChests = false
    }

    /// テスト用 WeaponResource。中庸な攻撃力 2 / 耐久度 10 / 直接攻撃 (range 1-1)。
    /// デフォルトは剣 (物理武器)。
    /// 攻撃力や耐久度を変えたい時は `testWeaponFull` を、武器タイプを切り替えたい時は
    /// `testWeaponWithType` を使う。
    pub def testWeapon(): UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = 2,
        hit        = 80,
        crit       = 0,
        durability = 10,
        range      = { min = 1, max = 1 },
        weaponType = WeaponCatalog.WeaponType.Sword,
        effect      = WeaponCatalog.WeaponEffect.NoEffect,
        effectValue = 0,
        sprite     = testSprite(),
        description = "",
        effectRule = None
    }

    /// 攻撃力 / 耐久度を明示したい時用のテスト用 WeaponResource。射程は 1-1 固定、剣 (物理武器) 扱い。
    pub def testWeaponFull(attack: Int32, durability: Int32): UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = attack,
        hit        = 80,
        crit       = 0,
        durability = durability,
        range      = { min = 1, max = 1 },
        weaponType = WeaponCatalog.WeaponType.Sword,
        effect      = WeaponCatalog.WeaponEffect.NoEffect,
        effectValue = 0,
        sprite     = testSprite(),
        description = "",
        effectRule = None
    }

    /// 物理/魔法トグルを切り替えたい時用のテスト用 WeaponResource。射程は 1-1 固定、耐久 10。
    pub def testWeaponWithType(attack: Int32, weaponType: WeaponCatalog.WeaponType):
            UnitCatalog.WeaponResource = {
        name       = "test-weapon",
        attack     = attack,
        hit        = 80,
        crit       = 0,
        durability = 10,
        range      = { min = 1, max = 1 },
        weaponType = weaponType,
        effect      = WeaponCatalog.WeaponEffect.NoEffect,
        effectValue = 0,
        sprite     = testSprite(),
        description = "",
        effectRule = None
    }

    /// テスト用の sprite。テクスチャ名やフレームは戦闘ロジックに影響しないのでダミー値。
    def testSprite(): Sprite.SpriteResource = {
        texture = "test-texture",
        hframes = 1,
        vframes = 1,
        frame   = 0,
        offset  = {x = 0.0, y = 0.0},
        scale   = {x = 1.0, y = 1.0},
        flipForFacing = false
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
            def renderCommands(_, _, _, k)     = k(())
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

    /// PlayerData.PartyQuery のスタブ。クロージャに閉じ込めた `scene` を読みに行く。
    /// `Game.start` の handler と同じ実装で、`sceneRef` の代わりに引数の scene を使う。
    /// テスト中に「PartyQuery が古い snapshot を返す」状況を再現したい場合は、
    /// このヘルパーに渡す scene を意図的に古い状態にする。
    pub def withMockPartyQuery(scene: Scene[NodeTag], thunk: Unit -> a \ ef):
            a \ (ef - PlayerData.PartyQuery) =
        run { thunk() } with handler PlayerData.PartyQuery {
            def get(id, k)          = k(PlayerScene.get(id, scene))
            def getAll(k)           = k(PlayerScene.getAll(scene))
        }

    /// EnemyData.RosterQuery のスタブ。クロージャに閉じ込めた `scene` を読みに行く。
    /// `Game.start` の handler と同じ実装で、`sceneRef` の代わりに引数の scene を使う。
    pub def withMockRosterQuery(scene: Scene[NodeTag], thunk: Unit -> a \ ef):
            a \ (ef - EnemyData.RosterQuery) =
        run { thunk() } with handler EnemyData.RosterQuery {
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
            def renderCommands(_, _, _, k)     = k(())
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

    /// AnimationPlayer.Scheduler のスタブで **`drainSignals` を owner 別に応答**させる。
    /// `ownerPath` 宛の drain にだけ `bundle` を返し、他 owner 宛には空 bundle を返す
    /// （実物 Scheduler の「自分宛 signal だけ pull できる」挙動の再現）。
    /// CombatScene.process の「他ユニットのシグナルを食わない」検証に使う。
    pub def withSignalsFor(ownerPath: NodePath, bundle: AnimationPlayer.EventBundle,
                            thunk: Unit -> a \ ef): a \ (ef - AnimationPlayer.Scheduler) =
        run { thunk() } with handler AnimationPlayer.Scheduler {
            def schedule(_, k) = k()
            def isPlaying(_, k) = k(false)
            def stop(_, k) = k()
            def cancelAll(k) = k()
            def activeOwners(k) = k(Nil)
            def consumeTick(_, k) = k(({propertyUpdates = Nil}: AnimationPlayer.Tick))
            def drainSignals(owner, k) =
                if (owner == ownerPath) k(bundle)
                else k(({methods = Nil, finished = Nil}: AnimationPlayer.EventBundle))
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

    /// GameEngine.Audio の no-op スタブ。効果音再生の effect だけ剥がす用途。
    /// 例: `onActionConfirmed` が「階段」で `play("change_floor")` を鳴らすため、
    /// それを呼ぶテストはこのハンドラで Audio effect を吸収する。
    pub def withMockAudio(thunk: Unit -> a \ ef):
            a \ (ef - GameEngine.Audio) =
        run { thunk() } with handler GameEngine.Audio {
            def playAudio(_, k)     = k()
            def stopAudio(_, k)     = k()
            def setVolume(_, _, k)  = k()
            def setLooping(_, _, k) = k()
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

    /// Math.Random の決定的スタブ。`randomFloat64` を 0.5 固定で返す。
    /// `rollPercent()`(= floor(randomFloat64 * 100)) が常に 50 になるので、
    /// `Combat.isHit(hitRate, 50)` の命中/回避境界（hitRate > 50 で命中）を決定的にできる。
    /// 成長判定（`rollGrowth` の各ロール）も全て 50 固定になる。
    pub def withMockRandom(thunk: Unit -> a \ ef): a \ (ef - Math.Random) =
        run { thunk() } with handler Math.Random {
            def randomFloat64(k) = k(0.5)
            def randomInt64(k)   = k(42i64)
        }

    // ════════════════════════════════════════════════════════
    // フェーズ / 選択駒 / フロア進行 の effect モック
    //   各テストファイルに散在していた inline handler・重複ローカル def を集約。
    //   固定値版（read-only, put 破棄）と Ref-backed 版（put 観測可）の 2 系統。
    // ════════════════════════════════════════════════════════

    /// `TurnPhase.State` を固定フェーズで返すスタブ。put は捨てる。
    /// フェーズ遷移を観測しない（refreshItems / visibility / メニュー項目構築など）系で使う。
    pub def withFixedPhase(phase: TurnPhase.Phase, thunk: Unit -> a \ ef):
            a \ (ef - TurnPhase.State) =
        run { thunk() } with handler TurnPhase.State {
            def get(k)    = k(phase)
            def put(_, k) = k()
        }

    /// `SelectedPlayer.State` を「id 選択中・drafts 空」で固定するスタブ。put は捨てる。
    /// drafts を巻き戻さないテスト（項目構築 / 隣接判定 / 緑マス描画）用。
    /// 未選択は `withNoSelection`、id+drafts を観測したいときは `withSelectionRef` を使う。
    pub def withSelectedPlayer(id: Int32, thunk: Unit -> a \ ef):
            a \ (ef - SelectedPlayer.State) =
        run { thunk() } with handler SelectedPlayer.State {
            def get(k)    = k({id = Some(id), drafts = Nil, gatherActive = false})
            def put(_, k) = k()
        }

    /// `SelectedPlayer.State` を未選択（`cleared()`）で固定するスタブ。put は捨てる。
    /// 空マスメニュー / ローグメニュー / ゲームオーバー経路など「選択駒なし」を再現する。
    pub def withNoSelection(thunk: Unit -> a \ ef):
            a \ (ef - SelectedPlayer.State) =
        run { thunk() } with handler SelectedPlayer.State {
            def get(k)    = k(SelectedPlayer.cleared())
            def put(_, k) = k()
        }

    /// `CustomEffects.FloorAdvanceRequest` の no-op スタブ。`advance` は渡された scene をそのまま返す。
    /// 「かいだん」分岐を踏まないアクション確定系テスト用（踏むテストは別途実 handler を使う）。
    pub def withNoopFloorAdvance(thunk: Unit -> a \ ef):
            a \ (ef - CustomEffects.FloorAdvanceRequest) =
        run { thunk() } with handler CustomEffects.FloorAdvanceRequest {
            def advance(scene, k) = k(scene)
        }

    /// Ref-backed の `TurnPhase.State`。put を観測でき、最終フェーズを結果と一緒に返す。
    /// `(result, finalPhase)` を返すので、確定アクションの遷移先を assert できる。
    /// engine の `TurnPhase.withState` と同じ Ref パターンだが、初期値を渡せて最終値を読み戻す点が test 向け。
    /// put 観測のため**最外**に巻くこと（内側で先に `- TurnPhase.State` されると届かない）。
    pub def withPhaseRef(rc: Region[r], initial: TurnPhase.Phase, thunk: Unit -> a \ ef):
            (a, TurnPhase.Phase) \ (ef - TurnPhase.State) + r =
        let phaseRef: Ref[TurnPhase.Phase, r] = Ref.fresh(rc, initial);
        let result = run { thunk() } with handler TurnPhase.State {
            def get(k)         = k(Ref.get(phaseRef))
            def put(target, k) = { Ref.put(target, phaseRef); k() }
        };
        (result, Ref.get(phaseRef))

    /// Ref-backed の `SelectedPlayer.State`。drafts スタックの push / 巻き戻しを跨いで状態が残る。
    /// pickup → cancelSelection のように put した drafts を後段が読み返す経路で使う。
    pub def withSelectionRef(rc: Region[r], initial: SelectedPlayer.Selection,
                              thunk: Unit -> a \ ef):
            a \ (ef - SelectedPlayer.State) + r =
        let selRef: Ref[SelectedPlayer.Selection, r] = Ref.fresh(rc, initial);
        run { thunk() } with handler SelectedPlayer.State {
            def get(k)    = k(Ref.get(selRef))
            def put(s, k) = { Ref.put(s, selRef); k() }
        }

    /// メニュー系テストで頻出する read-only effect 4 種を 1 呼び出しで剥がす束ね。
    ///   TurnPhase(固定) + SelectedPlayer(固定 id) + PartyQuery + RosterQuery。
    /// refreshItems / 項目可視性など「フェーズ遷移を観測しない」テストの定型。
    /// 遷移を観測するなら `withPhaseRef` を最外に巻き、こちらは使わない。
    pub def withMenuReadMocks(phase: TurnPhase.Phase, selectedId: Int32,
                               scene: Scene[NodeTag], thunk: Unit -> a \ ef):
            a \ (ef - TurnPhase.State - SelectedPlayer.State
                  - PlayerData.PartyQuery - EnemyData.RosterQuery) =
        withFixedPhase(phase, () ->
            withSelectedPlayer(selectedId, () ->
                withMockPartyQuery(scene, () ->
                    withMockRosterQuery(scene, thunk))))

    /// `withMenuReadMocks` の未選択版（選択駒なし）。`withSelectedPlayer` を `withNoSelection` に
    /// 差し替えただけ。空マスメニューの項目構築テスト用。
    pub def withMenuReadMocksNoSel(phase: TurnPhase.Phase,
                                    scene: Scene[NodeTag], thunk: Unit -> a \ ef):
            a \ (ef - TurnPhase.State - SelectedPlayer.State
                  - PlayerData.PartyQuery - EnemyData.RosterQuery) =
        withFixedPhase(phase, () ->
            withNoSelection(() ->
                withMockPartyQuery(scene, () ->
                    withMockRosterQuery(scene, thunk))))

    /// `SelectedPlayer.State` を「主人公(0) 選択中・gatherActive=true」で固定するスタブ。
    /// 集合（行軍）の隣接メニュー（交換 / 全員待機 / キャンセル）の項目構築テスト用。
    pub def withGatherSelection(thunk: Unit -> a \ ef):
            a \ (ef - SelectedPlayer.State) =
        run { thunk() } with handler SelectedPlayer.State {
            def get(k)    = k({id = Some(0), drafts = Nil, gatherActive = true})
            def put(_, k) = k()
        }

    /// `withMenuReadMocks` の集合（行軍）隣接メニュー版。フェーズ ActionSelect 固定・
    /// 主人公選択中・gatherActive=true で項目構築を観測する。
    pub def withMenuReadMocksGather(scene: Scene[NodeTag], thunk: Unit -> a \ ef):
            a \ (ef - TurnPhase.State - SelectedPlayer.State
                  - PlayerData.PartyQuery - EnemyData.RosterQuery) =
        withFixedPhase(TurnPhase.Phase.ActionSelect, () ->
            withGatherSelection(() ->
                withMockPartyQuery(scene, () ->
                    withMockRosterQuery(scene, thunk))))

    // ════════════════════════════════════════════════════════
    // 純粋値フィクスチャ / タプル変換（複数ファイルで重複していたものを集約）
    // ════════════════════════════════════════════════════════

    /// 武器なし・全ステ 0 の戦闘ビュー。`combat` を見ない経路（canAttack / join 述語）用。
    pub def noCombat(): Combat.CombatView =
        {attack = 0, magicAttack = 0, defense = 0, magicDefense = 0,
         skill = 0, speed = 0, luck = 0, hp = 0, maxHp = 0, weapon = None, hitMod = 0}

    /// 射程・位置・HP・生存だけ指定して UnitView を組む（combat は空）。
    /// 3 値だけ要るときは hp=10 / isDying=false / range=None を渡す。
    pub def mkUnit(id: Int32, faction: Faction, pos: {x = Int32, y = Int32}, hp: Int32,
                   isDying: Bool, range: Option[{min = Int32, max = Int32}]): UnitView =
        {id = id, faction = faction, pos = pos, hp = hp, moveTiles = 4,
         weaponRange = range, combat = noCombat(), isDying = isDying, hidden = false,
         aiType = EnemyAI.AiType.Aggressive}

    /// GridRect を 4-tuple `(x0, y0, x1, y1)` に整形（範囲を assertEq で比較するため）。
    pub def rectT(r: GridRect): (Int32, Int32, Int32, Int32) =
        (r#x0, r#y0, r#x1, r#y1)
}
