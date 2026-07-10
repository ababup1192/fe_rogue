import javax.imageio.ImageIO;
import java.awt.*;
import java.awt.image.BufferedImage;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

/**
 * replay_tiles.py が出す scene.txt を実タイルセットで描画する（before/after を横並び）。
 *
 * scene.txt の行形式:
 *   PANEL <セル幅> <セル高> <タイトル...>   … パネル開始（タイトル先頭 BEFORE=赤帯 / AFTER=緑帯）
 *   TILE <x> <y> <チップ列> <チップ行>      … セル (x,y) にチップを重ね描き（記述順 = 重ね順）
 *   MARK <x> <y>                            … セル (x,y) に枠（BEFORE=赤 / AFTER=緑）
 *   END                                     … パネル終了
 *
 * 使い方: java WallSceneRender scene.txt tileset.png out.png
 */
public class WallSceneRender {
    static final int TILE = 26;

    static class Panel {
        String title;
        int w, h;
        List<int[]> tiles = new ArrayList<>();
        List<int[]> marks = new ArrayList<>();
    }

    public static void main(String[] args) throws Exception {
        List<String> lines = Files.readAllLines(Paths.get(args[0]), StandardCharsets.UTF_8);
        BufferedImage tileset = ImageIO.read(new File(args[1]));

        List<Panel> panels = new ArrayList<>();
        Panel cur = null;
        for (String line : lines) {
            String[] t = line.trim().split(" ");
            if (t[0].equals("PANEL")) {
                cur = new Panel();
                cur.w = Integer.parseInt(t[1]);
                cur.h = Integer.parseInt(t[2]);
                cur.title = String.join(" ", java.util.Arrays.copyOfRange(t, 3, t.length));
                panels.add(cur);
            } else if (t[0].equals("TILE")) {
                cur.tiles.add(new int[]{Integer.parseInt(t[1]), Integer.parseInt(t[2]),
                                        Integer.parseInt(t[3]), Integer.parseInt(t[4])});
            } else if (t[0].equals("MARK")) {
                cur.marks.add(new int[]{Integer.parseInt(t[1]), Integer.parseInt(t[2])});
            }
        }

        // ズームはパネルの大きさで自動選択（大きい領域は縮めて全体を見せる）
        int maxCells = panels.stream().mapToInt(p -> Math.max(p.w, p.h)).max().orElse(10);
        int zoom = maxCells <= 12 ? 5 : (maxCells <= 20 ? 3 : 2);

        int header = 40, gap = 10;
        int panelW = panels.stream().mapToInt(p -> p.w).max().orElse(1) * TILE * zoom;
        int panelH = panels.stream().mapToInt(p -> p.h).max().orElse(1) * TILE * zoom;
        BufferedImage out = new BufferedImage(panelW * panels.size() + gap * (panels.size() - 1),
                                              header + panelH, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = out.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setColor(new Color(24, 26, 30));
        g.fillRect(0, 0, out.getWidth(), out.getHeight());
        // 日本語混在テキストは論理フォント SansSerif だと一部グリフが欠けるので Hiragino を明示
        g.setFont(new Font("Hiragino Sans", Font.BOLD, 20));

        for (int i = 0; i < panels.size(); i++) {
            Panel p = panels.get(i);
            int ox = i * (panelW + gap);
            boolean isBefore = p.title.startsWith("BEFORE");
            g.setColor(isBefore ? new Color(140, 45, 45) : new Color(45, 120, 70));
            g.fillRect(ox, 0, panelW, header);
            g.setColor(Color.WHITE);
            g.drawString(p.title, ox + panelW / 2 - g.getFontMetrics().stringWidth(p.title) / 2, 27);
            g.setColor(new Color(18, 22, 16));
            g.fillRect(ox, header, panelW, panelH);
            for (int[] tile : p.tiles) {
                g.drawImage(tileset,
                    ox + tile[0] * TILE * zoom, header + tile[1] * TILE * zoom,
                    ox + (tile[0] + 1) * TILE * zoom, header + (tile[1] + 1) * TILE * zoom,
                    tile[2] * TILE, tile[3] * TILE, (tile[2] + 1) * TILE, (tile[3] + 1) * TILE, null);
            }
            g.setStroke(new BasicStroke(4));
            g.setColor(isBefore ? new Color(235, 70, 70) : new Color(70, 220, 120));
            for (int[] mark : p.marks) {
                g.drawRect(ox + mark[0] * TILE * zoom + 2, header + mark[1] * TILE * zoom + 2,
                           TILE * zoom - 4, TILE * zoom - 4);
            }
        }
        g.dispose();
        ImageIO.write(out, "png", new File(args[2]));
    }
}
