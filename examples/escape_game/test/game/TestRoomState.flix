/// `Game.RoomState` の単体テスト。
///
/// 「現在の部屋 + ホットスポット状態テーブル」の Ref に対して `enter` /
/// `setLocked` / `setVisible` を効果越しに発火し、派生クエリ
/// (`currentRoom` / `isLocked` / `isVisible`) が一貫して動くことを確認する。
mod TestRoomState {
    use Game.RoomState.HotspotState

    /// テスト用 handler 装着ヘルパ。本番 (`Game.start`) と同じ
    /// `Game.RoomState.withState` を使い、挙動の乖離を防ぐ。
    def withRoomState(thunk: Unit -> a \ ef):
                       a \ (ef - Game.RoomState.Access) =
        region rc {
            Game.RoomState.withState(rc)(thunk)
        }

    /// 「初期ロック false / 初期 visible true」の HotspotState を作る短縮ヘルパ。
    /// 各テストでテーブルを組むときの定型を 1 行に。
    def hsUnlocked(): HotspotState =
        ({locked = false, visible = true}: HotspotState)

    /// 「初期ロック true / 初期 visible true」の HotspotState を作る短縮ヘルパ。
    def hsLocked(): HotspotState =
        ({locked = true, visible = true}: HotspotState)

    // ========================================================================
    // enter: 部屋切替で id とテーブルがまるごと差し替わる
    // ========================================================================

    /// `enter("demo_room", {chest, door})` の直後に currentRoom と各ホットスポットの
    /// 状態が初期値どおりに見える（chest=unlocked, door=locked）ことを 1 度に確認する。
    @Test
    def testEnterEstablishesRoomAndInitialStates(): Unit \ Assert =
        let result = withRoomState(() -> {
            let initial = Map#{
                "drawer" => hsUnlocked(),
                "door"  => hsLocked()
            };
            Game.RoomState.Access.enter("demo_room", initial);
            (Game.RoomState.currentRoom(),
             Game.RoomState.isLocked("drawer"),
             Game.RoomState.isLocked("door"))
        });
        Assert.assertEq(expected = ("demo_room", false, true), result)

    /// 別の部屋に enter しなおすと、前の部屋のホットスポット状態は完全に消える。
    /// `is_locked("drawer")` が前の部屋では unlocked でも、新部屋に drawer が無ければ
    /// 「未登録 = false」のデフォルトに落ちる。
    @Test
    def testEnterReplacesHotspotTable(): Unit \ Assert =
        let result = withRoomState(() -> {
            Game.RoomState.Access.enter("demo_room", Map#{"drawer" => hsUnlocked()});
            Game.RoomState.Access.enter("demo_room2", Map#{"sign" => hsUnlocked()});
            (Game.RoomState.currentRoom(),
             Game.RoomState.isVisible("drawer"),
             Game.RoomState.isVisible("sign"))
        });
        Assert.assertEq(expected = ("demo_room2", false, true), result)

    // ========================================================================
    // setLocked / setVisible: 既存ホットスポットだけを更新
    // ========================================================================

    /// `<<hotspot lock drawer>>` の典型フロー: unlocked で入場 → setLocked(true) →
    /// `is_locked` が true になる。visible は触っていないので true のまま。
    @Test
    def testSetLockedFlipsLockedFlagOnly(): Unit \ Assert =
        let result = withRoomState(() -> {
            Game.RoomState.Access.enter("demo_room", Map#{"drawer" => hsUnlocked()});
            Game.RoomState.Access.setLocked("drawer", true);
            (Game.RoomState.isLocked("drawer"), Game.RoomState.isVisible("drawer"))
        });
        Assert.assertEq(expected = (true, true), result)

    /// `<<hotspot hide drawer>>` の典型フロー: visible 状態から hide → `is_visible`
    /// が false。locked は触らないので元の false のまま。
    @Test
    def testSetVisibleFlipsVisibleFlagOnly(): Unit \ Assert =
        let result = withRoomState(() -> {
            Game.RoomState.Access.enter("demo_room", Map#{"drawer" => hsUnlocked()});
            Game.RoomState.Access.setVisible("drawer", false);
            (Game.RoomState.isLocked("drawer"), Game.RoomState.isVisible("drawer"))
        });
        Assert.assertEq(expected = (false, false), result)

    /// 未登録のホットスポット id への setLocked は no-op（無視される）。
    /// 該当 id がそもそも `is_locked = false` のデフォルトを保ち続ける。
    /// Yarn 側のタイプミス（`<<hotspot lock chesst>>`）でクラッシュしないことの保険。
    @Test
    def testSetLockedOnUnknownIdIsNoOp(): Unit \ Assert =
        let result = withRoomState(() -> {
            Game.RoomState.Access.enter("demo_room", Map#{"drawer" => hsUnlocked()});
            Game.RoomState.Access.setLocked("ghost", true);
            (Game.RoomState.isLocked("drawer"), Game.RoomState.isLocked("ghost"))
        });
        Assert.assertEq(expected = (false, false), result)

    // ========================================================================
    // 未入場時 / 未登録 id: 既定値（空文字 / false）が返る
    // ========================================================================

    /// `enter` を一度も呼んでいない初期状態では currentRoom は空文字、
    /// 任意のホットスポット id は locked=false / visible=false。
    /// `Game.start` 起動直後にビルトイン関数が呼ばれてもクラッシュしないことの保証。
    @Test
    def testQueriesBeforeAnyEnterReturnDefaults(): Unit \ Assert =
        let result = withRoomState(() -> {
            (Game.RoomState.currentRoom(),
             Game.RoomState.isLocked("anything"),
             Game.RoomState.isVisible("anything"))
        });
        Assert.assertEq(expected = ("", false, false), result)
}
