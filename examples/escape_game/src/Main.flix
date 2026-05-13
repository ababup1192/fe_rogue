def main(): Unit \ {IO, Chan, NonDet} =
    if (GameEngine.ensureMainThread()) ()
    else {
        let config: GameEngine.EngineConfig = {
            designWidth     = Game.designWi(),
            designHeight    = Game.designHi(),
            windowWidth     = Game.windowWi(),
            windowHeight    = Game.windowHi(),
            title           = "Yarn Spinner Plugin",
            // 背景・キャラのテクスチャ。論理名は story.yarn の <<bg ...>> / <<sprite ...>>
            // 引数と 1:1 で揃える（例: <<bg dungeon ...>> → "bg_dungeon"）。
            // 元素材は sprites/raw/ にあり、scripts/process-sprites.sh で
            // ニアレスト縮小（背景は不透明、キャラは 4 隅 floodfill で背景透過）して
            // sprites/<name>.png を生成する。
            // ファイル名 char_gragon.png は素材のタイポだが、論理名 "char_dragon" で吸収。
            textureManifest =
                // 部屋背景 (480×300, 16:10)。`<<room enter <id>>>` で `RoomScene.applyBackground`
                // が `bg_<id>` をテクスチャに差し替える。
                // ホットスポット (drawer / door 等) は背景画像内に絵として描き込み済みなので
                // 個別の sprite は持たない。クリック判定だけ Area2D + CollisionShape2D で配置する。
                ({ name = "bg_demo_room",  path = "sprites/bg_demo_room.png",  hasAlpha = false }: GameEngine.TextureEntry)
                // インベントリアイコン。InventoryScene が `icon_<itemId>` で参照する。
                :: ({ name = "icon_demo_key", path = "sprites/icon_demo_key.png", hasAlpha = true }: GameEngine.TextureEntry)
                // 個別オブジェクト sprite。背景に描き込まず単体テクスチャとして持ちたいものを登録する。
                :: ({ name = "sprite_safe_box", path = "sprites/sprite_safe_box.png", hasAlpha = true }: GameEngine.TextureEntry)
                :: Nil,
            // PixelMplus10 は 10px 設計のドットフォント。bake サイズも 10 に揃える。
            // [b] タグ用に Bold バリアントを並列登録し、RichTextLabel が文字単位で
            // 切り替える（DialogueScene が `default` と `default-bold` の両方を
            // getFontAtlas して RichTextLabel に注入する）。
            fontManifest    =
                ({ name = "default",      path = "fonts/PixelMplus10-Regular.ttf", fontSize = 10.0 }: GameEngine.FontEntry)
                :: ({ name = "default-bold", path = "fonts/PixelMplus10-Bold.ttf",    fontSize = 10.0 }: GameEngine.FontEntry)
                :: Nil,
            // talk: 行が出るたびに頭の 1〜2 秒（自然減衰まで）を流す効果音
            // tap : 確定キーで会話が進むタイミングの効果音
            // BGM: title / dungeon / room / battle / ending — story.yarn の
            //   <<bgm play <name> loop>> で論理名から引く。looping=true で
            //   OpenAL の AL_LOOPING に乗せて seamless loop。
            // SE chest_open: 宝箱を開けるとき。論理名は story 準拠で
            //   ファイル名 (chest.wav) と異なる。
            soundManifest   =
                ({ name = "talk",       path = "audio/talk.ogg",    looping = false }: GameEngine.AudioEntry)
                :: ({ name = "tap",        path = "audio/tap.ogg",     looping = false }: GameEngine.AudioEntry)
                :: ({ name = "title",      path = "audio/title.ogg",   looping = true  }: GameEngine.AudioEntry)
                :: ({ name = "dungeon",    path = "audio/dungeon.ogg", looping = true  }: GameEngine.AudioEntry)
                :: ({ name = "room",       path = "audio/room.ogg",    looping = true  }: GameEngine.AudioEntry)
                :: ({ name = "battle",     path = "audio/battle.ogg",  looping = true  }: GameEngine.AudioEntry)
                :: ({ name = "ending",     path = "audio/ending.ogg",  looping = true  }: GameEngine.AudioEntry)
                :: ({ name = "chest_open", path = "audio/chest.wav",     looping = false }: GameEngine.AudioEntry)
                // 以下 4 SE は Kenney.nl の RPG Audio パック (CC0) から流用。
                // door_open: doorOpen_1.ogg / locked: metalLatch.ogg
                // hit: knifeSlice.ogg / die: chop.ogg
                :: ({ name = "door_open",  path = "audio/door_open.ogg", looping = false }: GameEngine.AudioEntry)
                :: ({ name = "locked",     path = "audio/locked.ogg",    looping = false }: GameEngine.AudioEntry)
                :: ({ name = "hit",        path = "audio/hit.ogg",       looping = false }: GameEngine.AudioEntry)
                :: ({ name = "die",        path = "audio/die.ogg",       looping = false }: GameEngine.AudioEntry)
                :: Nil,
            clearColor      = {r = 0.1f32, g = 0.1f32, b = 0.15f32},
            maxDeltaTime    = 0.05
        };
        run {
            Game.start()
        } with LwjglLayer.withLwjgl(config)
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
          with Math.Random.runWithIO
    }
