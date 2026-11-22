# Animator: one still in, physically checked walk sheets out

Python 3 + numpy + Pillow only. No model draws motion: a still is cut into rigid parts on a
side-view skeleton, the skeleton walks on a published gait table, frames are baked to game
size, and every frame goes through a body-physics gate.

```
python3 -m tools.animator bake samples/HR6.1_1.png --joints samples/HR6.1_1.json --out out/
python3 -m tools.animator all            # every samples/*.json + out/contact.png
python3 -m tools.animator auto samples/HR6.1_1.png   # estimated joints JSON
python3 -m unittest discover tools/animator/tests
```
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
   (toe off). Far leg = the same table half a cycle later. Arms: shoulder +-17 deg about +2,
   elbow 10-35 deg, opposite the legs (Murray, Sepic & Barnard 1967). Trunk 1.5-2.5 deg
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

## Next
Monster rigs (quadruped, floater, blob), four directions (front/back need a different cut),
layout-supplied joints on the MSI, arm-point fitting for the art runner's joint files,
packing `*_parts/` into SkelForm `.skf`.
