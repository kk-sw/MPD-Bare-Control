# 0024
# -----------------------------------
#
# MPD BareControl (PS)
#
# -----------------------------------
# Dev: KK ; 2026 march
# -----------------------------------
# Bugs:
# - Elapsed play-time is estimated
# - Optimize: Code Cleanup
# - Optimize: Clear-Host calls
# - Optimize: Info Dialog
# - Optimize: Debug Dialog
#
# -----------------------------------

#
# Keyboard polling Config
#
$WaitWithKeyCheckSleepMs = 500

#
# MPD Host Config
#
$MPDHost = "CHANGE_ME"
$MPDPort = 6600

#
# Color Config  #DEF_COLOR
#
$ColorDashBack          = "Black"
$ColorHeaderBack        = "DarkBlue"
$ColorStatusBack        = "DarkGreen"
$ColorStatusFore        = "White"
$ColorPlaylistFore      = "DarkCyan"
$ColorNowPlaying        = "DarkGreen"

#
# Info Panel
#
$ShowInfoPanel = $false;

#
# Log Config
#
$ShowLog = $false;

# Global index to track sequence position
$Global:ColorIndex = 0


class StringQueue {
    [int]   $MaxSize = 20
    [System.Collections.ArrayList] $Items

    StringQueue() {
        $this.Items = [System.Collections.ArrayList]::new()
    }

    [void] Add([string]$value) {

        if ([string]::IsNullOrWhiteSpace($value) -or
            ($this.Items -contains $value)
        ) {
            return
        }
        
        # Drop oldest if full
        if ($this.Items.Count -ge $this.MaxSize) {
            $this.Items.RemoveAt(0)
        }

        # Add new item
        $null = $this.Items.Add($value)
    }

    [void] Delete([string]$value) {
        $this.Items.Remove($value) | Out-Null
    }

    [string[]] GetAll() {
        return $this.Items.ToArray()
    }
}


function Quote-MPD($text) {
    return '"' + $text.Replace('"', '\"') + '"'
}

function Write-Info($text) {
    Write-Host "  $text  "    -ForegroundColor White  -BackgroundColor Blue
}

function Write-Error($text) {
    $len = $text.Length + 10
    Write-Block $len  DarkRed
    Write-Text "  $text  "  Yellow Red $len
    Write-Block $len  DarkRed
}

function Write-Text($text, $foreColor, $backColor, $width) {
    $t = $text.PadRight($width)
    Write-Host $t    -ForegroundColor $foreColor  -BackgroundColor $backColor
}

function Write-Block {
    param(
        [int]$Width,
        [ConsoleColor]$ColorBack
    )

    $text = " ".PadRight($Width)
    Write-Host $text -BackgroundColor $ColorBack
}

function Get-NextColor {
    $colors = @(
        "DarkGray","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow",
        "Gray","Blue",         "Green",     "Cyan",     "Red",  "Magenta",   "Yellow","White", "Black"
    )

    $color = $colors[$Global:ColorIndex]

    # Move to next index (wrap around)
    $Global:ColorIndex = ($Global:ColorIndex + 1) % $colors.Count
    Write-Info "Using color: $color"
    return $color
}

function Format-Time($sec) {
    if ($sec -le 0) { return "00:00" }
    $m = [int]($sec / 60)
    $s = $sec % 60
    return ("{0:D2}:{1:D2}" -f $m, $s)
}

function Wait-WithKeyCheck {
    param( [int]$CycleCount = 10 )

    $elapsed = 0
    while ($elapsed -lt $CycleCount) {

        if ([Console]::KeyAvailable) {
            break
        }

        Start-Sleep -Milliseconds $WaitWithKeyCheckSleepMs
        $elapsed++
    } # while

}

function Send-MPDCommand {
    param([string]$Command)

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($MPDHost , $MPDPort)

        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)

        # Read MPD banner
        $null = $reader.ReadLine()

        # Send command
        $writer.WriteLine($Command)
        $writer.Flush()

        # Collect response
        $response  = @()
        while (($line = $reader.ReadLine()) -ne $null) {
            if ($line -eq "OK") { break }
            $response  += $line
        }

        $writer.Close()
        $reader.Close()
        $client.Close()

        if ($ShowLog) {
            Write-Host " Request  : "       -ForegroundColor DarkGreen  -NoNewline
            Write-Host "$Command"           -ForegroundColor DarkYellow
            Write-Host " Response : "       -ForegroundColor DarkGreen  -NoNewline
            Write-Host "$response `n"      -ForegroundColor DarkYellow
        }

        return $response
    }
    catch {
        Write-Error "ERROR: Cannot reach MPD server at $MPDHost`:$MPDPort"
        return "";
    }

}

function Show-History {
    param([string[]] $List)
    Clear-Host
    Write-Host "                    Last songs played                    `n"     -ForegroundColor Gray -BackgroundColor $ColorHeaderBack
    Write-Host "Oldest -> Newest`n"

    for ($i = 0; $i -lt $List.Count; $i++) {
        $color = if ($i % 2 -eq 0) { 
            $ColorPlaylistFore 
        } else { 
            $ColorStatusFore 
        }
        Write-Host (" $($i+1): $($List[$i])") -ForegroundColor $color
    }    
    
    Write-Host "`n(press any key to return)`n"
    [Console]::ReadKey($true) | Out-Null
    Clear-Host
}

function Show-MpdServerInfo {
    Clear-Host
    Write-Host "               MPD Server Info              `n"         -ForegroundColor Gray -BackgroundColor $ColorHeaderBack

    # Get MPD status and stats
    $stats  = Send-MPDCommand "stats"
    $outputs  = Send-MPDCommand "outputs"

    # Extract stats
    $uptimeSec     = (($stats | Where-Object { $_ -like "uptime:*" })     -replace "uptime:", "").Trim()
    $songs         = (($stats | Where-Object { $_ -like "songs:*" })      -replace "songs:", "").Trim()
    $artists       = (($stats | Where-Object { $_ -like "artists:*" })    -replace "artists:", "").Trim()
    $albums        = (($stats | Where-Object { $_ -like "albums:*" })     -replace "albums:", "").Trim()
    $dbPlaytimeSec = (($stats | Where-Object { $_ -like "db_playtime:*" }) -replace "db_playtime:", "").Trim()
    $dbUpdate      = (($stats | Where-Object { $_ -like "db_update:*" })   -replace "db_update:", "").Trim()

    # Convert uptime to H:M:S
    $uptimeTS = [TimeSpan]::FromSeconds([int]$uptimeSec)
    $uptimeFmt = "{0}h {1}m {2}s" -f $uptimeTS.Hours, $uptimeTS.Minutes, $uptimeTS.Seconds

    # Convert DB playtime
    $dbTS = [TimeSpan]::FromSeconds([int]$dbPlaytimeSec)
    $dbFmt = "{0}d {1}h {2}m" -f  $dbTS.Days, $dbTS.Hours, $dbTS.Minutes

    Write-Host " Host        : $MPDHost"     -ForegroundColor DarkCyan
    Write-Host " Port        : $MPDPort"     -ForegroundColor DarkCyan
    Write-Host " Uptime      : $uptimeFmt"   -ForegroundColor DarkCyan

    Write-Host "`n                  Database                  `n" -ForegroundColor Gray -BackgroundColor DarkYellow
    Write-Host " Artists     : $artists"      -ForegroundColor DarkYellow
    Write-Host " Albums      : $albums"       -ForegroundColor DarkYellow
    Write-Host " Songs       : $songs"        -ForegroundColor DarkYellow
    Write-Host " Playtime    : $dbFmt"        -ForegroundColor DarkYellow


    $tmp = [DateTimeOffset]::FromUnixTimeSeconds($dbUpdate).ToLocalTime()
    $tmp = $tmp.ToString('yyyy MMM dd  -  HH:mm')
    Write-Host " Last Update : $tmp"                            -ForegroundColor DarkYellow

    Write-Host "`n                  Outputs                   `n" -ForegroundColor Gray -BackgroundColor DarkGreen

    foreach ($line in $outputs) {
        if ($line -like "outputid:*") {
            $tmp = $line.Substring(9).Trim()
            Write-Host "`n Output ID   : $tmp"        -ForegroundColor DarkGreen
        }
        if ($line -like "outputname:*") {
            $tmp = $line.Substring(11).Trim()
            Write-Host " Output Name : $tmp"        -ForegroundColor DarkGreen
        }

        if ($line -like "plugin:*") {
            $tmp = $line.Substring(7).Trim()
            Write-Host " Plugin      : $tmp"        -ForegroundColor DarkGreen
        }

        if ($line -like "outputenabled:*") {
            $tmp = $line.Substring(14).Trim()
            $enab= "No"
            if ($tmp -eq "1") { $enab= "Yes" }
            Write-Host " Enabled     : $enab"        -ForegroundColor DarkGreen
        }

        if ($line -like "Album:*")          { $album        = $line.Substring(6).Trim() }
        if ($line -like "AlbumArtist:*")    { $albumArtist  = $line.Substring(12).Trim() }
        if ($line -like "date:*")           { $albumDate    = $line.Substring(6).Trim() }
        if ($line -like "Title:*")          { $trackTitle   = $line.Substring(6).Trim() }
        if ($line -like "Genre:*")          { $trackGenre   = $line.Substring(6).Trim() }
        if ($line -like "file:*")           { $trackFile    =   $line.Substring(6).Trim() }
    }


    Write-Host "`n(press any key to return)`n"
    [Console]::ReadKey($true) | Out-Null
    Clear-Host
}

function Show-NoPlaylist{
    Write-Host "                                        "                           -BackgroundColor Red
    Write-Host "   >>  No playlist is being played <<   "  -ForegroundColor Yellow  -BackgroundColor DarkRed
    Write-Host "                                        "                           -BackgroundColor Red
}

function Show-PlaylistHeader {
    param(
        [string]$PlaylistName,
        [int]$SongCount
    )

    Clear-Host
    Write-Host "     Playlist Content  -  "   -NoNewline -ForegroundColor Gray          -BackgroundColor DarkBlue
    Write-Host " $PlaylistName  "             -NoNewline -ForegroundColor DarkYellow    -BackgroundColor DarkBlue
    Write-Host " ($SongCount songs)    `n"               -ForegroundColor Yellow        -BackgroundColor DarkBlue

}

function Get-Playlists {
    $resp = Send-MPDCommand "listplaylists"
    $list = @()

    foreach ($line in $resp) {
        if ($line -like "playlist:*") {
            $list += $line.Substring(9).Trim()
        }
    }

    return $list
}

function Show-PlaylistContent($playlistName) {
    Clear-Host
    Write-Info "Fetching playlist data: $playlistName"

    $quoted = Quote-MPD $playlistName
    $resp = Send-MPDCommand "listplaylistinfo $quoted"

    if ($resp.Count -eq 0) {
        Write-Info "Playlist is empty"
        return;
    }
    $songCount = ($resp | Where-Object { $_ -like "file:*" }).Count

    Show-PlaylistHeader $playlistName $songCount

    $buffer = @()
    foreach ($line in $resp) {
        if ($line -like "file:*" -and $line -notmatch "Title:") {
            $buffer += (" > " + $line.Substring(5).Trim())
        } elseif ($line -like "Title:*") {
            $buffer += ("   | " + $line.Substring(6).Trim())
        }
    } # for

    # Output in chunks of 20
    $chunkSize = 20
    $preCnt = 0;
    $cnt = 0;
    for ($i = 0; $i -lt $buffer.Count; $i += $chunkSize) {
        $chunk = $buffer[$i..([Math]::Min($i + $chunkSize - 1, $buffer.Count - 1))]

        foreach ($entry in $chunk) {
            Write-Host $entry
        }

        if ($i + $chunkSize -lt $buffer.Count) {
            $preCnt = $cnt
            $cnt = ($i + $chunkSize)/2
            Write-Host "`n          SPACE to continue; Q to return ($preCnt-$cnt)                  " -ForegroundColor Yellow -BackgroundColor DarkBlue
            $keyChar = [Console]::ReadKey($true).KeyChar.ToString().ToLower()
            Show-PlaylistHeader $playlistName $songCount
            if ($keyChar -eq "q") {
                Clear-Host
                return;
            }

        }
    } # for

    Write-Host "`n                     ==>> End of playlist <<==                     " -ForegroundColor Yellow -BackgroundColor DarkBlue
    $keyChar = [Console]::ReadKey($true).KeyChar.ToString().ToLower()
    Clear-Host
}

function Show-PlaylistsMenu {
    Clear-Host
    Write-Host "             Available Playlists             `n" -ForegroundColor Gray -BackgroundColor DarkBlue

    $resp = Send-MPDCommand "listplaylists"
    $playlists = @()

    foreach ($line in $resp) {
        if ($line -like "playlist:*") {
            $playlists += $line.Substring(9).Trim()
        }
    }

    if ($playlists.Count -eq 0) {
            Write-Host "`n                                " -ForegroundColor Black -BackgroundColor  DarkYellow
            Write-Host "    >> No playlists found   <<    " -ForegroundColor Black -BackgroundColor Yellow
            Write-Host "                                  " -ForegroundColor Black -BackgroundColor DarkYellow
            [Console]::ReadKey($true) | Out-Null
            Clear-Host
            return
    }

    # Display numbered list
    $i = 1
    foreach ($p in $playlists) {
        #$count = Get-PlaylistCount $p
        #Write-Host (" $i. $p ($count)")
        Write-Host (" $i. $p")
        $i++
    }

    Write-Host "`nEnter number to load playlist, or +number to view playlist contents or ENTER to return`n" -ForegroundColor DarkYellow
    $choice = Read-Host "A"

    # Check for `+` prefix
    if ($choice.StartsWith("+")) {
        $num = $choice.Substring(1)
        if ($num -as [int]) {
            $index = [int]$num - 1
            if ($index -ge 0 -and $index -lt $playlists.Count) {
                Show-PlaylistContent $playlists[$index]
            }
        }
        return
    }

    if (-not ($choice -as [int])) {
        Clear-Host
        return
    }

    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $playlists.Count) {
        return
    }

    # load playlist
    $selected = Quote-MPD $playlists[$index]
#    $quoted = Quote-MPD $selected

    # Load playlist
    Send-MPDCommand "clear"
    Send-MPDCommand "load $selected"
    Send-MPDCommand "play"

    Clear-Host
}

function Test-MPDConnection {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($MPDHost, $MPDPort, $null, $null)

        # Wait up
        $success = $async.AsyncWaitHandle.WaitOne(600)

        if (-not $success) {
            $client.Close()
            return $false
        }

        $client.EndConnect($async)
        $client.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Run-Dashboard {
    $history = [StringQueue]::new()

    while ($true) {

        # Handle key-press without blocking
       if ([Console]::KeyAvailable) {
            $keyChar = [Console]::ReadKey($true).KeyChar.ToString().ToLower()

            switch ($keyChar) { #KEYS

                " " {
                        if ($playingState) {
                            Send-MPDCommand "stop"
                        } else {
                            Send-MPDCommand "play"
                        }
                    }

                "*" {
                        Send-MPDCommand "pause"  # toggle pause
                    }

                "+" {   # Vol+
                        Send-MPDCommand "volume +5"
                    }

                "-" {   # Vol-
                        Send-MPDCommand "volume -5"
                    }

                "[" {   # Mute -> volume 0
                        Send-MPDCommand "setvol 0"
                    }

                "]" {   # UnMute -> volume 95
                        Send-MPDCommand "setvol 95"
                    }

                "a" {
                        # Create playlist with all songs
                            Write-Info "Sending MPD Command: clear (playlist)"
                        Send-MPDCommand "clear"
                            Write-Info "Sending MPD Command: add / (playlist)"
                        Send-MPDCommand "add /"
                            Write-Info "Sending MPD Command: play  (playlist)"
                        Send-MPDCommand "play"
                    }

                "c" {
                        if ($consumeMode -eq "ON") {
                            Send-MPDCommand "consume 0"
                        } else {
                            Send-MPDCommand "consume 1"
                        }
                    }


                "d" {   # Log On/Off
                        $ShowLog = -not $ShowLog ;

                    }

                "f" {   # Fast-Forward
                        if ($playingState) {
                            Send-MPDCommand "seekcur +10"
                        }
                    }

                "h" {
                        Show-History $history.GetAll()
                    }

                "i" {
                        $ShowInfoPanel = -not $ShowInfoPanel
                    }


                "l" {
                        Show-PlaylistsMenu
                    }

                "n" {
                        if ($playingState) {
                            Send-MPDCommand "next"
                        } else {
                            Show-NoPlaylist
                        }
                    }

                "p" {
                        if ($playingState) {
                            Send-MPDCommand "previous"
                        } else {
                            Show-NoPlaylist
                        }
                    }


                "r" {
                        if ($randomMode -eq "ON") {
                            Send-MPDCommand "random 0"
                        } else {
                            Send-MPDCommand "random 1"
                        }
                    }

                "x" {
                        Send-MPDCommand "clear"     # clear queue
                    }

                "v" {
                        Show-MpdServerInfo
                    }

                "w" {
                        Send-MPDCommand "stop"
                        Clear-Host
                        Write-Info "Playback stopped ... "
                        return
                    }

                "q" {
                        Clear-Host;
                        return
                    }

                "1" {
                        $ColorHeaderBack = (Get-NextColor)
                    }

                "2" {
                        $ColorNowPlaying = (Get-NextColor)
                    }

                "3" {
                        $ColorPlaylistFore = (Get-NextColor)
                    }

                "4" {
                        $ColorStatusBack = (Get-NextColor)
                    }

                "5" {
                        $ColorStatusFore = (Get-NextColor)
                    }

                "6" {
                        $ColorDashBack = (Get-NextColor)
                    }


                "8" {   # Theme
                        $ColorDashBack          = "Gray"
                        $ColorHeaderBack        = "DarkGray"
                        $ColorStatusBack        = "DarkGray"
                        $ColorStatusFore        = "White"
                        $ColorPlaylistFore      = "DarkGray"
                        $ColorNowPlaying        = "Black"
                    }

                "9" {   #DEF_COLOR
                        $ColorDashBack          = "Black"
                        $ColorHeaderBack        = "DarkBlue"
                        $ColorStatusBack        = "DarkGreen"
                        $ColorStatusFore        = "White"
                        $ColorPlaylistFore      = "DarkCyan"
                        $ColorNowPlaying        = "DarkGreen"
                    }

            } # switch
        } # if

        $artist = ""
        $album = ""
        $albumArtist = ""
        $albumDate = ""
        $trackTitle = ""
        $trackGenre = ""
        $trackFile = ""

        # Fetch Data
        $currentSong = Send-MPDCommand "currentsong"
        foreach ($line in $currentSong) {
            if ($line -like "Artist:*")         { $artist       = $line.Substring(7).Trim() }
            if ($line -like "Album:*")          { $album        = $line.Substring(6).Trim() }
            if ($line -like "AlbumArtist:*")    { $albumArtist  = $line.Substring(12).Trim() }
            if ($line -like "date:*")           { $albumDate    = $line.Substring(6).Trim() }
            if ($line -like "Title:*")          { $trackTitle   = $line.Substring(6).Trim() }
            if ($line -like "Genre:*")          { $trackGenre   = $line.Substring(6).Trim() }
            if ($line -like "file:*")           { $trackFile    =   $line.Substring(6).Trim() }
        }

        $error      = ""
        $randomMode    = "<unknown>"
        $consumeMode   = "<unknown>"
        $volume        = "<unknown>"
        $volumeMuted   = $false
#        $playlistIndex = "<none>"
        $playlistLength = ""
        $playlistName = "<none>"
        $playingState = $false;
        $trackElapsed = 0
        $trackTotal = 0
        $trackBitrate = 0

        # Status + playlist
        $statusResp = Send-MPDCommand "status"
        foreach ($line in $statusResp) {

            if ($line -like "state:*") {
                $playingStateTxt = $line.Substring(6).Trim()
                if ($playingStateTxt -eq "play") {
                    $playingState    = $true
                }
            }

            if ($line -like "error:*") {
                $error = $line.Substring(6).Trim()
                Write-Error $error
            }

            if ($line -like "random:*") {
                $randomMode = if ($line.Substring(7).Trim() -eq "1") { "ON" } else { "OFF" }
            }

            if ($line -like "consume:*") {
                $consumeMode = if ($line.Substring(8).Trim() -eq "1") { "ON" } else { "OFF" }
            }

            if ($line -like "playlistlength:*") {
                $playlistLength = $line.Substring(15).Trim()
            }

            if ($line -like "volume:*") {
                $volume = $line.Substring(7).Trim()
                if ($volume -eq "0") {
                    $volumeMuted = $true
                }
            }

            if ($line -like "elapsed:*") {
                $trackElapsed = [int]([double]($line.Substring(8).Trim()))
            }

            if ($line -like "duration:*") {
                $trackTotal = [int]([double]($line.Substring(9).Trim()))
            }

            if ($line -like "bitrate:*") {
                $trackBitrate = [int]([double]($line.Substring(8).Trim()))
            }

            if ($line -match "lastloadedplaylist:") {
                $tmp = $line.Split(":",2)[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($tmp)) {
                    $playlistName = $tmp;
                }
            }

        }

        if ($playingState) {
            $elapsedStr    = Format-Time $trackElapsed
            $trackTotalStr = Format-Time $trackTotal
            $trackPlayStr  = "~$elapsedStr / $trackTotalStr"
            $playDisplay1  = "$artist - $trackTitle"
            $playDisplay2  = "$album ($albumDate)"
            $history.Add($playDisplay1)
        } else {
            $elapsedStr     = ""
            $trackTotalStr  = ""
            $trackPlayStr   = ""
            $playDisplay1   = "<nothing is played>"
            $playDisplay2   = "<nothing is played>"
            $artist         = ""
            $album          = ""
            $albumArtist    = ""
            $albumDate      = ""
            $trackTitle     = ""
            $trackGenre     = ""
            $trackFile      = ""
        }

        # Build dashboard lines
        $updateTime = (Get-Date -Format 'yyyy MMMM dd  |  HH:mm:ss')
        $lineHead   = "  MPD BareControl (PS) v.1                ($MPDHost`:$MPDPort)                       $updateTime "

        # Control KEYS  #KEYS
        $s = [char]0x2192     # right arrow
        $lineKeys1  = " SPC $s Start/Stop   | N/P/F $s Next/Prev/FFWD | * $s Pause   | +/- $s Volume  | [/] $s Mute     | A $s Play All   "
        $lineKeys2  = "  L  $s Load Playlst |   X   $s Clear Queue    | R $s Random  |  C  $s Consume |  Q  $s Quit     | W $s Stop & Quit"
        $lineKeys3  = "  I  $s Info Panel   |   H   $s History        | V $s SrvInfo | 1-6 $s Colors  | 8-9 $s Theme    | D $s Debug Log  "

        # panel size
        $width = ($lineHead.Length,  $lineKeys1.Length , $lineKeys2.Length, $lineKeys3.Length | Measure-Object -Maximum).Maximum + 1

        #
        # Header
        #
        Write-Host ("" + $lineHead.PadRight($width) + "")                           -ForegroundColor Gray -BackgroundColor $ColorHeaderBack

        #
        # Playlist
        #
        Write-Block $width $ColorDashBack
        Write-Text "   Artist/Title  : $playDisplay1"     $ColorNowPlaying    $ColorDashBack  $width
        Write-Text "   Album         : $playDisplay2"     $ColorNowPlaying    $ColorDashBack  $width
        Write-Block $width $ColorDashBack
        Write-Text "   Playlist Name : $playlistName"     $ColorPlaylistFore  $ColorDashBack  $width


        #
        # Control Keys Display
        #
        Write-Block $width $ColorDashBack
        Write-Text  $lineKeys1              Gray   $ColorHeaderBack  $width
        Write-Text  $lineKeys2              Gray   $ColorHeaderBack  $width
        Write-Text  $lineKeys3              Gray   $ColorHeaderBack  $width

        #
        # Play state
        #
        Write-Text "  Vol: $volume%              Random: $randomMode             Consume: $consumeMode                   State: $playingStateTxt    |    $trackPlayStr"  $ColorStatusFore $ColorStatusBack $width
        if ($volumeMuted) {
            Write-Info "Muted         "
        }
        if ($playingStateTxt -eq "pause") {
            Write-Info "Paused        "
        }

        #
        # Info Panel
        #
        if ($ShowInfoPanel) {
            Write-Block $width $ColorDashBack
            Write-Text "   Artist        : $artist"       $ColorNowPlaying    $ColorDashBack      $width
            Write-Text "   Album         : $album"        $ColorNowPlaying    $ColorDashBack      $width
            Write-Text "   AlbumArtist   : $albumArtist"  $ColorNowPlaying    $ColorDashBack      $width
            Write-Text "   Date          : $albumDate "        $ColorNowPlaying    $ColorDashBack      $width

            Write-Block $width $ColorDashBack
            Write-Text "   Title         : $trackTitle "       $ColorNowPlaying    $ColorDashBack      $width
            Write-Text "   Duration      : $trackTotalStr"     $ColorNowPlaying    $ColorDashBack      $width
            Write-Text "   Genre         : $trackGenre "       $ColorNowPlaying    $ColorDashBack      $width
            Write-Text "   Bitrate       : $trackBitrate kbps" $ColorNowPlaying    $ColorDashBack      $width

            $tmp = $trackFile.Substring(0, [Math]::Min($trackFile.Length, $width-22))
            Write-Text "   Path          : $tmp"               $ColorNowPlaying    $ColorDashBack      $width

            Write-Block $width $ColorDashBack
            Write-Text "   Queue Size    : $playlistLength"    $ColorNowPlaying    $ColorDashBack      $width

            Write-Block $width $ColorDashBack

            Write-Block $width $ColorHeaderBack
        }

        if ($playlistLength -eq "0") {
            Write-Block $width  DarkYellow
            Write-Text "                    >> No tracks in playlist << "    Black Yellow $width
            Write-Block $width  DarkYellow
        }

        Wait-WithKeyCheck
        Clear-Host

    }
}


    ####### START #########

    Clear-Host

    if ($args.Count -lt 1) {
        Write-Host  "`n  ERROR: MPD server address not specified as argument.  `n" -ForegroundColor Red
        exit 1
    }

    $MPDHost = $args[0]
    if (-not (Test-MPDConnection)) {
        Write-Host  "`n  ERROR: Cannot reach MPD server at $MPDHost`:$MPDPort  `n" -ForegroundColor Red
        exit 2
    }

    Run-Dashboard

    ####### END  #########
