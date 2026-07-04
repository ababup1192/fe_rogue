// EcsCodec のテスト。store / id 集合 / id Option の JSON 往復と、decode 失敗時の whole-None を固定する。

mod TestEcsCodec {

    use Util.Json.Json.{JNumber, JBool, JObject, JArray}

    def encInt(v: Int32): Util.Json.Json = JNumber(JsonCodec.intToBd(v))

    /// component store は encode→decode で元に戻る。
    @Test
    def testStoreRoundTrip(): Unit \ Assert =
        let store = Map#{1 => 10, 2 => 20, 3 => 30};
        Assert.assertEq(expected = Some(store),
            EcsCodec.decodeStore(JsonCodec.expectInt, EcsCodec.encodeStore(encInt, store)))

    /// id 集合（tag）の往復。
    @Test
    def testIdSetRoundTrip(): Unit \ Assert =
        let s = Set#{4, 8, 15};
        Assert.assertEq(expected = Some(s), EcsCodec.decodeIdSet(EcsCodec.encodeIdSet(s)))

    /// Option[EntityId]: None は false にエンコードされ、復元で None。
    @Test
    def testIdOptionNoneRoundTrip(): Unit \ Assert =
        Assert.assertEq(expected = None, EcsCodec.decodeIdOption(EcsCodec.encodeIdOption(None)))

    /// Option[EntityId]: Some(id) は数値で往復する。
    @Test
    def testIdOptionSomeRoundTrip(): Unit \ Assert =
        Assert.assertEq(expected = Some(7), EcsCodec.decodeIdOption(EcsCodec.encodeIdOption(Some(7))))

    /// 配列でない JSON は decodeStore で None（失敗時 whole-None 契約）。
    @Test
    def testDecodeStoreNonArrayIsNone(): Unit \ Assert =
        Assert.assertEq(expected = (None: Option[Map[EntityId, Int32]]),
            EcsCodec.decodeStore(JsonCodec.expectInt, JBool(false)))

    /// 配列だが値が型不一致の要素を1つでも含むと whole-None。
    @Test
    def testDecodeStoreBadElementIsNone(): Unit \ Assert =
        let bad = JArray(List.toVector(
            JObject(Map#{"id" => JNumber(JsonCodec.intToBd(1)), "v" => JBool(true)}) :: Nil));
        Assert.assertEq(expected = (None: Option[Map[EntityId, Int32]]),
            EcsCodec.decodeStore(JsonCodec.expectInt, bad))
}
