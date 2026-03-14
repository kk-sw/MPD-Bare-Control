# 700
# -----------------------------------
#
# MPD BareControl (PS)
#
# -----------------------------------
# Dev: KK ; 2026-03-10-12
# -----------------------------------
# Bugs:
# - Elapsed time sometimes is incorrect
# - Optimize: Code Cleanup
# - Optimize: Clear-Host calls
# - Optimize: Info Dialog
# - Optimize: Debug Dialog
#
# -----------------------------------

#
# MPD Host Config
#
$MPDHost = "CHANGE_ME"
$MPDPort = 6600

#
# Color Config
#
$ColorDashBack          = "Black";
$ColorPlaylistFore      = "DarkYellow";
$ColorRandomFore        = "DarkGray";
$ColorHeaderBack        = "DarkBlue";
$ColorNowPlaying        = "DarkGreen";

#
# File Info
#
$ShowFileInfo = $false;

#
# Log Config
#
#$ShowLog = $true;
$ShowLog = $false;

# Global index to track sequence position
$Global:ColorIndex = 0


function Show-Info($text) {
    Write-Host $text -ForegroundColor White -BackgroundColor Blue
}

function Quote-MPD($text) {
    return '"' + $text.Replace('"', '\"') + '"'
}

function Get-NextColor {
    $colors = @(
        "DarkGray","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow",
        "Gray","Blue",         "Green",     "Cyan",     "Red",  "Magenta",   "Yellow","White", "Black"
    )

    $color = $colors[$Global:ColorIndex]

    # Move to next index (wrap around)
    $Global:ColorIndex = ($Global:ColorIndex + 1) % $colors.Count
    Show-Info " Using color: $color "
    return $color
}

function Format-Time($sec) {
    if ($sec -le 0) { return "00:00" }
    $m = [int]($sec / 60)
    $s = $sec % 60
    return ("{0:D2}:{1:D2}" -f $m, $s)
}

function Wait-WithKeyCheck {
    param(
        [int]$CycleCount = 10
    )

    $elapsed = 0
    while ($elapsed -lt $CycleCount) {

        if ([Console]::KeyAvailable) {
            break
        }

        Start-Sleep -Milliseconds 800
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
            Write-Host " Request: " -ForegroundColor DarkBlue -NoNewline
            Write-Host "$Command" -ForegroundColor Blue
            Write-Host " Response: " -ForegroundColor DarkGreen -NoNewline
            Write-Host " $response `n" -ForegroundColor DarkYellow
        #    [Console]::ReadKey($true) | Out-Null
        }

        return $response
    }
    catch {
        Write-Host  "`n  ERROR: Cannot reach MPD server at $MPDHost`:$MPDPort  `n" -ForegroundColor Red
        return "";
    }

}

function Show-MpdServerInfo {
    Clear-Host
    Write-Host "               MPD Server Info              `n"         -ForegroundColor Gray -BackgroundColor $ColorHeaderBack

    # Get MPD status and stats
    $stats  = Send-MPDCommand "stats"

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

    # Convert DB playtime to H:M:S
    $dbTS = [TimeSpan]::FromSeconds([int]$dbPlaytimeSec)
    $dbFmt = "{0}h {1}m" -f $dbTS.Hours, $dbTS.Minutes

    Write-Host " Host        : $MPDHost"     -ForegroundColor DarkYellow
    Write-Host " Port        : $MPDPort"     -ForegroundColor DarkYellow
    Write-Host " Uptime      : $uptimeFmt"   -ForegroundColor DarkYellow

    Write-Host ""
    Write-Host "                  Database                  " -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Host ""
    Write-Host " Artists     : $artists"      -ForegroundColor DarkYellow
    Write-Host " Albums      : $albums"       -ForegroundColor DarkYellow
    Write-Host " Songs       : $songs"        -ForegroundColor DarkYellow
    Write-Host " Playtime    : $dbFmt"        -ForegroundColor DarkYellow


    $tmp = [DateTimeOffset]::FromUnixTimeSeconds($dbUpdate).ToLocalTime()
    $tmp = $tmp.ToString('yyyy MMM dd  -  HH:mm')
    Write-Host " Last Update : $tmp"        -ForegroundColor DarkYellow

    Write-Host "`n                                            " -ForegroundColor Gray -BackgroundColor $ColorHeaderBack

    [Console]::ReadKey($true) | Out-Null
    Clear-Host
}

function Show-NoPlaylist{
    Write-Host "                                        "  -BackgroundColor Red
    Write-Host "   >>  No playlist is being played <<   "  -BackgroundColor DarkRed  -ForegroundColor Yellow
    Write-Host "                                        "  -BackgroundColor Red
}

function Show-PlaylistHeader {
    param(
        [string]$PlaylistName,
        [int]$SongCount
    )

    Clear-Host
    Write-Host "     Playlist Content  -  "   -NoNewline -ForegroundColor Gray -BackgroundColor DarkBlue
    Write-Host " $PlaylistName  "             -NoNewline -ForegroundColor DarkYellow -BackgroundColor DarkBlue
    Write-Host " ($SongCount songs)    `n"    -ForegroundColor Yellow -BackgroundColor DarkBlue

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
    Show-Info " Fetching playlist data for   $playlistName      "

    $quoted = Quote-MPD $playlistName
    $resp = Send-MPDCommand "listplaylistinfo $quoted"

    if ($resp.Count -eq 0) {
        Write-Host "Playlist is empty." -ForegroundColor Yellow
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
            Write-Host "`n          SPACE to continue; q to return ($preCnt-$cnt)                  " -ForegroundColor Yellow -BackgroundColor DarkBlue
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
            Write-Host "`n                                  " -ForegroundColor Black -BackgroundColor  DarkYellow
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

    # Check for + prefix
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

    # load plalist
    if (-not ($choice -as [int])) {
        Clear-Host
        return
    }

    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $playlists.Count) { return }

    $selected = $playlists[$index]
    Write-Host "`nSelected playlist: $selected"

    $quoted = Quote-MPD $selected

    # Load playlist
    Send-MPDCommand "clear"
    Send-MPDCommand "load $quoted"
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

    while ($true) {

        # Handle keypresses without blocking
       if ([Console]::KeyAvailable) {
            $keyChar = [Console]::ReadKey($true).KeyChar.ToString().ToLower()

            switch ($keyChar) {

                "a" {
                        # Create playlist with all songs
                            Show-Info " Sending: clear (playlist) "
                        Send-MPDCommand "clear"
                            Show-Info " Sending: add / (playlist) "
                        Send-MPDCommand "add /"
                            Show-Info " Sending: play (playlist) "
                        Send-MPDCommand "play"
                    }

                "c" {
                        Send-MPDCommand "clear"
                    }

                "d" {   # DEBUG
                        $ShowLog = $true;
                    }

                "i" {   # File Info
                        if ($ShowFileInfo)
                            { $ShowFileInfo = $false }
                        else
                            { $ShowFileInfo = $true }
                    }


                "l" {
                        Show-PlaylistsMenu
                    }

                "n" {
                        if ($playingState) {
                            # Show-Info "Sending: next"
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

                "s" {
                        if ($playingState) {
                            Send-MPDCommand "stop"
                        } else {
                            Send-MPDCommand "play"
                        }
                    }

                "v" {
                        Show-MpdServerInfo
                    }

                "w" {
                        Send-MPDCommand "stop"
                        Clear-Host
                        Show-Info "`n  Playback stopped  `n"
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
                        $ColorRandomFore = (Get-NextColor)
                    }

                "5" {
                        $ColorDashBack = (Get-NextColor)
                    }


                "9" {
                        $ColorDashBack          = "Black";
                        $ColorPlaylistFore      = "DarkYellow";
                        $ColorRandomFore        = "DarkGray";
                        $ColorHeaderBack        = "DarkBlue";
                        $ColorNowPlaying        = "DarkGreen";
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

        $randomMode = "<unknown>"
        $playlistIndex = "<none>"
        $playlistLength = ""
        $playlistName = "<none>"
        $playingState = $false;
        $trackElapsed = 0
        $trackTotal = 0
        $trackBitrate = 0

        # Status + playlist
        $statusResp = Send-MPDCommand "status"
        foreach ($line in $statusResp) {
            if ($line -contains "state: play") {
                $playingState = $true
            }
            if ($line -like "random:*") {
                $randomMode = if ($line.Substring(7).Trim() -eq "1") { "ON" } else { "OFF" }
            }
            if ($line -like "playlist:*") {
                $playlistIndex = $line.Substring(9).Trim()
            }
            if ($line -like "playlistlength:*") {
                $playlistLength = $line.Substring(15).Trim()
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
            $elapsedStr     = Format-Time $trackElapsed
            $trackTotalStr  = Format-Time $trackTotal
            $playDisplay1  = "$artist - $trackTitle              | ~$elapsedStr / $trackTotalStr"
            $playDisplay2  = "$album ($albumDate)"

        } else {
            $elapsedStr     = ""
            $trackTotalStr  = ""
            $playDisplay1   = "<none>"
            $playDisplay2   = ""
        }

        # Build dashboard lines
        $updateTime = (Get-Date -Format 'yyyy MMMM dd  |  HH:mm:ss')
        $lineHead   = "  MPD BareControl (PS) v.1                  ($MPDHost`:$MPDPort)                            $updateTime "

        $linePlay1      = "   Artist/Title    : $playDisplay1"
        $linePlay2      = "   Album           : $playDisplay2"
        $lineRand       = "   Random Mode     : $randomMode "
        $linePlayName   = "   Playlist Name   : $playlistName"
        $linePlayLenght = "   Playlist Length : $playlistLength"

        $lineKeys1  = " (S)tart/Stop playing | (N)ext song | (P)rev. song |  (L)oad playlist | (C)lear playlist | Play (a)ll |  (R)andom On/Off"
        $lineKeys2  = " (I)nfo Panel         |                                                                               |  (V) MPD Server Info"
        $lineKeys3  = " (Q)uit               | (W) Stop play and quit     |  (1-5) Colors    | (9) Default colors            |  (D)ebug log"

        $width = ($lineHead.Length,  $lineKeys1.Length , $lineKeys2.Length | Measure-Object -Maximum).Maximum + 1

        Write-Host  ""
        Write-Host ("" + $lineHead.PadRight($width) + "")       -ForegroundColor Gray -BackgroundColor $ColorHeaderBack

        Write-Host  " ".PadRight($width)                                                              -BackgroundColor $ColorDashBack
        Write-Host $linePlay1.PadRight($width)            -ForegroundColor $ColorNowPlaying            -BackgroundColor $ColorDashBack
        Write-Host $linePlay2.PadRight($width)            -ForegroundColor $ColorNowPlaying            -BackgroundColor $ColorDashBack

        Write-Host  " ".PadRight($width)                                                          -BackgroundColor $ColorDashBack
        Write-Host $linePlayName.PadRight($width)        -ForegroundColor $ColorPlaylistFore      -BackgroundColor $ColorDashBack
        Write-Host $linePlayLenght.PadRight($width)      -ForegroundColor $ColorPlaylistFore      -BackgroundColor $ColorDashBack

        Write-Host  " ".PadRight($width)                                                        -BackgroundColor $ColorDashBack
        Write-Host $lineRand.PadRight($width)           -ForegroundColor $ColorRandomFore       -BackgroundColor $ColorDashBack

        Write-Host  " ".PadRight($width)                                                          -BackgroundColor $ColorDashBack
        Write-Host ( $lineKeys1.PadRight($width) )                    -ForegroundColor Gray       -BackgroundColor $ColorHeaderBack
        Write-Host ( $lineKeys2.PadRight($width) )                    -ForegroundColor Gray       -BackgroundColor $ColorHeaderBack
        Write-Host ( $lineKeys3.PadRight($width) )                    -ForegroundColor Gray       -BackgroundColor $ColorHeaderBack

        if ($ShowFileInfo) {
            Write-Host " ".PadRight($width)                       -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack

            Write-Host ( "    >> Artist      : $artist".PadRight($width) )              -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack
            Write-Host ( "    >> Album       : $album".PadRight($width) )               -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack
            Write-Host ( "    >> AlbumArtist : $albumArtist".PadRight($width) )         -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack
            Write-Host ( "    >> Date        : $albumDate ".PadRight($width) )          -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack
            Write-Host ( "    >> Title       : $trackTitle ".PadRight($width) )         -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack
            Write-Host ( "    >> Duration    : $trackTotalStr".PadRight($width) )       -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack
            Write-Host ( "    >> Genre       : $trackGenre ".PadRight($width) )         -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack
            Write-Host ( "    >> Bitrate     : $trackBitrate kbps".PadRight($width) )   -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack
            $tmp = $trackFile.Substring(0, [Math]::Min($trackFile.Length, $width-22))
            Write-Host ( "    >> Path        : $tmp".PadRight($width) )                -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack
            Write-Host " ".PadRight($width)                       -ForegroundColor $ColorNowPlaying  -BackgroundColor $ColorDashBack

            Write-Host " ".PadRight($width)                       -ForegroundColor Gray       -BackgroundColor $ColorHeaderBack
        }

        if ($playlistLength -eq "0") {
            Write-Host " ".PadRight($width) -ForegroundColor Black                          -BackgroundColor DarkYellow
            Write-Host "                                   >> No songs in playlist <<".PadRight($width)      -ForegroundColor Black -BackgroundColor Yellow
            Write-Host " ".PadRight($width) -ForegroundColor Black                          -BackgroundColor DarkYellow
        }

        Wait-WithKeyCheck
        Clear-Host

    }
}


####### START #########

    Clear-Host

    if (-not (Test-MPDConnection)) {
        Write-Host  "`n  ERROR: Cannot reach MPD server at $MPDHost`:$MPDPort  `n" -ForegroundColor Red
        exit
    }

    Run-Dashboard

