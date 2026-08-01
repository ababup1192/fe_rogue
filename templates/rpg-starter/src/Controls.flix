// Controls — 入力の解釈（純粋）。キーは InputMap の表で「操作の意図」に写してから解釈する。
// 操作は「歩く」（←→↑↓ / WASD。押しっぱなしで歩き続ける）と
// 「話す・進める」（Z / Enter / Space。押した瞬間だけ）の 2 つだけ。
// Doc の保存即反映（watchFile）と F1 一括リロードの読み直しもここに置く。
mod Controls {
    use GameEngine.Key

    /// 歩く向きの表（押している間ずっと効く）。矢印と WASD は同じ意図。
    /// 同時押しは表の順で先勝ち — 斜めは無い（Dir4 の世界）。
    def moveTable(): InputMap.Table[Dir4.Dir4] =
           (Key.Left,  Dir4.Left)  :: (Key.A, Dir4.Left)
        :: (Key.Right, Dir4.Right) :: (Key.D, Dir4.Right)
        :: (Key.Up,    Dir4.Up)    :: (Key.W, Dir4.Up)
        :: (Key.Down,  Dir4.Down)  :: (Key.S, Dir4.Down)
        :: Nil

    /// 決定（話す・進める）の表（押した瞬間だけ効く）。
    def confirmTable(): InputMap.Table[Unit] =
        (Key.Z, ()) :: (Key.Enter, ()) :: (Key.Space, ()) :: Nil

    /// 毎フレームのシステム: 歩みと文字送りを 1 歩進める。
    pub def step(frame: App.Frame, w: World.World): World.World =
        World.step(List.head(InputMap.held(moveTable(), frame)), frame#dt, w)

    /// 毎フレームのシステム: 決定キーの解釈（表紙では歩き出す・里では話す/送る・
    /// 戦いでは選んだコマンドを実行する）。戦いのカーソル移動（↑↓）も押した瞬間だけ拾う
    /// — 歩きと違って押しっぱなしで滑ってほしくないため。
    pub def interact(frame: App.Frame, w: World.World): World.World =
        let moved = match InputMap.firstTap(moveTable(), frame) {
            case Some(Dir4.Up)   => World.moveCursor(-1, w)
            case Some(Dir4.Down) => World.moveCursor(1, w)
            case _               => w
        };
        match InputMap.firstTap(confirmTable(), frame) {
            case Some(_) => World.confirm(moved)
            case None    => moved
        }

    // ── Doc の読み込み・読み直し（watchFile / F1） ──

    /// 起動時と bake が同じ形で読む Doc の束。
    pub def loadDocs(): World.Docs \ Fs.FileRead =
        { map = MapDoc.load(MapDoc.path()),
          kind = KindDoc.load(KindDoc.path()),
          theme = ThemeDoc.load(ThemeDoc.path()),
          battle = BattleDoc.load(BattleDoc.path()),
          sprites = PxSpriteDoc.load(World.spritePath()),
          terrain = TerrainDoc.load(World.terrainPath()) }

    pub def reloadMap(w: World.World): World.World \ Fs.FileRead =
        World.withMap(MapDoc.load(MapDoc.path()), w)

    pub def reloadKind(w: World.World): World.World \ Fs.FileRead =
        World.withKind(KindDoc.load(KindDoc.path()), w)

    pub def reloadTheme(w: World.World): World.World \ Fs.FileRead =
        World.withTheme(ThemeDoc.load(ThemeDoc.path()), w)

    pub def reloadBattle(w: World.World): World.World \ Fs.FileRead =
        World.withBattleDoc(BattleDoc.load(BattleDoc.path()), w)

    pub def reloadSprites(w: World.World): World.World \ Fs.FileRead =
        World.withSprites(PxSpriteDoc.load(World.spritePath()), w)

    pub def reloadTerrain(w: World.World): World.World \ Fs.FileRead =
        World.withTerrain(TerrainDoc.load(World.terrainPath()), w)

    /// F1: Doc を全部読み直す。
    pub def reloadAll(w: World.World): World.World \ Fs.FileRead =
        w |> reloadMap |> reloadKind |> reloadTheme |> reloadBattle
          |> reloadSprites |> reloadTerrain
}
