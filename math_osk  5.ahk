#Requires AutoHotkey v2.0
#SingleInstance Force

; Make this script DPI-aware. Without this, on a scaled display
; (125%, 150%, etc. - very common on laptops) AutoHotkey can
; miscalculate where the taskbar actually is, causing "snap to
; bottom" to land a bit too low and slide underneath it.
DllCall("SetProcessDpiAwarenessContext", "ptr", -4) ; DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2

; ============================================================
; Math On-Screen Keyboard
; A wide bar docked at the bottom of the screen, like Windows'
; built-in On-Screen Keyboard (OSK), but with math symbols
; and numbers instead of letters. Resizable and semi-transparent.
;
; Like the real Windows OSK, this window is marked so it can
; never become the "active" window (WS_EX_NOACTIVATE). That
; means whatever app you were typing into (Word, browser, etc.)
; never loses focus in the first place - clicking a key just
; sends it straight there via SendInput, with no flicker and
; no need to click back into the right window first.
;
; Also supports Hover Mode: hold the mouse still over a key for
; a short moment and it "clicks" automatically, for anyone who
; finds clicking itself difficult.
; ============================================================

global KeyControls := []
global RebuildPending := false
global TopBarH := 34

global HoverModeOn := false
global HoverCandidateHwnd := 0
global HoverCandidateLabel := ""
global HoverStartTick := 0
global HoverFired := false
global HoverDelayMs := 700 ; how long to hover before it "clicks"

; ---------------- Key layout ----------------
; Each inner array = one row of the keyboard, left to right.
KeyRows := [
    ["7", "8", "9", "/", "(", ")", "√", "⌫"],
    ["4", "5", "6", "*", "^", "x²", "x³", "π"],
    ["1", "2", "3", "-", "=", "≠", "≈", "∞"],
    ["0", ".", ",", "+", "±", "<", ">", "≤", "≥"],
    ["%", "!", "°", "∑", "∫", "θ", "α", "␣"]
]

; ---------------- Build the GUI ----------------

; +E0x08000000 = WS_EX_NOACTIVATE - this window can be clicked
; without ever becoming the foreground/active window, so the
; app you're typing into keeps focus the whole time.
MathOSK := Gui("+AlwaysOnTop +Resize -MaximizeBox +E0x08000000", "Math On-Screen Keyboard")
MathOSK.BackColor := "1E1E1E"
MathOSK.SetFont("s14 Bold cWhite", "Segoe UI")
MathOSK.OnEvent("Size", OnResize)
MathOSK.OnEvent("Close", (*) => ExitApp())

; Top control bar
snapBtn := MathOSK.Add("Button", "x10 y4 w150 h26", "Snap to Bottom")
snapBtn.OnEvent("Click", SnapToBottom)

snapTopBtn := MathOSK.Add("Button", "x170 y4 w150 h26", "Snap to Top")
snapTopBtn.OnEvent("Click", SnapToTop)

hoverBtn := MathOSK.Add("Button", "x330 y4 w170 h26", "Hover Mode: Off")
hoverBtn.OnEvent("Click", ToggleHoverMode)

; Work out an initial size/position: wide bar near the bottom of the screen.
MonitorGetWorkArea(, &waLeft, &waTop, &waRight, &waBottom)
screenW := waRight - waLeft
initW := Round(screenW * 0.6)
initH := 200
initX := waLeft + Round((screenW - initW) / 2)
initY := waBottom - initH - 10

MathOSK.Show(Format("x{} y{} w{} h{}", initX, initY, initW, initH))
WinSetTransparent(235, MathOSK)

BuildKeys()

; ---------------- Layout logic ----------------

OnResize(GuiObj, MinMax, Width, Height) {
    global RebuildPending
    if (MinMax = -1) ; minimized
        return
    if (MinMax = 1) {
        ; Maximized (e.g. via drag-to-top-of-screen or double-click title bar) -
        ; undo it and fall back to a large-but-not-maximized size instead.
        WinRestore(GuiObj.Hwnd)
        MonitorGetWorkArea(, &waLeft, &waTop, &waRight, &waBottom)
        restoreW := Round((waRight - waLeft) * 0.6)
        restoreH := 200
        restoreX := waLeft + Round(((waRight - waLeft) - restoreW) / 2)
        restoreY := waBottom - restoreH - 10
        WinMove(restoreX, restoreY, restoreW, restoreH, GuiObj.Hwnd)
        return
    }
    if (RebuildPending)
        return
    RebuildPending := true
    SetTimer(DoRebuild, -120) ; debounce rapid resize events
}

SnapToBottom(*) {
    global MathOSK
    MathOSK.GetPos(&curX, &curY, &curW, &curH)
    ; MonitorGetWorkArea excludes the taskbar, so this stops
    ; right above it rather than sliding behind it.
    MonitorGetWorkArea(, &waLeft, &waTop, &waRight, &waBottom)
    newY := waBottom - curH
    MathOSK.Move(, newY)
}

SnapToTop(*) {
    global MathOSK
    MonitorGetWorkArea(, &waLeft, &waTop, &waRight, &waBottom)
    MathOSK.Move(, waTop)
}

DoRebuild() {
    global RebuildPending
    RebuildPending := false
    BuildKeys()
}

BuildKeys() {
    global KeyControls, KeyRows, MathOSK, TopBarH

    ; Remove old buttons
    for ctrl in KeyControls {
        try ctrl.Destroy()
    }
    KeyControls := []

    MathOSK.GetClientPos(, , &clientW, &clientH)
    if (clientW < 100 || clientH < 100)
        return

    marginX := 10
    marginY := 10
    gap := 6
    topOffset := TopBarH + marginY

    numRows := KeyRows.Length
    availH := clientH - topOffset - marginY
    rowH := (availH - gap * (numRows - 1)) / numRows

    for rowIndex, rowItems in KeyRows {
        numCols := rowItems.Length
        rowW := clientW - marginX * 2
        keyW := (rowW - gap * (numCols - 1)) / numCols
        yPos := topOffset + (rowIndex - 1) * (rowH + gap)

        for colIndex, label in rowItems {
            xPos := marginX + (colIndex - 1) * (keyW + gap)
            btn := MathOSK.Add("Button", Format("x{} y{} w{} h{}", Round(xPos), Round(yPos), Round(keyW), Round(rowH)), label)
            btn.OnEvent("Click", MakeClickHandler(label))
            KeyControls.Push(btn)
        }
    }
}

; ---------------- Button logic ----------------

MakeClickHandler(label) {
    return SendLabel.Bind(label)
}

; Because MathOSK never becomes the active window (WS_EX_NOACTIVATE),
; whatever app you were typing into is still the foreground window
; here - SendText/Send go straight to it, no activating required.
SendLabel(label, *) {
    if (label = "⌫") {
        Send("{BackSpace}")
    } else if (label = "␣") {
        Send("{Space}")
    } else {
        SendText(label)
    }
}

; ---------------- Hover Mode ----------------

ToggleHoverMode(ctrlObj, *) {
    global HoverModeOn, HoverCandidateHwnd, HoverFired
    HoverModeOn := !HoverModeOn
    ctrlObj.Text := HoverModeOn ? "Hover Mode: On" : "Hover Mode: Off"
    HoverCandidateHwnd := 0
    HoverFired := false
    if (HoverModeOn) {
        SetTimer(HoverCheck, 60)
    } else {
        SetTimer(HoverCheck, 0)
    }
}

HoverCheck() {
    global HoverModeOn, KeyControls, MathOSK
    global HoverCandidateHwnd, HoverCandidateLabel, HoverStartTick, HoverFired, HoverDelayMs

    if (!HoverModeOn)
        return

    MouseGetPos(, , &winUnderMouse, &ctrlHwndUnderMouse, 2) ; flag 2 -> control's hwnd

    if (winUnderMouse != MathOSK.Hwnd) {
        HoverCandidateHwnd := 0
        HoverFired := false
        return
    }

    ; Find which key button (if any) the mouse is over
    matchedLabel := ""
    for btn in KeyControls {
        if (btn.Hwnd = ctrlHwndUnderMouse) {
            matchedLabel := btn.Text
            break
        }
    }

    if (matchedLabel = "") {
        HoverCandidateHwnd := 0
        HoverFired := false
        return
    }

    if (ctrlHwndUnderMouse != HoverCandidateHwnd) {
        ; Moved onto a new key - restart the dwell timer
        HoverCandidateHwnd := ctrlHwndUnderMouse
        HoverCandidateLabel := matchedLabel
        HoverStartTick := A_TickCount
        HoverFired := false
        return
    }

    ; Still hovering the same key
    if (!HoverFired && (A_TickCount - HoverStartTick >= HoverDelayMs)) {
        HoverFired := true
        SendLabel(HoverCandidateLabel)
    }
}