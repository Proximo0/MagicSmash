"""Contact sheet and bag mock for the icons.  python3 tools/char3d/icons_sheet.py <art dir> <out dir>"""
import sys, os, glob
from PIL import Image, ImageDraw, ImageFont
art, out = sys.argv[1:3]
os.makedirs(out, exist_ok=True)
PANEL = (19, 16, 19)
fs = sorted(glob.glob(os.path.join(art, "ui_item_*.png")) + glob.glob(os.path.join(art, "ui_stack_*.png")))
try:
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 10)
except Exception:
    f = ImageFont.load_default()
cols, cw, ch = 6, 190, 112
rows = (len(fs) + cols - 1) // cols
sh = Image.new("RGB", (cols * cw, rows * ch), PANEL)
d = ImageDraw.Draw(sh)
for i, p in enumerate(fs):
    im = Image.open(p).convert("RGBA")
    x, y = (i % cols) * cw, (i // cols) * ch
    sh.paste(im, (x + 8, y + 8), im)
    sh.paste(im.resize((96, 96), Image.NEAREST), (x + 50, y + 8), im.resize((96, 96), Image.NEAREST))
    d.text((x + 6, y + 102 - 4), os.path.basename(p)[3:-4], fill=(200, 190, 160), font=f)
sh.save(os.path.join(out, "icons_sheet.png"))
RAR = [(191, 184, 168), (128, 199, 128), (102, 158, 242), (184, 115, 235), (242, 140, 51)]
def row(names, rarities, w=330):
    pass
bag = Image.new("RGB", (760, 330), (10, 9, 11))
d = ImageDraw.Draw(bag)
def icon(n, sz, rar=None):
    im = Image.open(os.path.join(art, "ui_%s.png" % n)).convert("RGBA")
    if rar is not None:
        c = RAR[rar]
        tile = Image.new("RGBA", (32, 32), tuple(int(v * 0.3) for v in c) + (255,))
        ImageDraw.Draw(tile).rectangle([0, 0, 31, 31], outline=c + (255,))
        tile.alpha_composite(im)
        im = tile
    return im.resize((sz, sz), Image.LANCZOS) if sz != 32 else im
items = ["weapon_dirk", "weapon_cleaver", "weapon_staff", "weapon_longbow", "weapon_censer", "weapon_mace", "head_cowl", "head_helm", "head_crown", "body_robe", "body_mail", "body_coat", "hands_gloves", "hands_gauntlets", "hands_wraps", "feet_boots", "feet_greaves", "feet_sandals", "charm_talisman", "charm_ring", "charm_amulet"]
for i, n in enumerate(items):
    x, y = 10 + (i % 8) * 42, 10 + (i // 8) * 42
    d.rectangle([x, y, x + 39, y + 39], fill=(15, 13, 15), outline=(60, 50, 30))
    d.rectangle([x, y, x + 39, y + 39], outline=RAR[i % 5])
    bag.paste(icon("item_" + n, 32, i % 5), (x + 4, y + 4))
stacks = [("stack_coin", "COIN", "2,841"), ("stack_potion_0", "HEALING DRAUGHT", "7"), ("stack_potion_1", "VEIL OF ASH", "2"), ("stack_embers", "EMBERS", "11"), ("stack_material_1", "PLAGUE LINEN", "4"), ("stack_rune_might", "RUNE OF MIGHT II", "1"), ("stack_key", "VAULT KEY", "1"), ("stack_page", "PAGE OF THE FOOL", "3"), ("stack_card", "CARD OF BONE WIGHT", "2"), ("stack_trophy", "TROPHY OF THE HARVESTER", "1")]
for i, (n, t, c) in enumerate(stacks):
    y = 190 + (i % 5) * 26 if i < 5 else 190 + (i - 5) * 26
    x = 10 if i < 5 else 390
    d.rectangle([x, y, x + 340, y + 23], fill=(16, 14, 16), outline=(60, 50, 30))
    bag.paste(icon(n, 22), (x + 3, y + 1), icon(n, 22))
    d.text((x + 32, y + 6), t, fill=(224, 214, 184), font=f)
    d.text((x + 334, y + 6), c, fill=(217, 173, 76), font=f, anchor="ra")
x = 390
for i, (n, r, t) in enumerate([("weapon_mace", 2, "HANGED MACE +1"), ("head_helm", 1, "PILGRIM'S HELM +1"), ("hands_gauntlets", 3, "BOG GAUNTLETS")]):
    y = 10 + i * 40
    d.rectangle([x, y, x + 340, y + 36], fill=(17, 14, 17), outline=(60, 50, 30))
    bag.paste(icon("item_" + n, 28, r), (x + 72, y + 4))
    d.text((x + 108, y + 11), t, fill=tuple(RAR[r]), font=f)
bag = bag.resize((1520, 660), Image.NEAREST)
bag.save(os.path.join(out, "icons_bag_mock.png"))
