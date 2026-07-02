// 一時診断: 実カタログの敵で boot 直後の unitView parity を突合する（P6-2a の [UNITVIEW DIFF] 調査）。
mod TestDiagUnitView {

    @Test
    def diagBarbarianUnitViewParity(): Unit \ {Assert, Fs.FileRead} =
        diagOne("barbarian_t1")

    @Test
    def diagFighterUnitViewParity(): Unit \ {Assert, Fs.FileRead} = diagOne("fighter_t1")

    @Test
    def diagRangerUnitViewParity(): Unit \ {Assert, Fs.FileRead} = diagOne("ranger_t1")

    @Test
    def diagRogueUnitViewParity(): Unit \ {Assert, Fs.FileRead} = diagOne("rogue_t1")

    @Test
    def diagClericUnitViewParity(): Unit \ {Assert, Fs.FileRead} = diagOne("cleric_t1")

    def diagOne(rid: String): Unit \ {Assert, Fs.FileRead} =
        let weaponCatalog = WeaponCatalog.load();
        let enemyCatalog  = EnemyCatalog.load();
        let ringCatalog   = Ring.load();
        let res = match EnemyCatalog.get(rid, enemyCatalog) {
            case Some(r) => r
            case None    => bug!("no ${rid}")
        };
        let weapon = match List.find(e -> e#kind == UnitBase.ItemKind.Weapon, res#initialInventory) {
            case Some(entry) => WeaponCatalog.lookup(entry#id, weaponCatalog)
            case None        => bug!("no weapon")
        };
        let sp: EnemyScene.Spawn = {id = 0, resourceId = rid, gridPos = {x = 3, y = 3},
                                     moduleIdx = 0, resource = res, weapon = weapon};
        region rc {
            let wref = Ref.fresh(rc, World.empty());
            let scene = run {
                Scene.empty() |> MapScene.addWorldNode |> EnemyScene.respawnFromInitial(sp :: Nil, ringCatalog)
            } with handler World.Command {
                def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(wref)), wref); k() }
            };
            // ライブの frame-end を模す: refreshMirror → stepWorld → syncTreeFromWorld を 3 周。
            let w1 = World.refreshMirror(scene, Ref.get(wref));
            let (w2, _) = World.stepWorld(w1, 0.016);
            let s1 = World.syncTreeFromWorld(w2, scene);
            let w3 = World.refreshMirror(s1, w2);
            let (w4, _) = World.stepWorld(w3, 0.016);
            let s2 = World.syncTreeFromWorld(w4, s1);
            let d = match EnemyScene.get(0, s2) { case Some(x) => x case None => bug!("no enemy") };
            let sv = EnemyScene.unitView(d);
            match World.unitViewFromWorld(World.EntityRef.Enemy(0), w4, s2) {
                case None => Assert.assertEq(expected = "worldview Some", "worldview None")
                case Some(wv) =>
                    Assert.assertEq(
                        expected = (true, true, true, true, true, true, true),
                        ((wv#pos#x, wv#pos#y) == (sv#pos#x, sv#pos#y),
                         wv#hp == sv#hp,
                         wv#moveTiles == sv#moveTiles,
                         Option.map(r -> (r#min, r#max), wv#weaponRange) == Option.map(r -> (r#min, r#max), sv#weaponRange),
                         World.combatViewKey(wv#combat) == World.combatViewKey(sv#combat),
                         wv#isDying == sv#isDying,
                         wv#aiType == sv#aiType))
            }
        }
}
