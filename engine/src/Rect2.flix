/// Rect2 — 2D 矩形（Godot Rect2 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_rect2.html
///
/// position は左上座標、size は幅と高さを表す。
///
///   position
///     +----------+
///     |          | size.y
///     +----------+
///       size.x

mod Rect2 {

    /// 矩形: position = 左上座標、size = 幅と高さ
    pub type alias Rect2 = {position = Vec2.Vec2, size = Vec2.Vec2}

    // ========================================================================
    // コンストラクタ
    // ========================================================================

    /// 原点 (0, 0) から指定サイズの矩形を作成する
    pub def fromSize(size: Vec2.Vec2): Rect2 =
        {position = Vec2.zero(), size = size}

    // ========================================================================
    // プロパティ
    // ========================================================================

    /// 矩形の終端（右下）座標を返す
    pub def end(rect: Rect2): Vec2.Vec2 =
        Vec2.add(rect#position, rect#size)

    /// 矩形の面積を返す
    pub def area(rect: Rect2): Float64 =
        rect#size#x * rect#size#y

    /// 矩形の中心座標を返す
    pub def center(rect: Rect2): Vec2.Vec2 =
        Vec2.add(rect#position, Vec2.div(rect#size, 2.0))

    // ========================================================================
    // 判定
    // ========================================================================

    /// 指定した点が矩形に含まれるか判定する
    pub def hasPoint(point: Vec2.Vec2, rect: Rect2): Bool =
        let e = end(rect);
        point#x >= rect#position#x and point#x <= e#x and
        point#y >= rect#position#y and point#y <= e#y
}
