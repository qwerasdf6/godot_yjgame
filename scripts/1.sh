#!/usr/bin/env bash
# fix_ui_layout.sh
# 用法: bash fix_ui_layout.sh /path/to/project
# 对 editor_ui.gd / game_over_ui.gd / shop_ui.gd 做拉伸适配改造

set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

FILES=("editor_ui.gd" "game_over_ui.gd" "shop_ui.gd")

# ---------- 0. 备份 ----------
for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    cp -n "$f" "$f.bak" || true
    echo "[backup] $f -> $f.bak"
  else
    echo "[warn] 未找到 $f，跳过"
  fi
done

# ---------- 1. 用 python 做精确的多行替换（比 sed 稳） ----------
python3 - "$ROOT" <<'PY'
import os, re, sys

root = sys.argv[1]
files = ["editor_ui.gd", "game_over_ui.gd", "shop_ui.gd"]

# ---- 通用：把 bg 的固定尺寸改成锚点铺满 ----
bg_fix = lambda src: re.sub(
    r'(var bg := ColorRect\.new\(\)\n)(\s*bg\.color[^\n]*\n)?(\s*bg\.size[^\n]*\n)?(\s*bg\.position[^\n]*\n)?',
    lambda m: m.group(1) + "\tbg.set_anchors_preset(Control.PRESET_FULL_RECT)\n" + (m.group(2) or ""),
    src
)

# ---- 通用：把 panel 的 size/position 改成比例锚点 ----
def panel_fix(src, left, top, right, bottom):
    return re.sub(
        r'var panel := Panel\.new\(\)\n(?:\s*panel\.size[^\n]*\n)?(?:\s*panel\.position[^\n]*\n)?',
        f"var panel := Panel.new()\n"
        f"\tpanel.anchor_left = {left}\n"
        f"\tpanel.anchor_top = {top}\n"
        f"\tpanel.anchor_right = {right}\n"
        f"\tpanel.anchor_bottom = {bottom}\n",
        src
    )

# ---- 通用：把 container 的 position/size 改成锚点铺满 + 内边距 ----
container_fix = lambda src: re.sub(
    r'container = VBoxContainer\.new\(\)\n(?:\s*container\.position[^\n]*\n)?(?:\s*container\.size[^\n]*\n)?',
    "container = VBoxContainer.new()\n"
    "\tcontainer.set_anchors_preset(Control.PRESET_FULL_RECT)\n"
    "\tcontainer.offset_left = 20\n"
    "\tcontainer.offset_top = 20\n"
    "\tcontainer.offset_right = -20\n"
    "\tcontainer.offset_bottom = -20\n",
    src
)

# 每个文件对应的 panel 比例（editor / gameover / shop）
panel_ratios = {
    "editor_ui.gd":     ("0.15", "0.08", "0.85", "0.92"),
    "game_over_ui.gd":  ("0.30", "0.30", "0.70", "0.70"),
    "shop_ui.gd":       ("0.12", "0.08", "0.88", "0.92"),
}

for fn in files:
    path = os.path.join(root, fn)
    if not os.path.isfile(path):
        continue
    src = open(path, encoding="utf-8").read()
    orig = src

    src = bg_fix(src)
    src = panel_fix(src, *panel_ratios[fn])
    src = container_fix(src)

    # ---- 按钮宽度改为自适应（槽位按钮 120 宽改 EXPAND_FILL） ----
    src = src.replace(
        "btn.custom_minimum_size = Vector2(120, 52)\n\t\tbtn.add_theme_font_size_override(\"font_size\", 18)",
        "btn.custom_minimum_size = Vector2(0, 52)\n\t\tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL\n\t\tbtn.add_theme_font_size_override(\"font_size\", 18)"
    )

    # ---- 编辑器：把外部技能列表 ScrollContainer 尺寸改成自动扩张 ----
    src = src.replace(
        'scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL\n\tscroll.custom_minimum_size = Vector2(0, 200)',
        'scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL\n\tscroll.custom_minimum_size = Vector2(0, 160)'
    )

    # ---- 确保 setup 开头 root Control 铺满（防止子节点锚点基准错） ----
    src = re.sub(
        r'(func setup\([^\n]*\n\s*main = m\n)',
        r'\1\tset_anchors_preset(Control.PRESET_FULL_RECT)\n',
        src
    )

    if src != orig:
        open(path, "w", encoding="utf-8").write(src)
        print(f"[patched] {fn}")
    else:
        print(f"[no-op]   {fn}")

PY

echo "全部完成。如需回滚: for f in *.gd.bak; do mv \"\$f\" \"\${f%.bak}\"; done"