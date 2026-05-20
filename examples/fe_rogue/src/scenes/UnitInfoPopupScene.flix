/// UnitInfoPopupScene — カーソル上のユニット情報を画面中央に出す HUD ウィンドウ
///
/// PlayerCursor / PlayerAttack フェーズ中、カーソルが乗っているマスに味方/敵が居れば
/// 画面中央のパネルに「スプライト + 名前 + HP + ATK/DEF/SPD/MOV + HP バー」を表示する。
/// カーソルが空マスへ移動したら非表示。phase が cursor 系でないときも非表示。
///
/// ノード構造（layer=4、ForecastPanel(layer=3) より上）:
///   UnitInfoPopup (CanvasLayer, NodeTag.UnitInfoPanel({shownUnit: Option[(kind, id)]}))
///     └─ Panel (Panel, 中央配置)
///          ├─ Sprite (Sprite2D, ユニットの sprite)
///          ├─ Name   (Label2D, "Knight" 等)
///          ├─ HpText (Label2D, "HP 12/14")
///          ├─ HpBar  (ProgressBar)
///          └─ Stats  (Label2D, "ATK 6 DEF 5\nSPD 2 MOV 4")
///
/// 動作: 毎フレーム `update` が現在カーソル位置のユニットを判定し、前フレームと
/// 異なれば Panel 配下の動的 children を作り直して再表示。
mod UnitInfoPopupScene {

    // ─── 状態 ─────────────────────────────────────────────────

    /// 表示中ユニットの識別子。第 1 要素は `"enemy"` か `"player"`、第 2 要素は id。
    /// `None` のときは非表示。
    pub type alias PanelState = { shownUnit = Option[(String, Int32)] }

    // ─── 定数 ─────────────────────────────────────────────────

    def rootName(): String = "UnitInfoPopup"
    pub def rootPath(): NodePath = rootName() :: Nil

    def panelChildName(): String = "Panel"
    def panelPath(): NodePath = rootName() :: panelChildName() :: Nil

    /// fontManifest で登録した name と一致させる（LogScene 等と同じ "ui"）
    def fontName(): String = "ui"

    /// CanvasLayer 階層。ForecastPanel=3 より上に置く。
    def canvasLayerIdx(): Int32 = 4

    // パネル配置（128×128 デザイン解像度ベース、左上に固定）
    def panelPos(): Vec2.Vec2 = {x = 2.0, y = 2.0}
    def panelSize(): Vec2.Vec2 = {x = 64.0, y = 44.0}  // 旧 80×56 を約 80% に縮小

    // パネル内レイアウト（panel local 座標）
    def spriteScale(): Vec2.Vec2 = {x = 0.5, y = 0.5}  // 16×16 → 8×8 表示
    def spriteCenterLocal(): Vec2.Vec2 = {x = 7.0, y = 8.0}   // 8×8 の中央を (7,8) に置く
    def nameLocalPos(): Vec2.Vec2     = {x = 14.0, y = 4.0}
    def hpTextLocalPos(): Vec2.Vec2   = {x = 14.0, y = 14.0}
    def hpBarLocalPos(): Vec2.Vec2    = {x = 14.0, y = 20.0}
    def hpBarSize(): Vec2.Vec2        = {x = 44.0, y = 4.0}
    def statsLocalPos(): Vec2.Vec2    = {x = 3.0,  y = 28.0}

    def fontSizeBig(): Float64 = 6.0
    def fontSizeSmall(): Float64 = 4.0

    // 色
    def bgColor(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    def borderColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    def textColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    def hpBarFillColor(): Color = {r = 0.5f32, g = 0.9f32, b = 0.2f32}

    /// sprite#frame からユニットの表示名を引く（units.json の各キーに対応）
    def unitName(frame: Int32): String = match frame {
        case 0 => "Knight"
        case 1 => "Archer"
        case 2 => "Mage"
        case 3 => "Orc"
        case 4 => "Goblin"
        case _ => "Unknown"
    }

    // ─── 構築（初回） ─────────────────────────────────────────

    /// 空の CanvasLayer + 不可視 Panel を scene に追加する。
    /// `GameManager.buildPlayingScene` の構築チェーンで呼ぶ。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let initialState: PanelState = { shownUnit = None };
        let layer = CanvasLayer.make(canvasLayerIdx());
        let withLayer = Scene.addNode(rootName(),
            EngineNode.CanvasLayerWithState(layer, NodeTag.UnitInfoPanel(initialState)),
            scene);
        let panel = Panel.make(panelSize(), bgColor())
            |> Node2D.setPosition(panelPos())
            |> Panel.setBackgroundAlpha(0.45f32)   // ダンジョン視認性確保のため半透明
            |> Panel.setBorderColor(borderColor())
            |> Panel.setBorderWidth(1)
            |> CanvasItem.setVisible(false);
        Scene.addChildAt(rootPath(), panelChildName(),
            EngineNode.PanelWithState(panel, NodeTag.NoTag), withLayer)

    // ─── 毎フレーム更新 ───────────────────────────────────────

    /// 毎フレーム呼ぶ。カーソル位置にユニットが居ればパネル内容を組み立てて表示、
    /// 居なければ非表示。前フレームと同じユニットなら no-op で済む。
    pub def update(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, TurnPhase.State} =
        let phase = TurnPhase.State.get();
        let cursorActive = phase == TurnPhase.Phase.PlayerCursor
                        or phase == TurnPhase.Phase.PlayerAttack;
        if (not cursorActive) {
            // cursor フェーズ外: 表示中なら隠す
            if (Option.isEmpty(getShownUnit(scene))) scene
            else hide(scene)
        } else {
            let cursorPos = CursorScene.getGridPos(scene);
            let unitIdent = lookupUnitAt(cursorPos, scene);
            let prevIdent = getShownUnit(scene);
            if (unitIdent == prevIdent) scene  // 同じユニット: 何もしない
            else match unitIdent {
                case Some((kind, id)) =>
                    if (kind == "enemy") showEnemy(id, scene)
                    else showPlayer(id, scene)
                case None             => hide(scene)
            }
        }

    /// カーソル位置のユニット種別とid を返す。敵優先、無ければ味方。空マスなら None。
    def lookupUnitAt(coord: {x = Int32, y = Int32},
                      scene: Scene[NodeTag]): Option[(String, Int32)] =
        match EnemyScene.findIdAt(coord, scene) {
            case Some(id) => Some(("enemy", id))
            case None     =>
                PlayerScene.getAll(scene)
                    |> List.findMap(d ->
                        if (d#gridPos#x == coord#x and d#gridPos#y == coord#y)
                            Some(("player", d#id))
                        else None)
        }

    /// 現在 Panel に表示中のユニット識別子を取り出す（state から）。
    def getShownUnit(scene: Scene[NodeTag]): Option[(String, Int32)] =
        match Scene.getState(rootPath(), scene) {
            case Some(NodeTag.UnitInfoPanel(s)) => s#shownUnit
            case _                              => None
        }

    /// パネル state の `shownUnit` を更新する。
    def setShownUnit(unit: Option[(String, Int32)],
                      scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), n -> match n {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.UnitInfoPanel(_)) =>
                EngineNode.CanvasLayerWithState(layer,
                    NodeTag.UnitInfoPanel({shownUnit = unit}))
            case other => other
        }, scene)

    // ─── 表示/非表示 ──────────────────────────────────────────

    /// Panel 配下の動的 children（Sprite/Name/HpText/HpBar/Stats）を全部消す。
    def clearContents(scene: Scene[NodeTag]): Scene[NodeTag] =
        let childNames = Scene.getChildrenAt(panelPath(), scene);
        List.foldLeft(acc -> name -> {
            let childPath = List.append(panelPath(), name :: Nil);
            Scene.removeAt(childPath, acc)
        }, scene, childNames)

    /// Panel を非表示にして state をクリア。
    def hide(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> clearContents
            |> Scene.mapEngineNode(panelPath(), n -> match n {
                case EngineNode.PanelWithState(p, tag) =>
                    EngineNode.PanelWithState(CanvasItem.setVisible(false, p), tag)
                case other => other
            })
            |> setShownUnit(None)

    /// 敵ユニットの内容を表示。
    def showEnemy(id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        match EnemyScene.get(id, scene) {
            case None    => hide(scene)
            case Some(d) =>
                let withContents = renderPanel(d#resource, d#hp, scene);
                setShownUnit(Some(("enemy", id)), withContents)
        }

    /// 味方ユニットの内容を表示。
    def showPlayer(id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        match PlayerScene.get(id, scene) {
            case None    => hide(scene)
            case Some(d) =>
                let withContents = renderPanel(d#resource, d#hp, scene);
                setShownUnit(Some(("player", id)), withContents)
        }

    /// Panel 配下を一度クリアして Sprite/Name/HP テキスト/HP バー/Stats を建て、可視化する。
    def renderPanel(res: UnitCatalog.UnitResource, currentHp: Int32,
                     scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let cleared = clearContents(scene);
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        // Sprite（centered=true デフォルトで panel-local 中央寄せ位置に置く、半分サイズで描画）
        let sprite = Sprite2D.make(res#sprite#texture, spriteCenterLocal(), spriteScale())
            |> Sprite2D.setHframes(res#sprite#hframes)
            |> Sprite2D.setVframes(res#sprite#vframes)
            |> Sprite2D.setFrame(res#sprite#frame);
        let withSprite = Scene.addChildAt(panelPath(), "Sprite",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag), cleared);
        // Name Label
        let nameLabel = Label2D.make(unitName(res#sprite#frame), atlas, fontSizeBig())
            |> Node2D.setPosition(nameLocalPos())
            |> CanvasItem.setModulate(textColor());
        let withName = Scene.addChildAt(panelPath(), "Name",
            EngineNode.Label2DWithState(nameLabel, NodeTag.NoTag), withSprite);
        // HP text
        let hpText = Label2D.make("HP ${currentHp}/${res#hp}", atlas, fontSizeSmall())
            |> Node2D.setPosition(hpTextLocalPos())
            |> CanvasItem.setModulate(textColor());
        let withHpText = Scene.addChildAt(panelPath(), "HpText",
            EngineNode.Label2DWithState(hpText, NodeTag.NoTag), withName);
        // HP ProgressBar
        let hpBar = ProgressBar.make(hpBarSize(),
                                       Int32.toFloat64(res#hp), hpBarFillColor())
            |> Node2D.setPosition(hpBarLocalPos())
            |> ProgressBar.setValue(Int32.toFloat64(currentHp))
            |> ProgressBar.setBackgroundColor(bgColor())
            |> ProgressBar.setBorderColor(borderColor())
            |> ProgressBar.setBorderWidth(1);
        let withBar = Scene.addChildAt(panelPath(), "HpBar",
            EngineNode.ProgressBarWithState(hpBar, NodeTag.NoTag), withHpText);
        // Stats Label
        let statsText = "ATK ${res#attack}  DEF ${res#defense}\nSPD ${res#speed}  MOV ${res#moveTiles}";
        let statsLabel = Label2D.make(statsText, atlas, fontSizeSmall())
            |> Node2D.setPosition(statsLocalPos())
            |> CanvasItem.setModulate(textColor());
        let withStats = Scene.addChildAt(panelPath(), "Stats",
            EngineNode.Label2DWithState(statsLabel, NodeTag.NoTag), withBar);
        // Panel を可視化
        Scene.mapEngineNode(panelPath(), n -> match n {
            case EngineNode.PanelWithState(p, tag) =>
                EngineNode.PanelWithState(CanvasItem.setVisible(true, p), tag)
            case other => other
        }, withStats)
}
