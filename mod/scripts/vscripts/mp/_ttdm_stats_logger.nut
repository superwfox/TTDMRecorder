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
    string summaryCsv = ""
    int uploadRetries = 0
    bool uploaded = false
} file

void function TTDMStats_Init()
{
    printt("[TTDMStats] CLIENT init fired")
    if ( !NSDoesFileExist( ".ttdm_init" ) )
        NSSaveFile( ".ttdm_init", "" )
    thread TTDMStats_UploadLeftovers()
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
    file.summaryCsv = ""
    file.sampleCount = 0
    file.lastSampleAt = 0.0
    file.uploadRetries = 0
    file.uploaded = false
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
    if ( file.saved && !file.uploaded )
        thread TTDMStats_UploadWithRetry()
}

string function TTDMStats_GetTimestamp()
{
    int unixTime = GetUnixTimestamp()
    int minutes = ( unixTime / 60 ) % 60
    int hours = ( unixTime / 3600 ) % 24
    int days = unixTime / 86400
    int year = 1970
    while ( true )
    {
        int daysInYear = 365
        if ( year % 4 == 0 && ( year % 100 != 0 || year % 400 == 0 ) )
            daysInYear = 366
        if ( days < daysInYear )
            break
        days -= daysInYear
        year++
    }
    array<int> monthDays = [ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ]
    if ( year % 4 == 0 && ( year % 100 != 0 || year % 400 == 0 ) )
        monthDays[1] = 29
    int month = 1
    for ( int i = 0; i < 12; i++ )
    {
        if ( days < monthDays[i] )
            break
        days -= monthDays[i]
        month++
    }
    int day = days + 1
    return format( "%04d-%02d-%02d_%02d-%02d", year, month, day, hours, minutes )
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
    file.sampleCsv = "SampleNum,health,titanType,isDoomed\n"
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

bool function TTDMStats_IsDoomed( entity player )
{
    if ( !player.IsTitan() )
        return false

    entity soul = player.GetTitanSoul()
    if ( !IsValid( soul ) )
        return false

    return IsValid( soul ) && GetDoomedState( player )
}

void function TTDMStats_RecordSample( entity player )
{
    float now = Time()
    if ( now - file.lastSampleAt < 0.5 )
        return

    file.lastSampleAt = now
    file.sampleCount++

    bool doomed = TTDMStats_IsDoomed( player )

    file.sampleCsv += format(
        "%d,%d,%s,%d\n",
        file.sampleCount,
        player.GetHealth(),
        TTDMStats_GetTitanType( player ),
        doomed ? 1 : 0
    )

    if ( file.sampleCount % 20 == 0 )
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

    file.summaryCsv = summaryCsv
    NSSaveFile( file.samplePath, file.sampleCsv )
    NSSaveFile( file.summaryPath, summaryCsv )

    file.saved = true
    file.recording = false
    printt("[TTDMStats] saved =", file.samplePath, " and ", file.summaryPath)
}

// ── Leftover scan on startup ────────────────────────────────────

void function TTDMStats_UploadLeftovers()
{
    wait 1.0

    array<string> allFiles = NSGetAllFiles( "" )

    table< string, table< string, string > > groups = {}

    foreach ( string filename in allFiles )
    {
        var playersFind = filename.find( "_players.csv" )
        var timelineFind = filename.find( "_timeline.csv" )

        if ( playersFind != null )
        {
            string key = filename.slice( 0, expect int( playersFind ) )
            if ( !( key in groups ) )
                groups[key] <- { players = "", timeline = "" }
            groups[key]["players"] = filename
        }
        else if ( timelineFind != null )
        {
            string key = filename.slice( 0, expect int( timelineFind ) )
            if ( !( key in groups ) )
                groups[key] <- { players = "", timeline = "" }
            groups[key]["timeline"] = filename
        }
    }

    foreach ( string key, table< string, string > pair in groups )
    {
        string playersFile = pair["players"]
        string timelineFile = pair["timeline"]

        if ( playersFile == "" || timelineFile == "" )
        {
            if ( playersFile != "" )
            {
                NSDeleteFile( playersFile )
                printt("[TTDMStats] deleted orphan:", playersFile)
            }
            if ( timelineFile != "" )
            {
                NSDeleteFile( timelineFile )
                printt("[TTDMStats] deleted orphan:", timelineFile)
            }
            continue
        }

        printt("[TTDMStats] found leftover pair:", playersFile, timelineFile)
        thread TTDMStats_UploadLeftoverPair( playersFile, timelineFile )
        while ( NSDoesFileExist( playersFile ) )
            wait 1.0
    }
}

void function TTDMStats_UploadLeftoverPair( string playersFile, string timelineFile )
{
    table state = {
        playersCsv = "",
        timelineCsv = "",
        playersLoaded = false,
        timelineLoaded = false,
        playersFailed = false,
        timelineFailed = false
    }

    NSLoadFile( playersFile,
        void function( string data ) : ( state )
        {
            state.playersCsv = data
            state.playersLoaded = true
        },
        void function() : ( state )
        {
            state.playersFailed = true
        }
    )

    NSLoadFile( timelineFile,
        void function( string data ) : ( state )
        {
            state.timelineCsv = data
            state.timelineLoaded = true
        },
        void function() : ( state )
        {
            state.timelineFailed = true
        }
    )

    float deadline = Time() + 5.0
    while ( !( state.playersLoaded || state.playersFailed ) || !( state.timelineLoaded || state.timelineFailed ) )
    {
        if ( Time() > deadline )
            break
        wait 0.1
    }

    if ( state.playersFailed || state.timelineFailed || state.playersCsv == "" || state.timelineCsv == "" )
    {
        NSDeleteFile( playersFile )
        NSDeleteFile( timelineFile )
        printt("[TTDMStats] leftover files empty or failed to load, deleted")
        return
    }

    file.summaryPath = playersFile
    file.samplePath = timelineFile
    file.summaryCsv = expect string( state.playersCsv )
    file.sampleCsv = expect string( state.timelineCsv )
    file.uploaded = false

    for ( int attempt = 1; attempt <= TTDM_MAX_RETRIES; attempt++ )
    {
        file.uploaded = false
        printt("[TTDMStats] leftover upload attempt", attempt, "for", playersFile)

        bool started = TTDMStats_DoUpload()
        if ( !started )
        {
            wait 3.0
            continue
        }

        float deadline = Time() + 10.0
        while ( !file.uploaded && Time() < deadline )
            wait 0.5

        if ( file.uploaded )
        {
            NSDeleteFile( playersFile )
            NSDeleteFile( timelineFile )
            printt("[TTDMStats] leftover uploaded and deleted:", playersFile)
            TTDMStats_ShowHudMessage( "TTDM 历史数据上传成功", playersFile )
            return
        }

        if ( attempt < TTDM_MAX_RETRIES )
            wait 3.0
    }

    printt("[TTDMStats] leftover upload failed:", playersFile)
    TTDMStats_ShowHudMessage( "TTDM 历史数据上传失败", playersFile )
}

// ── Signing & Encoding ──────────────────────────────────────────

// Key fragments — combined at runtime, never stored as single value
const int _TTDM_KA = 0x5A3C
const int _TTDM_KB = 0x7F12
const int _TTDM_KC = 0x4E8D
const int _TTDM_KD = 0xA1B7

int function _TTDMDeriveKey()
{
    return ((_TTDM_KA << 16) | _TTDM_KB) ^ ((_TTDM_KC << 16) | _TTDM_KD)
}

// MurmurHash-inspired hash, must match server JS exactly
// Squirrel integers are 32-bit signed; we use bitand 0x7FFFFFFF where needed
// but ultimately the hex output must match JS's >>> 0
int function _TTDMHash( string str, int seed )
{
    int h = seed
    for ( int i = 0; i < str.len(); i++ )
    {
        h = h ^ str[i]
        // Multiply by 0x5bd1e995 — use split multiply to avoid overflow issues
        // h = h * 0x5bd1e995  (Squirrel handles 32-bit wrap natively)
        h = h * 0x5bd1e995
        h = h ^ ( (h >>> 15) & 0x1FFFF )
    }
    h = h * 0x27d4eb2d
    h = h ^ ( (h >>> 13) & 0x7FFFF )
    return h
}

string function _TTDMIntToHex( int val )
{
    // Convert to unsigned hex string matching JS (>>> 0).toString(16)
    string result = ""
    // Process as unsigned: treat negative as val + 2^32
    int remaining = val
    if ( remaining == 0 )
        return "0"

    string hexchars = "0123456789abcdef"
    // Extract 8 hex digits (32 bits)
    array<string> digits = []
    for ( int i = 0; i < 8; i++ )
    {
        int nibble = remaining & 0xF
        digits.insert( 0, hexchars.slice( nibble, nibble + 1 ) )
        remaining = (remaining >>> 4) & 0x0FFFFFFF
    }

    result = ""
    foreach ( string d in digits )
        result += d

    // Strip leading zeros
    int start = 0
    while ( start < result.len() - 1 && result[start] == '0' )
        start++

    return result.slice( start )
}

string function _TTDMComputeSig( string payload, int ts )
{
    int key = _TTDMDeriveKey()
    int h1 = _TTDMHash( payload, key )
    int h2 = _TTDMHash( "" + ts, h1 )
    int sigVal = h2 ^ key
    return _TTDMIntToHex( sigVal )
}

// XOR encode + Base64
string function _TTDMXorEncode( string input )
{
    int key = _TTDMDeriveKey()
    string encoded = ""
    for ( int i = 0; i < input.len(); i++ )
    {
        int shift = (i % 4) * 8
        int k = (key >>> shift) & 0xFF
        int c = input[i] ^ k
        encoded += format( "%c", c )
    }
    return _TTDMBase64Encode( encoded )
}

// Minimal Base64 encoder
string function _TTDMBase64Encode( string input )
{
    string chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    string result = ""
    int i = 0
    int len = input.len()

    while ( i < len )
    {
        int b0 = input[i] & 0xFF
        int b1 = (i + 1 < len) ? (input[i + 1] & 0xFF) : 0
        int b2 = (i + 2 < len) ? (input[i + 2] & 0xFF) : 0

        int triple = (b0 << 16) | (b1 << 8) | b2

        result += chars.slice( (triple >>> 18) & 0x3F, ((triple >>> 18) & 0x3F) + 1 )
        result += chars.slice( (triple >>> 12) & 0x3F, ((triple >>> 12) & 0x3F) + 1 )

        if ( i + 1 < len )
            result += chars.slice( (triple >>> 6) & 0x3F, ((triple >>> 6) & 0x3F) + 1 )
        else
            result += "="

        if ( i + 2 < len )
            result += chars.slice( triple & 0x3F, (triple & 0x3F) + 1 )
        else
            result += "="

        i += 3
    }

    return result
}

// ── Upload ──────────────────────────────────────────────────────

const string TTDM_UPLOAD_URL = "https://ttdm-review.pages.dev/api/upload"
const int    TTDM_MAX_RETRIES = 5

void function TTDMStats_UploadWithRetry()
{
    for ( int attempt = 1; attempt <= TTDM_MAX_RETRIES; attempt++ )
    {
        file.uploadRetries = attempt
        file.uploaded = false

        printt("[TTDMStats] upload attempt", attempt)
        bool started = TTDMStats_DoUpload()

        if ( !started )
        {
            printt("[TTDMStats] failed to start HTTP request")
            wait 3.0
            continue
        }

        float deadline = Time() + 10.0
        while ( !file.uploaded && Time() < deadline )
            wait 0.5

        if ( file.uploaded )
        {
            NSDeleteFile( file.samplePath )
            NSDeleteFile( file.summaryPath )
            printt("[TTDMStats] upload success, files deleted")
            TTDMStats_ShowHudMessage( "TTDM 数据上传成功", "" )
            return
        }

        if ( attempt < TTDM_MAX_RETRIES )
            wait 3.0
    }

    printt("[TTDMStats] upload failed after", TTDM_MAX_RETRIES, "attempts")
    TTDMStats_ShowHudMessage( "TTDM 数据上传失败", "已重试" + TTDM_MAX_RETRIES + "次" )
}

// Titan type name -> index mapping, must match server TITAN_TYPES array
int function _TTDMTitanIndex( string name )
{
    if ( name == "pilot" )     return 0
    if ( name == "legion" )    return 1
    if ( name == "ronin" )     return 2
    if ( name == "northstar" ) return 3
    if ( name == "scorch" )    return 4
    if ( name == "tone" )      return 5
    if ( name == "monarch" )   return 6
    if ( name == "ion" )       return 7
    return 8 // unknown
}

// Pack timeline CSV into binary (7 bytes per sample) then Base64 encode
string function _TTDMPackTimeline( string csv )
{
    string raw = ""
    array<string> lines = split( csv, "\n" )
    // Skip header line (index 0)
    for ( int i = 1; i < lines.len(); i++ )
    {
        string line = strip( lines[i] )
        if ( line == "" )
            continue

        array<string> cols = split( line, "," )
        if ( cols.len() < 4 )
            continue

        int sampleNum = cols[0].tointeger()
        int health = cols[1].tointeger()
        int titanIdx = _TTDMTitanIndex( strip( cols[2] ) )
        int doomed = strip( cols[3] ).tointeger()

        // 7 bytes: sampleNum(2 LE), health(2 LE), titanIdx(1), doomed(1), reserved(1)
        raw += format( "%c%c%c%c%c%c%c",
            sampleNum & 0xFF, (sampleNum >>> 8) & 0xFF,
            health & 0xFF, (health >>> 8) & 0xFF,
            titanIdx & 0xFF,
            doomed & 0xFF,
            0
        )
    }
    return _TTDMBase64Encode( raw )
}

bool function TTDMStats_DoUpload()
{
    // Pack timeline to binary
    string timelineBin = _TTDMPackTimeline( file.sampleCsv )

    // Build inner payload as JSON string
    table innerPayload = {
        players_filename = file.summaryPath,
        timeline_filename = file.samplePath,
        players_csv = file.summaryCsv,
        timeline_bin = timelineBin
    }
    string innerJson = EncodeJSON( innerPayload )

    // XOR encode the inner payload
    string encodedPayload = _TTDMXorEncode( innerJson )

    // Generate signature
    int ts = GetUnixTimestamp()
    string sig = _TTDMComputeSig( encodedPayload, ts )

    // Build outer envelope
    table envelope = {
        sig = sig,
        ts = ts,
        payload = encodedPayload
    }

    HttpRequest request
    request.method = HttpRequestMethod.POST
    request.url = TTDM_UPLOAD_URL
    request.headers["Content-Type"] <- [ "application/json" ]
    request.body = EncodeJSON( envelope )

    return NSHttpRequest( request,
        void function( HttpRequestResponse response )
        {
            if ( NSIsSuccessHttpCode( response.statusCode ) )
            {
                table result = DecodeJSON( response.body )
                if ( "ok" in result && result["ok"] == true )
                {
                    file.uploaded = true
                    printt("[TTDMStats] server accepted upload, match_id =", ( "match_id" in result ? result["match_id"] : "?" ))
                    return
                }
            }
            printt("[TTDMStats] upload rejected, status =", response.statusCode, " body =", response.body)
        },
        void function( HttpRequestFailure failure )
        {
            printt("[TTDMStats] upload HTTP error:", failure.errorCode, failure.errorMessage)
        }
    )
}

void function TTDMStats_ShowHudMessage( string title, string subtext )
{
    entity player = GetLocalClientPlayer()
    if ( !IsValid( player ) )
        return

    try
    {
        AnnouncementData ann = Announcement_Create( title )
        Announcement_SetSubText( ann, subtext )
        Announcement_SetDuration( ann, 5.0 )
        AnnouncementFromClass( player, ann )
    }
    catch ( ex )
    {
        printt("[TTDMStats] HUD message failed:", ex)
    }
}
