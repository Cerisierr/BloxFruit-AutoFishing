; ============================================================================
;  Blox Fruits Fishing Macro  -  AutoHotkey v2
;  Port of the "bloxfish" Python macro (vision + reel controller + shop).
;
;  Hotkeys : F2 = start / stop     F4 = quit     F8 = toggle debug log file
;  Requires: AutoHotkey v2.0+, Windows, Roblox (borderless fullscreen or windowed)
;
;  How it works
;    * The screen is read with GDI (BitBlt into a DIB) and scanned in memory,
;      so every colour rule from the Python version can be evaluated exactly.
;    * The reel minigame is a double integrator; the controller is the same
;      time-optimal bang-bang switching law (s = e + 0.5*ev*|ev|/a).
;    * All regions and click points are FRACTIONS of the game window, so the
;      1920x1080 and 2560x1440 profiles use the same calibrated numbers.
; ============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off
Persistent
ProcessSetPriority("High")
SetMouseDelay(-1)
SetKeyDelay(-1, -1)
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")

; ---- elevation: Roblox drops input from a non-elevated process --------------
if !A_IsAdmin {
    try Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
    ExitApp()
}

; ============================================================================
;  INPUT
; ============================================================================
class Mouse {
    static down := false
    static asserted := 0.0

    ; Drive the left button to `state`; re-assert every 150 ms so a dropped
    ; SendInput event can never leave the reel zone jammed against a wall.
    static Hold(state) {
        t := Now()
        if (state != this.down || t - this.asserted >= 0.15) {
            Click(state ? "Down" : "Up")
            this.down := state
            this.asserted := t
        }
    }

    static Tap(holdSec := 0.08) {
        Click("Down")
        this.down := true
        Sleep(Round(holdSec * 1000))
        Click("Up")
        this.down := false
        this.asserted := Now()
    }

    ; Real injected movement so Roblox's GUI cursor follows (used for menus).
    static ClickAt(x, y, settle := 0.15, holdSec := 0.06) {
        MouseMove(x - 4, y - 4, 0)
        Sleep(30)
        MouseMove(4, 4, 0, "R")
        Sleep(50)
        MouseMove(1, 0, 0, "R")
        MouseMove(-1, 0, 0, "R")
        Sleep(Round(settle * 1000))
        this.Tap(holdSec)
    }
}

class Keys {
    static SC_S := 0x1F
    static SC_LSHIFT := 0x2A
    static DIGITS := Map("1", 0x02, "2", 0x03, "3", 0x04, "4", 0x05, "5", 0x06
                       , "6", 0x07, "7", 0x08, "8", 0x09, "9", 0x0A, "0", 0x0B)

    ; Scan-code tap: Roblox reads scan codes, not virtual keys.
    static Tap(sc, holdSec := 0.06) {
        code := Format("sc{:03X}", sc)
        Send("{" . code . " down}")
        Sleep(Round(holdSec * 1000))
        Send("{" . code . " up}")
    }

    static Digit(slot) {
        s := Trim(String(slot))
        return this.DIGITS.Has(s) ? this.DIGITS[s] : this.DIGITS["1"]
    }
}

; ============================================================================
;  SCREEN CAPTURE  (GDI BitBlt -> top-down 32-bit DIB, read with NumGet)
; ============================================================================
class ScreenGrab {
    static cache := Map()

    static Get(w, h) {
        key := w "x" h
        if !this.cache.Has(key) {
            if (this.cache.Count > 12)
                this.cache := Map()
            this.cache[key] := ScreenGrab(w, h)
        }
        return this.cache[key]
    }

    static Clear() {
        this.cache := Map()
    }

    __New(w, h) {
        this.w := Max(1, w)
        this.h := Max(1, h)
        this.hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
        this.hdcMem := DllCall("CreateCompatibleDC", "ptr", this.hdcScreen, "ptr")
        bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0)
        NumPut("Int", this.w, bi, 4)
        NumPut("Int", -this.h, bi, 8)          ; negative = top-down
        NumPut("UShort", 1, bi, 12)
        NumPut("UShort", 32, bi, 14)
        bitsPtr := 0
        this.hBmp := DllCall("CreateDIBSection", "ptr", this.hdcScreen, "ptr", bi
            , "uint", 0, "ptr*", &bitsPtr, "ptr", 0, "uint", 0, "ptr")
        this.bits := bitsPtr
        this.hOld := DllCall("SelectObject", "ptr", this.hdcMem, "ptr", this.hBmp, "ptr")
    }

    ; Copy the screen rectangle whose top-left is (x, y) into the DIB.
    Capture(x, y) {
        return DllCall("BitBlt", "ptr", this.hdcMem, "int", 0, "int", 0
            , "int", this.w, "int", this.h, "ptr", this.hdcScreen
            , "int", x, "int", y, "uint", 0x40CC0020)   ; SRCCOPY | CAPTUREBLT
    }

    __Delete() {
        try {
            DllCall("SelectObject", "ptr", this.hdcMem, "ptr", this.hOld)
            DllCall("DeleteObject", "ptr", this.hBmp)
            DllCall("DeleteDC", "ptr", this.hdcMem)
            DllCall("ReleaseDC", "ptr", 0, "ptr", this.hdcScreen)
        }
    }
}

; ============================================================================
;  REEL CONTROLLER  (time-optimal bang-bang, identical law to controller.py)
; ============================================================================
class VelEst {
    __New(win := 5) {
        this.win := win
        this.t := []
        this.x := []
    }

    Reset() {
        this.t := []
        this.x := []
    }

    Push(tv, xv) {
        ; A large jump means the target teleported: restart the fit.
        if (this.x.Length && Abs(xv - this.x[this.x.Length]) > 0.25)
            this.Reset()
        this.t.Push(tv)
        this.x.Push(xv)
        if (this.t.Length > this.win) {
            this.t.RemoveAt(1)
            this.x.RemoveAt(1)
        }
    }

    ; Least-squares slope over the sliding window.
    Value() {
        n := this.t.Length
        if (n < 3)
            return 0.0
        t0 := this.t[1]
        tm := 0.0, xm := 0.0
        Loop n {
            tm += this.t[A_Index] - t0
            xm += this.x[A_Index]
        }
        tm /= n
        xm /= n
        num := 0.0, den := 0.0
        Loop n {
            dt := (this.t[A_Index] - t0) - tm
            num += dt * (this.x[A_Index] - xm)
            den += dt * dt
        }
        return den < 1e-12 ? 0.0 : num / den
    }
}

class ReelController {
    __New() {
        this.accel0 := 1.92          ; track widths / s^2
        this.vmax := 0.545           ; track widths / s
        this.win := 5
        this.lat := 0.045            ; capture + input latency (s)
        this.deadband := 0.004
        this.edge := 0.01
        this.vz := VelEst(5)
        this.vf := VelEst(5)
        this.Reset()
    }

    Reset() {
        this.vz.Reset()
        this.vf.Reset()
        this.accel := this.accel0
        this.obs := []
        this.haveLast := false
        this.lastT := 0.0
        this.lastVz := 0.0
        this.lastHold := false
        this.pwm := false
    }

    Retarget() {
        this.vf.Reset()
    }

    ; Learn the rod's real acceleration: median of recent |dv/dt| samples.
    Adapt(tv, vzv) {
        if !this.haveLast {
            this.lastT := tv
            this.lastVz := vzv
            this.haveLast := true
            return
        }
        dt := tv - this.lastT
        if (dt > 0.004 && dt < 0.08) {
            observed := (vzv - this.lastVz) / dt
            expected := this.lastHold ? 1 : -1
            sgn := observed > 0 ? 1 : (observed < 0 ? -1 : 0)
            if (sgn == expected && Abs(vzv) < this.vmax * 0.85) {
                mag := Abs(observed)
                if (mag > 0.2 && mag < 12.0) {
                    this.obs.Push(mag)
                    if (this.obs.Length > this.win * 3)
                        this.obs.RemoveAt(1)
                    if (this.obs.Length >= this.win)
                        this.accel := Median(this.obs)
                }
            }
        }
        this.lastT := tv
        this.lastVz := vzv
    }

    ; One decision. Positions are in track widths (0..1).
    Step(tv, zoneC, fishC, zoneHalf) {
        this.vz.Push(tv, zoneC)
        this.vf.Push(tv, fishC)
        vzv := this.vz.Value()
        vfv := this.vf.Value()
        this.Adapt(tv, vzv)

        a := Max(0.2, this.accel)
        lat := this.lat
        acc := this.lastHold ? a : -a
        zPred := zoneC + vzv * lat + 0.5 * acc * lat * lat
        vzPred := Min(Max(vzv + acc * lat, -this.vmax), this.vmax)
        fPred := fishC + vfv * lat

        lo := zoneHalf + this.edge
        hi := 1.0 - zoneHalf - this.edge
        target := Min(Max(fPred, lo), hi)

        e := target - zPred
        ev := vfv - vzPred
        s := e + 0.5 * ev * Abs(ev) / a

        if (Abs(s) < this.deadband) {
            ; Alternate every tick: mean acceleration ~ 0, the zone coasts.
            this.pwm := !this.pwm
            hold := this.pwm
        } else {
            hold := (s > 0)
        }
        if (hold && vzPred >= this.vmax)
            hold := (s > this.deadband)
        else if (!hold && vzPred <= -this.vmax)
            hold := (s > -this.deadband)

        this.lastHold := hold
        return {hold: hold, err: e, vz: vzv, vf: vfv}
    }
}

; ============================================================================
;  CONFIGURATION
; ============================================================================
APP_NAME    := "Blox Fruits Fishing Macro"
APP_VERSION := "1.0.0"
INI_FILE    := A_ScriptDir "\BloxFishing.ini"
LOG_FILE    := A_ScriptDir "\BloxFishing.log"
ROBLOX_WIN  := "ahk_exe RobloxPlayerBeta.exe"

; Supported screen resolutions (profile dropdown).
RES_PROFILES := Map("1920x1080", [1920, 1080], "2560x1440", [2560, 1440])
RES_ORDER    := ["1920x1080", "2560x1440"]

; Regions as fractions of the game window: [left, top, right, bottom].
Regions := {
    bar:   [0.2138, 0.7184, 0.8502, 0.8181],   ; reel bar search band
    bite:  [0.2800, 0.1600, 0.7200, 0.6000],   ; "!" marker area (excludes the top-right player list)
    meter: [0.1800, 0.2200, 0.8200, 0.8800],   ; cast charge meter (beside the character; excludes side HUD)
    menu:  [0.6700, 0.3900, 0.9500, 0.7450],   ; NPC button stack
    craft: [0.4020, 0.5769, 0.6020, 0.7162],   ; yellow Craft button
    learn: [0.6753, 0.6482, 0.8573, 0.7458]    ; recipe-note "Learn" button
}

; Click points as fractions of the game window: [x, y].
Points := {
    interact:  [0.4965, 0.6552],
    menu1:     [0.7594, 0.4454],   ; legacy ordinal fallbacks (live detection first)
    menu2:     [0.7629, 0.5352],
    menu3:     [0.7711, 0.6106],
    menuLast:  [0.7664, 0.7033],
    craftPlus: [0.6434, 0.5216],
    craftBtn:  [0.5000, 0.6473],
    craftClose:[0.6590, 0.2773],
    learn:     [0.7697, 0.7008]
}

; Timings in seconds (same defaults as the Python build).
Timing := {
    castHold: 1.20, releaseLead: 0.012, castSettle: 1.60, maxCastAttempts: 4, castRetryGap: 0.45
  , biteClickDelay: 0.05, biteToBar: 5.0, maxWaitBite: 30.0, maxReel: 12.0
  , flickGap: 0.08, flickSlowDelay: 0.50, flickSlowGap: 0.50, flickSettle: 0.50
  , catchConfirm: 0.30, popupDelay: 1.60, catchClickGap: 0.35, catchSettle: 0.55
  , barClear: 3.0, barLost: 0.9, errorRecovery: 1.0, responseTimeout: 300.0
  , chestHold: 2.5, chestGrace: 1.5, chestMinProgress: 0.20, chestMaxGrabs: 4
}

ShopCfg := {
    afterClick: 0.6, afterPlus: 0.25, afterShift: 0.35, afterNevermind: 1.5
  , afterRod: 0.45, walkBackTap: 0.10, approachWait: 1.2, directTimeout: 0.9
  , dialogTimeout: 6.0, craftTimeout: 6.0, rootTimeout: 2.0, rootSettle: 0.9
  , nevermindRetry: 1.4, beforeLeave: 0.7, pageSettle: 0.65, poll: 0.08
  , maxApproach: 2, afterBack: 0.5, confirmTimeout: 6.0, buyAt: 1, craftStep: 10
}

; NPC menu structure: rows are 1-based from the top, -1 = bottom row.
MENU_ROWS := Map(
    "root",    Map("shop", 1, "fishing_index", 2, "job_stats", 3, "nevermind", -1),
    "shop",    Map("buy_bait", 1, "sell_fish", 2, "nevermind", -1),
    "bait",    Map("basic_bait", 1, "back", -1),
    "confirm", Map("confirm", 1, "nevermind", -1))
PAGE_ROWS := Map("root", 4, "shop", 3, "bait", 2, "confirm", 2)

; User-adjustable settings (persisted in BloxFishing.ini, edited in the GUI).
Cfg := {
    resolution: "Auto", rodSlot: "4", fastBite: false, slowFlick: false
  , chest: true, anchor: true, buyBait: true, baitNow: 0, baitPer: 40
  , sellOn: true, sellEvery: 100, flick: true, perfect: true
}

; Runtime state.
BotState := {
    running: false, debug: false, win: {x: 0, y: 0, w: 1920, h: 1080}
  , resW: 1920, resH: 1080, sc: 1.0
  , shiftLock: false, shiftVerified: false, rodEquipped: true
  , atNpc: true, bait: -1, sinceSell: 0, lastResponse: 0.0, witness: ""
  , flicked: false, lastEscaped: false, buyFailures: 0, lastBought: 0
  , meterFull: 0, biteInfo: ""
}
BotStats := {casts: 0, bites: 0, catches: 0, escapes: 0, missedBar: 0
           , biteTimeouts: 0, sales: 0, purchases: 0, started: 0.0}

QPF := 0
DllCall("QueryPerformanceFrequency", "Int64*", &QPF)
Ui := {}
reelCtl := ReelController()

; ============================================================================
;  UTILITIES
; ============================================================================
Now() {
    static counter := 0
    DllCall("QueryPerformanceCounter", "Int64*", &counter)
    return counter / QPF
}

Median(arr) {
    a := []
    for v in arr
        a.Push(v)
    Loop a.Length - 1 {                      ; insertion sort
        i := A_Index + 1
        key := a[i]
        j := i - 1
        while (j >= 1 && a[j] > key) {
            a[j + 1] := a[j]
            j--
        }
        a[j + 1] := key
    }
    n := a.Length
    if (n == 0)
        return 0.0
    return (Mod(n, 2) == 1) ? a[(n + 1) // 2] : (a[n // 2] + a[n // 2 + 1]) / 2
}

; Sleep that ends early when the run is stopped.
Wait(sec) {
    endAt := Now() + sec
    while (BotState.running && Now() < endAt)
        Sleep(Min(20, Max(1, Round((endAt - Now()) * 1000))))
}

Alive() {
    if !BotState.running
        return false
    if (Timing.responseTimeout > 0 && Now() - BotState.lastResponse > Timing.responseTimeout) {
        LogMsg("[safety] no confirmed game response for "
            . Round(Timing.responseTimeout) . " s - stopping")
        BotState.running := false
        return false
    }
    return true
}

NoteResponse() {
    BotState.lastResponse := Now()
}

LogMsg(msg) {
    line := FormatTime(, "HH:mm:ss") . "  " . msg
    try {
        if Ui.HasOwnProp("log") {
            len := SendMessage(0x000E, 0, 0, Ui.log)         ; WM_GETTEXTLENGTH
            if (len > 24000) {
                Ui.log.Value := ""
                len := 0
            }
            SendMessage(0x00B1, len, len, Ui.log)            ; EM_SETSEL at end
            EditPaste(line . "`r`n", Ui.log)
        }
    }
    if BotState.debug
        try FileAppend(line . "`n", LOG_FILE)
}

; ---- geometry --------------------------------------------------------------
; Uses the real Roblox client rectangle (so windowed mode works too); the
; selected resolution profile is used for validation and as the fallback.
RefreshGame() {
    rect := 0
    hwnd := WinExist(ROBLOX_WIN)
    if hwnd {
        try {
            WinGetClientPos(&cx, &cy, &cw, &ch, hwnd)
            if (cw >= 400 && ch >= 300)
                rect := {x: cx, y: cy, w: cw, h: ch}
        }
    }
    if !rect
        rect := {x: 0, y: 0, w: BotState.resW, h: BotState.resH}
    BotState.win := rect
    BotState.sc := rect.h / 1080.0
    return rect
}

ApplyResolution() {
    name := Cfg.resolution
    if (name == "Auto" || !RES_PROFILES.Has(name)) {
        best := "", bestD := 1e9
        for k, v in RES_PROFILES {
            d := Abs(v[1] - A_ScreenWidth) + Abs(v[2] - A_ScreenHeight)
            if (d < bestD) {
                bestD := d
                best := k
            }
        }
        name := best
    }
    BotState.resW := RES_PROFILES[name][1]
    BotState.resH := RES_PROFILES[name][2]
    return name
}

CheckResolution() {
    win := RefreshGame()
    okW := Abs(win.w - BotState.resW) <= BotState.resW * 0.03
    okH := Abs(win.h - BotState.resH) <= BotState.resH * 0.03
    if (!okW || !okH)
        LogMsg("[warn] game area is " . win.w . "x" . win.h . " but the profile is "
            . BotState.resW . "x" . BotState.resH
            . " - set Roblox fullscreen (F11) at that resolution, or pick the matching profile")
    return okW && okH
}

SubRect(win, fr) {
    return {x: win.x + Round(win.w * fr[1]), y: win.y + Round(win.h * fr[2])
          , w: Max(1, Round(win.w * (fr[3] - fr[1])))
          , h: Max(1, Round(win.h * (fr[4] - fr[2])))}
}

PtAbs(fr) {
    win := BotState.win
    return {x: win.x + Round(win.w * fr[1]), y: win.y + Round(win.h * fr[2])}
}

FocusGame() {
    if WinActive(ROBLOX_WIN)
        return true
    hwnd := WinExist(ROBLOX_WIN)
    if !hwnd
        return false
    try WinActivate(hwnd)
    return WinWaitActive(hwnd, , 1) ? true : false
}

; ============================================================================
;  VISION - colour rules (RGB) ported from vision.py
; ============================================================================
IsTrackPx(r, g, b) {
    return Abs(b - 34) <= 14 && Abs(b - g) <= 12 && Abs(g - r) <= 12
}

IsZonePx(r, g, b) {                          ; green zone, normal + alarm look
    if (Abs(b - r) > 16)
        return false
    if (g > b + 10 && g > r + 10 && g > 62)
        return true
    return Abs(g - b) <= 12 && g >= 62 && g <= 170
}

IsFishPx(r, g, b) {
    return b > 110 && b > r + 60 && g > r + 30
}

IsChestPx(r, g, b) {
    return r > 140 && g > 90 && b < 130 && r > b + 60 && g > b + 20
}

; Fraction of sampled pixels on row y (between xl..xr) that belong to the bar.
BandFrac(bits, w, y, xl, xr) {
    n := 0, hit := 0
    base := y * w * 4
    x := xl
    while (x <= xr) {
        v := NumGet(bits, base + x * 4, "UInt")
        rr := (v >> 16) & 255
        gg := (v >> 8) & 255
        bb := v & 255
        n++
        if (IsTrackPx(rr, gg, bb) || IsZonePx(rr, gg, bb) || IsFishPx(rr, gg, bb)
            || IsChestPx(rr, gg, bb))
            hit++
        x += 6
    }
    return n ? hit / n : 0.0
}

; Locate the reel bar. Identified structurally: a long two-tone green progress
; strip with the dark track band directly above it. Returns a geometry object
; or 0.
FindBar() {
    win := BotState.win
    r := SubRect(win, Regions.bar)
    if (r.w < 50 || r.h < 10)
        return 0
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    minW := Floor(win.w * 0.18)
    maxW := Floor(win.w * 0.99)

    bestW := 0, bTop := -1, bBot := -1, bL := 0, bR := 0
    gTop := -1, gBot := -1, gL := 0, gR := 0

    y := 0
    while (y < h) {
        base := y * w * 4
        runStart := -1, last := -1
        curLen := 0, curL := 0, curR := 0
        x := 0
        while (x < w) {
            v := NumGet(bits, base + x * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (gg > bb + 15 && gg > rr + 15 && gg > 40) {       ; progress strip
                if (runStart < 0)
                    runStart := x
                last := x
            } else if (runStart >= 0 && x - last > 6) {
                if (last - runStart > curLen) {
                    curLen := last - runStart
                    curL := runStart
                    curR := last
                }
                runStart := -1
            }
            x += 2
        }
        if (runStart >= 0 && last - runStart > curLen) {
            curLen := last - runStart
            curL := runStart
            curR := last
        }

        if (curLen >= minW && curLen <= maxW) {
            if (gTop >= 0 && Abs(curL - gL) <= 8 && Abs(curR - gR) <= 8) {
                gBot := y
                if (curR - curL > gR - gL) {
                    gL := curL
                    gR := curR
                }
            } else {
                if (gTop >= 0 && gR - gL > bestW) {
                    bestW := gR - gL
                    bTop := gTop
                    bBot := gBot
                    bL := gL
                    bR := gR
                }
                gTop := y
                gBot := y
                gL := curL
                gR := curR
            }
        } else if (gTop >= 0) {
            if (gR - gL > bestW) {
                bestW := gR - gL
                bTop := gTop
                bBot := gBot
                bL := gL
                bR := gR
            }
            gTop := -1
        }
        y++
    }
    if (gTop >= 0 && gR - gL > bestW) {
        bestW := gR - gL
        bTop := gTop
        bBot := gBot
        bL := gL
        bR := gR
    }
    if (bTop < 0)
        return 0

    tw := bR - bL + 2
    progH := bBot - bTop + 1
    if (progH < 3 || progH > Ceil(0.05 * tw))            ; reject scenery blocks
        return 0

    ; Playfield band: rows of dark track / zone / tiles just above the strip.
    bandBotL := -1
    maxGap := Ceil(0.03 * tw)
    k := 0
    while (k <= maxGap && bTop - 1 - k >= 0) {
        if (BandFrac(bits, w, bTop - 1 - k, bL, bR) >= 0.5) {
            bandBotL := bTop - 1 - k
            break
        }
        k++
    }
    if (bandBotL < 0)
        return 0
    bandTopL := bandBotL
    while (bandTopL - 1 >= 0 && BandFrac(bits, w, bandTopL - 1, bL, bR) >= 0.4)
        bandTopL--
    bandH := bandBotL - bandTopL + 1
    if (bandTopL == 0)                                    ; clipped by the search box
        bandH := Max(bandH, Round(0.055 * tw))
    if (bandH < Max(6, Floor(0.02 * tw)))
        return 0

    x0 := r.x + bL
    progTopAbs := r.y + bTop
    progBotAbs := r.y + bBot
    bandBotAbs := r.y + bandBotL
    bandTopAbs := bandBotAbs - bandH + 1
    hh := progBotAbs - bandTopAbs + 1

    geo := {x0: x0, tw: tw, bandTop: bandTopAbs, hh: hh, bandH: bandH
          , grab: ScreenGrab.Get(tw, hh), rows: [], progRows: []}
    Loop 7
        geo.rows.Push(Round((bandH - 1) * (0.15 + 0.70 * (A_Index - 1) / 6)))
    pl0 := progTopAbs - bandTopAbs
    ph := progBotAbs - progTopAbs
    geo.progRows.Push(pl0 + Round(ph * 0.25))
    geo.progRows.Push(pl0 + Round(ph * 0.50))
    geo.progRows.Push(pl0 + Round(ph * 0.75))
    return geo
}

; The track width is measured once per catch: keep the widest of a few reads,
; because a tile over the strip can make a single read come back short.
AcquireWidest(geo) {
    best := geo
    Loop 4 {
        Sleep(20)
        g2 := FindBar()
        if (g2 && g2.tw > best.tw)
            best := g2
    }
    return best
}

; One grab -> zone / fish / chest spans (pixels, relative to the track).
; Returns 0 when the bar is not readable.
ReadBar(geo, zoneWRef, chestMinW) {
    gr := geo.grab
    gr.Capture(geo.x0, geo.bandTop)
    bits := gr.bits
    w := geo.tw
    rows := geo.rows
    nr := rows.Length
    zThr := Ceil(nr * 0.5)
    fThr := Ceil(nr * 0.25)
    cThr := Ceil(nr * 0.30)

    zl := -1, zr := -1, nz := 0
    fs := -1, fe := -1, bfLen := -1, bfS := -1, bfE := -1
    cs := -1, ce := -1, bcLen := -1, bcS := -1, bcE := -1
    trackHits := 0, total := 0

    x := 0
    while (x < w) {
        zc := 0, fc := 0, cc := 0
        for ry in rows {
            v := NumGet(bits, (ry * w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            total++
            if (Abs(bb - 34) <= 14 && Abs(bb - gg) <= 12 && Abs(gg - rr) <= 12)
                trackHits++
            if (Abs(bb - rr) <= 16
                && ((gg > bb + 10 && gg > rr + 10 && gg > 62)
                    || (Abs(gg - bb) <= 12 && gg >= 62 && gg <= 170)))
                zc++
            if (bb > 110 && bb > rr + 60 && gg > rr + 30)
                fc++
            else if (rr > 140 && gg > 90 && bb < 130 && rr > bb + 60 && gg > bb + 20)
                cc++
        }
        if (zc >= zThr) {
            if (zl < 0)
                zl := x
            zr := x
            nz++
        }
        if (fc >= fThr) {
            if (fs < 0) {
                fs := x
                fe := x
            } else if (x - fe > 4) {
                if (fe - fs > bfLen) {
                    bfLen := fe - fs
                    bfS := fs
                    bfE := fe
                }
                fs := x
                fe := x
            } else {
                fe := x
            }
        }
        if (chestMinW > 0 && cc >= cThr) {
            if (cs < 0) {
                cs := x
                ce := x
            } else if (x - ce > 4) {
                if (ce - cs > bcLen) {
                    bcLen := ce - cs
                    bcS := cs
                    bcE := ce
                }
                cs := x
                ce := x
            } else {
                ce := x
            }
        }
        x += 2
    }
    if (fs >= 0 && fe - fs > bfLen) {
        bfLen := fe - fs
        bfS := fs
        bfE := fe
    }
    if (cs >= 0 && ce - cs > bcLen) {
        bcLen := ce - cs
        bcS := cs
        bcE := ce
    }

    if (nz < 2)
        return 0
    if (total && trackHits / total < 0.25)               ; track background gone
        return 0

    fl := (bfLen >= 2) ? bfS : -1
    fr := (bfLen >= 2) ? bfE + 2 : -1
    cl := -1, cr := -1
    if (chestMinW > 0 && bcLen >= 0 && (bcE - bcS + 2) >= Max(3, chestMinW)) {
        cl := bcS
        cr := bcE + 2
    }
    zr += 2

    ; A tile clipping one end of the zone hides that edge: rebuild it.
    if (zoneWRef > 0 && (zr - zl) < zoneWRef - 8 * BotState.sc) {
        leftHit := (fl >= 0 && fl <= zl + 6) || (cl >= 0 && cl <= zl + 6)
        rightHit := (fr >= 0 && fr >= zr - 6) || (cr >= 0 && cr >= zr - 6)
        if (leftHit && !rightHit)
            zl := zr - zoneWRef
        else if (rightHit && !leftHit)
            zr := zl + zoneWRef
    }
    return {zl: zl, zr: zr, fl: fl, fr: fr, cl: cl, cr: cr}
}

; Fraction (0..1) of the progress bar that is filled, or -1 if unreadable.
ReadProgress(geo) {
    bits := geo.grab.bits
    w := geo.tw
    maxX := -1, cnt := 0
    x := 0
    while (x < w) {
        hit := 0
        for ry in geo.progRows {
            v := NumGet(bits, (ry * w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (gg > 150 && bb < 145 && rr < 185)
                hit++
        }
        if (hit >= 1) {
            cnt++
            maxX := x
        }
        x += 2
    }
    if (cnt < 3)
        return -1
    return Min(1.0, (maxX + 2) / w)
}

; The honest "minigame still up" witness: the two-tone strip spans the track.
ProgressPresent(geo) {
    bits := geo.grab.bits
    w := geo.tw
    ry := geo.progRows[2]
    n := 0, hit := 0
    x := 0
    while (x < w) {
        v := NumGet(bits, (ry * w + x) * 4, "UInt")
        rr := (v >> 16) & 255
        gg := (v >> 8) & 255
        bb := v & 255
        n++
        if (gg > bb + 15 && gg > rr + 15 && gg > 40)
            hit++
        x += 4
    }
    return n && (hit / n) >= 0.5
}

; Bite marker: a magenta-pink ring + "!" (hue 316..358 deg, S>=45/255, V>=110).
; Same method as the Python build: colour mask -> connected blobs (small gaps
; closed) -> shape gates on each blob, so stray pink pixels can't spoil it.
BiteNow() {
    win := BotState.win
    r := SubRect(win, Regions.bite)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    st := Max(3, Round(3.5 * BotState.sc))
    gw := (w + st - 1) // st
    gh := (h + st - 1) // st
    mask := Buffer(gw * gh, 0)
    cxs := [], cys := []

    gy := 0
    y := 0
    while (y < h) {
        base := y * w * 4
        gx := 0
        x := 0
        while (x < w) {
            v := NumGet(bits, base + x * 4, "UInt")
            rr := (v >> 16) & 255
            if (rr >= 110) {
                gg := (v >> 8) & 255
                bb := v & 255
                if (bb > gg && rr >= bb) {
                    d := rr - gg
                    e := bb - gg
                    if (d * 17 >= 3 * rr && e * 100 <= 73 * d && e * 30 >= d) {
                        NumPut("UChar", 1, mask, gy * gw + gx)
                        cxs.Push(gx)
                        cys.Push(gy)
                    }
                }
            }
            x += st
            gx++
        }
        y += st
        gy++
    }
    n := cxs.Length
    BotState.biteInfo := "pink cells=" . n
    if (n < 4 || n > 12000)
        return false

    seen := Buffer(gw * gh, 0)
    gap := 2                                   ; cells: bridges ~8 px gaps (the "close")
    minDim := w * 0.055
    areaFloor := 6e-4 * w * h
    bestDim := 0
    Loop n {
        i := A_Index
        sx := cxs[i], sy := cys[i]
        if NumGet(seen, sy * gw + sx, "UChar")
            continue
        NumPut("UChar", 1, seen, sy * gw + sx)
        stack := [[sx, sy]]
        cnt := 0
        minX := sx, maxX := sx, minY := sy, maxY := sy
        while stack.Length {
            c := stack.Pop()
            px := c[1], py := c[2]
            cnt++
            if (px < minX)
                minX := px
            if (px > maxX)
                maxX := px
            if (py < minY)
                minY := py
            if (py > maxY)
                maxY := py
            ny := Max(0, py - gap)
            while (ny <= Min(gh - 1, py + gap)) {
                nx := Max(0, px - gap)
                while (nx <= Min(gw - 1, px + gap)) {
                    o := ny * gw + nx
                    if (NumGet(mask, o, "UChar") && !NumGet(seen, o, "UChar")) {
                        NumPut("UChar", 1, seen, o)
                        stack.Push([nx, ny])
                    }
                    nx++
                }
                ny++
            }
        }
        bw := (maxX - minX + 1) * st
        bh := (maxY - minY + 1) * st
        area := cnt * st * st
        bestDim := Max(bestDim, Max(bw, bh))
        if (Max(bw, bh) < minDim || area < areaFloor)
            continue
        aspect := bw / bh
        if (aspect <= 0.40 || aspect >= 2.30)
            continue
        if (area / (bw * bh) < 0.10)
            continue
        BotState.biteInfo := "marker " . bw . "x" . bh . " px"
        return true
    }
    BotState.biteInfo := "pink cells=" . n . " largest blob=" . bestDim . " px (need " . Round(minDim) . ")"
    return false
}

IsMeterGreen(c) {
    rr := (c >> 16) & 255
    gg := (c >> 8) & 255
    bb := c & 255
    return gg > 150 && gg > bb + 80 && gg > rr + 80
}

; Cast charge meter: a bright-green vertical bar beside the character
; (~(31,249,16) RGB). Returns its current height in px, 0 when not charging.
; Native PixelSearch finds the top; one thin capture measures the height.
MeterRead() {
    win := BotState.win
    r := SubRect(win, Regions.meter)
    x1 := r.x, y1 := r.y
    x2 := r.x + r.w, y2 := r.y + r.h
    need := Max(10, Round(win.h * 0.03))
    Loop 8 {
        if !PixelSearch(&fx, &fy, x1, y1, x2, y2, 0x1FF910, 30)
            return 0
        xc := fx + Round(3 * BotState.sc)
        maxH := Min(Round(win.h * 0.20), y2 - fy)
        if (maxH >= need) {
            gr := ScreenGrab.Get(1, maxH)
            gr.Capture(xc, fy)
            hgt := 0, miss := 0
            Loop maxH {
                if IsMeterGreen(NumGet(gr.bits, (A_Index - 1) * 4, "UInt")) {
                    hgt := A_Index
                    miss := 0
                } else if (++miss > 3) {
                    break
                }
            }
            if (hgt >= need)
                return hgt
        }
        y1 := fy + 6                       ; false hit (side HUD bar): look below it
        if (y1 >= y2)
            break
    }
    return 0
}

; Recipe note: navy "Learn" button carrying white text.
LearnUp() {
    r := SubRect(BotState.win, Regions.learn)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    n := 0, navy := 0, white := 0
    y := 0
    while (y < r.h) {
        x := 0
        while (x < r.w) {
            v := NumGet(bits, (y * r.w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            n++
            if (bb > 70 && bb < 160 && gg > 30 && gg < 100 && rr < 70 && bb > rr + 45)
                navy++
            else if (bb > 200 && gg > 200 && rr > 200)
                white++
            x += 3
        }
        y += 3
    }
    return n && navy / n >= 0.45 && white / n >= 0.01
}

; Yellow "Craft" action button present?
CraftUp() {
    r := SubRect(BotState.win, Regions.craft)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    y := 0
    while (y < r.h) {
        first := -1, last := -1, cnt := 0
        x := 0
        while (x < r.w) {
            v := NumGet(bits, (y * r.w + x) * 4, "UInt")
            rr := (v >> 16) & 255
            gg := (v >> 8) & 255
            bb := v & 255
            if (rr > 180 && gg > 150 && bb < 110) {
                if (first < 0)
                    first := x
                last := x
                cnt++
            }
            x += 2
        }
        if (first >= 0 && (last - first) >= r.w * 0.25 && cnt * 2 >= (last - first) * 0.5)
            return true
        y += 2
    }
    return false
}

; Update 30 NPC menu: wide, very dark panels (~RGB 28) stacked in the menu
; region. The panel colour is far darker than the night sea behind it, so a
; strict darkness cut separates panels from the gaps between them. Returns an
; array of {x, y} click targets (absolute), top to bottom, or [] when unsure.
MenuPanels() {
    r := SubRect(BotState.win, Regions.menu)
    gr := ScreenGrab.Get(r.w, r.h)
    gr.Capture(r.x, r.y)
    bits := gr.bits
    w := r.w, h := r.h
    colStep := 4
    cols := (w + colStep - 1) // colStep
    nrows := (h + 1) // 2
    counts := []
    counts.Length := nrows
    maxC := 0
    ri := 0
    y := 0
    while (y < h) {
        dark := 0
        base := y * w * 4
        x := 0
        while (x < w) {
            v := NumGet(bits, base + x * 4, "UInt")
            gray := (((v >> 16) & 255) * 299 + ((v >> 8) & 255) * 587 + (v & 255) * 114) // 1000
            if (gray <= 48)
                dark++
            x += colStep
        }
        ri++
        counts[ri] := dark
        if (dark > maxC)
            maxC := dark
        y += 2
    }
    if (maxC < cols * 0.25)
        return []
    need := Max(8, Floor(maxC * 0.35))
    minH := Max(18, Floor(h * 0.09))
    maxH := Max(minH + 1, Floor(h * 0.40))
    panels := []
    start := -1, lastOn := -1

    Loop nrows + 1 {
        i := A_Index
        on := (i <= nrows) && counts[i] >= need
        yy := (i - 1) * 2
        if on {
            if (start < 0)
                start := yy
            lastOn := yy
        } else if (start >= 0 && (i > nrows || yy - lastOn > 4)) {
            hgt := lastOn - start + 1
            if (hgt >= minH && hgt <= maxH)
                panels.Push(PanelTarget(bits, w, colStep, r, start, lastOn))
            start := -1
        }
    }
    return panels.Length >= 2 ? panels : []
}

; Click point: 40 % into the dark span of the panel's middle row.
PanelTarget(bits, w, colStep, r, y0, y1) {
    ym := (y0 + y1) // 2
    xs := -1, xe := -1
    x := 0
    while (x < w) {
        v := NumGet(bits, ym * w * 4 + x * 4, "UInt")
        gray := (((v >> 16) & 255) * 299 + ((v >> 8) & 255) * 587 + (v & 255) * 114) // 1000
        if (gray <= 48) {
            if (xs < 0)
                xs := x
            xe := x
        }
        x += colStep
    }
    if (xs < 0)
        return {x: r.x + w // 2, y: r.y + ym}
    return {x: r.x + xs + Round((xe - xs) * 0.40), y: r.y + ym}
}

PanelSig(panels) {
    s := panels.Length . ":"
    for p in panels
        s .= (p.y // 4) . ","
    return s
}

; ============================================================================
;  SHOP  (NPC dialogue, bait, sell)
; ============================================================================
InDialogue() {
    return MenuPanels().Length >= 2 || CraftUp()
}

SetRod(equipped) {
    if (BotState.rodEquipped == equipped)
        return
    Keys.Tap(Keys.Digit(Cfg.rodSlot))
    BotState.rodEquipped := equipped
    Wait(ShopCfg.afterRod)
}

; Unequip + re-equip right after a catch: the Species/Weight card never shows.
FlickRod() {
    sc := Keys.Digit(Cfg.rodSlot)
    if Cfg.slowFlick {
        Wait(Timing.flickSlowDelay)
        Keys.Tap(sc)
        Wait(Timing.flickSlowGap)
        Keys.Tap(sc)
    } else {
        Keys.Tap(sc)
        Sleep(Round(Timing.flickGap * 1000))
        Keys.Tap(sc)
    }
    Wait(Timing.flickSettle)
}

ShiftCentered(x, y) {
    win := BotState.win
    cx := win.x + win.w // 2
    cy := win.y + win.h // 2
    tol := Max(24, Round(Min(win.w, win.h) * 0.03))
    return Abs(x - cx) <= tol && Abs(y - cy) <= tol
}

; Shift lock is a toggle, so drive it to a known state and PROVE it: the OS
; cursor must snap from away-from-centre to centre.
SetShiftLock(on) {
    if (BotState.shiftLock == on)
        return (!on || BotState.shiftVerified)
    win := BotState.win
    cx := win.x + win.w // 2
    cy := win.y + win.h // 2
    bx := 0, by := 0
    if on {
        MouseGetPos(&bx, &by)
        if ShiftCentered(bx, by) {                       ; make the snap observable
            MouseMove(cx + Round(220 * BotState.sc), cy + Round(160 * BotState.sc), 0)
            Sleep(120)
            MouseGetPos(&bx, &by)
        }
    }
    Keys.Tap(Keys.SC_LSHIFT, 0.10)
    BotState.shiftLock := on
    Wait(ShopCfg.afterShift)
    if !on {
        BotState.shiftVerified := true
        return true
    }
    ax := 0, ay := 0
    MouseGetPos(&ax, &ay)
    verified := ShiftCentered(ax, ay) && !ShiftCentered(bx, by)
    BotState.shiftVerified := verified
    if verified {
        LogMsg("[input] Shift Lock ON - centre cursor confirmed")
        return true
    }
    BotState.shiftLock := false
    LogMsg("[input] Could not verify Shift Lock (before=" . bx . "," . by
        . " after=" . ax . "," . ay . " centre=" . cx . "," . cy
        . ") - refusing to fish. Check Roblox focus, the Shift Lock Switch setting, "
        . "and leave Shift Lock OFF before pressing F2.")
    return false
}

FishingShiftReady() {
    if !(BotState.shiftLock && BotState.shiftVerified)
        return false
    MouseGetPos(&mx, &my)
    still := ShiftCentered(mx, my)
    BotState.shiftVerified := still
    if !still
        BotState.shiftLock := false
    return still
}

EnterFishingStance() {
    if !SetShiftLock(true)
        return false
    BotState.atNpc := false
    return true
}

; Wait until a complete, settled menu page is showing.
WaitMenuPage(page, timeout) {
    expected := PAGE_ROWS[page]
    poll := Max(0.03, ShopCfg.poll)
    deadline := Now() + timeout
    if (BotState.witness != "" && BotState.witness.page == page) {
        p := MenuPanels()
        if (p.Length == expected && PanelSig(p) == BotState.witness.sig)
            return true
        BotState.witness := ""
    }
    stableSig := "", stableSince := 0.0
    while (Now() < deadline) {
        if !Alive()
            return false
        p := MenuPanels()
        sig := PanelSig(p)
        if (p.Length == expected) {
            tn := Now()
            if (sig != stableSig) {
                stableSig := sig
                stableSince := tn
            } else if (tn - stableSince >= ShopCfg.pageSettle) {
                BotState.witness := {page: page, sig: sig}
                return true
            }
        } else {
            stableSig := ""
            stableSince := 0.0
        }
        Wait(poll)
    }
    return false
}

; Click a named action (page + role) using the live stack, with the calibrated
; ordinal dots as a last resort.
ClickMenuAction(page, action) {
    BotState.witness := ""
    index := MENU_ROWS[page][action]
    panels := MenuPanels()
    if panels.Length {
        chosen := index < 0 ? panels.Length + index + 1 : index
        if (chosen >= 1 && chosen <= panels.Length) {
            Mouse.ClickAt(panels[chosen].x, panels[chosen].y)
            return
        }
    }
    fr := (index == 1) ? Points.menu1 : (index == 2) ? Points.menu2
        : (index == 3) ? Points.menu3 : Points.menuLast
    p := PtAbs(fr)
    Mouse.ClickAt(p.x, p.y)
}

WaitUntil(pred, timeout) {
    deadline := Now() + timeout
    while (Now() < deadline) {
        if !Alive()
            return false
        if pred()
            return true
        Wait(ShopCfg.poll)
    }
    return false
}

; Retry one named action only from a stable page, observing its result.
ClickActionUntil(page, action, done, tries, waitSec, nextPage := "") {
    if !WaitMenuPage(page, waitSec)
        return false
    Loop tries {
        if !Alive()
            return false
        if (nextPage == "" && done())
            return true
        ClickMenuAction(page, action)
        if (nextPage != "") {
            if WaitMenuPage(nextPage, waitSec)
                return true
        } else if WaitUntil(done, waitSec) {
            return true
        }
    }
    return (nextPage != "") ? false : done()
}

ClearRecipeNote() {
    if !LearnUp()
        return false
    LogMsg("[catch] new-recipe note - clicking Learn")
    was := BotState.shiftLock
    SetShiftLock(false)
    p := PtAbs(Points.learn)
    Mouse.ClickAt(p.x, p.y)
    Wait(0.6)
    if was
        SetShiftLock(true)
    return true
}

OpenNpcDialogue() {
    ClearRecipeNote()
    if InDialogue() {
        SetShiftLock(false)
        LogMsg("[shop] dialogue already visible - no Interact click")
        if WaitMenuPage("root", ShopCfg.rootTimeout) {
            BotState.atNpc := true
            return true
        }
        LogMsg("[shop] dialogue visible but root rows not confirmed")
        return false
    }
    SetRod(false)
    ip := PtAbs(Points.interact)

    Loop ShopCfg.maxApproach + 1 {
        attempt := A_Index
        if (attempt > 1) {
            LogMsg("[shop] no dialogue - S range probe " . (attempt - 1) . "/" . ShopCfg.maxApproach)
            Keys.Tap(Keys.SC_S, ShopCfg.walkBackTap)
            Wait(ShopCfg.approachWait)
        }
        if !Alive()
            return false
        SetShiftLock(false)
        MouseMove(ip.x, ip.y, 0)
        Wait(0.25)
        BotState.witness := ""
        Mouse.ClickAt(ip.x, ip.y)
        timeout := (attempt == 1) ? ShopCfg.directTimeout : ShopCfg.dialogTimeout
        if WaitMenuPage("root", timeout) {
            BotState.atNpc := true
            return true
        }
        if (attempt == 1 && MenuPanels().Length >= 2) {   ; opening but not settled
            if WaitMenuPage("root", ShopCfg.rootTimeout) {
                BotState.atNpc := true
                return true
            }
            return false
        }
    }
    BotState.atNpc := false
    return false
}

; Back -> Nevermind, waiting for each page instead of sleeping blindly.
LeaveDialogue(tries := 3) {
    Wait(ShopCfg.beforeLeave)
    if !WaitUntil(() => MenuPanels().Length >= 2, ShopCfg.rootTimeout)
        return !InDialogue()
    if (MenuPanels().Length < 4) {
        ClickMenuAction("bait", "back")
        if !WaitMenuPage("root", ShopCfg.rootTimeout)
            return false
    }
    Wait(ShopCfg.rootSettle)
    Loop tries {
        if (!Alive() || !InDialogue())
            return true
        ClickMenuAction("root", "nevermind")
        if WaitUntil(() => !InDialogue(), ShopCfg.nevermindRetry)
            return true
        if (MenuPanels().Length >= 4)
            Wait(ShopCfg.afterBack)
    }
    if InDialogue()
        LogMsg("[shop] could not close the dialogue - stopping this shop route")
    return !InDialogue()
}

; Best-effort exit from whatever dialogue page we are stuck on.
RecoverDialogue() {
    try {
        if CraftUp() {
            p := PtAbs(Points.craftClose)
            Mouse.ClickAt(p.x, p.y)
            Wait(0.5)
        }
        Loop 3 {
            if !Alive()
                break
            ClickMenuAction("root", "nevermind")
            Wait(0.7)
            if !InDialogue()
                break
        }
        Wait(ShopCfg.afterNevermind)
    }
}

EscapeDialogue() {
    if !InDialogue()
        return false
    LogMsg("[cast] a dialogue is open - closing it and stepping away")
    SetShiftLock(false)
    RecoverDialogue()
    SetRod(false)
    SetRod(true)
    BotState.atNpc := true
    EnterFishingStance()
    return true
}

; One confirmed NPC dialogue is the position reset on F2.
EstablishAnchor() {
    LogMsg("[start] opening NPC dialogue to establish fishing position")
    if !OpenNpcDialogue() {
        LogMsg("[start] NPC anchor failed - stand at the NPC on the edge of interaction range")
        return false
    }
    if !LeaveDialogue() {
        LogMsg("[start] NPC dialogue did not close")
        return false
    }
    Wait(ShopCfg.afterNevermind)
    SetRod(true)
    if !EnterFishingStance() {
        LogMsg("[start] Shift Lock did not engage")
        return false
    }
    LogMsg("[start] NPC anchor confirmed")
    return Alive()
}

ShopFail(why, what) {
    LogMsg("[" . what . "] FAILED: " . why)
    RecoverDialogue()
    SetRod(true)
    EnterFishingStance()
    return false
}

BuyBait() {
    ok := BuyBaitRoute()
    if ok {
        BotState.buyFailures := 0
        BotState.bait := Max(0, BotState.bait) + BotState.lastBought
        BotStats.purchases += 1
        LogMsg("[bait] topped up to " . BotState.bait)
        return
    }
    BotState.buyFailures += 1
    if (BotState.buyFailures >= 3) {
        LogMsg("[shop] giving up after 3 failed attempts - fishing on without restocking")
        BotState.bait := -1
    }
}

BuyBaitRoute() {
    amount := Cfg.baitPer
    step := Max(1, ShopCfg.craftStep)
    nPlus := Max(0, (amount // step) - 1)
    bought := step * (nPlus + 1)
    LogMsg("[shop] buying x" . bought . " bait (" . nPlus . " '+' clicks)")

    if !OpenNpcDialogue()
        return ShopFail("NPC dialogue never opened", "shop")
    if !ClickActionUntil("root", "shop", () => MenuPanels().Length == 3
            , 4, ShopCfg.afterClick + 0.6, "shop")
        return ShopFail("Shop page never appeared", "shop")
    if !ClickActionUntil("shop", "buy_bait", () => MenuPanels().Length == 2
            , 4, ShopCfg.afterClick + 0.6, "bait")
        return ShopFail("Buy Bait page never appeared", "shop")
    if !ClickActionUntil("bait", "basic_bait", () => CraftUp()
            , 4, ShopCfg.afterClick + 0.6)
        return ShopFail("CRAFT window never opened", "shop")

    plus := PtAbs(Points.craftPlus)
    Loop nPlus {
        Mouse.ClickAt(plus.x, plus.y)
        Wait(ShopCfg.afterPlus)
    }
    craft := PtAbs(Points.craftBtn)
    closed := false
    Loop 4 {
        if !Alive()
            return false
        Mouse.ClickAt(craft.x, craft.y)
        if WaitUntil(() => !CraftUp(), ShopCfg.craftTimeout) {
            closed := true
            break
        }
    }
    if !closed
        return ShopFail("CRAFT window did not close - purchase unconfirmed", "shop")

    ; From here the bait IS bought: credit it however messy the exit is.
    BotState.lastBought := bought
    NoteResponse()
    if !LeaveDialogue() {
        LogMsg("[shop] bait bought, but the dialogue did not close - stopping safely")
        BotState.running := false
        return true
    }
    Wait(ShopCfg.afterNevermind)
    SetRod(true)
    EnterFishingStance()
    LogMsg("[shop] done - " . bought . " bait bought")
    return true
}

SellFish(stayAtNpc := false) {
    LogMsg("[sell] selling the fish stock")
    if !OpenNpcDialogue()
        return ShopFail("NPC dialogue never opened", "sell")
    if !ClickActionUntil("root", "shop", () => MenuPanels().Length == 3
            , 4, ShopCfg.afterClick + 0.6, "shop")
        return ShopFail("Shop page never appeared", "sell")
    if !ClickActionUntil("shop", "sell_fish", () => MenuPanels().Length == 2
            , 4, ShopCfg.confirmTimeout, "confirm")
        return ShopFail("sell confirmation never appeared", "sell")
    Wait(0.7)

    sold := false
    Loop 3 {
        if (!Alive() || !WaitMenuPage("confirm", ShopCfg.confirmTimeout))
            break
        ClickMenuAction("confirm", "confirm")
        if WaitUntil(() => MenuPanels().Length < 2, ShopCfg.confirmTimeout) {
            sold := true
            break
        }
    }
    if !sold
        return ShopFail("sell confirmation did not close", "sell")

    Wait(ShopCfg.afterNevermind)
    BotStats.sales += 1
    BotState.sinceSell := 0
    NoteResponse()
    if stayAtNpc {
        BotState.atNpc := false
        LogMsg("[sell] done - reopening the NPC for bait")
        return true
    }
    SetRod(true)
    EnterFishingStance()
    LogMsg("[sell] done")
    return true
}

; ============================================================================
;  FISHING ENGINE
; ============================================================================
DoCast() {
    if !FishingShiftReady() {
        LogMsg("[cast] Shift Lock not confirmed - stopping before a free-cursor cast")
        BotState.running := false
        return false
    }
    ; Never cast into a live minigame.
    if FindBar() {
        LogMsg("[cast] a minigame is still running - not casting")
        deadline := Now() + Timing.maxReel
        while (Alive() && Now() < deadline && FindBar())
            Sleep(100)
        return false
    }

    winH := BotState.win.h
    seenMin := Max(10, Round(winH * 0.03))       ; any bar at all = the press took
    plateauMin := Round(winH * 0.08)             ; a plausible "nearly full" height
    Loop Timing.maxCastAttempts {
        attempt := A_Index
        Mouse.Hold(true)
        deadline := Now() + Timing.castHold
        charged := false, perfect := false
        peak := 0, prevH := 0, flat := 0
        tPrev := Now(), rate := 0.0
        full := BotState.meterFull               ; learned full height (0 = not yet)

        while (Alive() && Now() < deadline) {
            hgt := MeterRead()
            tn := Now()
            if (hgt >= seenMin) {
                charged := true
                if !Cfg.perfect {
                    Wait(Min(0.15, Timing.castHold))     ; classic: hold a beat, release
                    break
                }
                if (hgt > peak) {
                    peak := hgt
                    flat := 0
                } else {
                    flat++
                }
                if (prevH > 0 && tn > tPrev)
                    rate := (hgt - prevH) / (tn - tPrev)
                prevH := hgt
                tPrev := tn
                if (full > 0) {
                    ; Release the moment the bar will be full by the time the
                    ; click lands (lead compensates capture + input latency).
                    if (hgt + Max(0.0, rate) * Timing.releaseLead >= full - 1) {
                        perfect := true
                        break
                    }
                } else if (peak >= plateauMin && flat >= 3) {
                    perfect := true                      ; first cast: bar stopped growing = full
                    break
                }
            }
            Sleep(1)
        }
        Mouse.Hold(false)

        if charged {
            if (Cfg.perfect && peak >= plateauMin && peak <= winH * 0.20) {
                if (full <= 0 || peak > full)
                    BotState.meterFull := peak
                LogMsg("[cast] released at " . peak . " px"
                    . (BotState.meterFull > 0 ? " (" . Round(100 * peak / BotState.meterFull) . "% of full)" : "")
                    . (perfect ? "" : " - timed out before full"))
            }
            BotStats.casts += 1
            LogMsg("[cast] #" . BotStats.casts . (attempt == 1 ? "" : " (attempt " . attempt . ")"))
            Wait(Timing.castSettle)
            return true
        }
        if !Alive()
            break
        ; A swallowed press may have hit the NPC instead: close it, step away.
        if EscapeDialogue()
            continue
        LogMsg("[cast] no charge - retrying (" . attempt . "/" . Timing.maxCastAttempts . ")")
        Wait(Timing.castRetryGap)
    }
    BotStats.casts += 1
    LogMsg("[cast] #" . BotStats.casts . " unverified - continuing")
    Wait(Timing.castSettle)
    return false
}

WaitForBite() {
    confirmNeeded := Cfg.fastBite ? 1 : 2
    deadline := Now() + Timing.maxWaitBite
    seen := 0
    while (Alive() && Now() < deadline) {
        if BiteNow() {
            seen++
            if (seen >= confirmNeeded) {
                if !Cfg.fastBite
                    Sleep(Round(Timing.biteClickDelay * 1000))
                Mouse.Tap()
                BotStats.bites += 1
                NoteResponse()
                LogMsg("[bite] hooked")
                if (BotState.bait > 0)                   ; bait is spent at the bite
                    BotState.bait -= 1
                if (BotState.bait >= 0)
                    LogMsg("[bait] " . BotState.bait . " left")
                return true
            }
        } else {
            seen := 0
        }
        Sleep(Cfg.fastBite ? 1 : 8)
    }
    BotStats.biteTimeouts += 1
    LogMsg("[bite] timed out, recasting (" . BotState.biteInfo . ")")
    return false
}

; Drive the minigame. Returns true if it ran through to the end.
Reel() {
    geo := 0
    deadline := Now() + Timing.biteToBar
    while (Alive() && Now() < deadline) {
        geo := FindBar()
        if geo
            break
        Sleep(20)
    }
    if !geo {
        BotStats.missedBar += 1
        LogMsg("[reel] bar never appeared")
        return false
    }
    geo := AcquireWidest(geo)
    tw := geo.tw
    LogMsg("[reel] track width locked at " . tw . " px")

    zoneWRef := 0
    Loop 6 {
        s0 := ReadBar(geo, 0, 0)
        if s0
            zoneWRef := Max(zoneWRef, s0.zr - s0.zl)
    }

    reelCtl.Reset()
    chestMinW := Cfg.chest ? Floor(0.035 * tw) : 0
    chestUntil := 0.0, chestAt := -1.0, chestOn := false
    chestDone := []
    progress := -1.0
    lostSince := 0.0
    stalling := false
    flicked := false
    timedOut := false
    t0 := Now()
    errSum := 0.0, driveTicks := 0, outTicks := 0, ticks := 0

    while Alive() {
        tn := Now()
        ticks++
        if (tn - t0 > Timing.maxReel) {
            timedOut := true
            break
        }
        st := ReadBar(geo, zoneWRef, chestMinW)
        if !st {
            if (lostSince == 0.0) {
                lostSince := tn
                ; If the progress strip went too, the fight is over: flick NOW,
                ; the catch card renders within a couple of frames.
                if (!ProgressPresent(geo) && !flicked && Cfg.flick) {
                    FlickRod()
                    flicked := true
                }
            }
            if (tn - lostSince >= Timing.barLost) {
                if ProgressPresent(geo) {                ; zone hidden (chest / alarm)
                    if !stalling {
                        stalling := true
                        LogMsg("[reel] zone hidden - bar still up, holding on")
                    }
                    lostSince := 0.0
                    continue
                }
                break
            }
            continue
        }
        if stalling {
            stalling := false
            LogMsg("[reel] zone visible again")
        }
        lostSince := 0.0

        if (st.fl < 0)                                   ; fish unreadable: coast
            continue

        zoneC := ((st.zl + st.zr) / 2) / tw
        fishC := ((st.fl + st.fr) / 2) / tw
        zoneHalf := (st.zr - st.zl) / tw / 2
        target := fishC

        ; ---- treasure chests: park the zone on the remembered spot ----------
        if (chestUntil > 0.0 && tn < chestUntil && chestAt >= 0) {
            target := chestAt
            if (!chestOn && Abs(zoneC - chestAt) <= Max(zoneHalf, 0.02)) {
                chestOn := true
                chestUntil := tn + Timing.chestHold
                LogMsg("[chest] reached it - holding " . Timing.chestHold . " s")
            }
        } else if (chestUntil > 0.0) {
            chestUntil := 0.0
            reelCtl.Retarget()
            LogMsg(chestOn ? "[chest] collected, back to the fish"
                           : "[chest] could not reach it in time, back to the fish")
            chestAt := -1.0
            chestOn := false
        } else if (Cfg.chest && st.cl >= 0 && chestDone.Length < Timing.chestMaxGrabs) {
            cx := ((st.cl + st.cr) / 2) / tw
            fresh := true
            for d0 in chestDone {
                if (Abs(cx - d0) <= 0.03)
                    fresh := false
            }
            if (fresh && (progress < 0 || progress >= Timing.chestMinProgress)) {
                chestAt := cx
                chestOn := false
                chestUntil := tn + Timing.chestHold + Timing.chestGrace
                chestDone.Push(cx)
                reelCtl.Retarget()
                LogMsg("[chest] grabbing at " . Round(cx, 2))
                target := cx
            }
        }

        d := reelCtl.Step(tn, zoneC, target, zoneHalf)
        Mouse.Hold(d.hold)

        if !(chestUntil > 0.0 && tn < chestUntil) {
            ae := Abs(d.err)
            errSum += ae
            driveTicks++
            if (ae > Max(zoneHalf, 0.000001))
                outTicks++
        }
        p := ReadProgress(geo)
        if (p >= 0)
            progress := p
    }

    Mouse.Hold(false)
    if !BotState.running
        return false
    elapsed := Now() - t0
    if timedOut {
        LogMsg("[reel] gave up after " . Round(elapsed, 1) . " s (bar never cleared); recasting")
        return false
    }
    BotState.flicked := flicked

    ; Losing the bar is not proof of a catch: watch briefly for it coming back.
    confirmEnd := Now() + Timing.catchConfirm
    while (Alive() && Now() < confirmEnd) {
        if FindBar() {
            LogMsg("[reel] bar came back - still fishing, not a catch")
            return false
        }
        Sleep(30)
    }

    escaped := (progress >= 0 && progress < 0.35)
    BotState.lastEscaped := escaped
    avgErr := driveTicks ? errSum / driveTicks : 0.0
    outPct := driveTicks ? 100.0 * outTicks / driveTicks : 0.0
    LogMsg("[reel] done in " . Round(elapsed, 2) . " s at " . Round(ticks / Max(elapsed, 0.001))
        . " Hz | accel " . Round(reelCtl.accel, 2) . " | err avg " . Round(avgErr * 100, 1)
        . "% | outside " . Round(outPct) . "%"
        . (progress >= 0 ? " | progress " . Round(progress * 100) . "%" : ""))
    if escaped {
        BotStats.escapes += 1
        LogMsg("[reel] the fish got away")
    }
    NoteResponse()
    return true
}

DismissCatch() {
    if Cfg.flick {
        if !BotState.flicked
            FlickRod()
        BotState.flicked := false
    } else {
        ; Fallback: wait for the Species/Weight card, then click it away twice.
        Wait(Timing.popupDelay)
        Mouse.Tap()
        Wait(Timing.catchClickGap)
        Mouse.Tap()
    }
    if BotState.lastEscaped {
        LogMsg("[catch] none - that one escaped; recasting")
    } else {
        BotStats.catches += 1
        BotState.sinceSell += 1
        NoteResponse()
        LogMsg("[catch] #" . BotStats.catches . " - recasting")
    }
    ClearRecipeNote()                                    ; the only popup that never fades
    if !Cfg.flick
        Wait(Timing.catchSettle)
}

WaitBarClear() {
    deadline := Now() + Timing.barClear
    while (Alive() && Now() < deadline) {
        if !FindBar()
            return
        Sleep(30)
    }
}

NeedsBait() {
    return Cfg.buyBait && BotState.bait >= 0 && BotState.bait <= ShopCfg.buyAt
}

NeedsSell() {
    return Cfg.buyBait && Cfg.sellOn && Cfg.sellEvery > 0 && BotState.sinceSell >= Cfg.sellEvery
}

Cycle() {
    RefreshGame()
    if !FocusGame() {
        LogMsg("[warn] Roblox is not focused / not found")
        Wait(1.0)
        return
    }
    ; Recover mid-cycle: a bar is already up (started mid-fight).
    if FindBar() {
        if Reel()
            DismissCatch()
        WaitBarClear()
        return
    }

    sellDue := NeedsSell()
    baitDue := NeedsBait()
    if sellDue {
        ok := SellFish(baitDue)
        if !Alive()
            return
        baitDue := baitDue && ok
    }
    if baitDue {
        BuyBait()
        if !Alive()
            return
    }

    if !DoCast()
        return
    if !Alive()
        return
    if !WaitForBite()
        return
    if !Alive()
        return
    if Reel()
        DismissCatch()
    WaitBarClear()
}

RunBot() {
    BotState.running := true
    ResetStats()
    SyncSettings()
    profile := ApplyResolution()
    RefreshGame()
    NoteResponse()
    LogMsg("[start] control loop started - profile " . profile . ", game area "
        . BotState.win.w . "x" . BotState.win.h)
    CheckResolution()
    SetStatus("Running")

    if !WinExist(ROBLOX_WIN) {
        LogMsg("[start] Roblox window not found - start Roblox first")
        FinishRun()
        return
    }
    FocusGame()
    Wait(0.15)

    BotState.shiftLock := false
    BotState.shiftVerified := false
    BotState.rodEquipped := true
    BotState.atNpc := true
    BotState.sinceSell := 0
    BotState.flicked := false
    BotState.witness := ""
    BotState.bait := (Cfg.buyBait && Cfg.baitNow > 0) ? Cfg.baitNow : -1

    startOk := true
    if Cfg.anchor
        startOk := EstablishAnchor()
    else
        startOk := EnterFishingStance()
    if !startOk {
        FinishRun()
        return
    }

    while Alive() {
        try {
            Cycle()
        } catch as err {
            Mouse.Hold(false)
            LogMsg("[warn] cycle error: " . err.Message . " - recovering")
            Wait(Timing.errorRecovery)
        }
    }
    FinishRun()
}

ResetStats() {
    BotStats.casts := 0
    BotStats.bites := 0
    BotStats.catches := 0
    BotStats.escapes := 0
    BotStats.missedBar := 0
    BotStats.biteTimeouts := 0
    BotStats.sales := 0
    BotStats.purchases := 0
    BotStats.started := Now()
}

FinishRun() {
    BotState.running := false
    try Mouse.Hold(false)
    BotState.shiftVerified := false
    mins := Max(0.001, (Now() - BotStats.started) / 60)
    LogMsg("[stop] casts " . BotStats.casts . " | bites " . BotStats.bites
        . " | catches " . BotStats.catches . " | escapes " . BotStats.escapes
        . " | sales " . BotStats.sales . " | " . Round(BotStats.catches / mins, 1) . " fish/min")
    SetStatus("Idle")
}

ToggleRun(*) {
    if BotState.running {
        BotState.running := false
        LogMsg("[stop] stopping...")
        return
    }
    BotState.running := true
    SetTimer(RunBot, -10)
}

ToggleDebug(*) {
    BotState.debug := !BotState.debug
    LogMsg("[debug] log file " . (BotState.debug ? "ON -> " . LOG_FILE : "OFF"))
}

; ============================================================================
;  SETTINGS + GUI
; ============================================================================
LoadSettings() {
    Cfg.resolution := IniRead(INI_FILE, "display", "resolution", "Auto")
    Cfg.rodSlot    := IniRead(INI_FILE, "fishing", "rodSlot", "4")
    Cfg.fastBite   := IniRead(INI_FILE, "fishing", "fastBite", "0") == "1"
    Cfg.slowFlick  := IniRead(INI_FILE, "fishing", "slowFlick", "0") == "1"
    Cfg.chest      := IniRead(INI_FILE, "fishing", "chest", "1") == "1"
    Cfg.anchor     := IniRead(INI_FILE, "fishing", "anchor", "1") == "1"
    Cfg.perfect    := IniRead(INI_FILE, "fishing", "perfect", "1") == "1"
    Cfg.buyBait    := IniRead(INI_FILE, "shop", "buyBait", "1") == "1"
    Cfg.baitNow    := Integer(IniRead(INI_FILE, "shop", "baitNow", "0"))
    Cfg.baitPer    := Integer(IniRead(INI_FILE, "shop", "baitPer", "40"))
    Cfg.sellOn     := IniRead(INI_FILE, "shop", "sellOn", "1") == "1"
    Cfg.sellEvery  := Integer(IniRead(INI_FILE, "shop", "sellEvery", "100"))
}

SyncSettings() {
    Cfg.resolution := Ui.res.Text
    Cfg.rodSlot    := Ui.rod.Text
    Cfg.fastBite   := Ui.fast.Value == 1
    Cfg.slowFlick  := Ui.slow.Value == 1
    Cfg.chest      := Ui.chest.Value == 1
    Cfg.anchor     := Ui.anchor.Value == 1
    Cfg.perfect    := Ui.perfect.Value == 1
    Cfg.buyBait    := Ui.buy.Value == 1
    Cfg.baitNow    := IntOf(Ui.baitNow, 0)
    Cfg.baitPer    := Max(10, (IntOf(Ui.baitPer, 40) // 10) * 10)
    Cfg.sellOn     := Ui.sell.Value == 1
    Cfg.sellEvery  := IntOf(Ui.sellEvery, 100)
    SaveSettings()
}

IntOf(ctrl, fallback) {
    try return Integer(ctrl.Value)
    return fallback
}

SaveSettings() {
    IniWrite(Cfg.resolution, INI_FILE, "display", "resolution")
    IniWrite(Cfg.rodSlot, INI_FILE, "fishing", "rodSlot")
    IniWrite(Cfg.fastBite ? 1 : 0, INI_FILE, "fishing", "fastBite")
    IniWrite(Cfg.slowFlick ? 1 : 0, INI_FILE, "fishing", "slowFlick")
    IniWrite(Cfg.chest ? 1 : 0, INI_FILE, "fishing", "chest")
    IniWrite(Cfg.anchor ? 1 : 0, INI_FILE, "fishing", "anchor")
    IniWrite(Cfg.perfect ? 1 : 0, INI_FILE, "fishing", "perfect")
    IniWrite(Cfg.buyBait ? 1 : 0, INI_FILE, "shop", "buyBait")
    IniWrite(Cfg.baitNow, INI_FILE, "shop", "baitNow")
    IniWrite(Cfg.baitPer, INI_FILE, "shop", "baitPer")
    IniWrite(Cfg.sellOn ? 1 : 0, INI_FILE, "shop", "sellOn")
    IniWrite(Cfg.sellEvery, INI_FILE, "shop", "sellEvery")
}

SetStatus(text) {
    try Ui.status.Text := "Status: " . text
    try Ui.start.Text := BotState.running ? "Stop  (F2)" : "Start  (F2)"
}

CheckSetup(*) {
    SyncSettings()
    name := ApplyResolution()
    win := RefreshGame()
    LogMsg("---- setup check ----")
    LogMsg("Administrator: " . (A_IsAdmin ? "yes" : "NO - input to Roblox will be dropped"))
    LogMsg("Screen: " . A_ScreenWidth . "x" . A_ScreenHeight . " | profile: " . name
        . " (" . BotState.resW . "x" . BotState.resH . ")")
    if WinExist(ROBLOX_WIN) {
        LogMsg("Roblox game area: " . win.w . "x" . win.h . " at " . win.x . "," . win.y)
        if CheckResolution()
            LogMsg("Resolution matches the selected profile.")
        FindBarReport()
    } else {
        LogMsg("Roblox window NOT found.")
    }
}

FindBarReport() {
    geo := FindBar()
    LogMsg(geo ? "Reel bar visible: track " . geo.tw . " px" : "Reel bar: not on screen (normal when idle)")
}

BuildGui() {
    g := Gui("+AlwaysOnTop", APP_NAME . "  v" . APP_VERSION)
    g.SetFont("s9", "Segoe UI")
    g.OnEvent("Close", (*) => ExitApp())

    g.Add("GroupBox", "x10 y8 w480 h58", "Display")
    g.Add("Text", "x24 y33", "Screen resolution:")
    Ui.res := g.Add("DropDownList", "x140 y29 w150", ["Auto", "1920x1080", "2560x1440"])
    try Ui.res.Choose(Cfg.resolution)
    if (Ui.res.Value == 0)
        Ui.res.Choose(1)
    Ui.resNote := g.Add("Text", "x300 y33 w180 cGray", "Screen: " . A_ScreenWidth . "x" . A_ScreenHeight)

    g.Add("GroupBox", "x10 y72 w480 h118", "Fishing")
    g.Add("Text", "x24 y96", "Rod hotbar slot:")
    Ui.rod := g.Add("DropDownList", "x125 y92 w50", ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
    try Ui.rod.Choose(Cfg.rodSlot)
    if (Ui.rod.Value == 0)
        Ui.rod.Choose(4)
    Ui.fast := g.Add("Checkbox", "x200 y94 w140", "Faster bite reaction")
    Ui.slow := g.Add("Checkbox", "x345 y94 w135", "Slower fish trick")
    Ui.chest := g.Add("Checkbox", "x24 y126 w140", "Collect chests")
    Ui.anchor := g.Add("Checkbox", "x200 y126 w280", "Anchor at the NPC on start (recommended)")
    Ui.perfect := g.Add("Checkbox", "x24 y158 w300", "Perfect cast (release at full charge)")
    Ui.perfect.Value := Cfg.perfect ? 1 : 0
    Ui.fast.Value := Cfg.fastBite ? 1 : 0
    Ui.slow.Value := Cfg.slowFlick ? 1 : 0
    Ui.chest.Value := Cfg.chest ? 1 : 0
    Ui.anchor.Value := Cfg.anchor ? 1 : 0

    g.Add("GroupBox", "x10 y196 w480 h92", "Shop")
    Ui.buy := g.Add("Checkbox", "x24 y218 w140", "Buy bait")
    Ui.buy.Value := Cfg.buyBait ? 1 : 0
    g.Add("Text", "x170 y219", "Bait now (0 = don't track):")
    Ui.baitNow := g.Add("Edit", "x345 y215 w60 Number", Cfg.baitNow)
    g.Add("UpDown", "Range0-9999", Cfg.baitNow)
    g.Add("Text", "x24 y251", "Bait per purchase (x10):")
    Ui.baitPer := g.Add("Edit", "x170 y247 w60 Number", Cfg.baitPer)
    g.Add("UpDown", "Range10-999", Cfg.baitPer)
    Ui.sell := g.Add("Checkbox", "x250 y251 w90", "Sell every")
    Ui.sell.Value := Cfg.sellOn ? 1 : 0
    Ui.sellEvery := g.Add("Edit", "x345 y247 w60 Number", Cfg.sellEvery)
    g.Add("UpDown", "Range0-9999", Cfg.sellEvery)
    g.Add("Text", "x412 y251", "catches")

    Ui.start := g.Add("Button", "x10 y296 w140 h30 Default", "Start  (F2)")
    Ui.start.OnEvent("Click", ToggleRun)
    btnCheck := g.Add("Button", "x160 y296 w140 h30", "Check setup")
    btnCheck.OnEvent("Click", CheckSetup)
    btnQuit := g.Add("Button", "x350 y296 w140 h30", "Quit  (F4)")
    btnQuit.OnEvent("Click", (*) => ExitApp())
    Ui.status := g.Add("Text", "x10 y334 w480", "Status: Idle")

    Ui.log := g.Add("Edit", "x10 y354 w480 r13 ReadOnly -Wrap +VScroll")
    g.Show("w500")
    Ui.gui := g
}

Cleanup(*) {
    try Mouse.Hold(false)
    try DllCall("winmm\timeEndPeriod", "UInt", 1)
}

; ============================================================================
;  STARTUP
; ============================================================================
DllCall("winmm\timeBeginPeriod", "UInt", 1)          ; 1 ms timer resolution
OnExit(Cleanup)
LoadSettings()
BuildGui()
Hotkey("F2", ToggleRun)
Hotkey("F4", (*) => ExitApp())
Hotkey("F8", ToggleDebug)
LogMsg(APP_NAME . " ready. Stand at the Fisherman (Interact prompt visible), rod equipped, "
    . "Shift Lock OFF, then press F2.")
