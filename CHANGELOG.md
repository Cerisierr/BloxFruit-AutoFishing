# Changelog: Blox Fruits Fishing Macro (AutoHotkey v2)

Current delivered file: `BloxFishing.ahk` (v1.16.2 below).
Nothing is pending from the earlier "not delivered" list except the open points at the bottom.

---

## v1.0: Python to AHK conversion

- Ported the Python macro (`Fishing-Macro-master`) into a single AHK v2 file.
- Added a screen resolution profile: Auto, 1920x1080 or 2560x1440.
- All regions and click points are fractions of the game window, so both resolutions share the same calibration.
- Ported the cast, bite, reel and shop logic.
- Reel controller: same time-optimal switching law as the Python version. In a simulation it kept the fish inside the zone 100% of the time.
- Added a settings window, saved to `BloxFishing.ini`.
- Hotkeys: F2 start/stop, F4 quit, F8 debug log.
- The script restarts itself as administrator.
- Checked: syntax validation, and a rendered reel bar was found at the right position.

## v1.1: Detection fixes (first screenshots)

- **Dialogue not seen:** the "dark panel" test merged the four buttons into one block, so it never matched. It now splits them correctly. On your screenshot it finds the 4 buttons at the right positions.
- **Bite marker:** it now finds each pink blob separately instead of merging every pink pixel on screen.
- **Perfect cast (first attempt):** added a "Perfect cast" checkbox that releases at full charge.

## v1.2: Zoom, bait, sell, dialogue

- **Camera zoom lock:** zooms all the way in, then out by a set number of notches. It runs at start, after each shop trip, and every 5 casts.
- **Cast meter:**
  - The meter reading was capped at 20% of the screen height, which clipped every reading and made casts release early. The cap is now 50%.
  - Yellow fill is now accepted as well as green.
- **Dialogue detection:** it now needs both the button stack and the yellow NPC name banner, so dark scenery alone no longer counts.
- **Craft window detection:** it now needs a solid yellow block, so yellow clothes no longer match.
- **Bait and sell:**
  - "Bait now" is tracked on its own, without needing "Buy bait".
  - "Sell every" works on its own.
  - The macro stops at zero bait when "Buy bait" is off.
  - This logic was tested in a simulation.

## v1.3: Robustness

- **Menu panels:** found by their flat slate colour instead of "darkness", so the sea colour no longer matters.
- **Hover recovery:** a panel whose colour changes under the mouse is recovered from its white icon.
- **Missed bites:** two casts in a row with no bite are treated as "out of bait".
- **Logs:**
  - The start of the log echoes the settings that were read.
  - The status line shows `catches | bait | sale in N`.
  - A failed shop trip logs what the screen looked like.

## v1.4

- Label change only: "Bait per purchase (x10)" became "Bait per purchase".
  Enter the real number: 10 for 10 bait, 20 for 20 bait.
- **Known bug in this version:** values from 1 to 9 are rounded up to 10, so a value of 2 buys 10 bait, not 20 (fixed in v1.7).

---

## v1.5: Cast fix, bait, NPCs, webhook, new window

Built from the screenshots you sent. Not yet tested in the game: the script was only checked statically (brackets, duplicate or missing functions).

- **Perfect cast (fixed at the root):**
  - The meter fill is orange at the bottom, then yellow, then green. The old reader only accepted green and yellow, so it never saw the bar fill or drain.
  - The meter is now found by its fill colours and measured against its own track (black outline, dark inside), so the camera distance no longer matters.
  - The macro reads the fill level every tick and releases when it reaches the chosen percentage (default 97%). The bar bounces, so a missed rise is not a problem: it waits for the next one.
  - If the bar stops just under the threshold, it releases after it has stayed still for 0.12 s.
  - Maximum hold is 5 s. Default zoom-out is now 8 notches.
- **Bait counting:** bait is now used up only when the reel bar really appears. "bar never appeared" no longer costs bait.
- **Choice of bait:** Basic, Kelp, Good (Sea 1), Abyssal, Frozen (Sea 2), Epic, Carnivore (Sea 3), with the price per 10 and the extra item (Demonic Wisp, Yeti Fur, Terror Eyes, Dragon Scale). The window shows the pack count and total cost.
- **Choice of NPC:**
  - The **Fisherman** buys bait and fish.
  - The **Angler** sells bait only. Auto-sell is switched off when the Angler is selected.
  - Angler path: Bait, then the bait row, then the craft window. The way out clicks the bottom row (Back, then Nevermind).
- **Menu detection:** buttons are now also found by their outline (4 px of pure black for an active button, grey 72 for a LOCKED one), because the fill colour changes with the scenery behind the buttons. The better of the two results is used.
- **Discord webhook (new page):**
  - Settings: on/off, URL (hidden by default), display name, optional user ID to mention on errors, "Send test".
  - Events: started, stopped with a session summary, fish sold, bait purchased, errors and safety stops, hourly report.
  - A screenshot of the strip below the screen centre is taken right after each sale and attached to the "Fish sold" message.
  - Sending uses `curl.exe`. The window shows "delivered (HTTP 204)" or "FAILED" about 5 s after each send.
- **Hourly Report:** money generated, bait bought and money spent, fish caught, net profit, casts and escapes, fish per hour, session totals. The interval is adjustable. "Send report now" sends it immediately.
- **Income:** read from the $ counter (bottom-left) with the Windows built-in OCR, before and after each sale. If that fails, the macro tries to read the sale screenshot instead.
- **New window:** sidebar with Dashboard, Fishing, Shop and Bait, Webhook and Appearance; stat tiles; 7 themes (Midnight, Obsidian, Ocean, Emerald, Sunset, Rose, Daylight); switches instead of checkboxes; settings saved automatically.
- The window is no longer "always on top", so it cannot hide the game area the macro reads.

## v1.6: Levels, report screenshot, title fix

- **Level tracking:** the level ("Lv. 868", under the $ counter) is read with OCR at start, every 5 minutes between casts, and just before each hourly report. Levels gained are counted and shown on a new Dashboard tile, in the start message, the stop summary and the hourly report. A jump of more than 25 is treated as an OCR error. A "Track levels" switch is on the Shop and Bait page.
- **Hourly report screenshot:** the report now also attaches a screenshot of the bottom-left block (money and level).
- **Window:** the large titles, the sidebar name and the tile numbers were cut off because their text boxes were too short. They are taller now.
- The version number shown in the window is now 1.6.0.

## v1.7: Bait per purchase list, 100-bait cap

- **Bait per purchase** is now a drop-down from 10 to 100 (steps of 10). The rounding bug (1 to 9 becoming 10) is gone because the field no longer takes free numbers.
- **Inventory cap:** the inventory holds at most 100 bait, so the macro buys only what fits: `min(wanted, 100 - bait in stock)`. Example: 50 in stock and 100 wanted buys 50; 1 in stock and 100 wanted buys 90. If the inventory is already full it skips the purchase and says so in the log.
- The tracked bait count is capped at 100 as well, and "Bait in inventory now" accepts 0 to 100.
- This relies on the bait count: enter your real stock in "Bait in inventory now" (0 = not counted, then the cap cannot be applied before the first purchase).
- Not tested in the game.

## v1.8: Live webhook messages

- **New "Live activity" group** on the Webhook page:
  - **Buying bait / selling fish:** a message when the macro starts a purchase (type, quantity, cost) or a sale (fish in stock).
  - **Casting and hooked:** a message for each cast (with the release percentage) and each bite. Off by default because it is chatty.
  - **Fish caught + progress:** catch number, catches until the next sale, bait left, level, fish per hour, chests.
  - **Catch screenshot:** attaches a screenshot of the Species/Weight card. The fast "flick" trick hides that card, so while this option is on the macro waits for the card instead, which makes each catch about 2 s slower. Off by default. The screenshot area (`catchShot` in the code) is a guess, check the first one.
  - **Chest collected:** a message when the zone reaches a chest and holds it. Chests are also counted in the hourly report and the catch message.
- **Message queue:** messages are sent one every 2.2 s so Discord's rate limit is not hit. If the queue is full, the live "casting/hooked/buying/selling" messages are dropped first.
- The window is a little taller (640) to fit the new switches.
- Not tested in the game or on a real Discord channel.

## v1.9: Income read fix, bait screenshot, live bait counter

- **Income "unreadable" (fixed):**
  - Cause: the $ was read while the Fisherman dialogue was still open, and the dialogue hides the bottom-left HUD. The counter also updates a moment after Confirm, and it was only read once.
  - Now: the $ is read before opening the NPC (3 tries), then after the sale the macro leaves the dialogue if it is still open and polls the counter until it has changed and shows the same value twice. Gain = after - before.
  - The region now skips the "$" sign, which OCR often misreads as a digit.
  - The log shows `[money] before/after` and the raw OCR text when a read fails.
  - The unreliable fallback (reading numbers from the sale text) is removed.
  - The "Fish sold" message now shows `Balance: $before > $after` and attaches the HUD ($ + level) after the sale instead of the dialogue text.
- **Bait purchase screenshot:** the Craft window is captured just before Craft is pressed (quantity and price visible) and attached to "Bait purchased", which also shows the inventory total. The `hkShot` switch is now labelled "Screenshots (sale, bait, report)". Region: `craftShot` in the code.
- **"Bait in inventory now" is live:** every bait used or bought updates the field and the saved setting, so the next start resumes from the real count. Editing the field during a run corrects the tracked count.
- Not tested in the game.

## v1.10: Step away when the cast talks to the NPC

- If the cast click opens the NPC dialogue again (standing too close after the anchor), the macro now closes it and taps W (forward, away from the NPC) for a short time before retrying: 70 ms the first time, +30 ms for each repeat in a row, up to 300 ms. The streak resets after a cast that charges. Tune with `stepAwayTap`, `stepAwayAdd` and `stepAwayMax` in `ShopCfg`.
- Not tested in the game. If W moves you toward the NPC in your layout, swap `SC_W` for `SC_S` in `StepAwayFromNpc`.

## v1.11: Craft window clicks (+ and Craft not registering)

- **What the video showed:** the Craft window was detected correctly, the money never changed, the quantity stayed at 10 and neither + nor Craft showed any reaction. Only the final Close click (from the error recovery) registered, so the fixed click positions are right but the earlier clicks were not accepted by the game.
- **Fixes:**
  - Waits 0.4 s after the Craft window appears, so its pop-up animation has finished.
  - Craft-window clicks now settle 0.30 s over the button and hold the press 0.12 s (was 0.15 s and 0.06 s), so a low game frame rate cannot miss the click.
  - Every `+` click is verified: the "10" on the bait icon (`craftQty` region) is compared before and after. If nothing changed, the click is repeated (up to 3 times); if it still does nothing the shop trip stops with a clear error.
  - The Craft button is pressed up to 4 times, each time waiting 3 s for the window to close (was 6 s).
- **Log:** new lines show the game area, the exact click positions and whether each `+` click changed the quantity.
- Not tested in the game.

## v1.12: Too close to the NPC (Interact prompt)

- **What the video showed:** the character stood right behind the Fisherman, so the NPC filled the screen. The meter reader took the NPC's yellow coat for a full cast meter ("released at 99%", no real cast), the bite reader took its red bobber for a "!" ("hooked"), and the bar never appeared. No dialogue opened, so the v1.10 step-away never triggered.
- **New detection:** a nearby NPC shows a floating white "Interact" prompt. The macro now reads that area (`npcLabel` region) with the Windows OCR and, if it sees the word, walks forward (W) in growing steps (0.10 s, +0.06 s each, up to 6 steps) until the prompt is gone.
- **When it runs:** after the start-up anchor, after every shop trip (sale or bait), and every time a bite is followed by "bar never appeared".
- **Log:** `[npc] too close ...`, `[npc] out of range after N steps`.
- Not tested in the game: the OCR match for "Interact" is the weak point. If it never triggers, send the log line `[npc]` (or a screenshot of the prompt) and I will tune the region.

## v1.13: Fixed pixels for the Craft window

- **What the video showed:** the Craft window was up from 3.2 s to 7.8 s. In that time the macro clicked three times, 1.6 s apart (the verify-and-retry `+` clicks of v1.11), and the quantity never changed. The cursor stayed on the water on the right, where the bait row had been clicked, so the `+` clicks did not land on the button.
- **Change:** the quantity comparison is removed. The Craft window now uses fixed pixels per resolution profile (`CRAFT_PX` table near `Points`):
  - 2560x1440: `+` (1642, 738), Craft (1280, 917), Close (1702, 386), measured on your screenshot.
  - 1920x1080: `+` (1232, 554), Craft (960, 688), Close (1277, 290), scaled from the 2560x1440 values (x0.75), not measured.
  - The profile is the one chosen in the window (Auto = nearest to your screen size). Pixels are offsets from the top-left of the game area.
- **Click diagnostics:** every click logs `[click] plus target X,Y cursor X,Y` and flags `CURSOR MISSED THE TARGET` if Windows did not move the mouse there. The cursor is first jumped to the target, then the usual nudged move and click follow.
- The Close click used by the error recovery uses the same table.
- Not tested in the game.

---

## v1.16.5: Re-anchor after a missed bite (boss event / teleport)

- **What the video showed:** the camera tilts up to the sea, the character is teleported to an arena, then comes back on the dock facing sideways instead of straight ahead. Casts then miss, and the old logic only counted the misses.
- **Fix:** after the first missed bite, the macro re-runs the NPC anchor (camera and position reset, same routine as at start). The second missed bite in a row still triggers the bait-out logic, as before.
- Log line: `[reanchor] no bite - re-establishing the NPC anchor`.
- Limit: this only works if the character is back near the NPC after the event. If the teleport leaves it too far away, the anchor fails and the macro stops.
- Not tested in the game.

---

## v1.16.4: Death detection (HP bar)

- **Problem:** the macro never noticed the character had died. A boss knocked the character into the water, and the macro kept waiting for a bite until the 5-minute response timeout.
- **Fix:** while fishing (waiting for a bite and during the reel), the macro reads the green HP bar at the bottom-left. If it stays empty for 3 s, the macro stops, logs `[death]`, and reports the stop reason (`character dead (HP bar gone)`) in the webhook summary.
- The check is not run during NPC dialogues, because the dialogue hides the HP bar.
- The macro does not respawn or walk back to the NPC. Restart it with F2 after you respawn and stand at the NPC again.
- Not tested in the game.

---

## v1.16.3: Fausses morsures (faux "hooked")

- **Cause:** la confirmation de morsure reposait sur 2 lectures consécutives espacées de 8 ms (environ une frame de jeu). Un flash rose/magenta dans la zone `bite` (effets du lancer, personnage, canne) suffisait donc à déclencher un clic.
- **Correctif:** le "!" doit maintenant rester visible au moins 0.15 s (0.04 s en Fast bite) avant le clic. La confirmation ne dépend plus de la vitesse de la boucle.
- **Journal:** `[bite] hooked` affiche désormais les détails de la détection (`biteInfo`).
- Pas encore testé en jeu. Pistes restantes : réduire la zone `bite` pour exclure le personnage, et ne lancer la recherche de morsure qu'après le relâchement du lancer.

---

## v1.16.2: Cast meter not found over bright sky (Fast Mode)

- **What your screenshot showed:** the fill is lime (170,255,0 in the middle, 132,197,0 at the sides) and the empty part of the track is (25,55,69) over the bright blue sky.
- **Two causes, both fixed:**
  - The fill search only knew orange, amber, yellow, one yellow-green and one pure green. The lime tones were not in the list, so the meter was never found. Added `0xAAFF00`, `0x84C500` and `0x6EFF08` (same tolerance).
  - The empty-track test allowed a colour spread of 40; this track has 44-47, so the search stopped at the first empty row above the fill. The limit is now 64 (still capped at brightness 125, so sky and bright sea are rejected).
- Checked on your screenshot: the old rules find no fill and fail at the first empty track row; the new ones find the fill top and the full track height.
- Not tested in the game.

---

## v1.16.1: Tilt a bit further

- Default "Tilt down (px)" raised from 40 to 70. A saved value of exactly 40 (the old default) is moved to 70 on load. Any other value you typed is kept.

---

## v1.16: Camera tilt after the NPC, Fast Mode + Reduce Motion on start

- **Camera tilt (new setting "Tilt down (px)", default 40, 0 = off):** after every conversation with the NPC (start-up anchor, sale, bait purchase, recovery) the macro moves the mouse down by that many pixels under Shift Lock, so the camera looks a little further down. It is done only right after the NPC dialogue, never at other times, because the movement would add up and end with the camera on the ground. Raise the number to look further down.
- **Game settings on start (new switch on the Fishing page, on by default):** before the NPC anchor the macro clicks the gear above the compass, scrolls the Settings list to the bottom, switches **Fast Mode** and **Reduce Motion** to On if they are not already (it reads the green button first), then closes the window. Positions come from your 1280x720 recording and scale with the game window; the yellow title bar is located first because the window slides while it opens.
- **Log:** `[settings]` lines say what was found and done, and `[camera] tilted down ...` after each tilt.
- Not tested in the game.

---

## v1.15: Reel bar lost over flat / bright scenery (Fast mode)

- **What the video showed:** with the "Fast" texture-less mode the bar's translucent track is lighter and bluer over the sky/sea (about 47,53,56) than the old rule accepted (blue 34 +/-14). Only the part over dark wood matched. When the zone turned grey against the left edge the match fell below 25%, the macro decided the bar was gone and released the mouse for about 2 s while the fish escaped.
- **Track colour:** widened to any dark neutral/blue-grey (blue 18-66, red and green <= 70, channels within 14 of each other). Your normal-texture screenshot (33,30,29) and the Fast-mode video (47,53,56) both match.
- **Track threshold:** the "track background gone" test now needs 10% instead of 25%.
- **Zone hidden but progress strip still up:** the macro now keeps the last mouse state instead of releasing it.
- Not tested in the game.

---

## v1.14: Separate channel for the hourly report

- New field on the Webhook page: **Hourly report webhook URL (optional)**. Create a webhook in the other Discord channel and paste its URL there. Empty = hourly reports stay in the main channel.
- "Send test" and "Send report now" also use it. The Show/Hide button reveals both URLs.
- The main webhook still has to be enabled and valid; everything except the hourly report keeps going to it.
- Window is a little taller (656).
- Not tested in the game or on a real Discord channel.

---

## Findings from your screenshots

- **Cast meter colour shows the charge:** orange is low, yellow is mid, green is full. (Used in v1.5.)
- **Meter position:** zoomed out, the bar sits low on screen. Fixed in v1.5 by measuring the track instead of using a fixed size.
- **Two NPCs:** the Fisherman sells fish and Basic Bait. The Angler sells the other baits and cannot buy fish. Its menu is Rods (locked), Bait, Quest, Nevermind; its bait page is Basic Bait, LOCKED, LOCKED, Back.

## Open points (to check in the game)

- **OCR:** money and level reading depend on Windows OCR reading the game font. If a sale says "unreadable", send me a screenshot of the bottom-left HUD.
- **Webhook screenshots:** the attachments have not been seen arriving on a real Discord channel yet.
- **Bait menu order:** I assumed Basic first, then the two baits of that sea in the order you listed. Override with `baitRow=` (1 to 3) in the `[shop]` section of `BloxFishing.ini`.
- **Craft window for baits that need an item:** only the Basic Bait layout is known, so the "+" and Craft button positions may need adjusting.
- **Selected bait:** if the game does not select a newly bought bait by itself, it has to be selected by hand.
