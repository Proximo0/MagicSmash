# Still spec: how a hero still must be drawn so that it fits the rig

A still that follows this page passes every input rule (G1-G11 in `RULES.md`) by construction,
because it is drawn on our skeleton instead of being fitted to it afterwards. The numbers live in
`spec.py`; `tests/test_arms_feet.py::TestSpec` draws a character exactly on them for each build
and checks that it passes every G rule and then walks with no R failure.

```
python3 -m tools.animator spec --build human|elf|dwarf|orc --out DIR      (or --build all)
```
writes `<build>_pose.png` (coloured limb skeleton on black, one colour per bone, for the image
model's pose control), `<build>_joints.json` (the same joints in the layout format the batch
reads; save it beside the still as `<id>.json`) and `<build>_reference.png` (a flat mannequin
drawn on the spec: what "fits the rig" looks like).

## Canvas
- 384 x 448 px, transparent background, hard alpha. Ground line at y = 428; pelvis at x = 176.
- Drawn on flat magenta and keyed out: no magenta or purple-pink pixel may be left (G10).
- One figure, one connected silhouette. No ground plate, shadow, blood pool, dust or loose
  pieces (a detached piece is taken for held gear).
- Dark outline (brightest channel under 70) around every form: each limb, the hand, the boot.

## View and pose (the same for every build)
- Strict side view, facing right. Not three-quarter: one shoulder, one hip.
- Mid-stride, both feet flat on the ground line, both feet pointing right (toe ahead of heel).
- **Near leg forward** (thigh 22 deg ahead of straight down, knee bent back 10 deg), far leg
  behind (thigh 12 deg behind, knee bent back 10 deg). Heel to heel is 0.26 of the body height:
  the walk's stride is copied from this, so do not draw a bigger lunge.
- Clear background between the two legs from the knees down (prompt: "background between the
  legs from the knees down"). Nothing crosses the legs: no
  sword, scabbard, staff, tail of a coat or strap in front of or between them (a sword along
  the shin makes the shin read as wide as the boot is long and the still is refused, G9).
- Knees bend back only, the elbow bends forward only (G3).

## Arms: exactly two, each one separable (owner rule, G8 and R17)
The fault this section exists for: a still that shows both arms over the body. The cutter takes
one arm, the other stays painted on the torso, the far arm is added again, and the walk has
three arms. So:
- **Near arm**: hangs forward of the chest, upper arm 34 deg ahead of straight down, elbow bent
  18 deg, hand open or a fist. Forearm and hand are **clear of the torso with a visible gap of
  background** between them and the belly (at least 1.2 % of the body height; 10-40 px in the
  reference figures). The hand never rests on the belt, hip or thigh.
- The upper arm does cross the chest in side view. Draw it as its own outlined shape in a
  colour that differs from the chest, shoulder to elbow, straight.
- **Far arm**: either hidden entirely behind the torso (the default; the tool then draws a
  shaded copy of the near arm), or its hand and forearm clear of the body **behind the back**
  with background on the back side of the hand (the tool then cuts that hand out and uses its
  own pixels, no copy). Never half over the body, never crossing the chest, never on a weapon
  held by the other hand.
- No two-handed grips (crossbow at the hip, greatsword held across the body).
- Nothing on the torso between the chest and the hips may have the hand's colour and size:
  no skin-coloured pouch, buckle plate, glove on the belt or blood stain. The gate cannot tell
  it from a hand and refuses the still.

## Feet (owner rule R6, G9)
- Flat on the ground line, sole level, pointing right.
- The heel's rear end is directly under the back edge of the shin: no heel block sticking out
  behind the leg. The whole foot runs forward from there.
- Length, per build, as the layout draws it (`spec.foot_numbers`, also in `<build>_joints.json`
  under `foot`):

| build | boot length, heel to toe | shin width at the ankle | boot / shin width | boot / leg (hip to ankle) | toe ahead of the shin's front edge |
|---|---|---|---|---|---|
| human | 0.120 BH = 47 px | 0.072 BH = 28 px | 1.67 | 0.30 | 0.048 BH = 19 px |
| elf | 0.115 BH = 46 px | 0.060 BH = 24 px | 1.92 | 0.27 | 0.055 BH = 22 px |
| dwarf | 0.200 BH = 62 px | 0.080 BH = 25 px | 2.50 | 0.58 | 0.120 BH = 37 px |
| orc | 0.135 BH = 57 px | 0.084 BH = 35 px | 1.61 | 0.35 | 0.051 BH = 21 px |

  A boot under 0.24 of the leg is refused as too short, one over 0.60 as too long; it is never
  stretched. The boot must be clearly longer than the shin is wide at the ankle: the toe at
  least one shin half-width ahead of the shin's front edge (G9).
- **Dwarf**: the first layout (boot 0.150, shin width 0.096, toe 0.054 BH = 17 px ahead) could
  not be drawn: 6 of 6 tries came back with boots shorter than the shin is wide, because the
  image model draws shins about 1.4 x as thick and boots about 0.8 x as long as the layout.
  The dwarf layout now asks for a boot of 0.200 BH (62 px) under a shin 0.080 BH (25 px) wide,
  on a leg 0.02 BH longer: the boot is 2.5 shin widths long and its toe 0.120 BH (37 px) ahead
  of the shin. G9 is unchanged; a dwarf drawn 1.4 x thick in the shin and 0.8 x short in the
  boot still passes it.
- **Boots, prompt wording**: "long boots, each boot at least twice as long as the lower leg is
  wide; the toe of each boot reaches well forward of the shin; the heel of each boot ends
  straight under the back of the leg, no heel sticking out behind; flat soles on the ground
  line, toes not curled up; slim lower legs, no wide boot shafts, no fur cuffs or greaves
  wider than the knee". Keep the boot's shaft as narrow as the shin: a wide shaft is measured
  as a wide shin and the boot is then too short for it.
- Ankle joint at 0.055-0.065 of the body height above the ground.

## Joint positions (x forward of the pelvis, y above the ground, as fractions of body height)
Body height on the canvas: human 390 px, elf 400, dwarf 310, orc 420.

| joint | human | elf | dwarf | orc |
|---|---|---|---|---|
| head_top | +0.000, 1.000 | +0.000, 1.000 | +0.000, 1.000 | +0.000, 1.000 |
| neck | +0.000, 0.810 | +0.000, 0.830 | +0.000, 0.740 | +0.000, 0.810 |
| near_shoulder | -0.010, 0.760 | -0.010, 0.785 | -0.010, 0.685 | -0.010, 0.755 |
| near_elbow | +0.082, 0.623 | +0.082, 0.648 | +0.082, 0.548 | +0.088, 0.610 |
| near_wrist | +0.196, 0.534 | +0.200, 0.556 | +0.193, 0.462 | +0.210, 0.515 |
| near_hand_tip | +0.240, 0.500 | +0.244, 0.522 | +0.240, 0.425 | +0.257, 0.478 |
| pelvis | +0.000, 0.470 | +0.000, 0.500 | +0.000, 0.430 | +0.000, 0.460 |
| near_hip | +0.000, 0.450 | +0.000, 0.480 | +0.000, 0.410 | +0.000, 0.440 |
| near_knee | +0.078, 0.258 | +0.084, 0.273 | +0.068, 0.242 | +0.075, 0.254 |
| near_ankle | +0.121, 0.055 | +0.130, 0.055 | +0.105, 0.065 | +0.117, 0.058 |
| near_heel | +0.085, 0.000 | +0.100, 0.000 | +0.065, 0.000 | +0.075, 0.000 |
| near_toe | +0.205, 0.000 | +0.215, 0.000 | +0.265, 0.000 | +0.210, 0.000 |
| far_hip | -0.020, 0.450 | -0.020, 0.480 | -0.020, 0.410 | -0.020, 0.440 |
| far_knee | -0.060, 0.247 | -0.037, 0.258 | -0.087, 0.237 | -0.082, 0.249 |
| far_ankle | -0.139, 0.055 | -0.130, 0.055 | -0.155, 0.065 | -0.143, 0.058 |
| far_heel | -0.175, 0.000 | -0.160, 0.000 | -0.195, 0.000 | -0.185, 0.000 |
| far_toe | -0.055, 0.000 | -0.045, 0.000 | +0.005, 0.000 | -0.050, 0.000 |

Limb half-widths (fractions of body height): thigh / shin / upper arm / forearm =
human 0.050 / 0.036 / 0.034 / 0.030, elf 0.042 / 0.030 / 0.028 / 0.025,
dwarf 0.058 / 0.040 / 0.042 / 0.038, orc 0.058 / 0.042 / 0.042 / 0.036.
Chest half-depth: human 0.085, elf 0.070, dwarf 0.115, orc 0.105; the torso's front and back
lines run straight from the shoulders to just below the hips. Limb lengths the gate accepts
(G2): thigh 0.10-0.34, shin 0.09-0.34, upper arm 0.10-0.27, forearm 0.08-0.26 of the body
height, front and back leg within 35 % of each other.

## Prompt wording that worked (lessons from the art PC's tries, 22 Nov)
Put these sentences into the prompt as they stand; each one answers a fault the gate refused.
- Arms (G8): "only ONE visible arm, background between hand and body; nothing skin-coloured on
  the belt". Without it the model draws the second arm over the torso (HR6.4: a fist over the
  body, 2.6 hands of skin colour where 0.15 is the limit).
- Legs (G1, G9): "background between the legs from the knees down".
- Shield (G11): "the shield is carried on the back, behind the body, wholly behind the back
  line; no shield on the arm, no shield in front of the body or over the hip". HR6.2 came back
  with the shield over the near arm (88 % of it ahead of the trunk axis, limit 25 %).
- Boots (G9): the wording under Feet above.
- Background: flat pure magenta (255, 0, 255), nothing else magenta or purple-pink in the
  picture. Our intake removes the 1 px half-keyed rim (`intake.clean_key`); magenta left
  anywhere else refuses the still (G10).
- **The reference picture must not be the old still.** The model copies the pose of a picture
  it is shown: given the old HR still as a look reference it redraws that still's arms and
  legs and ignores the layout. Give the pose layout as the only picture and describe the look
  in words: build, hair and beard, each garment with its colour, the weapon and where it is
  ("warhammer in the near hand, held ahead of the body"), the shield and where it is ("on the
  back").

## Gear
- **Weapon in the hand**: only in the near hand, drawn entirely ahead of the torso's front line,
  touching nothing but that hand. It is cut with the forearm and moves with it. Gear reaching
  more than 0.30 of the body height past the wrist (staff, spear, levelled crossbow) makes that
  arm a carried arm: it keeps the drawn pose and swings at 40 %.
- **Shield**: on the back (wholly behind the torso's back line, from below the neck to above
  the hips; it then moves with the body). Never on the near side: not over the torso's front,
  the near arm or the hip (G11 refuses a rimmed shield with more than 25 % of it ahead of the
  trunk axis), and never strapped to a forearm that lies over the body: the cut would slice it
  (G7).
- **Cape, cloak, quiver, pack**: behind the torso's back line, starting below the neck and
  ending above the hips. It must not wrap around the front or cover the near arm, and no hand
  shows through or under it.
- **Sheathed weapons**: on the back side, above the hips, not across the legs, and without a
  skin-coloured grip at hand height.
- **Hair and beards**: end above the chest's lower half; nothing hanging to hand height.
- **Hats and horns** above the head are free: the body height is measured to the top of the
  skull as the layout gives it.

## Robes and long coats
- The hem ends at the knee line or higher (0.25 of the body height above the ground). Both
  shins and both boots are fully visible below it with background between them. A floor-length
  robe hides the legs and is refused (G1): there is nothing to animate.
- Width at the hem: the heel-to-heel step plus one shin width, about 0.33-0.36 of the body
  height (it has to cover both thighs at full stride and no more). Not wider than 0.45: a bell
  wider than the step hides the gap between the legs.
- The front and back edges of the robe run straight down from the torso's front and back
  lines to the hem; no tails or flaps hanging below the hem, no slit that shows a thigh.
- Sleeves are arm-wide, not hanging bells: a sleeve wider than twice the forearm reads as a
  second limb.

## What the tool does with a still on spec
Joints come from `<id>.json` (known, not detected) and are only snapped a few pixels to the
picture. Near arm, near leg and foot are cut on those bones; the far leg is erased and redrawn
as a shaded copy; the far arm is a shaded copy when hidden, its own pixels when drawn behind
the back. The free arms are turned to hanging and swing +/-20 deg opposite to the legs; the
foot is seated with its heel on the shin's back edge.
