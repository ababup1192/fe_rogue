// SpritePreview — schema 走査で sprite-like nested を検出し、JLabel に画像を描画する
//
// 検出ロジック (汎用): schema を再帰 walk して以下を満たす Nested を探す:
//   - TexturePathT 型のフィールドがある
//   - IntT + FrameGrid ヒントのフィールドがある (同じ Nested 内)
//
// 検出した nested の値 (texture, hframes, vframes, frame) を data JSON から読み、
// AWT BufferedImage の getSubimage で frame を切り出し、×4 NEAREST スケールで JLabel に貼る。
//
// 「sprite」「icon」などのキー名は一切見ない。

mod SpritePreview {
    import javax.swing.JLabel
    import javax.swing.ImageIcon
    import javax.swing.SwingConstants
    import java.awt.Image
    import java.awt.Color
    import java.awt.image.BufferedImage
    import javax.imageio.ImageIO
    import java.io.File
    import java.math.{BigDecimal => JBigDecimal}

    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonNumber, JsonBool}
    use Resource.{ResourceSchema, FieldEntry, FieldSchema, FieldType, FieldHint}

    pub type alias IdeState = IdeState.IdeState

    /// 編集中の Resource 全体から sprite-like nested の値を取り出し、preview JLabel を更新する。
    /// 検出失敗 / 値不正 / texture 不在の場合は "(no preview)" 表示にする。
    /// catalog 形式時は ResourceState.selectedSubEntry の中身を見る。single 時は data top を見る。
    pub def refresh(state: IdeState): Unit \ IO =
        match ResourceState.getPreviewLabelRef(state#resource) {
            case None => ()
            case Some(label) =>
                let drawn = tryDraw(state, label);
                if (drawn) ()
                else {
                    // setIcon(null) で「アイコンなし」にしたいが Flix で null 渡しが難しい。
                    // 透明な 1x1 アイコンに差し替えて "(no preview)" テキストを出す。
                    let blank = new BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB);
                    label.setIcon(new ImageIcon(blank));
                    label.setText("(no preview)");
                    label.setForeground(new Color(120, 120, 120));
                    ()
                }
        }

    /// preview が描画できれば true、できなければ false (caller が placeholder 表示)。
    def tryDraw(state: IdeState, label: JLabel): Bool \ IO =
        match (ResourceState.getEditingSchema(state#resource),
               ResourceState.getEditingJson(state#resource)) {
            case (Some(schema), Some(json)) =>
                // schema を walk して sprite-like nested path を探す
                let candidate = detectInSchema(Resource.fieldsOf(schema), Nil);
                match candidate {
                    case None => false
                    case Some(nestedPath) =>
                        // nestedPath を catalog 用の prefix と合わせて完全な keyPath にする
                        let fullPath = buildFullPath(state, json, nestedPath);
                        match fullPath {
                            case None => false
                            case Some(p) =>
                                match JsonOps.getAtKeyPath(json, p) {
                                    case Some(JsonObject(nested)) =>
                                        drawFromNested(state, nested, label)
                                    case _ => false
                                }
                        }
                }
            case _ => false
        }

    /// 再帰 walk で、TexturePathT + FrameGrid を含む Nested の **schema 上のパス**を返す。
    /// 例: schema = {sprite: nested{texture: TexturePathT, frame: FrameGrid, ...}}
    /// → Some(["sprite"])。
    def detectInSchema(fields: Map[String, FieldEntry], pathSoFar: List[String]):
            Option[List[String]] =
        // まず自分自身が sprite-like かチェック
        if (isSpriteLike(fields)) Some(pathSoFar)
        else
            // 子の Nested を再帰
            Map.foldLeftWithKey((acc, name, entry) ->
                match acc {
                    case Some(_) => acc
                    case None    =>
                        match entry {
                            case FieldEntry.Nested(childFields) =>
                                detectInSchema(childFields, pathSoFar ::: (name :: Nil))
                            case _ => None
                        }
                }, None, fields)

    /// nested が「TexturePathT 型のフィールド」と「IntT/FrameGrid ヒントのフィールド」を両方含むか。
    def isSpriteLike(fields: Map[String, FieldEntry]): Bool =
        let hasTexture = Map.exists((_, e) -> match e {
            case FieldEntry.Field(fs) =>
                match fs#ftype { case FieldType.TexturePathT => true case _ => false }
            case _ => false
        }, fields);
        let hasFrameGrid = Map.exists((_, e) -> match e {
            case FieldEntry.Field(fs) =>
                match fs#hint { case FieldHint.FrameGrid(_) => true case _ => false }
            case _ => false
        }, fields);
        hasTexture and hasFrameGrid

    /// schema 上の nested path に、catalog 時の prefix を付けて data JSON への完全パスに変換する。
    def buildFullPath(state: IdeState, dataJson: JsonElement, nestedPath: List[String]):
            Option[List[String]] \ IO =
        match ResourceCatalog.classify(dataJson) {
            case ResourceCatalog.Classification.CatalogIn(info) =>
                match ResourceState.getSelectedSubEntry(state#resource) {
                    case Some(key) => Some(info#containerKey :: key :: nestedPath)
                    case None      => None
                }
            case ResourceCatalog.Classification.Single        => Some(nestedPath)
            case ResourceCatalog.Classification.Unsupported(_) => None
        }

    /// nested object から texture / hframes / vframes / frame を取り出し、画像を切り出して JLabel に貼る。
    /// 「texture」「hframes」などのキー名は schema が決める動的なものなので、
    /// nested 内で各フィールドの値型から特定する。
    def drawFromNested(state: IdeState, nested: Map[String, JsonElement], label: JLabel): Bool \ IO =
        // schema を引いて、どのフィールドが TexturePathT / FrameGrid なのかを知る必要があるが、
        // 簡略化: nested の各値型から推定する (string=texture, int=hframes/vframes/frame)
        let textureNameOpt = nested |> Map.foldLeftWithKey((acc, _, v) ->
            match acc {
                case Some(_) => acc
                case None    => match v {
                    case JsonString(s) => Some(s)
                    case _             => None
                }
            }, None);
        // hframes / vframes / frame は frame > vframes > hframes の順で名前ヒューリスティック
        // (v1 妥協: 名前で引く)。schema を渡せばより厳密に。
        let hframes = readInt(nested, "hframes") |> Option.getWithDefault(1);
        let vframes = readInt(nested, "vframes") |> Option.getWithDefault(1);
        let frame   = readInt(nested, "frame")   |> Option.getWithDefault(0);
        match textureNameOpt {
            case None => false
            case Some(name) =>
                let texMap = IdeState.getTexturePathMap(state);
                match Map.get(name, texMap) {
                    case None => false
                    case Some(absPath) =>
                        drawSprite(absPath, hframes, vframes, frame, label)
                }
        }

    def readInt(m: Map[String, JsonElement], key: String): Option[Int32] =
        Map.get(key, m) |> Option.flatMap(v -> match v {
            case JsonNumber(bd) =>
                BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
            case _ => None
        })

    /// BufferedImage を読み、frame を切り出して 4 倍 NEAREST スケールで JLabel.setIcon する。
    /// 失敗時は false。File 存在チェックで try/catch を避ける。
    def drawSprite(absPath: String, hframes: Int32, vframes: Int32, frame: Int32, label: JLabel):
            Bool \ IO =
        let file = new File(absPath);
        if (not file.exists() or not file.isFile()) false
        else {
            let img = ImageIO.read(file);
            if (Object.isNull(img)) false
            else if (hframes <= 0 or vframes <= 0) false
            else {
                let w = img.getWidth();
                let h = img.getHeight();
                let frameW = w / hframes;
                let frameH = h / vframes;
                let col = Int32.modulo(frame, hframes);
                let row = frame / hframes;
                if (col < 0 or row < 0 or col >= hframes or row >= vframes) false
                else {
                    let sub = img.getSubimage(col * frameW, row * frameH, frameW, frameH);
                    // ×4 アップスケール (NEAREST)
                    let scaled = sub.getScaledInstance(frameW * 4, frameH * 4, Image.SCALE_FAST);
                    let icon = new ImageIcon(scaled);
                    label.setIcon(icon);
                    label.setText("");
                    true
                }
            }
        }
}
