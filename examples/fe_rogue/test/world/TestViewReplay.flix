// ViewReplay の **純粋 dispatch**（`plan`: SimEvent → ViewAction）を固定する。
// ViewAction は Eq 非派生（EntityRef/record が Eq を持たない）なので、各 action を `tagOf` で決定的な
// 文字列へ射影して List 同士で比較する（test 本体に直接 match を書かない＝既存方針・tagOf 慣習）。
// effectful な `replay`/`execute` は runtime（run 検証）対象ゆえここでは検証しない＝plan が仕様の単一源泉。
mod TestViewReplay {

    use World.EntityRef
    use ViewReplay.ViewAction

    /// ViewAction を決定的な文字列タグへ（ToString の自動形式に依存しない比較用）。
    def tagOf(a: ViewAction): String = match a {
        case ViewAction.Play(n)        => "Play:${n}"
        case ViewAction.Text(x, y, t)  => "Text:${x},${y}:${t}"
        case ViewAction.Damage(r, d)   => "Damage:${refTag(r)}:${d}"
        case ViewAction.Explode(x, y)  => "Explode:${x},${y}"
        case ViewAction.FireBurst(cx, cy, tx, ty) => "Fire:${cx},${cy}->${tx},${ty}"
        case ViewAction.HpBar(r, hp)   => "HpBar:${refTag(r)}:${hp}"
        case ViewAction.Snap(r, x, y)  => "Snap:${refTag(r)}:${x},${y}"
        case ViewAction.Death(r)       => "Death:${refTag(r)}"
    }

    def refTag(r: EntityRef): String = match r {
        case EntityRef.Enemy(i)  => "E${i}"
        case EntityRef.Player(i) => "P${i}"
    }

    def tags(events: List[World.SimEvent]): List[String] =
        ViewReplay.plan(events) |> List.map(tagOf)

    /// 非撃破命中: Sound→Damaged→Alerted→Released。SE→ダメージ数字→HPバー（Alerted/Released は view なし）。
    @Test
    def testPlanNonKillHit(): Unit \ Assert =
        let events =
            World.SimEvent.ViewFx(World.ViewFxKind.Sound("damage")) ::
            World.SimEvent.Damaged(EntityRef.Enemy(1), {newHp = 6, dmg = 4}) ::
            World.SimEvent.Alerted(EntityRef.Enemy(1), true) ::
            World.SimEvent.Released(EntityRef.Enemy(1)) :: Nil;
        Assert.assertEq(
            expected = "Play:damage" :: "Damage:E1:4" :: "HpBar:E1:6" :: Nil,
            tags(events))

    /// 撃破: Sound(必殺)→Damaged(0)→Dying→ViewFx(Died)。Dying は view なし・Died は Death 演出。
    @Test
    def testPlanKill(): Unit \ Assert =
        let events =
            World.SimEvent.ViewFx(World.ViewFxKind.Sound("critical")) ::
            World.SimEvent.Damaged(EntityRef.Enemy(1), {newHp = 0, dmg = 12}) ::
            World.SimEvent.Dying(EntityRef.Enemy(1)) ::
            World.SimEvent.ViewFx(World.ViewFxKind.Died(EntityRef.Enemy(1))) :: Nil;
        Assert.assertEq(
            expected = "Play:critical" :: "Damage:E1:12" :: "HpBar:E1:0" :: "Death:E1" :: Nil,
            tags(events))

    /// 魔導書命中: Sound(magic)→FireShot(詠唱者→対象)→Damaged。SE→炎 3 幕→ダメージ数字→HPバー。
    @Test
    def testPlanMagicHit(): Unit \ Assert =
        let events =
            World.SimEvent.ViewFx(World.ViewFxKind.Sound("magic")) ::
            World.SimEvent.ViewFx(World.ViewFxKind.FireShot({caster = {x = 2, y = 2}, target = {x = 3, y = 2}})) ::
            World.SimEvent.Damaged(EntityRef.Enemy(1), {newHp = 5, dmg = 5}) :: Nil;
        Assert.assertEq(
            expected = "Play:magic" :: "Fire:2,2->3,2" :: "Damage:E1:5" :: "HpBar:E1:5" :: Nil,
            tags(events))

    /// 回避: Sound(miss)→Popup("miss")。SE→テキストポップアップ。
    @Test
    def testPlanMiss(): Unit \ Assert =
        let events =
            World.SimEvent.ViewFx(World.ViewFxKind.Sound("miss")) ::
            World.SimEvent.ViewFx(World.ViewFxKind.Popup({x = 3, y = 2, text = "miss"})) :: Nil;
        Assert.assertEq(
            expected = "Play:miss" :: "Text:3,2:miss" :: Nil,
            tags(events))

    /// ノックバック: Moved → Snap（着地セル）。
    @Test
    def testPlanKnockback(): Unit \ Assert =
        let events = World.SimEvent.Moved(EntityRef.Enemy(1), {x = 5, y = 2}) :: Nil;
        Assert.assertEq(expected = "Snap:E1:5,2" :: Nil, tags(events))

    /// lifesteal は攻撃側 HPバー更新のみ。ExpGained / Afflicted は即時 view なし（plan で空に落ちる）。
    @Test
    def testPlanLifestealHpBarAndSilentEvents(): Unit \ Assert =
        let spd = ({effect = StatusSystem.StatusEffect.SpdDown, magnitude = 3, remaining = 3}: StatusSystem.Status);
        let events =
            World.SimEvent.Lifesteal(EntityRef.Player(0), {newHp = 10, amt = 5}) ::
            World.SimEvent.ExpGained({entity = EntityRef.Player(0), newLevel = 1, newExp = 35}) ::
            World.SimEvent.Afflicted(EntityRef.Player(0), spd) :: Nil;
        Assert.assertEq(expected = "HpBar:P0:10" :: Nil, tags(events))

    /// 敵→味方の被弾は Damage 色が player（赤）になる（tagOf は ref だけ見るが、faction 取り違えで Snap/Death/HpBar の
    /// path 解決が壊れないことを ref タグで固定）。Damaged(player)→ Damage:P0 + HpBar:P0。
    @Test
    def testPlanPlayerHit(): Unit \ Assert =
        let events =
            World.SimEvent.ViewFx(World.ViewFxKind.Sound("damage")) ::
            World.SimEvent.Damaged(EntityRef.Player(0), {newHp = 6, dmg = 4}) ::
            World.SimEvent.ViewFx(World.ViewFxKind.Died(EntityRef.Player(0))) :: Nil;
        Assert.assertEq(
            expected = "Play:damage" :: "Damage:P0:4" :: "HpBar:P0:6" :: "Death:P0" :: Nil,
            tags(events))
}
