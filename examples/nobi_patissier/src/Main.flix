// 起動: いまは絵作りフェーズの足場だけ（空の World で起動し Escape で終了）。
// ゲーム本体は絵の承認（gallery/index.html）が全部 OK になってから組む。

def main(): Unit \ IO =
    App.make({ stub = 0 })
        |> App.launch
