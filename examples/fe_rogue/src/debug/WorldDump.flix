/// WorldDump — F8 注釈チケットに同梱する world.json の本文を組む純粋モジュール。
///
/// annotation.json（絵の側の事実）に対して、こちらはシムの側の事実を残す:
/// 全体の要約（フェーズ・カーソル・カメラ・両陣営の駒）と、注釈で囲った場所の
/// セル詳細（地形・壁キー・居る駒・宝箱・床アイテム）の二段構成。
/// 見た目と状態のどちらが食い違っているかを、チケットだけで切り分けられるようにする。
mod WorldDump {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber, JBool, JNull}

    /// 注釈の矩形（デザイン座標）と表示中の World から world.json の本文を組む。
    /// App.withWorldDump に繋ぐ入口。盤面レス画面（タイトル等）は cellsInRect が空になる。
    pub def dump(rect: Rect2.Rect2, world: World): String =
        let playerViews = unitViews(World.playerIdsOf(world) |> List.map(World.EntityRef.Player), world);
        let enemyViews = unitViews(World.enemyIdsOf(world) |> List.map(World.EntityRef.Enemy), world);
        let allViews = List.append(playerViews, enemyViews);
        let obj = JObject(Map#{
            "turnPhase"   => JString("${World.turnPhaseOf(world)}"),
            "screen"      => JString(screenName(World.screenOf(world))),
            "floorId"     => JString(World.floorIdOf(world)),
            "materialId"  => World.mapFloorInfoOf(world)
                             |> Option.map(info -> JString(info#materialId))
                             |> Option.getWithDefault(JNull),
            "cursor"      => cellJson(World.cursorLogicalOf(world)#gridPos),
            "camera"      => cameraJson(World.cameraRigOf(world)),
            "players"     => JArray(playerViews |> List.map(unitJson) |> List.toVector),
            "enemies"     => JArray(enemyViews |> List.map(unitJson) |> List.toVector),
            "map"         => mapJson(allViews, world),
            "mapLegend"   => JString("# = 壁, ~ = 描画床(通行不可・水路等), . = 床, , = 盤内の空(void), 空白 = 範囲外, P = 味方, E = 敵, + = カーソル, C = 宝箱, i = 床アイテム"),
            "cellsInRect" => JArray(cellsUnder(rect, world)
                                    |> List.map(cell -> cellDetailJson(cell, allViews, world))
                                    |> List.toVector)
        });
        Util.Json.toPrettyString(2, obj)

    /// リモートデバッグ（view=status）用の 1 行サマリ。画面・ターン・フロア・
    /// カーソル位置・両陣営の生存数だけを短く並べる（詳細は view=full = dump が担う）。
    pub def statusLine(world: World): String =
        let cursor = World.cursorLogicalOf(world)#gridPos;
        let players = unitViews(World.playerIdsOf(world) |> List.map(World.EntityRef.Player), world);
        let enemies = unitViews(World.enemyIdsOf(world) |> List.map(World.EntityRef.Enemy), world);
        "screen=${screenName(World.screenOf(world))} turnPhase=${World.turnPhaseOf(world)}"
        + " floor=${World.floorIdOf(world)} cursor=(${cursor#x},${cursor#y})"
        + " players=${List.length(players)} enemies=${List.length(enemies)}"

    /// 駒参照の列を UnitView の列へ（倒れて store から消えた駒は自然に落ちる）。
    def unitViews(refs: List[World.EntityRef], world: World): List[UnitView] =
        refs |> List.filterMap(ref -> World.unitViewFromWorld(ref, world))

    /// 画面（GamePhase）の表示名。ToString を持たないため、ここで名前を付ける。
    def screenName(phase: GamePhase): String = match phase {
        case GamePhase.Title           => "Title"
        case GamePhase.CharacterSelect => "CharacterSelect"
        case GamePhase.Playing         => "Playing"
    }

    /// カメラの要約: 画面中央に映しているワールド座標・追従ターゲット・ズーム倍率。
    def cameraJson(rig: CameraState.RigState): Json =
        JObject(Map#{
            "center" => vecJson(Camera.transform(rig#camera)#position),
            "target" => vecJson(rig#target),
            "zoom"   => JNumber(JsonCodec.floatToBd(Camera.getZoom(rig#camera)#x))
        })

    /// 駒 1 体の要約: 位置・残 HP・攻撃対象から外れるフラグ・索敵タイプ。
    def unitJson(unit: UnitView): Json =
        JObject(Map#{
            "id"      => JNumber(JsonCodec.intToBd(unit#id)),
            "faction" => JString("${unit#faction}"),
            "pos"     => cellJson(unit#pos),
            "hp"      => JNumber(JsonCodec.intToBd(unit#hp)),
            "isDying" => JBool(unit#isDying),
            "hidden"  => JBool(unit#hidden),
            "ai"      => JString("${unit#aiType}")
        })

    /// フロア全体の ASCII 地図（1 行 = 1 文字列）。地形の上に駒・カーソル・宝箱・
    /// 床アイテムを重ねる。部屋の形と配置関係をひと目で掴むための全体像で、
    /// セルの正確な値は cellsInRect が担う。地形が無い画面は空。
    pub def mapRows(allViews: List[UnitView], world: World): List[String] =
        match World.terrainOf(world) {
            case None          => Nil
            case Some(terrain) =>
                List.range(0, terrain#usedRect#size#y)
                |> List.map(row -> mapRow(row, allViews, world, terrain))
        }

    /// mapRows を JSON へ（地形が無い画面は null）。
    def mapJson(allViews: List[UnitView], world: World): Json =
        match mapRows(allViews, world) {
            case Nil  => JNull
            case rows => JArray(rows |> List.map(row -> JString(row)) |> List.toVector)
        }

    /// 地図の 1 行ぶんの文字列。
    def mapRow(row: Int32, allViews: List[UnitView], world: World, terrain: MapSnapshot): String =
        List.range(0, terrain#usedRect#size#x)
        |> List.map(col -> mapGlyph({x = col, y = row}, allViews, world, terrain))
        |> List.join("")

    /// セル 1 個ぶんの地図記号。重なったときは 駒 > カーソル > 宝箱・床アイテム > 地形 の順に勝つ
    /// （調査で最も見たいものを上に出す）。床セル集合があれば「範囲内だが床が無い空間（void）」を
    /// `,` として床と区別する（タイル選択は床/void で違うチップを選ぶため、地図もその粒度で出す）。
    /// 通行不可なのに床セル集合に入っているセル（水路など、床として描かれる装飾）は `~`。
    /// タイル選択はこのセルを床として数えるので、`#` と混ぜると再現器のキー計算が全部ずれる。
    def mapGlyph(cell: Grid.Cell, allViews: List[UnitView], world: World, terrain: MapSnapshot): String =
        match List.find(unit -> unit#pos#x == cell#x and unit#pos#y == cell#y, allViews) {
            case Some(unit) => match unit#faction {
                case Faction.Player => "P"
                case Faction.Enemy  => "E"
            }
            case None =>
                let cursor = World.cursorLogicalOf(world)#gridPos;
                if (cursor#x == cell#x and cursor#y == cell#y) "+"
                else if (Option.nonEmpty(World.chestAtOf(cell, world))) "C"
                else if (Option.nonEmpty(World.groundItemAtOf(cell, world))) "i"
                else if (MapSnapshot.isWall(cell, terrain) and isFloorCell(cell, world, terrain)) "~"
                else if (MapSnapshot.isWall(cell, terrain)) "#"
                else if (isFloorCell(cell, world, terrain)) "."
                else if (MapSnapshot.isFloor(cell, terrain)) ","
                else " "
        }

    /// セルが本当の床か。床セル集合（合成後 mergedFloor）が seed 済みならそれが正解。
    /// 無ければ従来どおり「範囲内かつ非壁 = 床」に落とす（床/void の区別なし）。
    def isFloorCell(cell: Grid.Cell, world: World, terrain: MapSnapshot): Bool =
        match World.mapFloorInfoOf(world) {
            case Some(info) => Set.memberOf((cell#x, cell#y), info#floorCells)
            case None       => MapSnapshot.isFloor(cell, terrain)
        }

    /// 注釈の矩形（デザイン座標）が触れているグリッドセルを左上から行順に列挙する。
    /// 地形が無い画面（タイトル等）は空。
    pub def cellsUnder(rect: Rect2.Rect2, world: World): List[Grid.Cell] =
        match World.terrainOf(world) {
            case None          => Nil
            case Some(terrain) =>
                let camera = World.cameraRigOf(world)#camera;
                let topLeft = Grid.cellAt(terrain#tileSize,
                                  Vec2.sub(screenToWorld(rect#position, camera), terrain#mapGlobal));
                let bottomRight = Grid.cellAt(terrain#tileSize,
                                  Vec2.sub(screenToWorld(Vec2.add(rect#position, rect#size), camera),
                                           terrain#mapGlobal));
                List.range(topLeft#y, bottomRight#y + 1) |> List.flatMap(row ->
                    List.range(topLeft#x, bottomRight#x + 1) |> List.map(col -> {x = col, y = row}))
        }

    /// デザイン座標 → ワールド座標。カメラ投影 screen = world * zoom - (center * zoom - design/2)
    /// を world について逆に解く。design は fe_rogue の設計解像度（Game.designWi/Hi）。
    pub def screenToWorld(screenPos: Vec2.Vec2, camera: Camera): Vec2.Vec2 =
        let center = Camera.transform(camera)#position;
        let zoom = Camera.getZoom(camera);
        let halfW = Int32.toFloat64(Game.designWi()) / 2.0;
        let halfH = Int32.toFloat64(Game.designHi()) / 2.0;
        { x = (screenPos#x + center#x * zoom#x - halfW) / zoom#x,
          y = (screenPos#y + center#y * zoom#y - halfH) / zoom#y }

    /// セル 1 個の真実: 地形（Wall/Floor/Void）・TRBL キー・居る駒・宝箱・床アイテム。
    /// Void は「床でも壁でもない」で、盤面の範囲内（部屋の外の暗がり）と範囲外の両方を含む
    /// （タイル選択の trit キーもこの 2 つを同じ E として扱う）。
    /// terrain は通行可否（ゲームプレイ）、wallKey はタイル選択（描画）の真実で、基準が違う:
    /// wallKey は壁リング（描画床の 8 近傍）のセルに出す。地形が Void でもリングに入って
    /// いれば壁チップが生成されるので出し、逆に水路などの描画床セルには出さない。
    def cellDetailJson(cell: Grid.Cell, allViews: List[UnitView], world: World): Json =
        let terrain = World.terrainOrBug(world);
        let floorCells = World.mapFloorInfoOf(world) |> Option.map(info -> info#floorCells);
        let ringOpt = ringCellsOf(floorCells, terrain);
        let isWall = MapSnapshot.isWall(cell, terrain);
        let bakesWallChip = match ringOpt {
            case Some(ring) => Set.memberOf((cell#x, cell#y), ring)
            case None       => isWall
        };
        JObject(Map#{
            "pos"     => cellJson(cell),
            "terrain" => JString(if (isWall) "Wall"
                                 else if (isFloorCell(cell, world, terrain)) "Floor"
                                 else "Void"),
            "wallKey" => if (bakesWallChip) JString(wallTritKey(cell, floorCells, terrain)) else JNull,
            "chips"   => JArray(World.tileChipsAtOf(cell, world)
                                |> List.map(cellJson) |> List.toVector),
            "units"   => JArray(allViews
                                |> List.filter(unit -> unit#pos#x == cell#x and unit#pos#y == cell#y)
                                |> List.map(unitJson) |> List.toVector),
            "chest"   => World.chestAtOf(cell, world)
                         |> Option.map(chest -> JString(chest#contentId))
                         |> Option.getWithDefault(JNull),
            "item"    => World.groundItemAtOf(cell, world)
                         |> Option.map(item -> JString(item#itemKey))
                         |> Option.getWithDefault(JNull)
        })

    /// 壁セルの TRBL 4 文字キー（上右下左、W=壁 F=床 E=どちらでもない）。material の wallMap を
    /// 引くキーと同じ読み方・同じ基準（MapLoader.trblTritKeyAt と同義）。`floorCells`（合成後の
    /// 床セル集合）があれば W=壁リング所属 / F=床セル集合所属 / E=それ以外 で判定するため、
    /// 通行不可でも床として描かれるセル（水路等）は F、リング外の通行不可セルは E になる。
    /// None なら地形基準（壁=W・範囲内かつ非壁=F）に落ちるため、盤内 void が F と出る
    /// （正確なキーが要る調査では床セル集合を必ず渡す）。
    /// キー欠落・キー衝突による黒い穴を、スクショと突き合わせて特定するための値。
    pub def wallTritKey(cell: Grid.Cell, floorCells: Option[Set[(Int32, Int32)]], terrain: MapSnapshot): String =
        let ringOpt = ringCellsOf(floorCells, terrain);
        tritOf({x = cell#x, y = cell#y - 1}, floorCells, ringOpt, terrain)
        + tritOf({x = cell#x + 1, y = cell#y}, floorCells, ringOpt, terrain)
        + tritOf({x = cell#x, y = cell#y + 1}, floorCells, ringOpt, terrain)
        + tritOf({x = cell#x - 1, y = cell#y}, floorCells, ringOpt, terrain)

    /// タイルベイクと同じ壁リング（描画床の 8 近傍で床でないセル）。
    /// 床セル集合が無い画面では None（地形基準の判定に落ちる）。
    def ringCellsOf(floorCells: Option[Set[(Int32, Int32)]], terrain: MapSnapshot): Option[Set[(Int32, Int32)]] =
        floorCells |> Option.map(cells ->
            MapLoader.computeWallCells(cells, terrain#usedRect#size#x, terrain#usedRect#size#y))

    /// 隣セル 1 方向ぶんの 3 値: 壁 W / 床 F / どちらでもない E。
    /// リングがあればリング所属 → 床セル集合所属 → E の順（MapLoader.tritAt と同じ）。
    def tritOf(cell: Grid.Cell, floorCells: Option[Set[(Int32, Int32)]],
               ringOpt: Option[Set[(Int32, Int32)]], terrain: MapSnapshot): String =
        match (ringOpt, floorCells) {
            case (Some(ring), Some(cells)) =>
                if (Set.memberOf((cell#x, cell#y), ring)) "W"
                else if (Set.memberOf((cell#x, cell#y), cells)) "F"
                else "E"
            case _ =>
                if (MapSnapshot.isWall(cell, terrain)) "W"
                else if (MapSnapshot.isFloor(cell, terrain)) "F"
                else "E"
        }

    /// グリッド座標を {x, y} の JSON へ。
    def cellJson(cell: {x = Int32, y = Int32}): Json =
        JObject(Map#{
            "x" => JNumber(JsonCodec.intToBd(cell#x)),
            "y" => JNumber(JsonCodec.intToBd(cell#y))
        })

    /// ワールド座標を {x, y} の JSON へ。
    def vecJson(v: Vec2.Vec2): Json =
        JObject(Map#{
            "x" => JNumber(JsonCodec.floatToBd(v#x)),
            "y" => JNumber(JsonCodec.floatToBd(v#y))
        })
}
