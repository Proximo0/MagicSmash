# Animator: one still in, physically checked walk sheets out

Python 3 + numpy + Pillow only. No model draws motion: a still is cut into rigid parts on a
side-view skeleton, the skeleton walks on a published gait table, frames are baked to game
size, and every frame goes through a body-physics gate.

```
python3 -m tools.animator bake samples/HR6.1_1.png --joints samples/HR6.1_1.json --out out/
python3 -m tools.animator all            # every samples/*.json + out/contact.png
python3 -m tools.animator auto samples/HR6.1_1.png   # estimated joints JSON
python3 -m tools.animator batch samples/stills --out out/batch   # fit + gate + bake all 24 stills
python3 -m tools.animator spec --build all --out out/spec        # pose picture + joints per build
python3 -m unittest discover tools/animator/tests                # from the repo root
cd tools/animator/tests && python3 -m unittest discover -s . -p "test_*.py"
```
How a still must be drawn so it fits the rig: `STILL_SPEC.md`. Every rule: `RULES.md`.
Relative paths are resolved against `tools/animator/` when they do not exist from the cwd.

Scope note (coordinator, 22 Nov): the skeleton/keyframe/IK runtime will be SkelForm
(`rusty_skelform`, MIT). So this tool only has the walk, no run/idle/attack/BVH, and it
writes the cut as plain files (`out/<name>_parts/*.png` + `rig.json`: pivot, parent bone,
draw order, bone lengths, rest angles, sha1 per part) so they can be packed into a `.skf`.

## How it works
1. **Still** (`cut.load_still`): the 4-frame strip is split at empty columns (frames that
   touch are split at the thinnest column in their middle third, and small bits of the
   neighbouring frame are dropped). The still is the frame named in the JSON (`"frame"`),
   or else the one with the widest spread of the feet (`pick_still`).
2. **Rig** (`rig.py`): pelvis, spine, head; per side upper arm, forearm, hand, thigh, shin,
   foot. Bone lengths are measured once from the JSON joints. Angle conventions are in the
   module docstring. Joint limits (`JOINT_LIMITS`, degrees), AAOS normal range of motion
   (Greene & Heckman 1994) rounded out a few degrees: spine -30..90, hip -30..125,
   knee 0..150 (backwards only), ankle -50..30, shoulder -60..180, elbow 0..150
   (forwards only), wrist -70..80 (rigid in v1). Two-bone IK always puts the knee in front.
3. **Cut** (`cut.py`): hard alpha (>=128); `erase` polygons (the red ground plate of
   HR6.1_1). Each opaque pixel is labelled, first match wins: gear polygon (+1 px outline)
   > near arm capsule > `torso_keep` polygon > near leg capsule > torso/head capsule >
   far limb capsule / `far_poly` > nearest bone by distance/radius. A limb capsule only
   claims pixels past its proximal joint (the joint-aware boundary). Torso pixels below the
   hips within 1.8 radii of a leg go to that leg, so no scraps hang between the legs.
   Holes: where the near arm, held gear or the erased far limbs covered the torso
   (row span of the torso, plus an optional hand-drawn `body_poly`), the hole and the
   1-px outline the arm left behind are refilled row by row from the front (facing) side,
   then by 8-neighbour majority; transparent slits deeper than 0.75 radius inside a leg are
   filled the same way. Overlap caps: at shoulder, hip, elbow, knee and ankle the part
   drawn behind takes the front part's pixels in a disc (one bone radius), so a turned
   joint shows that disc, not a gap. Far arm and far leg = copies of the near ones at 70 %
   value, snapped back to the still's palette, drawn behind the torso.
4. **Walk** (`motion.py`): thigh, knee and ankle angles per 5-10 % of the cycle read from
   the published normal adult curves (Winter, *Biomechanics and Motor Control of Human
   Movement*, 4th ed. 2009; Perry & Burnfield, *Gait Analysis*, 2nd ed. 2010). Stance 62 %
   (toe off). Far leg = the same table half a cycle later. Arms: shoulder +-20 deg about +2 (hanging),
   elbow 8-28 deg, opposite the legs (Murray, Sepic & Barnard 1967). Trunk 1.5-2.5 deg
   extra lean, twice a cycle. Retargeting (`Gait`): the footprint at heel strike and the
   stride come from the table's own FK on this character's bone lengths (stride =
   distance the planted foot must travel back between heel strike and toe off, divided by
   0.62), so a short-legged character takes shorter steps. The planted foot is fixed on the
   ground line: heel rocker (turns about the heel while the toe is up), flat foot, forefoot
   rocker (turns about the toe). Pelvis height = as high as the stance leg allows at the
   table's knee angle (this gives the bob twice a cycle), smoothed but never higher than
   reachable; the leg is then solved by two-bone IK. Swing: table FK, blended so it leaves
   and lands exactly where stance needs it, and lifted if it would touch the floor.
5. **Bake** (`bake.py`): 56 px from the ground line to the head top (`head_top` joint;
   hat brims above it are extra), canvas 96x80, foot line y=74, pelvis x=46, walk in place.
   Each part is inverse-mapped from the still at 4x game size (nearest neighbour, so only
   still colours exist), far limbs, torso, near leg, near arm, gear. 4x4 -> 1 reduction:
   opaque if >= 8 of 16 sub-pixels are; colour = most common sub-pixel colour, dark
   (luma < 60) outline colours get +1.5 votes so 1-px outlines survive the ~2:1 shrink.
   Tidy pass: 1-px slits/pinholes closed, lone specks removed. Output per character:
   `<name>_walk{4,8}_r.png`, `_l.png` (mirror), `_r_x4.png`, `.gif` (125 ms/frame at 8
   frames = 1 s cycle, 120 steps/min, brisk normal cadence), `<name>.json` (speed in px per
   cycle for the game to move the sprite: the planted foot then stays put on screen).
6. **Gate** (`checks.py`), on every baked frame, failures read `frame i: rule: detail`:
   `bone_length` (posed joints vs rig x scale, 1 px), `joint_limit`, `foot_slide`
   (planted foot's footprint moves back by speed/frames, 1 px), `stance_ground` /
   `foot_sink`, `foot_direction` (toe ahead of heel), `draw_order` (far < torso < near,
   never changes), `two_legs` (leg-wide runs, >= 60 % of a shin, in the leg rows of the
   output pixels; arms/gear in front are bridged, rows with cape/robe skipped; > 2 runs
   fails, < 2 when the feet are apart fails), `rigid_part` (sha1 of unposed torso, back and
   gear pixels per frame = the cut's), `cycle_closes` (phase 1.0 pose = frame 0 within
   1 px), `mirror_timing` (equal stance, far step exactly half a cycle later, per-frame
   contacts mirror-equal), `palette` (no new colours, hard alpha). Tests break each rule on
   purpose (third leg pasted, knee mirrored forward, sliding/sinking foot, legs swapped,
   shield pixel changed, stretched bone, reversed foot, open cycle, uneven steps, new colour).
7. **Sheet** (`sheet.py`): `out/contact.png`, old strip above, new 8-frame walk (2x) below.

## Joint JSON (samples/*.json)
`ground_y`, `joints` (head_top, neck, pelvis, shoulder, elbow, wrist, hand_tip, hip, knee,
ankle, heel, toe; heel/toe on the sole), optional `far` joints (only to erase the far limbs),
`far_shoulder_offset`/`far_hip_offset` (where the far copy hangs; -19 px for the 3/4-view
elves), `radius` per bone, polygons `gear` (attach `hand` or `spine`), `torso_keep`,
`far_poly`, `body_poly`, `erase`. Sample joints were placed by eye on zoomed grids.

`auto_joints()` (silhouette + proportions) median error on the six samples vs the hand
joints: head_top 2 px, knee 3, hand_tip 3, neck 6, wrist 6, heel 7, ankle 8, pelvis 8,
shoulder 8, toe 9, elbow 9, hip 10; worst 38 px (arms on HR6.2). Only a starting point:
fine for feet and head, unreliable for hips and arms. Production joints should come
from the pose layout.

## Batch, fit, gates (stills in samples/stills/)
- `fit.py`: the layout joints are a prior only. Snapped to the picture: plates/shadows removed
  (thin dark rows under the feet), ground = lowest opaque rows, head top and neck from the
  silhouette, legs tracked up from the feet along the medial axis (knee by least squares),
  torso front/back lines from the silhouette's reach, front hand = blob past the front line.
  No hand-drawn shapes. `data["fit"]` holds moved_px per joint, flags and a score (0..1).
- `autocut.py`: parts are labelled from capsules around the fitted bones; cape = behind the
  back line below the neck; robe = below the hip and not leg. Far limbs are copies darkened
  in OKLab (L x0.75, chroma x0.9) and snapped to the still's 48-colour palette.
- Cloth (`cloth.py`): steady-state damped pendulum per harmonic (1.6 swings/cycle, zeta 0.35),
  so it never needs warm-up and the cycle closes exactly. Cape: 3 deg drag + 5 deg sway about
  its top anchor. Robe: each row sheared between the hindmost and foremost leg (0 at the hip,
  full at knee height), hem lag 0.6.
- Stride: thigh swing gain fitted to the still's own step (x0.95), quantized to 8 game px per
  cycle so the stance foot moves whole pixels; knee lift 0.30, heel-strike pitch <= 20 deg,
  stance dorsiflexion <= 26 deg. A stride the legs cannot reach (a planted knee past 55 deg or
  a planted foot steeper than 45 deg on its toe) is stepped down by 8 px until stance is stance.
- Arms (R18): a free arm is normalised to hanging before the swing is applied. Whatever pose
  the still drew (stretched forward, bent at the belt), the posed upper arm is the table's
  absolute angle: 2 deg +/- 20 deg about straight down (23 at gain 2; Murray 1967: 30-40 deg
  total), elbow 8 deg (arm back) to 28 deg (arm forward), furthest back at the same-side heel
  strike, far arm half a cycle later. v1 centred the swing half-way to the still's drawn angle
  and kept the still's elbow, which is why arms were held out in front. Only a near arm
  carrying long gear (> 0.30 body heights past the wrist) keeps the drawn pose and swings x0.4.
- Downscale: 6x supersample, per-block mode with a bonus for dark detail (outlines, eyes),
  palette locked; R16 checks the stance foot moves <= 1 px against its footprint.
- Foot (owner rule R6, `foot.py`): true by construction. Shin edges are measured on the shin
  (0.55-0.2 shin lengths above the ankle; v1 measured down to the ankle and took the boot's heel
  block for the shin). Sole = longest near-level edge (-25..+60 deg) of the lower convex hull of
  the pixels below the ankle; foot = everything below the ankle line; length = the drawn boot.
  The foot part is re-seated: shifted whole pixels along the sole so its heel's rear end is
  the shin's back-edge offset behind the ankle joint (flush at a neutral ankle), nothing
  stretched or dropped. The walk never plantarflexes past the angle that would swing the heel
  more than 0.8 game px behind that line (`plantar_limit`, at most 20 deg). G9 refuses, before
  baking, a boot under 0.24 of the leg length (the still is wrong) or one not longer than the
  shin is wide. v1's "short boots on steep shins" was mostly its own measurement: it put the
  heel where the leaning shin's back line met the ground, mid-boot.
- Arms in the still (owner: "there is three arms there"; G8, R17): `fit.hand_census` lists
  every other blob of the front hand's colour (hue within 30 deg, chroma x0.45-1.9, lightness
  -0.10..+0.35, hand-sized or forearm-shaped, at arm's reach, rows from 0.12 body heights
  under the shoulder to 0.08 under the hip). At the silhouette's back edge = the far arm,
  visible: it is erased from the body with a 3 px rim, the hole filled, and its own pixels
  become the far forearm and hand (turned into the near forearm's frame, tip on the rig's
  hand tip; the shaded copy of the near sleeve is kept only above where the real pixels
  start, so there is never a second hand). With body on both sides = an arm drawn over the
  body: G8 refuses the still. Nothing found = far arm hidden: shaded copy as before. R17 then
  counts on every baked frame: any hand-sized blob of the hands' colours in the arm rows that
  is not on a forearm part fails.
- **Rulebook `RULES.md`**: every rule (R1-R18 on baked frames, G1-G9 on the input) with its
  check function and a failing-example test; `tests/test_rules.py::TestRulebook` fails if
  one is missing or an owner rule (third leg, crooked elbow, backwards foot, heel, third arm,
  short boot) loses its mark. A still failing a G rule is never animated: `out/batch/needs_attention/<id>.png`
  shows the fitted skeleton with failed joints ringed. Any failed rule -> nothing in
  `accepted/`, and `batch` exits 1.
- `skf.py` writes `<id>.skf` (zip: armature.json, atlas0.png, readme.md). **Unverified against
  the SkelForm editor**: rot units, y axis, Vec2 form, version string, element names and the
  texture anchor are guesses, named constants at the top of skf.py. The robe shear is
  exported rigid. Open one in the editor (v0.9) once and flip the constants.

Batch result (22 Nov, after the three-arm fix, arm swing and foot model): 5 accepted
(HR1.2 HR2.2 HR3.1 HR4.2 HR5.1), 19 rejected. Of the 7 accepted before, HR1.1, HR6.1 and HR6.3
had an arm left painted on the body (three arms in the walk); HR4.1 and HR6.4 are refused by
the same rule (two-handed crossbow; a hand on the shield).
- G8, arm drawn over the body: HR1.1 HR1.3 HR1.4 HR2.1 HR2.3 HR2.4 HR3.2 HR4.1 HR4.4 HR5.2 HR5.3
  HR5.4 HR6.1 HR6.3 HR6.4. HR2.1 and HR5.2 are false alarms of the colour test (blood on the
  tabard, a belt pouch); both fail another rule as well.
- G9, boot too short or shin too wide for it: HR1.1 HR1.3 HR2.3 HR2.4 HR3.2 HR3.3 HR3.4 HR4.3
  HR5.2. G1/G2/G5 (robes, dwarves, layout): HR2.3 HR3.2 HR3.3 HR3.4 HR4.3 HR5.3. G4: HR2.1.
  G6: HR1.3 HR4.4 HR5.4. G7: HR6.2.
- R6 no longer rejects anything: HR1.2 and HR2.2 pass with the new foot model.
- Timing: about 0.9 s mean and 2.5 s max per character on one core.

## Limits (what it cannot cut well)
- Long robes and skirts (HR3.2 wizard, the elves' loin cloth): kept rigid with the torso, so
  only the boots move under them; looks stiff next to hand animation.
- Arms drawn across the body leave a guessed area behind them; the fill is plausible
  cloth, but you can see it when the arm swings well away (HR1.1 cape edge).
- Stills whose two arms are both prominent (3/4 view) need `far_shoulder_offset`, and the
  far arm is always a darkened copy of the near one: skin becomes a dark red-brown sleeve
  (palette snap), which reads as a sleeve rather than a shadowed bare arm.
- At 56 px the source is shrunk ~2.2:1; faces and thin straps lose detail.
- Polygons (`far_poly`, `torso_keep`, gear) are hand work per still (5-10 min each); the
  art runner's exported joints (samples/stills/, not yet present) will need arm points fitted
  to the drawn arm before cutting.
- The slide/ground checks use the posed joints (float, game px); a 1-px pixel jitter from
  the reduction is not itself checked.

- The hand test is by colour. It misses a second arm whose hand has another colour than the
  front hand (two different gloves) and it refuses stills with hand-coloured things on the
  torso. Stills drawn on `STILL_SPEC.md` do not depend on it.
- Normalising the arm to hanging uncovers the torso where the still drew the arm; that area
  is a fill (HR2.2's chest is patchy). The fitted upper arm also takes whatever chest it lies
  on (HR2.2's emblem swings with the arm). Stills on spec draw the upper arm as its own shape.
- A boot's shaft above the ankle line belongs to the shin; where the still drew the foot
  toe-up 40 deg the shaft keeps that angle (HR3.1: red-brown boot pixels at the shin's end).
- The six legacy hand-joint samples (`all`, 130 px strips) were not re-tuned for the new foot
  model and arm rules: 5 of 6 now fail R6/R16/R18 there.

## Next
Take the joints of a still drawn on spec as exact (skip the fit's snapping) and cut the far arm
from the layout when it is drawn behind the back.
Cut held gear (strapped shields) as its own part instead of rejecting (G7); robes under G5; verify the .skf in the editor.
Monster rigs (quadruped, floater, blob), four directions (front/back need a different cut),
layout-supplied joints on the MSI, arm-point fitting for the art runner's joint files,
packing `*_parts/` into SkelForm `.skf`.
