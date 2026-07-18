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
    ShaderGen.compileBody({ name = "t", cycleRate = 0.0, bindings = Nil,
        out = ShaderDoc.Out.Fill({ shade = ShaderDoc.Shade.Solid({ r = 0.0f32, g = 0.0f32, b = 0.0f32 }),
                                   alpha = field }) })

/// prelude は長さだけ pin（本文は別扱い）。長さが変わったら prelude を触った合図。
@Test
def testPreludeLength(): Unit \ Assert =
    Assert.assertEq(expected = 3167, String.length(ShaderGen.preludeSource()))

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

// ════════════════════════════════════════════════════════════════════
// (5) 素の代数（Bin/Un/Pow/Time）— 走査線を math2/math1/time だけで組む
// ════════════════════════════════════════════════════════════════════

/// 走査線の木を作る。scan = 0.5 + 0.5*sin(v*40 - uTime*3)。hash も floor も踏まない連続 sin。
def scanlineField(): ShaderDoc.Field =
    ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Add,
        a = ShaderDoc.Field.Const(0.5),
        b = ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Mul,
            a = ShaderDoc.Field.Const(0.5),
            b = ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.Sin,
                of = ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Sub,
                    a = ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Mul,
                        a = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.V }),
                        b = ShaderDoc.Field.Const(40.0) }),
                    b = ShaderDoc.Field.Time({ scale = 3.0,
                        offset = ShaderDoc.Field.Const(0.0) }) }) }) }) })

/// 走査線が Bin/Un/Time だけで書けて compileBody を pin（実装が最初に吐いた文字列を固定）。
@Test
def testScanlineBodySnapshot(): Unit \ Assert =
    let expected =
        "outColor = vec4(vec3(0.0, 0.0, 0.0), " +
        "(0.5 + (0.5 * sin((((vUv).y * 40.0) - (uTime * 3.0 + (0.0)))))));";
    Assert.assertEq(expected = expected, bodyOfField(scanlineField()))

/// 同じ木の CPU 代表点 pin。v=0.3, t=0.1 → 位相 = 40*0.3 - 3*0.1 = 11.7（連続 sin ＝ 安全）。
@Test
def testScanlineEval(): Unit \ Assert =
    let got = ShaderEval.evalField(scanlineField(), { x = 0.0, y = 0.3 }, 0.1);
    Assert.assertEq(expected = 0.5 + 0.5 * Vec2.sin(11.7), got)

// ════════════════════════════════════════════════════════════════════
// (6) Wave 2a: bindings（shared/use）＋ Tiling — 共有機構と座標のマス目化
// ════════════════════════════════════════════════════════════════════

// ripples プリミティブと同じ式を素の atom + bindings(wob) で書き下す（§3 の反射うねり線）。
//   freq=9, amp=0.24, speed=0.09, seed=7。厳密一致のため掛け算の順序と 2π 定数(6.2831853)を
//   プリミティブ（sg_ripples の CPU 版）とそっくり同じに畳む（浮動小数は結合則が成り立たないので）。
//   wob = sin(uv.x*6.2831853*9*0.5 + 7)*0.24 + sin(uv.x*6.2831853*9*1.3 + 18.9)*0.096
//   結果 = 0.5 + 0.5*sin((uv.y*9 + wob + t*0.09) * 6.2831853)。
def ripplesAtomField(): (List[(String, ShaderDoc.Field)], ShaderDoc.Field) =
    let tau = 6.2831853;
    let mul = (a, b) -> ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Mul, a = a, b = b });
    let add = (a, b) -> ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Add, a = a, b = b });
    let c = v -> ShaderDoc.Field.Const(v);
    let uvU = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.U });
    // sin(((uv.x * tau) * freq) * fracK + phase)。掛け順は sg_ripples に一致。
    let sinOf = (fracK, phase) ->
        ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.Sin,
            of = add(mul(mul(mul(uvU, c(tau)), c(9.0)), c(fracK)), c(phase)) });
    // 第 1 項 = sin(...)*amp、第 2 項 = (sin(...)*amp)*0.4（プリミティブの掛け順そのまま）。
    let wob = add(mul(sinOf(0.5, 7.0), c(0.24)),
                  mul(mul(sinOf(1.3, 18.900000000000002), c(0.24)), c(0.4)));
    // band = uv.y*9 + wob + t*0.09。alpha = 0.5 + 0.5*sin(band * tau)。
    let band = add(add(mul(ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.V }), c(9.0)),
                       ShaderDoc.Field.Ref("wob")),
                   ShaderDoc.Field.Time({ scale = 0.09, offset = c(0.0) }));
    let alpha = add(c(0.5), mul(c(0.5), ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.Sin,
        of = mul(band, c(tau)) })));
    (("wob", wob) :: Nil, alpha)

/// ② 素 atom + bindings(wob) で組んだ ripples が、プリミティブ Ripples と代表点で厳密一致する。
///   連続 sin なので hash/floor を踏まず assertEq で完全一致するはず（ズレたら式の写し間違い）。
@Test
def testRipplesAtomsMatchPrimitive(): Unit \ Assert =
    let uv = { x = 0.3, y = 0.4 };
    let t = 0.2;
    let (bindings, alpha) = ripplesAtomField();
    let spec = { name = "r", cycleRate = 0.0, bindings = bindings,
                 out = ShaderDoc.Out.Fill({
                     shade = ShaderDoc.Shade.Solid({ r = 1.0f32, g = 1.0f32, b = 1.0f32 }),
                     alpha = alpha }) };
    let atomVal = ShaderEval.evalAlpha(spec, uv, t);
    let prim = ShaderDoc.Field.Ripples({ freq = 9.0, amp = 0.24, speed = 0.09, seed = 7 });
    let primVal = ShaderEval.evalField(prim, uv, t);
    Assert.assertEq(expected = primVal, atomVal)

/// ③ Tiling ノードは inner uv を fract((vUv) * vec2(..,..)) に差し替える（初回出力を固定）。
@Test
def testTilingNodeSnapshot(): Unit \ Assert =
    let field = ShaderDoc.Field.Tiling({ tiles = { x = 8.0, y = 8.0 },
                                         of = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.U }) });
    Assert.assertEq(expected =
        "outColor = vec4(vec3(0.0, 0.0, 0.0), (fract((vUv) * vec2(8.0, 8.0))).x);",
        bodyOfField(field))

/// ④a 前方参照: 後の binding が前の binding を Ref して正しく評価される。
///   base=0.5 を wob=base+0.25 が参照 → alpha=use(wob)=0.75。
@Test
def testBindingForwardRef(): Unit \ Assert =
    let bindings =
        ("base", ShaderDoc.Field.Const(0.5)) ::
        ("wob", ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Add,
            a = ShaderDoc.Field.Ref("base"), b = ShaderDoc.Field.Const(0.25) })) :: Nil;
    let spec = { name = "f", cycleRate = 0.0, bindings = bindings,
                 out = ShaderDoc.Out.Fill({
                     shade = ShaderDoc.Shade.Solid({ r = 0.0f32, g = 0.0f32, b = 0.0f32 }),
                     alpha = ShaderDoc.Field.Ref("wob") }) };
    Assert.assertEq(expected = 0.75, ShaderEval.evalAlpha(spec, { x = 0.0, y = 0.0 }, 0.0))

/// ④b 循環（自己参照 or 後方参照）の JSON は parse で Err（fail-open で呼び側がフォールバック）。
@Test
def testBindingCircularIsErr(): Unit \ Assert =
    // "a" が自分自身を Ref（自己参照＝定義前の名前）→ Err。
    let json = "{\"name\":\"x\"," +
               "\"shared\":[[\"a\",{\"kind\":\"use\",\"name\":\"a\"}]]," +
               "\"out\":{\"kind\":\"fill\"," +
               "\"shade\":{\"kind\":\"solid\",\"color\":\"#000000\"}," +
               "\"alpha\":{\"kind\":\"const\",\"value\":1.0}}}";
    let r = match Util.Json.parse(json) {
        case Ok(j)  => Result.isErr(ShaderJson.parse(j))
        case Err(_) => false
    };
    Assert.assertEq(expected = true, r)

/// ④c 未定義 Ref（out が定義されていない名前を使う）の JSON は parse で Err。
@Test
def testUndefinedRefIsErr(): Unit \ Assert =
    let json = "{\"name\":\"x\"," +
               "\"out\":{\"kind\":\"fill\"," +
               "\"shade\":{\"kind\":\"solid\",\"color\":\"#000000\"}," +
               "\"alpha\":{\"kind\":\"use\",\"name\":\"ghost\"}}}";
    let r = match Util.Json.parse(json) {
        case Ok(j)  => Result.isErr(ShaderJson.parse(j))
        case Err(_) => false
    };
    Assert.assertEq(expected = true, r)

// ════════════════════════════════════════════════════════════════════
// (7) Wave 2b: Hash1/Hash2（bucket）— セル乱数
//   パリティの線引き（設計 §5）を厳守する:
//     floor/hash を踏む値を「GPU が出すはずの値」として assertEq しない。
//     許すのは「範囲が正気」「floor が段を刻んで値が変わる」「亜種が JSON で組める」だけ。
//   （GPU は f32/floor で境界の位置が CPU と別なので、CPU の hash/cyc 値が GPU と一致する
//     保証はない。ここでは GPU 一致を一切主張しない。）
// ════════════════════════════════════════════════════════════════════

/// 時間で乱数を選び直すための「バケツ」場: cyc = floor(uTime*0.5)。
/// （bucket にこれを入れると一定時間ごとに別の乱数へ切り替わる。）
def cycField(): ShaderDoc.Field =
    ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.Floor,
        of = ShaderDoc.Field.Time({ scale = 0.5, offset = ShaderDoc.Field.Const(0.0) }) })

/// ⑤ Hash1 の GLSL 片（bucket 無し/有り）。既存 sg_hash1 を呼ぶだけ（prelude は増えない）。
@Test
def testHash1NodeSnapshot(): Unit \ Assert =
    let none = ShaderDoc.Field.Hash1({ scale = 8.0, seed = 5, bucket = None });
    let buck = ShaderDoc.Field.Hash1({ scale = 8.0, seed = 5, bucket = Some(cycField()) });
    let expNone = "outColor = vec4(vec3(0.0, 0.0, 0.0), sg_hash1(floor((vUv) * 8.0), 5.0));";
    let expBuck = "outColor = vec4(vec3(0.0, 0.0, 0.0), " +
        "sg_hash1((floor((vUv) * 8.0) + (floor((uTime * 0.5 + (0.0))))), 5.0));";
    Assert.assertEq(expected = (expNone, expBuck), (bodyOfField(none), bodyOfField(buck)))

/// ⑤ Hash2 の GLSL 片（bucket 無し=comp u / bucket 有り=comp v）。
@Test
def testHash2NodeSnapshot(): Unit \ Assert =
    let none = ShaderDoc.Field.Hash2({ scale = 8.0, seed = 22, comp = ShaderDoc.Axis.U, bucket = None });
    let buck = ShaderDoc.Field.Hash2({ scale = 8.0, seed = 22, comp = ShaderDoc.Axis.V,
                                       bucket = Some(cycField()) });
    let expNone = "outColor = vec4(vec3(0.0, 0.0, 0.0), (sg_hash2(floor((vUv) * 8.0), 22.0)).x);";
    let expBuck = "outColor = vec4(vec3(0.0, 0.0, 0.0), " +
        "(sg_hash2((floor((vUv) * 8.0) + (floor((uTime * 0.5 + (0.0))))), 22.0)).y);";
    Assert.assertEq(expected = (expNone, expBuck), (bodyOfField(none), bodyOfField(buck)))

/// ⑥ hash1 の eval は代表点で 0..1 の範囲に収まる（範囲の正気のみ・GPU 一致は非主張）。
@Test
def testHash1Range(): Unit \ Assert =
    let field = ShaderDoc.Field.Hash1({ scale = 8.0, seed = 5, bucket = None });
    let v = ShaderEval.evalField(field, { x = 0.37, y = 0.62 }, 0.0);
    Assert.assertEq(expected = true, 0.0 <= v and v < 1.0)

/// ⑥ bucket=cyc（floor(uTime*k)）の Hash1 を、別々の時間バケツに落ちる 2 時刻で eval し、
///   「floor が段を刻んで値が変わる」ことだけ確かめる（値そのものは pin しない）。
///   t=0.0 → cyc=floor(0)=0、t=3.0 → cyc=floor(1.5)=1 で別セルの乱数になる。
///   GPU は f32/floor で境界が別位置なので、この CPU 値が GPU と一致するとは主張しない。
@Test
def testHashBucketSteps(): Unit \ Assert =
    let field = ShaderDoc.Field.Hash1({ scale = 8.0, seed = 5, bucket = Some(cycField()) });
    let uv = { x = 0.37, y = 0.62 };
    let vLow  = ShaderEval.evalField(field, uv, 0.0);   // cyc=0
    let vHigh = ShaderEval.evalField(field, uv, 3.0);   // cyc=1（段が 1 つ上がる）
    // 段が変われば hash の入力座標が変わるので値も変わる。範囲も両方 0..1 に収まる。
    let sane = 0.0 <= vLow and vLow < 1.0 and 0.0 <= vHigh and vHigh < 1.0;
    Assert.assertEq(expected = (true, true), (vLow != vHigh, sane))

/// ⑥ Hash1(bucket=cyc) を on、菱形（Pow）/丸（Un）で組んだ Sparkle 亜種を eval して
///   0.0 <= v の範囲に収まることだけ確かめる（＝亜種が JSON 語彙で組めることの実証）。
///   この亜種は bucket に floor(cyc) を通すので CPU パリティ（GPU との値一致）は適用外。
@Test
def testSparkleVariantEvalSane(): Unit \ Assert =
    // on = Hash1(bucket=cyc)、tw = pow(sat(sin(uTime)), 12)、point = 1 - sat(|uv.x-0.5|)。
    let on = ShaderDoc.Field.Hash1({ scale = 8.0, seed = 5, bucket = Some(cycField()) });
    let tw = ShaderDoc.Field.Pow({ p = 12.0,
        of = ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.Sat,
            of = ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.Sin,
                of = ShaderDoc.Field.Time({ scale = 1.0, offset = ShaderDoc.Field.Const(0.0) }) }) }) });
    let point = ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.OneMinus,
        of = ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.Sat,
            of = ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.Abs,
                of = ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Sub,
                    a = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.U }),
                    b = ShaderDoc.Field.Const(0.5) }) }) }) });
    let variant = ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Mul,
        a = ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Mul, a = on, b = tw }), b = point });
    let v = ShaderEval.evalField(variant, { x = 0.4, y = 0.6 }, 0.3);
    Assert.assertEq(expected = true, 0.0 <= v)

/// ⑦ hash 呼び出し回数 lint。生成 GLSL 中の sg_hash 出現数の上限を機械ガードする。
///   compileBody（prelude 抜き）で数える理由: prelude には sg_hash1/sg_hash2 の定義と内部呼びが
///   多数あり、そこを含めると Spec 側の展開数が測れない（prelude の定数に埋もれる）。
///   方式(b): 同じ hash 場を「binding で 1 回だけ計算して 2 か所で use する版」と
///   「2 か所に直書きする版」で作り、共有版の sg_hash 数 < 直書き版 を assert する。
///   閾値マジックナンバーを使わず、共有し忘れると sg_hash がテキスト増殖する footgun を直接示す。
@Test
def testHashCallCountBounded(): Unit \ Assert =
    let h = ShaderDoc.Field.Hash1({ scale = 8.0, seed = 5, bucket = Some(cycField()) });
    let mul = (a, b) -> ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Mul, a = a, b = b });
    // 直書き版: alpha = h * h（h を 2 か所に展開）→ sg_hash がテキストで 2 回出る。
    let inlinedSpec = { name = "inl", cycleRate = 0.0, bindings = Nil,
        out = ShaderDoc.Out.Fill({
            shade = ShaderDoc.Shade.Solid({ r = 0.0f32, g = 0.0f32, b = 0.0f32 }),
            alpha = mul(h, h) }) };
    // 共有版: binding "h" に 1 回だけ計算し、alpha = use(h) * use(h)。sg_hash はテキストで 1 回。
    let sharedSpec = { name = "shr", cycleRate = 0.0, bindings = ("h", h) :: Nil,
        out = ShaderDoc.Out.Fill({
            shade = ShaderDoc.Shade.Solid({ r = 0.0f32, g = 0.0f32, b = 0.0f32 }),
            alpha = mul(ShaderDoc.Field.Ref("h"), ShaderDoc.Field.Ref("h")) }) };
    let nInlined = countOccurrences("sg_hash", ShaderGen.compileBody(inlinedSpec));
    let nShared  = countOccurrences("sg_hash", ShaderGen.compileBody(sharedSpec));
    Assert.assertEq(expected = (true, true), (nShared < nInlined, nShared >= 1))

/// 部分文字列の非重複な出現回数を数える薄いヘルパ（見つけたら needle の長さだけ削って進む）。
def countOccurrences(needle: String, haystack: String): Int32 =
    def loop(rest, acc) =
        match String.indexOf({ substr = needle }, rest) {
            case Some(i) => loop(String.drop(i + String.length(needle), rest), acc + 1)
            case None    => acc
        };
    loop(haystack, 0)

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
