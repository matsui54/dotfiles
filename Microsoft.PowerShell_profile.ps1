Import-Module PSReadLine
Set-PSReadlineOption -EditMode Emacs
Set-PSReadLineOption -PredictionSource None

Import-Module PSFzf
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$is_admin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (!$is_admin) {
  # Syntax highlighting colors
  Set-PSReadLineOption -Colors @{
    Command            = 'Black'
    Number             = 'DarkGray'
    Member             = 'DarkGray'
    Operator           = 'DarkGray'
    Type               = 'DarkGray'
    Variable           = 'DarkGreen'
    Parameter          = 'DarkGreen'
    ContinuationPrompt = 'DarkGray'
    Default            = 'DarkGray'
  }
   
  # Logging / Progress colors
  $p = $host.privatedata
  $p.ErrorForegroundColor    = "Red"
  $p.ErrorBackgroundColor    = "White"
  $p.WarningForegroundColor  = "Yellow"
  $p.WarningBackgroundColor  = "White"
  $p.DebugForegroundColor    = "Yellow"
  $p.DebugBackgroundColor    = "White"
  $p.VerboseForegroundColor  = "Black"
  $p.VerboseBackgroundColor  = "White"
  $p.ProgressForegroundColor = "DarkGray"
  $p.ProgressBackgroundColor = "White"

  $env:BAT_THEME = 'GitHub'
  $env:FZF_DEFAULT_OPTS = "--color=light"
}
