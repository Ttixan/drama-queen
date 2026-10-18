#!/usr/bin/env python3
"""把 `相框-每周-*.png` 裁成翻牌用的牌面（背面 + 三张正面）。

    python tools/import_reward_frames.py

【为什么要裁】美术给的相框是 1920×1080 的整幅画布：相框只占**左边一块**
（alpha 包围盒 41,10 → 869,1064），右边一大片全透明。整张塞进游戏，
按贴图比例排三张时，卡片之间会出现一大段"看不见但占位"的空白 ——
三张牌会挤在屏幕左边，而不是均匀排开。

【为什么四张共用同一个裁剪框】背面与三张正面是同一套相框、同一个摆位
（包围盒逐像素相同）。各自算一遍包围盒，一旦某张多了根描边就会差 1~2 px，
翻面时会看到相框"跳一下"。写死一个框，四张永远对齐。

【输出】assets/ui/reward/ 下四张：frame_back / frame_smug / frame_smirk /
frame_late_love，高度统一 760（三张并排时每张约 300 宽，1080p 下正好）。
"""

from pathlib import Path

from PIL import Image

SRC = Path(r"e:\GodotProjects\drama-queen\.document\package")
OUT = Path(r"e:\GodotProjects\drama-queen\assets\ui\reward")

# 四张图共用的相框包围盒（见 make_frames 的说明）
CROP = (41, 10, 869, 1064)
OUT_HEIGHT = 760

# 输出名 -> 源文件
SOURCES = {
    "frame_back": "三个相框和空白脸.png",
    "frame_smug": "相框-每周-得意.png",
    "frame_smirk": "相框-每周-皮笑肉不笑.png",
    "frame_late_love": "相框-每周-已故爱人.png",
}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    w, h = CROP[2] - CROP[0], CROP[3] - CROP[1]
    scale = OUT_HEIGHT / h
    size = (round(w * scale), OUT_HEIGHT)
    print(f"裁剪框 {CROP} → {w}×{h}  缩到 {size[0]}×{size[1]}")
    print("")

    for name, src in SOURCES.items():
        path = SRC / src
        if not path.exists():
            raise SystemExit(f"缺素材：{path}")
        img = Image.open(path).convert("RGBA").crop(CROP)
        img = img.resize(size, Image.LANCZOS)
        img.save(OUT / f"{name}.png")
        print(f"  {name}.png  ←  {src}")

    print("")
    print(f"共 {len(SOURCES)} 张 → {OUT}")
    print("下一步：godot --headless --path <项目> --import")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
