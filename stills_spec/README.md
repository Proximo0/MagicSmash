# Hero stills drawn to the animator's still spec

Latest round (22 Nov, animator d0dc5cf). Klein 4B redrew each hero over its build's spec mannequin, which was the only picture given; the hero's look was described in words. The gate ran after every try, up to 8 tries per hero.

| hero | tries | result |
|---|---|---|
| HR6.2 elf paladin | 8 | not accepted. Refused for G11 (shield on the near side) in 4 tries, G8/G6 (arm over the body) in 4, G1 (no hand outside the torso) in 3, and R1 (third leg in the 112 px bake) in 1 |
| HR6.3 dwarf paladin | 8 | not accepted. Refused for G9 in all 8: the boot is now too LONG (0.71-0.77 of the leg, limit 0.60) after the long-boot wording. Also G1 in 6 tries, G11 in 4 |
| HR6.4 orc paladin | 2 | accepted (try 1: G8). See the faults below |

These files come from different rounds:
- HR6.4.png/json are from this round.
- HR6.1.png/json are from the first round (it still passes the d0dc5cf gate).
- HR6.2.png/json are from the first round and are REFUSED by the d0dc5cf gate (G8). Don't use them.

contact_d0dc5cf.png shows this round's batch at 56 and 112 px. tries_log_d0dc5cf.json lists every try with the refused rules and the extra wording that try's prompt carried.

Faults the gate accepted in HR6.4 at 112 px (checked by eye, all 8 frames; 2 legs, 2 feet and 1 near arm in each):
1. A loose brown stick, a detached fragment, floats behind the heels in every frame. Proposed rule: refuse a baked frame with any opaque blob not connected to the body.
2. The orc's legs are bare green skin, the same colour as the hands. When the near hand swings past the thigh, hand and thigh merge into one green lump. In frame 1 a green hand-like blob also shows under the shield on the back side. Proposed rule: refuse hand-coloured legs, or a hand overlapping a leg of the same colour. Prompt: "trousers or greaves in a colour different from the skin".
