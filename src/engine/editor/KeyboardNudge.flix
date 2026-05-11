// KeyboardNudge — 矢印キーで選択ノードを 1px / 10px 単位で動かす + Ctrl+Shift で scale 変更
//
// マウスドラッグでは 1px 精度の調整が辛いため、選択中ノードを矢印キーで
// 微調整できるようにする。
//   - Arrow            : 1px 移動
//   - Shift+Arrow      : 10px 移動
//   - Ctrl+Shift+Arrow : scale を 0.1 ステップで変更

mod KeyboardNudge {

    def scaleStep(): Float64 = 0.1

    def minScale(): Float64 = 0.1

    /// 矢印キー（4 方向）の押下状態スナップ。
    pub type alias ArrowKeys = {
        up = Bool,
        down = Bool,
        left = Bool,
        right = Bool
    }

    pub def initialPrev(): ArrowKeys =
        {up = false, down = false, left = false, right = false}

    pub def readArrows(): ArrowKeys \ GameEngine.Game = {
        up    = GameEngine.Game.isKeyPressed(GameEngine.Key.Up),
        down  = GameEngine.Game.isKeyPressed(GameEngine.Key.Down),
        left  = GameEngine.Game.isKeyPressed(GameEngine.Key.Left),
        right = GameEngine.Game.isKeyPressed(GameEngine.Key.Right)
    }

    pub def pressEdges(prev: ArrowKeys, cur: ArrowKeys): ArrowKeys = {
        up    = cur#up    and not prev#up,
        down  = cur#down  and not prev#down,
        left  = cur#left  and not prev#left,
        right = cur#right and not prev#right
    }

    pub def nudgeDelta(edges: ArrowKeys, step: Float64): Vec2.Vec2 =
        let dx = (if (edges#right) step else 0.0) - (if (edges#left) step else 0.0);
        let dy = (if (edges#down)  step else 0.0) - (if (edges#up)   step else 0.0);
        {x = dx, y = dy}

    pub def scaleDelta(edges: ArrowKeys, step: Float64): Vec2.Vec2 =
        let dx = (if (edges#right) step else 0.0) - (if (edges#left) step else 0.0);
        let dy = (if (edges#down)  step else 0.0) - (if (edges#up)   step else 0.0);
        {x = dx, y = dy}

    /// 押下エッジに応じて選択ノードを動かし JSON に書き戻す。
    pub def applyNudge(stateData: Editor.EditorStateData,
                       curArrows: ArrowKeys,
                       scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditHistory.Rewind, GameEngine.Game,
                              Fs.FileRead, Fs.FileWrite} =
        match stateData#selected {
            case None => scene
            case Some((jsonPath, nodePath)) =>
                let edges = pressEdges(stateData#prevArrowKeys, curArrows);
                let shift = GameEngine.Game.isKeyPressed(GameEngine.Key.LeftShift);
                let ctrl = GameEngine.Game.isKeyPressed(GameEngine.Key.LeftCtrl);
                if (ctrl and shift) {
                    let dScale = scaleDelta(edges, scaleStep());
                    if (dScale#x == 0.0 and dScale#y == 0.0) scene
                    else applyScaleAndSave(jsonPath, nodePath, dScale, scene)
                } else {
                    let step = if (shift) 10.0 else 1.0;
                    let delta = nudgeDelta(edges, step);
                    if (delta#x == 0.0 and delta#y == 0.0) scene
                    else moveAndSave(jsonPath, nodePath, delta, scene)
                }
        }

    def moveAndSave(jsonPath: String, nodePath: NodePath, delta: Vec2.Vec2,
                    scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        let curGlobal = Scene.globalPositionAt(nodePath, scene);
        EditHistory.Rewind.save(EditHistory.Entry.MoveEntry({
            jsonPath = jsonPath, nodePath = nodePath,
            prevWorldPos = curGlobal}));
        let newGlobal = Vec2.round(Vec2.add(curGlobal, delta));
        let newScene = scene
            |> Scene.setGlobalPositionAt(nodePath, newGlobal)
            |> Scene.mapEngineNode(nodePath, engineNode ->
                Node2D.setPosition(Vec2.round(Node2D.getPosition(engineNode)),
                                   engineNode));
        let localPos = match Scene.getEngineNode(nodePath, newScene) {
            case Some(engineNode) => Node2D.getPosition(engineNode)
            case None             => Vec2.zero()
        };
        SceneSerializer.updatePos(jsonPath, nodePath, localPos);
        newScene

    def applyScaleAndSave(jsonPath: String, nodePath: NodePath, deltaScale: Vec2.Vec2,
                          scene: Scene[NodeTag]):
            Scene[NodeTag] \ {EditHistory.Rewind, Fs.FileRead, Fs.FileWrite} =
        match Scene.getEngineNode(nodePath, scene) {
            case None => scene
            case Some(engineNode) =>
                let curScale = Node2D.getScale(engineNode);
                let curGlobal = Scene.globalPositionAt(nodePath, scene);
                let newScale = {x = Float64.max(minScale(), curScale#x + deltaScale#x),
                                y = Float64.max(minScale(), curScale#y + deltaScale#y)};
                if (newScale#x == curScale#x and newScale#y == curScale#y) scene
                else {
                    EditHistory.Rewind.save(EditHistory.Entry.ScaleEntry({
                        jsonPath = jsonPath, nodePath = nodePath,
                        prevWorldPos = curGlobal, prevScale = curScale}));
                    let newScene = Scene.mapEngineNode(nodePath,
                        Node2D.setScale(newScale), scene);
                    SceneSerializer.updateScale(jsonPath, nodePath, newScale);
                    newScene
                }
        }
}
