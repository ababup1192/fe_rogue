/// 2D スプライトノード — テクスチャを表示する最小の描画ノード。
///
/// テクスチャを 1 枚表示するだけの軽いノードで、可視性・描画順（CanvasItem）と座標変換（Node2D）を持つ。
/// これがあれば絵をとりあえず画面に出せるので、キャラや背景の基本パーツになる。
/// 利用例: キャラ 1 体を配置する / スプライトシートの 1 コマを切り出して表示する。
///
///   Sprite
///     ├─ CanvasItem: visible, zIndex, modulate
///     └─ Node2D: position, rotation, scale, skew
///
/// テクスチャの切り出しは 2 つの機構で表現する:
///   - region: テクスチャ内のサブ矩形（ピクセル単位）。None ならテクスチャ全体を使う。
///   - hframes / vframes / frame: region をさらに格子分割し、表示するセル index を指定。
///
/// region のみ指定すれば region_rect 切り出し、hframes/vframes/frame のみ指定すれば
/// スプライトシート分割、両方指定すれば region 内をさらに格子分割となる。
pub enum Sprite {
    case Sprite({
        position = Vec2.Vec2,           // 位置
        rotation = Float64,              // 回転（ラジアン）
        scale = Vec2.Vec2,              // スケール
        skew = Float64,                  // スキュー（ラジアン）
        visible = Bool,                  // 表示フラグ
        zIndex = Int32,                  // 描画順
        modulate = Color,                // 色変調（{r, g, b}、不透明度は alpha フィールドで指定）
        alpha = Float32,                 // 不透明度 0.0–1.0。Color にアルファが無いため別フィールド
        texture = String,                // テクスチャパス
        centered = Bool,                 // 中心を原点にするか
        offset = Vec2.Vec2,             // 描画オフセット
        flipH = Bool,                    // 水平反転
        flipV = Bool,                    // 垂直反転
        regionRect = Option[Rect2.Rect2], // テクスチャ内の切り出し矩形（ピクセル単位）。None ならテクスチャ全体
        hframes = Int32,                 // 格子分割の列数（デフォルト 1）
        vframes = Int32,                 // 格子分割の行数（デフォルト 1）
        frame = Int32,                   // 表示セル index = row * hframes + col（デフォルト 0）
        ySortEnabled = Bool              // CanvasItem: 子を global_y で並べる
    })
}

mod Sprite {
    /// デフォルト値で Sprite を生成する（テクスチャ全体を表示）
    pub def make(texture: String, position: Vec2.Vec2, scale: Vec2.Vec2): Sprite =
        Sprite.Sprite({
            position = position,
            rotation = 0.0,
            scale = scale,
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            alpha = 1.0f32,
            texture = texture,
            centered = true,
            offset = {x = 0.0, y = 0.0},
            flipH = false,
            flipV = false,
            regionRect = None,
            hframes = 1,
            vframes = 1,
            frame = 0,
            ySortEnabled = false
        })

    /// 不透明度を設定する（0.0 = 完全透明、1.0 = 不透明）
    pub def setAlpha(alpha: Float32, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({alpha = alpha | r})

    /// テクスチャ名を変更する
    pub def setTexture(texture: String, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({texture = texture | r})

    /// 水平反転を設定する
    pub def setFlipH(h: Bool, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({flipH = h | r})

    /// 垂直反転を設定する
    pub def setFlipV(v: Bool, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({flipV = v | r})

    /// テクスチャ内の切り出し矩形を設定する。None ならテクスチャ全体を使う
    pub def setRegionRect(rect: Option[Rect2.Rect2], sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({regionRect = rect | r})

    /// 格子分割の列数を設定する（スプライトシート用）
    pub def setHframes(hframes: Int32, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({hframes = hframes | r})

    /// 格子分割の行数を設定する（スプライトシート用）
    pub def setVframes(vframes: Int32, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({vframes = vframes | r})

    /// 表示セル index を設定する。frame = row * hframes + col
    pub def setFrame(frame: Int32, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({frame = frame | r})

    /// centered フラグ (中心を原点にするか) を設定する
    pub def setCentered(centered: Bool, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({centered = centered | r})

    /// 描画オフセット (centered 基準点からのずれ) を設定する
    pub def setOffset(offset: Vec2.Vec2, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({offset = offset | r})

    /// 表示セルを (col, row) 座標で設定する。内部で frame = row * hframes + col に変換される
    pub def setFrameCoords(col: Int32, row: Int32, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({frame = row * r#hframes + col | r})

    /// Sprite を Drawable に変換する。
    /// region / hframes / vframes / frame から GPU シェーダ用 uvOffset/uvScale を計算するため
    /// テクスチャサイズが必要で、Game eff を要求する。
    /// テクスチャ未登録時は bug! でクラッシュする。
    /// centered=false かつ region 未指定・分割なしの場合は scale を uvScale にして
    /// タイリング描画する（背景用）。
    pub def toDrawable(sprite: Sprite, globalPos: Vec2.Vec2):
                        GameEngine.Drawable \ GameEngine.Game =
        let Sprite.Sprite(r) = sprite;
        let texInfo = match GameEngine.Game.getTextureInfo(r#texture) {
            case Some(info) => info
            case None       => bug!("Sprite.toDrawable: texture '${r#texture}' not registered")
        };
        let texSize: Vec2.Vec2 = {x = texInfo#width, y = texInfo#height};
        let uv = Sprite.computeUv(sprite, texSize);
        // 切り出しなし (regionRect=None, hframes=vframes=1, frame=0) かつ centered=false なら
        // 背景タイリング扱いで scale を uv にも反映する
        let isFullTexture = Option.isEmpty(r#regionRect) and r#hframes == 1
                            and r#vframes == 1 and r#frame == 0;
        let uvSc: Vec2.Vec2 =
            if (isFullTexture and not r#centered) r#scale
            else uv#uvScale;
        // セル分割／領域指定が有効なときは描画矩形をセルサイズに合わせる必要がある。
        // レンダラは `displayW = texInfo#width * drawable#scale#x` で矩形を決めるため、
        // scale に uvScale を掛けて (texSize * scale * uvScale = cellSize * scale) にする
        let drawScale: Vec2.Vec2 =
            if (isFullTexture) r#scale
            else {x = r#scale#x * uv#uvScale#x,
                  y = r#scale#y * uv#uvScale#y};
        // flipH / flipV は scale を負にすることで model 行列で反転させる
        let flippedScale: Vec2.Vec2 = {
            x = if (r#flipH) -1.0 * drawScale#x else drawScale#x,
            y = if (r#flipV) -1.0 * drawScale#y else drawScale#y
        };
        {
            texture = r#texture,
            position = globalPos,
            scale = flippedScale,
            rotation = r#rotation,
            color = r#modulate,
            alpha = r#alpha,
            centered = r#centered,
            uvOffset = uv#uvOffset,
            uvScale = uvSc,
            zIndex = r#zIndex,
            style = None
        }

    /// regionRect / hframes / vframes / frame と元テクスチャサイズから
    /// GPU シェーダ用の uvOffset / uvScale を計算する。
    /// regionRect = None なら textureSize を atlas として使い、hframes×vframes でセル分割する。
    pub def computeUv(sprite: Sprite, textureSize: Vec2.Vec2):
                      {uvOffset = Vec2.Vec2, uvScale = Vec2.Vec2} =
        let Sprite.Sprite(r) = sprite;
        let atlasPx = match r#regionRect {
            case Some(rect) => rect
            case None       => Rect2.fromSize(textureSize)
        };
        let cellW = atlasPx#size#x / Int32.toFloat64(r#hframes);
        let cellH = atlasPx#size#y / Int32.toFloat64(r#vframes);
        let col = Int32.modulo(r#frame, r#hframes);
        let row = r#frame / r#hframes;
        let cellX = atlasPx#position#x + Int32.toFloat64(col) * cellW;
        let cellY = atlasPx#position#y + Int32.toFloat64(row) * cellH;
        {
            uvOffset = {x = cellX / textureSize#x, y = cellY / textureSize#y},
            uvScale  = {x = cellW / textureSize#x, y = cellH / textureSize#y}
        }

}

// ── Renderable 実装 ──

instance GameEngine.Renderable[Sprite] {
    pub def toDrawables(sprite: Sprite, globalPos: Vec2.Vec2):
                         List[GameEngine.Drawable] \ GameEngine.Game =
        Sprite.toDrawable(sprite, globalPos) :: Nil
}

// ── CanvasItem 実装 ──

instance CanvasItem[Sprite] {
    pub def isVisible(sprite: Sprite): Bool =
        let Sprite.Sprite(r) = sprite;
        r#visible
    pub def setVisible(visible: Bool, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({ visible = visible | r })
    pub def getModulate(sprite: Sprite): Color =
        let Sprite.Sprite(r) = sprite;
        r#modulate
    pub def setModulate(color: Color, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({ modulate = color | r })
    pub def getZIndex(sprite: Sprite): Int32 =
        let Sprite.Sprite(r) = sprite;
        r#zIndex
    pub def setZIndex(zIndex: Int32, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({ zIndex = zIndex | r })
    redef isYSortEnabled(sprite: Sprite): Bool =
        let Sprite.Sprite(r) = sprite;
        r#ySortEnabled
    redef setYSortEnabled(v: Bool, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({ ySortEnabled = v | r })
}

// ── Node2D 実装 ──

instance Node2D[Sprite] {
    pub def getPosition(sprite: Sprite): Vec2.Vec2 =
        let Sprite.Sprite(r) = sprite;
        r#position
    pub def setPosition(position: Vec2.Vec2, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({ position = position | r })
    pub def getRotation(sprite: Sprite): Float64 =
        let Sprite.Sprite(r) = sprite;
        r#rotation
    pub def setRotation(rotation: Float64, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({ rotation = rotation | r })
    pub def getScale(sprite: Sprite): Vec2.Vec2 =
        let Sprite.Sprite(r) = sprite;
        r#scale
    pub def setScale(scale: Vec2.Vec2, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({ scale = scale | r })
    pub def getSkew(sprite: Sprite): Float64 =
        let Sprite.Sprite(r) = sprite;
        r#skew
    pub def setSkew(skew: Float64, sprite: Sprite): Sprite =
        let Sprite.Sprite(r) = sprite;
        Sprite.Sprite({ skew = skew | r })
}
