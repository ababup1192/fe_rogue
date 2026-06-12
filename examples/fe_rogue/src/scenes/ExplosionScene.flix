/// ExplosionScene — 一発再生の爆発エフェクト（火炎瓶 / 爆発瓶 / 魔法攻撃の着弾）
///
/// `DamagePopupScene` と同じ「World 配下に永続の親 Marker2D を 1 つ持ち、emit で
/// 子スプライトを連番でぶら下げ、process で寿命を減らしつつ自動消去する」流儀。
/// 子は `explosion` テクスチャ（assets/effect/explosion.png）の **1 行目** を
/// 寿命にわたって frame 0 → frameCount-1 まで送ることでコマ送りアニメする。
///
/// ノード構造:
///   Explosions (Marker2D, NodeTag.ExplosionsRoot({nextSeq}))   永続
///     └─ Explosion_<seq> (Sprite2D, NodeTag.Explosion({remaining, total}))  寿命つき
mod ExplosionScene {

    /// 親 Marker2D に紐づくデータ。子 Explosion_<seq> の連番採番にだけ使う。
    pub type alias RootData = { nextSeq = Int32 }

    /// 各 Explosion_<seq> Sprite2D に紐づくデータ。寿命の残り / 初期値（コマ送り比率算出用）。
    pub type alias ExpData = {
        remaining = Duration.Duration,
        total     = Duration.Duration
    }

    def rootName(): String = "Explosions"

    /// 親 Marker2D の NodePath。`World/Explosions` として固定。
    pub def rootPath(): NodePath = MapScene.worldName() :: rootName() :: Nil

    /// explosion.png は 896x576。64px グリッドで 14 列 x 9 行。**1 行目（frame 0..13）が爆発**。
    def texture(): String = "explosion"
    def hframes(): Int32 = 14
    def vframes(): Int32 = 9
    /// 1 行目で使うコマ数（14 列ぶん）。
    def frameCount(): Int32 = 14
    /// 1 マス 16px に対して少し大きめ（迫力重視）に見せる拡大率（火炎瓶 / 魔法攻撃の着弾）。
    def scaleFactor(): Float64 = 0.4
    /// 爆発瓶用の大きい拡大率。3×3 の影響範囲を覆うサイズ感。
    def bigScaleFactor(): Float64 = 0.95
    /// 1 回の爆発の寿命（出現 → 消滅）。
    def lifetime(): Duration.Duration = Duration.millis(500)
    /// ダメージポップアップ(100)より少し奥。ユニットよりは前面。
    def zIndex(): Int32 = 90

    /// World 配下に親 Marker2D を 1 つだけ生やす。`Game` の Scene 構築チェーンで
    /// MapScene の後に挟む（World が必要）。`DamagePopupScene.add` と同じ位置づけ。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        Scene.addChildAt(MapScene.worldPath(), rootName(),
            EngineNode.Marker2DWithState(parent,
                NodeTag.ExplosionsRoot({nextSeq = 0})),
            scene)

    /// 指定セル中心に通常サイズの爆発を 1 つ発生させる。親未登録（add 前）なら no-op。
    pub def emitAtCell(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Scene[NodeTag] =
        emit(MapSnapshot.cellCenter(cell), scaleFactor(), scene)

    /// 指定セル中心に大きい爆発を 1 つ発生させる（爆発瓶用。3×3 範囲を覆う見た目）。
    pub def emitBigAtCell(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]): Scene[NodeTag] =
        emit(MapSnapshot.cellCenter(cell), bigScaleFactor(), scene)

    /// 指定ワールド座標に通常サイズの爆発を 1 つ発生させる（魔法攻撃の着弾用）。
    pub def emitNormal(worldPos: Vec2.Vec2, scene: Scene[NodeTag]): Scene[NodeTag] =
        emit(worldPos, scaleFactor(), scene)

    /// 指定ワールド座標に `scale` 倍の爆発を 1 つ発生させる。親未登録なら no-op。
    pub def emit(worldPos: Vec2.Vec2, scale: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getEngineNode(rootPath(), scene) {
            case Some(EngineNode.Marker2DWithState(parent, NodeTag.ExplosionsRoot(root))) =>
                let seq = root#nextSeq;
                let sprite = Sprite2D.make(texture(), worldPos,
                                ({x = scale, y = scale}: Vec2.Vec2))
                                |> Sprite2D.setHframes(hframes())
                                |> Sprite2D.setVframes(vframes())
                                |> Sprite2D.setFrame(0)
                                |> CanvasItem.setZIndex(zIndex());
                let data: ExpData = {remaining = lifetime(), total = lifetime()};
                scene
                    |> Scene.setEngineNode(rootPath(),
                        EngineNode.Marker2DWithState(parent,
                            NodeTag.ExplosionsRoot({nextSeq = seq + 1})))
                    |> Scene.addChildAt(rootPath(), "Explosion_${seq}",
                        EngineNode.Sprite2DWithState(sprite, NodeTag.Explosion(data)))
            case _ => scene
        }

    /// `Game` の process redef から `ExplosionsRoot` ノードに dispatch される。
    /// 各子の remaining を dt 分減らし、経過比率から 1 行目のコマ（frame）を進め、
    /// 寿命満了の子は `Scene.removeAt` で取り除く。親未登録なら no-op。
    pub def process(dt: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        let childNames = Scene.getChildrenAt(rootPath(), scene);
        let next = List.foldLeft(acc -> childName -> {
            let childPath = MapScene.worldName() :: rootName() :: childName :: Nil;
            match Scene.getEngineNode(childPath, acc) {
                case Some(EngineNode.Sprite2DWithState(sprite, NodeTag.Explosion(data))) =>
                    let newRemaining = Duration.subClampedToZero(data#remaining, dt);
                    if (Duration.isExpired(newRemaining))
                        Scene.removeAt(childPath, acc)
                    else {
                        let elapsed = Duration.sub(data#total, newRemaining);
                        let ratio = Duration.ratio(elapsed, data#total);
                        let raw = Float64.truncateToInt32(
                                    Float64.floor(ratio * Int32.toFloat64(frameCount())));
                        let frame = Int32.max(0, Int32.min(frameCount() - 1, raw));
                        let newSprite = sprite |> Sprite2D.setFrame(frame);
                        let newData: ExpData = {remaining = newRemaining | data};
                        Scene.setEngineNode(childPath,
                            EngineNode.Sprite2DWithState(newSprite,
                                NodeTag.Explosion(newData)),
                            acc)
                    }
                case _ => acc
            }
        }, scene, childNames);
        (node, next)
}
