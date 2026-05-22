/// ForecastPanelScene — 攻撃前の戦闘予報パネル
///
/// `AttackForecast` フェーズで右上に表示される。武器を選んだ瞬間に
/// 「攻撃側（味方）」と「防御側（敵）」の HP / 威力 / 命中 を Combat.forecast から
/// 算出して並べて見せる。Z で攻撃を実行、X/Escape で武器選択に戻る。
///
/// ノード構造（visible のとき）:
///   ForecastPanel (CanvasLayer, layer=3)
///     └─ panel (Panel, NodeTag.ForecastPanel)
///           └─ text (Label2D, NodeTag.ForecastText)
mod ForecastPanelScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    def sceneJsonPath(): String = "src/scenes/ForecastPanelScene.scene.json"

    /// fontManifest で登録した name と一致させる（LogScene / WeaponMenuScene と同じ "ui"）
    def fontName(): String = "ui"

    def rootName(): String = "ForecastPanel"
    pub def panelName(): String = "panel"
    pub def textName(): String  = "text"

    pub def rootPath(): NodePath  = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def textPath(): NodePath  = rootName() :: panelName() :: textName() :: Nil

    /// scene.json 内の "tag" 文字列 → NodeTag への変換
    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("ForecastPanel") => Ok(NodeTag.ForecastPanel)
            case Some("ForecastText")  => Ok(NodeTag.ForecastText)
            case Some(unknown)         =>
                Err(JsonError(Root, Set#{"ForecastPanelScene tag (got: ${unknown})"}))
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
        let visible = phase == TurnPhase.Phase.AttackForecast;
        scene
            |> Panel.mapAt(panelPath(), Panel.setVisible(visible))
            |> Label2D.mapAt(textPath(), Label2D.setVisible(visible))

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から ForecastPanel の Panel
    /// ノードに対して dispatch される (panel は 1 個のみなので 1 フレーム 1 回)。
    /// phase に応じて Panel + Label2D の visible を再評価し、AttackForecast フェーズ中は
    /// 選択中プレイヤー / 武器 / 攻撃対象から予報テキストを毎フレーム再構築する。
    /// 自走モデルなので外部 (WeaponMenu 等) からテキスト更新を push する必要はない。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {TurnPhase.State, SelectedPlayer.State,
                       PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        let phase = TurnPhase.State.get();
        let next = scene
            |> applyVisibility(phase)
            |> applyText(phase);
        match Scene.getEngineNode(panelPath(), next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

    /// AttackForecast フェーズのときだけ Label2D に予報テキストを書き込む。
    /// 同フェーズ中は毎フレーム呼ばれるが Label2D.setText は冪等。
    def applyText(phase: TurnPhase.Phase, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State,
                              PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        if (phase != TurnPhase.Phase.AttackForecast) scene
        else
            let text = buildForecastText();
            Label2D.mapAt(textPath(), Label2D.setText(text), scene)

    /// `AttackForecast` + Z: 戦闘予報を確認した上で攻撃モーションを開始する。
    /// 攻撃モーションの完了 (`attack_lunge` finished) で `PlayerScene.onAttackLungeDone`
    /// が反撃 / kill 演出 / commit に流す。
    ///
    /// 遷移先は `PlayerAttack` ではなく **`PlayerAttackHold`**。`PlayerAttack` は
    /// 「赤マスでターゲット選択中」のフェーズで Z で WeaponMenu を再オープンできてしまうため、
    /// 攻撃モーション中もここに居ると Z 連打で `PlayerAttack → WeaponSelect → AttackForecast
    /// → PlayerAttack ...` のループが回って `startAttack` が再起動される（連打バグ）。
    /// `PlayerAttackHold` は `TurnRules.decide` の catch-all で全入力を `Stay` 扱いに
    /// するため、`attack_lunge` 完了 (`onAttackLungeDone`) までキー入力をブロックできる。
    pub def confirm(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              TurnPhase.State, SelectedPlayer.State,
                              PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        match SelectedPlayer.State.get()#id {
            case None             => scene
            case Some(attackerId) =>
                match PlayerScene.PartyQuery.get(attackerId) {
                    case None         => scene
                    case Some(player) =>
                        match player#attackTargetId {
                            case None             => scene
                            case Some(defenderId) =>
                                match EnemyScene.RosterQuery.get(defenderId) {
                                    case None        => scene
                                    case Some(enemy) =>
                                        TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
                                        GameLogger.playerLog("味方${attackerId}の攻撃");
                                        PlayerScene.startAttack(attackerId, defenderId,
                                                                  enemy#gridPos, scene)
                                }
                        }
                }
        }

    /// `AttackForecast` + X: 予報をキャンセルして WeaponSelect に戻る (武器選び直し)。
    /// 選択中武器 index はクリアして再選択を促す (同じ武器をすぐ選び直しても OK)。
    pub def cancel(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.WeaponSelect);
        match SelectedPlayer.State.get()#id {
            case None             => scene
            case Some(attackerId) => PlayerScene.clearSelectedWeaponIdx(attackerId, scene)
        }

    /// 選択中プレイヤー / 攻撃対象敵 / 選択中武器の組から予報テキストを組み立てる。
    /// 反撃が成立する（敵が生存・隣接・武器装備中）なら敵側の予報も出す。
    /// 該当条件が揃わなければ空文字を返す（visible でないフェーズで描画されない想定）。
    def buildForecastText(): String
            \ {SelectedPlayer.State, PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        match SelectedPlayer.State.get()#id {
            case None     => ""
            case Some(pid) =>
                match PlayerScene.PartyQuery.get(pid) {
                    case None         => ""
                    case Some(player) =>
                        match player#attackTargetId {
                            case None         => ""
                            case Some(eid) =>
                                match EnemyScene.RosterQuery.get(eid) {
                                    case None        => ""
                                    case Some(enemy) =>
                                        let weaponIdx = Option.getWithDefault(0, player#selectedWeaponIdx);
                                        match List.nth(weaponIdx, player#weapons) {
                                            case None        => ""
                                            case Some(weapon) =>
                                                formatForecast(player, weapon, enemy)
                                        }
                                }
                        }
                }
        }

    /// 予報文字列の整形。1 行目はヘッダ、以降は HP / 威力 / 命中 を 2 列で並べる。
    /// 反撃可能（敵が武器を持っている）なら敵側の威力/命中も出す。範囲外なら "--" を出す。
    def formatForecast(player: PlayerScene.Data, weapon: UnitCatalog.WeaponResource,
                        enemy: EnemyScene.Data): String =
        let playerAtk = player#resource#attack + weapon#attack;
        let playerForecast = Combat.forecast(
            {attack = playerAtk, speed = player#resource#speed},
            {hp = enemy#hp, defense = enemy#resource#defense, speed = enemy#resource#speed});
        let enemyCols = formatEnemyColumns(player, enemy);
        let header   = padRight("味方", 10) ++ enemyCols#header;
        let hpLine   = padRight("HP   ${player#hp}", 10) ++ enemyCols#hp;
        let atkLine  = padRight("威力 ${playerForecast#damage}", 10) ++ enemyCols#atk;
        let hitLine  = padRight("命中 ${playerForecast#hit}%", 10) ++ enemyCols#hit;
        String.unlines(header :: hpLine :: atkLine :: hitLine :: Nil)

    /// 敵側の列。武器を装備していて かつ 敵の武器射程が「敵 → 味方」距離に届くときだけ
    /// 反撃可として威力/命中を出す。武器なし or 射程外なら "--" 表示。
    /// 例: 味方が射程 2 の弓で 2 マス先の敵 (剣 range=1-1) を攻撃 → 敵は反撃不能。
    def formatEnemyColumns(player: PlayerScene.Data,
                            enemy: EnemyScene.Data): {header = String, hp = String, atk = String, hit = String} =
        let header = "敵";
        let hpStr  = "HP   ${enemy#hp}";
        let unable = {header = header, hp = hpStr,
                       atk = "威力 --", hit = "命中 --"};
        match enemy#weapon {
            case None          => unable
            case Some(eWeapon) =>
                let d = Weapon.manhattan(enemy#gridPos, player#gridPos);
                if (not Weapon.canReach(d, eWeapon)) unable
                else {
                    let enemyAtk = enemy#resource#attack + eWeapon#attack;
                    let enemyForecast = Combat.forecast(
                        {attack = enemyAtk, speed = enemy#resource#speed},
                        {hp = player#hp, defense = player#resource#defense, speed = player#resource#speed});
                    {header = header, hp = hpStr,
                     atk = "威力 ${enemyForecast#damage}",
                     hit = "命中 ${enemyForecast#hit}%"}
                }
        }

    /// 右側に半角スペースで埋めて指定幅にする（全角は 1 文字 2 幅で扱う簡易版）。
    /// 列をきれいに揃えるためのヘルパ。
    def padRight(text: String, width: Int32): String =
        let len = visualWidth(text);
        if (len >= width) text
        else text ++ String.repeat(width - len, " ")

    /// 表示幅の概算: ASCII は 1、それ以外は 2 として数える。完全ではないが
    /// CJK と半角の混在で列を概ね揃えるための簡易計算。
    def visualWidth(s: String): Int32 =
        String.toList(s)
            |> List.foldLeft(acc -> ch ->
                if (Char.toBmpCodePoint(ch) < 0x80) acc + 1 else acc + 2,
                0)
}
