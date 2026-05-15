/// メニュー項目の選択イベント駆動（Godot ItemList.item_selected / index_pressed 相当）。
///
/// `ItemList` は内部で前フレームのキー状態と pending フラグを持っており、
/// `handleMenus` を毎フレーム呼ぶことで:
///   1. focused = true な ItemList のキー入力差分を検出
///   2. Up / Down で `moveCursorUp` / `moveCursorDown` 自動適用
///   3. Enter 押下瞬間で `MenuHandler.onItemConfirmed` を発火
///   4. Escape 押下瞬間で `MenuHandler.onItemCancelled` を発火
/// の流れを engine 側で完結させる。
///
/// 使い方:
///   1. `MenuHandler[s]` を実装し `onItemConfirmed` で確定時の処理を書く
///   2. `gameLoop` 内で `GameEngine.handleMenus(scene)` を呼ぶ（パイプラインに組み込み済み）
///
/// 入力キー割り当て（初期版固定）:
///   - Up    = カーソル上移動
///   - Down  = カーソル下移動
///   - Enter = 確定（onItemConfirmed）
///   - Escape = キャンセル（onItemCancelled、サブメニューから親に戻る用途）
pub mod MenuEvent {

    /// メニュー項目の選択／確定／キャンセルに応答する trait。
    /// 関連エフェクト Aef でインスタンスごとに必要な副作用を宣言する。
    pub trait MenuHandler[s] {

        /// メニュー応答で発生するエフェクト
        type Aef: Eff

        /// 項目が確定された（Enter 押下）瞬間に呼ばれる。
        /// menuPath: ItemList ノードのパス
        /// idx     : 確定された項目の index
        /// entry   : 確定された項目データ
        /// state   : ItemList ノードのゲーム状態
        /// scene   : 現在のシーン
        pub def onItemConfirmed(_menuPath: NodePath, _idx: Int32, _entry: ItemEntry,
                                _state: s, scene: Scene[s]): Scene[s] \ MenuHandler.Aef[s] =
            checked_ecast(scene)

        /// キャンセル（Escape 押下）瞬間に呼ばれる。サブメニューを閉じる等。
        pub def onItemCancelled(_menuPath: NodePath, _state: s,
                                scene: Scene[s]): Scene[s] \ MenuHandler.Aef[s] =
            checked_ecast(scene)
    }

    /// 全 ItemList の前フレーム差分検出とカーソル更新を一括で行う。
    /// 入力キー: Up / Down / Enter / Escape（Z/Space/X は使わない、初期版は固定）。
    pub def updateMenus(scene: Scene[s]): Scene[s] \ GameEngine.Game =
        let upDown      = GameEngine.Game.isKeyPressed(GameEngine.Key.Up);
        let downDown    = GameEngine.Game.isKeyPressed(GameEngine.Key.Down);
        let confirmDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Enter);
        let cancelDown  = GameEngine.Game.isKeyPressed(GameEngine.Key.Escape);
        let paths = Scene.preorderPaths(scene);
        List.foldLeft((sc, path) ->
            match Scene.getEngineNode(path, sc) {
                case Some(EngineNode.ItemListWithState(list, _)) =>
                    if (not CanvasItem.isVisible(list)) sc
                    else {
                        let updated = ItemList.updateInputState(upDown, downDown,
                                                                confirmDown, cancelDown, list);
                        Scene.mapEngineNode(path, EngineNode.mapItemList(_ -> updated), sc)
                    }
                case _ => sc
            },
            scene,
            paths)

    /// pendingConfirm / pendingCancel が立っている ItemList の (path, kind) 列を収集する。
    /// kind: true = confirm, false = cancel
    pub def detectPendingMenus(scene: Scene[s]): List[(NodePath, Bool)] =
        let paths = Scene.preorderPaths(scene);
        List.flatMap(path ->
            match Scene.getEngineNode(path, scene) {
                case Some(EngineNode.ItemListWithState(list, _)) =>
                    let conf = if (ItemList.isPendingConfirm(list)) (path, true) :: Nil else Nil;
                    let canc = if (ItemList.isPendingCancel(list))  (path, false) :: Nil else Nil;
                    List.append(conf, canc)
                case _ => Nil
            }, paths)

    /// pending フラグをクリアする
    def clearAllPending(paths: List[(NodePath, Bool)], scene: Scene[s]): Scene[s] =
        List.foldLeft((sc, pair) ->
            let (path, _) = pair;
            match Scene.getEngineNode(path, sc) {
                case Some(EngineNode.ItemListWithState(_, _)) =>
                    Scene.mapEngineNode(path, EngineNode.mapItemList(ItemList.clearPending), sc)
                case _ => sc
            },
            scene,
            paths)

    /// メニューイベントを処理する:
    ///   1. updateMenus でキー入力差分を反映
    ///   2. detectPendingMenus で pending を収集
    ///   3. onItemConfirmed / onItemCancelled を発火
    ///   4. pending フラグをクリア
    pub def handleMenus(scene: Scene[s]): Scene[s] \ {GameEngine.Game, MenuHandler.Aef[s]}
            with MenuHandler[s] =
        let afterUpdate = updateMenus(scene);
        let pending = detectPendingMenus(afterUpdate);
        let afterHandlers = List.foldLeft((sc, pair) ->
            let (path, isConfirm) = pair;
            match Scene.getEngineNode(path, sc) {
                case Some(EngineNode.ItemListWithState(list, state)) =>
                    if (isConfirm) {
                        let idx = ItemList.getSelectedIndex(list);
                        match ItemList.getSelected(list) {
                            case Some(entry) => MenuHandler.onItemConfirmed(path, idx, entry, state, sc)
                            case None        => sc
                        }
                    } else
                        MenuHandler.onItemCancelled(path, state, sc)
                case _ => sc
            },
            afterUpdate,
            pending);
        clearAllPending(pending, afterHandlers)
}
