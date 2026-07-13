// World — ゲームの状態そのもの。ここには「いま何がどうなっているか」の値だけを置く。
// 絵や入力や外の世界（窓・時計）はここに持ち込まない。それらは View と Controls と App の担当。

mod World {

    /// プレイヤーの中心座標だけを持つ最小の状態。
    /// x, y は design 座標（project.json の designWidth/Height と同じ 320×240 の中の位置）。
    pub type alias World = { x = Float64, y = Float64 }

    /// このフレームの入力（横・縦の軸値。-1 / 0 / +1）。Controls がキーからこの形に写す。
    pub type alias Input = { x = Float64, y = Float64 }

    /// プレイヤーの1辺の長さ（正方形）。
    pub def size(): Float64 = 16.0

    /// 1秒あたりの移動速度（design 座標 px/秒）。
    pub def speed(): Float64 = 120.0

    /// ゲーム開始時の状態。画面の真ん中に置く（design サイズは project.json の designWidth/Height 由来）。
    pub def initial(design: Vec2.Vec2): World = { x = design#x / 2.0, y = design#y / 2.0 }

    /// 入力と経過時間から次の状態を作る（純粋）。
    /// 端で止めないのは、まず「動く」ことだけを見せたいから。壁で止めたくなったらここに clamp を足す。
    pub def step(input: Input, dt: Float64, world: World): World =
        { x = world#x + input#x * speed() * dt,
          y = world#y + input#y * speed() * dt }
}
