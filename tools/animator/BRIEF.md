# The animator: one still picture in, physically checked walk sheets out

Curtis, 22 Nov 2026: "i see a third leg there and some off the feet are pointed the wrong directions"; "we are going
to have to build our own animator that works because i dont want to pay for it"; "we need a way to keep you on track
with the body physics". So: free, ours, and the motion is never drawn by an AI model. A model draws ONE still of a
character; this tool cuts it into rigid parts on a skeleton, moves the skeleton with a real gait, bakes sprite
strips, and refuses any frame that breaks a body rule.

Python 3 with numpy and Pillow only (no scipy, no installs, no paid services, no model downloads).
Everything under `tools/animator/`. Samples: `samples/*.png` are 4-frame side-view walk strips (RGBA, about 80x130
per frame, facing right) made the old way; use ONE frame of each as the still (the widest stride frame), the other
frames only as a look reference.

## Build
1. `rig.py`: a side-view humanoid skeleton: pelvis, spine, head, and per side upper arm, forearm, hand, thigh, shin,
   foot. Bone lengths fixed per character (measured once from the still). Joint limits in a table (knee bends
   backwards only, 0 to 150 deg; elbow forwards only; hip, shoulder, ankle, spine ranges from standard anatomy).
   Forward kinematics; a `Rig` loads/saves JSON (joint positions in the still, part list, draw order).
2. `cut.py`: given the still and its joints, cut rigid parts: head+torso (with cape and anything strapped to the
   back as part of the torso, or as its own part hung from the spine when the JSON says so), near arm (upper, fore+hand),
   near leg (thigh, shin, foot), and gear held in a hand (shield, weapon: rigid, pinned to the hand). Pixels go to
   the nearest bone with joint-aware boundaries; each part keeps a round overlap cap at its joints so no gap opens
   when it turns. The FAR arm and FAR leg are copies of the near ones, darkened (about 70% value), drawn behind the
   torso: the still never has to show them. Holes left in the torso where a limb or shield covered it are filled
   from neighbouring torso pixels. Joints for the samples: write them by looking at the picture (`samples/*.json`);
   also provide `auto_joints()` that estimates them from the silhouette and proportions, and say how good it is.
   In production the joints come from the pose layout the still was drawn from, so the JSON format must be simple.
3. `motion.py`: a motion is a table of joint angles per phase of the cycle plus pelvis height and forward speed.
   v1 walk from published gait-analysis curves for normal adult walking (sagittal hip, knee, ankle angles over the
   gait cycle, arm swing opposite to the legs, pelvis bob twice a cycle); cite the source in the README. Also idle
   (breathing), run, and a one-handed attack swing. Add `bvh.py`, an importer that reads a BVH motion-capture file
   and projects it to these side-view joint angles, so recorded motion can replace any table; test it with a small
   BVH you write in the test. Retarget to each character's own bone lengths; solve the stance foot so it stays on
   the ground line (two-bone IK on the leg when FK would lift or sink it).
4. `bake.py`: pose the parts (rotate about joints at 4x supersample from the source, far limbs first, torso, near
   leg, near arm, gear), then reduce to game size with a pixel-art-safe downscale and lock the palette to the
   still's colours (no new colours, hard alpha). Output per character: strips for 4 and 8 frames at 56 px body
   height on a fixed canvas with a common foot line, a 4x preview strip, and an animated GIF. Left-facing is a
   mirror. CLI: `python3 -m tools.animator bake samples/HR6.1_1.png --joints samples/HR6.1_1.json --out out/`.
5. `checks.py`, the body-physics gate, run on every baked frame; a failure names the frame and the rule:
   bone lengths equal to the rig's within 1 px; every joint inside its limits; the stance foot does not slide
   (its ground position moves back at exactly the body's forward speed, within 1 px at game size) and never sinks
   below or floats above the ground line; both feet point the facing direction; near and far limbs never swap draw
   order; exactly two legs (count leg-wide runs across the leg rows of the baked frame, as a check on the output,
   not the rig); gear and torso parts are the same pixels in every frame apart from the rigid move (hash of the
   unposed part); the cycle closes (last frame leads into the first); left and right steps are mirror-equal in
   timing. Tests must show each rule failing on a deliberately broken input (third leg pasted in, knee bent
   forward, sliding foot, swapped legs, changed shield).
6. `sheet.py`: a contact sheet (old 4-frame strip above, new 8-frame strip below, per sample, with the check
   result) to `out/contact.png`, and GIFs to `out/`.

## Done
- `python3 -m unittest discover tools/animator/tests` passes; `tools/animator/README.md` says how it works, every
  number chosen and why, the limits (what kinds of picture it cannot cut well) and what is next (monsters:
  quadruped, floater, blob rigs; four directions; layout-supplied joints on the MSI).
- All six samples baked, checks green, `out/contact.png` written. LOOK at your own output (Read the PNG) and fix
  what looks wrong (gaps at joints, smeared pixels, a shield that floats, stiff or sliding walk) before reporting.
  Curtis judges this by eye against shipped games.
- Do not commit, push, install packages, write outside this checkout, or message anyone.
Report in at most 15 lines: what is built, test summary line, per-sample check results, honest weak points.
