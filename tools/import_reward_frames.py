#!/usr/bin/env python3
"""把 `相框-*.png` 裁成翻牌用的牌面。

    python tools/import_reward_frames.py

【两批牌面，别混】
  · `frame_back / frame_smug / frame_smirk / frame_late_love` —— **周结算翻牌**：
    欧式椭圆雕花相框，对应「首次当上龙套/配角/主角」赢来的那三套复杂表情。
  · `frame_starter_back / frame_blowup / frame_frog / frame_serious` —— **新手礼包**：
    拍立得相框（带红图钉），只在开场引导里翻一次，「爆缸笑脸 / 恶俗青蛙 / 严肃给力」三选一。
  两批画风不同是有意的：一个是"影棚里赢来的奖杯"，一个是"钉在墙上的旧照片"。

【为什么要裁】美术给的相框是 1920×1080 的整幅画布：相框只占**左边一块**
（alpha 包围盒见下面的 CROP 常量），右边一大片全透明。整张塞进游戏，
按贴图比例排三张时，卡片之间会出现一大段"看不见但占位"的空白 ——
三张牌会挤在屏幕左边，而不是均匀排开。

【为什么同批共用同一个裁剪框】背面与三张正面是同一套相框、同一个摆位
（包围盒逐像素相同）。各自算一遍包围盒，一旦某张多了根描边就会差 1~2 px，
翻面时会看到相框"跳一下"。写死一个框，四张永远对齐。

【输出】assets/ui/reward/，高度统一 760（三张并排时每张约 300 宽，1080p 下正好）。
"""

from pathlib import Path

from PIL import Image

SRC = Path(r"e:\GodotProjects\drama-queen\.document\package")
OUT = Path(r"e:\GodotProjects\drama-queen\assets\ui\reward")

OUT_HEIGHT = 760

# 周结算那批：欧式相框的包围盒（四张逐像素相同）
CROP = (41, 10, 869, 1064)
SOURCES = {
    "frame_back": "三个相框和空白脸.png",
    "frame_smug": "相框-每周-得意.png",
    "frame_smirk": "相框-每周-皮笑肉不笑.png",
    "frame_late_love": "相框-每周-已故爱人.png",
}

# 新手礼包那批：拍立得（含红图钉）的包围盒，四张同样逐像素相同
STARTER_CROP = (115, 50, 813, 992)
STARTER_SOURCES = {
    "frame_starter_back": "相框-问号回忆.png",
    "frame_blowup": "相框-爆缸笑脸.png",
    "frame_frog": "相框-恶俗青蛙.png",
    "frame_serious": "相框-严肃给力.png",
}


def _export(crop: tuple, sources: dict) -> None:
    w, h = crop[2] - crop[0], crop[3] - crop[1]
    scale = OUT_HEIGHT / h
    size = (round(w * scale), OUT_HEIGHT)
    print(f"裁剪框 {crop} → {w}×{h}  缩到 {size[0]}×{size[1]}")
    for name, src in sources.items():
        path = SRC / src
        if not path.exists():
            raise SystemExit(f"缺素材：{path}")
        img = Image.open(path).convert("RGBA").crop(crop)
        img = img.resize(size, Image.LANCZOS)
        img.save(OUT / f"{name}.png")
        print(f"  {name}.png  ←  {src}")
    print("")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    _export(CROP, SOURCES)
    _export(STARTER_CROP, STARTER_SOURCES)
    print(f"共 {len(SOURCES) + len(STARTER_SOURCES)} 张 → {OUT}")
    print("下一步：godot --headless --path <项目> --import")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
