"""裁切录像机顶栏素材。

源图（美术给的两张 1920×1080 稿，放在 `.document/second/`，**不进导出包**）：

- `录像机界面-顶部.png`      —— 手绘长条 + 4 个状态图标
- `录像机界面-顶部-返回桌面.png` —— 左上角的黄色返回按钮

产出到 `assets/ui/recorder/`：

| 文件 | 内容 |
|---|---|
| `top_bar.png` | 只有纸面（4 个图标已被擦成底色），给 NinePatchRect 横向拉伸 |
| `stat_ap.png` / `stat_acting.png` / `stat_fame.png` / `stat_money.png` | 四个图标，背景保留条子的同色，叠回去无缝 |
| `back_button.png` | 返回按钮（透明底） |
| `back_button_hover.png` | 同一张纸向白色提亮 —— hover 态 |

【为什么要把图标从条子里挖出来】条子要铺满右栏宽度（≈1372），原图 1917 宽。
整条缩放会把 76px 的图标压成 54px 的扁片；分开之后图标按高度等比缩，纸面走九宫格拉伸，
只有中段纯色区被拉长，两端的手绘卷角保持原样。

重跑：`python tools/gen_recorder_header.py`（需要 Pillow），然后
`godot --headless --path . --import` 让引擎生成 .import。
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / ".document" / "second"
OUT = ROOT / "assets" / "ui" / "recorder"

# 条子的实际内容范围（整张稿 1929×1083，右侧与下方是空白）
BAR_RECT = (0, 0, 1917, 107)
# 返回按钮的 alpha 包围盒
BACK_RECT = (22, 5, 286, 96)

# 4 个图标的包围盒（已按与条底色的色差量过），顺序 = 闪电 / 面具 / 星星 / 金币
# 含义对齐主界面便利贴：行动点 / 演技 / 知名度 / 金钱
ICON_RECTS = {
    "stat_ap": (804, 13, 858, 89),
    "stat_acting": (1078, 16, 1142, 90),
    "stat_fame": (1334, 12, 1412, 90),
    "stat_money": (1640, 26, 1702, 89),
}
# 裁图标时向外留的余量：边缘带一点抗锯齿，留 6px 底色才不会出现一圈硬边
ICON_PAD = 6
# 条子的底色（取样自图标之间的空白处，整条中段就是这个值）
BAR_COLOR = (207, 207, 208, 255)


def _crop_with_pad(im: Image.Image, rect: tuple[int, int, int, int], pad: int) -> Image.Image:
    x0, y0, x1, y1 = rect
    return im.crop((max(0, x0 - pad), max(0, y0 - pad), x1 + pad, y1 + pad))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    bar_src = Image.open(SRC / "录像机界面-顶部.png").convert("RGBA")
    back_src = Image.open(SRC / "录像机界面-顶部-返回桌面.png").convert("RGBA")

    # ---- 图标：先按原图裁，再拿去擦条子 ----
    for name, rect in ICON_RECTS.items():
        _crop_with_pad(bar_src, rect, ICON_PAD).save(OUT / f"{name}.png")

    # ---- 条子：把图标按同一块矩形刷成底色 ----
    bar = bar_src.crop(BAR_RECT)
    for rect in ICON_RECTS.values():
        x0, y0, x1, y1 = rect
        px0, py0 = max(0, x0 - ICON_PAD), max(0, y0 - ICON_PAD)
        px1 = min(bar.width, x1 + ICON_PAD)
        py1 = min(bar.height, y1 + ICON_PAD)
        # 只刷图标所在的那块，不碰条子上下边缘的手绘阴影（图标 y 到 96，边缘在 99 以下）
        for y in range(py0, py1):
            for x in range(px0, px1):
                bar.putpixel((x, y), BAR_COLOR)
    bar.save(OUT / "top_bar.png")

    # ---- 返回按钮 + hover ----
    back = back_src.crop(BACK_RECT)
    back.save(OUT / "back_button.png")

    hover = back.copy()
    mix = 0.38  # 向白提亮的比例：再高红色叉会发粉
    px = hover.load()
    for y in range(hover.height):
        for x in range(hover.width):
            r, g, b, a = px[x, y]
            px[x, y] = (
                round(r + (255 - r) * mix),
                round(g + (255 - g) * mix),
                round(b + (255 - b) * mix),
                a,
            )
    hover.save(OUT / "back_button_hover.png")

    for p in sorted(OUT.glob("*.png")):
        with Image.open(p) as im:
            print(f"{p.relative_to(ROOT)}  {im.width}x{im.height}")


if __name__ == "__main__":
    main()
