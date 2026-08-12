# ensure-path.ps1 -- append one directory to the per-user PATH, safely.
#
# Why not setx: `setx PATH "%PATH%;dir"` writes the merged process PATH
# (machine + user) into HKCU\Environment and silently truncates the value at
# 1024 characters, so on machines with a long PATH the appended directory is
# exactly what gets cut off, and the user PATH ends up polluted with
# duplicated machine entries. This script edits only the user PATH value,
# preserves its registry type (REG_EXPAND_SZ entries stay unexpanded), and
# broadcasts WM_SETTINGCHANGE so newly opened terminals see the change.

param([Parameter(Mandatory = $true)][string]$PathEntry)

$ErrorActionPreference = 'Stop'

$expandedEntry = [Environment]::ExpandEnvironmentVariables($PathEntry).TrimEnd('\')

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
try {
    $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
    $current = ''
    if ($key.GetValueNames() -contains 'Path') {
        $kind = $key.GetValueKind('Path')
        $current = [string]$key.GetValue('Path', '',
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }

    $present = @($current -split ';' | Where-Object { $_ -ne '' } | Where-Object {
        [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $expandedEntry
    })

    if ($present.Count -gt 0) {
        Write-Output "ensure-path: '$PathEntry' already on user PATH"
    }
    else {
        $new = if ($current) { $current.TrimEnd(';') + ';' + $PathEntry } else { $PathEntry }
        $key.SetValue('Path', $new, $kind)
        Write-Output "ensure-path: appended '$PathEntry' to user PATH"
    }
}
finally {
    $key.Close()
}

# Same broadcast setx sends; without it Explorer (and anything launched from
# it, like a new terminal) keeps the old environment until the next logon.
$signature = @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
$native = Add-Type -MemberDefinition $signature -Name 'EnvBroadcast' `
    -Namespace 'ClaudeInstaller' -PassThru
[UIntPtr]$result = [UIntPtr]::Zero
$null = $native::SendMessageTimeout([IntPtr]0xFFFF, 0x001A, [UIntPtr]::Zero,
    'Environment', 0x0002, 5000, [ref]$result)
