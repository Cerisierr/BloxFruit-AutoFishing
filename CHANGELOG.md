# Changelog: Blox Fruits Fishing Macro (AutoHotkey v2)

Current delivered file: `BloxFishing.ahk` (v1.4 below).
Work that was started afterwards (see "Not delivered") is **not** in that file.

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

## v1.4: Latest delivered file

- Label change only: "Bait per purchase (x10)" became "Bait per purchase".
  Enter the real number: 10 for 10 bait, 20 for 20 bait.
- **Known bug in this version:** values from 1 to 9 are rounded up to 10, so a value of 2 buys 10 bait, not 20.

---

## Findings from your screenshots (not yet in the file)

- **Cast meter colour shows the charge:** orange is low, yellow is mid, green is full.
- **Meter position:** zoomed out, the bar sits low on screen, outside my search area. This is why the perfect cast kept failing.
- **Bait counter:** bait is counted at "hooked", even when the reel bar never appears. It should only count when the reel bar appears.
- **Two NPCs:**
  - The **Fisherman** sells fish and Basic Bait.
  - The **Angler** sells the other baits and cannot buy fish.
  - The Angler's menu is: Rods (locked), Bait, Quest, Nevermind.
  - The Angler's bait page is: Basic Bait, LOCKED, LOCKED, Back. Locked rows are lighter grey and need their own detection.
- **Choosing the NPC:** you have to pick which NPC to AFK next to. Selling and advanced baits cannot both happen at one spot.

## Requested, not delivered

- Redesigned window with themes.
- Discord webhook with its own settings page.
- Hourly Report: money earned, bait bought and money spent, fish caught.
- Screenshot of the sale text after each sale.
- Choice of which bait to buy (Sea 1, 2 and 3 baits).
- Choice of AFK NPC (Fisherman or Angler).
- Correct bait counting (only when the reel bar appears).
- Fix for the bait-per-purchase rounding.
- Cast meter fix based on the colour-coded fill.
