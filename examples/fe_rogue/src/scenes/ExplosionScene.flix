/// ExplosionScene — 一発再生の爆発エフェクト（火炎瓶 / 爆発瓶 / 魔法攻撃の着弾）
///
/// `DamagePopupScene` と同じ「World 配下に永続の親 Marker2D を 1 つ持ち、emit で
/// 子スプライトを連番でぶら下げ、process で寿命を減らしつつ自動消去する」流儀。
/// 子は `explosion` テクスチャ（assets/effect/explosion.png）の **1 行目** を
/// 寿命にわたって frame 0 → frameCount-1 まで送ることでコマ送りアニメする。
///
/// ノード構造:
///   Explosions (Marker2D, NodeTag.ExplosionsRoot)   永続
///     └─ Explosion_<seq> (Sprite2D, NodeTag.Explosion)  寿命は World.explosionFx が持つ
///
/// P5-b: 寿命・採番の権威は World の `explosionFx` store（`Cmd.SpawnExplosionFx` で spawn・
/// `stepWorld` が tick して期限切れを drop）。子 Sprite2D は位置/scale を持つ描画 view で、
/// gameLoop が毎フレーム `syncView` で store から frame コマ送りと除去を派生する。
mod ExplosionScene {

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
            EngineNode.Marker2DWithState(parent, NodeTag.ExplosionsRoot),  // P5-b: 採番は World へ
            scene)

    /// 指定セル中心に通常サイズの爆発を 1 つ発生させる。親未登録（add 前）なら no-op。
    pub def emitAtCell(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {World.Command, World.WorldQuery} =
        emit(MapSnapshot.cellCenter(cell), scaleFactor(), scene)

    /// 指定セル中心に大きい爆発を 1 つ発生させる（爆発瓶用。3×3 範囲を覆う見た目）。
    pub def emitBigAtCell(cell: {x = Int32, y = Int32}, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {World.Command, World.WorldQuery} =
        emit(MapSnapshot.cellCenter(cell), bigScaleFactor(), scene)

    /// 指定ワールド座標に通常サイズの爆発を 1 つ発生させる（魔法攻撃の着弾用）。
    pub def emitNormal(worldPos: Vec2.Vec2, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {World.Command, World.WorldQuery} =
        emit(worldPos, scaleFactor(), scene)

    /// 指定ワールド座標に `scale` 倍の爆発を 1 つ発生させる。親未登録なら no-op。
    /// P5-b: 寿命は `Cmd.SpawnExplosionFx` で World の explosionFx store へ（採番は applyCmd＝
    /// WorldQuery で次 seq を先読みして子ノード名を合わせる。DamagePopupScene.emitText と同型）。
    pub def emit(worldPos: Vec2.Vec2, scale: Float64, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {World.Command, World.WorldQuery} =
        match Scene.getEngineNode(rootPath(), scene) {
            case Some(EngineNode.Marker2DWithState(_, NodeTag.ExplosionsRoot)) =>
                let seq = World.explosionFxNextSeqOf(World.WorldQuery.get());
                World.Command.emit(World.Cmd.SpawnExplosionFx(
                    {total = Duration.toSeconds(lifetime())}));
                let sprite = Sprite2D.make(texture(), worldPos,
                                ({x = scale, y = scale}: Vec2.Vec2))
                                |> Sprite2D.setHframes(hframes())
                                |> Sprite2D.setVframes(vframes())
                                |> Sprite2D.setFrame(0)
                                |> CanvasItem.setZIndex(zIndex());
                scene
                    |> Scene.addChildAt(rootPath(), "Explosion_${seq}",
                        EngineNode.Sprite2DWithState(sprite, NodeTag.Explosion))
            case _ => scene
        }

    /// P5-b: gameLoop（stepWorld の後）から呼ばれる view 派生。World の explosionFx store を読み、
    ///   1) 生存 seq の子 Sprite2D を経過比率で 1 行目のコマ（frame 0..13）に送る
    ///   2) store に無い（期限切れで drop 済み）子を `Scene.removeAt` で除去
    /// する。寿命の tick はここでは行わない（stepWorld が権威）。親未登録なら no-op。
    pub def syncView(world: World, scene: Scene[NodeTag]): Scene[NodeTag] =
        let fx = World.explosionFxOf(world);
        let updated = Map.foldLeftWithKey((acc, seq, d) -> {
            let childPath = List.append(rootPath(), "Explosion_${seq}" :: Nil);
            let ratio = (d#total - d#remaining) / d#total;
            let raw = Float64.truncateToInt32(
                        Float64.floor(ratio * Int32.toFloat64(frameCount())));
            let frame = Int32.max(0, Int32.min(frameCount() - 1, raw));
            Sprite2D.mapAt(childPath, Sprite2D.setFrame(frame), acc)
        }, scene, fx);
        let liveNames = Map.foldLeftWithKey((s, seq, _) -> Set.insert("Explosion_${seq}", s), Set.empty(), fx);
        Scene.getChildrenAt(rootPath(), updated)
            |> List.foldLeft((acc, name) ->
                if (Set.memberOf(name, liveNames)) acc
                else Scene.removeAt(List.append(rootPath(), name :: Nil), acc), updated)
}
