/// 物理ステップ — Node.physicsProcess + RigidBody2D の重力・ダンピング・速度積分
///
/// Godot の physics_process に相当する物理更新。
/// 静的衝突解決（resolveStaticCollisions）は別関数 — GameEngine.handleCollisions の
/// 内部で Area2D 重なり検出の後に呼ばれる。順序を逆にすると、RigidBody2D が
/// StaticBody2D に接触した瞬間に Area2D が「ピッタリ境界」になり、
/// 重なり判定が外れて areaEntered が発火しないため。
///
/// 使い方:
///   PhysicsStep.step(delta, paused, gravity, scene)
///
/// 処理順序:
///   1. Node.physicsProcess（全ノード）— 力の適用・速度変更などカスタム物理ロジック
///   2. 重力加速: linearVelocity += gravity * gravityScale * delta
///   3. ダンピング: linearVelocity /= (1 + linearDamp * delta)
///   4. 速度積分: position += linearVelocity * delta, rotation += angularVelocity * delta
///
pub mod PhysicsStep {

    /// デフォルト重力（Godot 準拠: 980 pixels/sec² 下向き）
    pub def defaultGravity(): Vec2.Vec2 = {x = 0.0, y = 980.0}

    /// 物理ステップ: physicsProcess → 重力適用 → ダンピング → 速度積分
    /// 全ノードの physicsProcess を呼んだ後、RigidBody2D に物理更新を適用する。
    pub def step(delta: Duration.Duration, paused: Bool, gravity: Vec2.Vec2, scene: Scene[s]): Scene[s] \ Node.Aef[s] with Node[s] =
        let afterPhysicsProcess = Scene.physicsProcessAll(delta, paused, scene);
        integrate(delta, gravity, afterPhysicsProcess)

    /// RigidBody2D への重力・ダンピング・速度積分のみ行う（physicsProcess なし）
    pub def integrate(delta: Duration.Duration, gravity: Vec2.Vec2, scene: Scene[s]): Scene[s] =
        let paths = Scene.preorderPaths(scene);
        List.foldLeft((sc, path) ->
            Scene.mapEngineNode(path, engineNode ->
                EngineNode.mapRigidBody2D(body ->
                    integrateBody(delta, gravity, body),
                    engineNode),
                sc),
            scene,
            paths)

    /// 単体の RigidBody2D に重力・ダンピング・速度積分を適用する
    def integrateBody(delta: Duration.Duration, gravity: Vec2.Vec2, body: RigidBody2D): RigidBody2D =
        let RigidBody2D.RigidBody2D(r) = body;
        let dtSec = Duration.toSeconds(delta);
        // 1. 重力加速
        let gravAccel = Vec2.mul(gravity, r#gravityScale * dtSec);
        let velAfterGravity = Vec2.add(r#linearVelocity, gravAccel);
        // 2. ダンピング
        let linearDampFactor = 1.0 + r#linearDamp * dtSec;
        let velAfterDamp = Vec2.div(velAfterGravity, linearDampFactor);
        let angularDampFactor = 1.0 + r#angularDamp * dtSec;
        let angVelAfterDamp = r#angularVelocity / angularDampFactor;
        // 3. 速度積分
        let newPosition = Vec2.add(r#position, Vec2.mul(velAfterDamp, dtSec));
        let newRotation = r#rotation + angVelAfterDamp * dtSec;
        RigidBody2D.RigidBody2D({
            linearVelocity = velAfterDamp,
            angularVelocity = angVelAfterDamp,
            position = newPosition,
            rotation = newRotation
            | r
        })

    /// RigidBody2D が StaticBody2D（physicsCollisionEnabled=true）と重なっている場合、
    /// 押し出して分離する。法線方向の速度はゼロにする（重力蓄積を防ぐ）。
    /// Godot の RigidBody2D ↔ StaticBody2D 自動衝突解決相当。
    /// RigidBody2D 側の collisionExceptions に登録された path のペアは skip
    /// （Godot add_collision_exception_with 相当）。
    /// シーン内のすべての静的衝突体（StaticBody2D + TileMapLayer の壁セル）を集める。
    /// resolveStaticCollisions が物理応答に、RayCast2D が線分クエリに、それぞれ共有して使う。
    pub def collectStaticColliders(scene: Scene[s]):
            List[(NodePath, Vec2.Vec2, CollisionShape2D)] =
        let paths = Scene.preorderPaths(scene);
        let staticBodies: List[(NodePath, Vec2.Vec2, CollisionShape2D)] =
            List.filterMap(p -> match Scene.getEngineNode(p, scene) {
                case Some(EngineNode.StaticBody2DWithState(body, _)) =>
                    if (StaticBody2D.isPhysicsCollisionEnabled(body))
                        match CollisionObject2D.getCollisionShape(body) {
                            case Some(shape) =>
                                Some((p, Scene.globalPositionAt(p, scene), shape))
                            case None => None
                        }
                    else None
                case _ => None
            }, paths);
        let tileWalls: List[(NodePath, Vec2.Vec2, CollisionShape2D)] =
            List.flatMap(p -> match Scene.getEngineNode(p, scene) {
                case Some(EngineNode.TileMapLayerWithState(tileMap, _)) =>
                    TileMapLayer.expandWallShapes(Scene.globalPositionAt(p, scene), tileMap)
                    |> List.map(match (center, shape) -> (p, center, shape))
                case _ => Nil
            }, paths);
        List.append(staticBodies, tileWalls)

    pub def resolveStaticCollisions(scene: Scene[s]): Scene[s] =
        let paths = Scene.preorderPaths(scene);
        let allStatics = collectStaticColliders(scene);
        // 各 RigidBody2D に対して全 static body との分離を順次適用
        List.foldLeft((sc, path) ->
            match Scene.getEngineNode(path, sc) {
                case Some(EngineNode.RigidBody2DWithState(body, _)) =>
                    match CollisionObject2D.getCollisionShape(body) {
                        case Some(shape) =>
                            let pos = Scene.globalPositionAt(path, sc);
                            resolveOneRigid(path, pos, shape, body, allStatics, sc)
                        case None => sc
                    }
                case _ => sc
            },
            scene,
            paths)

    /// 1 つの RigidBody2D に対し、全静的ボディとの MTV を順に適用する。
    /// 各分離ごとに位置を更新し、法線方向の速度成分をゼロにする。
    /// collisionExceptions に登録された静的ボディとの分離は skip する。
    def resolveOneRigid(path: NodePath, initPos: Vec2.Vec2, shape: CollisionShape2D,
                         initBody: RigidBody2D, statics: List[(NodePath, Vec2.Vec2, CollisionShape2D)],
                         scene: Scene[s]): Scene[s] =
        let (finalPos, finalBody) = List.foldLeft(
            (acc, sb) -> {
                let (pos, body) = acc;
                let (sPath, sPos, sShape) = sb;
                if (RigidBody2D.hasCollisionException(sPath, body))
                    (pos, body)
                else
                    match CollisionShape2D.resolveOverlap(pos, shape, sPos, sShape) {
                        case None => (pos, body)
                        case Some(mtv) =>
                            let newPos = Vec2.add(pos, mtv);
                            let vel = RigidBody2D.getLinearVelocity(body);
                            let mtvLen = Vec2.length(mtv);
                            let newVel = if (mtvLen < 0.001) vel else {
                                let normal = Vec2.div(mtv, mtvLen);
                                let velAlongNormal = Vec2.dot(vel, normal);
                                // 法線と逆向きの速度成分のみ除去（重力蓄積防止）
                                if (velAlongNormal < 0.0)
                                    Vec2.sub(vel, Vec2.mul(normal, velAlongNormal))
                                else vel
                            };
                            (newPos, RigidBody2D.setLinearVelocity(newVel, body))
                    }
            },
            (initPos, initBody),
            statics);
        scene
            |> Scene.mapEngineNode(path, en -> EngineNode.mapRigidBody2D(_ -> finalBody, en))
            |> Scene.setGlobalPositionAt(path, finalPos)
}
