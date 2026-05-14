// RenderTexture — テクスチャ読み込み (STBImage + OpenGL アップロード)
//
// LwjglLayer.flix の loadTexture / loadTextureRegistry を移植。

mod RenderTexture {
    import org.lwjgl.opengl.GL11
    import org.lwjgl.stb.STBImage
    import org.lwjgl.system.MemoryStack

    /// PNG/JPG など STBImage がサポートする画像をロードし、OpenGL テクスチャとして
    /// アップロードする。NEAREST フィルタ + REPEAT ラップ (ピクセルアート前提)。
    pub def loadTexture(path: String, alpha: Bool): RenderAsset.TextureInfo \ IO =
        let stack = MemoryStack.stackPush();
        let w = stack.mallocInt(1);
        let h = stack.mallocInt(1);
        let c = stack.mallocInt(1);
        STBImage.stbi_set_flip_vertically_on_load(false);
        let channels = if (alpha) 4 else 3;
        let data = STBImage.stbi_load(path, w, h, c, channels);
        if (Object.isNull(data)) {
            discard MemoryStack.stackPop();
            bug!("Failed to load texture: ${path}")
        } else {
            let texWidth = w.get(0);
            let texHeight = h.get(0);
            let textureID = GL11.glGenTextures();
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, textureID);
            let format = if (alpha) GL11.GL_RGBA else GL11.GL_RGB;
            GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, format, texWidth, texHeight, 0, format, GL11.GL_UNSIGNED_BYTE, data);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_S, GL11.GL_REPEAT);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_T, GL11.GL_REPEAT);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
            STBImage.stbi_image_free(data);
            discard MemoryStack.stackPop();
            { id = textureID, width = Int32.toFloat64(texWidth), height = Int32.toFloat64(texHeight) }
        }

    /// テクスチャマニフェストから全テクスチャを読み込み、論理名 → TextureInfo の
    /// マップを返す。
    pub def loadTextureRegistry(manifest: List[RenderAsset.TextureEntry]): RenderAsset.TextureRegistry \ IO =
        List.foldLeft((registry, entry) -> {
            let texInfo = loadTexture(entry#path, entry#hasAlpha);
            println("  ${entry#path} loaded (${texInfo#width}x${texInfo#height})");
            Map.insert(entry#name, texInfo, registry)
        }, Map.empty(), manifest)

}
