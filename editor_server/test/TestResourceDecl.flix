// TestResourceDecl — project.json の "editor" 宣言の読み取りと、
// パターン照合・スキーマパス規約・組み込み宣言を固定する。
// ファイル IO は一切無い純粋層なので、JSON 値を組み立ててそのまま食わせる。
// レコードは assertEq で直接比べられない (Eq/ToString が無い) ので、
// フィールドを並べたタプルに射影してから比べる。

mod TestResourceDecl {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString}

    /// Decl をタプル (id, pattern, title, schemaPath, plugin, builtin) に射影する。
    def declView(decl: ResourceDecl.Decl): (String, String, Option[String], Option[String], Option[String], Bool) =
        (decl#id, decl#pattern, decl#title, decl#schemaPath, decl#plugin, decl#builtin)

    /// DashboardDecl をタプル (id, title, plugin, uses) に射影する。
    def dashboardView(board: ResourceDecl.DashboardDecl): (String, Option[String], String, List[String]) =
        (board#id, board#title, board#plugin, board#uses)

    /// fromProjectJson の結果を (resources 射影列, dashboards 射影列) に直して返す。
    def decodedView(json: Json): Result[String, (List[(String, String, Option[String], Option[String], Option[String], Bool)],
                                                 List[(String, Option[String], String, List[String])])] =
        ResourceDecl.fromProjectJson(json)
            |> Result.map(decoded -> (List.map(declView, decoded#resources),
                                      List.map(dashboardView, decoded#dashboards)))

    // ══ fromProjectJson (宣言のデコード) ═══════════════════

    /// フル宣言のデコード。resources 2 件 (フル指定 + glob の最小指定) と dashboards 1 件。
    /// 2 件目は schema 省略 + glob pattern なので schemaPath は None のまま
    /// (一致ファイルごとの sibling 解決に委ねる)。
    @Test
    def testFromProjectJsonFull(): Unit \ Assert =
        let projectJson = JObject(Map#{
            "title"  => JString("shooter"),
            "editor" => JObject(Map#{
                "resources" => JArray(Vector#{
                    JObject(Map#{
                        "id"      => JString("level"),
                        "pattern" => JString("assets/level.json"),
                        "title"   => JString("レベル"),
                        "schema"  => JString("assets/level.schema.json"),
                        "plugin"  => JString("shooterLevel")
                    }),
                    JObject(Map#{
                        "id"      => JString("wave"),
                        "pattern" => JString("assets/*.wave.json")
                    })
                }),
                "dashboards" => JArray(Vector#{
                    JObject(Map#{
                        "id"     => JString("monsterBoard"),
                        "title"  => JString("モンスター一覧"),
                        "plugin" => JString("monsterBoard"),
                        "uses"   => JArray(Vector#{JString("monsters"), JString("weapons")})
                    })
                })
            })
        });
        Assert.assertEq(
            expected = Ok((
                   ("level", "assets/level.json", Some("レベル"),
                    Some("assets/level.schema.json"), Some("shooterLevel"), false)
                :: ("wave", "assets/*.wave.json", (None: Option[String]),
                    (None: Option[String]), (None: Option[String]), false)
                :: Nil,
                   ("monsterBoard", Some("モンスター一覧"), "monsterBoard",
                    "monsters" :: "weapons" :: Nil)
                :: Nil)),
            decodedView(projectJson))

    /// "editor" セクションが無い project.json は Err ではなく Ok(空) —
    /// 名乗っていないゲームも従来どおり編集できる。
    @Test
    def testFromProjectJsonNoEditor(): Unit \ Assert =
        Assert.assertEq(
            expected = Ok((Nil, Nil)),
            decodedView(JObject(Map#{"title" => JString("shooter")})))

    /// resources の要素に id が無いときは、どの項目かが分かる日本語 1 行の Err。
    @Test
    def testFromProjectJsonMissingId(): Unit \ Assert =
        let projectJson = JObject(Map#{
            "editor" => JObject(Map#{
                "resources" => JArray(Vector#{
                    JObject(Map#{"pattern" => JString("assets/level.json")})
                })
            })
        });
        Assert.assertEq(
            expected = Err("editor.resources[0] に id (文字列) がありません"),
            decodedView(projectJson))

    // ══ matchFiles (パターン照合) ══════════════════════════

    /// 照合の 4 形: 完全一致 ('*' 無し) / ディレクトリ内 glob / 拡張子二段の glob / 非マッチ。
    /// '*' は '/' をまたがないので、assets/*.level.json は assets/sub/… を拾わず、
    /// *.ui.json はてっぺん直下だけを拾う。
    @Test
    def testMatchFiles(): Unit \ Assert =
        let allPaths =
               "assets/level.json" :: "assets/level2.json"
            :: "assets/a.level.json" :: "assets/sub/b.level.json"
            :: "menu.ui.json" :: "assets/hud.ui.json" :: Nil;
        Assert.assertEq(
            expected = ("assets/level.json" :: Nil,
                        "assets/a.level.json" :: Nil,
                        "menu.ui.json" :: Nil,
                        (Nil: List[String])),
            (ResourceDecl.matchFiles("assets/level.json", allPaths),
             ResourceDecl.matchFiles("assets/*.level.json", allPaths),
             ResourceDecl.matchFiles("*.ui.json", allPaths),
             ResourceDecl.matchFiles("*.png", allPaths)))

    // ══ siblingSchemaPath (スキーマパス規約) ═══════════════

    /// データファイルの隣に .schema.json を置く規約: foo.json → foo.schema.json。
    @Test
    def testSiblingSchemaPath(): Unit \ Assert =
        Assert.assertEq(
            expected = "assets/level.schema.json",
            ResourceDecl.siblingSchemaPath("assets/level.json"))

    // ══ builtinDecls (組み込み宣言) ════════════════════════

    /// 組み込みは ui (*.ui.json) と hitbox (hitbox.json) の 2 件で、どちらも builtin = true。
    /// 専用プレビュー画面が受け持つので schemaPath / plugin は持たない。
    @Test
    def testBuiltinDecls(): Unit \ Assert =
        Assert.assertEq(
            expected =
                   ("ui", "*.ui.json", Some("UI"),
                    (None: Option[String]), (None: Option[String]), true)
                :: ("hitbox", "hitbox.json", Some("ヒットボックス"),
                    (None: Option[String]), (None: Option[String]), true)
                :: Nil,
            List.map(declView, ResourceDecl.builtinDecls()))
}
