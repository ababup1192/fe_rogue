/// BattlePanelScene — 攻撃前の戦闘予報パネル
///
/// `AttackForecast` フェーズで右上に表示される。武器を選んだ瞬間に
/// 「攻撃側（味方）」と「防御側（敵）」の HP / 威力 / 命中 を Combat.forecast から
/// 算出して並べて見せる。Z で攻撃を実行、X/Escape で武器選択に戻る。
///
/// ノード構造（visible のとき）:
///   BattlePanel (CanvasLayer, layer=3)
///     └─ panel (Panel, NodeTag.BattlePanel)
///           └─ text (Label2D, NodeTag.BattleText)
mod BattlePanelScene {

    use JsonCompat.PathTag.Root

    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/BattlePanelScene.scene.json")

    /// fontManifest で登録した name と一致させる（LogScene / WeaponMenuScene と同じ "ui"）
    def fontName(): String = "ui"

    def rootName(): String = "BattlePanel"
    pub def panelName(): String = "panel"
    // VBox 構成: 上=味方武器名(青帯) / 中=数値 3 カラム(青|暗|赤) / 下=敵武器名(赤帯)。
    // 各セルは背景 ColorRect（FullRect）+ テキスト Label2D の 2 ノード。
    // Container はロード時 directive なので、これらは CanvasLayer 直下 (root::名前) に並ぶ。
    // 各カラムは HP 行だけ独立ラベル（点滅・グレー用）。leftRest/rightRest は威力/命中の 2 行。
    def topBgName(): String       = "topBg"
    def pWeaponName(): String     = "playerWeaponText"
    def leftBgName(): String      = "leftBg"
    def leftHpName(): String      = "leftHp"
    def leftPowerName(): String   = "leftPower"
    def leftRestName(): String    = "leftRest"
    def centerBgName(): String    = "centerBg"
    def centerHpName(): String    = "centerHp"
    def centerRestName(): String  = "centerRest"
    def rightBgName(): String     = "rightBg"
    def rightHpName(): String     = "rightHp"
    def rightRestName(): String   = "rightRest"
    def botBgName(): String       = "botBg"
    def eWeaponName(): String     = "enemyWeaponText"

    pub def rootPath(): NodePath  = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    def topBgPath(): NodePath      = rootName() :: topBgName()      :: Nil
    def pWeaponPath(): NodePath    = rootName() :: pWeaponName()    :: Nil
    def leftBgPath(): NodePath     = rootName() :: leftBgName()     :: Nil
    def leftHpPath(): NodePath     = rootName() :: leftHpName()     :: Nil
    def leftPowerPath(): NodePath  = rootName() :: leftPowerName()  :: Nil
    def leftRestPath(): NodePath   = rootName() :: leftRestName()   :: Nil
    def centerBgPath(): NodePath   = rootName() :: centerBgName()   :: Nil
    def centerHpPath(): NodePath   = rootName() :: centerHpName()   :: Nil
    def centerRestPath(): NodePath = rootName() :: centerRestName() :: Nil
    def rightBgPath(): NodePath    = rootName() :: rightBgName()    :: Nil
    def rightHpPath(): NodePath    = rootName() :: rightHpName()    :: Nil
    def rightRestPath(): NodePath  = rootName() :: rightRestName()  :: Nil
    def botBgPath(): NodePath      = rootName() :: botBgName()      :: Nil
    def eWeaponPath(): NodePath    = rootName() :: eWeaponName()    :: Nil

    /// scene.json 内の "tag" 文字列 → NodeTag への変換
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("BattlePanel") => Ok(NodeTag.BattlePanel(Duration.zero()))
            case Some("BattleText")  => Ok(NodeTag.BattleText)
            case Some(unknown)         =>
                Err(JsonCompat.jsonError(Root, Set#{"BattlePanelScene tag (got: ${unknown})"}))
        }

    /// scene にパネルを追加する
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 現フェーズに応じて Panel と Label2D の visible を切り替える（Push モデル）。
    /// Label2D の visible も Panel と一緒に切り替えるのは、Label2D 自体は描画パス上
    /// 親の可視性を見ない実装で、`visible=true` のまま放置すると非表示中もテキストが
    /// 描画されてしまうため。
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        // 戦闘予測 = ターゲット選択フェーズ(PlayerAttack)。カーソルで敵を選ぶ間ずっと表示する。
        let visible = phase == TurnPhase.Phase.PlayerAttack;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> setBgVisible(topBgPath(), visible)
            |> setBgVisible(leftBgPath(), visible)
            |> setBgVisible(centerBgPath(), visible)
            |> setBgVisible(rightBgPath(), visible)
            |> setBgVisible(botBgPath(), visible)
            |> Label2D.mapAt(pWeaponPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(leftHpPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(leftPowerPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(leftRestPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(centerHpPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(centerRestPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(rightHpPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(rightRestPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(eWeaponPath(), CanvasItem.setVisible(visible))

    /// 背景 ColorRect の可視性を path 指定で切り替える。
    /// ColorRect には mapAt が無いので Scene.mapEngineNode + EngineNode.mapColorRect を使う。
    def setBgVisible(path: NodePath, visible: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(path,
            en -> EngineNode.mapColorRect(rect -> CanvasItem.setVisible(visible, rect), en), scene)

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から BattlePanel の Panel
    /// ノードに対して dispatch される (panel は 1 個のみなので 1 フレーム 1 回)。
    /// phase に応じて Panel + Label2D の visible を再評価し、AttackForecast フェーズ中は
    /// 選択中プレイヤー / 武器 / 攻撃対象から予報テキストを毎フレーム再構築する。
    /// 自走モデルなので外部 (WeaponMenu 等) からテキスト更新を push する必要はない。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {TurnPhase.State, SelectedPlayer.State,
                       PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        let phase = TurnPhase.State.get();
        // HP 点滅のサイクル内経過時間を delta 分進めて panel ノードに書き戻す。
        let elapsed = match Scene.getState(panelPath(), scene) {
            case Some(NodeTag.BattlePanel(e)) => e
            case _                            => Duration.zero()
        };
        let newElapsed = advanceBlink(Duration.add(elapsed, delta));
        let synced     = syncTargetToCursor(phase, scene);
        let visible    = applyVisibility(phase, synced);
        // 予測に使う武器は「攻撃中の武器選択リストでアクティブな武器」(= カーソル上の敵に
        // 届く選択武器)。武器を上下で切り替えるたびに予測も切り替わる。
        let selWeapon  = selectedAttackWeapon(synced);
        let forecasted = applyForecast(phase, newElapsed, selWeapon, visible);
        let next       = writeElapsed(newElapsed, forecasted);
        match Scene.getEngineNode(panelPath(), next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

    /// 点滅サイクル長。前半は戦闘後HP(灰)、後半は現在HP(白) を見せる。
    def blinkCycle(): Duration.Duration = Duration.seconds(1.6)

    /// `elapsed` をサイクル長で巻き戻す（dt はサイクル未満前提で 1 回引き算）。
    def advanceBlink(e: Duration.Duration): Duration.Duration =
        if (Duration.toSeconds(e) >= Duration.toSeconds(blinkCycle()))
            Duration.sub(e, blinkCycle())
        else e

    /// サイクル前半なら戦闘後HP(灰)を見せる。
    def blinkShowsDamaged(elapsed: Duration.Duration): Bool =
        Duration.toSeconds(elapsed) < Duration.toSeconds(blinkCycle()) / 2.0

    /// 点滅経過時間を panel ノードのタグに書き戻す。
    def writeElapsed(newElapsed: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(panelPath(), n -> match n {
            case EngineNode.PanelWithState(p, NodeTag.BattlePanel(_)) =>
                EngineNode.PanelWithState(p, NodeTag.BattlePanel(newElapsed))
            case other => other
        }, scene)

    /// PlayerAttack 中、攻撃対象をカーソル位置の敵に毎フレーム同期する。
    /// カーソルは `CursorScene.stepTargetCycle` で射程内の敵の上を巡回するので、
    /// 「今カーソルが乗っている敵」が攻撃対象になり、予報も Z の確定もそれを使う。
    /// カーソルが敵に乗っていなければ対象をクリアする（予報は空・確定は no-op）。
    def syncTargetToCursor(phase: TurnPhase.Phase, scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        if (phase != TurnPhase.Phase.PlayerAttack) scene
        else match SelectedPlayer.State.get()#id {
            case None             => scene
            case Some(attackerId) =>
                match EnemyScene.findIdAt(CursorScene.getGridPos(scene), scene) {
                    case Some(enemyId) => CombatScene.setAttackTargetId(attackerId, enemyId, scene)
                    case None          => CombatScene.clearAttackTargetId(attackerId, scene)
                }
        }

    /// PlayerAttack(= ターゲット選択 + 戦闘予測)中だけ各 Label2D に予報を書き込む。
    /// 静的なラベル（武器名・威力/命中・中央ラベル）はそのまま、HP 行は点滅で
    /// 現在HP(白) ⇄ 戦闘後HP(灰) を切り替える。同フェーズ中は毎フレーム呼ばれる。
    def applyForecast(phase: TurnPhase.Phase, elapsed: Duration.Duration,
                       selWeapon: Option[UnitCatalog.WeaponResource], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State,
                              PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        if (phase != TurnPhase.Phase.PlayerAttack)
            // 予報を抜けたら足元 HP バーの予測オーバーレイを消す（パネルは applyVisibility が隠す）。
            clearAllHpForecasts(scene)
        else
            let cols = buildColumns(selWeapon);
            let showDamaged = blinkShowsDamaged(elapsed);
            scene
                |> Label2D.mapAt(pWeaponPath(),    Label2D.setText(cols#pWeapon))
                |> Label2D.mapAt(eWeaponPath(),    Label2D.setText(cols#eWeapon))
                // 威力は独立ラベル。苦手武器のときだけ青字で「80% に下がっている」と知らせる。
                |> Label2D.mapAt(leftPowerPath(), lbl -> lbl
                       |> Label2D.setText(cols#leftPower)
                       |> CanvasItem.setModulate(
                            if (cols#playerProficient) powerNormalColor() else powerWeakColor()))
                |> Label2D.mapAt(leftRestPath(),   Label2D.setText(cols#leftRest))
                |> Label2D.mapAt(centerHpPath(),   Label2D.setText(cols#centerHp))
                |> Label2D.mapAt(centerRestPath(), Label2D.setText(cols#centerRest))
                |> Label2D.mapAt(rightRestPath(),  Label2D.setText(cols#rightRest))
                |> applyHpLabel(leftHpPath(),  cols#playerHpCur, cols#playerHpPost, cols#playerTakesDmg, showDamaged)
                |> applyHpLabel(rightHpPath(), cols#enemyHpCur,  cols#enemyHpPost,  cols#enemyTakesDmg,  showDamaged)
                // パネルの HP 点滅と同位相で、足元 HP バーの「減る分」を暗色点滅させる。
                |> applyHpBarForecast(cols, showDamaged)

    /// 攻撃予報中、攻撃側（味方）と対象（敵）の足元 HP バーに「減る分」の暗色点滅を反映する。
    /// 毎フレーム全ユニットの予測を一旦消してから対象 2 体へ出し直すので、カーソルが別の敵へ
    /// 移っても古い予測が残らない。`showDamaged` は BattlePanel の HP 点滅と同位相。
    def applyHpBarForecast(cols: Forecast, showDamaged: Bool, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        let cleared = clearAllHpForecasts(scene);
        if (cols#attackerId < 0 or cols#defenderId < 0) cleared
        else cleared
            |> UnitHPBarScene.showDamageForecast(EnemyScene.enemyPath(cols#defenderId),
                    cols#enemyHpCur, cols#enemyHpPost, showDamaged)
            |> UnitHPBarScene.showDamageForecast(PlayerScene.playerPath(cols#attackerId),
                    cols#playerHpCur, cols#playerHpPost, showDamaged)

    /// 全ユニット（味方・敵）の足元 HP バー予測オーバーレイを消す。
    /// 予報フェーズを抜けたフレームや、対象が変わったフレームの取りこぼし防止に使う。
    def clearAllHpForecasts(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        let hidePlayer = (acc, p) -> UnitHPBarScene.hideDamageForecast(PlayerScene.playerPath(p#id), acc);
        let hideEnemy  = (acc, e) -> UnitHPBarScene.hideDamageForecast(EnemyScene.enemyPath(e#id), acc);
        let withPlayers = List.foldLeft(hidePlayer, scene, PlayerScene.PartyQuery.getAll());
        List.foldLeft(hideEnemy, withPlayers, EnemyScene.RosterQuery.getAll())

    /// HP ラベル 1 つを点滅で更新する。ダメージを受ける側でサイクル前半のときだけ
    /// 戦闘後HP(灰)、それ以外は現在HP(白)。数値は他の数値列と同じ幅で右寄せ。
    def applyHpLabel(path: NodePath, current: Int32, postDamage: Int32,
                      takesDamage: Bool, showDamaged: Bool,
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        let (value, color) =
            if (takesDamage and showDamaged) (postDamage, hpDamagedColor())
            else                             (current,    hpNormalColor());
        Label2D.mapAt(path,
            label -> label
                |> Label2D.setText(padLeft("${value}", numWidth()))
                |> CanvasItem.setModulate(color),
            scene)

    /// 現在HP（通常）の文字色 = 白。
    /// 威力ラベルの通常色（白）。得意武器のときはこれ。
    def powerNormalColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    /// 苦手武器のときの威力ラベル色（青）。80% に下がっていることを示す。
    def powerWeakColor(): Color = {r = 0.45f32, g = 0.65f32, b = 1.0f32}

    def hpNormalColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    /// 戦闘後HP（減少予測）の文字色 = グレー。
    def hpDamagedColor(): Color = {r = 0.55f32, g = 0.55f32, b = 0.55f32}

    /// 数値カラムの文字幅（右寄せ用）。HP / 威力 / 命中 で共通。
    def numWidth(): Int32 = 5

    /// `AttackForecast` + Z: 戦闘予報を確認した上で攻撃モーションを開始する。
    /// 攻撃モーションの完了 (`attack_lunge` finished) で `CombatScene.onLungeDone`
    /// が反撃 / kill 演出 / commit に流す。
    ///
    /// 遷移先は `PlayerAttack` ではなく **`PlayerAttackHold`**。`PlayerAttack` は
    /// 「赤マスでターゲット選択中」のフェーズで Z で WeaponMenu を再オープンできてしまうため、
    /// 攻撃モーション中もここに居ると Z 連打で `PlayerAttack → WeaponSelect → AttackForecast
    /// → PlayerAttack ...` のループが回って `startAttack` が再起動される（連打バグ）。
    /// `PlayerAttackHold` は `TurnRules.decide` の catch-all で全入力を `Stay` 扱いに
    /// するため、`attack_lunge` 完了 (`onLungeDone`) までキー入力をブロックできる。
    pub def confirm(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              TurnPhase.State, SelectedPlayer.State,
                              PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        // 選択中の味方 → 攻撃対象 → 対象の敵 が揃ったら攻撃を開始。欠けていれば何もしない。
        // Option を forM でたどってネストを浅くする（揃ったときだけ yield 本体の副作用が走る）。
        let started = forM (
            attackerId <- SelectedPlayer.State.get()#id;
            player     <- PlayerScene.PartyQuery.get(attackerId);
            defenderId <- player#attackTargetId;
            enemy      <- EnemyScene.RosterQuery.get(defenderId)
        ) yield {
            // 選択中の武器を先頭に装備してから攻撃する（startAttack は weapons.head を使う）。
            // activeAttackWeaponIndex は予報に出ていた武器と同じ index を返す。
            let idx      = ItemMenuScene.activeAttackWeaponIndex(scene) |> Option.getWithDefault(0);
            let equipped = PlayerScene.equipWeapon(attackerId, idx, scene);
            TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
            GameLogger.playerLog("味方${attackerId}の攻撃");
            CombatScene.startAttack(Faction.Player, attackerId, defenderId, enemy#gridPos, equipped)
        };
        Option.getWithDefault(scene, started)

    /// `AttackForecast` + X: 攻撃をやめて行動メニュー (ActionSelect) に戻る。
    /// 待機にはせず（ターン消費しない）、`attackTargetId` をクリアしてカーソルを選択中
    /// 味方に戻す。次フレームの `ActionMenuScene.refreshItems` がメニューを再表示する。
    pub def cancel(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              TurnPhase.State, SelectedPlayer.State,
                              PlayerScene.PartyQuery} =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        match SelectedPlayer.State.get()#id {
            case None             => scene
            case Some(attackerId) =>
                CombatScene.clearAttackTargetId(attackerId, scene)
                    |> CursorScene.snapToPlayer
        }

    /// 予報セルの組（点滅 HP 用の数値を含む）。テキスト系は整形済み文字列、HP 系は数値。
    /// playerHpCur/Post は味方の現在/戦闘後HP、enemyHpCur/Post は敵の現在/戦闘後HP。
    /// takesDmg はそのユニットがダメージを受けるか（点滅させるかの判定）。
    /// `attackerId` / `defenderId` は足元 HP バーへ予測を反映するための対象 id
    /// （味方 = 攻撃側 / 敵 = 防御側）。予報が出せないときは -1（= 対象なし）。
    type alias Forecast = {
        attackerId = Int32, defenderId = Int32,
        pWeapon = String, eWeapon = String,
        // leftPower = 味方の威力（独立ラベル・苦手なら青）。leftRest = 味方の命中。
        leftPower = String, playerProficient = Bool,
        leftRest = String, centerHp = String, centerRest = String, rightRest = String,
        playerHpCur = Int32, playerHpPost = Int32, playerTakesDmg = Bool,
        enemyHpCur = Int32, enemyHpPost = Int32, enemyTakesDmg = Bool
    }

    /// 攻撃中の武器選択リストでアクティブな武器 `selWeapon` を返す（カーソル上の敵に届く
    /// 選択武器）。`process` から呼んで `applyForecast` / `buildColumns` に渡す。
    /// 敵が居ない / 届く武器が無いなら None（予報は空になる）。
    def selectedAttackWeapon(scene: Scene[NodeTag]):
            Option[UnitCatalog.WeaponResource] \ SelectedPlayer.State =
        forM (
            idx      <- ItemMenuScene.activeAttackWeaponIndex(scene);
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerScene.get(playerId, scene);
            w        <- List.nth(idx, player#weapons)
        ) yield w

    /// 選択中プレイヤー / 攻撃対象敵 / 選択武器が揃ったら予報を組み立てる。
    /// 揃わなければ全カラム空・HP 0 を返す（visible でないフェーズで描画されない想定）。
    def buildColumns(selWeapon: Option[UnitCatalog.WeaponResource]): Forecast
            \ {SelectedPlayer.State, PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        // 選択中の味方 → 攻撃対象の敵 → 選択武器まで Option を forM でたどる。
        let columns = forM (
            pid    <- SelectedPlayer.State.get()#id;
            player <- PlayerScene.PartyQuery.get(pid);
            eid    <- player#attackTargetId;
            enemy  <- EnemyScene.RosterQuery.get(eid);
            weapon <- selWeapon
        ) yield {attackerId = pid, defenderId = eid | formatColumns(player, weapon, enemy)};
        Option.getWithDefault(emptyForecast(), columns)

    /// 予報が出せないときの空 Forecast。
    def emptyForecast(): Forecast =
        {attackerId = -1, defenderId = -1,
         pWeapon = "", eWeapon = "",
         leftPower = "", playerProficient = true,
         leftRest = "", centerHp = "", centerRest = "", rightRest = "",
         playerHpCur = 0, playerHpPost = 0, playerTakesDmg = false,
         enemyHpCur = 0, enemyHpPost = 0, enemyTakesDmg = false}

    /// 予報を Forecast に整形する。
    ///   pWeapon / eWeapon … 味方 / 敵の武器名（＋相性マーク）。上下の帯に中央寄せ。
    ///   leftPower … 味方の威力（独立ラベル。苦手武器なら applyForecast が青字にする）。
    ///   leftRest … 味方の命中。rightRest … 敵の威力 / 命中 の 2 行。HP は別ラベルなので含めない。
    ///   centerHp / centerRest … 中央ラベル "HP" と "威力 / 命中"。
    ///   *HpCur / *HpPost … HP 点滅シミュレーション用の現在 / 戦闘後HP。
    /// 戦闘後HP = 現在HP − 受けるダメージ（下限 0）。敵は味方の攻撃で、味方は敵の反撃で減る。
    /// 敵が反撃できない（武器なし / 射程外）場合は敵側の威力 / 命中を "--"・反撃ダメージ 0。
    def formatColumns(player: PlayerScene.Data, weapon: UnitCatalog.WeaponResource,
                       enemy: EnemyScene.Data): Forecast =
        // 武器相性マーク表示用（味方の武器 vs 敵の装備武器。敵が未装備なら中立）。
        // 威力 / 命中の数値計算は `Combat.estimate`（faction 非依存）に集約済み。
        let rel  = WeaponTriangle.relationOpt(weapon#weaponType,
                                              enemy#weapon |> Option.map(w -> w#weaponType));
        let playerForecast = Combat.estimate(PlayerScene.combatViewWith(player, weapon),
                                             EnemyScene.combatView(enemy));
        let enemyCols = formatEnemyColumns(player, weapon, enemy);
        let bandWidth  = 16;  // 上下の帯の文字幅（武器名の中央寄せ用）
        let labelWidth = 5;   // 中央ラベルの文字幅（左マージン込みで中央へ寄せる）
        let pWeapon    = padCenter("${weapon#name}${relationMark(rel)}", bandWidth);
        let eWeapon    = padCenter(enemyCols#name, bandWidth);
        // 威力は独立ラベル（苦手なら青字）、命中は leftRest。中央/敵カラムは 2 行のまま。
        let proficient = UnitCatalog.proficientWith(player#resource, weapon#weaponType);
        let leftPower  = padLeft("${playerForecast#damage}", numWidth());
        let leftRest   = padLeft("${playerForecast#hit}%", numWidth());
        let centerHp   = padCenter("HP", labelWidth);
        let centerRest = "${padCenter("威力", labelWidth)}\n${padCenter("命中", labelWidth)}";
        let rightRest  = "${padLeft(enemyCols#atk, numWidth())}\n${padLeft(enemyCols#hit, numWidth())}";
        // HP シミュレーション: 戦闘後HP と「減るか」フラグ。
        let enemyHpPost  = Int32.max(0, enemy#hp - playerForecast#damage);
        let playerHpPost = Int32.max(0, player#hp - enemyCols#counterDamage);
        // attackerId/defenderId は buildColumns の yield で実 id に上書きする（ここは仮置き 0）。
        {attackerId = 0, defenderId = 0,
         pWeapon = pWeapon, eWeapon = eWeapon,
         leftPower = leftPower, playerProficient = proficient,
         leftRest = leftRest, centerHp = centerHp, centerRest = centerRest, rightRest = rightRest,
         playerHpCur = player#hp, playerHpPost = playerHpPost, playerTakesDmg = playerHpPost < player#hp,
         enemyHpCur = enemy#hp, enemyHpPost = enemyHpPost, enemyTakesDmg = enemyHpPost < enemy#hp}

    /// 敵側の威力 / 命中 / 反撃ダメージ。武器を装備し かつ 射程が「敵 → 味方」に届くときだけ
    /// 反撃成立で数値を出す。武器なし or 射程外なら "--"・反撃ダメージ 0。
    /// name は敵の武器名（＋相性マーク）。counterDamage は味方が受ける反撃ダメージ（点滅 HP 用）。
    def formatEnemyColumns(player: PlayerScene.Data,
                            weapon: UnitCatalog.WeaponResource,
                            enemy: EnemyScene.Data):
                           {name = String, atk = String, hit = String, counterDamage = Int32} =
        let playerWeaponType = Some(weapon#weaponType);
        match enemy#weapon {
            case None          => {name = "", atk = "--", hit = "--", counterDamage = 0}
            case Some(eWeapon) =>
                // 相性は射程に関係なく武器どうしで決まるので、武器名の隣のマークは常に出す。
                let eRel    = WeaponTriangle.relationOpt(eWeapon#weaponType, playerWeaponType);
                let nameStr = "${eWeapon#name}${relationMark(eRel)}";
                let d = Weapon.manhattan(enemy#gridPos, player#gridPos);
                if (not Weapon.canReach(d, eWeapon))
                    {name = nameStr, atk = "--", hit = "--", counterDamage = 0}
                else {
                    // 反撃の威力 / 命中は敵 → 味方の `Combat.estimate`（味方の予報と同一経路）。
                    let enemyForecast = Combat.estimate(EnemyScene.combatView(enemy),
                                                         PlayerScene.combatViewWith(player, weapon));
                    {name = nameStr,
                     atk = "${enemyForecast#damage}", hit = "${enemyForecast#hit}%",
                     counterDamage = enemyForecast#damage}
                }
        }

    /// 武器相性マーク。有利は ▲、不利は ▼、中立は空文字。
    /// 数値の直後に置くため、マークがあるときだけ先頭に半角スペースを 1 つ含める。
    /// ▲▼（塗りつぶし三角）を使うのは、現在の UI フォント(MPLUSU-Medium)が
    /// △▽（白抜き三角 U+25B3/U+25BD）のグリフを持たず別字に化けるため。
    def relationMark(rel: WeaponTriangle.Relation): String = match rel {
        case WeaponTriangle.Relation.Advantage    => " ▲"
        case WeaponTriangle.Relation.Disadvantage => " ▼"
        case WeaponTriangle.Relation.Neutral      => ""
    }

    /// 左側をスペースで埋めて指定幅にする（右寄せ。全角は 1 文字 2 幅で扱う）。
    /// 味方の数値を中央のラベル列に右から寄せるのに使う。
    def padLeft(text: String, width: Int32): String =
        let len = visualWidth(text);
        if (len >= width) text
        else String.repeat(width - len, " ") ++ text

    /// 中央寄せで指定幅にそろえる（全角は 1 文字 2 幅で扱う。余り 1 は左側に寄せる）。
    /// 余りを左に寄せるのは、中央帯のラベルにわずかな左マージンを持たせて中央に寄せるため。
    def padCenter(text: String, width: Int32): String =
        let len = visualWidth(text);
        if (len >= width) text
        else {
            let pad      = width - len;
            let rightPad = pad / 2;
            String.repeat(pad - rightPad, " ") ++ text ++ String.repeat(rightPad, " ")
        }

    /// 表示幅の概算: ASCII は 1、それ以外は 2 として数える。完全ではないが
    /// CJK と半角の混在で列を概ね揃えるための簡易計算。
    def visualWidth(s: String): Int32 =
        String.toList(s)
            |> List.foldLeft(acc -> ch ->
                if (Char.toBmpCodePoint(ch) < 0x80) acc + 1 else acc + 2,
                0)
}
