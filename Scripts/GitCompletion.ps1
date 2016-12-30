# Based on GitUtils.ps1 and GitTabExpansion.ps1 from posh-git (https://github.com/dahlbyk/posh-git)

$Global:GitTabSettings = New-Object PSObject -Property @{
    AllCommands = $false
}

function Get-GitBranch($gitDir = $(Get-GitDirectory), [Diagnostics.Stopwatch]$sw) {
    if ($gitDir) {
        $r = ''; $b = ''; $c = ''
        if (Test-Path $gitDir\rebase-merge\interactive) {
            $r = '|REBASE-i'
            $b = "$(Get-Content $gitDir\rebase-merge\head-name)"
        }
        elseif (Test-Path $gitDir\rebase-merge) {
            $r = '|REBASE-m'
            $b = "$(Get-Content $gitDir\rebase-merge\head-name)"
        }
        else {
            if (Test-Path $gitDir\rebase-apply) {
                if (Test-Path $gitDir\rebase-apply\rebasing) {
                    $r = '|REBASE'
                }
                elseif (Test-Path $gitDir\rebase-apply\applying) {
                    $r = '|AM'
                }
                else {
                    $r = '|AM/REBASE'
                }
            }
            elseif (Test-Path $gitDir\MERGE_HEAD) {
                $r = '|MERGING'
            }
            elseif (Test-Path $gitDir\CHERRY_PICK_HEAD) {
                $r = '|CHERRY-PICKING'
            }
            elseif (Test-Path $gitDir\BISECT_LOG) {
                $r = '|BISECTING'
            }

            $b = Invoke-NullCoalescing `
                { '({0})' -f (Invoke-NullCoalescing `
                    {
                        switch ($Global:GitPromptSettings.DescribeStyle) {
                            'contains' { git describe --contains HEAD 2>$null }
                            'branch' { git describe --contains --all HEAD 2>$null }
                            'describe' { git describe HEAD 2>$null }
                            default { git tag --points-at HEAD 2>$null }
                        }
                    } `
                    {
                        $ref = $null

                        if (Test-Path $gitDir\HEAD) {
                            $ref = Get-Content $gitDir\HEAD 2>$null
                        }
                        else {
                            $ref = git rev-parse HEAD 2>$null
                        }

                        if ($ref -match 'ref: (?<ref>.+)') {
                            return $Matches['ref']
                        }
                        elseif ($ref -and $ref.Length -ge 7) {
                            return $ref.Substring(0,7)+'...'
                        }
                        else {
                            return 'unknown'
                        }
                    }
                ) }
        }

        if ('true' -eq $(git rev-parse --is-inside-git-dir 2>$null)) {
            if ('true' -eq $(git rev-parse --is-bare-repository 2>$null)) {
                $c = 'BARE:'
            }
            else {
                $b = 'GIT_DIR!'
            }
        }

        "$c$($b -replace 'refs/heads/','')$r"
    }
}

function GetUniquePaths($pathCollections) {
    $hash = New-Object System.Collections.Specialized.OrderedDictionary

    foreach ($pathCollection in $pathCollections) {
        foreach ($path in $pathCollection) {
            $hash[$path] = 1
        }
    }

    $hash.Keys
}

function Get-GitStatus($gitDir = (Get-GitDirectory)) {
    $settings = $Global:GitPromptSettings
    $enabled = (-not $settings) -or $settings.EnablePromptStatus
    if($settings.Debug) {
        $sw = [Diagnostics.Stopwatch]::StartNew(); Write-Host ''
    }
    else {
        $sw = $null
    }

    $branch = $null
    $aheadBy = 0
    $behindBy = 0
    $gone = $false
    $indexAdded = New-Object System.Collections.Generic.List[string]
    $indexModified = New-Object System.Collections.Generic.List[string]
    $indexDeleted = New-Object System.Collections.Generic.List[string]
    $indexUnmerged = New-Object System.Collections.Generic.List[string]
    $filesAdded = New-Object System.Collections.Generic.List[string]
    $filesModified = New-Object System.Collections.Generic.List[string]
    $filesDeleted = New-Object System.Collections.Generic.List[string]
    $filesUnmerged = New-Object System.Collections.Generic.List[string]
    $stashCount = 0

    if($settings.EnableFileStatus -and !$(InDisabledRepository)) {
        $status = git -c color.status=false status --short --branch 2>$null
        if($settings.EnableStashStatus) {
            $stashCount = $null | git stash list 2>$null | measure-object | Select-Object -expand Count
        }
    }
    else {
        $status = @()
    }

    switch -regex ($status) {
        '^(?<index>[^#])(?<working>.) (?<path1>.*?)(?: -> (?<path2>.*))?$' {

            switch ($matches['index']) {
                'A' { $null = $indexAdded.Add($matches['path1']); break }
                'M' { $null = $indexModified.Add($matches['path1']); break }
                'R' { $null = $indexModified.Add($matches['path1']); break }
                'C' { $null = $indexModified.Add($matches['path1']); break }
                'D' { $null = $indexDeleted.Add($matches['path1']); break }
                'U' { $null = $indexUnmerged.Add($matches['path1']); break }
            }
            switch ($matches['working']) {
                '?' { $null = $filesAdded.Add($matches['path1']); break }
                'A' { $null = $filesAdded.Add($matches['path1']); break }
                'M' { $null = $filesModified.Add($matches['path1']); break }
                'D' { $null = $filesDeleted.Add($matches['path1']); break }
                'U' { $null = $filesUnmerged.Add($matches['path1']); break }
            }
            continue
        }

        '^## (?<branch>\S+?)(?:\.\.\.(?<upstream>\S+))?(?: \[(?:ahead (?<ahead>\d+))?(?:, )?(?:behind (?<behind>\d+))?(?<gone>gone)?\])?$' {

            $branch = $matches['branch']
            $upstream = $matches['upstream']
            $aheadBy = [int]$matches['ahead']
            $behindBy = [int]$matches['behind']
            $gone = [string]$matches['gone'] -eq 'gone'
            continue
        }

        '^## Initial commit on (?<branch>\S+)$' {
            $branch = $matches['branch']
            continue
        }

        default {}

    }

    if(!$branch) { $branch = Get-GitBranch $gitDir $sw }

    # This collection is used twice, so create the array just once
    $filesAdded = $filesAdded.ToArray()

    $indexPaths = @(GetUniquePaths $indexAdded,$indexModified,$indexDeleted,$indexUnmerged)
    $workingPaths = @(GetUniquePaths $filesAdded,$filesModified,$filesDeleted,$filesUnmerged)
    $index = (,$indexPaths) |
        Add-Member -PassThru NoteProperty Added    $indexAdded.ToArray() |
        Add-Member -PassThru NoteProperty Modified $indexModified.ToArray() |
        Add-Member -PassThru NoteProperty Deleted  $indexDeleted.ToArray() |
        Add-Member -PassThru NoteProperty Unmerged $indexUnmerged.ToArray()

    $working = (,$workingPaths) |
        Add-Member -PassThru NoteProperty Added    $filesAdded |
        Add-Member -PassThru NoteProperty Modified $filesModified.ToArray() |
        Add-Member -PassThru NoteProperty Deleted  $filesDeleted.ToArray() |
        Add-Member -PassThru NoteProperty Unmerged $filesUnmerged.ToArray()

    $result = New-Object PSObject -Property @{
        GitDir          = $gitDir
        Branch          = $branch
        AheadBy         = $aheadBy
        BehindBy        = $behindBy
        UpstreamGone    = $gone
        Upstream        = $upstream
        HasIndex        = [bool]$index
        Index           = $index
        HasWorking      = [bool]$working
        Working         = $working
        HasUntracked    = [bool]$filesAdded
        StashCount      = $stashCount
    }

    if($sw) { $sw.Stop() }
    return $result
}

$subcommands = @{
    bisect = 'start bad good skip reset visualize replay log run'
    notes = 'edit show'
    reflog = 'expire delete show'
    remote = 'add rename rm set-head show prune update'
    stash = 'list show drop pop apply branch save clear create'
    submodule = 'add status init update summary foreach sync'
    svn = 'init fetch clone rebase dcommit branch tag log blame find-rev set-tree create-ignore show-ignore mkdirs commit-diff info proplist propget show-externals gc reset'
    tfs = 'bootstrap checkin checkintool ct cleanup cleanup-workspaces clone diagnostics fetch help init pull quick-clone rcheckin shelve shelve-list unshelve verify'
    flow = 'init feature release hotfix'
}

$gitflowsubcommands = @{
    feature = 'list start finish publish track diff rebase checkout pull delete'
    release = 'list start finish publish track delete'
    hotfix = 'list start finish publish delete'
}

function script:gitCmdOperations($commands, $command, $filter) {
    $commands.$command -split ' ' |
        Where-Object { $_ -like "$filter*" }
}


$script:someCommands = @('add','am','annotate','archive','bisect','blame','branch','bundle','checkout','cherry',
                         'cherry-pick','citool','clean','clone','commit','config','describe','diff','difftool','fetch',
                         'format-patch','gc','grep','gui','help','init','instaweb','log','merge','mergetool','mv',
                         'notes','prune','pull','push','rebase','reflog','remote','rerere','reset','revert','rm',
                         'shortlog','show','stash','status','submodule','svn','tag','whatchanged')
try {
  if ($null -ne (git help -a 2>&1 | Select-String flow)) {
      $script:someCommands += 'flow'
  }
}
catch {
    Write-Debug "Search for 'flow' in 'git help' output failed with error: $_"
}

function script:gitCommands($filter, $includeAliases) {
    $cmdList = @()
    if (-not $global:GitTabSettings.AllCommands) {
        $cmdList += $someCommands -like "$filter*"
    } else {
        $cmdList += git help --all |
            Where-Object { $_ -match '^  \S.*' } |
            ForEach-Object { $_.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) } |
            Where-Object { $_ -like "$filter*" }
    }

    if ($includeAliases) {
        $cmdList += gitAliases $filter
    }
    $cmdList | Sort-Object
}

function script:gitRemotes($filter) {
    git remote |
        Where-Object { $_ -like "$filter*" }
}

function script:gitBranches($filter, $includeHEAD = $false) {
    $prefix = $null
    if ($filter -match "^(?<from>\S*\.{2,3})(?<to>.*)") {
        $prefix = $matches['from']
        $filter = $matches['to']
    }
    $branches = @(git branch --no-color | ForEach-Object { if($_ -match "^\*?\s*(?<ref>.*)") { $matches['ref'] } }) +
                @(git branch --no-color -r | ForEach-Object { if($_ -match "^  (?<ref>\S+)(?: -> .+)?") { $matches['ref'] } }) +
                @(if ($includeHEAD) { 'HEAD','FETCH_HEAD','ORIG_HEAD','MERGE_HEAD' })
    $branches |
        Where-Object { $_ -ne '(no branch)' -and $_ -like "$filter*" } |
        ForEach-Object { $prefix + $_ }
}

function script:gitTags($filter) {
    git tag |
        Where-Object { $_ -like "$filter*" }
}

function script:gitFeatures($filter, $command){
	$featurePrefix = git config --local --get "gitflow.prefix.$command"
    $branches = @(git branch --no-color | ForEach-Object { if($_ -match "^\*?\s*$featurePrefix(?<ref>.*)") { $matches['ref'] } })
    $branches |
        Where-Object { $_ -ne '(no branch)' -and $_ -like "$filter*" } |
        ForEach-Object { $prefix + $_ }
}

function script:gitRemoteBranches($remote, $ref, $filter) {
    git branch --no-color -r |
        Where-Object { $_ -like "  $remote/$filter*" } |
        ForEach-Object { $ref + ($_ -replace "  $remote/","") }
}

function script:gitStashes($filter) {
    (git stash list) -replace ':.*','' |
        Where-Object { $_ -like "$filter*" } |
        ForEach-Object { "'$_'" }
}

function script:gitTfsShelvesets($filter) {
    (git tfs shelve-list) |
        Where-Object { $_ -like "$filter*" } |
        ForEach-Object { "'$_'" }
}

function script:gitFiles($filter, $files) {
    $files | Sort-Object |
        Where-Object { $_ -like "$filter*" } |
        ForEach-Object { if($_ -like '* *') { "'$_'" } else { $_ } }
}

function script:gitIndex($filter) {
    gitFiles $filter $GitStatus.Index
}

function script:gitAddFiles($filter) {
    gitFiles $filter (@($GitStatus.Working.Unmerged) + @($GitStatus.Working.Modified) + @($GitStatus.Working.Added))
}

function script:gitCheckoutFiles($filter) {
    gitFiles $filter (@($GitStatus.Working.Unmerged) + @($GitStatus.Working.Modified) + @($GitStatus.Working.Deleted))
}

function script:gitDiffFiles($filter, $staged) {
    if ($staged) {
        gitFiles $filter $GitStatus.Index.Modified
    }
    else {
        gitFiles $filter (@($GitStatus.Working.Unmerged) + @($GitStatus.Working.Modified) + @($GitStatus.Index.Modified))
    }
}

function script:gitMergeFiles($filter) {
    gitFiles $filter $GitStatus.Working.Unmerged
}

function script:gitDeleted($filter) {
    gitFiles $filter $GitStatus.Working.Deleted
}

function script:gitAliases($filter) {
    git config --get-regexp ^alias\. | ForEach-Object{
        if($_ -match "^alias\.(?<alias>\S+) .*") {
            $alias = $Matches['alias']
            if($alias -like "$filter*") {
                $alias
            }
        }
    } | Sort-Object
}

function script:expandGitAlias($cmd, $rest) {
    if ((git config --get-regexp "^alias\.$cmd`$") -match "^alias\.$cmd (?<cmd>[^!].*)`$") {
        return "git $($Matches['cmd'])$rest"
    }
    else {
        return "git $cmd$rest"
    }
}

function GitTabExpansion($lastBlock) {
    $GitStatus = Get-GitStatus

    if ($lastBlock -match "^$(Get-AliasPattern git) (?<cmd>\S+)(?<args> .*)$") {
        $lastBlock = expandGitAlias $Matches['cmd'] $Matches['args']
    }

    # Handles tgit <command> (tortoisegit)
    if ($lastBlock -match "^$(Get-AliasPattern tgit) (?<cmd>\S*)$") {
        # Need return statement to prevent fall-through.
        return $tortoiseGitCommands | Where-Object { $_ -like "$($matches['cmd'])*" }
    }

    # Handles gitk
    if ($lastBlock -match "^$(Get-AliasPattern gitk).* (?<ref>\S*)$"){
        return gitBranches $matches['ref'] $true
    }

    switch -regex ($lastBlock -replace "^$(Get-AliasPattern git) ","") {

        # Handles git <cmd> <op>
        "^(?<cmd>$($subcommands.Keys -join '|'))\s+(?<op>\S*)$" {
            gitCmdOperations $subcommands $matches['cmd'] $matches['op']
        }


        # Handles git flow <cmd> <op>
        "^flow (?<cmd>$($gitflowsubcommands.Keys -join '|'))\s+(?<op>\S*)$" {
            gitCmdOperations $gitflowsubcommands $matches['cmd'] $matches['op']
        }

		# Handles git flow <command> <op> <name>
        "^flow (?<command>\S*)\s+(?<op>\S*)\s+(?<name>\S*)$" {
			gitFeatures $matches['name'] $matches['command']
        }

        # Handles git remote (rename|rm|set-head|set-branches|set-url|show|prune) <stash>
        "^remote.* (?:rename|rm|set-head|set-branches|set-url|show|prune).* (?<remote>\S*)$" {
            gitRemotes $matches['remote']
        }

        # Handles git stash (show|apply|drop|pop|branch) <stash>
        "^stash (?:show|apply|drop|pop|branch).* (?<stash>\S*)$" {
            gitStashes $matches['stash']
        }

        # Handles git bisect (bad|good|reset|skip) <ref>
        "^bisect (?:bad|good|reset|skip).* (?<ref>\S*)$" {
            gitBranches $matches['ref'] $true
        }

        # Handles git tfs unshelve <shelveset>
        "^tfs +unshelve.* (?<shelveset>\S*)$" {
            gitTfsShelvesets $matches['shelveset']
        }

        # Handles git branch -d|-D|-m|-M <branch name>
        # Handles git branch <branch name> <start-point>
        "^branch.* (?<branch>\S*)$" {
            gitBranches $matches['branch']
        }

        # Handles git <cmd> (commands & aliases)
        "^(?<cmd>\S*)$" {
            gitCommands $matches['cmd'] $TRUE
        }

        # Handles git help <cmd> (commands only)
        "^help (?<cmd>\S*)$" {
            gitCommands $matches['cmd'] $FALSE
        }

        # Handles git push remote <ref>:<branch>
        "^push.* (?<remote>\S+) (?<ref>[^\s\:]*\:)(?<branch>\S*)$" {
            gitRemoteBranches $matches['remote'] $matches['ref'] $matches['branch']
        }

        # Handles git push remote <ref>
        # Handles git pull remote <ref>
        "^(?:push|pull).* (?:\S+) (?<ref>[^\s\:]*)$" {
            gitBranches $matches['ref']
            gitTags $matches['ref']
        }

        # Handles git pull <remote>
        # Handles git push <remote>
        # Handles git fetch <remote>
        "^(?:push|pull|fetch).* (?<remote>\S*)$" {
            gitRemotes $matches['remote']
        }

        # Handles git reset HEAD <path>
        # Handles git reset HEAD -- <path>
        "^reset.* HEAD(?:\s+--)? (?<path>\S*)$" {
            gitIndex $matches['path']
        }

        # Handles git <cmd> <ref>
        "^commit.*-C\s+(?<ref>\S*)$" {
            gitBranches $matches['ref'] $true
        }

        # Handles git add <path>
        "^add.* (?<files>\S*)$" {
            gitAddFiles $matches['files']
        }

        # Handles git checkout -- <path>
        "^checkout.* -- (?<files>\S*)$" {
            gitCheckoutFiles $matches['files']
        }

        # Handles git rm <path>
        "^rm.* (?<index>\S*)$" {
            gitDeleted $matches['index']
        }

        # Handles git diff/difftool <path>
        "^(?:diff|difftool)(?:.* (?<staged>(?:--cached|--staged))|.*) (?<files>\S*)$" {
            gitDiffFiles $matches['files'] $matches['staged']
        }

        # Handles git merge/mergetool <path>
        "^(?:merge|mergetool).* (?<files>\S*)$" {
            gitMergeFiles $matches['files']
        }

        # Handles git <cmd> <ref>
        "^(?:checkout|cherry|cherry-pick|diff|difftool|log|merge|rebase|reflog\s+show|reset|revert|show).* (?<ref>\S*)$" {
            gitBranches $matches['ref'] $true
            gitTags $matches['ref']
        }
    }
}

$PowerTab_RegisterTabExpansion = if (Get-Module -Name powertab) { Get-Command Register-TabExpansion -Module powertab -ErrorAction SilentlyContinue }
if ($PowerTab_RegisterTabExpansion) {
    & $PowerTab_RegisterTabExpansion "git.exe" -Type Command {
        param($Context, [ref]$TabExpansionHasOutput, [ref]$QuoteSpaces)  # 1:

        $line = $Context.Line
        $lastBlock = [regex]::Split($line, '[|;]')[-1].TrimStart()
        $TabExpansionHasOutput.Value = $true
        GitTabExpansion $lastBlock
    }
    return
}

if (Test-Path Function:\TabExpansion) {
    Rename-Item Function:\TabExpansion TabExpansionBackup
}

function TabExpansion($line, $lastWord) {
    $lastBlock = [regex]::Split($line, '[|;]')[-1].TrimStart()

    switch -regex ($lastBlock) {
        # Execute git tab completion for all git-related commands
        "^$(Get-AliasPattern git) (.*)" { GitTabExpansion $lastBlock }
        "^$(Get-AliasPattern tgit) (.*)" { GitTabExpansion $lastBlock }
        "^$(Get-AliasPattern gitk) (.*)" { GitTabExpansion $lastBlock }

        # Fall back on existing tab expansion
        default { if (Test-Path Function:\TabExpansionBackup) { TabExpansionBackup $line $lastWord } }
    }
}
