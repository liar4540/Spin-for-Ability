# Spin for Abilities - grabs the Roblox Studio window into a PNG (PrintWindow, so it works even when
# another window is on top). Usage:
#   powershell -ExecutionPolicy Bypass -File capture_studio_window.ps1 <out.png> [count] [intervalMs] [title]
# With count > 1 it writes a burst named <out dir>\<unix ms>.png instead, for timed comparisons.
# title: part of the window title to pick when several Studio windows are open (a local server test
# opens "Server - Roblox Studio" / "Client - ..." windows next to the place's own).
param([string]$Out, [int]$Count = 1, [int]$IntervalMs = 33, [string]$Title = "")

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[Win]::SetProcessDPIAware() | Out-Null

$proc = Get-Process RobloxStudioBeta -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 -and ($Title -eq "" -or $_.MainWindowTitle -like "*$Title*") } | Select-Object -First 1
$h = $proc.MainWindowHandle
if ([Win]::IsIconic($h)) {
    # A minimized window renders nothing: restore it without taking focus (SW_SHOWNOACTIVATE).
    [Win]::ShowWindow($h, 4) | Out-Null
    Start-Sleep -Milliseconds 800
}
$r = New-Object Win+RECT
[Win]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top

for ($i = 0; $i -lt $Count; $i++) {
    # the time the frame is grabbed (PrintWindow takes ~100 ms: stamping after it read ~0.03 game s late at 0.25x)
    $ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $bmp = New-Object System.Drawing.Bitmap $w, $ht
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [Win]::PrintWindow($h, $hdc, 2) | Out-Null  # 2 = PW_RENDERFULLCONTENT (needed for the 3D viewport)
    $g.ReleaseHdc($hdc); $g.Dispose()
    if ($Count -gt 1) {
        $path = Join-Path (Split-Path $Out) "$ms.png"
    } else { $path = $Out }
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    if ($Count -gt 1) { Start-Sleep -Milliseconds $IntervalMs }
}
Write-Output "saved $Count capture(s), window ${w}x${ht}"
