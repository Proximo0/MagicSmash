"""The game-size batch: names from fixture metadata, client files only for accepted heroes, results.json."""
import json
import os
import tempfile
import unittest

from PIL import Image

from helpers import ROOT

from tools.animator import gamesize_batch as gb

ROUND5 = os.path.join(ROOT, "tools", "animator", "samples", "round5")


class Names(unittest.TestCase):
    def test_race_from_build_and_class_from_gear(self):
        png = os.path.join(ROUND5, "HR3.2.png")
        self.assertEqual(gb.hero_names("HR3.2", png, png[:-4] + ".json"), ("elf", "mage", "json build + gear mage_staff"))
        png = os.path.join(ROUND5, "HR6.3.png")
        self.assertEqual(gb.hero_names("HR6.3", png, png[:-4] + ".json")[:2], ("dwarf", "paladin"))


class Batch(unittest.TestCase):
    def test_two_heroes_client_files_sheets_results(self):
        with tempfile.TemporaryDirectory() as out:
            res = gb.run(ROUND5, out, {"HR2.1", "HR3.2"})
            self.assertEqual(len(res), 2)
            data = json.load(open(os.path.join(out, "results.json")))
            self.assertEqual(data["summary"]["heroes"], 2)
            for r in data["heroes"]:
                self.assertIn("gates", r)
                png = os.path.join(out, "client", r["name"] + "_walk.png")
                self.assertEqual(os.path.exists(png), r["pass"])
                if r["pass"]:
                    im = Image.open(png)
                    self.assertEqual(im.width, 8 * r["client"]["frame_px"][0])
                    self.assertEqual(json.load(open(png[:-4] + ".json")), {"frames": 8, "fps": 16, "scale": 0.5})
            self.assertTrue(os.path.exists(os.path.join(out, "overview.png")))

    def test_refused_hero_gets_no_client_files(self):
        with tempfile.TemporaryDirectory() as out, tempfile.TemporaryDirectory() as src:
            bad = os.path.join(src, "HR1.1.png")
            Image.new("RGBA", (384, 448), (0, 0, 0, 0)).save(bad)
            json.dump({"build": "human"}, open(bad[:-4] + ".json", "w"))
            res = gb.run(src, out)
            self.assertFalse(res[0]["pass"])
            self.assertTrue(res[0]["refused_by"][0].startswith("bake_error"))
            self.assertEqual(os.listdir(os.path.join(out, "client")), [])


if __name__ == "__main__":
    unittest.main()
