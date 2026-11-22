# Art runner (Horde & Hearth stand-in art from the free Perchance image generator)

Runs on the MSI, unattended, in its OWN headless browser (Playwright, separate profile), so it never depends on
Curtis's Chrome window being in front.

- Input: `queue.json` (365 entries: id, pri, shape l/s/p, prompt). Work through it in order of `pri`, then id.
- Page: https://perchance.org/ai-text-to-image-generator . The generator lives in the iframe `#outputIframeEl`
  (cross-origin; Playwright's frame API reaches it). Set the description box to the prompt, keep Art Style
  "Pixel Art", set the shape (Landscape for l, Square for s, Portrait for p) and How many = 4, press Generate,
  wait until four new pictures have finished, save each at full resolution.
- Output: `D:\projects\hh_art\raw\<id>_<n>.png` (n = 1..4), and a line per id in `done.txt`. Skip ids already done,
  so it can be restarted at any time.
- Every 20 ids: copy new files into a checkout of branch `art-raw` (orphan branch, pictures only, under
  `raw/`) and push it. The lead thread fetches that branch, picks the best of the four and cuts them.
- Be polite: one generation at a time, a pause of a few seconds between them.
- If the site shows a verification check, CAPTCHA or a sign-in wall: stop, write `BLOCKED` in `status.txt`, push,
  and exit. Never try to get past it.
- Never type anything that names the game, the repository or a person.
