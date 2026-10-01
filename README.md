# Blox Fruits Fishing Macro

AutoHotkey v2 macro for automating fishing in **Blox Fruits**.

The macro uses screen detection and color recognition to detect the fishing bar, bite indicator, fish position, chests and NPC/shop menus. It also includes an automatic reel controller and optional bait purchasing / fish selling.

## Requirements

- Windows
- [AutoHotkey v2.0+](https://www.autohotkey.com/)
- Roblox
- Blox Fruits
- The macro must be run with administrator privileges
- Roblox should be running in **windowed or borderless fullscreen**
- Supported resolution profiles:
  - `1920x1080`
  - `2560x1440`
  - `Auto`

> The selected resolution must match the Roblox game area closely. A mismatch can cause the screen detection to fail.

---

## Installation

1. Install **AutoHotkey v2**.
2. Put `BloxFishing.ahk` anywhere on your PC.
3. Double-click `BloxFishing.ahk`.
4. Allow the administrator/UAC prompt if Windows asks.
5. Start Roblox and open **Blox Fruits**.
6. Go to the fishing NPC and make sure the **Interact** prompt is visible.
7. Equip your fishing rod.
8. Make sure **Shift Lock is OFF** before starting.
9. Open the macro window and configure your settings.
10. Press **F2** to start.

The macro will automatically enable and verify Shift Lock when it starts fishing.

---

## Important: First setup

Before pressing F2:

- Roblox must already be open.
- You must be in Blox Fruits.
- Your fishing rod must be equipped.
- You should be standing close enough to the fishing NPC for the Interact prompt to appear.
- Shift Lock must be **OFF**.
- The rod hotbar slot must be correct in the macro.
- Your Roblox game resolution should match the selected profile.

The recommended setup is to enable:

- **Anchor at the NPC on start**
- **Perfect cast**
- **Collect chests**

---

## Macro controls

| Key | Action |
|---|---|
| `F2` | Start / Stop the macro |
| `F4` | Close the macro |
| `F8` | Enable / disable debug log file |

You can also use the buttons in the macro window.

### F2 — Start / Stop

Press `F2` to start the fishing loop.

Press `F2` again to stop it.

When stopped, the macro releases the mouse button automatically.

### F4 — Quit

Completely closes the macro.

### F8 — Debug log

Toggles the debug log file:

```text
BloxFishing.log
```

The file is created in the same folder as the `.ahk` file when debug logging is enabled.

---

# Configuration

The macro has three configuration sections.

## Display

### Screen resolution

Available options:

- `Auto`
- `1920x1080`
- `2560x1440`

`Auto` selects the closest supported profile based on your screen resolution.

If you are using 1920×1080, select:

```text
1920x1080
```

If you are using 2560×1440, select:

```text
2560x1440
```

The macro also checks the actual Roblox client area when it starts.

---

# Fishing settings

## Rod hotbar slot

Select the number corresponding to the slot containing your fishing rod.

Example:

```text
Rod in slot 4 → select 4
```

The default is:

```text
4
```

## Faster bite reaction

When enabled, the macro reacts to the bite indicator faster.

This can reduce the confirmation time before clicking the bite.

If you experience unreliable bite detection, try disabling this option.

## Slower fish trick

Changes the timing used when the macro quickly unequips and re-equips the rod after fishing.

If the normal timing works correctly, leave this disabled.

## Collect chests

When enabled, the reel controller can detect and attempt to collect treasure chests during the fishing minigame.

## Anchor at the NPC on start

Recommended.

When enabled, the macro starts by:

1. Opening the fishing NPC dialogue.
2. Closing the dialogue.
3. Returning to the fishing position.
4. Enabling Shift Lock.
5. Verifying that the cursor is centered.

This gives the macro a known starting position.

## Perfect cast

When enabled, the macro attempts to release the cast at full charge instead of using a fixed basic timing.

The macro learns the approximate full charge height from the game.

---

# Shop settings

## Buy bait

Automatically handles bait purchases from the fishing NPC.

The macro can open the NPC dialogue, navigate the shop and craft/buy the configured amount.

## Bait now

This tells the macro how much bait you currently have.

Example:

```text
Bait now: 35
```

Use `0` if you do not want the macro to track your current bait amount.

## Bait per purchase

Controls how much bait the macro attempts to purchase.

The value is rounded to multiples of 10.

Example:

```text
40
```

means the macro will attempt to buy 40 bait.

## Sell every

When enabled, the macro sells the fish after the configured number of catches.

Example:

```text
Sell every: 100 catches
```

The macro will periodically return to the NPC and sell the fish before continuing.

---

# How the fishing loop works

Once started, the macro roughly follows this process:

```text
Start
  ↓
Check Roblox
  ↓
Establish NPC anchor
  ↓
Enable + verify Shift Lock
  ↓
Check bait / sell requirements
  ↓
Cast
  ↓
Wait for bite
  ↓
Click the bite
  ↓
Detect fishing bar
  ↓
Track fish + green zone
  ↓
Control the reel
  ↓
Detect the end of the minigame
  ↓
Dismiss the catch / recipe notification
  ↓
Repeat
```

If something goes wrong, the macro has several recovery checks and can stop itself when it cannot safely confirm the game state.

---

# Automatic detection

The macro does not rely only on fixed mouse positions for the fishing minigame.

It uses screen capture and color detection to identify:

- Fishing bar
- Green reel zone
- Fish position
- Treasure chests
- Bite indicator
- Cast charge meter
- NPC dialogue panels
- Craft button
- Recipe `Learn` button
- Fishing progress

The main fishing regions and click points are defined as **fractions of the Roblox game window**, allowing the same calibration to work across the supported resolution profiles.

---

# BloxFishing.ini

The macro automatically creates:

```text
BloxFishing.ini
```

in the same directory as the `.ahk` file.

This file stores your settings so you do not have to configure everything again after restarting the macro.

Do not delete it unless you want the settings to return to their defaults.

Example settings stored in the INI include:

```ini
[display]
resolution=Auto

[fishing]
rodSlot=4
fastBite=0
slowFlick=0
chest=1
anchor=1
perfect=1

[shop]
buyBait=1
baitNow=0
baitPer=40
sellOn=1
sellEvery=100
```

The exact file is generated and updated automatically by the macro.

---

# BloxFishing.log

When debug logging is enabled with `F8`, the macro writes detailed information to:

```text
BloxFishing.log
```

This can contain information such as:

```text
[start]
[cast]
[bite]
[reel]
[chest]
[bait]
[sell]
[catch]
[warn]
[stop]
```

This log is useful when troubleshooting detection or configuration problems.

---

# Troubleshooting

## The macro does not click Roblox

Make sure:

1. AutoHotkey is running as administrator.
2. Roblox is also running normally.
3. Roblox is focused.
4. The macro was started after Roblox was opened.

The script automatically requests administrator privileges because Roblox can ignore injected input from a non-elevated process.

---

## The macro says Shift Lock could not be verified

Check:

- Roblox is focused.
- Shift Lock Switch is enabled in Roblox settings.
- Shift Lock is currently OFF before pressing F2.
- You are actually inside Blox Fruits.

The macro intentionally refuses to start fishing if it cannot verify the centered Shift Lock state.

---

## The fishing bar is not detected

Check:

- Your resolution profile.
- Your Roblox game/window size.
- That the Roblox client is not heavily resized.
- That the game is visible and not covered by another window.

Use **Check setup** in the GUI.

It reports:

- Administrator status
- Screen resolution
- Selected profile
- Roblox game area
- Whether the reel bar is currently detected

---

## The bite is not detected

Try disabling or enabling:

```text
Faster bite reaction
```

Also make sure Roblox is displayed normally and the bite indicator is not covered by another UI element.

---

## The rod slot is wrong

If your rod is in slot 5, for example:

```text
Rod hotbar slot → 5
```

The macro uses the selected hotbar slot when it needs to equip or flick the rod.

---

## The shop does not work

Make sure:

- You are close enough to the fishing NPC.
- The Interact prompt is visible when starting.
- The selected rod slot is correct.
- The NPC dialogue is not already stuck open.
- The resolution profile is correct.

The macro uses live menu detection when possible and has calibrated fallback click positions.

---

# Files

A typical folder can look like:

```text
BloxFishing/
├── BloxFishing.ahk
├── BloxFishing.ini       ← generated automatically
├── BloxFishing.log       ← generated when debug logging is enabled
├── README.md
├── LICENSE
└── .gitignore
```

You do not need to manually create the `.ini` or `.log` files.

---

# Recommended first test

For the first run, use:

```text
Resolution:        Auto
Rod slot:          Your rod slot
Faster bite:       OFF
Slower fish trick: OFF
Collect chests:    ON
NPC anchor:        ON
Perfect cast:      ON
Buy bait:          OFF
Sell every:        OFF
```

Then:

1. Stand at the fishing NPC.
2. Make sure the Interact prompt is visible.
3. Equip your rod.
4. Turn Shift Lock OFF.
5. Press **Check setup**.
6. If everything looks correct, press **F2**.
7. Watch the first few cycles before leaving it unattended.

---

## Credits

This project was created with assistance from **Claude by Anthropic**.
