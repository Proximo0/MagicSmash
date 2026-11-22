# Extends the SD queue: action sheets (atk/hit/die) for every hero + monster walk entry, and painted art
# (deck cards, townsfolk portraits, class cards, title, field backdrops, store capsules). NEW entries only.
# Writes queue_sd2.json. Rerun: python3 queue_sd2.py
import json, os, sys, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import queue_sd as Q   # RACE CLS MON NPC STYLE BG WALK_NEG est_tokens
import data

# ---------- action sheets ----------
HERO_ACT = {  # class: (wind-up, strike, follow-through)
 "novice": ("dirk drawn back at the hip, lantern raised", "lunging forward stabbing with the dirk", "arm fully extended, lantern swinging"),
 "knight": ("two-handed sword raised over the right shoulder", "sword chopping down in a wide arc", "sword low to the ground, body bent forward"),
 "mage": ("staff pulled back, ember tip glowing", "staff thrust forward, orange fire bursting from the tip", "staff pointing ahead, embers drifting"),
 "archer": ("longbow drawn to the cheek, arrow nocked", "string released, arrow leaving the bow", "bow arm extended, string trembling"),
 "priest": ("candle staff raised high, yellow flame flaring", "staff swung down, flame streaking", "staff low, a trail of sparks behind it"),
 "paladin": ("war hammer lifted behind the head, shield forward", "hammer slamming down", "hammer resting low, shield still raised"),
 "warden": ("tower shield drawn back, short sword cocked", "shield shoved forward, sword thrusting", "braced behind the shield, chains swinging"),
 "berserker": ("both axes raised overhead, mouth open in a roar", "both axes swinging in crossing arcs", "axes low, torso twisted, chest heaving"),
 "archmage": ("staff raised, floating orb flaring", "staff swept forward, orb hurling a burning bolt", "arm extended, orb dimming, robes billowing"),
 "hexer": ("wand raised, censer swung back", "wand jabbing forward, censer smoke bursting", "arm extended, smoke trailing, dolls swinging"),
 "ranger": ("horn bow drawn, arrow nocked, crow flaring wings", "arrow loosed from the bow", "bow arm extended, crow flapping"),
 "sharpshooter": ("heavy crossbow raised to the eye, lens glinting", "crossbow firing, bolt leaving with smoke", "crossbow lowered, recoiling backward"),
 "oracle": ("open book held out, ring of flames growing", "one hand thrust forward, flames shooting out", "hand extended, ring of flames fading"),
 "inquisitor": ("flaming brand held back, scroll raised", "brand lashing forward, fire streaking", "brand low, scroll fluttering"),
 "templar": ("iron mace raised, red cross shield forward", "mace crashing down over the shield", "mace low, shield raised, leaning in"),
 "crusader": ("glowing war hammer lifted over the back, banner flaring", "hammer swung down, white light bursting", "hammer low, light fading, banner swaying"),
}
MON_ACT = {  # monster: (wind-up, strike, follow-through, optional die text)
 "plague_rat": ("crouched low, mouth wide with yellow teeth", "leaping forward, jaws snapping", "landing low, tail whipping"),
 "carrion_crow": ("wings raised, beak back", "diving forward, beak stabbing", "wings spread wide, feathers flying", "wings crumple, flops on its side, lies with wings splayed"),
 "scarecrow": ("one straw arm raised high", "arm swinging down, straw flying", "bent forward, arm low, pole creaking"),
 "bloated_pilgrim": ("belly swelling, arms clutching it", "bursting forward, green gas spraying", "deflated, hunched, green mist hanging", "belly bursts, collapses, lies as a flat green husk"),
 "penitent": ("arm cocked back with a stone", "arm whipping forward, stone leaving the hand", "arm extended, body leaning forward"),
 "gravedigger": ("spade raised high over the shoulder", "spade slamming down", "leaning on the spade stuck in the mud, lantern swaying"),
 "hanged_man": ("both arms reaching up, head lolling", "arms swiping forward, rope swinging", "arms hanging low, rope swaying"),
 "noose_spider": ("rearing on four back legs, fangs open", "pouncing forward, fangs bared", "landing low, legs splayed, webbing trailing", "legs curl inward, flips onto its back, lies with legs curled"),
 "wood_wolf": ("crouched, hackles up, jaws open", "lunging with jaws snapping", "landing, head low, snarling"),
 "wisp": ("flame shrinking and drawing back", "flaring bright, darting forward", "stretched into a streak, sparks behind", "flame flickers, shrinks, lies as a small dark ash puff"),
 "wood_witch": ("clay pot raised high in one hand", "arm swung forward, pot flying with green splash", "arm extended, bent forward, empty hand"),
 "bark_wight": ("wooden slab drawn back, other fist cocked", "slab bashing forward", "body leaning behind the slab"),
 "lumberer": ("huge axe raised high over the stump head", "axe chopping down, splinters flying", "axe buried low, torso bent"),
 "drowned": ("arms reaching, mouth open, water streaming", "lunging, grabbing hands forward", "arms hanging, dripping, bent over"),
 "leech": ("body coiled back, ringed mouth open", "lunging forward, mouth wide", "stretched long on the ground", "curls up, shrivels, lies flat and limp"),
 "eel_knight": ("barbed spear drawn back at the hip", "spear thrusting far forward", "spear extended, body low"),
 "marsh_light": ("blue flame dimming, spectral hand pulling back", "hand thrusting forward, flame flaring", "hand extended, flame trailing", "flame gutters out, hand drops, lies as a limp pale hand"),
 "toadstone": ("cheeks puffing out, body squatting", "cheeks deflating, spit flying forward", "mouth open, hunched low", "rolls onto its back, legs up, belly pale"),
 "bog_hag": ("herb bundle raised, green glow rising", "bundle thrown, green burst forward", "arm extended, hunched, reeds swaying"),
 "corpse_barge": ("mass of bodies heaving back, arms reaching", "hull lurching forward, arms grabbing", "hull dragged low, bodies sagging", "hull tilts and splits, bodies slump, lies as a still wreck"),
 "goat_cultist": ("sickle raised behind the head", "sickle slashing across", "sickle low, leaning forward"),
 "flagellant": ("scourge swung back over the shoulder", "scourge lashing forward", "scourge trailing, body twisted"),
 "rune_carver": ("stone tablet held to the chest, glowing", "tablet thrust forward, blue light bursting", "arms extended, light fading"),
 "cliff_harpy": ("crouched, wings drawn back, talons out", "swooping forward, talons slashing", "wings spread, talons extended", "wings fold, tumbles, lies crumpled with wings spread"),
 "bone_piper": ("flute raised to the mouth, cheeks hollow", "playing, notes bursting forward", "flute lowered, head tilted"),
 "frost_revenant": ("arms drawn back, ice cracking, chest glow rising", "fists slamming forward, frost bursting", "arms extended, breath of frost"),
 "stone_anchorite": ("arms pushing back out of the cell", "arms thrusting forward, eyes flaring", "arms extended, cell tilted", "cell cracks, arms drop, lies tipped on its side"),
 "ash_legionary": ("shield raised, arm cocked behind it", "shield slamming forward, ash puffing", "behind the shield, ash drifting"),
 "pit_hound": ("crouched, embers flaring in the ribs", "lunging, jaws wide, sparks flying", "landing, head low, embers trailing"),
 "hollow_angel": ("wing bones spread wide, rising", "diving forward, wing bones slashing", "wing bones swept back, halo tilted", "wing bones snap, spirals down, lies burnt and broken"),
 "void_eye": ("sphere swelling, eye burning bright, cords pulling back", "cords lashing forward, eye flaring", "cords extended, eye narrowed", "eye closes, sphere sags, lies as a dark deflated shell"),
 "blood_priest": ("chalice raised high, blood slopping", "chalice swung forward, blood splashing", "arm extended, vestments swaying"),
 "flesh_choir": ("mouths gaping wide, mass swelling", "mouths screaming, mass lurching forward", "mass sagging low, mouths drooping"),
 "unmade": ("huge arm raised, red cracks flaring", "fist slamming down", "fist buried low, dust rising", "cracks go dark, collapses in pieces, lies as a heap of clay and bone"),
}
HERO_DIE = "staggering back clutching the chest; falling to the knees, weapon dropping; lying flat on the back on the ground"
MON_DIE = "staggering back; falling sideways; lying still on the ground"
SHEET_NEG_X = "different outfits between frames, standing idle in every frame, front view, back view, extra limbs"

def pix_prompt(kind, desc_subj, pose_txt, frames):
    return (f"Pixel art animation sprite sheet on a plain bright magenta pink background: the same one character drawn {frames} "
            f"side by side in one row, far apart, seen from the side facing right, as {pose_txt}. The character is identical in every "
            f"frame, same size, same armour, same colours; only the pose changes. Every frame fits inside the picture with pink "
            f"between and beyond them. The character is: {desc_subj}. The plain bright magenta pink (#FF00FF) fills the whole picture. "
            f"Style: gritty 16-bit pixel art for a dark gothic action RPG in the spirit of Diablo: hard dark outlines, dark "
            f"desaturated colours (iron grey, bone, dried-blood red, tallow yellow, sickly green), lit from the upper left. Grim and weathered.")

def pose_texts(kind, acts, die):
    if kind == "atk":
        return ("three frames of an attack: frame 1 wind-up (%s), frame 2 strike (%s), frame 3 follow-through (%s)" % acts[:3],
                "three times", "pixel art, 3-pose sprite row, {S}, wind-up (%s)1.2, strike (%s)1.2, follow-through (%s)1.2" % acts[:3])
    if kind == "hit":
        return ("a single frame of recoil: head thrown back, body flinching and leaning away, weapon arm flung out", "once",
                "pixel art, {S}, (single frame, hit reaction)1.3, (head thrown back, body recoiling and leaning away)1.2, arms flung out")
    d = die.split("; ")
    return ("three frames of dying: frame 1 stagger (%s), frame 2 fall (%s), frame 3 lying still (%s)" % tuple(d),
            "three times", "pixel art, 3-pose sprite row, {S}, (%s)1.2, (%s)1.2, (%s)1.2" % tuple(d))

SIZE = {"atk": [1024, 512], "hit": [512, 512], "die": [1024, 512]}
POSE = {"atk": "attack_3f", "hit": "recoil_1f", "die": "die_3f"}

def dedupe(t):
    seen, out = set(), []
    for p in t.split(", "):
        if p not in seen: seen.add(p); out.append(p)
    return ", ".join(out)

def sub_first(e):  # subject chunk from the walk sd_prompt
    s = e["sd_prompt"]
    s = s[len("pixel art, "):]
    return s.split(", full body, side view")[0]

def actions(walk):
    out = []
    ids = {e["name"]: e["id"] for e in walk}
    for e in walk:
        n = e["name"]
        hero = n.startswith("hero_")
        subj = sub_first(e)
        if hero:
            subj = ", ".join(subj.split(", ")[:-3]) if False else subj
            _, r, c = n.split("_", 2)
            acts = HERO_ACT[c]; die = HERO_DIE
            ref_base = ids[f"hero_{r}_novice"]
            wtxt = acts
            subj = f"{Q.RACE[r][0]}, {', '.join(Q.CLS[c][0].split(', ')[:2])}"
        else:
            m = n.removeprefix("enemy_")
            a = MON_ACT[m]; acts = a[:3]
            die = (f"{a[3]}; flopping flat; lying still" if len(a) > 3 else MON_DIE)
            ref_base = None
        for k in ("atk", "hit", "die"):
            ptxt, times, sdt = pose_texts(k, acts, die)
            if k == "die" and not hero and len(MON_ACT[n.removeprefix("enemy_")]) > 3:
                t = MON_ACT[n.removeprefix("enemy_")][3]
                ptxt = "three frames of dying: frame 1 stagger, frame 2 collapse, frame 3 lying still; specifically: " + t
                sdt = "pixel art, 3-pose sprite row, {S}, (stagger, collapse, lying still: %s)1.2" % t
            first = sdt.replace("{S}", subj)
            frames = "once" if k == "hit" else "three times"
            o = dict(
                id=f"{e['id']}.{k}", pri=e["pri"], folder=e["folder"], name=f"{n}.{k}", kind="action", shape="l",
                prompt=pix_prompt(k, e["prompt"].split("The character is: ")[-1].split(". The plain")[0] if "The character is: " in e["prompt"] else e["name"],
                                  ptxt, frames if k == "hit" else "three times"),
                height=e["height"],
                sd_prompt=f"{first}, side view facing right, {Q.STYLE}{Q.BG}",
                negative=dedupe(e["negative"].replace("border, frame,", "border, picture frame,") + ", " + SHEET_NEG_X),
                must=e["must"][:3] + ["same figure each frame"] if len(e["must"]) > 3 else e["must"] + ["same figure each frame"],
                scale=e["scale"], style="pixel", size=SIZE[k], pose=POSE[k], ref=e["id"])
            if hero:
                o["ref_base"] = ref_base
            out.append(o)
    return out

# ---------- painted ----------
PSTYLE = ("dark gothic oil painting, Diablo-like, tarot illustration, chiaroscuro, painterly brushwork, candle light, "
          "desaturated iron grey, bone, dried-blood red, tallow yellow, deep violet shadows")
PNEG = "text, letters, watermark, signature, frame, border, blurry, lowres, deformed hands, extra fingers, 3d render, photo"
CARD_NEG = PNEG + ", multiple cards, card edge, modern, cartoon"

DECK = {  # id: (subject with weights, must)
 "the_empress": ("(crowned queen on a throne woven of wheat and black thorns)1.4, heavy crimson velvet gown, gold crown, pale stern face, dead wheat field behind", ["crowned queen", "wheat and thorn throne"]),
 "the_emperor": ("(armoured king on a stone throne carved with ram skulls)1.4, grey steel plate, red cloak, iron crown, scepter, barren mountains behind", ["armoured king", "ram skull throne"]),
 "the_hierophant": ("(masked high priest raising two fingers)1.4, between two stone pillars, white bone mask, red and gold vestments, two kneeling acolytes", ["masked priest", "two pillars", "two fingers raised"]),
 "the_lovers": ("(two figures bound by a red thread)1.4, (dark winged angel above them)1.3, ruined garden, blood-red thread, violet sky", ["two figures", "red thread", "dark angel"]),
 "the_chariot": ("(armoured rider in a stone chariot)1.4, (one black and one white sphinx pulling)1.3, starry night canopy, steel armour with gold trim", ["armoured rider", "black and white sphinx"]),
 "strength": ("(calm woman in white gently closing the jaws of a lion)1.4, golden mane, infinity loop of light over her head, grey rocky cliff", ["woman", "lion's jaws", "light loop"]),
 "the_hermit": ("(cloaked old man on a snowy peak holding up a lantern)1.4, grey hooded cloak, long white beard, yellow lantern light, dark storm sky", ["old hermit", "raised lantern", "mountain peak"]),
 "wheel_of_fortune": ("(great stone wheel carved with beasts)1.4, turning in black storm clouds, gold rune ring, a sphinx, a jackal and a serpent around it", ["great wheel", "carved beasts", "storm clouds"]),
 "justice": ("(blindfolded judge seated holding a sword upright and brass scales)1.4, crimson robe, grey stone pillars, cold light", ["blindfold", "sword", "scales"]),
 "the_hanged_man": ("(man hanging upside down by one foot from a dead tree)1.4, serene face, halo of pale light, bare black branches, grey dawn", ["upside down man", "dead tree", "serene face"]),
 "temperance": ("(winged figure pouring water between two golden cups)1.4, flowing stream between the cups, one foot in a pond, pale robes, violet dusk", ["winged figure", "two cups", "water stream"]),
 "the_devil": ("(horned goat-headed devil on a black block)1.4, two small chained figures below, torch in one hand, red glow, black bat wings", ["goat-headed devil", "two chained figures", "red glow"]),
 "the_sun": ("(blazing sun with a stern carved face)1.4, field of drooping withered sunflowers below, gold and orange rays, a pale child on a grey horse", ["sun with stern face", "withered sunflowers"]),
 "judgement": ("(angel blowing a long trumpet from the clouds)1.4, grey dead rising from open graves with arms raised, grey sea, pale gold light", ["angel with trumpet", "dead rising from graves"]),
 "the_world": ("(dancing figure inside a laurel wreath)1.4, four beasts in the corners: lion, bull, eagle, angel, violet cloth, starry dark sky", ["dancing figure", "laurel wreath", "four beasts"]),
 "nine_of_swords": ("(figure sitting up in bed with face in hands)1.4, nine swords hanging on the dark wall, patchwork blanket with roses, black night", ["figure in bed", "nine swords"]),
 "three_of_cups": ("(three hooded figures raising golden goblets together)1.4, candlelit stone hall, deep red wine, harvest garlands wilted", ["three hooded figures", "raised goblets"]),
 "ace_of_wands": ("(hand emerging from a cloud gripping a budding burning staff)1.4, orange flames and green leaves, distant black castle, dark valley", ["hand from cloud", "burning staff"]),
 "five_of_pentacles": ("(two ragged beggars in deep snow)1.4, one on crutches, passing a lit stained-glass church window with five gold coins, blue night", ["two beggars", "snow", "lit church window"]),
 "six_of_cups": ("(small child handing a cup of white flowers to another child)1.4, old stone courtyard, five more cups of flowers, faded warm light", ["two children", "cups of flowers", "stone courtyard"]),
 "ten_of_swords": ("(fallen figure lying face down with ten swords in the back)1.4, black sky, thin pale dawn line on the horizon, red cloak spread", ["fallen figure", "ten swords", "black sky"]),
 "queen_of_pentacles": ("(queen on a carved throne cradling a great gold coin)1.4, dark green robe, rose thorns on the throne, black raven on the armrest", ["queen", "great gold coin", "carved throne"]),
 "knight_of_wands": ("(armoured knight on a rearing black horse holding a burning staff)1.4, scorched desert, red plume, orange sparks", ["armoured knight", "rearing horse", "burning staff"]),
}
CLASS_CARD = {
 "novice": ("(ragged pilgrim in a patched hooded cloak holding a brass lantern)1.4, short dirk at the belt, dark muddy road, small yellow lantern glow", ["hooded pilgrim", "lantern"]),
 "knight": ("(knight in dented grey plate and great helm)1.4, notched two-handed sword planted point-down, tattered red tabard, grey storm light", ["great helm", "two-handed sword", "red tabard"]),
 "mage": ("(mage in soot-black robe and wide dark hat)1.4, gnarled staff with an orange ember tip, sparks rising, dark library", ["wide dark hat", "ember staff"]),
 "archer": ("(archer in brown leather and deep hood drawing a tall yew longbow)1.4, quiver of black-fletched arrows, misty dark forest", ["hood", "longbow", "quiver"]),
 "priest": ("(priest in grey cassock holding a tall iron candle staff)1.4, yellow flame, wooden reliquary on a chain, bandaged hands, ruined chapel", ["grey cassock", "candle staff"]),
 "paladin": ("(paladin in blackened plate with gold edges)1.4, iron war hammer and kite shield with a yellow sunburst, grey-white cloak, burning village behind", ["black plate", "sunburst shield", "war hammer"]),
}
NPC_BUST = {  # id -> (subject, must)
 "npc_banker": ("(thin pale man in a black coat)1.4, sunken cheeks, open ledger book, ring of iron keys, spectacles", ["pale thin man", "ledger", "keys"]),
 "npc_smith": ("(broad muscular woman)1.4, soot on her face, brown leather apron, burn scars on bare arms, red forge glow on one side", ["woman smith", "leather apron", "burn scars"]),
 "npc_merchant": ("(stout trader in a dark green hood)1.4, heavy pack, brass balance scales in hand, sly smile", ["green hood", "brass scales"]),
 "npc_apothecary": ("(plague doctor with a long bone-coloured beaked mask)1.4, black coat, leather bag of glass vials, green glass glints", ["beaked mask", "vials"]),
 "npc_trainer": ("(one-eyed old soldier with an eye patch)1.4, grey beard, scarred face, worn leather jerkin, wooden practice sword on shoulder", ["eye patch", "grey beard"]),
 "npc_card_reader": ("(veiled woman in purple-black shawl)1.4, holding a fan of tarot cards, dark kohl eyes, candle glow", ["veil", "tarot cards"]),
 "npc_tavern_keeper": ("(big bearded man)1.4, stained white apron, pewter mug, rag over shoulder, warm hearth glow", ["big beard", "pewter mug"]),
 "npc_guild_clerk": ("(monk in brown habit with shaved crown)1.4, white quill pen, huge leather-bound book held open, ink-stained fingers", ["shaved crown", "quill", "great book"]),
 "npc_auctioneer": ("(gaunt tall man in a tall black hat)1.4, long dark coat, small brass handbell raised, thin smile", ["tall hat", "handbell", "gaunt face"]),
}
BACKDROP = {  # field id -> (subject, must)
 "fools_road": ("(muddy plague road through a dead blighted field)1.4, cart tracks, a lone dead tree, burnt chapel ruin on the horizon, bruise-purple dusk sky", ["muddy road", "dead tree", "burnt chapel"]),
 "hanged_wood": ("(black forest of twisted dead trees with ropes hanging from branches)1.4, gallows in a clearing, pale green fog, grey moonlight", ["dead trees", "hanging ropes", "green fog"]),
 "moon_marsh": ("(black marsh water under a huge pale moon)1.4, drowned church steeple leaning out of the water, reeds, floating blue lanterns, mist", ["black water", "pale moon", "leaning steeple"]),
 "hermits_peaks": ("(snowy grey mountain peaks)1.4, cliff monastery with a bronze bell, rope bridge, frozen prayer flags, cold blue light, a distant cave fire", ["snowy peaks", "cliff monastery", "rope bridge"]),
 "the_tower": ("(vast ruined library interior)1.4, toppled bookcases, tall candelabra with yellow flames, spiral staircase, cracked mirror, dust in candle light", ["ruined library", "candelabra", "spiral stairs"]),
 "worlds_edge": ("(grey ash plain with glowing orange cracks)1.4, floating rock shards, obsidian obelisk with red runes, empty black throne, starless black void sky", ["ash plain", "orange cracks", "empty throne"]),
 "town": ("(small walled medieval hearth town at night)1.4, cobblestone square, lamp post with a yellow lantern, dry stone fountain, tavern doorway with warm light, dark rooftops", ["walled town", "lamp post", "warm tavern light"]),
}
FIELD_NAME = {f[0]: f[1] for f in data.FIELDS}

STORE_SCENE = ("(one small warm lit hearth in the foreground)1.4, three heroes seen from behind: a knight in grey plate, an archer in a hood, "
               "a priest with a candle staff, facing (a horizon-wide sea of thousands of monster silhouettes)1.3 under a (huge blood-red moon)1.3, "
               "black sky, orange fire glow on the heroes")
STORE = {  # id: (native size, gen size, composition, must)
 "st_header": ([920, 430], [1024, 480], "wide banner composition, the horde in silhouette along a ridge under the blood moon, a single lit window and the hearth at the far right, (dark empty sky on the left third)1.2 left clear for a logo", ["horde silhouettes", "blood moon", "empty left space"]),
 "st_capsule_small": ([462, 174], [1152, 432], "very wide composition, the heroes small at the right, the horde filling the left and back, (dark empty area at the top left)1.2 left clear for a logo", ["heroes", "horde", "blood moon"]),
 "st_capsule_main": ([1232, 706], [1344, 768], "16:9 key image, heroes and hearth in the lower third, horde stretching to the horizon, (upper third dark and empty)1.3 left clear for a logo", ["hearth", "three heroes", "horde", "empty upper third"]),
 "st_capsule_vertical": ([748, 896], [832, 1000], "vertical composition, heroes small at the bottom by the hearth, the horde rising above them like a wave, (top quarter dark and empty)1.3 left clear for a logo", ["small heroes", "hearth", "rising horde", "empty top"]),
 "st_library_hero": ([3840, 1240], [1536, 496], "ultra wide panorama, horde across the whole width, hearth and heroes at the left third, (dark empty centre and right for a logo)1.2", ["panorama", "horde", "blood moon", "clear space"]),
}

def painted():
    out = []
    def add(i, pri, folder, name, shape, size, desc, subj, must, style_txt=PSTYLE, neg=PNEG, extra=None):
        first = f"{subj}"
        o = dict(id=i, pri=pri, folder=folder, name=name, kind="painted", shape=shape,
                 prompt=f"Painting: {desc}. Style: {style_txt}. No text, no letters, no border.",
                 height=0, sd_prompt=f"{first}, {style_txt}", negative=neg, must=must[:4], scale=None,
                 style="painted", size=size, pose=None)
        if extra: o.update(extra)
        out.append(o)
    for n, (i, (sj, m)) in enumerate(DECK.items(), 1):
        add(f"DK1.{n}", 1, "cards/", f"card_{i}", "p", [768, 1152], f"ornate dark tarot card art of {i.replace('_',' ')}: {sj}",
            f"(ornate dark tarot card illustration)1.3, {sj}, vertical 2:3, art fills the whole picture, intricate gold filigree motifs inside the scene",
            m, neg=CARD_NEG)
    for n, (i, (sj, m)) in enumerate(NPC_BUST.items(), 1):
        add(f"PT1.{n}", 2, "portraits/", f"portrait_{i.removeprefix('npc_')}", "p", [768, 1024], f"bust portrait of a townsfolk: {sj}",
            f"(painted bust portrait)1.3, {sj}, head and shoulders, facing slightly left, dark candle light from one side, black background, weathered face",
            m)
    for n, (c, (sj, m)) in enumerate(CLASS_CARD.items(), 1):
        add(f"UI2.{n}", 1, "ui/", f"ui_card_{c}", "p", [768, 1152], f"hero tarot card face for the {c} class: {sj}",
            f"(ornate dark tarot card illustration)1.3, {sj}, vertical 2:3, full figure, art fills the whole picture, gold filigree motifs in the scene",
            m, neg=CARD_NEG)
    add("UI1.1", 1, "ui/", "ui_title", "l", [1344, 768], "title backdrop: a lone lit hearth in a dark stone hall with an endless horde of silhouettes pressing at the far doorway, clear dark space at the top centre",
        "(lone lit hearth in a dark stone hall)1.4, (endless horde of black silhouettes pressing at a far doorway)1.3, orange fire glow on grey flagstones, tarot symbols carved on the walls, dark empty ceiling space at the top centre for a logo",
        ["lit hearth", "silhouette horde", "stone hall", "empty top centre"])
    for n, (f, (sj, m)) in enumerate(BACKDROP.items(), 1):
        add(f"BG1.{n}", 2, "backdrops/", f"bg_{f}", "l", [1344, 768], f"field backdrop for {FIELD_NAME[f]}: {sj}",
            f"{sj}, wide landscape, no people, no characters, painterly dark gothic concept art, empty ground in the lower third for gameplay",
            m, neg=PNEG + ", people, characters, creatures")
    for n, (i, (nat, gen, comp, m)) in enumerate(STORE.items(), 1):
        add(f"ST1.{n}", 1, "store/", i, "p" if gen[1] > gen[0] else "l", gen,
            f"Steam {i} art at {nat[0]}x{nat[1]} (generated at {gen[0]}x{gen[1]}), no text: {STORE_SCENE}; {comp}",
            f"{STORE_SCENE}, {comp}", m, extra={"native": nat})
    return out

def main():
    q = json.load(open(os.path.join(HERE, "queue_sd.json")))
    walk = [e for e in q if e["kind"] == "walk" and (e["name"].startswith("hero_") or e["name"].startswith("enemy_"))]
    res = actions(walk) + painted()
    ids = [e["id"] for e in res]
    assert len(set(ids)) == len(ids)
    old = {e["id"] for e in q}
    assert not old & set(ids)
    for e in res:
        assert 2 <= len(e["must"]) <= 5, e["id"]
        assert e["style"] in ("pixel", "painted") and len(e["size"]) == 2
    json.dump(res, open(os.path.join(HERE, "queue_sd2.json"), "w"), indent=1)
    c = collections.Counter((e["kind"], e["style"]) for e in res)
    print("entries", len(res), dict(c), "by pose:", dict(collections.Counter(e["pose"] for e in res)))
    over = [(e["id"], round(Q.est_tokens(e["sd_prompt"].split(", dark gothic")[0]))) for e in res if e["style"] == "pixel"
            and Q.est_tokens(e["sd_prompt"].split(", dark gothic")[0]) > 70]
    print("pixel first chunks over 70 tokens:", len(over), over[:6])
    for i in ("HR2.3.atk", "HR1.4.die", "MN1.4.die", "DK1.4", "ST1.3"):
        o = next(x for x in res if x["id"] == i)
        print("\n", o["id"], o["name"], o["size"], o["pose"], o.get("ref"), o.get("ref_base"), "\n P:", o["sd_prompt"], "\n N:", o["negative"], "\n must:", o["must"])

if __name__ == "__main__":
    main()
