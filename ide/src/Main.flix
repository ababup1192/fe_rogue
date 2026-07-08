// ide/src/Main.flix — 最小スタブ。
//
// エンジンから Scene ツリー層（Scene / SceneLoader / EngineNode / 各種ノード型）を撤去した際に、
// それらに依存していた旧 IDE 実装は撤去した。IDE は描画語彙ベースで作り直す前提のため、
// ここではコンパイルを通すためだけの空エントリを置く。
def main(): Unit \ IO =
    println("flix_game_engine IDE: rebuild 前提の最小スタブです（旧 Scene ツリー実装は撤去済み）。")
