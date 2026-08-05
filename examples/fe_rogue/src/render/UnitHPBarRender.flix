/// UnitHPBarRender — キャラ足元に常時表示する連続フィル HP ゲージ
///
/// scene ノードは持たない。HP/最大 HP は World store（hp/baseStats）、待機/行動済みの暗転は
/// World store（waited/enemyActed）から導出し、`renderBars` が Rect **値**を組んで毎フレーム
/// 直描きする（update/setColor 等の押し込み API は不要になった＝SetHp 等の Cmd が唯一の書込）。
/// 攻撃予報の「減る分」点滅だけは BattlePanel が毎フレーム計算する view 状態なので、
/// `ForecastState` resource 経由で受け取る。
mod UnitHPBarRender {

    /// HP バーのチーム。フィル色の出し分けに使う（味方=青 / 敵=赤）。
    pub enum Team with Eq {
        case Player
        case Enemy
    }

    /// 攻撃予報（BattlePanel が毎フレーム計算）を renderBars へ渡す view 状態。
    /// attacker=味方/defender=敵の「予測後 HP」と点滅位相（dark）。None=予報なし。
    pub type alias Forecast = {
        attackerId = Int32, playerHpPost = Int32,
        defenderId = Int32, enemyHpPost = Int32,
        dark = Bool
    }

    pub eff ForecastState {
        def get(): Option[Forecast]
        def put(v: Option[Forecast]): Unit
    }

    pub def withForecast(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - ForecastState) + r =
        thunk -> {
            let ref: Ref[Option[Forecast], r] = Ref.fresh(rc, None);
            run {
                thunk()
            } with handler ForecastState {
                def get(k)    = k(Ref.get(ref))
                def put(v, k) = { Ref.put(v, ref); k() }
            }
        }

    // ─── 色 ───────────────────────────────────────────────────
    def fillColorPlayer(): Color = {r = 0.25f32, g = 0.5f32, b = 0.95f32}
    def fillColorEnemy(): Color = {r = 0.9f32, g = 0.25f32, b = 0.25f32}
    def fillColorFor(team: Team): Color = match team {
        case Team.Player => fillColorPlayer()
        case Team.Enemy  => fillColorEnemy()
    }
    /// 残量トラック（暗背景・枠兼用）。
    def trackColor(): Color = {r = 0.08f32, g = 0.08f32, b = 0.08f32}

    /// 点滅の「暗」側 color（フィル色を暗く落とす乗算色）。減少分が暗く沈んで見える。
    def dmgDarkModulate(): Color = {r = 0.3f32, g = 0.3f32, b = 0.3f32}
    /// 点滅の「明」側 color（通常色 = フィルと同色に見え、満タンに戻って見える）。
    def dmgNormalModulate(): Color = UITheme.white()
    /// 「減る分」オーバーレイの 45° 斜線（赤マスと同じハッチ）。バーが小さいので細かめに。
    def dmgStripeColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    def dmgStripeAlpha(): Float32 = 0.6f32
    /// バーが小さいので周期を詰めて斜線を細かく（灰色の隙間を減らす）。
    def dmgStripeWidth(): Float64 = 0.5
    def dmgStripePeriod(): Float64 = 1.0

    // ─── サイズ・位置 ─────────────────────────────────────────
    /// 全ユニット共通幅（最大 HP に依らない）。HP 量で見た目が変わると比較が難しくなるため固定。
    def barWidthPx(): Float64 = MapSnapshot.tileSize() * 0.9
    def barHeightPx(): Float64 = 5.0
    /// 暗トラックの枠として機能する。Fill を 1px インセットすることで別枠ノードなしで枠線を表現。
    def borderPx(): Float64 = 1.0
    /// 足元オフセット（中心基準・下向き）。タイルは tileSize(26)＝中心から ±13。
    /// バー上端をこの値に置くと、バー(高さ 5)はタイル下端(13)の内側＝キャラの足元に収まる。
    def barFeetY(): Float64 = 7.0
    /// HP バー（トラック）の角丸半径。高さ 5px に対して丸みを付ける。
    def barCornerRadius(): Float64 = 2.0
    /// フィル（内側 3px）の角丸半径。半径＝高さ/2 でピル状にし、丸みが見えるようにする。
    def fillCornerRadius(): Float64 = innerHeightPx() / 2.0
    def barZIndex(): Int32 = 1100

    /// フィル領域（枠 1px インセット）の幅・高さ。
    def innerWidthPx(): Float64 = barWidthPx() - 2.0 * borderPx()
    def innerHeightPx(): Float64 = barHeightPx() - 2.0 * borderPx()

    /// 残量比（0..1 にクランプ）。maxHp<=0 は 0 扱い。
    def hpRatio(currentHp: Int32, maxHp: Int32): Float64 =
        if (maxHp <= 0) 0.0
        else {
            let r = Int32.toFloat64(currentHp) / Int32.toFloat64(maxHp);
            if (r < 0.0) 0.0 else if (r > 1.0) 1.0 else r
        }

    /// 残量比から Fill 幅（px）を求める純粋関数（テスト対象）。
    pub def fillWidth(currentHp: Int32, maxHp: Int32, innerW: Float64): Float64 =
        innerW * hpRatio(currentHp, maxHp)

    /// チームのフィル色（テスト用に公開）。
    pub def teamFillColor(team: Team): Color = fillColorFor(team)

    // ─── 公開 API（直描き） ────────────────────────────

    /// 全ユニットの足元 HP バーを World store から直描きする（在籍・位置とも scene を読まない）。
    ///   - HP = World.hpOf / 最大 HP = World.baseStatsOf#hp（SetHp/SetBaseStats が唯一の書込）
    ///   - 暗転 = waited（味方）/ enemyActed（敵）→ UITheme.dimmed() 乗算
    ///   - 位置 = `World.visualPosOf` + 足元オフセット（静止=セル中心／移動=renderPos 補間／
    ///     lunge=往復導出＝本体 sprite と同じ追従）
    ///   - 攻撃予報の「減る分」= ForecastState（BattlePanel が毎フレーム put）
    /// 退場（hidden）ユニット・フォグで隠れた敵（`holesOpt` の lit ゲート）は描かない。
    pub def renderBars(world: World, holesOpt: Option[List[GridRect]],
                        transform: Projection.ViewTransform):
            List[GameEngine.Drawable] \ {GameEngine.Game, ForecastState} =
        let fc = ForecastState.get();
        let players = World.playerIdsOf(world)
            |> List.filter(id -> not World.playerHiddenOf(World.EntityRef.Player(id), world))
            |> List.flatMap(id -> {
                let ref = World.EntityRef.Player(id);
                // 暗転は World.unitModulate store（本体/バー/アイコン共通の単一真実源。
                // setSpriteModulate 系が Cmd.SetModulate を emit し showAllActive も同経路）。
                let post = fc |> Option.flatMap(f ->
                    if (f#attackerId == id) Some((f#playerHpPost, f#dark)) else None);
                barDrawables(ref, Team.Player, World.modulateOf(ref, world), post, world, transform)
            });
        let enemies = World.enemyIdsOf(world)
            // フォグで隠れた敵は描かない（明るい穴の lit ゲート＝本体 sprite と同じ判定）。
            |> List.filter(id -> holesOpt
                |> Option.map(holes -> EnemyDriver.isLitIn(id, holes, world))
                |> Option.getWithDefault(false))
            |> List.flatMap(id -> {
                let ref = World.EntityRef.Enemy(id);
                let post = fc |> Option.flatMap(f ->
                    if (f#defenderId == id) Some((f#enemyHpPost, f#dark)) else None);
                barDrawables(ref, Team.Enemy, World.modulateOf(ref, world), post, world, transform)
            });
        List.append(players, enemies)


    /// 1 ユニットぶんの HP バー Drawable 列（Bg トラック + Fill + 予報オーバーレイ）。
    def barDrawables(ref: World.EntityRef, team: Team, modColor: Color,
                      post: Option[(Int32, Bool)], world: World,
                      transform: Projection.ViewTransform):
            List[GameEngine.Drawable] \ GameEngine.Game =
        match World.visualPosOf(ref, world) {
            case Some(unitPos) =>
                let hp    = World.hpOf(ref, world) |> Option.getWithDefault(0);
                let maxHp = World.baseStatsOf(ref, world) |> Option.map(b -> b#maxHp) |> Option.getWithDefault(0);
                if (maxHp <= 0) Nil
                else {
                    let barTopLeft: Vec2.Vec2 =
                        {x = unitPos#x - barWidthPx() / 2.0, y = unitPos#y + barFeetY()};
                    let bg = Rect.make({x = barWidthPx(), y = barHeightPx()}, mulColor(trackColor(), modColor))
                        |> Rect.setCornerRadius(barCornerRadius());
                    let fill = Rect.make(
                            {x = fillWidth(hp, maxHp, innerWidthPx()), y = innerHeightPx()},
                            mulColor(fillColorFor(team), modColor))
                        |> Rect.setCornerRadius(fillCornerRadius());
                    let bgDs = rectDrawables(bg, barTopLeft, barZIndex(), transform);
                    let fillDs = rectDrawables(fill,
                        {x = barTopLeft#x + borderPx(), y = barTopLeft#y + borderPx()},
                        barZIndex() + 1, transform);
                    let prevDs = match post {
                        case Some((postHp, dark)) =>
                            if (postHp >= hp) Nil
                            else {
                                let xStart = borderPx() + fillWidth(postHp, maxHp, innerWidthPx());
                                let w = fillWidth(hp, maxHp, innerWidthPx()) - fillWidth(postHp, maxHp, innerWidthPx());
                                let blink = if (dark) dmgDarkModulate() else dmgNormalModulate();
                                let prev = Rect.make({x = w, y = innerHeightPx()},
                                        mulColor(mulColor(fillColorFor(team), blink), modColor))
                                    |> Rect.setStripe(dmgStripeColor(), dmgStripeAlpha(),
                                                           dmgStripeWidth(), dmgStripePeriod());
                                rectDrawables(prev,
                                    {x = barTopLeft#x + xStart, y = barTopLeft#y + borderPx()},
                                    barZIndex() + 2, transform)
                            }
                        case None => Nil
                    };
                    bgDs |> List.append(fillDs) |> List.append(prevDs)
                }
            case _ => Nil
        }

    /// Rect 値 1 枚を world 左上座標へ Drawable 化する（tree に積まない）。
    def rectDrawables(rect: Rect, worldTopLeft: Vec2.Vec2, z: Int32,
                       transform: Projection.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        let screenPos = Projection.applyToWorldPos(transform, worldTopLeft);
        // Rect.toDrawable は純粋。呼び側の Game eff 連鎖を保つため checked_ecast で持ち上げる。
        checked_ecast(
            (Rect.toDrawable(rect, screenPos) :: Nil)
                |> Render.applyCameraScale(transform)
                |> List.map(d -> {zIndex = z | d}))

    /// 乗算合成（engine の祖先 color 伝播の代替）。
    def mulColor(a: Color, b: Color): Color =
        {r = a#r * b#r, g = a#g * b#g, b = a#b * b#b}
}
