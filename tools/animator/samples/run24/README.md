# Bare body + separate gear (animator 58b5c4d, 22 Nov)

Klein 4B (distilled, 4-bit, no LoRA) drew each body over its build's spec mannequin, with the look in words, using STILL_SPEC.md's step 1 sentences and the per-build boot sentence; up to 8 tries, gated after every try. The shield and the war hammer were each drawn alone, keyed, scaled into their guide box, and tested on the spec mannequin (up to 6 tries). One shield and one hammer are shared by all four paladins (gear/).

| hero | body tries | body alone | body + shield + hammer |
|---|---|---|---|
| HR6.1 human paladin | 1 | accepted | accepted |
| HR6.2 elf paladin | 8 | not accepted: R17 (a hand-coloured blob not on a forearm, in the bake) in 6 tries, R24 (loose blob in the bake) in 5, G8 in 1, G6 in 1, R6 in 1 | not drawn |
| HR6.3 dwarf paladin | 3 (try 1: G10, G15; try 2: R17) | accepted | REFUSED: R17, a hand-coloured blob of 25 px not on a forearm in 112 px frame 5 (7 px in 56 px frame 3) |
| HR6.4 orc paladin | 1 | accepted | accepted |
| gear: shield | 1 | accepted on the mannequin | |
| gear: hammer | 1 | accepted on the mannequin | |

The extra prompt wording only covers G rules, so the R17/R24 refusals added none: HR6.2's later tries differed by seed only.

What the gate accepted that I would not show Curtis (112 px walk, all 8 frames counted by eye):
1. HR6.4: green skin-coloured specks on the trousers at the knees in every frame. In frames 5-6, a green hand dangles under the shield at the back hip and reads as a loose hand. Proposed rule: hand-coloured pixels on a leg part fail, and a far hand shown below the hip line fails.
2. HR6.1: dark and brown smudges on the trousers at the knees (frames 2, 6, 7) and a brown sliver at the back hip under the shield (frame 5): residue from the far leg's shaded copy and the cut.
3. Both: the white tunic skirt has ragged edges and speckle noise. My 2x NEAREST downscale of the model's off-grid pixels causes it. Fix on my side: downscale with a mode / k-centroid filter, not NEAREST.
Legs (2), feet (2), near arm (1), shield (1) and hammer (1) are present in every frame. In the passing frames the two legs overlap, which is expected.

Not started: the 24-body run. It needed 3 of 4 accepted and looking right. With gear, 2 of 4 are accepted, and neither looks right yet.
