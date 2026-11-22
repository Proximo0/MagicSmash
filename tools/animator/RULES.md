# Body rulebook

Every rule a baked walk (R) or an input still (G) must pass. One rule per line:
`number | owner mark | the rule in plain words | check: function | test: failing-example test(s)`.

- `owner` marks a rule the owner caught by eye (third leg, crooked elbow, backwards foot, heel,
  third arm).
  Never drop or weaken one of these.
- `tests/test_rules.py::TestRulebook` fails when a rule has no check function or no failing-example
  test, when an owner rule loses its mark, or when a check or rule number in the code is not listed here.
- The pose and layout that pass every G rule by construction are in `STILL_SPEC.md`
  (`python3 -m tools.animator spec` writes the pose picture and joints per build).
- Pixel tolerances ("1 px") are pixels of the 56 px sprite, the size the rules were written for.
  Every still is also baked at 112 px, where the same still is twice as big: there the same
  length is 2 baked pixels (`checks.TOL_PX x ctx["size_x"]`), and the walk is the same walk. A
  character must pass every R rule at both sizes.
- Never loosen a rule. 22 Nov (stills drawn on spec): G8 tightened, G10, G11 and R19 added; R1,
  R16 and R17 measure more exactly (their limits are unchanged).
- G rules gate the still before anything is animated. A still that fails one is not baked; it goes to
  `out/batch/needs_attention/<id>.png` with the failed joints ringed. R rules run on every baked frame.
  A character that fails any rule writes nothing into `out/batch/accepted/`, and `batch` exits 1.

```
R1  | owner | Exactly two legs: no third leg-shaped run of pixels below the knees in any frame (a run made only of one leg's own foot pixels, in a row where that leg has another run, is its raised toe) | check: checks.two_legs | test: TestBrokenInputs.test_third_leg
R2  | -     | Exactly two arms, and each hand sits on the end of its own forearm | check: checks.two_arms | test: TestBrokenInputs.test_third_arm, TestBrokenInputs.test_hand_off_forearm
R3  | -     | Knees bend backwards only (0 to 150 deg) | check: checks.joint_limits | test: TestBrokenInputs.test_knee_bent_forward
R4  | owner | Elbows bend forwards only, never crooked backwards (0 to 150 deg) | check: checks.joint_limits | test: TestBrokenInputs.test_elbow_bent_backwards
R5  | owner | Both feet point the way the character faces (toe ahead of heel) | check: checks.feet_facing | test: TestBrokenInputs.test_foot_backwards
R6  | owner | The heel is the bottom of the shin's back edge: nothing of the foot sticks out more than 1 px behind that line, and the foot reaches ahead of the shin's front edge | check: checks.heel_flush | test: TestBrokenInputs.test_foot_shifted_backwards_rig, TestBrokenInputs.test_foot_shifted_backwards_pixels
R7  | -     | A planted foot does not slide along the ground | check: checks.stance_foot | test: TestBrokenInputs.test_sliding_foot
R8  | -     | A planted foot stands on the ground line, neither sunk nor floating | check: checks.stance_foot | test: TestBrokenInputs.test_sinking_foot
R9  | -     | Bones keep their length in every frame | check: checks.bone_lengths | test: TestBrokenInputs.test_bone_stretched
R10 | -     | Hips, shoulders, ankles and spine stay inside human joint ranges | check: checks.joint_limits | test: TestBrokenInputs.test_hip_overextended
R11 | -     | Far limbs are drawn behind the body, near limbs in front | check: checks.draw_order | test: TestBrokenInputs.test_swapped_legs
R12 | -     | Rigid parts (shield, weapon, head) never change their pixels | check: checks.rigid_parts | test: TestBrokenInputs.test_changed_shield
R13 | -     | The cycle closes: the frame after the last equals the first | check: checks.cycle_closes | test: TestBrokenInputs.test_cycle_not_closed
R14 | -     | Left and right steps take equal time, half a cycle apart | check: checks.mirror_timing | test: TestBrokenInputs.test_uneven_steps
R15 | -     | Only colours of the still appear in the baked frames | check: checks.palette | test: TestBrokenInputs.test_new_colour
R16 | -     | The shrunk stance foot jitters at most 1 px frame to frame and its lowest row is on the ground row (its ground end is read from its bottom 2 rows at 56 px, the same slice, 4 rows, at 112 px) | check: checks.foot_jitter | test: TestBrokenInputs.test_foot_jitter
R17 | owner | At most two arms and two hands in any frame, counted on the baked pixels: every hand-sized blob of the hands' colours in the arm rows lies on a forearm part, at the end of that forearm; none is painted on the torso, cape, robe or a leg (skin along one forearm's own bone, a bare forearm and its hand parted by a wristband, is that one arm; a blob beside the bone counts as another hand) | check: checks.arm_count | test: TestArms.test_third_hand_on_torso, TestArms.test_hand_off_its_forearm_pixels
R18 | -     | Arms swing opposite to the legs and hang near the body at mid-stance: at a foot's heel strike the arm on that side is the one behind; where the feet pass, each wrist is within 0.45 arm lengths of the line under its shoulder; a free upper arm never leaves hanging by more than 32 deg, is centred on hanging and swings at least 20 deg (an arm carrying long gear is held steady and exempt) | check: checks.arm_swing | test: TestArms.test_arm_held_out_in_front, TestArms.test_arms_in_step_with_legs, TestArms.test_stiff_arms
G1  | owner | The silhouette shows two separate legs and a hand (no missing or extra limb) | check: fit.gate_still | test: TestGate.test_g1_missing_leg
G2  | -     | Limb lengths are in human ranges of the body height, front and back leg alike | check: fit.gate_still | test: TestGate.test_g2_long_thigh
G3  | owner | In the still, knees bend back and elbows bend forward only (-5 to 150 deg) | check: fit.gate_still | test: TestGate.test_g3_knee_bent_forward, TestGate.test_g3_elbow_bent_backwards
G4  | owner | In the still, both feet point the facing way | check: fit.gate_still | test: TestGate.test_g4_foot_backwards
G5  | -     | The fit of the skeleton to the picture scores at least 0.7 | check: fit.gate_still | test: TestGate.test_g5_low_score
G6  | -     | No second arm drawn over the body that would stay painted on the torso | check: fit.gate_still | test: TestGate.test_g6_arm_over_body
G7  | -     | Held gear (a strapped shield) is not sliced between the forearm and the body | check: autocut.gate_cut | test: TestGate.test_g7_shield_cut_through
G8  | owner | Every arm visible in the still belongs to exactly one arm part: no hand or bare forearm is drawn over the body, not even partly (it cannot be cut from the torso and would stay painted on it as a third arm). Measured: the area of all blobs of the front hand's colour drawn over the body (each at least 0.05 of the front hand's lit area), summed, must stay under 0.15 of that hand (until 22 Nov: one blob of 0.50); on a still drawn on the layout the hand's colour is read at the layout's hand, not at the tip of what it holds | check: fit.gate_still | test: TestArms.test_g8_arm_on_body_real_stills, TestArms.test_g8_hand_blob_inside, TestArmOverlap.test_g8_partly_overlapping_arm_on_spec_still, TestArmOverlap.test_g8_small_blobs_add_up
G9  | owner | The drawn foot can keep R6 in every frame: it is at least 0.24 of the leg length as drawn (a shorter boot is the still's fault and is refused, never stretched) and longer than the shin is wide at the ankle | check: fit.gate_still | test: TestFoot.test_g9_short_boot, TestFoot.test_g9_boot_shorter_than_shin_is_wide
G10 | owner | No pixel of the background key's colour (magenta, pure or shaded: red and blue both at least 60, green at most 0.35 of the smaller, red and blue within 20 % of each other) is left in the still. Our intake removes the half-keyed rim itself (`intake.clean_key`: fringe within 3 px of the background takes the nearest inside colour, hard alpha); what is left after that is unkeyed background and the still is refused | check: fit.gate_still | test: TestKeyColour.test_g10_key_colour_left_in_still, TestKeyColour.test_clean_key_removes_fringe
G11 | owner | No large gear over the torso's front or the near arm (a shield belongs on the back). Measured: a gear blob is a patch of the body of at least 0.006 body heights squared walled in completely by a rim of one lit colour (`intake.rimmed_blobs`); at most 25 % of it may lie ahead of the trunk axis (the neck-pelvis line) between the shoulder row and 0.08 body heights under the hips | check: fit.gate_still | test: TestGearPlacement.test_g11_shield_on_near_side, TestGearPlacement.test_g11_threshold
R19 | owner | No pixel of the background key's colour (as in G10) in any baked frame, at either size | check: checks.key_colour | test: TestKeyColour.test_r19_key_colour_in_frame
```

Measured on the three stills drawn on spec (22 Nov), with the margin to each limit:

| still | G10 key px raw -> after intake (limit 0) | G11 share of the shield ahead of the trunk axis (limit 0.25) | G8 hand-coloured area over the body (limit 0.15) | result |
|---|---|---|---|---|
| HR6.1 | 969 -> 0 | 0.00 (shield on the back) | 0.00 | accepted at 56 and 112 px |
| HR6.2 | 826 -> 0 | 0.88 (shield over the near arm) | 0.00 | refused G11 |
| HR6.4 | 973 -> 0 | no closed rim found (the fist covers it) | 2.62 (a fist of 2.54 and a speck of 0.08) | refused G8 |

G8 before the change read the hand's colour off the hammer's head (the blob's point furthest from
the shoulder) and so saw no hand at all on HR6.4. G11 only knows gear with a rim; a plain
board without one is not seen (HR6.4's shield is refused through the arm drawn over it).
