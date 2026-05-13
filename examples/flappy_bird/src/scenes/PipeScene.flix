// PipeScene — パイプ障害物の構築・リサイクル
//
// 上下パイプ + 採点用コインを Marker2D 親ノードでまとめ、親ごと自殺で 4 ノード一括削除する。
// 画面左端を超えたペアはリサイクルして右端に再配置する無限スクロール方式。
// スコアが低いうちは上下パイプの隙間を広くし、難易度を段階的に上げる。
//
//   Marker2DWithState(pipe_${id}, Pipe)
//     ├── StaticBody2DWithState(top, PipePart)
//     │     └── Sprite2DWithState(sprite, NoTag)
//     ├── StaticBody2DWithState(bottom, PipePart)
//     │     └── Sprite2DWithState(sprite, NoTag)
//     └── Area2DWithState(coin, Coin)

mod PipeScene {

    // ========================================================================
    // 定数
    // ========================================================================

    /// パイプグループ名（一括操作用）
    pub def pipeGroup(): String = "pipes"

    // ========================================================================
    // ノード名定数（ペア親 / 子ノード）
    // ========================================================================

    /// パイプペア親の名前接頭辞（"pipe_${counter}"）
    pub def pairNamePrefix(): String = "pipe"

    /// counter からペア親ノード名を作る
    pub def pairName(counter: Int32): String = "${pairNamePrefix()}_${counter}"

    /// 上パイプの子ノード名
    pub def topName(): String = "top"

    /// 下パイプの子ノード名
    pub def bottomName(): String = "bottom"

    /// コインの子ノード名
    pub def coinName(): String = "coin"

    /// スプライトの孫ノード名
    pub def spriteName(): String = "sprite"

    /// ペアの上パイプ path
    pub def topPath(pair: String): NodePath = pair :: topName() :: Nil

    /// ペアの下パイプ path
    pub def bottomPath(pair: String): NodePath = pair :: bottomName() :: Nil

    /// ペアのコイン path
    pub def coinPath(pair: String): NodePath = pair :: coinName() :: Nil

    /// ギャップ中心 Y 座標の最小値
    def gapYMin(): Float64 = 110.0

    /// ギャップ中心 Y 座標の最大値
    def gapYMax(): Float64 = 290.0

    /// ギャップ中心からパイプ中心までの距離（通常難易度: score >= 10）
    /// 縦ギャップ = 2 × (202 - 160) = 84px
    def normalSpriteOffset(): Float64 = 202.0

    /// ギャップ中心からパイプ中心までの距離（初心者向け: score = 0）
    /// 縦ギャップ = 2 × (250 - 160) = 180px
    def easySpriteOffset(): Float64 = 250.0

    /// パイプの衝突形状（矩形 52×320 = 参考実装 26×160 の 2 倍）
    def pipeCollisionShape(): CollisionShape2D =
        CollisionShape2D.RectShape2D({width = 52.0, height = 320.0})

    /// パイプペア間の水平距離
    def pipeSpacingX(): Float64 = 182.0

    /// 難易度が通常に到達するスコア閾値
    def difficultyMaxScore(): Int32 = 10

    /// スコアに応じた上下パイプ間のギャップ用オフセットを返す
    /// score 0 → 250（初心者向けの広いギャップ 180px）
    /// score 10 以上 → 202（通常難易度のギャップ 84px）
    /// score 1〜9 → 線形補間で徐々に狭くなる
    pub def gapSpriteOffset(score: Int32): Float64 =
        if (score >= difficultyMaxScore()) normalSpriteOffset()
        else {
            let t = Int32.toFloat64(score) / Int32.toFloat64(difficultyMaxScore());
            easySpriteOffset() + (normalSpriteOffset() - easySpriteOffset()) * t
        }

    /// 初期パイプペア数
    def initialPipeCount(): Int32 = 3

    /// 最初のパイプの X 座標（鳥の初期 X 144 + 画面幅 288 × 1.5）
    /// 鳥が操作に慣れる猶予を持たせるために画面 1.5 枚分先に配置
    def firstPipeX(): Float64 = 576.0

    /// パイプの半幅（画面外判定に使用）
    pub def pipeHalfWidth(): Float64 = 26.0

    /// トップパイプのテクスチャ名
    def topTexture(): String = "pipe_green_top"

    /// ボトムパイプのテクスチャ名
    def bottomTexture(): String = "pipe_green_bottom"

    /// パイプの衝突形状の半高（320 / 2）
    def pipeHalfHeight(): Float64 = 160.0

    // ========================================================================
    // シーン構築
    // ========================================================================

    /// パイプペア（top + bottom + coin）を 1 つの Marker2D 親ノード配下に追加する
    /// godot の pipe.tscn 構造に対応。親ごと自殺で 3 ノード一括削除できる。
    /// pair: 親ノード名（"pipe_${counter}"）
    /// x: ペアの X 座標（親 Marker2D の position）
    /// gapY: ギャップ中心の Y 座標
    /// offset: ギャップ中心からパイプ中心までの距離（難易度依存）
    def spawnPipePairWithOffset(pair: String, x: Float64, gapY: Float64,
                                 offset: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make({x = x, y = 0.0});
        let topBody = StaticBody2D.make({x = 0.0, y = gapY - offset}, pipeCollisionShape());
        let topSprite = Sprite2D.make(topTexture(), Vec2.zero(), {x = 2.0, y = 2.0});
        let bottomBody = StaticBody2D.make({x = 0.0, y = gapY + offset}, pipeCollisionShape());
        let bottomSprite = Sprite2D.make(bottomTexture(), Vec2.zero(), {x = 2.0, y = 2.0});
        let gapHeight = 2.0 * (offset - pipeHalfHeight());
        let coinShape = CollisionShape2D.RectShape2D({width = 4.0, height = gapHeight});
        let coin = Area2D.make({x = 0.0, y = gapY}, coinShape)
            |> Area2D.setMonitoring(false);
        scene
            |> Scene.addNode(pair, EngineNode.Marker2DWithState(parent, NodeTag.Pipe))
            |> Scene.addToGroup(pair :: Nil, pipeGroup())
            |> Scene.addChild(pair, topName(),
                EngineNode.StaticBody2DWithState(topBody, NodeTag.PipePart))
            |> Scene.addChildAt(topPath(pair), spriteName(),
                EngineNode.Sprite2DWithState(topSprite, NodeTag.NoTag))
            |> Scene.addChild(pair, bottomName(),
                EngineNode.StaticBody2DWithState(bottomBody, NodeTag.PipePart))
            |> Scene.addChildAt(bottomPath(pair), spriteName(),
                EngineNode.Sprite2DWithState(bottomSprite, NodeTag.NoTag))
            |> Scene.addChild(pair, coinName(),
                EngineNode.Area2DWithState(coin, NodeTag.Coin))

    /// パイプペアを指定位置に決定的に追加する（テスト用公開）
    /// 通常難易度のオフセット（normalSpriteOffset）を使用する
    pub def spawnPipePairAt(counter: Int32, x: Float64, gapY: Float64,
                            scene: Scene[NodeTag]): Scene[NodeTag] =
        spawnPipePairWithOffset(pairName(counter), x, gapY, normalSpriteOffset(), scene)

    /// パイプペアをランダムな gapY で追加する
    /// スコアに応じた縦ギャップで配置する
    def spawnPipePair(counter: Int32, x: Float64, score: Int32,
                      scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let gapY = gapYMin() + (gapYMax() - gapYMin()) * Math.Random.randomFloat64();
        spawnPipePairWithOffset(pairName(counter), x, gapY, gapSpriteOffset(score), scene)

    /// 初期パイプ（3 ペア）を配置する
    /// score=0 の初心者向けギャップで配置する
    /// 画面外になったペアの再スポーンは NodeRemovedHandler が担う
    pub def addPipes(scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let spacing = pipeSpacingX();
        List.range(0, initialPipeCount())
            |> List.foldLeft((acc, i) ->
                spawnPipePair(i, firstPipeX() + Int32.toFloat64(i) * spacing, 0, acc),
                scene)

    /// パイプグループ内の最右端 X 座標を返す（リサイクル位置決定に使用）
    pub def maxPipeX(scene: Scene[NodeTag]): Float64 =
        Scene.getNodesInGroup(pipeGroup(), scene)
            |> List.map(p -> Scene.globalPositionAt(p, scene)#x)
            |> List.maximum
            |> Option.getWithDefault(0.0)

    /// リサイクル時に新ペアを spawn する
    /// 新ペアの X は現在の最右端 + pipeSpacingX。ID は X 座標から導出
    pub def spawnRecycledPair(score: Int32, scene: Scene[NodeTag]): Scene[NodeTag] \ Math.Random =
        let nextX = maxPipeX(scene) + pipeSpacingX();
        let id = Float64.tryToInt32(nextX) |> Option.getWithDefault(0);
        spawnPipePair(id, nextX, score, scene)

    // ========================================================================
    // ロジック（process）
    // ========================================================================

    /// パイプペア親が画面左端を完全に通過したらサブツリーごと除去する
    /// 親 Marker2D を removeAt するため top/bottom/coin が一度に消える
    /// 除去通知は NodeRemovedHandler が Recycle 効果に変換し、上位ハンドラが
    /// 新ペアを最右端に再スポーンする
    pub def process(node: EngineNode[NodeTag], path: NodePath,
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ Recycle =
        match node {
            case EngineNode.Marker2DWithState(_, NodeTag.Pipe) =>
                let pos = Scene.globalPositionAt(path, scene);
                if (pos#x + pipeHalfWidth() < Game.getViewportLeftX(scene))
                    (node, Scene.removeAtAndNotify(path, scene))
                else
                    (node, scene)
            case _ => (node, scene)
        }
}
