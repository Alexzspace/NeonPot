param(
    [string]$Godot = $env:GODOT,
    [switch]$Graphical
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$Godot = Resolve-GodotConsole -Requested $Godot
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$logDirectory = Join-Path $projectPath 'test-results'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$testNames = @('test_public_notices', 'test_language_defaults', 'test_exact_raise_panel', 'test_exact_raise_integration', 'test_slider_labels', 'test_chip_input', 'test_manual_chip_integration', 'test_chip_inventory', 'test_session_inventory', 'test_chip_inventory_display', 'test_bet_sizing', 'test_manual_chip_panel', 'test_seat_presence', 'test_rectangular_freehand', 'test_flac_import', 'test_kaleidoscope_art', 'test_kaleidoscope_integration', 'test_music_import', 'test_deck_workshop', 'test_personal_tools', 'test_entry_lifecycle', 'test_ai_idle_network', 'test_table_entry', 'test_gallery_entry', 'test_entry_chips', 'test_ai_chip_idle', 'test_poker_engine', 'test_session', 'test_adversarial', 'test_cards', 'test_ui', 'test_haptics', 'test_chip_display', 'test_feedback', 'test_presentation_edges', 'test_chip_gesture', 'test_touch_slider', 'test_music_player', 'test_tactile_ui', 'test_interaction_lifecycle', 'test_chip_flourishes', 'test_chip_presence', 'test_fidget_timing', 'test_midnight_lifecycle', 'test_solo', 'test_solo_ui', 'test_ai_policy', 'test_seat_badge', 'test_neon_ui', 'test_showdown_readability', 'test_host_lobby', 'test_lan_lobby_ui', 'test_mixed_lan', 'test_lan_discovery', 'test_join_failures', 'test_lan_showdown_transition', 'test_public_card', 'test_table_typography', 'test_board_touch_ui', 'test_board_gesture', 'test_boot', 'test_home_entrance', 'test_chip_intro', 'test_table_prop_gesture', 'test_table_prop_ui', 'test_card_art', 'test_card_themes', 'test_deck_gallery', 'test_gallery_fidget', 'test_inertia_wheel', 'test_party_settings', 'test_back_navigation', 'test_exit_process', 'test_safe_area', 'test_mixflip_outer_layout', 'test_winning_hand', 'test_deck_settings', 'test_session_deck_theme')
foreach ($testName in $testNames) {
    $stdout = Join-Path $logDirectory ($testName + '.log')
    $stderr = Join-Path $logDirectory ($testName + '-error.log')
    $testArguments = @('--headless', '--path', ('"' + $projectPath + '"'), '--script', ('res://tests/' + $testName + '.gd'))
    $testProcess = Start-Process -FilePath $Godot -ArgumentList $testArguments -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    try {
        $testTimeout = if ($testName -eq 'test_solo_ui') { 60000 } else { 30000 }
        if (-not $testProcess.WaitForExit($testTimeout)) { throw "Timeout: $testName" }
        $testOutput = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
        if ($testProcess.ExitCode -ne 0 -or $testOutput -match 'SCRIPT ERROR|ERROR:|leaked|still in use' -or $testOutput -notmatch 'failures=0') {
            Write-Output $testOutput
            throw "Failed: $testName"
        }
        $testOutput -split "`r?`n" | Where-Object { $_ -match 'SUMMARY|_TEST |RANDOM_HANDS' } | Write-Output
    } finally {
        if (-not $testProcess.HasExited) { Stop-Process -Id $testProcess.Id }
    }
}
& (Join-Path $PSScriptRoot 'test_chip_inventory_network.ps1') -Godot $Godot -Dealer 0
& (Join-Path $PSScriptRoot 'test_chip_inventory_network.ps1') -Godot $Godot -Dealer 1
& (Join-Path $PSScriptRoot 'test_network.ps1') -Godot $Godot
& (Join-Path $PSScriptRoot 'test_chip_gesture_network.ps1') -Godot $Godot
& (Join-Path $PSScriptRoot 'test_mixed_lan.ps1') -Godot $Godot
& (Join-Path $PSScriptRoot 'test_discovery.ps1') -Godot $Godot
& (Join-Path $PSScriptRoot 'test_board_gesture_network.ps1') -Godot $Godot
& (Join-Path $PSScriptRoot 'test_table_prop_network.ps1') -Godot $Godot
& (Join-Path $PSScriptRoot 'test_deck_theme_network.ps1') -Godot $Godot
if ($Graphical) {
    $graphicsOutput = & $Godot --path $projectPath --script res://tests/test_ui.gd -- --capture-ui 2>&1 | Out-String
    Write-Output $graphicsOutput
    if ($LASTEXITCODE -ne 0 -or $graphicsOutput -match 'SCRIPT ERROR|ERROR:|leaked|still in use' -or $graphicsOutput -notmatch 'failures=0') {
        throw 'Graphical UI regression failed.'
    }
}
Write-Output 'ALL_SELFTESTS_PASS'


