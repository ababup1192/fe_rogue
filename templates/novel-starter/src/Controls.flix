// Controls — 入力の解釈（純粋）。キーは InputMap の表で「操作の意図」に写してから解釈し、
// クリックは UiFocus.hitTestUi で当たりを引いて meta（novel/choice/N）を World の操作へ写す。
// 操作は「選ぶだけ」: ↑↓（カーソル）と 決定（クリック / Z / Enter / Space）。
// Doc の保存即反映（watchFile）と F1 一括リロードの読み直しもここに置く。
mod Controls {
    use GameEngine.Key

    /// このゲームの操作の意図。キーとの対応は tapTable が持つ。
    enum Act with Eq {
        case Confirm   // 進める・選ぶ（クリック / Z / Enter / Space）
        case NavPrev   // 選択肢カーソルを前へ（← ↑ / A W）
        case NavNext   // 選択肢カーソルを後ろへ（→ ↓ / D S）
    }

    /// 単発操作の表。同時押しは firstTap がこの順で先勝ちにする。
    def tapTable(): InputMap.Table[Act] =
           (Key.Z,     Act.Confirm)
        :: (Key.Enter, Act.Confirm)
        :: (Key.Space, Act.Confirm)
        :: (Key.Left,  Act.NavPrev) :: (Key.Up,   Act.NavPrev)
        :: (Key.A,     Act.NavPrev) :: (Key.W,    Act.NavPrev)
        :: (Key.Right, Act.NavNext) :: (Key.Down, Act.NavNext)
        :: (Key.D,     Act.NavNext) :: (Key.S,    Act.NavNext)
        :: Nil

    /// 毎フレームのシステム: 文字送りと UI 投影を 1 歩進める。
    pub def step(frame: App.Frame, w: World.World): World.World =
        World.step(frame#dt, w)

    /// 毎フレームのシステム: 入力の解釈。選択肢待ちだけ操作が変わる
    /// （カーソル移動 + チップのクリック。それ以外は決定 = 進める）。
    pub def interact(frame: App.Frame, w: World.World): World.World =
        if (NovelKit.isAsking(w#kit))
            askInteract(frame, UiFocus.hitTestUi(w#ui, frame#viewport, frame#cursor), w)
        else if (frame#mouseClicked or InputMap.firstTap(tapTable(), frame) == Some(Act.Confirm))
            World.advance(w)
        else w

    /// 選択肢待ち: キーボードのカーソルを基準にし、マウスは動いたフレームだけ吸着
    /// （UiMenu.syncCursor）。ホバー強調はカーソル位置のチップへ。
    /// ↑↓ で移動、決定かチップのクリックで選ぶ。
    def askInteract(frame: App.Frame, hit: Option[EntityId], w: World.World): World.World =
        let synced = UiMenu.syncCursor(NovelKit.choicesPath(),
                                       { mouseMoved = frame#mouseMoved, hit = hit },
                                       w#cursor, w#ui);
        let hovered = { cursor = synced#cursor,
                        ui = UiStore.setHovered(synced#hoverPath, w#ui) | w };
        if (frame#mouseClicked)
            pickClicked(hit, hovered)
        else
            match InputMap.firstTap(tapTable(), frame) {
                case Some(Act.NavPrev) => World.moveCursor(-1, hovered)
                case Some(Act.NavNext) => World.moveCursor(1, hovered)
                case Some(Act.Confirm) => World.pick(hovered#cursor, hovered)
                case _                 => hovered
            }

    /// クリックが選択肢チップ（novel/choice/N）なら、その番号を選ぶ。
    def pickClicked(hit: Option[EntityId], w: World.World): World.World =
        hit |> Option.flatMap(id -> Map.get(id, w#ui#metas))
            |> Option.flatMap(meta -> UiMeta.indexOf(NovelKit.choicePrefix(), meta))
            |> Option.map(i -> World.pick(i, w))
            |> Option.getWithDefault(w)

    // ── Doc の読み込み・読み直し（watchFile / F1） ──

    /// 起動時と bake が同じ形で読む Doc の束。
    pub def loadDocs(): World.Docs \ Fs.FileRead =
        { story = StoryDoc.load(StoryDoc.path()),
          kind = KindDoc.load(KindDoc.path()),
          theme = ThemeDoc.load(ThemeDoc.path()),
          sprites = PxSpriteDoc.load(World.spritePath()) }

    pub def reloadStory(w: World.World): World.World \ Fs.FileRead =
        World.withStory(StoryDoc.load(StoryDoc.path()), w)

    pub def reloadKind(w: World.World): World.World \ Fs.FileRead =
        World.withKind(KindDoc.load(KindDoc.path()), w)

    pub def reloadTheme(w: World.World): World.World \ Fs.FileRead =
        World.withTheme(ThemeDoc.load(ThemeDoc.path()), w)

    pub def reloadSprites(w: World.World): World.World \ Fs.FileRead =
        World.withSprites(PxSpriteDoc.load(World.spritePath()), w)

    /// F1: Doc も ui.json も全部読み直す。
    pub def reloadAll(w: World.World): World.World \ Fs.FileRead =
        w |> reloadStory |> reloadKind |> reloadTheme |> reloadSprites |> World.reloadUi
}
