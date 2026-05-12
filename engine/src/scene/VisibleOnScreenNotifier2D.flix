/// 画面外検出ノード（Godot VisibleOnScreenNotifier2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_visibleonscreennotifier2d.html
///
/// ノードの矩形領域が画面内に表示されているかを判定する。
/// Godot の screen_entered / screen_exited シグナルに相当する判定ロジックを提供する。
///
///   画面 (0,0)
///   +-------------------+
///   |                   |
///   |   +----+ rect     |
///   |   |node|          |
///   |   +----+          |
///   +-------------------+ (screenWidth, screenHeight)
///
pub enum VisibleOnScreenNotifier2D {
    // 通知領域（ノード中心からの相対矩形）
    case VisibleOnScreenNotifier2D({rect = Rect2.Rect2})
}

mod VisibleOnScreenNotifier2D {

    /// 中心基準の通知領域を生成する。
    /// size は領域の幅と高さ。矩形の position は (-size.x/2, -size.y/2) となる。
    pub def make(size: Vec2.Vec2): VisibleOnScreenNotifier2D =
        VisibleOnScreenNotifier2D.VisibleOnScreenNotifier2D({
            rect = {
                position = {x = -1.0 * size#x / 2.0, y = -1.0 * size#y / 2.0},
                size = size
            }
        })

    /// Rect2 を直接指定して通知領域を生成する。
    pub def makeWithRect(rect: Rect2.Rect2): VisibleOnScreenNotifier2D =
        VisibleOnScreenNotifier2D.VisibleOnScreenNotifier2D({ rect = rect })

    /// 通知領域の Rect2 を取得する
    pub def getRect(notifier: VisibleOnScreenNotifier2D): Rect2.Rect2 =
        let VisibleOnScreenNotifier2D.VisibleOnScreenNotifier2D(r) = notifier;
        r#rect

    /// ノードが画面内に表示されているか判定する。
    /// nodePosition はノードのグローバル座標。
    /// 通知領域の AABB と画面矩形の AABB が重なっていれば true を返す。
    ///
    ///   画面矩形: (0, 0) - (screenWidth, screenHeight)
    ///   通知矩形: nodePosition + rect.position から rect.size 分の領域
    ///
    pub def isOnScreen(nodePosition: Vec2.Vec2, notifier: VisibleOnScreenNotifier2D,
                       screenWidth: {screenWidth = Int32},
                       screenHeight: {screenHeight = Int32}): Bool =
        let VisibleOnScreenNotifier2D.VisibleOnScreenNotifier2D(r) = notifier;
        let rectPos = Vec2.add(nodePosition, r#rect#position);
        let rectEnd = Vec2.add(rectPos, r#rect#size);
        let sw = Int32.toFloat64(screenWidth#screenWidth);
        let sh = Int32.toFloat64(screenHeight#screenHeight);
        // AABB 重なり判定: 画面矩形 (0,0)-(w,h) と通知矩形
        rectEnd#x > 0.0 and
        rectPos#x < sw and
        rectEnd#y > 0.0 and
        rectPos#y < sh
}
