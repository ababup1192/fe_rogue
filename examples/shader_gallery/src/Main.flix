// エントリーポイント。
//
// マウスのスライダーで池シェーダーを弄るエディタ。左上の大きな池タイルは Params から
// 毎フレーム組み立て、スライダーを動かすと即変わる。右上のマグマ2枚は JSON から一度
// 読むだけの静的な絵。camera は使わず design 座標を直に描く。

def pathFlow(): String = "assets/magma_bright_flow.shader.json"
def pathMetal(): String = "assets/magma_molten_metal.shader.json"

/// JSON が壊れている/未生成のときの保険（デモ面）。
def fallback(): ShaderDoc.Spec = ShaderDoc.demoSurface()

def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            // マグマ2枚を読む（壊れていても demo に倒れる）。
            let flow = ShaderJson.load(pathFlow()) |> Result.getWithDefault(fallback());
            let metal = ShaderJson.load(pathMetal()) |> Result.getWithDefault(fallback());
            // 前回スライダーで決めた値を読む（無ければ初期値）。水と岸は別ファイル。
            let settings = Store.load() |> Option.getWithDefault(World.initialSettings());
            let shore = Store.loadShore() |> Option.getWithDefault(World.initialShore());
            App.make(World.initial(settings, shore, flow, metal))
                |> App.addSystem((f, w) -> checked_ecast(Controls.step(f, w)))
                |> App.withView((ctx, w) -> checked_ecast(View.frame(ctx, w)))
                |> App.withDebug(App.debugFromEnv())
                |> App.launch
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
    }
