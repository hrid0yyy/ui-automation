<#
.SYNOPSIS
  The only way to run test cases. Checks the app version, applies settings, runs the
  script step by step, resets settings, and writes results\<date>\<test_id>\<time>\result.json.

  Paired tests: a Windows workflow with `pairedWith: <android flow>` runs on both devices.
  run.ps1 applies the settings of both scripts, opens the phone flow's launchIntent, starts the
  phone flow in the background, runs the PC workflow, waits for both, then (if the workflow has
  `fixture:`) checks that the file arrived on the phone with the same content and deletes it.

.EXAMPLE
  tools\run.ps1 -Test android\flows\quick-share\TC-101-main-screen.yaml
  tools\run.ps1 -Test windows\workflows\quick-share\WTC-101-home-screen.yml -Repeat 2
  tools\run.ps1 -Test windows\workflows\quick-share\WTC-103-send-to-phone.yml   # paired PC + phone
  tools\run.ps1 -Test android\flows\quick-share -Serial <adb serial>   # every TC-* in a folder
  tools\run.ps1 -VersionOnly -App quick-share
#>
param(
    [string]$Test,
    [string]$Serial,
    [string]$App,
    [int]$Repeat = 1,
    [switch]$VersionOnly,
    [switch]$IgnoreVersion
)

. "$PSScriptRoot\common.ps1"
$py = Get-ToolPath 'python'
if (-not (Test-Path $py)) { throw 'Python venv missing. Run setup\setup.ps1 first.' }
$env:PYTHONIOENCODING = 'utf-8'
$Apps = Get-Content (Join-Path $RepoRoot 'apps.json') -Raw | ConvertFrom-Json
$devicesFile = Join-Path $RepoRoot 'devices.json'
$Devices = if (Test-Path $devicesFile) { Get-Content $devicesFile -Raw | ConvertFrom-Json } else { $null }

function Invoke-Py([string[]]$PyArgs) {
    $out = & $py @PyArgs
    if ($LASTEXITCODE -ne 0) { throw "python $($PyArgs -join ' ') failed" }
    return ($out -join "`n") | ConvertFrom-Json
}

function Get-AppVersion([string]$AppName, [string]$Platform, [string]$Ser) {
    $entry = $Apps.$AppName
    if (-not $entry) { throw "App '$AppName' is not in apps.json" }
    if ($Platform -eq 'android') {
        $pkg = $entry.android.package
        $d = Invoke-Adb $Ser @('shell', 'dumpsys', 'package', $pkg)
        $m = [regex]::Match($d, 'versionName=([^\r\n]+)')
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
        return ''
    }
    $p = Get-AppxPackage -Name $entry.windows.appx -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { return "$($p.Version)" }
    return ''
}

# Name other devices see in Quick Share: devices.json first, else Settings > Global > device_name.
function Get-PhoneShareName([string]$Ser) {
    if ($Devices -and $Devices.$Ser -and $Devices.$Ser.quickShareName) { return $Devices.$Ser.quickShareName }
    return (Invoke-Adb $Ser @('shell', 'settings', 'get', 'global', 'device_name')).Trim()
}

# --- -VersionOnly -------------------------------------------------------------
if ($VersionOnly) {
    $names = if ($App) { @($App) } else { @($Apps.PSObject.Properties.Name) }
    foreach ($n in $names) {
        if ($Apps.$n.windows) { Write-Output ("{0} windows: {1}" -f $n, (Get-AppVersion $n 'windows' '')) }
        if ($Apps.$n.android) {
            try { $s = Resolve-Serial $Serial; Write-Output ("{0} android ({1}): {2}" -f $n, $s, (Get-AppVersion $n 'android' $s)) }
            catch { Write-Output ("{0} android: {1}" -f $n, $_.Exception.Message) }
        }
    }
    return
}
if (-not $Test) { throw 'Pass -Test <file or folder> or -VersionOnly.' }

# --- settings -----------------------------------------------------------------
function Invoke-Setting([string]$Platform, [string]$Spec, [string]$Action, [string]$Value, [string]$Ser) {
    $name = $Spec.Split(':')[0]
    $script = Join-Path $RepoRoot "$Platform\settings\$name.ps1"
    if (-not (Test-Path $script)) { throw "No settings script: $Platform\settings\$name.ps1" }
    $a = @{ Action = $Action }
    if ($Value) { $a.Value = $Value }
    if ($Platform -eq 'android') { $a.Serial = $Ser }
    $out = & $script @a
    return (($out | ForEach-Object { "$_" }) -join "`n").Trim()
}

function Get-MaestroArgs([string]$Flow, [string]$Dir, [string]$Ser, $Device) {
    return @('--device', $Ser, 'test', '--no-reinstall-driver', $Flow, '--test-output-dir', $Dir,
             '--debug-output', (Join-Path $Dir 'maestro-debug'), '--format', 'junit', '--output', (Join-Path $Dir 'junit.xml'),
             '-e', "BRAND=$($Device.brand)", '-e', "SERIAL=$Ser")
}

function Get-MaestroFailure([string]$Dir, [int]$Code) {
    $why = Get-Content (Join-Path $Dir 'maestro-console.txt') -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'Failure \[|Exception:|Error:' -and $_ -notmatch '^\s+at ' } | Select-Object -First 1
    if (-not $why) { $why = "maestro exited with code $Code" }
    if ($why -match 'INSTALL_FAILED_USER_RESTRICTED') {
        $why += ' -- tap Install on the phone (Xiaomi "Install via USB" prompt); see guides/system/android'
    }
    return "$($why.Trim()) (see maestro-console.txt)"
}

function Invoke-OneTest([string]$File) {
    $meta = Invoke-Py @("$PSScriptRoot\testmeta.py", 'meta', $File)
    $platform = $meta.platform
    $id = if ($meta.testCaseId) { $meta.testCaseId } else { [IO.Path]::GetFileNameWithoutExtension($File) }

    # Paired script (the other device's half of the test)
    $pair = $null
    if ($meta.pairedWith) {
        if ($platform -ne 'windows') { throw "$id - put pairedWith on the Windows workflow, not on the Android flow" }
        $pairPath = [IO.Path]::GetFullPath((Join-Path (Split-Path $File -Parent) $meta.pairedWith))
        if (-not (Test-Path $pairPath)) { throw "$id - pairedWith file not found: $pairPath" }
        $pair = Invoke-Py @("$PSScriptRoot\testmeta.py", 'meta', $pairPath)
        if ($pair.platform -ne 'android') { throw "$id - pairedWith must point to an Android flow" }
        $pair | Add-Member -NotePropertyName path -NotePropertyValue $pairPath
    }
    $androidMeta = if ($platform -eq 'android') { $meta } elseif ($pair) { $pair } else { $null }

    $ser = ''
    $device = $null
    if ($androidMeta) {
        $ser = Resolve-Serial $Serial
        $device = Get-AndroidProfile $ser
    }
    $started = Get-Date
    $outDir = Join-Path $RepoRoot ("results\{0}\{1}\{2}" -f $started.ToString('yyyy-MM-dd'), $id, $started.ToString('HHmmss'))
    New-Item -ItemType Directory -Force $outDir | Out-Null

    $appVersion = Get-AppVersion $meta.app $platform $ser
    $result = [ordered]@{
        test_id     = $id
        name        = $meta.name
        file        = (Resolve-Path $File).Path.Substring($RepoRoot.Length + 1)
        app         = $meta.app
        app_version = $appVersion
        platform    = $platform
        device      = $device
        pc          = Get-PcProfile
        started     = $started.ToString('yyyy-MM-ddTHH:mm:sszzz')
        result      = 'running'
        steps       = @()
    }
    $pairVersion = ''
    if ($pair) {
        $pairVersion = Get-AppVersion $pair.app 'android' $ser
        $result.platform = 'windows+android'
        $result.paired = [ordered]@{
            test_id = $pair.testCaseId; file = $pair.path.Substring($RepoRoot.Length + 1)
            app = $pair.app; app_version = $pairVersion
        }
    }
    $steps = New-Object System.Collections.ArrayList
    $script:n = 0
    function Add-Step($name, $status, $ms, $err) {
        $script:n++
        $s = [ordered]@{ n = $script:n; name = $name; status = $status; duration_ms = [int]$ms }
        if ($err) { $s.error = $err }
        [void]$steps.Add($s)
        Write-Host ("[{0}] {1} {2}{3}" -f $status.ToUpper(), $script:n, $name, $(if ($err) { " - $err" } else { '' }))
    }
    function Add-Steps($list, [string]$Prefix) {
        foreach ($s in @($list)) {
            if ($null -eq $s) { continue }
            $script:n++
            $s.n = $script:n
            if ($Prefix) { $s.name = $Prefix + $s.name }
            [void]$steps.Add($s)
        }
    }

    $label = if ($pair) { "$($meta.app) $appVersion + $($pair.testCaseId) on phone ($pairVersion)" } else { "$($meta.app) $appVersion" }
    Write-Host "=== $id ($($result.platform)) $($meta.name) | $label"

    # Version gate (both halves of a paired test)
    $inRange = Invoke-Py @("$PSScriptRoot\testmeta.py", 'in-range', $appVersion, $meta.minVersion, $meta.maxVersion)
    if (-not $appVersion) {
        $result.result = 'skipped'; $result.reason = "App $($meta.app) not installed"
    } elseif (-not $inRange -and -not $IgnoreVersion) {
        $result.result = 'skipped'; $result.reason = "Version $appVersion outside $($meta.minVersion)-$($meta.maxVersion)"
    } elseif ($pair) {
        $pairIn = Invoke-Py @("$PSScriptRoot\testmeta.py", 'in-range', $pairVersion, $pair.minVersion, $pair.maxVersion)
        if (-not $pairVersion) {
            $result.result = 'skipped'; $result.reason = "App $($pair.app) not installed on the phone"
        } elseif (-not $pairIn -and -not $IgnoreVersion) {
            $result.result = 'skipped'; $result.reason = "Phone version $pairVersion outside $($pair.minVersion)-$($pair.maxVersion)"
        }
    }
    if ($result.result -eq 'skipped') {
        Write-Host "SKIPPED: $($result.reason)"
        $result.steps = @()
        Write-JsonFile (Join-Path $outDir 'result.json') $result
        return $result
    }

    # Apply settings (own, then the paired script's), remembering previous values
    $specs = @()
    foreach ($s in $meta.settings) { $specs += , @($platform, $s) }
    if ($pair) { foreach ($s in $pair.settings) { $specs += , @('android', $s) } }
    $restore = @()
    $failed = $false
    foreach ($ps in $specs) {
        $plat, $spec = $ps
        $name, $value = $spec.Split(':', 2)
        $who = if ($pair) { if ($plat -eq 'android') { 'phone ' } else { 'pc ' } } else { '' }
        $t0 = Get-Date
        try {
            $prev = Invoke-Setting $plat $spec 'get' '' $ser
            Invoke-Setting $plat $spec 'set' $value $ser | Out-Null
            $restore += , @($plat, $spec, $prev)
            Add-Step "${who}setting $name=$value (was $prev)" 'passed' ((Get-Date) - $t0).TotalMilliseconds $null
        } catch {
            Add-Step "${who}setting $name=$value" 'failed' ((Get-Date) - $t0).TotalMilliseconds $_.Exception.Message
            $failed = $true
            break
        }
    }

    # Paired transfer: work out the file to send and where it will land; remove any old copy first
    $fixture = $null; $remote = $null
    if (-not $failed -and $pair -and $meta.fixture) {
        $fixture = [IO.Path]::GetFullPath((Join-Path $RepoRoot $meta.fixture))
        if (-not (Test-Path $fixture)) { throw "$id - fixture not found: $fixture" }
        $recvDir = $Apps.($pair.app).android.receiveDir
        if (-not $recvDir) { throw "apps.json: $($pair.app).android.receiveDir is not set" }
        $remote = "$recvDir/" + [IO.Path]::GetFileName($fixture)
        $null = Invoke-Adb $ser @('shell', "rm -f '$remote'")
    }

    # Android: open the screen by intent when the app has no launcher (e.g. Quick Share inside GMS).
    # NEW_TASK|CLEAR_TASK so every run starts on a fresh screen.
    if (-not $failed -and $androidMeta -and $androidMeta.launchIntent) {
        $t0 = Get-Date
        $who = if ($pair) { 'phone ' } else { '' }
        $o = Invoke-Adb $ser @('shell', "am start -W -f 0x10008000 $($androidMeta.launchIntent)")
        if ($o -match 'Error|Exception') {
            Add-Step "${who}launchIntent $($androidMeta.launchIntent)" 'failed' ((Get-Date) - $t0).TotalMilliseconds $(($o -split "`n" | Select-Object -First 2) -join ' ')
            $failed = $true
        } else {
            Add-Step "${who}launchIntent $($androidMeta.launchIntent)" 'passed' ((Get-Date) - $t0).TotalMilliseconds $null
        }
    }

    # Run the script(s)
    if (-not $failed) {
        if ($platform -eq 'android') {
            Use-PinnedJava
            $maestro = Get-ToolPath 'maestro'
            $mArgs = Get-MaestroArgs $File $outDir $ser $device
            $ErrorActionPreference = 'Continue'
            & $maestro @mArgs 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath (Join-Path $outDir 'maestro-console.txt') | Out-Host
            $code = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            Add-Steps (Invoke-Py @("$PSScriptRoot\testmeta.py", 'maestro-steps', $outDir)) ''
            # Attach the failing step's screenshot if Maestro saved one
            $bad = @($steps | Where-Object { $_.status -eq 'failed' } | Select-Object -First 1)
            if ($bad) {
                $png = Get-ChildItem $outDir -Recurse -Filter '*.png' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
                if ($png) { $bad[0] | Add-Member -NotePropertyName screenshot -NotePropertyValue $png.FullName.Substring($outDir.Length + 1) -Force }
            }
            if ($code -ne 0) {
                $failed = $true
                if (-not ($steps | Where-Object { $_.status -eq 'failed' })) { Add-Step 'maestro test' 'failed' 0 (Get-MaestroFailure $outDir $code) }
            }
        } else {
            # Paired: start the phone flow in the background first; it waits for the PC to act.
            $proc = $null
            $phoneDir = Join-Path $outDir 'phone'
            if ($pair) {
                New-Item -ItemType Directory -Force $phoneDir | Out-Null
                Use-PinnedJava
                $mArgs = Get-MaestroArgs $pair.path $phoneDir $ser $device
                $argLine = ($mArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
                $proc = Start-Process -FilePath (Get-ToolPath 'maestro') -ArgumentList $argLine -NoNewWindow -PassThru `
                    -RedirectStandardOutput (Join-Path $phoneDir 'maestro-console.txt') `
                    -RedirectStandardError (Join-Path $phoneDir 'maestro-stderr.txt')
                $null = $proc.Handle   # keeps ExitCode readable after exit
                Write-Host "phone: started $($pair.testCaseId) in the background (pid $($proc.Id))"
            }

            $wArgs = @("$PSScriptRoot\winrunner.py", $File, '--out', $outDir)
            if ($pair) {
                $wArgs += @('--env', "SERIAL=$ser", '--env', "PHONE_NAME=$(Get-PhoneShareName $ser)")
                if ($fixture) { $wArgs += @('--env', "FIXTURE=$fixture") }
            }
            $ErrorActionPreference = 'Continue'
            & $py @wArgs 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath (Join-Path $outDir 'runner-console.txt') | Out-Host
            $code = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            $sj = Join-Path $outDir 'steps.json'
            $pcPrefix = if ($pair) { 'pc: ' } else { '' }
            if (Test-Path $sj) { Add-Steps (Get-Content $sj -Raw | ConvertFrom-Json).steps $pcPrefix }
            if ($code -ne 0) {
                $failed = $true
                if (-not ($steps | Where-Object { $_.status -eq 'failed' })) {
                    Add-Step "${pcPrefix}winrunner" 'failed' 0 "runner exited with code $code (see runner-console.txt)"
                }
            }

            if ($pair) {
                # Wait for the phone flow (it has its own timeouts; 3 minutes is the hard stop)
                if (-not $proc.WaitForExit(180000)) {
                    & taskkill /PID $proc.Id /T /F 2>&1 | Out-Null
                    Add-Step "phone: $($pair.testCaseId)" 'failed' 180000 'phone flow did not finish within 180 s (killed)'
                    $failed = $true
                } else {
                    $pcode = $proc.ExitCode
                    Get-Content (Join-Path $phoneDir 'maestro-console.txt') -ErrorAction SilentlyContinue | ForEach-Object { "phone> $_" } | Out-Host
                    $before = $steps.Count
                    Add-Steps (Invoke-Py @("$PSScriptRoot\testmeta.py", 'maestro-steps', $phoneDir)) 'phone: '
                    $phoneFailed = @($steps | Select-Object -Skip $before | Where-Object { $_.status -eq 'failed' })
                    if ($phoneFailed) {
                        $png = Get-ChildItem $phoneDir -Recurse -Filter '*.png' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
                        if ($png) { $phoneFailed[0] | Add-Member -NotePropertyName screenshot -NotePropertyValue $png.FullName.Substring($outDir.Length + 1) -Force }
                    }
                    if ($pcode -ne 0) {
                        $failed = $true
                        if (-not $phoneFailed) { Add-Step "phone: maestro test" 'failed' 0 (Get-MaestroFailure $phoneDir $pcode) }
                    }
                }

                # The file must be on the phone with the same content (line endings ignored)
                if ($remote) {
                    $t0 = Get-Date
                    $got = Invoke-Adb $ser @('shell', "cat '$remote'")
                    $want = [IO.File]::ReadAllText($fixture)
                    $norm = { param($x) ($x -replace "`r", '').TrimEnd("`n") }
                    $ms = ((Get-Date) - $t0).TotalMilliseconds
                    if ($got -match 'No such file') {
                        Add-Step "phone: received file $remote" 'failed' $ms 'file not found on the phone'
                        $failed = $true
                    } elseif ((& $norm $got) -ne (& $norm $want)) {
                        Add-Step "phone: received file $remote" 'failed' $ms 'content differs from the fixture'
                        $failed = $true
                    } else {
                        Add-Step "phone: received file $remote matches fixture" 'passed' $ms $null
                    }
                    $t0 = Get-Date
                    $null = Invoke-Adb $ser @('shell', "rm -f '$remote'")
                    Add-Step "phone: delete $remote" 'passed' ((Get-Date) - $t0).TotalMilliseconds $null
                }
            }
        }
    }

    # Reset settings (always, newest first)
    [array]::Reverse($restore)
    foreach ($r in $restore) {
        $plat, $spec, $prev = $r
        $name = $spec.Split(':')[0]
        $who = if ($pair) { if ($plat -eq 'android') { 'phone ' } else { 'pc ' } } else { '' }
        $t0 = Get-Date
        try {
            Invoke-Setting $plat $spec 'set' $prev $ser | Out-Null
            Add-Step "${who}reset $name=$prev" 'passed' ((Get-Date) - $t0).TotalMilliseconds $null
        } catch {
            Add-Step "${who}reset $name=$prev" 'failed' ((Get-Date) - $t0).TotalMilliseconds $_.Exception.Message
        }
    }

    $result.result = if ($failed) { 'failed' } else { 'passed' }
    $result.duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    $result.steps = @($steps)
    Write-JsonFile (Join-Path $outDir 'result.json') $result
    Write-Host ("=== {0}: {1}  ->  {2}" -f $id, $result.result.ToUpper(), (Join-Path $outDir 'result.json'))
    return $result
}

# --- main ---------------------------------------------------------------------
$files = if (Test-Path $Test -PathType Container) {
    $all = @(Get-ChildItem $Test -Recurse -Include 'TC-*.yaml', 'TC-*.yml', 'WTC-*.yml' | Sort-Object FullName | ForEach-Object { $_.FullName })
    # Receiver halves of paired tests run through their Windows workflow, not on their own
    @($all | Where-Object {
        $m = Invoke-Py @("$PSScriptRoot\testmeta.py", 'meta', $_)
        if ($m.pairedFrom) { Write-Host "skip $([IO.Path]::GetFileName($_)): runs via $($m.pairedFrom)"; $false } else { $true }
    })
} else { @((Resolve-Path $Test).Path) }

$summary = @()
foreach ($f in $files) {
    $streak = 0
    for ($i = 1; $i -le $Repeat; $i++) {
        if ($Repeat -gt 1) { Write-Host "--- run $i of $Repeat" }
        $r = Invoke-OneTest $f
        $summary += [pscustomobject]@{ test = $r.test_id; run = $i; result = $r.result }
        if ($r.result -eq 'passed') { $streak++ } else { break }
    }
}
Write-Host ''
$summary | Format-Table -AutoSize | Out-Host
if ($summary | Where-Object { $_.result -eq 'failed' }) { exit 1 }
exit 0
