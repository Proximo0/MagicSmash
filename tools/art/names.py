"""Add game_name (the file name the Horde & Hearth client loads) to every entry of queue_sd.json and write game_names.tsv.
usage: python3 names.py   (rerun after queue_sd.py rewrites the queue)
Client side read from realm/client/ui/ui_art.gd and realm/client/field/field_art.gd: enemy_<kind>[_walk] for the 43
kinds of realm/core/src/tables/kinds.rs, hero_<race>_<class>[_walk] (4 races x 6 classes), ui_title, ui_card_<class>,
ui_town_<station>, ui_item_<slot>, ui_stack_<kind>, ui_ground. Prints client names with no queue entry and queue entries
with no loader. tsv: id, name, game_name, loaded(yes/no)."""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
KINDS = ["plague rat", "carrion crow", "scarecrow", "bloated pilgrim", "penitent", "gravedigger", "hanged man", "noose spider",
         "wood wolf", "wisp", "wood witch", "bark wight", "lumberer", "drowned", "leech", "eel knight", "marsh light", "toadstone",
         "bog hag", "corpse barge", "goat cultist", "flagellant", "rune carver", "cliff harpy", "bone piper", "frost revenant",
         "stone anchorite", "shard", "cinderling", "hound", "bloat", "censor", "guard", "swords", "coffin", "ash legionary",
         "pit hound", "hollow angel", "void eye", "blood priest", "flesh choir", "the unmade"]   # core tables/kinds.rs order
KINDS_RS = os.path.join(HERE, "..", "..", "realm", "core", "src", "tables", "kinds.rs")
if os.path.exists(KINDS_RS):
    import re
    KINDS = re.findall(r'\bk\("([^"]+)"', open(KINDS_RS).read()) or KINDS
RACES = ["human", "elf", "dwarf", "orc"]; CLASSES = ["novice", "knight", "mage", "archer", "priest", "paladin"]
STATIONS = ["bank", "smith", "merchants", "reader", "trainer", "gate"]; SLOTS = ["weapon", "head", "body", "hands", "feet", "charm"]
STACKS = ["coin", "embers", "potion", "rune", "page", "card", "key", "material"]
CLIENT = (["enemy_" + k.replace(" ", "_") for k in KINDS] + ["hero_%s_%s" % (r, c) for c in CLASSES for r in RACES] + ["ui_title", "ui_ground"]
          + ["ui_card_" + c for c in CLASSES] + ["ui_town_" + s for s in STATIONS] + ["ui_item_" + s for s in SLOTS] + ["ui_stack_" + s for s in STACKS])
# queue name -> client key, where the rule enemy_/hero_ same-name does not hold. One queue picture per client slot.
MAP = {"enemy_unmade": "enemy_the_unmade",
       "town_bank": "ui_town_bank", "town_smithy": "ui_town_smith", "town_merchant": "ui_town_merchants",
       "town_card_table": "ui_town_reader", "town_trainer": "ui_town_trainer", "town_gate": "ui_town_gate",
       "town_ground": "ui_ground",
       "misc_coin": "ui_stack_coin", "mat_embers": "ui_stack_embers", "potion_draught": "ui_stack_potion", "rune_might": "ui_stack_rune",
       "misc_page": "ui_stack_page", "misc_vault_key": "ui_stack_key", "mat_ash": "ui_stack_material"}
for s in SLOTS: MAP["gear_%s_1" % s] = "ui_item_" + s      # the client has one icon per slot (no tiers): tier 1


def main():
    p = os.path.join(HERE, "queue_sd.json")
    q = json.load(open(p))
    have, loaded, rows = set(), [], []
    for e in q:
        n = e["name"]; key = MAP.get(n, n)
        ok = key in CLIENT
        e["game_name"] = key + ("_walk" if ok and e["kind"] == "walk" else "")
        if ok: have.add(key)
        else: loaded.append(n)
        rows.append((e["id"], n, e["game_name"], "yes" if ok else "no"))
    json.dump(q, open(p, "w"), indent=1)
    open(os.path.join(HERE, "game_names.tsv"), "w").write("".join("\t".join(r) + "\n" for r in rows))
    missing = [c for c in CLIENT if c not in have]
    print("client names with no queue entry (%d of %d): %s" % (len(missing), len(CLIENT), " ".join(missing)))
    print("queue entries with no client loader (%d of %d): %s" % (len(loaded), len(q), " ".join(loaded[:40]) + (" ..." if len(loaded) > 40 else "")))
    print("NAMES matched=%d client_missing=%d queue_unloaded=%d" % (len(have), len(missing), len(loaded)))


if __name__ == "__main__":
    main()
