/// ノード削除イベントへの応答トレイト（godot tree_exited シグナル相当）
///
/// `Scene.removeAtAndNotify` で削除されたノードに対し、削除直前の状態と
/// 削除後の Scene を渡してハンドラを呼ぶ。spawner パターン（自殺＋再生成）の
/// 実装に使う。
///
/// 関連エフェクト Aef により、インスタンスごとに必要なエフェクトを宣言できる。
/// 例: ランダム位置で再生成する場合は `type Aef = { Math.Random }`。

pub trait NodeRemovedHandler[s] {

    /// 削除応答で発生するエフェクト
    type Aef: Eff

    /// ノードが Scene から削除されたとき呼ばれる。
    /// path: 削除されたノードのパス
    /// state: 削除直前のゲーム状態
    /// scene: 削除後のシーン
    pub def onNodeRemoved(_path: NodePath, _state: s, scene: Scene[s]):
            Scene[s] \ NodeRemovedHandler.Aef[s] =
        checked_ecast(scene)
}
