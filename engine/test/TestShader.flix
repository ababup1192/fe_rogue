// TestShader — 宣言シェーダー機構のデータ層テスト（GL 不要・headless で回る）。
// 3 本柱: (1) Spec 木の値を assert、(2) compile が吐く GLSL 文字列を決定論スナップショットで pin、
// (3) CPU 評価器 evalPixel/evalField の代表点を pin。絵でなく「宣言データとその変換」を釘打ちする。
//
// スナップショットの粒度（後で崩すとスナップ総入れ替えになるので前提として固定）:
//   - prelude（hash2/worley/fbm の固定テンプレ）は長さだけ pin し本文は Spec スナップから除外する
//     （prelude 改訂は 1 テストだけ動く）。
//   - Spec 本体は compileBody（prelude 抜きの main 式）を pin する。
//   - 個々のノードの GLSL 片も compileBody で個別に pin（1 ノード変更→その pin だけ動く）。

// ════════════════════════════════════════════════════════════════════
// (1) Spec 木の値を assert（組んだ木が期待通りか）
// ════════════════════════════════════════════════════════════════════

/// demoSurface は 2 色 Ramp を Uv U で補間する Fill。
@Test
def testDemoSpecShape(): Unit \ Assert =
    let spec = ShaderDoc.demoSurface();
    let axis = match spec#out {
        case ShaderDoc.Out.Fill(f) => match f#shade {
            case ShaderDoc.Shade.Ramp(r) => match r#field {
                case ShaderDoc.Field.Uv(u) => Some(u#axis)
                case _ => None
            }
            case _ => None
        }
    };
    Assert.assertEq(expected = (Some(ShaderDoc.Axis.U), 0.5), (axis, spec#cycleRate))

/// waterVeins は Worley F2mF1 を Warp+Scaled でくるみ Smoothstep で目地に絞る。
/// 木の芯（Smoothstep → Warp → Scaled → Worley(F2mF1)）を辿って型で確認する。
@Test
def testWaterVeinsSpecShape(): Unit \ Assert =
    let spec = ShaderDoc.waterVeins();
    let worleyOut = match spec#out {
        case ShaderDoc.Out.Fill(f) => match f#shade {
            case ShaderDoc.Shade.Ramp(r) => match r#field {
                case ShaderDoc.Field.Smoothstep(s) => match s#of {
                    case ShaderDoc.Field.Warp(wp) => match wp#of {
                        case ShaderDoc.Field.Scaled(sc) => match sc#of {
                            case ShaderDoc.Field.Worley(w) => Some(w#out)
                            case _ => None
                        }
                        case _ => None
                    }
                    case _ => None
                }
                case _ => None
            }
            case _ => None
        }
    };
    Assert.assertEq(expected = Some(ShaderDoc.WorleyOut.F2mF1), worleyOut)

// ════════════════════════════════════════════════════════════════════
// (2) GLSL 文字列スナップショット（決定論・codegen 変更を検出）
// ════════════════════════════════════════════════════════════════════

/// Spec 本体を組む小道具（prelude 抜きの main 式を作るためのラッパ）。
def bodyOfField(field: ShaderDoc.Field): String =
    ShaderGen.compileBody({ name = "t", cycleRate = 0.0,
        out = ShaderDoc.Out.Fill({ shade = ShaderDoc.Shade.Solid({ r = 0.0f32, g = 0.0f32, b = 0.0f32 }),
                                   alpha = field }) })

/// prelude は長さだけ pin（本文は別扱い）。長さが変わったら prelude を触った合図。
@Test
def testPreludeLength(): Unit \ Assert =
    Assert.assertEq(expected = 2286, String.length(ShaderGen.preludeSource()))

/// demoSurface の main 式（prelude 抜き）。Ramp の三角波位相・Uv 展開まで含めて決定論で pin。
@Test
def testDemoBodySnapshot(): Unit \ Assert =
    let expected =
        "outColor = vec4(mix(vec3(0.15000000596046448, 0.3499999940395355, 0.550000011920929), " +
        "vec3(0.550000011920929, 0.8500000238418579, 0.949999988079071), " +
        "clamp(abs(fract(((vUv).x) + 0.5 * uTime) * 2.0 - 1.0), 0.0, 1.0)), 1.0);";
    Assert.assertEq(expected = expected, ShaderGen.compileBody(ShaderDoc.demoSurface()))

/// Worley(F2mF1) ノード単体の GLSL 片（prelude の sg_worleyF1F2 を呼ぶ形）。
@Test
def testWorleyNodeSnapshot(): Unit \ Assert =
    let field = ShaderDoc.Field.Worley({ scale = 6.0, seed = 42, out = ShaderDoc.WorleyOut.F2mF1 });
    let expected =
        "outColor = vec4(vec3(0.0, 0.0, 0.0), " +
        "(sg_worleyF1F2((vUv) * 6.0, 42.0).y - sg_worleyF1F2((vUv) * 6.0, 42.0).x));";
    Assert.assertEq(expected = expected, bodyOfField(field))

/// Fbm ノード単体の GLSL 片。
@Test
def testFbmNodeSnapshot(): Unit \ Assert =
    let field = ShaderDoc.Field.Fbm({ octaves = 2, scale = 3.0, seed = 5 });
    Assert.assertEq(expected = "outColor = vec4(vec3(0.0, 0.0, 0.0), sg_fbm((vUv) * 3.0, 2, 5.0));",
                    bodyOfField(field))

/// Smoothstep ノード（inner を包んで 0..1 に絞る）。
@Test
def testSmoothstepNodeSnapshot(): Unit \ Assert =
    let field = ShaderDoc.Field.Smoothstep({ lo = 0.0, hi = 0.06, of = ShaderDoc.Field.Const(0.03) });
    Assert.assertEq(expected = "outColor = vec4(vec3(0.0, 0.0, 0.0), smoothstep(0.0, 0.06, 0.03));",
                    bodyOfField(field))

/// Mix ノード（定数比 t で 2 場を混ぜる）。
@Test
def testMixNodeSnapshot(): Unit \ Assert =
    let field = ShaderDoc.Field.Mix({ a = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.U }),
                                      b = ShaderDoc.Field.Const(1.0), t = 0.5 });
    Assert.assertEq(expected = "outColor = vec4(vec3(0.0, 0.0, 0.0), mix((vUv).x, 1.0, 0.5));",
                    bodyOfField(field))

/// Disk ノード（丸マスク・radius→radius+feather で soft fade）。
@Test
def testDiskNodeSnapshot(): Unit \ Assert =
    let field = ShaderDoc.Field.Disk({ cx = 0.5, cy = 0.5, radius = 0.42, feather = 0.1 });
    Assert.assertEq(expected =
        "outColor = vec4(vec3(0.0, 0.0, 0.0), " +
        "(1.0 - smoothstep(0.42, 0.52, length((vUv) - vec2(0.5, 0.5)))));",
        bodyOfField(field))

// ════════════════════════════════════════════════════════════════════
// (3) CPU 評価器 evalPixel / evalField の代表点（数式の正気）
// ════════════════════════════════════════════════════════════════════

/// Uv U は u 座標をそのまま返す。
@Test
def testEvalUvU(): Unit \ Assert =
    Assert.assertEq(expected = 0.25,
        ShaderEval.evalField(ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.U }), { x = 0.25, y = 0.5 }, 0.0))

/// Smoothstep の中点（(lo+hi)/2 の入力）は 0.5。
@Test
def testEvalSmoothstepMidpoint(): Unit \ Assert =
    let field = ShaderDoc.Field.Smoothstep({ lo = 0.0, hi = 0.06, of = ShaderDoc.Field.Const(0.03) });
    Assert.assertEq(expected = 0.5, ShaderEval.evalField(field, { x = 0.0, y = 0.0 }, 0.0))

/// Mix(a=0.4, b=1.0, t=0.5) = 0.7。
@Test
def testEvalMix(): Unit \ Assert =
    let field = ShaderDoc.Field.Mix({ a = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.U }),
                                      b = ShaderDoc.Field.Const(1.0), t = 0.5 });
    Assert.assertEq(expected = 0.7, ShaderEval.evalField(field, { x = 0.4, y = 0.0 }, 0.0))

/// Scaled の scroll は時間で読む座標を動かす（t=0 で 0.2 が t=1 で 0.3 に流れる）。
/// = 「スクロールで模様が動く」ことの数式的な証拠。
@Test
def testEvalScaledScrollsWithTime(): Unit \ Assert =
    let field = ShaderDoc.Field.Scaled({ factor = 1.0, scroll = { x = 0.1, y = 0.0 },
                                         of = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.U }) });
    let at0 = ShaderEval.evalField(field, { x = 0.2, y = 0.0 }, 0.0);
    let at1 = ShaderEval.evalField(field, { x = 0.2, y = 0.0 }, 1.0);
    Assert.assertEq(expected = (0.2, true), (at0, at1 > at0))

/// Ramp の位相は cycleRate*t で回る（demoSurface の色が時間で変わる）。
/// 同じ uv でも t=0 と t=1 で色が違う = パレット循環の証拠。
@Test
def testEvalRampCyclesWithTime(): Unit \ Assert =
    let spec = ShaderDoc.demoSurface();
    // t=0: 位相=triWave(0.25)=0.5 / t=0.5: 位相=triWave(0.25+0.5*0.5)=triWave(0.5)=0.0（別の色）。
    let c0 = ShaderEval.evalPixel(spec, { x = 0.25, y = 0.5 }, 0.0);
    let c1 = ShaderEval.evalPixel(spec, { x = 0.25, y = 0.5 }, 0.5);
    Assert.assertEq(expected = true, c0#r != c1#r)

/// Worley F2mF1 は非負（境界＝目地で大きく・セル内で小さい）。代表点で正の値。
@Test
def testEvalWorleyNonNegative(): Unit \ Assert =
    let field = ShaderDoc.Field.Worley({ scale = 6.0, seed = 42, out = ShaderDoc.WorleyOut.F2mF1 });
    let v = ShaderEval.evalField(field, { x = 0.5, y = 0.5 }, 0.0);
    Assert.assertEq(expected = true, v >= 0.0 and v < 2.0)

/// waterVeins は Ramp 2 色の範囲内の色を返す（lo..hi の間・網目の濃淡）。
@Test
def testEvalWaterVeinsInRange(): Unit \ Assert =
    let c = ShaderEval.evalPixel(ShaderDoc.waterVeins(), { x = 0.3, y = 0.3 }, 0.0);
    let inRange = c#r >= 0.35f32 and c#r <= 0.80f32 and c#g >= 0.55f32 and c#g <= 0.95f32;
    Assert.assertEq(expected = true, inRange)

/// Disk: 中心=1・radius+feather の外=0・feather 中間=0.5。
@Test
def testEvalDisk(): Unit \ Assert =
    let d = ShaderDoc.Field.Disk({ cx = 0.5, cy = 0.5, radius = 0.42, feather = 0.1 });
    let center = ShaderEval.evalField(d, { x = 0.5, y = 0.5 }, 0.0);            // dist 0 → 1
    let outside = ShaderEval.evalField(d, { x = 1.1, y = 0.5 }, 0.0);          // dist 0.6 > 0.52 → 0
    let mid = ShaderEval.evalField(d, { x = 0.97, y = 0.5 }, 0.0);            // dist 0.47 = radius+feather/2 → 0.5
    // mid は smoothstep 中点だが浮動小数で 0.5 の近傍。中心=1・外=0・中間≈0.5 を確かめる。
    Assert.assertEq(expected = (true, true, true),
        (center == 1.0, outside == 0.0, Float64.abs(mid - 0.5) < 0.0001))

// ════════════════════════════════════════════════════════════════════
// (4) JSON 往復（検証ループ②・toJson→parse で木が保たれる・fail-open）
// ════════════════════════════════════════════════════════════════════

/// parse(toJson(waterVeins())) の木が保たれる（Smoothstep→Warp→Scaled→Worley(F2mF1) を辿る）。
@Test
def testJsonRoundTripShape(): Unit \ Assert =
    let worleyOut = match ShaderJson.parse(ShaderJson.toJson(ShaderDoc.waterVeins())) {
        case Ok(spec) => match spec#out {
            case ShaderDoc.Out.Fill(f) => match f#shade {
                case ShaderDoc.Shade.Ramp(r) => match r#field {
                    case ShaderDoc.Field.Smoothstep(s) => match s#of {
                        case ShaderDoc.Field.Warp(wp) => match wp#of {
                            case ShaderDoc.Field.Scaled(sc) => match sc#of {
                                case ShaderDoc.Field.Worley(w) => Some(w#out)
                                case _ => None
                            }
                            case _ => None
                        }
                        case _ => None
                    }
                    case _ => None
                }
                case _ => None
            }
        }
        case Err(_) => None
    };
    Assert.assertEq(expected = Some(ShaderDoc.WorleyOut.F2mF1), worleyOut)

/// 往復後の代表値（cycleRate=0.25 / Scaled factor=5.0 / scroll.x=0.11）を釘打ち。
@Test
def testJsonRoundTripValues(): Unit \ Assert =
    let got = match ShaderJson.parse(ShaderJson.toJson(ShaderDoc.waterVeins())) {
        case Ok(spec) => match spec#out {
            case ShaderDoc.Out.Fill(f) => match f#shade {
                case ShaderDoc.Shade.Ramp(r) => match r#field {
                    case ShaderDoc.Field.Smoothstep(s) => match s#of {
                        case ShaderDoc.Field.Warp(wp) => match wp#of {
                            case ShaderDoc.Field.Scaled(sc) => Some((spec#cycleRate, sc#factor, sc#scroll#x))
                            case _ => None
                        }
                        case _ => None
                    }
                    case _ => None
                }
                case _ => None
            }
        }
        case Err(_) => None
    };
    Assert.assertEq(expected = Some((0.25, 5.0, 0.11)), got)

/// 往復後の Spec を compile すると元と同じ GLSL（JSON 経由でも既存スナップショットが不変な担保）。
@Test
def testJsonRoundTripGlslIdentical(): Unit \ Assert =
    let spec = ShaderDoc.waterVeins();
    let same = match ShaderJson.parse(ShaderJson.toJson(spec)) {
        case Ok(s2) => ShaderGen.compile(s2) == ShaderGen.compile(spec)
        case Err(_) => false
    };
    Assert.assertEq(expected = true, same)

/// fail-open: 未知 kind の壊れ json は Err で返る（load 側が getWithDefault でフォールバックする前提）。
@Test
def testJsonParseErrorOnUnknownKind(): Unit \ Assert =
    let r = match Util.Json.parse("{\"name\":\"x\",\"out\":{\"kind\":\"bogus\"}}") {
        case Ok(j)  => Result.isErr(ShaderJson.parse(j))
        case Err(_) => false
    };
    Assert.assertEq(expected = true, r)

/// fail-open: 色や必須キー欠落も Err（"of" 欠落の smoothstep）。
@Test
def testJsonParseErrorOnMissingKey(): Unit \ Assert =
    let broken = "{\"name\":\"x\",\"out\":{\"kind\":\"fill\"," +
                 "\"shade\":{\"kind\":\"solid\",\"color\":\"#112233\"}," +
                 "\"alpha\":{\"kind\":\"smoothstep\",\"lo\":0.0,\"hi\":1.0}}}";
    let r = match Util.Json.parse(broken) {
        case Ok(j)  => Result.isErr(ShaderJson.parse(j))
        case Err(_) => false
    };
    Assert.assertEq(expected = true, r)

/// 色は "#rrggbb" でも {r,g,b} でも読める（hex 経路の往復）。
@Test
def testJsonHexColor(): Unit \ Assert =
    let json = "{\"name\":\"c\",\"out\":{\"kind\":\"fill\"," +
               "\"shade\":{\"kind\":\"solid\",\"color\":\"#ff8000\"}," +
               "\"alpha\":{\"kind\":\"const\",\"value\":1.0}}}";
    let got = match Util.Json.parse(json) {
        case Ok(j) => match ShaderJson.parse(j) {
            case Ok(spec) => match spec#out {
                case ShaderDoc.Out.Fill(f) => match f#shade {
                    case ShaderDoc.Shade.Solid(c) => Some((c#r, c#g, c#b))
                    case _ => None
                }
            }
            case Err(_) => None
        }
        case Err(_) => None
    };
    // #ff8000 → (1.0, 0.502..., 0.0)。中央値は 128/255 なので近い値で確かめる。
    let ok = match got {
        case Some((r, g, b)) => r == 1.0f32 and b == 0.0f32 and g > 0.49f32 and g < 0.51f32
        case None            => false
    };
    Assert.assertEq(expected = true, ok)

/// lavaVeins も JSON 往復で GLSL がバイト一致（Disk/Blend/Fbm/Warp 込みのフル語彙）。
@Test
def testLavaJsonRoundTripGlslIdentical(): Unit \ Assert =
    let spec = ShaderDoc.lavaVeins();
    let same = match ShaderJson.parse(ShaderJson.toJson(spec)) {
        case Ok(s2) => ShaderGen.compile(s2) == ShaderGen.compile(spec)
        case Err(_) => false
    };
    Assert.assertEq(expected = true, same)

/// lava の alpha は Disk（丸い溶岩溜まり）を Warp でくるんだ木（往復後も辿れる）。
@Test
def testLavaAlphaIsWarpDisk(): Unit \ Assert =
    let radius = match ShaderJson.parse(ShaderJson.toJson(ShaderDoc.lavaVeins())) {
        case Ok(spec) => match spec#out {
            case ShaderDoc.Out.Fill(f) => match f#alpha {
                case ShaderDoc.Field.Warp(wp) => match wp#of {
                    case ShaderDoc.Field.Disk(d) => Some(d#radius)
                    case _ => None
                }
                case _ => None
            }
        }
        case Err(_) => None
    };
    Assert.assertEq(expected = Some(0.42), radius)
