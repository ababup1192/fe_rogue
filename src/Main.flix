// コミュニティビルド用のスモークエントリポイント。
// ルート src/ はエンジン全パッケージの symlink 集で、`flix build` の型検査が本体。
// main はビルド成立の確認としてエンジンの純粋関数を1つ叩くだけ。
def main(): Unit \ IO =
    let v = Vec2.add(Vec2.zero(), Vec2.one());
    println(Vec2.length(v))
