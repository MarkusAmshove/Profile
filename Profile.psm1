if($Host.Name -ne "ConsoleHost") {
    Remove-Module PSReadLine -ErrorAction SilentlyContinue
    Trace-Message "PSReadLine skipped!"
}

elseif(Get-Module PSReadline) {
    Set-PSReadlineOption -EditMode Emacs

    Set-PSReadlineKeyHandler Ctrl+Shift+C CaptureScreen
    Set-PSReadlineKeyHandler Ctrl+Shift+R ForwardSearchHistory
    Set-PSReadlineKeyHandler Ctrl+R ReverseSearchHistory

    Set-PSReadlineKeyHandler Ctrl+UpArrow HistorySearchBackward
    Set-PSReadlineKeyHandler Ctrl+DownArrow HistorySearchForward

    Set-PSReadlineKeyHandler Ctrl+M SetMark
    Set-PSReadlineKeyHandler Ctrl+Shift+M ExchangePointAndMark
    Set-PSReadLineKeyHandler -Key PageDown -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key PageUp -Function HistorySearchBackward

    Set-PSReadlineKeyHandler Ctrl+K KillLine
    Set-PSReadlineKeyHandler Ctrl+I Yank
    Set-PSReadlineKeyHandler Ctrl+W BackwardKillWord
    Set-PSReadlineKeyHandler -Key CTRL+a -Function SelectAll
    Set-PSReadlineKeyHandler -Key CTRL+v -Function Paste
    Set-PSReadlineKeyHandler -Key CTRL+^ -Function BeginningOfLine

    Set-PSReadlineOption -HistorySaveStyle SaveAtExit
    Trace-Message "PSReadLine fixed"
}

function Set-HostColor {
    <#
        .Description
            Set more reasonable colors, because yellow is for warning, not verbose
    #>
    [CmdletBinding()]
    param(
        # Change the background color only if ConEmu didn't already do that.
        [Switch]$Light=$(Test-Elevation),

        # Don't use the special PowerLine characters
        [Switch]$SafeCharacters,

        # If set, run the script even when it's not the ConsoleHost
        [switch]$Force
    )

    Set-PSReadlineOption -ContinuationPromptForegroundColor DarkGray -ContinuationPrompt "``  "
    Set-PSReadlineOption -EmphasisForegroundColor White -EmphasisBackgroundColor Gray

    Set-PSReadlineOption -TokenKind Keyword   -ForegroundColor "${Dark}Yellow" -BackgroundColor $BackgroundColor
    Set-PSReadlineOption -TokenKind String    -ForegroundColor "DarkGreen" -BackgroundColor $BackgroundColor
    Set-PSReadlineOption -TokenKind Operator  -ForegroundColor "DarkRed" -BackgroundColor $BackgroundColor
    Set-PSReadlineOption -TokenKind Number    -ForegroundColor "Red" -BackgroundColor $BackgroundColor
    Set-PSReadlineOption -TokenKind Variable  -ForegroundColor "${Dark}Magenta" -BackgroundColor $BackgroundColor
    Set-PSReadlineOption -TokenKind Command   -ForegroundColor "${Dark}Gray" -BackgroundColor $BackgroundColor
    Set-PSReadlineOption -TokenKind Parameter -ForegroundColor "DarkCyan" -BackgroundColor $BackgroundColor
    Set-PSReadlineOption -TokenKind Type      -ForegroundColor "Blue" -BackgroundColor $BackgroundColor

    Set-PSReadlineOption -TokenKind Member    -ForegroundColor "Cyan" -BackgroundColor $BackgroundColor
    Set-PSReadlineOption -TokenKind None      -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
    Set-PSReadlineOption -TokenKind Comment   -ForegroundColor "DarkGray" -BackgroundColor $BackgroundColor
}

function Get-PoshGitPowerlineStatus {
    $status = Get-GitStatus
    if(!$status) { return }
    $branchSymbol = [PowerLine.Prompt]::Branch
    $branch = $status.Branch
    $statusLine = "$branchSymbol $branch"

    if($status.AheadBy -eq 0 -and $status.BehindBy -eq 0) {
        $statusLine += " " + $GitPromptSettings.BranchIdenticalStatusToSymbol
    }
    if($status.BehindBy -gt 0 -and $status.AheadBy -eq 0) {
        $statusLine += " " + $GitPromptSettings.BranchBehindStatusSymbol + $status.BehindBy
    }
    if($status.AheadBy -gt 0 -and $status.BehindBy -eq 0) {
        $statusLine += " " + $GitPromptSettings.BranchAheadStatusSymbol + $status.AheadBy
    }
    if($status.AheadBy -gt 0 -and $status.BehindBy -gt 0) {
        $statusLine += " " + $status.AheadBy + $GitPromptSettings.BrandBehindAndAheadStatusSymbol + $status.BehindBy
    }

    if($status.HasWorking) {
        $statusLine += " +" + $status.Working.Added.Count
        $statusLine += " ~" + $status.Working.Modified.Count
        $statusLine += " -" + $status.Working.Deleted.Count
    }
    if($status.HasIndex) {
        if($status.HasWorking) {
            $statusLine += " | "
        }
        $statusLine += " +" + $status.Index.Added.Count
        $statusLine += " ~" + $status.Index.Modified.Count
        $statusLine += " -" + $status.Index.Deleted.Count
    }

    return $statusLine
}

function Update-ToolPath {
    #.Synopsis
    # Add useful things to the PATH which aren't normally there on Windows.
    #.Description
    # Add Tools, Utilities, or Scripts folders which are in your profile to your Env:PATH variable
    # Also adds the location of msbuild, merge, tf and python, as well as iisexpress
    # Is safe to run multiple times because it makes sure not to have duplicates.
    param()

    ## I add my "Scripts" directory and all of its direct subfolders to my PATH
    [string[]]$folders = Get-ChildItem $ProfileDir\Tool[s], $ProfileDir\Utilitie[s], $ProfileDir\Scripts\*, $ProfileDir\Script[s] -ad | % FullName

    ## Developer tools stuff ...
    ## I need InstallUtil, MSBuild, and TF (TFS) and they're all in the .Net RuntimeDirectory OR Visual Studio*\Common7\IDE
    if("System.Runtime.InteropServices.RuntimeEnvironment" -as [type]) {
        $folders += [System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
    }

    ## MSBuild is now in 'C:\Program Files (x86)\MSBuild\{version}'
    $folders += Set-AliasToFirst -Alias "msbuild" -Path 'C:\Program*Files*\*Visual?Studio*\*\*\MsBuild\*\Bin\MsBuild.exe', 'C:\Program*Files*\MSBuild\*\Bin\MsBuild.exe' -Description "Visual Studio's MsBuild" -Force -Passthru
    Trace-Message "Development aliases set"

    $ENV:PATH = Select-UniquePath $folders ${Env:Path}
    Trace-Message "Env:PATH Updated"
}

if(!$ProfileDir -or !(Test-Path $ProfileDir)) {
    $ProfileDir = Split-Path $Profile.CurrentUserAllHosts
}

## The qq shortcut for quick quotes
Set-Alias qq ConvertTo-StringArray
function ConvertTo-StringArray {
    <#
        .Synopsis
            Cast parameter array to string (see examples)
        .Example
            $array = qq there is no need to use quotes or commas to create a string array

            Is the same as writing this, but with a lot less typing::
            $array = "there", "is", "no", "need", "to", "use", "quotes", "or", "commas", "to", "create", "a", "string", "array"
    #>
    param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$InputObject
    )
    $InputObject
}

Trace-Message "Random Quotes Loaded"

# Run these functions once
Update-ToolPath

# Unfortunately, in order for our File Format colors and History timing to take prescedence, we need to PREPEND the path:
Update-FormatData -PrependPath (Join-Path $PSScriptRoot 'Formats.ps1xml')

function spc { & "C:\Program Files\SpeedProject\SpeedCommander 16\SpeedCommander.exe" $pwd }
if(Get-Command fzf) {
	function gfzf { fzf | %{ gvim $_ } }
	function vfzf { fzf | %{ vim $_ } }
	function fbr() {
    		$branches = git branch -vv
    		$branch = ($branches | fzf +m)
    		$selected = $branch.Replace("*", "").Trim().Split(" ")[0]
    		git checkout $selected
	}

	function fshow() {
    		$commit = git log --graph --color=always --format="%C(auto)%h%d %s %C(black)%C(bold)%cr <%an>" |
				fzf --ansi --no-sort --reverse --tiebreak=index 
		$selected = $commit.Replace("*", "").Replace("|", "").Replace("\", "").Replace("/", "").Trim().Split(" ")[0]
		git show $selected
	}

	function ftk() {
		$commit = git log --graph --color=always --format="%C(auto)%h%d %s %C(black)%C(bold)%cr <%an>" |
				fzf --ansi --no-sort --reverse --tiebreak=index 
		$commit -match "Ticket #(\d+):" | Out-Null
		$Matches[1] | clip
	}

	function fco() {
    		$commit = git log --graph --color=always --format="%C(auto)%h%d %s %C(black)%C(bold) <%an> %cr" |
				fzf --ansi --no-sort --reverse --tiebreak=index 
		if(![System.String]::IsNullOrEmpty($commit)) {
			$selected = $commit.Replace("*", "").Replace("|", "").Replace("\", "").Replace("/", "").Trim().Split(" ")[0]
			git checkout $selected
		}
	}

}
function magit { vim -c MagitOnly }
Set-Alias gradlew .\gradlew
Set-Alias rgg "& rg --files -g"
Export-ModuleMember -Function * -Alias *
