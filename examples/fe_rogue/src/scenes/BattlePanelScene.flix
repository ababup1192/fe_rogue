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

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    def sceneJsonPath(): String = "src/scenes/BattlePanelScene.scene.json"

    /// fontManifest で登録した name と一致させる（LogScene / WeaponMenuScene と同じ "ui"）
    def fontName(): String = "ui"

    def rootName(): String = "BattlePanel"
    pub def panelName(): String = "panel"
    // VBox 構成: 上=味方武器名(青帯) / 中=数値 3 カラム(青|暗|赤) / 下=敵武器名(赤帯)。
    // 各セルは背景 ColorRect（FullRect）+ テキスト Label2D の 2 ノード。
    // Container はロード時 directive なので、これらは CanvasLayer 直下 (root::名前) に並ぶ。
    def topBgName(): String       = "topBg"
    def pWeaponName(): String     = "playerWeaponText"
    def leftBgName(): String      = "leftBg"
    def leftTextName(): String    = "leftText"
    def centerBgName(): String    = "centerBg"
    def centerTextName(): String  = "centerText"
    def rightBgName(): String     = "rightBg"
    def rightTextName(): String   = "rightText"
    def botBgName(): String       = "botBg"
    def eWeaponName(): String     = "enemyWeaponText"

    pub def rootPath(): NodePath  = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    def topBgPath(): NodePath      = rootName() :: topBgName()      :: Nil
    def pWeaponPath(): NodePath    = rootName() :: pWeaponName()    :: Nil
    def leftBgPath(): NodePath     = rootName() :: leftBgName()     :: Nil
    def leftTextPath(): NodePath   = rootName() :: leftTextName()   :: Nil
    def centerBgPath(): NodePath   = rootName() :: centerBgName()   :: Nil
    def centerTextPath(): NodePath = rootName() :: centerTextName() :: Nil
    def rightBgPath(): NodePath    = rootName() :: rightBgName()    :: Nil
    def rightTextPath(): NodePath  = rootName() :: rightTextName()  :: Nil
    def botBgPath(): NodePath      = rootName() :: botBgName()      :: Nil
    def eWeaponPath(): NodePath    = rootName() :: eWeaponName()    :: Nil

    /// scene.json 内の "tag" 文字列 → NodeTag への変換
    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("BattlePanel") => Ok(NodeTag.BattlePanel)
            case Some("BattleText")  => Ok(NodeTag.BattleText)
            case Some(unknown)         =>
                Err(JsonError(Root, Set#{"BattlePanelScene tag (got: ${unknown})"}))
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
            |> Label2D.mapAt(leftTextPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(centerTextPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(rightTextPath(), CanvasItem.setVisible(visible))
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
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {TurnPhase.State, SelectedPlayer.State,
                       PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        let phase = TurnPhase.State.get();
        let next = scene
            |> syncTargetToCursor(phase)
            |> applyVisibility(phase)
            |> applyText(phase);
        match Scene.getEngineNode(panelPath(), next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

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
                    case Some(enemyId) => PlayerScene.setAttackTargetId(attackerId, enemyId, scene)
                    case None          => PlayerScene.clearAttackTargetId(attackerId, scene)
                }
        }

    /// PlayerAttack(= ターゲット選択 + 戦闘予測)中だけ 3 カラムの Label2D に
    /// 予報テキストを書き込む。同フェーズ中は毎フレーム呼ばれるが setText は冪等。
    def applyText(phase: TurnPhase.Phase, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State,
                              PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        if (phase != TurnPhase.Phase.PlayerAttack) scene
        else
            let cols = buildColumns();
            scene
                |> Label2D.mapAt(pWeaponPath(),    Label2D.setText(cols#pWeapon))
                |> Label2D.mapAt(leftTextPath(),   Label2D.setText(cols#left))
                |> Label2D.mapAt(centerTextPath(), Label2D.setText(cols#center))
                |> Label2D.mapAt(rightTextPath(),  Label2D.setText(cols#right))
                |> Label2D.mapAt(eWeaponPath(),    Label2D.setText(cols#eWeapon))

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
        // 選択中の味方 → 攻撃対象 → 対象の敵 が揃ったら攻撃を開始。欠けていれば何もしない。
        // Option を forM でたどってネストを浅くする（揃ったときだけ yield 本体の副作用が走る）。
        let started = forM (
            attackerId <- SelectedPlayer.State.get()#id;
            player     <- PlayerScene.PartyQuery.get(attackerId);
            defenderId <- player#attackTargetId;
            enemy      <- EnemyScene.RosterQuery.get(defenderId)
        ) yield {
            TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
            GameLogger.playerLog("味方${attackerId}の攻撃");
            PlayerScene.startAttack(attackerId, defenderId, enemy#gridPos, scene)
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
                PlayerScene.clearAttackTargetId(attackerId, scene)
                    |> CursorScene.snapToPlayer
        }

    /// 選択中プレイヤー / 攻撃対象敵 / 選択中武器の組から 3 カラム分の予報テキストを組み立てる。
    /// 反撃が成立する（敵が生存・隣接・武器装備中）なら敵側の数値も出す。
    /// 該当条件が揃わなければ 3 カラムとも空文字（visible でないフェーズで描画されない想定）。
    def buildColumns(): {pWeapon = String, left = String, center = String, right = String, eWeapon = String}
            \ {SelectedPlayer.State, PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        // 選択中の味方 → 攻撃対象の敵 → 装備武器（weapons の先頭）まで揃って初めて予報を出す。
        // どれか欠けたら（None）全カラム空文字。Option を forM でたどってネストを浅くする。
        let columns = forM (
            pid    <- SelectedPlayer.State.get()#id;
            player <- PlayerScene.PartyQuery.get(pid);
            eid    <- player#attackTargetId;
            enemy  <- EnemyScene.RosterQuery.get(eid);
            weapon <- List.head(player#weapons)
        ) yield formatColumns(player, weapon, enemy);
        Option.getWithDefault(
            {pWeapon = "", left = "", center = "", right = "", eWeapon = ""}, columns)

    /// 予報を 5 つのテキストに整形する（FE 流レイアウト）。
    ///   pWeapon … 味方の武器名（＋相性マーク）。上の青帯に中央寄せで載せる。
    ///   left / center / right … 数値 3 行（HP / 威力 / 命中）の 味方 / ラベル / 敵 カラム。
    ///   eWeapon … 敵の武器名（＋相性マーク）。下の赤帯に中央寄せで載せる。
    /// カラムの横並び・色分け・行の縦積みは VBox/HBox + ColorRect が担う。ここは各セル内の
    /// 文字寄せ（武器名＝中央, 味方の数値＝右寄せ, 敵の数値＝右寄せ）だけを文字幅で調整する。
    /// 敵が反撃できない（武器なし / 射程外）場合は敵側の威力 / 命中を "--" にする。
    /// 相性マークは有利 △ / 不利 ▽ / 中立 なし（武器名の隣に置く）。
    def formatColumns(player: PlayerScene.Data, weapon: UnitCatalog.WeaponResource,
                       enemy: EnemyScene.Data):
                      {pWeapon = String, left = String, center = String, right = String, eWeapon = String} =
        let phys = UnitCatalog.isPhysical(weapon#weaponType);
        // 武器相性: 味方の武器 vs 敵の装備武器。敵が未装備なら中立。
        let rel  = WeaponTriangle.relationOpt(weapon#weaponType,
                                              enemy#weapon |> Option.map(w -> w#weaponType));
        let playerAtk = Combat.attackStatFor(player#resource#attack,
                                              player#resource#magicAttack,
                                              weapon#attack, phys);
        let enemyDef  = Combat.defenseStatFor(enemy#resource#defense,
                                               enemy#resource#magicDefense,
                                               phys);
        let playerForecast = Combat.forecast(
            {attack = playerAtk, skill = player#resource#skill,
             luck = player#resource#luck, weaponHit = weapon#hit},
            {hp = enemy#hp, defense = enemyDef,
             speed = enemy#resource#speed, luck = enemy#resource#luck},
            rel);
        let enemyCols = formatEnemyColumns(player, enemy);
        // 武器名は帯の幅（おおよその文字数）に中央寄せ。数値カラムは文字数で右寄せ。
        let bandWidth  = 16;  // 上下の帯の文字幅（武器名の中央寄せ用）
        let numWidth   = 5;   // 数値カラムの文字幅（右寄せ用）
        let labelWidth = 5;   // 中央ラベルの文字幅（左マージン込みで中央へ寄せる）
        let pWeapon = padCenter("${weapon#name}${relationMark(rel)}", bandWidth);
        let eWeapon = padCenter(enemyCols#name, bandWidth);
        let left = String.unlines(
            padLeft("${player#hp}", numWidth) ::
            padLeft("${playerForecast#damage}", numWidth) ::
            padLeft("${playerForecast#hit}%", numWidth) :: Nil);
        let center = String.unlines(
            padCenter("HP", labelWidth) :: padCenter("威力", labelWidth) :: padCenter("命中", labelWidth) :: Nil);
        // 敵の数値も右寄せ（味方と同じく右端そろえ）。
        let right = String.unlines(
            padLeft(enemyCols#hp, numWidth) ::
            padLeft(enemyCols#atk, numWidth) ::
            padLeft(enemyCols#hit, numWidth) :: Nil);
        {pWeapon = pWeapon, left = left, center = center, right = right, eWeapon = eWeapon}

    /// 敵側の数値。武器を装備していて かつ 敵の武器射程が「敵 → 味方」距離に届くときだけ
    /// 反撃可として威力 / 命中の数値を出す。武器なし or 射程外なら "--"。
    /// name は敵の武器名（＋相性マーク）。hp / atk / hit は数値だけ（ラベルは付けない）。
    /// 例: 味方が射程 2 の弓で 2 マス先の敵 (剣 range=1-1) を攻撃 → 敵は反撃不能。
    def formatEnemyColumns(player: PlayerScene.Data,
                            enemy: EnemyScene.Data): {name = String, hp = String, atk = String, hit = String} =
        let playerWeaponType = List.head(player#weapons) |> Option.map(w -> w#weaponType);
        let hpStr = "${enemy#hp}";
        match enemy#weapon {
            case None          => {name = "", hp = hpStr, atk = "--", hit = "--"}
            case Some(eWeapon) =>
                // 相性は射程に関係なく武器どうしで決まるので、武器名の隣のマークは常に出す。
                let eRel    = WeaponTriangle.relationOpt(eWeapon#weaponType, playerWeaponType);
                let nameStr = "${eWeapon#name}${relationMark(eRel)}";
                let d = Weapon.manhattan(enemy#gridPos, player#gridPos);
                if (not Weapon.canReach(d, eWeapon))
                    {name = nameStr, hp = hpStr, atk = "--", hit = "--"}
                else {
                    let ePhys = UnitCatalog.isPhysical(eWeapon#weaponType);
                    let enemyAtk = Combat.attackStatFor(enemy#resource#attack,
                                                         enemy#resource#magicAttack,
                                                         eWeapon#attack, ePhys);
                    let playerDef = Combat.defenseStatFor(player#resource#defense,
                                                           player#resource#magicDefense,
                                                           ePhys);
                    let enemyForecast = Combat.forecast(
                        {attack = enemyAtk, skill = enemy#resource#skill,
                         luck = enemy#resource#luck, weaponHit = eWeapon#hit},
                        {hp = player#hp, defense = playerDef,
                         speed = player#resource#speed, luck = player#resource#luck},
                        eRel);
                    {name = nameStr, hp = hpStr,
                     atk = "${enemyForecast#damage}", hit = "${enemyForecast#hit}%"}
                }
        }

    /// 武器相性マーク。有利は △、不利は ▽、中立は空文字。
    /// 数値の直後に置くため、マークがあるときだけ先頭に半角スペースを 1 つ含める。
    def relationMark(rel: WeaponTriangle.Relation): String = match rel {
        case WeaponTriangle.Relation.Advantage    => " △"
        case WeaponTriangle.Relation.Disadvantage => " ▽"
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
