/// EnemyCardScene — 攻撃対象の敵の簡易情報カード（画面の右端）。
///
/// 攻撃フロー（WeaponSelect / PlayerAttack）で「いま狙っている敵」を、味方カード
/// （`UnitCardScene`）と同じレイアウト・同じ scene テンプレートで画面右に出す。
/// 内容は反転しない（味方カードと同じ並び）。違いは panel の表示位置だけ:
/// ビューポート幅は窓のアスペクトで変わる（設計高さ 128 基準の高さフィット）ため、
/// 右端は固定値でなく `getViewportRect` の実幅から毎フレーム算出して寄せる。
///
/// scene ファイルは味方カードと共有する（`UnitCardScene.scene.json` を `PackedScene` で
/// 別名 "EnemyCard" としてインスタンス化）。描画も `UnitCardScene.renderUnitInto` を再利用。
///
/// 対象の決め方は `BattlePanelScene` の予報対象と同じ:
///   - WeaponSelect : カーソルが乗っている敵（WeaponSelectScene が対象へスナップ済み）
///   - PlayerAttack : 選択中味方の `attackTargetId`
/// それ以外のフェーズや対象が居ないときは隠す。
///
/// ノード構造（layer=2）:
///   EnemyCard (CanvasLayer, NodeTag.EnemyCard)
///     └─ panel (Panel)  … children は process が UnitCardScene 経由で動的生成
mod EnemyCardScene {

    def rootName(): String = "EnemyCard"
    pub def rootPath(): NodePath = rootName() :: Nil
    def panelChildName(): String = "panel"
    def panelPath(): NodePath = rootName() :: panelChildName() :: Nil
    def fontName(): String = "ui"

    /// 画面右端からの余白（design px）。味方カードの左余白(2)と対称にする。
    def rightMargin(): Float64 = 2.0

    /// 味方カードと同じ scene テンプレートを別名 "EnemyCard" でインスタンス化し、
    /// CanvasLayer に NodeTag.EnemyCard を差し込む（初期非表示）。children は process が動的生成。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let template = PackedScene.load(UnitCardScene.sceneJsonPath());
        PackedScene.instantiate({
            opts      = {parentPath = Nil, nameOverride = Some(rootName()),
                         positionOverride = None},
            tagParser = SceneLoader.constTagParser(NodeTag.NoTag),
            template  = template,
            fontAtlas = Some(atlas),
            scene     = scene
        })
            |> Scene.setState(rootPath(), NodeTag.EnemyCard)

    /// Game.flix の process redef から NodeTag.EnemyCard ノードに dispatch される。
    /// 攻撃対象の敵が居ればカードを右端に寄せて描画、なければ隠す。
    pub def process(_delta: Duration.Duration, node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameEngine.Game, SelectedPlayer.State, TurnPhase.State} =
        let phase = TurnPhase.State.get();
        let next = match targetEnemyId(phase, scene) {
            case Some(eid) => match EnemyScene.get(eid, scene) {
                case Some(d) =>
                    let positioned = repositionRight(scene);
                    UnitCardScene.renderUnitInto(panelPath(),
                        UnitCardScene.enemyBorderColor(), UnitCardScene.enemyBarColor(),
                        d#resource, d#hp, Option.toList(d#weapon), d#ring, None, positioned)
                case None => UnitCardScene.hidePanel(panelPath(), scene)
            }
            case None => UnitCardScene.hidePanel(panelPath(), scene)
        };
        match Scene.getEngineNode(path, next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

    /// panel をビューポート右端へ寄せる（y は scene テンプレートの値を保つ）。
    /// 窓幅は実行時に変わるため `getViewportRect` の実幅から右端 x を求める。
    def repositionRight(scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let vp = GameEngine.Game.getViewportRect();
        let x = vp#size#x - UnitCardScene.panelW() - rightMargin();
        Panel.mapAt(panelPath(), p ->
            Node2D.setPosition({x = x, y = Node2D.getPosition(p)#y}, p), scene)

    /// いま狙っている敵の id（左の予報ミニ窓 `BattlePanelScene` と同じ対象）。
    ///   - WeaponSelect : カーソル上の（フォグで隠れていない）敵
    ///   - PlayerAttack : 選択中味方の attackTargetId
    /// それ以外は None。
    def targetEnemyId(phase: TurnPhase.Phase, scene: Scene[NodeTag]):
            Option[Int32] \ SelectedPlayer.State =
        match phase {
            case TurnPhase.Phase.WeaponSelect =>
                EnemyScene.findIdAt(CursorScene.getGridPos(scene), scene)
                    |> Option.filter(id -> EnemyScene.isVisible(id, scene))
            case TurnPhase.Phase.PlayerAttack =>
                match SelectedPlayer.State.get()#id {
                    case Some(pid) =>
                        PlayerScene.get(pid, scene) |> Option.flatMap(p -> p#attackTargetId)
                    case None => None
                }
            case _ => None
        }
}
