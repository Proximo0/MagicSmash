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
  R16 and R17 measure more exactly (their limits are unchanged). 22 Nov (body + gear): R20-R25
  and G12-G15 added; nothing else changed.
- Gear (`gear.py`, `STILL_SPEC.md`): a character is a bare body still plus gear pictures. Gear is
  never cut from the body or mixed into it: each gear is a layer laid over the finished body
  frame, so R20-R23 and R25 are true by construction and the checks guard the construction.
  G12-G15 and R24 apply to every still (G12 only to body stills); the legacy stills with gear
  painted in keep G7 and G11.
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
R20 | -     | Every gear's pixels are its own picture in every frame, apart from the rigid move: the gear's sprite is made again from its picture at that frame's turn and compared by hash with what the frame holds, every gear pixel the frame shows is that sprite's pixel at that place, and a gear that does not turn (back) has one hash in all frames | check: checks.gear_rigid | test: TestGearBake.test_r20_gear_pixel_changed
R21 | -     | A gear held in a hand has its grip within 1 px of the middle of that hand in every frame | check: checks.gear_grip | test: TestGearBake.test_r21_grip_off_the_hand
R22 | -     | Back gear (shield, cape) is layered behind the torso and never draws over the near arm | check: checks.gear_back | test: TestGearBake.test_r22_back_gear_over_the_near_arm
R23 | -     | Gear never covers the head (the body's pixels above the neck joint's row) | check: checks.gear_head | test: TestGearBake.test_r23_gear_over_the_head
R24 | owner | The baked figure is one connected shape in every frame: any opaque blob not connected to the body (a loose stick floating behind the heels, gear that left its hand) is refused | check: checks.loose_blobs | test: TestGearBake.test_r24_loose_blob_in_a_frame
R25 | -     | Gear held in a hand never crosses a leg below the knee (shins and feet) | check: checks.gear_legs | test: TestGearBake.test_r25_weapon_across_the_legs
G12 | -     | A body still (layout `"format": "body"`, or gear pictures beside it) is the bare body: it contains no gear. Refused: any rimmed blob as in G11, wherever it lies; a long thin rigid object (`intake.thin_objects`: a part of the silhouette narrower than 0.035 body heights, at least 0.14 long, within 0.012 RMS of a straight line); anything held (the near hand's shape reaching more than 0.11 body heights from the hand's middle); cloth behind the back (more than 0.010 body heights squared further than 0.05 behind the layout's back line between neck and hips) | check: fit.gate_still | test: TestBodyStill.test_g12_shield_drawn_into_the_body, TestBodyStill.test_g12_staff_drawn_into_the_body, TestBodyStill.test_g12_hammer_in_the_hand, TestBodyStill.test_g12_cape_drawn_into_the_body, TestBodyStill.test_g12_real_still_with_gear_drawn_in
G13 | owner | Nothing loose in the still: every opaque blob of 9 px or more is connected to the body (smaller ones are keying dust and are dropped; a ground plate is still erased) | check: fit.gate_still | test: TestBodyStill.test_g13_loose_stick_in_the_still
G14 | -     | A gear picture is one connected shape with a known slot (one gear per slot), its anchor inside the picture (a hand grip on the gear itself), a size of 0.05 to 1.40 body heights, at least 24 px long, and no key colour left | check: gear.gate_gear | test: TestGearPictures.test_g14_gear_picture
G15 | owner | The legs do not have the hand's colour: at most 25 % of the thighs and upper shins may pass the hand-colour test of G8 (bare legs: the hand vanishes against the thigh and cannot be counted). Trousers or greaves in a colour different from the skin | check: fit.gate_still | test: TestBodyStill.test_g15_bare_legs
R26 | -     | No leg part shows the body's skin colour where the still had none: no pixel of the hand's palette (`colour.skin_palette`) on a trouser, greave or boot part of a baked frame when that part's cut picture has none (a rare grey or gold that median cut turned into a skin shade, a shaded kilt come out pink). The cut repairs such pixels (`colour.repair_false_skin`, `darken` keeps non-skin colours non-skin); the check guards it | check: checks.leg_skin_colour | test: TestPass6.test_r26_skin_on_a_leg_part
R27 | -     | With back gear (shield, cape) or far-hand gear the far hand stays hidden behind it: no pixel of the far forearm is visible below the far hip's row (a hand dangling under the shield at the back hip). The pose keeps it there: `Gait.solve_far_tuck` folds the far elbow, per phase, just enough that the far wrist and hand tip hang no lower than the far hip, and only where the arm swings back (no stub of forearm ahead of the chest) | check: checks.far_hand_hidden | test: TestPass6.test_r27_far_hand_dangling_under_the_shield
R28 | -     | The far arm has one treatment for every character: joined to the torso and shown only where it swings out forward of it, or not shown. No far-arm pixel behind the torso's back edge (row by row; a flap behind the back hip, a sleeve sliver along the back), no piece of the far arm touching neither torso, robe nor near arm (detached), no cape pixel in the sleeve's colour (the arm cut into the cloth: HR4.2's wedge behind the shoulder and ribbon down the back, until pass 8 `autocut` gave the drawn far arm's stretch behind the back to the cape), and no background pixel in the torso's rows between its back edge and the pelvis column, neck to pelvis (a gap in the torso). The cut hides the far arm behind the torso (`bake.hide_far_behind_torso`); a hand-coloured blob behind the back of a body still more than 1.5 x the near hand is clothes (HR6.2's white skirt), a smaller one is the drawn far arm (HR4.2) | check: checks.far_arm_flap | test: TestFarArm.test_r28_far_arm_behind_the_back, TestFarArm.test_r28_detached_far_arm, TestFarArm.test_r28_gap_in_the_torso, TestFarArm.test_real_flap_of_the_still_without_the_hiding, TestFarArm.test_r28_real_elf_archer_arm_cut_into_the_cape
G16 | -     | No bare near shin: at most 25 % of the NEAR leg's shin (knee to ankle, the thighs not counted) may be within 22 Lab of the hand's colour and pass the hand-colour test of G8. A near shin that is skin (shorts over bare legs: HR3.2 pale pink, HR4.4 bright green) bakes as one bare near leg and a far leg whose shaded copy snaps to a grey or dark shade in the palette. The far leg is not measured: it is that copy (HR6.3's drawn back calf is bare, its near leg a tall boot: accepted) | check: fit.gate_still | test: TestBareShin.test_g16_refuses_the_pale_bare_shin_of_the_elf_mage_and_the_orc, TestBareShin.test_g16_passes_trousers_boots_and_the_dwarf_whose_drawn_back_calf_is_bare
G17 | -     | The hand grips the handle: the anchor of a hand gear sits on the handle, on the short side of a sword's crossguard and away from the head of a hammer, axe, mace or staff ornament. A picture drawn the other way up than its guide (the knight's greatsword, point down, hilt at the top, held by the blade tip) is turned 180 deg and its anchor put on the handle by `gear.orient_grip`, recorded in `summary.json` (`gear_solved.orientation`); a staff is gripped a third of the way up. G17 fails a picture whose orientation is kept (`"orient": "keep"` in its JSON) and still has the hand on the blade or head end | check: gear.gate_gear | test: TestGrip.test_g17_greatsword_gripped_by_the_blade, TestGrip.test_g17_passes_when_turned
```

Eighth pass (22 Nov): G17 added; R28 tightened (cape in the sleeve's colour); G16 measures the near leg only. Long hand
gear (staff, greatsword, bow: guide kinds `staff`, `two_hand_weapon`, `bow`) is CARRIED: `motion.CARRY_UPPER`/`CARRY_ELBOW`
put the hand ahead of the torso at belt height, the arm bobs at `bake.CARRY_BOB` of the walk's swing, and `gear.solve_gear`
holds the gear within 15 deg of upright in every frame with 2 px clear of legs and head where it can (R23/R25 unchanged).
Hand gear of every kind now keeps the far hand tucked (R27) so it does not show beside the near hand.

Seventh pass (22 Nov, `samples/run24`): R28 and G16 added; nothing loosened. Hand gear is placed clear by
construction (`gear.solve_gear`: per character, over 16 phases and both sizes, the angle within 32 deg of the guide's
and, if that is not enough, a size cap down to 0.7, so that R23 and R25 hold with a pixel to spare where possible; the
solved angle and size are in `summary.json` under `gear_solved`). R27's tuck is refined on the pixels
(`bake.refine_far_tuck`).

Measured on the three stills drawn on spec (22 Nov), with the margin to each limit:

| still | G10 key px raw -> after intake (limit 0) | G11 share of the shield ahead of the trunk axis (limit 0.25) | G8 hand-coloured area over the body (limit 0.15) | result |
|---|---|---|---|---|
| HR6.1 | 969 -> 0 | 0.00 (shield on the back) | 0.00 | accepted at 56 and 112 px |
| HR6.2 | 826 -> 0 | 0.88 (shield over the near arm) | 0.00 | refused G11 |
| HR6.4 | 973 -> 0 | no closed rim found (the fist covers it) | 2.62 (a fist of 2.54 and a speck of 0.08) | refused G8 |

G8 before the change read the hand's colour off the hammer's head (the blob's point furthest from
the shoulder) and so saw no hand at all on HR6.4. G11 only knows gear with a rim; a plain
board without one is not seen (HR6.4's shield is refused through the arm drawn over it).

Body + gear, measured (22 Nov, `samples/stills_gear`, 56 and 112 px):

| character | G12 hand reach (limit 0.11) | G12 cloth behind the back (limit 0.010) | G12 rimmed / thin objects | G15 skin on the legs (limit 0.25) | result |
|---|---|---|---|---|---|
| PAL_SYN (mannequin + synthetic shield, hammer) | 0.067 | 0.000 | 0 / 0 | 0.00 | accepted |
| HR6.1_SPLIT (HR6.1 with shield and hammer cut out by hand) | 0.078 | 0.000 | 0 / 0 | 0.00 | accepted |
| HR6.1 as drawn, handed in as a body still | held: refused | - | 1 rimmed blob: refused | 0.00 | refused G12 |

New rules on the old stills: R24 refuses HR2.2 (the loose line at its hip, seen by eye before);
G13 refuses loose pieces on HR2.1, HR5.3, HR5.4; G15 refuses HR4.1, HR4.4, HR5.4 and the spec
still HR6.4 (grey-green trousers on a green orc), all of which already failed another rule.
`samples/stills` now: accepted HR3.1 HR4.2 HR5.1; `samples/stills_spec`: accepted HR6.1.

Sixth pass (22 Nov, `samples/stills_gear_msi`, HR6.1 / HR6.3 / HR6.4 with shield and hammer): R26 and R27 added;
nothing else changed. R17 reads the far forearm's hand colours only where the body does not use them
(`hand_colours(common=0)`): the far arm is the near one shaded and snapped to the palette, and on HR6.3 the
shade of the skin snapped to the belt's colour, so a belt of 25 px was counted as a third hand (false alarm;
the near hand's own colours still count every blob on the torso).
