#!/usr/bin/env python3
"""把美术导出的表情图层合成为录像机的部件图（512 共用画布）。

    python tools/import_emoji_layers.py

【为什么需要这个脚本】美术给的是 .psd 的**逐图层导出**：每张 PNG 都裁到了
图层自己的包围盒（眼睛 581×94、嘴 352×236…），**位置信息不在图里**。
而录像机的四层叠加要求「所有部件共用一张画布、坐标一致」—— 直接把这些图
改名塞进 assets/parts/ 会全部叠在左上角。

位置在 .document 里那份 index.html 的 figcaption 上（"726×905 · 坐标(541,333)"），
它就是导出工具顺手写的图层清单。本脚本读它，把每张图按原坐标摆回 1748 画布，
再整体等比缩到 512×512，于是四层自然重合。

【输出规格 —— 与 tools/gen_placeholder_art.gd 定下的接口一致】
    512 × 512，透明 PNG，**人脸中心 = 画布中心**，脸占画布高度的 94%。

【映射表为什么是「挑着用」】素材是 14 套完整表情，而部件池是 12 眼 / 14 嘴 / 12 眉
+ 6 配件 + 9 肤色 ——
每套的眉/眼/嘴是一起画的，摆进槽位后玩家仍可跨套混搭（位置本来就对齐）。
挑选原则是**表情名对得上既有部件的情绪梯度**（见 tools/part_catalog.gd）：
「喜悦的眼睛」就是 tier 4 的「眯笑」，「愤怒的眉毛」就是 tier 4 的「倒竖」。
【10-18 起 14 套全部进池】剩下的「得意 / 皮笑肉不笑 / 想起已故的爱人 / 爆缸笑脸 /
绿豆蛙」按套补齐（一套三件同周解锁，见 part_catalog.gd 的 `week`），
不再有「用不上的四套」。
"""

import html
import re
from pathlib import Path

from PIL import Image, ImageChops

SRC = Path(r"e:\GodotProjects\drama-queen\.document\所有表情-细化版_图层导出")
OUT = Path(r"e:\GodotProjects\drama-queen\assets\parts")

CANVAS = 512
FACE_FILL = 0.94          # 脸占画布高度的比例；留一圈边，描边不会被裁掉
FACE_OUTLINE = "空白脸  - 脸部轮廓.png"   # 定中心用的那张（文件名里是两个空格）

# 部件 id -> 图层文件名。左边的 id 见 tools/part_catalog.gd
SOURCES = {
    # 眼 12：平静 → 睁大 → 瞪 → 含泪 → 眯笑 → 星星眼 → 死鱼眼 → 泪如雨下
    #        → 斜睨(得意) → 死笑(皮笑肉不笑) → 笑崩(爆缸笑脸) → 蛙眼(绿豆蛙)
    "eyes_00": "信任 - 眼睛.png",
    "eyes_01": "惊讶 - 眼睛.png",
    "eyes_02": "愤怒 - 眼睛1.png",
    "eyes_03": "悲伤（忧愁） - 眼睛.png",
    "eyes_04": "喜悦 - 眼睛.png",
    "eyes_05": "期待 - 眼睛.png",
    "eyes_06": "厌恶 - 眼睛.png",
    "eyes_07": "想起已故的爱人 - 眼睛.png",
    # 10-18 补齐：这三套以前只进了嘴/眼，现在按套补齐（另一条腿见下面的嘴、眉）
    "eyes_08": "得意 - 眼.png",
    "eyes_09": "皮笑肉不笑 - 眼睛.png",
    "eyes_10": "爆缸笑脸 - 眼睛.png",
    "eyes_11": "绿豆蛙 - 眼睛.png",
    # 10-20 补缺：恐惧眼（8 基础补全）、愤怒第二张变体、认真脸眼
    "eyes_12": "恐惧 - 眼睛.png",
    "eyes_13": "愤怒 - 眼睛2.png",
    "eyes_14": "认真脸 - 眼睛.png",
    # 嘴 14：认真脸 → 惊讶 → 信任 → 喜悦 → 期待 → 厌恶 → 恐惧 → 愤怒 → 悲伤忧愁
    #        → 得意 → 皮笑肉不笑 → 苦笑(想起已故的爱人) → 笑崩 → 蛙嘴
    "mouth_00": "认真脸 - 嘴巴.png",
    "mouth_01": "惊讶 - 嘴巴.png",
    "mouth_02": "信任 - 嘴.png",
    "mouth_03": "喜悦 - 嘴.png",
    "mouth_04": "期待 - 嘴.png",
    "mouth_05": "厌恶 - 嘴巴.png",
    "mouth_06": "恐惧 - 嘴.png",
    "mouth_07": "愤怒 - 嘴巴.png",
    "mouth_08": "悲伤（忧愁） - 嘴巴.png",
    "mouth_09": "得意 - 嘴巴.png",
    # 10-17 新增：素材里本来就有这套，只是当时没进池子
    "mouth_10": "皮笑肉不笑 - 嘴巴.png",
    "mouth_11": "想起已故的爱人 - 嘴巴.png",
    "mouth_12": "爆缸笑脸 - 嘴.png",     # 这套里是「嘴」不是「嘴巴」
    "mouth_13": "绿豆蛙 - 嘴巴.png",
    # 眉 12：舒展 → 上挑 → 高扬 → 紧锁 → 倒竖 → 八字 → 微蹙 → 斜挑
    #        → 皮笑肉不笑 → 想起已故的爱人 → 爆缸笑脸 → 绿豆蛙
    "brows_00": "信任 - 眉毛.png",
    "brows_01": "期待 - 眉毛.png",
    "brows_02": "惊讶 - 眉毛.png",
    "brows_03": "厌恶 - 眉毛.png",
    "brows_04": "愤怒 - 眉毛.png",
    "brows_05": "悲伤（忧愁） - 眉毛.png",
    "brows_06": "恐惧 - 眉毛.png",
    "brows_07": "得意 - 眉毛.png",
    "brows_08": "皮笑肉不笑 - 眉毛.png",
    "brows_09": "想起已故的爱人 - 眉毛.png",
    "brows_10": "爆缸笑脸 - 眉毛.png",
    "brows_11": "绿豆蛙 - 眉毛.png",
    # 10-20 补缺：喜悦眉、认真脸眉
    "brows_12": "喜悦 - 眉毛.png",
    "brows_13": "认真脸 - 眉毛.png",
    # 其他 6：名字见 part_catalog.gd 的 EXTRA 段
    "extra_00": "配件 - 要吐了.png",
    "extra_01": "配件 - 压迫感.png",
    "extra_02": "配件 - 汗如雨下.png",
    "extra_03": "配件 - 加载中.png",
    "extra_04": "配件 - 脸红-喜.png",
    "extra_05": "配件 - 眼镜.png",
    # 肤色 9：**外观槽**，玩家可选。tier 0 是默认肤色（Frame.skin 为空时用它）
    "skin_00": "肤色 - 亚洲人常规肤色.png",
    "skin_01": "肤色 - 白.png",
    "skin_02": "肤色 - 黑.png",
    "skin_03": "肤色 - 深肤色（特定剧本_搞笑）.png",
    "skin_04": "肤色 - 喜.png",
    "skin_05": "肤色 - 怒.png",
    "skin_06": "肤色 - 悲.png",
    "skin_07": "肤色 - 恐.png",
    "skin_08": "肤色 - 受刺激.png",
}

# 底图：脸不是部件（玩家不能选），是一张固定的「空白脸」，按「轮廓 → 鼻子」的顺序叠。
# 肤色**不在这里** —— 它有 9 种、是可选的槽位，由玩家那张 `skin_XX.png` 叠在轮廓下面。
# 第二项是额外乘上的不透明度：鼻子那张导出的是**纯黑实心**（美术在 PSD 里大概用了正片叠底），
# 100% 叠上去就是脸上贴一块黑三角 —— 压到 35% 才是一道阴影。
FACE_STACK = [
    ("空白脸  - 脸部轮廓.png", 1.0),
    ("空白脸  - 鼻子.png", 0.35),
]

# 纸底：1748×1748 整画布的白纸，压在所有图层最底下（见 scenes/minigame/recorder.tscn 的 LayerPaper）。
PAPER = "纸张.png"

# 走「正片叠底」的槽位：眼 / 嘴 / 眉
#
# 【为什么要在这里把 RGB 改掉】Godot 的 CanvasItemMaterial.BLEND_MODE_MUL 是
#     out.rgb = src.rgb * dst.rgb      ← **完全不看 src.a**
# 而这些图层的透明区是 (0,0,0,0)，直接乘会把整块画布压成黑色（实测过）。
# 所以出图前把 RGB 往「白」那边预乘一次：
#     c' = 1 - a * (1 - c)
#     a=0（透明）→ c'=1  → 乘上去底色不变
#     a=1（实心）→ c'=c  → 正常相乘
#     半透明边缘 → 恰好等于「按 alpha 插值的正片叠底」应有的值
# 这样换任何肤色，眼白 / 牙齿都会融进肤色，只留深色的线。
#
# 【为什么不写着色器读屏幕纹理】那个方案要 backbuffer 拷贝，同一帧里后画的层会拿到
# 旧的底图、把前一层整块盖掉 —— 表现就是「点一个部件，整张脸只剩这一层」。
#
# ⚠️ **新增五官素材后必须改 .import**：Godot 生成的 `xxx.png.import` 里
#    `process/fix_alpha_border` 默认是 **true**，它导入时会把透明区的 RGB 用邻近的墨色填满，
#    上面那次预乘就白做了 —— 表现是五官周围浮出一圈灰色方块（10-17 踩过）。
#    眼 / 嘴 / 眉这三类的 .import 必须是 false；`tools/test_recorder.gd` 有一条断言守着。
MULTIPLY_SLOTS = ("eyes", "mouth", "brows")

# ============================================================
# 文件名 → 显示名（规则见 tools/part_catalog.gd 顶部的注释）
# ============================================================
## 横线两边，含这些词的那一边是**分类**（`眼睛` / `眼睛1` / `嘴巴` / `眉毛` / `肤色` / `配件`），
## 另一边才是名字。
CATEGORY_OF = {
    "眼睛": "眼", "眼": "眼",
    "嘴巴": "嘴", "嘴": "嘴",
    "眉毛": "眉", "眉": "眉",
    "配件": "其他",
    "肤色": "肤色",
}


def _category(token: str):
    t = token.strip()
    for word in CATEGORY_OF:
        if t.startswith(word):
            return CATEGORY_OF[word]
    return None


def title_of(filename: str) -> str:
    """`悲伤（忧愁） - 眉毛` → 悲伤忧愁；`肤色 - 白` → 白（名字在哪边取决于分类词在哪边）。"""
    left, _, right = Path(filename).stem.partition(" - ")
    left, right = left.strip(), right.strip()
    out = left if (_category(right) and not _category(left)) else (right or left)
    for ch in "（）()":
        out = out.replace(ch, "")
    return out


FIG_RE = re.compile(
    r'<img src="([^"]+)"[^>]*>.*?(\d+)&times;(\d+) &middot; 坐标\((\d+),(\d+)\)'
    r'.*?不透明度(\d+)%',
    re.S,
)


def read_index(index_path: Path):
    """把 index.html 读成 {文件名: (x, y, w, h, 不透明度)}。"""
    text = index_path.read_text(encoding="utf-8")
    info = {}
    for m in FIG_RE.finditer(text):
        name = html.unescape(m.group(1))
        w, h, x, y, alpha = (int(m.group(i)) for i in (2, 3, 4, 5, 6))
        info[name] = (x, y, w, h, alpha / 100.0)
    return info


def to_multiply(canvas: Image.Image) -> Image.Image:
    """把图层 RGB 预乘成「正片叠底友好」的形态（推导见 MULTIPLY_SLOTS 上的注释）。"""
    alpha = canvas.getchannel("A")
    inv = Image.eval(canvas.convert("RGB"), lambda v: 255 - v)
    delta = ImageChops.multiply(inv, alpha.convert("RGB"))   # a * (1 - c)
    rgb = ImageChops.subtract(Image.new("RGB", canvas.size, (255, 255, 255)), delta)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def main() -> int:
    index = read_index(SRC / "index.html")
    if FACE_OUTLINE not in index:
        raise SystemExit(f"index.html 里找不到 {FACE_OUTLINE!r}，没法定中心")
    fx, fy, fw, fh, _ = index[FACE_OUTLINE]
    cx, cy = fx + fw / 2.0, fy + fh / 2.0
    scale = CANVAS * FACE_FILL / fh

    print(f"画布 {CANVAS}×{CANVAS}  脸 {fw}×{fh} @ ({fx},{fy})  中心 ({cx:.1f},{cy:.1f})")
    print(f"缩放 {scale:.5f}  脸在成品里占 {fw * scale:.0f}×{fh * scale:.0f}")
    print("")

    OUT.mkdir(parents=True, exist_ok=True)

    def stamp(dst: Image.Image, name: str, alpha_mul: float = 1.0) -> None:
        """把一张图层按原坐标缩放贴到 dst 上（dst 是 512 画布）。"""
        x, y, w, h, alpha = index[name]
        src = Image.open(SRC / name).convert("RGBA")
        tw, th = max(1, round(w * scale)), max(1, round(h * scale))
        src = src.resize((tw, th), Image.LANCZOS)
        alpha *= alpha_mul
        if alpha < 1.0:
            a = src.getchannel("A").point(lambda v: int(v * alpha))
            src.putalpha(a)
        dst.alpha_composite(src, (round((x - cx) * scale + CANVAS / 2),
                                  round((y - cy) * scale + CANVAS / 2)))

    # ---- 部件 ----
    missing = [n for n in SOURCES.values() if n not in index]
    if missing:
        raise SystemExit("index.html 里缺这些图层：" + "、".join(missing))

    for part_id, name in SOURCES.items():
        canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        stamp(canvas, name)
        if part_id.split("_")[0] in MULTIPLY_SLOTS:
            canvas = to_multiply(canvas)
        canvas.save(OUT / f"{part_id}.png")
        print(f"  {part_id}.png  ←  {name}   [标题 {title_of(name)}]")

    # ---- 底图：脸皮 + 纸底 ----
    face = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    for name, mul in FACE_STACK:
        stamp(face, name, mul)
    face.save(OUT / "face_base.png")
    print(f"  face_base.png  ←  {' + '.join(n for n, _ in FACE_STACK)}")

    paper = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    stamp(paper, PAPER)
    paper.save(OUT / "face_paper.png")
    print(f"  face_paper.png  ←  {PAPER}")

    print("")
    print(f"共 {len(SOURCES)} 张部件图 + 2 张底图 → {OUT}")
    print("下一步：godot --headless --path <项目> --import")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
