// NodeRegistry の挙動保存テスト（Phase A リファクタ）。
// 旧 ScenePanel の型リスト / 旧 SceneSerializer.defaultChildJson と完全一致することを保証する。
mod TestNodeRegistry {

    @Test
    def testAddableTypeNamesMatchesLegacyMenu(): Unit \ Assert =
        // 旧 buildAddChildMenu のハードコード順と同一
        Assert.assertEq(
            expected = "StaticBody2D" :: "RigidBody2D" :: "CharacterBody2D" ::
                       "Area2D" :: "ColorRect" :: "Marker2D" :: Nil,
            NodeRegistry.addableTypeNames())

    @Test
    def testDefaultJsonStaticBody2D(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"type\": \"StaticBody2D\", \"name\": \"wall\", \"pos\": [0, 0], \"shape\": {\"kind\": \"RectShape2D\", \"width\": 32, \"height\": 32}}",
            NodeRegistry.defaultJsonFor("StaticBody2D", "wall"))

    @Test
    def testDefaultJsonColorRect(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"type\": \"ColorRect\", \"name\": \"bg\", \"pos\": [0, 0], \"size\": [32, 16], \"color\": {\"r\": 1, \"g\": 1, \"b\": 1}}",
            NodeRegistry.defaultJsonFor("ColorRect", "bg"))

    @Test
    def testDefaultJsonRigidBody2D(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"type\": \"RigidBody2D\", \"name\": \"ball\", \"pos\": [0, 0], \"shape\": {\"kind\": \"CircleShape2D\", \"radius\": 8}}",
            NodeRegistry.defaultJsonFor("RigidBody2D", "ball"))

    @Test
    def testDefaultJsonCharacterBody2D(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"type\": \"CharacterBody2D\", \"name\": \"paddle\", \"pos\": [0, 0], \"shape\": {\"kind\": \"RectShape2D\", \"width\": 48, \"height\": 8}}",
            NodeRegistry.defaultJsonFor("CharacterBody2D", "paddle"))

    @Test
    def testDefaultJsonArea2D(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"type\": \"Area2D\", \"name\": \"trigger\", \"pos\": [0, 0], \"shape\": {\"kind\": \"RectShape2D\", \"width\": 32, \"height\": 16}}",
            NodeRegistry.defaultJsonFor("Area2D", "trigger"))

    @Test
    def testDefaultJsonMarker2DExplicit(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"type\": \"Marker2D\", \"name\": \"m\", \"pos\": [0, 0]}",
            NodeRegistry.defaultJsonFor("Marker2D", "m"))

    @Test
    def testEachEntryJsonContainsItsTypeName(): Unit \ Assert =
        // typeName と JSON 内 "type" のデシンクを防ぐ
        let ok = List.forAll(d ->
            String.contains({substr = "\"type\": \"${d#typeName}\""}, (d#defaultJson)("n")),
            NodeRegistry.entries());
        Assert.assertEq(expected = true, ok)

    @Test
    def testDefaultJsonUnknownFallsBackToMarker(): Unit \ Assert =
        // 旧 defaultChildJson の `_ => Marker2D` フォールバックと同一
        Assert.assertEq(
            expected = "{\"type\": \"Marker2D\", \"name\": \"x\", \"pos\": [0, 0]}",
            NodeRegistry.defaultJsonFor("NoSuchType", "x"))
}
