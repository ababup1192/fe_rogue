# Shader Gallery — 朝の審査ブリーフ

起動: `cd examples/shader_gallery && DEBUG=true flix run`  (矢印=パン / ホイール=ズーム / 各JSON保存で即反映)

全13枚コンパイル通過。色は有名パレット固定。以下、技法と朝に触る調整ノブ。自信度 A=そのままいけそう / B=要一見。


## 水 (7)

### caustic pond  `water_caustic_pond.shader.json`
パレット=トロピカル・ターコイズ(暗深水→水色→泡)。技法: 主役はゆっくり流れる warp+scaled+fbm の下地(coherent な水面)。コースティクスは Worley f2mf1 を smoothstep+pow で光の網に締め、係数0.24 の控えめ上乗せ(支配させない=抽象画回避)。深さのグラデは v 軸 smoothstep で暗い深→明るい浅を演出。自信度=A。朝の調整ノブ: (1)caustics 係数0.24 を上げると光の網が強く出る(0.35 超で模様寄りに崩れるので上げ過ぎ注意)、(2)pow の p=2.6 を上げると網が細く鋭く・下げると滲む、(3)flow の scroll(x0.012/y0.02)を上げると流れが速くなる、(4)flow 係数0.72 を下げ深さグラデ0.24 を上げると深浅コントラストが強まる、(5)gradient stops の位置(特に0.6→0.82)を詰めると浅瀬の泡が広がる。

### still pond  `water_gentle_pond.shader.json`
パレット=Nord frost/polar(#2e3440暗→#88c0d0水色)。技法=fbmの二重warp下地(flow=主流れ+rippleLace=直交する二次のさざなみで単調さを崩す)を主役に、縦vの深さグラデ(下=深く暗い/上=浅く明るい)、稀に控えめなsparkle煌めき(pow3.5で尖らせ点に絞る)。カオスはWorleyを使わず全てfbmで抑え、静かでcoherentな止水に。自信度=A。朝の調整ノブ: flowのamount(0.05)↑でうねり強/↓でよりガラス面。scrollのx/y(0.010/0.006)↑で流れ速。sparkleのdensity(0.04)↑で煌めき増/rate(0.30)↑で瞬き速。深さ帯はuv-v項の係数(0.18)↑で上下コントラスト強。rippleLaceのmul係数(0.10)↑でさざなみ目立つ。gradient中間#5e81acの位置(0.55)を下げると水面が明るく浅く見える。

### river  `water_river.shader.json`
パレット=北斎の藍(#0a2540→#81c3d7)。技法=強く warp した方向スクロール fbm フロー(scroll.x=0.16 で主に横流れ)を主役の下地にし、深さのグラデを効かせて coherent な水面に。上に細いリッジ状の水筋(1-|2x-1| を smoothstep+pow で締めた"streaks")を控えめに乗せ、光の走る筋を演出。カオスは fbm octaves を 2-3 に抑え抽象画化を回避。自信度=B(coherent な流れは出るが、streaks を強めると模様寄りになるので控えめ固定)。朝の調整ノブ: (1)flow.of.scaled.scroll.x を上げると横の流速が速くなる(0.16→0.24 でぐっと流れる)。(2)streaks の係数 0.24 を下げると水筋が消えて静かな水面、上げると光の筋が目立つ(0.35 超で模様化注意)。(3)pow.p=2.6 を上げると水筋が細く鋭く、下げると太く柔らかく。(4)flow.warp.amount=0.22 を上げるとうねりが増える(0.3 超でカオス化)。(5)gradient の 0.0/1.0 stop を差し替えると深→浅の色域が変わる。

### murky swamp  `water_swamp.shader.json`
パレット=沼/オリーブ(#14200f→#8fbc8f)。技法=遅い warp+scaled で fbm をゆっくり漂わせた下地(current)を主役にし、別 fbm の澱み(silt)を中心0.5基準の弱い明暗として上乗せ、worley f1 の斑は smoothstep(0.72-0.94)で拾って係数0.14まで絞り込みほぼ囁き程度に。深→浅のグラデで沈んだ緑褐色。カオスを抑え coherent な流れを守った。自信度=B(沼として静かで濁った質感は出たが、specks がやや点在的。真の泥水にはもう少し silt を主張させたい)。朝の調整ノブ: (1)current の warp.amount(0.06)を上げると流れがうねり乱れる/下げると鏡のように静まる。(2)current 係数0.66を上げると全体が明るく浅い水面、下げると暗く深い澱み。(3)specks 係数0.14を上げると水面の光る泡・浮遊物が目立つ/0にすると完全に消える。(4)scaled.scroll(current の x0.012 y0.008)を上げると流れが速く、下げると遅い。(5)silt 係数0.22を上げると濁りムラが濃くなる。

### shallow  `water_shallow.shader.json`
パレット=トロピカル・ターコイズ(明るい側 #1b98a0→#3fc5c0→#a8e6cf→#dff6f2)+砂色 #d9c9a3 を最下 stop に。技法=fbm を warp+scaled でゆっくり流す coherent な下地(0.5 重み)を主役にし、深さのグラデ(oneMinus(uv v)=上ほど明るい浅瀬・0.24)を足し、Worley f1 の oneMinus を smoothstep+pow で締めたコースティクス光網を控えめ(0.4)に上乗せ。カオスを抑え『静かで coherent な水』を優先。自信度=A。朝の調整ノブ: (1)caustics 係数 0.4 を上げると光網が強く(下げると穏やか)、pow の p=2.4 を上げると光点が細く鋭くなる。(2)深さ係数 0.24 を上げると上下の明暗差(浅深感)が強調される。(3)flow の scaled.factor=2.4 を下げると模様が大きくゆったり、scroll x/y を上げると流れが速くなる。(4)最下 stop の砂色 #d9c9a3 の位置 0.0→0.1 を動かすと底砂の透け具合が変わる。(5)gradient の 0.26 の stop を左右すると水色が浅瀬側に寄る/沖側に寄る。

### deep lake  `water_deep_lake.shader.json`
パレット=深海(#04121f→#2e6f95)。技法=fbmをwarpした緩いswell下地+uvのvで深さグラデ(depth: smoothstepで下ほど明るい浅瀬)+ゆっくりした横縞のsin脈動+pow(3.5)で絞ったsparkleをまれな遠い煌めきとして極少量上乗せ。カオスを抑えcoherentな静水を優先。自信度=A。朝の調整ノブ: (1)swellのconst0.22↑でうねりの主張が増す/↓でより鏡面の静水に。(2)depthのconst0.42で上下の明暗差(深さ感)、↑で浅瀬が明るく立体的。(3)glintのconst0.45とsparkleのdensity0.015で煌めきの量、↓で更に静謐に。(4)sin脈動のconst0.08とtime.scale0.3で表面のうねる速さ、time.scaleを下げるとより緩慢に。(5)swellのscroll(x0.006,y0.009)で流れの向きと速さ。

### ice  `water_ice.shader.json`
パレット=Nord(polar #2e3440/#434c5e→frost #5e81ac/#81a1c1/#88c0d0→snow #eceff4)。技法=Fbmをゆっくり流れる下地(flow)にして氷盤の厚みムラを出し、その上にWorley F2-F1をひび割れ(cracks)としてsmoothstep+powで細く発光させ、sparkleを極控えめに霜のきらめきとして上乗せ。動きは最小(scroll極小)で凍って静止した水面に見せる。自信度=B(coherentな下地+締めたひびで水/氷らしさは出たが、ひび発光がやや強いと模様寄りに転ぶ境目)。朝の調整ノブ: (1)cracksのmul係数0.46=ひびの主張(上げると割れ目くっきり氷、下げるとのっぺり湖面)。(2)smoothstepのhi0.13=ひびの太さ(下げると細く鋭く、上げると太くにじむ)。(3)flowのmul係数0.5と下地const0.5=全体の明るさ/コントラスト(下げると暗い深氷、上げると白い薄氷)。(4)sparkleのmul0.12=霜のきらめき量(上げすぎるとノイズっぽく散る)。(5)scaledのscroll値=流れの速さ(0にすると完全静止、上げると溶けかけの動き)。


## マグマ (6)

### cracked crust  `magma_cracked.shader.json`
パレット=matplotlib Inferno(黒→紫→赤→橙→黄白)。技法=Worley F2-F1 の割れ目ネットワーク(voronoi crack)を warp+scaled でゆっくりうねらせ、smoothstep+pow で発光帯を締め、sin の脈動(pulse)で明滅、fbm(heat)で熱ムラを足し、細い高温コア(core)を最深部に上乗せ。自信度=A。朝の調整ノブ: (1)cracks.warp.amount(0.15) を上げると割れ目がうねって荒れる/下げると整然。(2)glow の smoothstep.hi(0.14) を下げると発光帯が細く鋭くなる/上げると太くにじむ。(3)pulse の const 0.40 が明滅の深さ、time.scale 1.5 が明滅の速さ。(4)core の smoothstep.hi(0.085) を上げると白熱コアが太くなる。(5)heat の *0.30 係数(下の const)を上げると熱ムラが強く粒だつ。

### molten flow  `magma_bright_flow.shader.json`
パレット=matplotlib Magma(黒→紫→桃→橙→淡黄)。技法=fbm を二段 warp(粗2.2+細4.8)で溶けた流れを主役にし、pow1.5 で明部を伸ばす。割れ目は Worley F2-F1 を軽く warp(0.1)して硬すぎない発光線に、smoothstep+pow2.4 で細く締めて上乗せ。heat 用 fbm を薄く(0.16)足して熱ムラ、sin(1.7) で全体を脈動。自信度=A。朝に触るノブ: flow の外側 warp.amount(0.24)=大きいほど流れが渦巻く/小さいと素直、scroll.y(0.12)=流れる速さ、cracks の smoothstep.hi(0.11)=小さいほど割れ目が細く鋭い/大きいと太く滲む、cracks の上乗せ係数(0.42)=割れ目の明るさ、time.scale(1.7)=脈動の速さ、gradient の 0.52 の桃色ストップ位置=色の温度感(左へ寄せると熱く)。

### bubbling  `magma_bubbling.shader.json`
パレット=matplotlib Inferno(黒→紫→赤→橙→黄白)。技法: (1)Worley F2-F1 の割れ目ネットワークを warp でうねらせ smoothstep+pow で発光帯に。(2)下から昇る熱波は sin(v*11 - time*2.4) で溶岩が沸き上がる縦スクロール。(3)新規の blobs レイヤ=別seed Worley F1 を warp で丸い泡塊にし、pow3 で締めて時間 sin で膨張収縮させ『ぐつぐつ煮える気泡』を上乗せ。(4)Fbm heat で全体の熱ムラ。自信度=A。朝の調整ノブ: blobs の time.scale(3.2)を上げると泡の沸きが速く/下げると緩慢に。blobs の pow.p(3.0)を上げると泡が小さく点状・下げると大きく溶け合う。cracks の warp.amount(0.17)を上げると割れ目がうねうね・下げると硬い。熱波の time.scale(2.4)で上昇速度、uv係数11.0で縞の細かさ。全体を暗くしたいなら base の const 0.56 を下げる。

### obsidian  `magma_obsidian.shader.json`
パレット=Inferno低域+Magma(黒#000004→暗紫#180f3e→紫#451077→#721f81→桃紫#9f2f7f)。技法=Worley F2-F1でひび網を作り、warp(0.085)でうねらせ、scaled+微scrollでほぼ静止した冷えゆく面に。ひびをsmoothstep(hi=0.075)+pow(3.0)で細い残光線だけ抜き出し、sin(scale0.45)のゆっくりした脈動breathで明滅。二段目のsmoothstep(0.02-0.28)+pow1.6で割れ目のほのかな地明かり、fbmで熱ムラ。自信度=A。朝の調整ノブ: emberのsmoothstep.hi(0.075)を上げると残光線が太く明るく/下げると更に消えかけ。pow.p(3.0)を上げると線が細く鋭く。breathのtime.scale(0.45)で明滅の速さ。gradient最終stop#9f2f7fを暗赤系(#4a0c6b等)にすると残光の色味が青紫→赤へ寄る。fbm係数0.05で熱ムラ量、cracksのwarp.amount(0.085)でひびのうねり。全体をもっと暗くするなら0.45/0.55のbreath基準を下げる。

### ember field  `magma_embers.shader.json`
パレット=matplotlib Inferno(黒#000004→藍紫#1b0c41→赤紫#781c6d→橙#ed6925→黄橙#fb9b06→淡黄#f7d13d)。技法=(1)drift: fbmをwarp+scaledでゆっくり流し暗い岩の熱ムラ下地(寄与0.15と控えめ)、(2)cinder: Worley F1をwarpで歪めsmoothstep(0.66-0.99)+pow3.6で点状に絞り、疎らに散る火の粉の芯を作る、(3)twinkle: sin×uv横位相で場所ごとにずれる明滅を掛け火の粉を点滅発光させる。cinder×twinkleが主役の発光、driftが下地。自信度=A。朝の調整ノブ: cinderのsmoothstep lo(0.66)を上げると火の粉が減って疎に・下げると増える/pow(3.6)を上げると粒が小さく鋭く/twinkleのtime.scale(3.6)で明滅の速さ/const22.0相当の24.0で明滅の空間的まばらさ/driftのb=0.15を上げると岩の熱ムラが明るく主張。"}

Wait, I included an invalid "spark" entry. Let me output the corrected raw JSON only.

{"name":"m_embers

### molten metal  `magma_molten_metal.shader.json`
パレット=ブラックボディ金属(黒→暗赤→橙→白熱)。技法=fbm(oct4)をwarpでうねらせた滑らかな流れ`flow`を主役の下地にし、smoothstep+pow2.4で反射のホットバンドを鋭く締め(金属の高反射感)、そこにflow位相を注いだsin脈動で表面が「溶けて流れる」動きを付与。さらにflow自身を弱めた下駄で溶湯の厚みムラを出し、細かいfbmを微量上乗せして白熱スパッタのざらつきを足した。gradientは0.55→0.8を橙〜金の帯に寄せて発光の芯を太く。自信度=A。朝の調整ノブ: (1)smoothstepのlo/hi(0.36/0.60)=幅を狭めるほど明暗のバンドが鋭く金属光沢が強まる/広げると溶岩寄りに柔らかく。(2)pow.p(2.4)=上げると暗部が締まりハイライトが点在、下げると全体が明るくのっぺり。(3)sinのscale(1.1)=脈動の速さ。sin振幅(0.26)=明滅の強さ。(4)flow.warp.amount(0.14)=流れのうねり量、上げると渦巻き感。(5)flow.scroll.y(0.038)=溶湯が下へ流れる速さ。(6)白熱スパッタfbmのmul係数(0.20)=上げるとザラつき増、下げると鏡面的に。
