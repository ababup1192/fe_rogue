/// FireShotFx — 魔導書攻撃の炎 3 幕演出（詠唱 → 飛翔 → 着弾）。
///
/// 火の玉はどこにも保存されない: 絵ぜんぶが (詠唱者セル中心 caster, 対象セル中心 target,
/// 通し番号 seed, 発生からの経過秒 elapsed) の純粋な導出で、spawn も update も消去も要らない。
/// World の `fireShots` store が持つのは spawn 時の caster/target/seed と寿命だけ。描きたい
/// フレームで `quads` を呼び、`FireFx` のプリセット（fireball / flare）を各幕へ配って polygon 列に
/// 混ぜる（`RenderWorld.renderFireShots` が camera を掛けて出す）。
///
/// 幕（elapsed による分岐）:
///   幕1 詠唱  [0, castDuration)          … 詠唱者の頭上（1 タイル上）に fireball が現れ、scale が
///                                          伸びて育つ（点火の閃光 → 脈動する火の玉）。
///   幕2 飛翔  [castDuration, impactStart) … 火の玉が頭上から対象へ直線移動（速め・移動中も脈動）。
///   幕3 着弾  [impactStart, totalDuration)… 対象位置で flare が大きく炸裂する（派手目・フル duration）。
///
/// spawn は攻撃の解決点（`CombatSystem.hitFxEvents` の魔法命中）で `ViewFx(FireShot)` を出し、
/// `ViewReplay` が `emitAtCells` で `Cmd.SpawnFireShot` を emit する。着弾の拍は攻撃解決＝ダメージ
/// 適用と同一フレームに spawn されるので、被弾数字が浮くあいだに詠唱→飛翔→着弾が続けて見える。
mod FireShotFx {

    /// 演出の幕。`quads` の分岐と、境界時刻を固定するテストが読む。
    pub enum Phase with Eq, ToString {
        case Cast     // 幕1 詠唱
        case Flight   // 幕2 飛翔
        case Impact   // 幕3 着弾
        case Done     // 寿命切れ（何も描かない）
    }

    // ── 尺（秒）と大きさ ──────────────────────────────

    /// 幕1 詠唱の長さ。頭上で火の玉が育ちきるまで。
    pub def castDuration(): Float64 = 0.35
    /// 幕2 飛翔の長さ。頭上から対象へ届くまで（速め）。
    pub def flightDuration(): Float64 = 0.25
    /// 幕2 開始時刻（= 幕1 の終わり）。
    def flightStart(): Float64 = castDuration()
    /// 幕3 着弾の開始時刻（= 詠唱 + 飛翔の合計）。ここでダメージ適用と拍が揃う。
    pub def impactStart(): Float64 = castDuration() + flightDuration()
    /// 幕3 の flare の尺（fireball とは別プリセット）。
    def flareDuration(): Float64 = FireFx.flare()#duration
    /// 総寿命。`Cmd.SpawnFireShot` が remaining=total で開始し、tickFxMap が 0 で cull する。
    pub def totalDuration(): Float64 = impactStart() + flareDuration()

    /// 詠唱者頭上の高さ（セル中心から真上へ 1 タイル）。
    def headOffset(): Float64 = MapSnapshot.tileSize()
    /// 幕1 の火の玉スケール（詠唱の始まり → 育ちきり）。1.0 で 1 マス 16px を覆う FireFx 基準。
    def castScaleMin(): Float64 = 0.5
    def castScaleMax(): Float64 = 1.3
    /// 幕2 飛翔中の火の玉スケール（育ちきりを保つ）。
    def flightScale(): Float64 = 1.3
    /// 幕3 flare の炸裂スケール（派手目に大きく）。
    pub def flareScale(): Float64 = 1.9

    // ── 幕の判定と位置・スケールの導出（純粋・テスト対象）─────────

    /// elapsed から今どの幕か。境界は左閉右開（幕1 は [0,cast)、幕2 は [cast,impact) …）。
    pub def phaseAt(elapsed: Float64): Phase =
        if (elapsed < flightStart())        Phase.Cast
        else if (elapsed < impactStart())   Phase.Flight
        else if (elapsed < totalDuration()) Phase.Impact
        else                                Phase.Done

    /// 詠唱者頭上のワールド座標（セル中心から真上）。
    def headOf(caster: Vec2.Vec2): Vec2.Vec2 =
        {x = caster#x, y = caster#y - headOffset()}

    /// 火の玉の中心（幕1=頭上・幕2=頭上→対象の lerp・以降=対象）。テストが飛翔中点を固定する。
    pub def ballCenterAt(caster: Vec2.Vec2, target: Vec2.Vec2, elapsed: Float64): Vec2.Vec2 =
        match phaseAt(elapsed) {
            case Phase.Cast   => headOf(caster)
            case Phase.Flight => Vec2.lerp(headOf(caster), target, (elapsed - flightStart()) / flightDuration())
            case _            => target
        }

    /// 幕1 の火の玉スケール（詠唱中のみ育つ・以降は育ちきり）。
    pub def ballScaleAt(elapsed: Float64): Float64 =
        match phaseAt(elapsed) {
            case Phase.Cast => castScaleMin() + (castScaleMax() - castScaleMin()) * (elapsed / castDuration())
            case _          => flightScale()
        }

    /// 幕1 の fireball 内部時間: elapsed をそのまま渡す（点火の閃光 → 保持帯に留まり、育ちは scale が担う）。
    /// castDuration は fireball の減衰開始より手前ゆえ、詠唱のあいだ玉は消えずに脈動し続ける。
    def castBallTime(elapsed: Float64): Float64 = elapsed
    /// 幕2 の fireball 内部時間: 保持帯 [0.15, 0.38] へ写して玉を灯したまま脈動させる（閃光の再点火なし）。
    def flightBallTime(elapsed: Float64): Float64 =
        0.15 + 0.23 * ((elapsed - flightStart()) / flightDuration())

    // ── 描画（ワールド座標の polygon 列）────────────────────

    /// 発生からの経過秒 elapsed の炎（polygon 列・ワールド座標）。寿命外は空。
    /// 頂点はワールド px。camera 変換は `RenderWorld.renderFireShots` が各頂点に掛ける。
    pub def quads(caster: Vec2.Vec2, target: Vec2.Vec2, seed: Int32, elapsed: Float64):
            List[GameEngine.PolygonRenderCmd] =
        match phaseAt(elapsed) {
            case Phase.Cast =>
                FireFx.quads(FireFx.fireball(),
                    {center = headOf(caster), seed = seed, scale = ballScaleAt(elapsed)},
                    castBallTime(elapsed))
            case Phase.Flight =>
                FireFx.quads(FireFx.fireball(),
                    {center = ballCenterAt(caster, target, elapsed), seed = seed, scale = flightScale()},
                    flightBallTime(elapsed))
            case Phase.Impact =>
                FireFx.quads(FireFx.flare(),
                    {center = target, seed = seed, scale = flareScale()},
                    elapsed - impactStart())
            case Phase.Done => Nil
        }

    // ── 発生（解決点から呼ばれる emit）─────────────────────

    /// 詠唱者セル `caster` → 対象セル `target` の炎 3 幕を 1 つ spawn する（`Cmd.SpawnFireShot` の
    /// emit のみ・ノード無し）。seed は applyCmd が通し番号で採番する。
    pub def emitAtCells(caster: {x = Int32, y = Int32}, target: {x = Int32, y = Int32}):
            Unit \ World.Command =
        World.Command.emit(World.Cmd.SpawnFireShot({
            total  = totalDuration(),
            caster = MapSnapshot.cellCenter(caster),
            target = MapSnapshot.cellCenter(target)}))
}
