# Still spec: a character is a bare BODY still plus separate GEAR pictures

The image model cannot be made to place gear by prompt (shield in front of the arm, a weapon
across the legs). So it never draws gear on the character. It draws two kinds of picture, and
the tool pins the gear to the body's bones itself (`gear.py`): placement is ours, by construction.

## The recipe

**Step 1: the body.** One picture per character, on the pose layout of its build, look described
in words only (no reference picture of an older still).
```
python3 -m tools.animator spec --build human|elf|dwarf|orc --out DIR
```
writes `<build>_pose.png` (the pose control picture), `<build>_joints.json` (save a copy beside
the still as `<id>.json`, unchanged) and `<build>_reference.png` (a mannequin that passes).
Prompt, as it stands, then the look:
> "Pixel-art game character, full body, strict side view facing right, on a flat pure magenta
> background. The bare character only: NO shield, NO weapon, NO cape or cloak, NO pack, nothing
> in the hands, nothing on the back. Both hands empty and open. Only ONE visible arm, hanging
> clear of the body with background between the hand and the body; nothing skin-coloured on
> the belt. Trousers or greaves in a colour different from the skin, no bare legs. Background
> between the legs from the knees down. `<boot sentence of the build, see Feet>`. One connected
> figure: no ground, no shadow, no loose pieces. Dark outline around every form."
> + the look: build, hair and beard, each garment with its colour.

**Step 2: each gear, alone.** One small picture per piece of gear, on its gear layout:
```
python3 -m tools.animator spec --gear --out DIR
```
writes, for `shield`, `one_hand_weapon`, `two_hand_weapon`, `staff` and `cape`:
`gear_<kind>_guide.png` (black picture; cyan box = where to draw, yellow cross in a red ring =
the anchor, green arrow = up) and `gear_<kind>.json` (the JSON for a gear drawn on that guide).
Prompt, as it stands, then the look:
> "A single pixel-art game item on a flat pure magenta background, nothing else in the picture:
> no hand, no arm, no character, no shadow. `<the guide's sentence>`. One connected object,
> dark outline around it, filling the marked box."
> + the look: material and colours ("round steel shield with a gold rim and a gold sun on black").

The guide's sentence (also in `gear_<kind>.json` under `note`):

| kind | picture, box | anchor | sentence | slot, size, angle in the JSON |
|---|---|---|---|---|
| shield | 256 x 320, box 28,20-228,300 | 128,160 (its middle) | "a shield seen face-on, upright" | back, 0.36 |
| one_hand_weapon | 160 x 384, box 30,16-130,368 | 80,316 (middle of the grip) | "a hammer / sword / axe / mace standing upright, head or point at the top, grip at the bottom" | near_hand, 0.34, 110 |
| two_hand_weapon | 192 x 448, box 26,12-166,436 | 96,330 (the leading hand, a quarter up the haft) | "a greatsword / great axe / maul standing upright, head or point at the top" | near_hand, 0.62, 115 |
| staff | 128 x 448, box 34,8-94,440 | 64,330 (a quarter up) | "a staff / spear standing upright, head at the top, shaft as thick as marked" | near_hand, 0.90, 112 |
| cape | 224 x 384, box 24,16-200,368 | 176,28 (top front corner, on the shoulder) | "a cape seen from the side, hanging flat and straight down" | cape, 0.52 |

**Files to push for a character `<id>`** (a folder of these is what `batch` reads):
```
<id>.png                  the body still, 384 x 448, background keyed out
<id>.json                 copy of <build>_joints.json
<id>_gear/<name>.png      one gear picture, background keyed out   (name: shield, hammer, ...)
<id>_gear/<name>.json     copy of gear_<kind>.json; change only what differs
```
A character without gear has no `<id>_gear` folder. One gear per slot.

Gear JSON:
```
{"slot": "back",            back | near_hand | far_hand | cape
 "anchor": [128, 160],      px in the gear picture: the grip (hand slots) or the pin point
 "up": [0, -1],             the gear's up direction in its picture (picture up = [0, -1])
 "size": 0.36,              its length along `up`, as a fraction of the body height
 "in_front": false,         hand slots: true = drawn over the hand, false = behind it (the hand grips it)
 "angle": 110,              hand slots: degrees between the forearm and the gear's up, turned to the
                            facing side: 90 = straight out ahead of a hanging forearm, 180 = back up the arm
 "at": [0.5, 0.10]}         back / cape: pin point = this share of the way from pelvis to neck, and
                            this many body heights behind the spine
```
What the baker does with each slot:
- `back`: pinned to the spine; drawn behind the torso, the near leg and the near arm, in front of
  the far arm and far leg. It keeps one angle for the whole walk and moves by whole pixels, so
  its pixels are the same in every frame.
- `near_hand` / `far_hand`: grip on the middle of the drawn hand, angle fixed to the forearm. A
  near hand that holds gear is a carried arm: it keeps the still's pose and swings at 40 %.
- `cape`: hung from its pin point on the spine, sways with the cloth pendulum (`cloth.py`).
Rules on the result: R20-R25 and G12-G15 in `RULES.md`.

**Worked example, the paladin: body + shield (back) + hammer (near_hand) + nothing else.**
```
PAL.png        body: "stocky human man, short black hair and beard, white tunic with a dark red
               collar and belt, dark grey trousers, brown ankle boots" + the step 1 sentences
PAL.json       copy of human_joints.json
PAL_gear/shield.png   on gear_shield_guide.png: "kite shield, gold rim, black field, gold sun"
PAL_gear/shield.json  {"slot": "back", "anchor": [128, 160], "up": [0, -1], "size": 0.36}
PAL_gear/hammer.png   on gear_one_hand_weapon_guide.png: "warhammer, steel head, brown wooden haft"
PAL_gear/hammer.json  {"slot": "near_hand", "anchor": [80, 316], "up": [0, -1], "size": 0.34,
                       "angle": 110, "in_front": false}
python3 -m tools.animator batch <folder> --out out/<name>
```
`python3 -m tools.animator spec --example --out DIR` writes exactly this with a mannequin and a
flat synthetic shield and hammer (`samples/stills_gear/PAL_SYN*`); it passes every rule at 56
and 112 px. `samples/stills_gear/HR6.1_SPLIT*` is the accepted paladin HR6.1 with its shield and
hammer cut out by hand into gear pictures (`tests/fixtures.py`), also accepted at both sizes.

## What a body still must be (G1-G13, G15 in `RULES.md`)
The numbers live in `spec.py`; `tests/test_arms_feet.py::TestSpec` draws a character exactly on
them for each build and checks that it passes every G rule and then walks with no R failure.
A body still is refused when it has gear drawn in (G12): a rimmed blob (shield), a long thin
straight object (sword, staff), anything in the near hand, or cloth hanging behind the back.

## Canvas
- 384 x 448 px, transparent background, hard alpha. Ground line at y = 428; pelvis at x = 176.
- Drawn on flat magenta and keyed out: no magenta or purple-pink pixel may be left (G10).
- One figure, one connected silhouette. No ground plate, shadow, blood pool, dust or loose
  pieces: any loose blob of 9 px or more refuses the still (G13).
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
  18 deg, hand empty (open, or a loose fist). Forearm and hand are **clear of the torso with a visible gap of
  background** between them and the belly (at least 1.2 % of the body height; 10-40 px in the
  reference figures). The hand never rests on the belt, hip or thigh.
- The upper arm does cross the chest in side view. Draw it as its own outlined shape in a
  colour that differs from the chest, shoulder to elbow, straight.
- **Far arm**: either hidden entirely behind the torso (the default; the tool then draws a
  shaded copy of the near arm), or its hand and forearm clear of the body **behind the back**
  with background on the back side of the hand (the tool then cuts that hand out and uses its
  own pixels, no copy). Never half over the body, never crossing the chest, never on a weapon
  held by the other hand.
- Nothing in either hand (G12); a two-handed weapon is a gear picture in the `near_hand` slot.
- Nothing on the torso between the chest and the hips may have the hand's colour and size:
  no skin-coloured pouch, buckle plate, glove on the belt or blood stain. The gate cannot tell
  it from a hand and refuses the still.

## Feet (owner rule R6, G9)
- Flat on the ground line, sole level, pointing right.
- The heel's rear end is directly under the back edge of the shin: no heel block sticking out
  behind the leg. The whole foot runs forward from there.
- Length, per build (`spec.foot_numbers`, also in `<build>_joints.json` under `foot`). "allowed"
  is what G9 accepts for that build's layout: from the shortest boot that is long enough for
  the layout's shin width up to 0.60 of the leg. The boot is never stretched or trimmed.

| build | boot / leg (hip to ankle): allowed | boot / leg: the mannequin | boot length, heel to toe | shin width at the ankle | boot / shin width | toe ahead of the shin's front edge | boot sentence for the prompt |
|---|---|---|---|---|---|---|---|
| human | 0.25-0.60 | 0.30 | 0.120 BH = 47 px | 0.072 BH = 28 px | 1.67 | 0.048 BH = 19 px | "ordinary ankle boots; each foot about a third as long as the whole leg and clearly longer than the lower leg is wide" |
| elf | 0.24-0.60 | 0.27 | 0.115 BH = 46 px | 0.060 BH = 24 px | 1.92 | 0.055 BH = 22 px | "slim ordinary ankle boots; each foot a little under a third as long as the whole leg and almost twice as long as the lower leg is wide" |
| dwarf | 0.335-0.60 | 0.46 | 0.160 BH = 50 px | 0.080 BH = 25 px | 2.00 | 0.080 BH = 25 px | "ordinary ankle boots, not oversized and not long; each foot about as long as the shin is tall and twice as long as the lower leg is wide" |
| orc | 0.285-0.60 | 0.35 | 0.135 BH = 57 px | 0.084 BH = 35 px | 1.61 | 0.051 BH = 21 px | "ordinary heavy ankle boots; each foot about a third as long as the whole leg and clearly longer than the lower leg is wide" |

  Add to every build's sentence: "the heel of each boot ends straight under the back of the leg,
  no heel sticking out behind; flat soles on the ground line, toes not curled up; boot shafts
  as narrow as the lower leg, no fur cuffs" (`spec.BOOT_WORDS`, `spec.BOOT_WORDS_ALL`). Do not
  write "long boots": with it the dwarf came back at 0.71-0.77 of the leg (limit 0.60).
- **Dwarf, history**: layout 1 (boot 0.150 BH under a shin 0.096 wide) came back with boots
  shorter than the shin is wide, 6 of 6. Layout 2 (boot 0.200 = 0.58 of the leg, the top of the
  range, plus "long boots" in the prompt) came back too long, 0.71-0.77. Layout 3, now: boot
  0.160 BH = 0.46 of the leg, the middle of 0.335-0.60, under the same slim shin (0.080). It
  passes G9 with the shin drawn 1.4 x as thick, or the boot 0.8 x as short, or the boot 1.29 x
  as long; not with a thick shin and a short boot at once.
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
| near_toe | +0.205, 0.000 | +0.215, 0.000 | +0.225, 0.000 | +0.210, 0.000 |
| far_hip | -0.020, 0.450 | -0.020, 0.480 | -0.020, 0.410 | -0.020, 0.440 |
| far_knee | -0.060, 0.247 | -0.037, 0.258 | -0.087, 0.237 | -0.082, 0.249 |
| far_ankle | -0.139, 0.055 | -0.130, 0.055 | -0.155, 0.065 | -0.143, 0.058 |
| far_heel | -0.175, 0.000 | -0.160, 0.000 | -0.195, 0.000 | -0.185, 0.000 |
| far_toe | -0.055, 0.000 | -0.045, 0.000 | -0.035, 0.000 | -0.050, 0.000 |

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
- Gear (G12): none in the body still, see the recipe. (Until 22 Nov the shield was asked for "on
  the back" in the same picture; it came back over the near arm about half the time, HR6.2.)
- Legs (G15): "trousers or greaves in a colour different from the skin".
- Boots (G9): the build's boot sentence under Feet above.
- Background: flat pure magenta (255, 0, 255), nothing else magenta or purple-pink in the
  picture. Our intake removes the 1 px half-keyed rim (`intake.clean_key`); magenta left
  anywhere else refuses the still (G10).
- **The reference picture must not be the old still.** The model copies the pose of a picture
  it is shown: given the old HR still as a look reference it redraws that still's arms and
  legs and ignores the layout. Give the pose layout as the only picture and describe the look
  in words: build, hair and beard, each garment with its colour. Gear is described only in its
  own gear picture's prompt.

## Gear
Drawn separately, never in the body still: see the recipe at the top. In the body still:
- **Hair and beards**: end above the chest's lower half; nothing hanging to hand height, no long
  hair down the back (more than 0.010 BH squared behind the back line counts as a cape, G12).
- **Hats and horns** above the head are free: the body height is measured to the top of the
  skull as the layout gives it.
- Stills made before 22 Nov with the gear painted in (no `"format": "body"` in their JSON, no
  `_gear` folder) are still read the old way: weapon cut with the forearm, shield on the back
  as part of the torso, G7 and G11.

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
