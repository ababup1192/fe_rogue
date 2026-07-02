// ViewReplay — resolveCombat の SimEvent ログを「見た目」へ再生する view 層。
//
// 設計: sim（`CombatSystem.resolveAttack`/`resolveEnemyAttack`）は (World, [SimEvent]) を返し、
// World 変更は reducer（`applyEventToWorld`）が済ませる。本モジュールは **その [SimEvent] を view 演出へ dispatch** する。
//   - dispatch ロジックは **純粋な `plan`（SimEvent → ViewAction 列）** に集約しテストで固める＝ViewReplay の仕様。
//   - effectful な `replay`/`execute` は ViewAction → 既存 Scene API への薄い 1:1 実行（compile 検証・runtime は run 検証）。
//
// 再生するもの: 命中 SE / テキストポップアップ(miss) / ダメージ数字ポップアップ / 着弾爆発 / HPバー /
//   ノックバック着地 / 敵死亡演出。
// 未配線: Alerted の sprite tint、Released の unbind 表示、Afflicted の status 表示。
//   これらは `plan` で空に落とす（World 状態は reducer が既に反映済み）。
// ここで空に落とすが別経路で配線済のもの: LeveledUp（modal-gate は `CombatDriver.applyEcsSceneEffects` が
//   pendingLevelUp を立て signal 駆動で発火）、ViewFx(Thief)（drop 実体は `CombatDriver.applyThiefDrop` が引く＝
//   フロア落下は view でなく scene 状態ゆえ純 view の本モジュールでなく wrapper で処理）。
mod ViewReplay {

    use World.EntityRef

    /// SimEvent から導く純粋な view 指示（effect なし・`ToString` 派生でデバッグ可能。EntityRef/record が Eq 非派生
    /// ゆえ Eq は持たず、テストは `tagOf` 射影で比較する）。座標は **グリッドセル**（実行時に `cellCenter` で pixel 化）。
    /// ref を持つもの（Damage/HpBar/Snap/Death）は実行時に side 色 / node path / 現在セルへ解決する。
    pub enum ViewAction with ToString {
        case Play(String)                     // 効果音
        case Text(Int32, Int32, String)       // テキストポップアップ（"miss" 等）at (x,y)
        case Damage(EntityRef, Int32)         // ダメージ数字ポップアップ（ref の現在セル・side 色）
        case Explode(Int32, Int32)            // 着弾爆発 at (x,y)
        case HpBar(EntityRef, Int32)          // HPバー更新（newHp）
        case Snap(EntityRef, Int32, Int32)    // 位置確定（ノックバック着地）at (x,y)
        case Death(EntityRef)                 // 死亡演出
    }

    /// **純粋 dispatch**: SimEvent ログ → ViewAction 列（順序保存）。これが ViewReplay の仕様＝テストの対象。
    /// World 状態を変える event（Damaged/Healed/Lifesteal/Moved）は **被弾後の絶対値**を持つので、ここでは
    /// view（数字ポップアップ・HPバー・位置）への射影だけを行う（World 反映は reducer 済み）。
    pub def plan(events: List[World.SimEvent]): List[ViewAction] =
        List.flatMap(planOne, events)

    def planOne(ev: World.SimEvent): List[ViewAction] = match ev {
        case World.SimEvent.ViewFx(fx)       => planViewFx(fx)
        case World.SimEvent.Damaged(r, d)    => ViewAction.Damage(r, d#dmg) :: ViewAction.HpBar(r, d#newHp) :: Nil
        case World.SimEvent.Healed(r, h)     => ViewAction.HpBar(r, h#newHp) :: Nil
        case World.SimEvent.Lifesteal(r, l)  => ViewAction.HpBar(r, l#newHp) :: Nil
        case World.SimEvent.Moved(r, c)      => ViewAction.Snap(r, c#x, c#y) :: Nil
        case World.SimEvent.Dying(_)         => Nil    // World 状態（演出は ViewFx(Died)）
        case World.SimEvent.Released(_)      => Nil    // unbind 表示は未配線
        case World.SimEvent.Alerted(_, _)    => Nil    // sprite tint は frame sync 由来・未配線
        case World.SimEvent.ExpGained(_)     => Nil    // 即時 view なし
        case World.SimEvent.LeveledUp(_)     => Nil    // modal-gate は applyEcsSceneEffects が pendingLevelUp で発火（配線済）
        case World.SimEvent.Afflicted(_, _)  => Nil    // status 表示は未配線
    }

    def planViewFx(fx: World.ViewFxKind): List[ViewAction] = match fx {
        case World.ViewFxKind.Sound(n)        => ViewAction.Play(n) :: Nil
        case World.ViewFxKind.Popup(p)        => ViewAction.Text(p#x, p#y, p#text) :: Nil
        case World.ViewFxKind.Explosion(c)    => ViewAction.Explode(c#x, c#y) :: Nil
        case World.ViewFxKind.Knockback(r, c) => ViewAction.Snap(r, c#x, c#y) :: Nil
        case World.ViewFxKind.Thief(_)        => Nil   // drop は scene 状態＝CombatDriver.applyThiefDrop が引く（純 view でない）
        case World.ViewFxKind.Died(r)         => ViewAction.Death(r) :: Nil
    }

    /// **effectful 実行**: SimEvent ログを `plan` → 各 ViewAction を既存 Scene API へ反映する。
    /// live combat（`CombatDriver`/`StaffCast` の ECS 経路）の演出発火はこの 1 本を通す。
    pub def replay(events: List[World.SimEvent], scene: Scene[NodeTag]): Scene[NodeTag] \
            {GameEngine.Audio, AnimationPlayer.Scheduler,
             World.Command, World.WorldQuery} =
        List.foldLeft((sc, a) -> execute(a, sc), scene, plan(events))

    def execute(action: ViewAction, scene: Scene[NodeTag]): Scene[NodeTag] \
            {GameEngine.Audio, AnimationPlayer.Scheduler,
             World.Command, World.WorldQuery} =
        match action {
            case ViewAction.Play(n)        => AudioStreamPlayer.play(n); scene
            case ViewAction.Text(x, y, t)  =>
                DamagePopupFx.emitText(MapSnapshot.cellCenter({x = x, y = y}), t,
                    DamagePopupFx.damageToEnemyColor(), scene)
            case ViewAction.Damage(r, dmg) =>
                // ポップアップは ref の現在セルへ（knockback 前。combat は防御側を最後にしか動かさない）。
                let cell = World.posOf(r, World.WorldQuery.get()) |> Option.getWithDefault({x = 0, y = 0});
                DamagePopupFx.emit(MapSnapshot.cellCenter(cell), dmg, popupColor(r), scene)
            case ViewAction.Explode(x, y)  => ExplosionFx.emitAtCell({x = x, y = y}, scene)
            // HP バーは World.hp store から直描き＝リプレイでも押し込み不要（SetHp が既に反映済み）。
            case ViewAction.HpBar(_r, _hp) => scene
            case ViewAction.Snap(r, x, y)  => snapRefTo(r, {x = x, y = y}, scene)
            case ViewAction.Death(r)       => deathAnim(r, scene)
        }

    /// ダメージポップアップ色（被弾側の faction）。enemy=白 / player=赤（legacy `damageTo*Color`）。
    def popupColor(ref: EntityRef): Color = match ref {
        case EntityRef.Enemy(_)  => DamagePopupFx.damageToEnemyColor()
        case EntityRef.Player(_) => DamagePopupFx.damageToPlayerColor()
    }

    /// ノックバック着地（faction で snapTo を振り分け）。
    def snapRefTo(ref: EntityRef, cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]):
            Scene[NodeTag] \ World.Command = match ref {
        case EntityRef.Enemy(i)  => EnemyScene.snapTo(i, cell, scene)
        case EntityRef.Player(i) => PlayerScene.snapTo(i, cell, scene)
    }

    /// 死亡演出。enemy は death_blink。player 死亡は game-over 経路（`CombatDriver` が ViewFx(Died(player)) を
    /// filter して `GameOverRequest` を引く）が担うので純 view 層では no-op。
    def deathAnim(ref: EntityRef, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler, World.Command} = match ref {
        case EntityRef.Enemy(i)  => EnemyScene.startDeathAnimation(i, scene)
        case EntityRef.Player(_) => scene
    }
}
