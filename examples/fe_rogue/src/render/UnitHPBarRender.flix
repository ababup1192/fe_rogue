/// UnitHPBarRender — キャラ足元に常時表示する連続フィル HP ゲージ
///
/// P6-1g: scene ノードは全廃。HP/最大 HP は World store（hp/baseStats）、待機/行動済みの暗転は
/// World store（waited/enemyActed）から導出し、`renderBars` が ColorRect **値**を組んで毎フレーム
/// 直描きする（update/setModulate 等の押し込み API は不要になった＝SetHp 等の Cmd が唯一の書込）。
/// 攻撃予報の「減る分」点滅だけは BattlePanel が毎フレーム計算する view 状態なので、
/// `ForecastState` resource 経由で受け取る。
mod UnitHPBarRender {

    /// HP バーのチーム。フィル色の出し分けに使う（味方=青 / 敵=赤）。
    pub enum Team with Eq {
        case Player
        case Enemy
    }

    /// P6-1g: 攻撃予報（BattlePanel が毎フレーム計算）を renderBars へ渡す view 状態。
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

    /// 点滅の「暗」側 modulate（フィル色を暗く落とす乗算色）。減少分が暗く沈んで見える。
    def dmgDarkModulate(): Color = {r = 0.3f32, g = 0.3f32, b = 0.3f32}
    /// 点滅の「明」側 modulate（通常色 = フィルと同色に見え、満タンに戻って見える）。
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
    def barZIndex(): Int32 = 50

    pub def childName(): String = "HPBar"

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

    // ─── 公開 API（P6-1g: 直描き） ────────────────────────────

    /// 全ユニットの足元 HP バーを World store から直描きする。
    ///   - HP = World.hpOf / 最大 HP = World.baseStatsOf#hp（SetHp/SetBaseStats が唯一の書込）
    ///   - 暗転 = waited（味方）/ enemyActed（敵）→ UITheme.dimmed() 乗算
    ///   - 位置 = unit marker global + 足元オフセット（marker が移動 tween/lunge の位置権威のまま）
    ///   - 攻撃予報の「減る分」= ForecastState（BattlePanel が毎フレーム put）
    /// 退場（hidden）ユニットは描かない。ノード不在ユニット（死亡除去後）も自然にスキップ。
    pub def renderBars(world: World, transform: Camera2D.ViewTransform, scene: Scene[NodeTag]):
            List[GameEngine.Drawable] \ {GameEngine.Game, ForecastState} =
        let fc = ForecastState.get();
        let players = PlayerScene.getAll(scene)
            |> List.filter(d -> not d#hidden)
            |> List.flatMap(d -> {
                let ref = World.EntityRef.Player(d#id);
                // P6-1h: 暗転は World.unitModulate store（本体/バー/アイコン共通の単一真実源。
                // setSpriteModulate 系が Cmd.SetModulate を emit し showAllActive も同経路）。
                let post = fc |> Option.flatMap(f ->
                    if (f#attackerId == d#id) Some((f#playerHpPost, f#dark)) else None);
                barDrawables(ref, PlayerScene.playerPath(d#id), Team.Player,
                    World.modulateOf(ref, world), post, world, transform, scene)
            });
        let enemies = EnemyScene.getAll(scene)
            // フォグで隠れた敵は描かない（applyFog が marker を隠す＝isVisible が真実源。
            // 旧実装は bar/icon が marker の子だったため祖先不可視で連動して消えていた）。
            |> List.filter(d -> EnemyScene.isVisible(d#id, scene))
            |> List.flatMap(d -> {
                let ref = World.EntityRef.Enemy(d#id);
                let post = fc |> Option.flatMap(f ->
                    if (f#defenderId == d#id) Some((f#enemyHpPost, f#dark)) else None);
                barDrawables(ref, EnemyScene.enemyPath(d#id), Team.Enemy,
                    World.modulateOf(ref, world), post, world, transform, scene)
            });
        List.append(players, enemies)


    /// 1 ユニットぶんの HP バー Drawable 列（Bg トラック + Fill + 予報オーバーレイ）。
    def barDrawables(ref: World.EntityRef, unitPath: NodePath, team: Team, modColor: Color,
                      post: Option[(Int32, Bool)], world: World,
                      transform: Camera2D.ViewTransform, scene: Scene[NodeTag]):
            List[GameEngine.Drawable] \ GameEngine.Game =
        match (World.posOf(ref, world), Scene.getEngineNode(unitPath, scene)) {
            case (Some(_), Some(_)) =>
                let hp    = World.hpOf(ref, world) |> Option.getWithDefault(0);
                let maxHp = World.baseStatsOf(ref, world) |> Option.map(b -> b#maxHp) |> Option.getWithDefault(0);
                if (maxHp <= 0) Nil
                else {
                    let markerG = Scene.globalPositionAt(unitPath, scene);
                    let barTopLeft: Vec2.Vec2 =
                        {x = markerG#x - barWidthPx() / 2.0, y = markerG#y + barFeetY()};
                    let bg = ColorRect.make({x = barWidthPx(), y = barHeightPx()}, mulColor(trackColor(), modColor))
                        |> ColorRect.setCornerRadius(barCornerRadius());
                    let fill = ColorRect.make(
                            {x = fillWidth(hp, maxHp, innerWidthPx()), y = innerHeightPx()},
                            mulColor(fillColorFor(team), modColor))
                        |> ColorRect.setCornerRadius(fillCornerRadius());
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
                                let prev = ColorRect.make({x = w, y = innerHeightPx()},
                                        mulColor(mulColor(fillColorFor(team), blink), modColor))
                                    |> ColorRect.setStripe(dmgStripeColor(), dmgStripeAlpha(),
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

    /// ColorRect 値 1 枚を world 左上座標へ Drawable 化する（tree に積まない）。
    def rectDrawables(rect: ColorRect, worldTopLeft: Vec2.Vec2, z: Int32,
                       transform: Camera2D.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        let screenPos = Camera2D.applyToWorldPos(transform, worldTopLeft);
        GameEngine.Renderable.toDrawables(EngineNode.ColorRectWithState(rect, NodeTag.NoTag), screenPos)
            |> Render.applyCameraScale(transform)
            |> List.map(d -> {zIndex = z | d})

    /// 乗算合成（engine の祖先 modulate 伝播の代替）。
    def mulColor(a: Color, b: Color): Color =
        {r = a#r * b#r, g = a#g * b#g, b = a#b * b#b}
}
