# Rewrites queue.json prompts for local SDXL (pixel-art-xl LoRA, compel weights). Writes queue_sd.json. Rerun: python3 queue_sd.py
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import data  # raw subject texts (FIELDS, HOUSE, PROPS, ICONS, ...)

STYLE = ("dark gothic 16-bit pixel art, Diablo-like, hard dark outline, desaturated iron grey, bone, dried-blood red, "
         "tallow yellow, sickly green, lit from upper left")
BG = ", flat magenta background (#FF00FF)"
BASE_NEG = ("multiple characters, crowd, duplicate, text, watermark, border, frame, ground, floor, cast shadow, scenery, "
            "background objects, blurry, smooth gradient, 3d render, photo")
WALK_NEG = ("text, watermark, border, frame, ground, floor, cast shadow, scenery, background objects, blurry, smooth gradient, "
            "3d render, photo, front view, back view, different outfits between frames")
ICON_NEG = BASE_NEG + ", hand, person"
TILE_NEG = ("multiple characters, crowd, duplicate, text, watermark, border, frame, cast shadow, background objects, blurry, "
            "smooth gradient, 3d render, photo, vignette, single object")
VIEW = {"walk": "full body, side view facing right", "one": "full body, three-quarter view facing right",
        "prop": "single object centred, three-quarter view", "icon": "single item centred",
        "tile": "top-down seamless texture"}

# ---- heroes: race x class ----
RACE = {  # phrase, must, neg, (height, width)
 "human": ("(human man, round ears, short dark beard)1.2", [], "pointed ears, tusks, green skin", (1.0, 1.0)),
 "elf": ("(slender elf, long pointed ears)1.4, long pale hair", ["long pointed ears", "slender"],
         "round ears, beard, stocky, tusks", (1.0, 1.0)),
 "dwarf": ("(short stocky very wide dwarf)1.4, (huge braided beard to the belt)1.3", ["broad dwarf", "huge braided beard"],
           "tall, slender, long legs, clean-shaven", (0.8, 1.3)),
 "orc": ("(green skin, big lower tusks, heavy brow)1.4, broad hulking bald orc", ["green skin", "lower tusks", "broad hulking"],
         "human face, smooth chin, beard, slender", (1.1, 1.2)),
}
CLS = {  # gear, must, neg
 "novice": ("patched grey hooded cloak, short iron dirk, brass lantern at belt", ["hooded cloak", "lantern"], "armour, helmet"),
 "knight": ("dented grey plate armour, great helm, notched two-handed sword, tattered red tabard", ["great helm", "two-handed sword", "red tabard"], "robe, bare head"),
 "mage": ("soot-black robe, wide dark hat, gnarled wooden staff with orange ember tip", ["wide hat", "staff with ember"], "plate armour, sword"),
 "archer": ("brown leather jerkin, deep hood, tall yew longbow, quiver of black-fletched arrows", ["hood", "tall longbow", "quiver"], "sword, plate armour"),
 "priest": ("grey cassock, wooden reliquary on chain, tall iron candle staff with yellow flame, bandaged hands", ["candle staff", "grey cassock"], "armour, sword"),
 "paladin": ("blackened plate with gold edges, iron war hammer, kite shield with yellow sunburst strapped to the back in every frame, short grey-white cloak the same in every frame", ["large shield", "war hammer"], "robe, bow"),
 "warden": ("heaviest dark plate, tower shield as tall as the body, short broad sword, chains across chest", ["tower shield", "chains on chest"], "robe, bow"),
 "berserker": ("bare scarred arms, grey wolf pelt, two bearded axes, red war paint, broken helm", ["two axes", "bare arms", "wolf pelt"], "full plate, shield"),
 "archmage": ("gold-threaded layered robe, tall horned mitre, staff with floating burning orange orb", ["horned mitre", "floating orb staff"], "plate armour, sword"),
 "hexer": ("robe hung with bones and dolls, veiled face, crooked wand, smoking censer in off hand", ["veiled face", "bones and dolls", "censer"], "plate armour, bright colours"),
 "ranger": ("fur-trimmed cloak, antlers on hood, recurved horn bow, black crow on shoulder", ["antlered hood", "crow on shoulder", "horn bow"], "plate armour, sword"),
 "sharpshooter": ("long dark coat, brimmed hat, heavy iron crossbow with glass lens, bolts across chest", ["brimmed hat", "crossbow with lens"], "longbow, plate armour"),
 "oracle": ("white robes, grey blindfold, ring of candle flames behind head, open book at chest", ["blindfold", "halo of flames", "open book"], "armour, weapon"),
 "inquisitor": ("black coat, capotain hat, iron mask, flaming brand in one hand, scroll in other", ["iron mask", "capotain hat", "flaming brand"], "bare face, armour"),
 "templar": ("full pale plate, great winged helm, huge shield with red cross, iron mace", ["winged helm", "red cross shield"], "robe, bare head"),
 "crusader": ("mail with surcoat, bare scarred head, two-handed war hammer glowing white, banner on back", ["bare scarred head", "glowing war hammer", "banner on back"], "helmet, shield"),
}

# ---- townsfolk ----
NPC = {  # subject, must, neg, scale
 "npc_banker": ("(thin pale man in black coat)1.3, open ledger book, ring of iron keys at belt", ["black coat", "ledger", "key ring"], "armour, fat", 1.0),
 "npc_smith": ("(broad muscular woman)1.3, brown leather apron, iron hammer in hand, burn scars on bare arms", ["leather apron", "hammer", "scarred arms"], "robe, thin", 1.0),
 "npc_merchant": ("(stout hooded trader)1.3, dark green hood, large pack on back, brass balance scales in hand", ["hood", "big pack", "scales"], "thin, armour", 0.95),
 "npc_apothecary": ("(plague doctor with long bone-coloured bird beak mask)1.4, black coat, leather bag of glass vials", ["beaked mask", "vial bag"], "bare face", 1.0),
 "npc_trainer": ("(one-eyed old soldier, eye patch)1.3, grey beard, worn leather jerkin, wooden practice sword", ["eye patch", "wooden sword"], "young, two eyes", 1.0),
 "npc_card_reader": ("(veiled woman)1.3, purple-black shawl and veil, fan of tarot cards in hand", ["veil", "fan of cards"], "man, armour", 1.0),
 "npc_tavern_keeper": ("(big bearded man)1.3, stained white apron, pewter mug in one hand, rag over shoulder", ["big beard", "mug", "apron"], "thin, armour", 1.1),
 "npc_guild_clerk": ("(monk in brown habit with shaved crown)1.3, white quill pen, huge leather-bound book held open", ["monk habit", "quill", "great book"], "armour", 1.0),
 "npc_auctioneer": ("(gaunt tall man)1.3, tall black hat, long dark coat, small brass handbell in hand", ["tall hat", "handbell", "gaunt"], "fat, short", 1.05),
}

# ---- monsters: subject, must, neg, height scale vs human ----
MON = {
 "plague_rat": ("(bloated plague rat)1.4, patchy bare grey skin, red eyes, long pink tail, low to the ground", ["plague rat", "red eyes", "bare patches"], "cute, mouse, pet", 0.25),
 "carrion_crow": ("(large ragged black crow)1.4, hopping, wings half spread, open yellow beak", ["crow", "open beak", "ragged wings"], "cute, flying away, small bird", 0.4),
 "scarecrow": ("(scarecrow of rotten yellow straw)1.4, sack head with black stitched grin, broken wooden pole frame, shambling", ["sack head", "stitched grin", "straw body"], "human face, clean clothes", 1.0),
 "bloated_pilgrim": ("(swollen sickly-green corpse)1.4, ragged pilgrim robe, clutching its belly, about to burst", ["swollen green body", "clutching belly"], "thin, healthy skin", 1.1),
 "penitent": ("(hunched hooded figure in brown sackcloth)1.3, right arm raised holding a grey stone to throw", ["sackcloth hood", "raised arm with stone"], "armour, upright", 0.9),
 "gravedigger": ("(huge gravedigger)1.4, muddy to the knees, heavy iron spade, lantern hanging on a long pole", ["huge size", "spade", "lantern pole"], "small, thin", 1.4),
 "hanged_man": ("(walking grey corpse with a rope noose round its neck)1.4, head lolling to the side, bare feet", ["noose", "lolling head", "bare feet"], "armour, clean clothes", 1.0),
 "noose_spider": ("(long-legged black spider)1.4, trailing rope-like pale webbing, coiled to jump", ["black spider", "long legs", "rope webbing"], "cute, small body, human", 0.5),
 "wood_wolf": ("(gaunt black wolf)1.4, bark-like rough fur, pale white eyes, running", ["gaunt wolf", "bark fur", "pale eyes"], "dog, cute, fat, standing still", 0.7),
 "wisp": ("(small floating ball of pale green fire)1.4, faint white skull inside", ["green fire ball", "skull inside"], "body, face, limbs, candle", 0.3),
 "wood_witch": ("(bent old witch)1.3, ragged brown rags, twig hair, glowing green poison clay pot held up to throw", ["bent witch", "twig hair", "glowing pot"], "pretty, straight back, hat", 0.9),
 "bark_wight": ("(undead warrior overgrown with brown bark and green moss)1.4, slab of wood held as a shield", ["bark skin", "moss", "wood slab shield"], "clean armour, metal shield", 1.1),
 "lumberer": ("(giant corpse woodcutter)1.4, tree stump for a head, huge rusty iron axe", ["stump head", "huge rusty axe", "giant"], "human head, small", 1.5),
 "drowned": ("(pale blue-white drowned villager)1.4, dripping water, green weeds in hair and clothes, arms stretched out", ["pale skin", "weeds", "arms outstretched"], "dry, healthy, armour", 1.0),
 "leech": ("(fat black leech)1.4, ringed round mouth with teeth open, wet shiny segmented body, forearm-sized", ["black leech", "ringed mouth"], "snake, legs, cute", 0.2),
 "eel_knight": ("(rusted armoured knight with an eel's head)1.4, barbed iron spear lunging, orange rust on plate", ["eel head", "rusted armour", "barbed spear"], "human head, clean armour", 1.1),
 "marsh_light": ("(floating lantern-like blue flame)1.4, held by a pale grey spectral hand", ["blue flame", "spectral hand"], "full body, candle, cute", 0.4),
 "toadstone": ("(huge warty brown-green toad)1.4, glowing blue stone in its forehead, cheeks puffed to spit", ["warty toad", "forehead stone", "puffed cheeks"], "frog prince, cute, smooth skin", 0.7),
 "bog_hag": ("(swollen hag wrapped in green reeds and grey fishing nets)1.4, bundle of herbs glowing green in hand", ["reeds and nets", "swollen hag", "green glowing herbs"], "pretty, thin", 1.1),
 "corpse_barge": ("(hulking mass of drowned grey bodies)1.4, lashed to a broken wooden boat hull, dragging itself forward", ["pile of bodies", "boat hull"], "single person, intact boat", 1.6),
 "goat_cultist": ("(robed cultist in dark red robe)1.3, (goat skull mask)1.4, iron sickle in hand", ["goat skull mask", "sickle", "robe"], "human face, armour", 1.0),
 "flagellant": ("(half-naked fanatic)1.3, bloody scarred back, swinging a knotted leather scourge, sprinting, white loincloth", ["bloodied back", "scourge", "sprinting"], "armour, clothed, standing still", 1.0),
 "rune_carver": ("(hooded monk in brown robe)1.3, holding a glowing blue-white carved stone tablet out in front", ["hood", "glowing stone tablet"], "weapon, armour", 1.0),
 "cliff_harpy": ("(gaunt harpy with grey feathered wings and yellow talons)1.4, crouched to leap, pale human-like face", ["grey wings", "talons", "crouched"], "angel, beautiful, white wings", 0.9),
 "bone_piper": ("(skeleton in grey fur cloak)1.4, playing a flute made of bone", ["skeleton", "fur cloak", "bone flute"], "flesh, armour", 1.0),
 "frost_revenant": ("(frozen dead mountaineer rimed with white ice)1.4, pale blue glow in the chest, torn grey coat", ["ice-rimed body", "blue chest glow"], "warm colours, fire", 1.0),
 "stone_anchorite": ("(hermit walled into a grey stone cell carried on his back)1.4, only thin arms and glowing eyes showing", ["stone cell on back", "arms and eyes only"], "full body visible, no cell", 1.1),
 "ash_legionary": ("(soldier made of grey ash)1.4, cracked iron armour, tall rectangular iron shield", ["ash body", "cracked armour", "tall rectangular shield"], "clean skin, round shield", 1.1),
 "pit_hound": ("(skinless red-muscled hound)1.4, glowing orange embers in its ribs, running", ["skinless", "ember ribs", "running"], "furry dog, cute", 0.7),
 "hollow_angel": ("(faceless pale angel)1.4, burnt bare wing bones, empty thin gold halo, about to dive", ["no face", "burnt wing bones", "empty halo"], "feathered white wings, face", 1.3),
 "void_eye": ("(floating black sphere with one burning orange eye)1.4, trailing red nerve cords", ["one burning eye", "nerve cords", "black sphere"], "body, many eyes", 0.6),
 "blood_priest": ("(priest in blood-red vestments)1.3, tall mitre, holding a gold chalice overflowing with blood", ["red vestments", "overflowing chalice"], "armour, white robe", 1.0),
 "flesh_choir": ("(cluster of fused pink-grey bodies)1.4, many open singing mouths", ["fused bodies", "many mouths"], "single body, crowd of separate people", 1.4),
 "unmade": ("(giant half-formed figure of grey clay and bone)1.4, cracks glowing red", ["clay and bone", "glowing red cracks", "half-formed"], "finished face, armour", 1.7),
}

BOSS = {  # subject, must, neg
 "boss_harvester": ("(towering scarecrow reaper)1.4, tattered black shroud, great curved scythe, black crows on its shoulders", ["towering scarecrow", "great scythe", "crows on shoulders"]),
 "boss_hanging_tree": ("(vast dead oak with a face in the bark)1.4, hanged bodies swaying from branches, roots like claws", ["face in bark", "hanged bodies", "clawed roots"]),
 "boss_mother_of_leeches": ("(enormous bloated marsh queen, half woman, half black leech)1.4, crown of green reeds", ["woman torso, leech body", "reed crown", "bloated"]),
 "boss_goat_prophet": ("(giant goat-headed prophet with four arms)1.4, seated on a grey stone throne, staff of horns, burning orange eyes", ["goat head", "four arms", "stone throne"]),
 "boss_unmade_king": ("(colossal crowned figure of grey ash with molten orange cracks)1.4, broken sword, cape of black smoke", ["crown", "molten cracks", "broken sword"]),
 "boss_pale_rider": ("(skeletal rider in black plate on a pale skeletal horse)1.4, long lance, torn banner", ["skeleton rider", "skeletal horse", "long lance"]),
 "boss_archlich": ("(floating crowned lich in royal purple grave robes)1.4, staff topped by a caged green flame", ["floating", "crown", "caged green flame"]),
}

# ---- icons: name -> (phrase, must) ----
ICON = {
 "weapon_dirk": ("(short iron dirk with dark wooden grip)1.3", ["short blade"]),
 "weapon_cleave": ("(great steel sword in mid swing)1.3, curved white arc trail", ["sword", "swing arc"]),
 "weapon_fireball": ("(ball of orange fire)1.3, long red tail", ["fireball", "tail"]),
 "weapon_longbow": ("(drawn yew longbow)1.3, arrow nocked, taut string", ["bow", "arrow"]),
 "weapon_holy_light": ("(yellow candle flame)1.3 inside a gold ring halo", ["flame", "halo"]),
 "weapon_smite": ("(iron war hammer falling)1.3 in a white-yellow beam of light", ["hammer", "light beam"]),
 "skill_second_wind": ("(pale blue-white wind swirl)1.3 around a red heart", ["wind", "heart"]),
 "skill_provoke": ("(roaring face in an iron helmet)1.3, open mouth", ["helmeted face", "open mouth"]),
 "skill_nova": ("(ring of orange fire)1.3 bursting outward from a bright centre", ["ring of fire"]),
 "skill_volley": ("(fan of many arrows)1.3 spreading upward", ["many arrows", "fan"]),
 "skill_sanctuary": ("(stone chapel doorway)1.3 glowing yellow from within", ["doorway", "inner glow"]),
 "skill_aegis": ("(shining round steel shield)1.3 with a gold sunburst", ["shield", "sunburst"]),
 "skill_charge": ("(grey armoured shoulder pauldron)1.3 with white speed lines", ["pauldron", "speed lines"]),
 "skill_meteor": ("(burning brown rock)1.3 falling with an orange fire trail", ["rock", "fire trail"]),
 "skill_tumble": ("(rolling hooded figure)1.3 with small iron caltrops", ["hooded roll", "caltrops"]),
 "skill_consecrate": ("(glowing yellow circle)1.3 with a cross inside, drawn on dark ground", ["circle", "cross"]),
 "skill_hammerfall": ("(iron hammer striking the ground)1.3, white shock ring", ["hammer", "shock ring"]),
 "ult_rampart": ("(wall of round iron shields)1.3 side by side", ["row of shields"]),
 "ult_blood_rage": ("(red screaming skull)1.3, open jaw", ["red skull", "screaming"]),
 "ult_cataclysm": ("(five orange meteors)1.3 over a burning red horizon", ["five meteors", "burning horizon"]),
 "ult_plague": ("(green skull)1.3 in a cloud of black flies", ["green skull", "flies"]),
 "ult_hail": ("(rain of arrows)1.3 falling from a dark grey cloud", ["arrows", "cloud"]),
 "ult_deadeye": ("(open eye with a crosshair pupil)1.3", ["eye", "crosshair"]),
 "ult_benediction": ("(two raised bone-coloured hands)1.3 with yellow light between them", ["two hands", "light"]),
 "ult_pyre": ("(pillar of white fire)1.3 rising from black logs", ["white fire pillar"]),
 "ult_martyr": ("(red glowing heart)1.3 pierced by three steel swords", ["heart", "swords through it"]),
 "ult_crusade": ("(banner with a yellow sunburst and a hammer)1.3 on a pole", ["banner", "sunburst", "hammer"]),
 "potion_draught": ("(round glass flask of red liquid)1.3 with a cork", ["round flask", "red liquid"]),
 "potion_veil": ("(grey glass flask)1.3 with ash swirling inside", ["grey flask", "ash swirl"]),
 "potion_whetstone": ("(small amber oil bottle)1.3 beside a grey whetstone", ["oil bottle", "whetstone"]),
 "potion_ink": ("(black ink pot)1.3 with a white feather quill", ["ink pot", "quill"]),
 "potion_coin": ("(gold coin)1.3 with a skull face stamped on it", ["gold coin", "skull face"]),
 "potion_phoenix": ("(small clay urn)1.3 with a glowing orange feather", ["urn", "glowing feather"]),
 "stat_might": ("(clenched iron gauntlet)1.3", ["fist gauntlet"]),
 "stat_focus": ("(open eye inside a gold triangle)1.3", ["eye", "triangle"]),
 "stat_swift": ("(leather boot with white feathered wings)1.3", ["boot", "wings"]),
 "stat_vigor": ("(anatomical red heart)1.3 with veins", ["heart", "veins"]),
 "stat_ward": ("(small round iron shield)1.3 with a bone-coloured rim", ["round shield"]),
 "stat_fortune": ("(four-leaf clover)1.3 made of gold coins", ["four leaves", "coins"]),
 "class_novice": ("(brass lantern)1.3 with a small yellow flame", ["lantern"]),
 "class_knight": ("(grey iron great helm)1.3 with a thin eye slit", ["great helm"]),
 "class_mage": ("(wide dark pointed hat)1.3 with an orange flame on top", ["wide hat", "flame"]),
 "class_archer": ("(brown hood)1.3 with a black-fletched arrow across it", ["hood", "arrow"]),
 "class_priest": ("(white candle with yellow flame)1.3 under a gold halo", ["candle", "halo"]),
 "class_paladin": ("(iron war hammer)1.3 over a kite shield with yellow sunburst", ["hammer", "sunburst shield"]),
 "job_warden": ("(tall rectangular iron tower shield)1.3", ["tower shield"]),
 "job_berserker": ("(two crossed bearded axes)1.3 with red-stained blades", ["two axes", "crossed"]),
 "job_archmage": ("(tall horned mitre)1.3 with a burning orange orb above", ["horned mitre", "orb"]),
 "job_hexer": ("(cloth doll)1.3 stuck with iron pins", ["doll", "pins"]),
 "job_ranger": ("(deer antlers)1.3 over a recurved horn bow", ["antlers", "bow"]),
 "job_sharpshooter": ("(iron crossbow)1.3 with a round glass lens on top", ["crossbow", "lens"]),
 "job_oracle": ("(pale face with a grey blindfold)1.3 and a ring of candle flames", ["blindfold", "flames"]),
 "job_inquisitor": ("(iron face mask)1.3 beside a burning brand", ["iron mask", "brand"]),
 "job_templar": ("(pale steel winged helm)1.3", ["winged helm"]),
 "job_crusader": ("(red cloth banner)1.3 hung on a war hammer", ["banner", "hammer"]),
 "race_human": ("(human face in profile)1.3, round ear, bone-coloured skin", ["profile face", "round ear"]),
 "race_elf": ("(elf face in profile)1.3, long pointed ear, pale hair", ["long ear", "profile"]),
 "race_dwarf": ("(bearded dwarf face in profile)1.3, huge braided beard, round nose", ["beard", "profile"]),
 "race_orc": ("(green orc face in profile)1.3, two big lower tusks", ["green skin", "tusks"]),
 "misc_blood_mark": ("(red handprint)1.3 with drips running down", ["handprint", "drips"]),
 "misc_waystone": ("(grey standing stone)1.3 with a glowing blue rune", ["standing stone", "glowing rune"]),
 "rune_might": ("(red angular rune)1.3 on a grey stone", ["red rune", "stone"]),
 "rune_focus": ("(violet rune)1.3 on a grey stone", ["violet rune", "stone"]),
 "rune_swift": ("(pale green rune)1.3 on a grey stone", ["green rune", "stone"]),
 "rune_vigor": ("(crimson heart-shaped rune)1.3 on a grey stone", ["heart rune", "stone"]),
 "rune_ward": ("(grey-blue rune)1.3 on a grey stone", ["blue-grey rune", "stone"]),
 "rune_greed": ("(gold rune)1.3 on a grey stone", ["gold rune", "stone"]),
 "mat_embers": ("(handful of glowing orange embers)1.3 with black charcoal", ["embers"]),
 "mat_straw": ("(knot of black straw)1.3 tied with string", ["black straw", "knot"]),
 "mat_bark": ("(strip of pale bark)1.3 with a carved face", ["pale bark", "face"]),
 "mat_silt": ("(glass jar of glowing green marsh silt)1.3", ["jar", "glowing silt"]),
 "mat_horn": ("(curled bone-coloured goat horn)1.3", ["curled horn"]),
 "mat_ink": ("(glass bottle of living black ink)1.3 with ink tendrils", ["bottle", "black ink"]),
 "mat_ash": ("(pile of pale grey ash)1.3 with one orange spark", ["ash pile", "spark"]),
 "misc_coin": ("(stack of worn silver coins)1.3", ["stack of coins"]),
 "misc_vault_key": ("(ornate black iron key)1.3 with a skull-shaped bow", ["key", "skull bow"]),
 "misc_page": ("(torn yellowed page)1.3 with a tarot-card border", ["torn page", "border pattern"]),
 "misc_tide_cache": ("(wet dark wood chest)1.3 bound with iron bands, dripping", ["chest", "iron bands"]),
 "misc_boss_chest": ("(large chest)1.3 with gold edges and two curved horns on the lid", ["gilded chest", "horns"]),
 "misc_vault_chest": ("(grey stone chest)1.3 carved with round seals", ["stone chest", "seals"]),
 "misc_tide": ("(wave)1.3 made of white skulls", ["wave", "skulls"]),
 "misc_party": ("(three hooded heads)1.3 side by side, dark grey hoods", ["three hoods"]),
 "misc_guild": ("(red banner on a wooden pole)1.3", ["banner", "pole"]),
 "misc_mail": ("(sealed letter)1.3 with a red wax seal", ["letter", "red wax"]),
 "misc_house": ("(small house with a lit yellow window)1.3, steep dark roof", ["house", "lit window"]),
}
# gear icons: 5 tiers x 6 slots
SLOT = {"weapon": ("steel sword, point up", "sword"), "head": ("helmet", "helmet"), "body": ("chest plate armour", "chest armour"),
        "hands": ("pair of gauntlets", "gauntlets"), "feet": ("pair of boots", "boots"), "charm": ("amulet on a chain", "amulet")}
TIER = {1: ("plain worn rusted iron and rough brown cloth", "rusty plain"), 2: ("sturdy oiled brown leather and grey steel", "leather and steel"),
        3: ("fine engraved steel with dark purple gems", "engraved, gems"), 4: ("ornate blackened iron with gold trim", "black and gold"),
        5: ("relic bone and gold with a faint sickly green glow", "bone, gold, glow")}
for _sl, (_ph, _m) in SLOT.items():
    for _t, (_tp, _tm) in TIER.items():
        ICON[f"gear_{_sl}_{_t}"] = (f"({_ph})1.3, {_tp}", [_m, _tm])

# ---- props (objects): description -> (phrase, must) ----
PROP = {
 "a bank vault door set in stone with a barred counter": ("(round iron vault door set in grey stone wall)1.3, iron-barred counter in front", ["vault door", "barred counter"]),
 "an anvil and a glowing forge": ("(black iron anvil)1.3 beside a stone forge with glowing orange coals", ["anvil", "glowing forge"]),
 "a merchant's covered stall": ("(wooden stall with a dark red canvas roof)1.3, hanging pots and cloth wares", ["canvas roof", "hanging wares"]),
 "a merchant's covered stall with hanging wares": ("(wooden stall with a dark red canvas roof)1.3, hanging pots and cloth wares", ["canvas roof", "hanging wares"]),
 "a stall of bottles and drying herbs": ("(wooden stall)1.3 with rows of green glass bottles and bundles of drying herbs hanging", ["bottles", "hanging herbs"]),
 "a weapon rack and a fighting post": ("(wooden weapon rack with swords and spears)1.3 beside a scarred wooden fighting post", ["weapon rack", "fighting post"]),
 "a round table with a candle and spread tarot cards": ("(round dark wood table)1.3 with a lit white candle and spread tarot cards", ["round table", "candle", "cards"]),
 "a wooden notice board with pinned papers and a lantern": ("(wooden notice board)1.3 with pinned yellow papers, brass lantern hanging", ["notice board", "papers", "lantern"]),
 "a tavern doorway with a hanging sign and warm light": ("(stone tavern doorway)1.3, hanging wooden sign, warm yellow light inside", ["doorway", "hanging sign", "warm light"]),
 "an empty market stall with an awning": ("(empty wooden stall)1.3 with a torn grey awning", ["empty stall", "awning"]),
 "a heavy door under a banner": ("(heavy iron-banded oak door)1.3 under a red cloth banner", ["heavy door", "banner"]),
 "a straw training dummy on a post": ("(straw training dummy)1.3 tied to a wooden post, yellow straw", ["dummy", "post"]),
 "a campfire with logs to sit on": ("(campfire with orange flames)1.3 ringed by stones, three log seats", ["campfire", "log seats"]),
 "an iron letter box on a post": ("(black iron letter box)1.3 on a wooden post", ["letter box", "post"]),
 "a dry stone fountain with a saint's statue": ("(dry grey stone fountain)1.3 with a worn saint statue on top", ["dry fountain", "saint statue"]),
 "a small house front with a door and a lit window": ("(small stone house front)1.3, wooden door, lit yellow window, dark roof", ["house", "door", "lit window"]),
 "a great town gate with a portcullis and torches": ("(great stone town gate)1.3 with iron portcullis, two burning torches", ["gate", "portcullis", "torches"]),
 "a ruined stone arch with a rune-carved keystone": ("(ruined grey stone arch)1.3, rune-carved keystone glowing blue", ["arch", "rune keystone"]),
 "a sealed round stone door with eight seals": ("(round grey stone door)1.3 with eight small wax-red seals around the rim", ["round stone door", "eight seals"]),
 "a standing stone with dim runes": ("(tall grey standing stone)1.3 with dim blue runes", ["standing stone", "dim runes"]),
 "the same standing stone with runes blazing blue": ("(tall grey standing stone)1.3 with bright blazing blue runes", ["standing stone", "blazing blue runes"]),
 "a stone altar with unlit braziers": ("(grey stone altar)1.3 with two black iron braziers, unlit", ["altar", "unlit braziers"]),
 "the same altar with braziers burning red": ("(grey stone altar)1.3 with two black iron braziers burning red", ["altar", "burning red braziers"]),
 "a wet iron-bound chest": ("(wet dark wood chest)1.3 bound with iron bands", ["chest", "iron bands"]),
 "a large gilded chest with horns": ("(large chest)1.3 with gold edges and two curved horns on the lid", ["gilded chest", "horns"]),
 # fields
 "a dead leafless tree": ("(dead leafless black tree)1.3, twisted branches", ["dead tree"]),
 "a broken cart with a wheel off": ("(broken wooden cart)1.3, one wheel lying beside it", ["cart", "missing wheel"]),
 "a roadside shrine with melted candles": ("(small stone roadside shrine)1.3 with melted white candle stubs", ["shrine", "melted candles"]),
 "a gibbet cage on a post": ("(iron gibbet cage)1.3 hanging from a wooden post", ["cage", "post"]),
 "a field of burnt wheat stubble patch": ("(patch of burnt black wheat stubble)1.3", ["burnt stubble"]),
 "the burnt chapel: a roofless stone chapel with a broken bell": ("(roofless grey stone chapel)1.3, soot-black walls, cracked bronze bell", ["roofless chapel", "broken bell"]),
 "a huge black tree trunk with a noose": ("(huge black tree trunk)1.3 with a rope noose hanging", ["trunk", "noose"]),
 "a gallows with three ropes": ("(wooden gallows)1.3 with three hanging ropes", ["gallows", "three ropes"]),
 "a ring of standing stones": ("(ring of grey standing stones)1.3 with moss", ["stone ring"]),
 "a woodcutter's hut, abandoned": ("(abandoned wooden woodcutter's hut)1.3, sagging roof, dark door", ["hut", "sagging roof"]),
 "a pile of skulls and antlers": ("(pile of bone-coloured skulls and antlers)1.3", ["skulls", "antlers"]),
 "a great hollow stump with candles inside": ("(great hollow tree stump)1.3 with lit candles inside", ["hollow stump", "candles"]),
 "a drowned church steeple leaning out of the water": ("(leaning grey stone church steeple)1.3 rising from black water", ["steeple", "leaning"]),
 "a dead willow hung with lanterns": ("(dead willow tree)1.3 hung with small yellow lanterns", ["willow", "lanterns"]),
 "a sunken rowing boat": ("(half-sunk wooden rowing boat)1.3 in black water", ["rowing boat", "sunk"]),
 "a fisherman's stilt hut": ("(wooden fisherman's hut)1.3 on tall stilts, net hanging", ["stilt hut", "net"]),
 "a stone marker with a moon carved on it": ("(grey stone marker)1.3 with a carved crescent moon", ["stone marker", "moon"]),
 "a mound of reeds and bones": ("(mound of green reeds)1.3 mixed with bone-coloured bones", ["reeds", "bones"]),
 "a cliff monastery gate": ("(grey stone monastery gate)1.3 built into a cliff face, wooden doors", ["gate", "cliff"]),
 "a prayer pole with frozen flags": ("(wooden prayer pole)1.3 with frozen grey-white flags", ["pole", "frozen flags"]),
 "a frozen corpse seated in meditation": ("(frozen corpse seated cross-legged)1.3, white frost, pale blue skin", ["seated corpse", "frost"]),
 "a rope bridge end with posts": ("(end of a rope bridge)1.3 with two wooden posts", ["rope bridge", "posts"]),
 "a great bronze bell on a frame": ("(great bronze bell)1.3 hanging on a wooden frame", ["bronze bell", "frame"]),
 "a hermit's cave mouth with a fire": ("(dark rock cave mouth)1.3 with a small orange fire inside", ["cave mouth", "fire"]),
 "a toppled bookcase": ("(toppled dark wood bookcase)1.3, books spilled", ["bookcase", "spilled books"]),
 "a tall candelabrum": ("(tall black iron candelabrum)1.3 with five lit candles", ["candelabrum", "candles"]),
 "a reading lectern with a chained book": ("(wooden reading lectern)1.3 with a big book on an iron chain", ["lectern", "chained book"]),
 "a cracked mirror in a gilt frame": ("(cracked mirror)1.3 in a gold frame", ["cracked mirror", "gilt frame"]),
 "a spiral staircase end": ("(end of a grey stone spiral staircase)1.3", ["spiral stairs"]),
 "a great hanging chandelier fallen to the floor": ("(great iron chandelier)1.3 fallen on its side, candles scattered", ["chandelier", "fallen"]),
 "a broken colossal statue hand": ("(broken colossal grey stone hand)1.3 with open fingers", ["stone hand", "cracked"]),
 "a pillar of bones": ("(tall pillar of stacked bone-coloured bones)1.3", ["bone pillar"]),
 "a floating shard of rock": ("(floating grey rock shard)1.3 with orange ember glow underneath", ["floating rock"]),
 "an obsidian obelisk with red runes": ("(black obsidian obelisk)1.3 with glowing red runes", ["obelisk", "red runes"]),
 "a field of swords planted in ash": ("(many steel swords planted upright)1.3 in grey ash", ["swords", "ash"]),
 "the empty throne": ("(empty tall black stone throne)1.3 with cracked gold trim", ["throne", "empty"]),
 "a lamp post with a hanging lantern": ("(black iron lamp post)1.3 with a hanging yellow lantern", ["lamp post", "lantern"]),
 "a stone bench": ("(grey stone bench)1.3", ["stone bench"]),
 "a well with a bucket": ("(round grey stone well)1.3 with a wooden bucket and rope", ["well", "bucket"]),
 "a market cart of turnips": ("(wooden market cart)1.3 piled with pale purple turnips", ["cart", "turnips"]),
 "a row of barrels and crates": ("(row of brown wooden barrels and crates)1.3", ["barrels", "crates"]),
 "a small stage of planks": ("(small raised stage of wooden planks)1.3", ["plank stage"]),
 # house
 "a rough wooden bed with a patched blanket": ("(rough wooden bed)1.3 with a patched grey blanket", ["bed", "patched blanket"]),
 "a four-poster bed with black drapes": ("(wooden four-poster bed)1.3 with black drapes", ["four posts", "black drapes"]),
 "a small table with a candle": ("(small wooden table)1.3 with one lit candle", ["table", "candle"]),
 "a long banquet table": ("(long dark wood banquet table)1.3 with plates and goblets", ["long table"]),
 "a wooden chair": ("(plain wooden chair)1.3", ["chair"]),
 "a high-backed carved throne chair": ("(high-backed carved dark wood throne chair)1.3", ["tall back", "carving"]),
 "a stone hearth with a fire": ("(grey stone hearth)1.3 with an orange fire", ["hearth", "fire"]),
 "an iron stove": ("(black iron stove)1.3 with a chimney pipe", ["stove", "pipe"]),
 "a bookshelf full of old books": ("(dark wood bookshelf)1.3 full of old brown books", ["bookshelf", "books"]),
 "a weapon rack": ("(wooden weapon rack)1.3 with swords and an axe", ["rack", "weapons"]),
 "an armour stand with plate armour": ("(wooden armour stand)1.3 with grey plate armour", ["stand", "plate armour"]),
 "a storage chest": ("(brown wooden chest)1.3 with iron corners", ["chest"]),
 "a round rug with an occult circle": ("(round dark red rug)1.3 with a pale occult circle", ["round rug", "circle"]),
 "a bearskin rug": ("(brown bearskin rug)1.3 with head and claws", ["bearskin", "head"]),
 "a wall tapestry of a tarot wheel": ("(hanging tapestry)1.3 with a gold tarot wheel on dark red", ["tapestry", "wheel"]),
 "a standing candelabrum": ("(standing black iron candelabrum)1.3 with three lit candles", ["candelabrum"]),
 "a hanging lantern": ("(iron hanging lantern)1.3 with yellow flame, short chain", ["lantern", "chain"]),
 "a tall mirror in a dark frame": ("(tall mirror)1.3 in a dark wood frame", ["tall mirror", "frame"]),
 "an alchemy bench with bottles": ("(wooden alchemy bench)1.3 with green and red glass bottles", ["bench", "bottles"]),
 "a card reader's table with tarot": ("(small round table)1.3 with purple cloth and tarot cards", ["table", "cards"]),
 "a small shrine with candles": ("(small stone shrine)1.3 with lit white candles", ["shrine", "candles"]),
 "a cauldron on a tripod": ("(black iron cauldron)1.3 on an iron tripod, green bubbling liquid", ["cauldron", "tripod"]),
 "a barrel and a crate": ("(brown wooden barrel)1.3 beside a wooden crate", ["barrel", "crate"]),
 "a potted dead tree with charms": ("(small dead tree in a clay pot)1.3 with hanging bone charms", ["dead tree", "charms"]),
 "a bird cage with a crow": ("(brass bird cage)1.3 with a black crow inside", ["cage", "crow"]),
 "a cat asleep on a cushion": ("(grey cat asleep)1.3 curled on a red cushion", ["cat", "cushion"]),
 "a harp": ("(wooden harp)1.3 with gold strings", ["harp"]),
 "a painting of a storm in a gilt frame": ("(painting of a dark storm)1.3 in a gold frame", ["painting", "gilt frame"]),
 "a window with moonlight": ("(stone-framed window)1.3 with pale blue moonlight", ["window", "moonlight"]),
 "a door with iron bands": ("(wooden door)1.3 with black iron bands", ["door", "iron bands"]),
 "the Harvester's scythe on a wall plaque": ("(long curved scythe)1.3 mounted on a dark wood wall plaque", ["scythe", "plaque"]),
 "a branch of the Hanging Tree with a noose": ("(black tree branch)1.3 with a rope noose", ["branch", "noose"]),
 "a jar holding a giant leech": ("(glass jar)1.3 holding a fat black leech in green liquid", ["jar", "leech"]),
 "the Goat Prophet's horned skull": ("(bone-coloured goat skull)1.3 with long curved horns", ["goat skull", "horns"]),
 "a chandelier crystal the size of a head": ("(large clear-blue crystal)1.3, faceted, head-sized, on a chain", ["crystal"]),
 "the Ghostwriter's quill and ink-stained page": ("(white feather quill)1.3 on a yellowed page with black ink stains", ["quill", "ink-stained page"]),
 "the Unmade King's broken crown": ("(broken grey ash-coloured crown)1.3 with cracks glowing orange", ["crown", "broken"]),
 "the Pale Rider's lance": ("(long pale bone lance)1.3 with a torn grey pennant", ["lance", "pennant"]),
 "the Archlich's caged green flame": ("(green flame)1.3 inside a small iron cage", ["green flame", "cage"]),
 "a banner of a won tide": ("(red cloth banner)1.3 on a pole with a white skull wave", ["banner", "wave"]),
 "a mounted champion's head (a monstrous wolf)": ("(huge grey wolf head)1.3 mounted on a wooden plaque, open jaws", ["wolf head", "plaque"]),
 "a golden statue of a hero": ("(small golden statue of a hero)1.3 with raised sword, on a stone plinth", ["gold statue", "plinth"]),
}

TILE = {
 "blighted dry grass and bare earth": "(dry yellow-brown grass tufts)1.3 on bare grey-brown earth",
 "a rutted muddy plague road with cart tracks": "(dark brown mud)1.3 with two parallel wheel ruts and hoof prints",
 "the top of a low ruined stone wall and hedge": "(crumbling grey stone wall top)1.3 with dead thorn hedge",
 "burnt chapel floor of cracked flagstones": "(cracked grey flagstones)1.3 with black soot stains",
 "black forest floor of roots and dead leaves": "(black soil)1.3 with twisted brown roots and dead brown leaves",
 "a narrow trodden dirt path": "(trodden brown dirt)1.3 with scattered leaves and pebbles",
 "the canopy of a dense dark tree seen from above (a wall)": "(dense black-green tree crowns)1.3 with overlapping leaves",
 "a mossy clearing with mushrooms": "(mossy green ground)1.3 with small pale mushrooms",
 "wet dark peat with puddles": "(wet black peat)1.3 with small grey puddles",
 "deep mire: black water with reeds (slows walking)": "(black stagnant water)1.3 with green reeds",
 "a rotten plank walkway": "(rotten brown wooden planks)1.3 side by side with dark gaps",
 "the roof of a drowned house seen from above (a wall)": "(sagging brown thatch roof)1.3 covered in green moss",
 "trampled snow over grey rock": "(trampled grey-white snow)1.3 over dark grey rock",
 "an icy mountain path": "(pale blue-white ice)1.3 with cracks and footprints",
 "a sheer rock ridge seen from above (a wall)": "(jagged dark grey rock ridge)1.3 with snow in the cracks",
 "monastery courtyard flagstones dusted with snow": "(grey flagstones)1.3 dusted with white snow",
 "dusty library floorboards": "(dusty brown wooden floorboards)1.3",
 "a worn red carpet runner": "(worn dark red carpet)1.3 with faded gold pattern",
 "the top of a stone wall with bookshelves (a wall)": "(dark wooden bookshelf tops)1.3 with old brown books",
 "a mosaic floor with an occult circle": "(dark tile mosaic floor)1.3 with a pale occult circle",
 "grey ash plain with glowing cracks": "(grey ash)1.3 with glowing orange cracks",
 "a bridge of black stone slabs": "(black stone slabs)1.3 with narrow gaps",
 "the void: starless black with drifting embers (a wall)": "(starless black void)1.3 with drifting orange embers",
 "a ruined throne room floor, half melted": "(melted dark stone floor)1.3 with gold inlay slag",
 "worn cobblestones": "(worn grey cobblestones)1.3",
 "packed earth of a market square": "(packed brown earth)1.3 with cart tracks",
 "the top of a town wall and rooftops (a wall)": "(grey roof tiles)1.3 and wall top stones",
 "tavern floorboards with rushes": "(brown wooden floorboards)1.3 with scattered straw rushes",
}

def est_tokens(s: str) -> float:
    words = len(re.findall(r"[A-Za-z0-9#.\-']+", s))
    commas = s.count(",")
    groups = s.count("(")  # each weight group costs about 2 extra tokens: ( ... )1.3
    return words * 1.3 + commas + 2 * groups

def sub(e: dict) -> str:
    p = e["prompt"]
    m = re.search(r"The character is: (.*?)\. The plain", p) or re.search(r"It is: (.*?)\. The plain", p) \
        or re.search(r"seen from straight above: (.*?)\. The same", p)
    assert m, e["id"]
    return m.group(1)

def build(e: dict) -> dict:
    n, k, raw = e["name"], e["kind"], sub(e)
    neg_extra, must, scale = "", [], None
    if n.startswith("hero_"):
        _, r, c = n.split("_", 2)
        rp, rm, rn, sc = RACE[r]
        cg, cm, cn = CLS[c]
        subj = f"{rp}, {cg}"
        must, neg_extra, scale = rm[:2] + cm[:2], f"{rn}, {cn}", {"height": sc[0], "width": sc[1]}
        view = VIEW["walk"]
    elif n in NPC:
        s, must, neg_extra, h = NPC[n]; subj = s; scale = {"height": h, "width": 1.0}; view = VIEW["walk"]
    elif n.removeprefix("enemy_") in MON:
        s, must, neg_extra, h = MON[n.removeprefix("enemy_")]; subj = s; scale = {"height": h, "width": 1.0}; view = VIEW["walk"]
    elif n in BOSS:
        s, must = BOSS[n]; subj = s; neg_extra = "small, ordinary man, empty background"
        scale = {"height": 1.0, "width": 1.0, "note": "fills the frame"}; view = VIEW["one"]
    elif k == "icon":
        if n in ICON:
            subj, must = ICON[n]
        else:
            raise KeyError(n)
        view = VIEW["icon"]; neg_extra = "realistic, many items"
    elif k == "tile":
        subj = TILE[raw]; must = [re.sub(r"[()\d.]+$", "", subj.split(")")[0].strip("( "))]; view = VIEW["tile"]
        neg_extra = "perspective, shadows, lighting gradient"
    else:  # prop
        subj, must = PROP[raw]; view = VIEW["prop"]; neg_extra = "people, characters, many objects"
    first = f"pixel art, {subj}, {view}"
    style = STYLE if k == "tile" else STYLE + BG
    base = {"walk": WALK_NEG, "icon": ICON_NEG, "tile": TILE_NEG}.get(k, BASE_NEG)
    if len(must) < 2:
        must = must + {"icon": ["single centred item"], "tile": ["seamless, no border"]}.get(k, ["single object"])
    out = dict(e)
    out.update(sd_prompt=f"{first}, {style}", negative=f"{base}, {neg_extra}", must=must[:4], scale=scale)
    out["_first"] = first
    return out

def main() -> None:
    q = json.load(open(os.path.join(HERE, "queue.json")))
    res, bad = [], []
    for e in q:
        o = build(e)
        t = est_tokens(o.pop("_first"))
        if t > 70: bad.append((e["id"], round(t)))
        assert 2 <= len(o["must"]) <= 4, (e["id"], o["must"])
        res.append(o)
    json.dump(res, open(os.path.join(HERE, "queue_sd.json"), "w"), indent=1)
    print("entries", len(res), "over-70 first chunks:", bad)
    for i in ("HR2.3", "HR4.4", "MN1.1", "BS1.1", "IC1.2", "TL1.1"):
        o = next(x for x in res if x["id"] == i or x["id"].startswith(i + "."))
        print("\n", o["id"], o["name"], "\n P:", o["sd_prompt"], "\n N:", o["negative"], "\n must:", o["must"], "scale:", o["scale"],
              "tok~", round(est_tokens(o["sd_prompt"].split(", dark gothic")[0])))

if __name__ == "__main__":
    main()
