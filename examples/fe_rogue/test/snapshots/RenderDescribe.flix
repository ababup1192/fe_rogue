// RenderDescribe — renderFrame（render-from-World パイプライン）の描画リストを
// 「1 行 = 1 描画物」の決定的テキストへ変換し、golden と突き合わせる土台。
//
//  - Frame             : renderCommands の 3 チャンネル（sprite / tilemap / polygon）を束ねた記録単位
//  - withRecordingGame : renderCommands の引数を Frame として記録する GameEngine.Game handler
//  - describe          : Frame → テキスト。sprite/box/text/poly は SnapshotSupport.formatScene を
//                        再利用し、tilemap 行だけここで足す（フォーマットの再発明をしない）
//  - matchGolden       : test/snapshots/<name>.golden.txt と比較（FE_ROGUE_SNAPSHOT_UPDATE=1 で更新）
mod RenderDescribe {
    import java.lang.{System => JSystem}

    /// renderCommands 1 回分の描画リスト（描画チャンネル 3 本の束）。
    pub type alias Frame = {
        drawables = List[GameEngine.Drawable],
        tileMaps  = List[GameEngine.TileMapRenderCmd],
        polygons  = List[GameEngine.PolygonRenderCmd]
    }

    /// text 行の外接矩形計算に使うフォントアトラス一辺（testFontAtlas の textureSize と揃える）。
    pub def atlasDim(): Float64 = 256.0

    // ════════════════════════════════════════════════════════
    // renderCommands を記録する GameEngine.Game handler
    // ════════════════════════════════════════════════════════

    /// GL 無しの GameEngine.Game。`renderCommands` の引数を Frame として記録し、
    /// それ以外は TestUnitFixtures.withMockGame と同じ無害スタブ（viewport は設計解像度 240×128）。
    /// `texInfo` は sprite 描画（spriteToDrawable）が要求するテクスチャ実寸表
    /// （SnapshotSupport.buildTextureInfo で組む）。戻り値は (thunk の結果, 記録した Frame 列＝呼ばれた順)。
    pub def withRecordingGame(rc: Region[r], texInfo: Map[String, GameEngine.TextureInfo],
                              thunk: Unit -> a \ ef):
            (a, List[Frame]) \ (ef - GameEngine.Game) + r =
        let framesRef: Ref[List[Frame], r] = Ref.fresh(rc, Nil);
        let out = run { thunk() } with handler GameEngine.Game {
            def renderCommands(sprites, tiles, polys, _staticLayer, k) = {
                Ref.put(({drawables = sprites, tileMaps = tiles, polygons = polys}: Frame)
                            :: Ref.get(framesRef), framesRef);
                k(())
            }
            def initTileBuffer(_, k)        = k((GpuHandle.wrapTileVao(0i32), 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.016))
            def isKeyPressed(_, k)          = k(false)
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(TestUnitFixtures.testFontAtlas())
            def ensureGlyphs(_, _cps, k)    = k(())
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 240.0, y = 128.0}})
            def getTextureInfo(name, k)     = k(Map.get(name, texInfo))
            def ensureTexture(_, _, _, _, _, k) = k(())
            def setCursor(_, k)             = k(())
            def setCursorVisible(_, k)      = k(())
            def setFullscreen(_, k)         = k(())
            def isFullscreen(k)             = k(false)
            def saveAnnotation(_, k)        = k(None)
            def setDebugBadge(_, k)         = k(())
        };
        (out, List.reverse(Ref.get(framesRef)))

    // ════════════════════════════════════════════════════════
    // describe（決定的テキスト化）
    // ════════════════════════════════════════════════════════

    /// Frame を決定的な複数行テキストに変換する。tilemap は 1 コマンド 1 行、
    /// sprite/box/text/poly は SnapshotSupport.formatScene（既存 golden と同じ書式）に委譲する。
    pub def describe(frame: Frame): String =
        let tiles = frame#tileMaps |> List.map(tileLine);
        let body = SnapshotSupport.formatScene(atlasDim(),
            {drawables = frame#drawables, polygons = frame#polygons});
        let sections = List.append(tiles, if (String.isEmpty(body)) Nil else body :: Nil);
        String.unlines(sections)

    /// tilemap 描画コマンドの 1 行表現（tex / 位置 / タイル寸 / 倍率 / タイル数 / z）。
    def tileLine(t: GameEngine.TileMapRenderCmd): String =
        "tiles  z=${t#zIndex} tex=${t#textureName} pos=(${fmt2(t#position#x)},${fmt2(t#position#y)}) "
            + "tileSize=${fmt2(t#tileSize)} scale=(${fmt2(t#tileScale#x)},${fmt2(t#tileScale#y)}) "
            + "n=${t#tileCount}"

    /// Float64 を符号付き小数 2 桁固定に（SnapshotSupport.fmt2 と同じ規約。FP ノイズを締め出す）。
    def fmt2(x: Float64): String =
        let neg = x < 0.0;
        let a = Float64.abs(x);
        let scaled = Float64.tryToInt32(a * 100.0 + 0.5) |> Option.getWithDefault(0i32);
        let ip = scaled / 100i32;
        let fp = scaled - ip * 100i32;
        let body = "${ip}.${if (fp < 10i32) "0${fp}" else "${fp}"}";
        if (neg and scaled != 0i32) "-${body}" else body

    // ════════════════════════════════════════════════════════
    // golden 照合（test/snapshots/<name>.golden.txt）
    // ════════════════════════════════════════════════════════

    /// `text` を golden と突き合わせる。一致なら None、不一致なら差分メッセージ Some。
    /// golden 不在時は生成してメッセージを返す（内容確認とコミットを促す）。
    /// FE_ROGUE_SNAPSHOT_UPDATE が空でなければ上書きして None（SnapshotSupport と同じ更新規約）。
    pub def matchGolden(name: String, text: String): Option[String] \ {IO, Fs.FileRead, Fs.FileWrite} =
        match readGolden(name) {
            case Some(expected) =>
                if (String.trimRight(expected) == String.trimRight(text))
                    None
                else if (updateMode()) {
                    writeGolden(name, text);
                    None
                } else
                    Some(diffMessage(name, String.trimRight(expected), String.trimRight(text)))
            case None =>
                writeGolden(name, text);
                if (updateMode()) None
                else Some("render golden '${name}': 新規 golden を生成しました。内容を確認して "
                          + "${goldenPath(name)} をコミットするか、FE_ROGUE_SNAPSHOT_UPDATE=1 で再実行してください。")
        }

    def goldenPath(name: String): String = "test/snapshots/${name}.golden.txt"

    def updateMode(): Bool \ IO =
        let v = JSystem.getenv("FE_ROGUE_SNAPSHOT_UPDATE");
        not Object.isNull(v) and not String.isEmpty(v)

    def readGolden(name: String): Option[String] \ Fs.FileRead =
        let result = run { Fs.ReadFile.read(goldenPath(name)) } with Fs.ReadFile.runWithFileRead;
        Result.toOption(result)

    def writeGolden(name: String, content: String): Unit \ Fs.FileWrite =
        run { discard Fs.WriteFile.write({str = content}, goldenPath(name)) }
            with Fs.WriteFile.runWithFileWrite

    /// 最初に食い違う行を指摘する（行番号 + expected/actual の該当行）。
    def diffMessage(name: String, expected: String, actual: String): String =
        let es = String.lines(expected);
        let as_ = String.lines(actual);
        match findFirstDiff(0, es, as_) {
            case None    => "render golden '${name}': 行数のみ相違 (expected ${List.length(es)} / actual ${List.length(as_)})"
            case Some(i) =>
                let e = List.nth(i, es) |> Option.getWithDefault("<なし>");
                let a = List.nth(i, as_) |> Option.getWithDefault("<なし>");
                "render golden '${name}' が相違。最初の相違は ${i + 1} 行目:\n"
                    + "  expected: ${e}\n  actual  : ${a}"
        }

    def findFirstDiff(i: Int32, es: List[String], as_: List[String]): Option[Int32] =
        match (es, as_) {
            case (e :: ert, a :: art) => if (e != a) Some(i) else findFirstDiff(i + 1, ert, art)
            case (Nil, Nil)           => None
            case _                    => Some(i)
        }
}
