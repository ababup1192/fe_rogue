/// 2D 空間上のノード（Godot Node2D 準拠）
/// see: https://docs.godotengine.org/en/stable/classes/class_node2d.html
pub trait Node2D[a] with CanvasItem[a] {

    // ── Properties ──

    /// 位置を取得する
    pub def getPosition(node: a): Vec2.Vec2

    /// 位置を設定する
    pub def setPosition(position: Vec2.Vec2, node: a): a

    /// 回転（ラジアン）を取得する
    ///
    ///   rotation = 0       rotation = PI/4
    ///       |                  /
    ///       |                /
    ///       +---            +
    ///
    pub def getRotation(node: a): Float64

    /// 回転（ラジアン）を設定する
    pub def setRotation(rotation: Float64, node: a): a

    /// スケールを取得する
    ///
    ///   scale(1,1)    scale(2,1)    scale(1,2)
    ///   +--+          +------+      +--+
    ///   |  |          |      |      |  |
    ///   +--+          +------+      |  |
    ///                               |  |
    ///                               +--+
    ///
    pub def getScale(node: a): Vec2.Vec2

    /// スケールを設定する
    pub def setScale(scale: Vec2.Vec2, node: a): a

    /// せん断変形（ラジアン）を取得する
    /// ノードを平行四辺形のように歪ませる
    ///
    ///   skew = 0          skew > 0
    ///   +------+          /------/
    ///   |      |         /      /
    ///   |      |        /      /
    ///   +------+       /------/
    ///
    pub def getSkew(node: a): Float64

    /// せん断変形（ラジアン）を設定する
    pub def setSkew(skew: Float64, node: a): a

    // ── Methods ──

    /// ローカル座標系でオフセット分だけ移動する
    ///
    ///          offset
    ///       +---->
    ///   [A]         [A']
    ///
    pub def translate(offset: Vec2.Vec2, node: a): a =
        Node2D.getPosition(node)
            |> Vec2.add(offset)
            |> flip -> Node2D.setPosition(flip, node)

    /// 現在の回転に加算する（ラジアン）
    pub def rotate(radians: Float64, node: a): a =
        (Node2D.getRotation(node) + radians)
            |> flip -> Node2D.setRotation(flip, node)

    /// 現在のスケールにベクトルを乗算する
    ///
    ///   scale(1,1)  -- applyScale(2,2) -->  scale(2,2)
    ///   +--+                                +------+
    ///   |  |                                |      |
    ///   +--+                                |      |
    ///                                       +------+
    ///
    pub def applyScale(ratio: Vec2.Vec2, node: a): a =
        let scale = Node2D.getScale(node);
        Node2D.setScale({x = scale#x * ratio#x, y = scale#y * ratio#y}, node)

    /// 指定した点への角度（ラジアン）を返す
    ///
    ///              * point
    ///            /
    ///          / angle
    ///   node *-------> +X
    ///
    pub def getAngleTo(point: Vec2.Vec2, node: a): Float64 =
        let position = Node2D.getPosition(node);
        Vec2.sub(point, position) |> Vec2.angle

    /// 指定した点の方を向くように回転する
    ///
    ///   before:            after:
    ///       * point            * point
    ///                        /
    ///   node *--->      node *
    ///
    pub def lookAt(point: Vec2.Vec2, node: a): a =
        Node2D.getAngleTo(point, node)
            |> flip -> Node2D.setRotation(flip, node)
}
