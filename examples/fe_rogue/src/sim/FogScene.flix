/// FogScene — フォグ・オブ・ウォー（画面全体モヤ＋現在部屋を矩形で切り抜き）
///
/// 画面全体を薄暗いモヤで覆い、明るい穴を矩形で切り抜く。点灯ルールは部屋と通路で異なる:
///   - 部屋(room module): origin(ターン開始位置)基準で部屋全体を点灯。キャラがいない部屋は
///     訪問済みでも暗いまま（非永続。部屋を出れば再びモヤに沈む）。
///   - 通路(corridor): 常に味方キャラの周囲1マス(松明)だけを点灯する（部屋とは別仕様）。
/// 敵・アイテム・階段は明るい所以外では非表示。
///
/// scene ノードは持たない。暗幕は `RenderWorld.renderFog` が補集合の矩形
/// （バンド分割 `bandDecompose`）を毎フレーム直描きし、敵/アイテム/階段の可視は
/// 「明るい穴 `holesNow` にセルが入っているか」を読者が描画/判定時に導出する
/// （marker の visible フラグへの書き込みは持たない）。

/// グリッド座標の矩形（半開区間 [x0,x1) × [y0,y1)）。
pub type alias GridRect = {x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32}

mod FogScene {

    /// モヤの色（暗い青灰）と不透明度。地形がうっすら見える程度に薄暗くする。
    /// 視認性とパフォーマンスのトレードオフ調整点。B: render-from-World の `renderFog` も同値を使うため pub。
    pub def fogColor(): Color = {r = 0.04f32, g = 0.05f32, b = 0.10f32}
    pub def fogAlpha(): Float32 = 0.66f32

    /// モヤ矩形の zIndex。Floor=-1 / Walls=0 の上、Item(4,5)/Unit(10) の下。
    /// 可視性制御は z 順ではなく visible=false で行うため z 競合しない。
    pub def fogZIndex(): Int32 = 2

    /// 明るい部屋矩形を floorBounds から外側へ広げるタイル数（壁リングまで明るくする）。tunable。
    def edgePad(): Int32 = 1

    /// モヤで覆う領域をマップ bbox の外側へ広げるタイル数（画面端まで確実にモヤで覆うため）。
    def marginTiles(): Int32 = 60

    /// いま明るい穴の矩形リスト。味方の live 位置/hidden は World、部屋点灯の origin は
    /// 移動ドラフト（`SelectedPlayer` の drafts）由来。移動ドラフト中も「部屋点灯」は
    /// ターン開始位置(origin)基準に固定し、コミットで drafts が消えれば origin==live に戻る
    /// （＝待機/接敵まで新規部屋を暗いまま）。通路は常に周囲1マス(松明)。
    /// Map 不在（タイトル/選択画面などの盤面レス）は None＝読者は「何も照らさない」に倒す。
    /// 敵可視（`EnemyScene.isVisible`）・配置物の lit ゲート（renderStairs/renderItems 等）が共有する。
    pub def holesNow(): Option[List[GridRect]] \ {SelectedPlayer.State, World.WorldQuery} =
        let world = World.WorldQuery.get();
        match World.terrainOf(world) {
            case None    => None
            case Some(_) =>
                let drafts = SelectedPlayer.State.get()#drafts;
                let units  = World.fogUnitsOf(world)
                    |> List.map(d -> {+origin = MoveDraft.originOf(d#id, drafts)
                                                    |> Option.getWithDefault(d#gridPos) | d});
                Some(holesForDraft(units, World.placementsOf(world),
                                    World.roomCountOf(world), true))
        }

    /// 非 hidden プレイヤーごとの「明るい穴」矩形リスト（純粋・テスト対象）。
    /// 部屋なら部屋全体、通路は torchCorridors のとき周囲1マスだけ。
    /// 行多相シグネチャにより PlayerScene.Data 以外（CursorScene 等）からも呼べる汎用 API。
    /// 各ユニットの origin=live としてライブ挙動になる（移動デファー無し）。CursorScene の
    /// 可動域計算など「いまどの部屋が明るいか」をライブで欲しい用途はこちらを使う。
    pub def holesFor(units: List[{gridPos = {x = Int32, y = Int32}, hidden = Bool | r}],
                      placements: List[DungeonComposer.ModulePlacement],
                      roomCount: Int32, torchCorridors: Bool): List[GridRect] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> holeFor(d#gridPos, d#gridPos, placements, roomCount, torchCorridors))

    /// `holesFor` の draft 対応版。部屋(room module)点灯は origin（ターン開始位置）基準で、
    /// 通路・松明はライブ位置。移動中に新しく踏み込んだ部屋を確定まで暗いままにするために
    /// FogScene の per-frame 経路から使う。
    pub def holesForDraft(units: List[{gridPos = {x = Int32, y = Int32},
                                       origin = {x = Int32, y = Int32}, hidden = Bool | r}],
                           placements: List[DungeonComposer.ModulePlacement],
                           roomCount: Int32, torchCorridors: Bool): List[GridRect] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> holeFor(d#gridPos, d#origin, placements, roomCount, torchCorridors))

    /// 1 プレイヤーの明るい穴。`live`=現在位置、`origin`=ターン開始位置（draft 外は origin==live）。
    /// 通路では module 矩形ではなく周囲1マスに絞るのは、通路全体が一気に見えないシレン準拠の
    /// サプライズ感を保つため。**部屋(room module)は origin が同じ部屋にあるときだけ点灯**させ、
    /// 移動中に新しく踏み込んだ部屋は確定（origin 更新）まで暗いままにする。通路・松明はライブ位置。
    def holeFor(live: {x = Int32, y = Int32}, origin: {x = Int32, y = Int32},
                 placements: List[DungeonComposer.ModulePlacement],
                 roomCount: Int32, torch: Bool): Option[GridRect] =
        match MapSnapshot.moduleOfCellIn(live, placements) {
            case None    => if (torch) Some(torchRect(live)) else None
            case Some(m) =>
                if (m >= roomCount)
                    (if (torch) Some(torchRect(live)) else moduleRectByIdx(m, placements))
                else if (MapSnapshot.moduleOfCellIn(origin, placements) == Some(m))
                    moduleRectByIdx(m, placements)
                else None
        }

    /// module idx → moduleRect。未配置 idx は None（DungeonComposer が idx を連番で振るため通常起きない）。
    def moduleRectByIdx(m: Int32, placements: List[DungeonComposer.ModulePlacement]): Option[GridRect] =
        List.find(p -> p#idx == m, placements) |> Option.map(moduleRect)

    /// セルの周囲 torchRadius マス（半開区間）の矩形。
    def torchRadius(): Int32 = 1
    def torchRect(cell: {x = Int32, y = Int32}): GridRect =
        let rad = torchRadius();
        ({x0 = cell#x - rad, y0 = cell#y - rad,
          x1 = cell#x + rad + 1, y1 = cell#y + rad + 1}: GridRect)

    /// セルがいずれかの矩形の内側か（半開区間 [x0,x1) × [y0,y1)）。
    /// フォグの穴判定と CursorScene の移動可動域判定で共用するため pub に公開する。
    pub def insideAny(cell: {x = Int32, y = Int32}, holes: List[GridRect]): Bool =
        List.exists(h ->
            cell#x >= h#x0 and cell#x < h#x1 and cell#y >= h#y0 and cell#y < h#y1, holes)

    /// GridRect を四方に n タイル広げる（Chebyshev 拡張）。半開区間なので x1/y1 は + n。
    def dilate(r: GridRect, n: Int32): GridRect =
        ({x0 = r#x0 - n, y0 = r#y0 - n, x1 = r#x1 + n, y1 = r#y1 + n}: GridRect)

    /// カーソルが動ける範囲の矩形群。
    ///   - いま明るい部屋（holesFor, torch=false）を radius タイル四方に拡張したもの
    ///   - すでに訪れた module（visited）の矩形（moduleRect, 壁リング込み）
    /// の和。CursorScene が候補セルの可否判定（insideAny）に使う。純粋（テスト対象）。
    /// PlayerCursor フェーズは torchCorridors=false なので holesFor は各非 hidden
    /// プレイヤーの module 矩形を返す。明るい部屋は visited にも含まれるが、litExpanded が
    /// +radius の余白を足す（visited 矩形は余白なし＝「行った部屋まで」）。
    pub def cursorRangeRects(units: List[{gridPos = {x = Int32, y = Int32}, hidden = Bool | r}],
                              placements: List[DungeonComposer.ModulePlacement],
                              roomCount: Int32, visited: Set[Int32],
                              radius: Int32): List[GridRect] =
        let litExpanded  = holesFor(units, placements, roomCount, false)
                            |> List.map(rc -> dilate(rc, radius));
        let visitedRects = placements
                            |> List.filter(p -> Set.memberOf(p#idx, visited))
                            |> List.map(moduleRect);
        List.append(litExpanded, visitedRects)

    // 暗幕は `RenderWorld.renderFog` が bandDecompose の矩形を solidBox で直描きする唯一の経路。

    /// module の floorBounds(±edgePad で壁リングまで拡張) を world grid 矩形にする。
    pub def moduleRect(p: DungeonComposer.ModulePlacement): GridRect =
        { x0 = p#offset#x + p#floorBoundsMin#x   - edgePad(),
          y0 = p#offset#y + p#floorBoundsMin#y   - edgePad(),
          x1 = p#offset#x + p#floorBoundsMaxEx#x + edgePad(),
          y1 = p#offset#y + p#floorBoundsMaxEx#y + edgePad() }

    /// モヤで覆う領域 = 全 module の moduleRect の union を marginTiles だけ外へ広げたもの。
    pub def mapRegion(placements: List[DungeonComposer.ModulePlacement]): GridRect =
        match List.map(moduleRect, placements) {
            case Nil          => ({x0 = 0, y0 = 0, x1 = 0, y1 = 0}: GridRect)
            case first :: rest =>
                let u = List.foldLeft((a, r) -> ({
                            x0 = Int32.min(a#x0, r#x0), y0 = Int32.min(a#y0, r#y0),
                            x1 = Int32.max(a#x1, r#x1), y1 = Int32.max(a#y1, r#y1)}: GridRect),
                        first, rest);
                let m = marginTiles();
                ({x0 = u#x0 - m, y0 = u#y0 - m, x1 = u#x1 + m, y1 = u#y1 + m}: GridRect)
        }

    /// `area` から `holes`（明るい部屋の矩形群）を除いた補集合を、重なりのない矩形群へ
    /// 分割する（横バンド分割）。純粋関数（テスト対象）。
    pub def bandDecompose(area: GridRect, holes: List[GridRect]): List[GridRect] =
        // area に clamp して空矩形を除去
        let clamped = holes |> List.filterMap(h -> {
            let x0 = Int32.max(h#x0, area#x0);
            let y0 = Int32.max(h#y0, area#y0);
            let x1 = Int32.min(h#x1, area#x1);
            let y1 = Int32.min(h#y1, area#y1);
            if (x0 < x1 and y0 < y1) Some(({x0 = x0, y0 = y0, x1 = x1, y1 = y1}: GridRect))
            else None
        });
        let ys = sortedDistinct(area#y0 :: area#y1 ::
                    (clamped |> List.flatMap(h -> h#y0 :: h#y1 :: Nil)));
        consecutivePairs(ys) |> List.flatMap(band -> {
            let (ya, yb) = band;
            // このバンド [ya,yb) を縦に跨ぐ hole の x 区間
            let intervals = clamped
                |> List.filter(h -> h#y0 <= ya and h#y1 >= yb)
                |> List.map(h -> (h#x0, h#x1))
                |> List.sortBy(iv -> fst(iv))
                |> mergeIntervals;
            xGaps(area#x0, area#x1, intervals)
                |> List.map(g -> {
                    let (gx0, gx1) = g;
                    ({x0 = gx0, y0 = ya, x1 = gx1, y1 = yb}: GridRect)
                })
        })

    /// 昇順ソート＋重複除去。
    def sortedDistinct(xs: List[Int32]): List[Int32] = dedupSorted(List.sort(xs))

    def dedupSorted(xs: List[Int32]): List[Int32] = match xs {
        case a :: b :: rest => if (a == b) dedupSorted(b :: rest) else a :: dedupSorted(b :: rest)
        case _              => xs
    }

    /// 連続ペア [a,b,c] -> [(a,b),(b,c)]。bandDecompose でバンド境界の y 区間を生成するために使う。
    def consecutivePairs(xs: List[Int32]): List[(Int32, Int32)] = match xs {
        case a :: b :: rest => (a, b) :: consecutivePairs(b :: rest)
        case _              => Nil
    }

    /// x0 昇順ソート済みの区間列を、重なり・隣接を結合する。
    /// 隣接 hole が重なったとき余分な矩形が生まれないよう、xGaps 適用前に呼ぶ。
    def mergeIntervals(xs: List[(Int32, Int32)]): List[(Int32, Int32)] = match xs {
        case Nil               => Nil
        case (a0, a1) :: rest  => mergeGo(a0, a1, rest)
    }

    /// 不変条件: c0 <= c1 を維持しながら現在の区間 [c0,c1) に次の区間を結合または確定させる。
    def mergeGo(c0: Int32, c1: Int32, rest: List[(Int32, Int32)]): List[(Int32, Int32)] = match rest {
        case Nil              => (c0, c1) :: Nil
        case (b0, b1) :: more =>
            if (b0 <= c1) mergeGo(c0, Int32.max(c1, b1), more)
            else (c0, c1) :: mergeGo(b0, b1, more)
    }

    /// [lo,hi) から（マージ済み・昇順の）区間群を除いた隙間を返す。
    def xGaps(lo: Int32, hi: Int32, intervals: List[(Int32, Int32)]): List[(Int32, Int32)] =
        match intervals {
            case Nil              => if (lo < hi) (lo, hi) :: Nil else Nil
            case (a0, a1) :: rest =>
                let gap = if (lo < a0) ((lo, a0): (Int32, Int32)) :: Nil else Nil;
                List.append(gap, xGaps(Int32.max(lo, a1), hi, rest))
        }
}
