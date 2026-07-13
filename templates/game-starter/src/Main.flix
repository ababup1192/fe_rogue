// エントリーポイント。ここでゲームを組み立てて起動する。
//
// App に3点を繋ぐ: 出発点の World（World.initial）・毎フレームの処理（Controls.step）・
// 絵への写し（View.frame）。窓・時計・キー・描画といった外の世界の処理は App が引き受けるので、
// ゲーム側は純粋な関数を渡すだけでよい。外の世界に触れる処理（effect）は隠さず with で並べる。
//
// このゲームは「四角を矢印キーで動かすだけ」。自分のゲームにするには、まず World / Controls / View を
// いじる。音や設定リロードが要るなら App.withAudio / App.reloadOn を足す（breakout 例が参考になる）。

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            App.make(World.initial())
                |> App.addSystem(Controls.step)
                |> App.withView(View.frame)
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
    }
