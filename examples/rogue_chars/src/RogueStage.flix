// RogueStage — 24 体全キャラが従うクリップ契約（演技の台本）v3。
//
// マスタークロックは 24 ticks/s。各クリップの fps は 24 の約数なので
// ticksPerFrame は必ず整数になり、GIF もゲームも同じ割り付けで再生できる。
//
// v3 の骨子: Idle/Attack/UseItem/Damage も歩きと同じ 3 方向（Down/Up/Side）を持つ。
// Death だけは方向なしの 1 本（倒れる芝居は向きに依存しない）。
//
// アンカー規約（全キャラ共通・TestLint と創作エージェントの前提）:
//   - 足元線は y=29（足の底がこの行に乗る）
//   - 体の中心は x=15..16 の間（32px の真ん中）
//   - 身長は 28px 以下（頭上に 2px 以上の余白を残す）
//   - Side 系クリップ（IdleSide/WalkSide/AttackSide/UseItemSide/DamageSide）は左向きで描く。
//     右向きは実行時の hflip で作る（fe_rogue の flipForFacing 慣習）。

mod RogueStage {

    pub enum Clip with Eq, Order, ToString {
        case IdleDown case IdleUp case IdleSide
        case WalkDown case WalkUp case WalkSide
        case AttackDown case AttackUp case AttackSide
        case UseItemDown case UseItemUp case UseItemSide
        case DamageDown case DamageUp case DamageSide
        case Death
    }

    /// マスタークロック（ticks/s）。
    pub def ticksPerSecond(): Int32 = 24

    /// シート行順 = この並び（IdleDown=0 .. Death=15）。
    pub def clips(): List[Clip] =
        Clip.IdleDown :: Clip.IdleUp :: Clip.IdleSide ::
        Clip.WalkDown :: Clip.WalkUp :: Clip.WalkSide ::
        Clip.AttackDown :: Clip.AttackUp :: Clip.AttackSide ::
        Clip.UseItemDown :: Clip.UseItemUp :: Clip.UseItemSide ::
        Clip.DamageDown :: Clip.DamageUp :: Clip.DamageSide ::
        Clip.Death :: Nil

    /// Death は 6 コマ: よろめき(2) → 膝から崩れ(2) → 膝立ちのまま前傾がくり(2)。
    /// 完全な遺体は描かない — 死亡後は共通の Skeleton（白骨）へ差し替わる。
    pub def frameCount(c: Clip): Int32 = match c {
        case Clip.IdleDown    => 4
        case Clip.IdleUp      => 4
        case Clip.IdleSide    => 4
        case Clip.WalkDown    => 4
        case Clip.WalkUp      => 4
        case Clip.WalkSide    => 4
        case Clip.AttackDown  => 6
        case Clip.AttackUp    => 6
        case Clip.AttackSide  => 6
        case Clip.UseItemDown => 4
        case Clip.UseItemUp   => 4
        case Clip.UseItemSide => 4
        case Clip.DamageDown  => 3
        case Clip.DamageUp    => 3
        case Clip.DamageSide  => 3
        case Clip.Death       => 6
    }

    pub def fps(c: Clip): Int32 = match c {
        case Clip.IdleDown    => 6
        case Clip.IdleUp      => 6
        case Clip.IdleSide    => 6
        case Clip.WalkDown    => 8
        case Clip.WalkUp     => 8
        case Clip.WalkSide    => 8
        case Clip.AttackDown  => 12
        case Clip.AttackUp    => 12
        case Clip.AttackSide  => 12
        case Clip.UseItemDown => 8
        case Clip.UseItemUp   => 8
        case Clip.UseItemSide => 8
        case Clip.DamageDown  => 12
        case Clip.DamageUp    => 12
        case Clip.DamageSide  => 12
        case Clip.Death       => 8
    }

    pub def loops(c: Clip): Bool = match c {
        case Clip.IdleDown    => true
        case Clip.IdleUp      => true
        case Clip.IdleSide    => true
        case Clip.WalkDown    => true
        case Clip.WalkUp      => true
        case Clip.WalkSide    => true
        case Clip.AttackDown  => false
        case Clip.AttackUp    => false
        case Clip.AttackSide  => false
        case Clip.UseItemDown => false
        case Clip.UseItemUp   => false
        case Clip.UseItemSide => false
        case Clip.DamageDown  => false
        case Clip.DamageUp    => false
        case Clip.DamageSide  => false
        case Clip.Death       => false   // 最終コマ = 前傾がくり（この後 Skeleton に差し替わる）
    }

    /// 1 コマの表示 tick 数。fps は 24 の約数なので常に整数。
    pub def ticksPerFrame(c: Clip): Int32 = ticksPerSecond() / fps(c)

    /// スプライトシートの行番号（clips() の並び順）。
    pub def sheetRow(c: Clip): Int32 =
        clips()
            |> List.zipWithIndex
            |> List.findMap(pair -> { let (i, x) = pair; if (x == c) Some(i) else None })
            |> Option.getWithDefault(0)

    // ── リール（ギャラリー GIF の振り付け・全レーン共通）──

    /// リールの 1 tick 分。キャラのコマだけでなく、死亡後の共通白骨と
    /// その消滅フェードも 1 本の振り付けとして表せる。
    pub enum ReelStep with Eq, Order, ToString {
        /// キャラのクリップの 1 コマ（必要なら左右反転して見せる）。
        case Char(Clip, Int32, Bool)
        /// 共通白骨（Skeleton.draw）のコマ番号（0..1）。
        case Bones(Int32)
        /// 白骨の消滅フェード段（0..3）。段 3 で完全に消える。
        case Fade(Int32)
    }

    /// 白骨のコマ数（Skeleton.draw と対で固定）。
    pub def bonesFrameCount(): Int32 = 2

    /// 白骨 1 コマの表示 tick 数（8fps 相当 = 3tick だと速すぎるので 6tick で見せる）。
    pub def bonesTicksPerFrame(): Int32 = 6

    /// フェードの段数と 1 段の表示 tick 数。
    pub def fadeStepCount(): Int32 = 4
    pub def fadeTicksPerStep(): Int32 = 3

    /// 全クリップを一巡する振り付け（1 tick = 1 要素・計 204 tick = 8.5 秒）:
    /// IdleDown×2周 → WalkDown×2周 → WalkUp×2周 → WalkSide×2周 → WalkSide 反転1周（右向き確認）
    /// → AttackSide → IdleDown×1周 → UseItemSide → DamageSide → Death
    /// → 白骨 2 コマ（各 6tick）→ フェード 4 段（各 3tick）→ 完全消滅で終了。
    pub def reel(): List[ReelStep] =
        List.flatten(
            plays(Clip.IdleDown, 2, false) ::
            plays(Clip.WalkDown, 2, false) ::
            plays(Clip.WalkUp, 2, false) ::
            plays(Clip.WalkSide, 2, false) ::
            plays(Clip.WalkSide, 1, true) ::
            plays(Clip.AttackSide, 1, false) ::
            plays(Clip.IdleDown, 1, false) ::
            plays(Clip.UseItemSide, 1, false) ::
            plays(Clip.DamageSide, 1, false) ::
            plays(Clip.Death, 1, false) ::
            bonesSteps() ::
            fadeSteps() :: Nil)

    /// クリップを n 周ぶん tick 展開する。
    def plays(c: Clip, n: Int32, flip: Bool): List[ReelStep] =
        List.range(0, n) |> List.flatMap(_ ->
            List.range(0, frameCount(c)) |> List.flatMap(f ->
                hold(ReelStep.Char(c, f, flip), ticksPerFrame(c))))

    /// 白骨 2 コマを各 6tick で見せる。
    def bonesSteps(): List[ReelStep] =
        List.range(0, bonesFrameCount()) |> List.flatMap(f ->
            hold(ReelStep.Bones(f), bonesTicksPerFrame()))

    /// フェード 4 段を各 3tick で見せる（最終段 = 完全消滅）。
    def fadeSteps(): List[ReelStep] =
        List.range(0, fadeStepCount()) |> List.flatMap(s ->
            hold(ReelStep.Fade(s), fadeTicksPerStep()))

    /// 1 ステップを ticks 個に引き伸ばす。
    def hold(step: ReelStep, ticks: Int32): List[ReelStep] =
        List.range(0, ticks) |> List.map(_ -> step)
}
