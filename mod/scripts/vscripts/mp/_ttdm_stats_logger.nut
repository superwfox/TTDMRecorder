global function TTDMStats_Init

struct {
    bool enabled = false
    bool announced = false
    bool running = false
    bool recording = false
    bool saved = false
    string matchKey = ""
    string samplePath = ""
    string summaryPath = ""
    string sampleCsv = ""
    int sampleCount = 0
    int lastDamage = 0
    int lastKills = 0
    int lastDeaths = 0
    float lastSampleAt = 0.0
} file

void function TTDMStats_Init()
{
    printt("[TTDMStats] CLIENT init fired")
    AddCallback_OnClientScriptInit( TTDMStats_OnClientReady )
    AddCallback_GameStateEnter( eGameState.Prematch, TTDMStats_OnPrematch )
    AddCallback_GameStateEnter( eGameState.Playing, TTDMStats_OnPlaying )
    AddCallback_GameStateEnter( eGameState.WinnerDetermined, TTDMStats_OnMatchFinished )
    AddCallback_GameStateEnter( eGameState.Postmatch, TTDMStats_OnMatchFinished )
}

void function TTDMStats_OnClientReady( entity player )
{
    if ( file.running )
        return

    file.running = true
    thread TTDMStats_MonitorThread()
}

void function TTDMStats_MonitorThread()
{
    while ( true )
    {
        entity player = GetLocalClientPlayer()
        if ( !IsValid( player ) )
        {
            wait 0.5
            continue
        }

        TTDMStats_UpdateMode( player )
        if ( file.recording )
        {
            TTDMStats_LogChanges( player )
            TTDMStats_RecordSample( player )
        }

        wait 0.1
    }
}

void function TTDMStats_ResetState( entity player )
{
    file.announced = false
    file.recording = false
    file.saved = false
    file.matchKey = ""
    file.samplePath = ""
    file.summaryPath = ""
    file.sampleCsv = ""
    file.sampleCount = 0
    file.lastSampleAt = 0.0
    file.lastDamage = player.GetPlayerGameStat( PGS_ASSAULT_SCORE )
    file.lastKills = player.GetPlayerGameStat( PGS_KILLS )
    file.lastDeaths = player.GetPlayerGameStat( PGS_DEATHS )
}

void function TTDMStats_UpdateMode( entity player )
{
    string mode = GameRules_GetGameMode()
    file.enabled = ( mode == "ttdm" )

    if ( !file.enabled )
    {
        if ( file.recording && !file.saved )
            TTDMStats_SaveMatch()

        TTDMStats_ResetState( player )
        return
    }

    if ( file.announced )
        return

    file.announced = true
    file.lastDamage = player.GetPlayerGameStat( PGS_ASSAULT_SCORE )
    file.lastKills = player.GetPlayerGameStat( PGS_KILLS )
    file.lastDeaths = player.GetPlayerGameStat( PGS_DEATHS )

    printt("[TTDMStats] mode =", mode, " baseline damage =", file.lastDamage, " kills =", file.lastKills, " deaths =", file.lastDeaths)
}

void function TTDMStats_OnPrematch()
{
    TTDMStats_TryStartRecording()
}

void function TTDMStats_OnPlaying()
{
    TTDMStats_TryStartRecording()
}

void function TTDMStats_OnMatchFinished()
{
    TTDMStats_SaveMatch()
}

string function TTDMStats_GetTimestamp()
{
    int unixTime = GetUnixTimestamp()
    int hours = ( unixTime / 3600 ) % 24
    int minutes = ( unixTime / 60 ) % 60
    return format( "%02d-%02d", hours, minutes )
}

void function TTDMStats_TryStartRecording()
{
    entity player = GetLocalClientPlayer()
    if ( !IsValid( player ) )
        return

    if ( GameRules_GetGameMode() != "ttdm" )
        return

    if ( file.recording )
        return

    file.recording = true
    file.saved = false
    string timestamp = TTDMStats_GetTimestamp()
    string playerName = player.GetPlayerName()
    file.matchKey = format( "%s_%s", playerName, timestamp )
    file.samplePath = file.matchKey + "_timeline.csv"
    file.summaryPath = file.matchKey + "_players.csv"
    file.sampleCsv = "SampleNum,health,titanType\n"
    file.sampleCount = 0
    file.lastSampleAt = 0.0

    printt("[TTDMStats] recording started =", file.matchKey)
}

void function TTDMStats_LogChanges( entity player )
{
    int damage = player.GetPlayerGameStat( PGS_ASSAULT_SCORE )
    int kills = player.GetPlayerGameStat( PGS_KILLS )
    int deaths = player.GetPlayerGameStat( PGS_DEATHS )

    if ( damage != file.lastDamage || kills != file.lastKills || deaths != file.lastDeaths )
    {
        printt(
            "[TTDMStats] damage =", damage,
            " kills =", kills,
            " deaths =", deaths,
            " deltaDamage =", damage - file.lastDamage,
            " deltaKills =", kills - file.lastKills,
            " deltaDeaths =", deaths - file.lastDeaths
        )

        file.lastDamage = damage
        file.lastKills = kills
        file.lastDeaths = deaths
    }
}

void function TTDMStats_RecordSample( entity player )
{
    float now = Time()
    if ( now - file.lastSampleAt < 0.5 )
        return

    file.lastSampleAt = now
    file.sampleCount++
    file.sampleCsv += format(
        "%d,%d,%s\n",
        file.sampleCount,
        player.GetHealth(),
        TTDMStats_GetTitanType( player )
    )

    if ( file.sampleCount % 2 == 0 )
        NSSaveFile( file.samplePath, file.sampleCsv )
}

string function TTDMStats_GetTitanType( entity player )
{
    if ( player.IsTitan() )
        return TTDMStats_GetTitanClass( player )

    entity petTitan = player.GetPetTitan()
    if ( IsValid( petTitan ) && IsValid( petTitan.GetTitanSoul() ) )
        return TTDMStats_GetTitanClass( petTitan )

    return "pilot"
}

string function TTDMStats_GetTitanClass( entity titan )
{
    entity soul = titan.GetTitanSoul()
    if ( !IsValid( soul ) )
        return "unknown"

    string settingsName = PlayerSettingsIndexToName( soul.GetPlayerSettingsNum() )
    return expect string( Dev_GetPlayerSettingByKeyField_Global( settingsName, "titanCharacterName" ) )
}

void function TTDMStats_SaveMatch()
{
    if ( !file.recording || file.saved )
        return

    entity localPlayer = GetLocalClientPlayer()
    if ( !IsValid( localPlayer ) )
        return

    string summaryCsv = "name,kills,deaths,damage\n"
    foreach ( entity player in GetPlayerArray() )
    {
        if ( !IsValid( player ) )
            continue

        if ( player.GetPlayerName() == "Replay" )
            continue

        summaryCsv += format(
            "%s,%d,%d,%d\n",
            player.GetPlayerName(),
            player.GetPlayerGameStat( PGS_KILLS ),
            player.GetPlayerGameStat( PGS_DEATHS ),
            player.GetPlayerGameStat( PGS_ASSAULT_SCORE )
        )
    }

    NSSaveFile( file.samplePath, file.sampleCsv )
    NSSaveFile( file.summaryPath, summaryCsv )

    file.saved = true
    file.recording = false
    printt("[TTDMStats] saved =", file.samplePath, " and ", file.summaryPath)
}
