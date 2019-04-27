#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <zombieswarm>
#include <gum>
#include <cstrike>
#include <colorvariables>
#include <overlays>

#include <swarm/utils>

#pragma newdecls required

#define TIMER_SPEED 1.0

#define int(%1)            view_as<int>(%1)

#define PLUGIN_VERSION "1.0"
#define PLUGIN_NAME    "Zombie Mod"

// Checks if user connected, whithout any errors.
//#define IsValidClient(%1)  ( 1 <= %1 <= MaxClients && IsClientInGame(%1) && !IsClientSourceTV(%1) )

// Checks if user alive, whithout any errors.
#define IsValidAlive(%1) ( 1 <= %1 <= MaxClients && IsClientInGame(%1) && IsPlayerAlive(%1) )

#define MENU_DISPLAY_TIME 20

#define MAX_CLASS 20
#define MAX_HINT_SIZE 512

#define HIDEHUD_RADAR 1 << 12

#define EF_NOSHADOW                 (1 << 4)
#define EF_NORECEIVESHADOW          (1 << 6)

#define DEFAULT_ZM_NAME "Unnamed Zombie"
#define DEFAULT_ZM_DESC "This zombie needs more information"
#define DEFAULT_ZM_MODEL_PATH "models/player/kuristaja/zombies/classic/classic"
#define DEFAULT_ZM_ARMS_PATH ""
#define DEFAULT_ZM_HEALTH 100
#define DEFAULT_ZM_DAMAGE 20.0
#define DEFAULT_ZM_SPEED 1.0
#define DEFAULT_ZM_GRAVITY 1.0
#define DEFAULT_ZM_EXCLUDED false

#define DEFAULT_ARMS "models/weapons/ct_arms_gign.mdl"

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "Zombie Swarm Contributors",
    description = "Zombie mod like Left4Dead",
    version = PLUGIN_VERSION,
    url = "https://github.com/Prefix/zombieswarm"
};

int numClasses;

int zombieClass[MAXPLAYERS + 1], pTeam[MAXPLAYERS + 1];
bool b_isGhost[MAXPLAYERS + 1]
bool shouldCollide[MAXPLAYERS + 1];
bool canJoin[MAXPLAYERS + 1], canIgnore[MAXPLAYERS + 1];
float lastPressedButtons[MAXPLAYERS + 1];
int CTSpawns, TSpawns;
float Spawns[5][MAXPLAYERS + 1][3];

//ZombieClass classes[MAX_CLASS];
int zClassHp[MAX_CLASS];
float zClassSpeed[MAX_CLASS], zClassGravity[MAX_CLASS], zClassDamage[MAX_CLASS];
char zClassName[MAX_CLASS][MAX_CLASS_NAME_SIZE], zClassDesc[MAX_CLASS][MAX_CLASS_DESC_SIZE],
zClassModel[MAX_CLASS][MAX_CLASS_DESC_SIZE], zClassArms[MAX_CLASS][MAX_CLASS_DESC_SIZE];
bool zClassExcluded[MAX_CLASS];

// Hint 

bool b_OverrideHint[MAXPLAYERS + 1];
char c_OverrideHintText[MAXPLAYERS + 1][MAX_HINT_SIZE];

char downloadFilesPath[PLATFORM_MAX_PATH];

Handle timerGhostHint[MAXPLAYERS + 1] = null, timerZombieRespawn[MAXPLAYERS + 1];
Handle forwardZombieSelected = null, forwardZombieRightClick = null;
Handle timerCountDown = INVALID_HANDLE;

int timerZombieRespawnLeft[MAXPLAYERS + 1];

Handle cvarRespawnTimeZ, cvarRespawnTimeZVip, cvarRespawnTimeS, cvarRespawnTimeSVip, cvarRoundStartZombies, cvarRoundKillsTeamJoinHumans;

bool isGhostCanSpawn, roundEnded;

int roundKillCounter;
int countdownNumber;

Handle cvarAlpha;

int collisionOffset;

int g_fLastButtons[MAXPLAYERS + 1 ];

float f_HintSpeed[MAXPLAYERS + 1 ];
int FogIndex = -1, SunIndex = -1, SkyCameraIndex = -1, CascadeLightIndex = -1;



char humansWinSounds[][] = 
{
    "zombie_mod/hwin1.mp3",
    "zombie_mod/hwin2.mp3",
    "zombie_mod/hwin3.mp3"
};

char zombiesWinSounds[][] = 
{
    "zombie_mod/zwin1.mp3",
    "zombie_mod/zwin2.mp3",
    "zombie_mod/zwin3.mp3"
};

char countdownSounds[][] = {
    "zombie_mod/countdown/1.mp3",
    "zombie_mod/countdown/2.mp3",
    "zombie_mod/countdown/3.mp3",
    "zombie_mod/countdown/4.mp3",
    "zombie_mod/countdown/5.mp3",
    "zombie_mod/countdown/6.mp3",
    "zombie_mod/countdown/7.mp3",
    "zombie_mod/countdown/8.mp3",
    "zombie_mod/countdown/9.mp3",
    "zombie_mod/countdown/10.mp3",
}

// Convars

ConVar cvarFog, cvarCountDown, cvarFogDensity, cvarFogStartDist, cvarFogEndDist, cvarFogColor, cvarFogZPlane,
       cvarOverlayCTWin, cvarOverlayTWin, cvarOverlayEnable;
       
// Fowards
Handle fw_ZSOnLoaded;

public void OnPluginStart()
{   
    cvarRespawnTimeZ = CreateConVar("zm_respawn_time_t", "3.0", "Vip players respawn time after team join or death");
    cvarRespawnTimeZVip = CreateConVar("zm_respawn_time_t_vip", "3.0", "Vip players respawn time after team join or death");
    cvarRespawnTimeS = CreateConVar("zm_respawn_time_ct", "60.0", "Players respawn time after team join or death");
    cvarRespawnTimeSVip = CreateConVar("zm_respawn_time_ct_vip", "55.0", "Vip players respawn time after team join or death");
    cvarRoundStartZombies = CreateConVar("zm_round_start_zombies", "5", "Round start zombies");
    cvarRoundKillsTeamJoinHumans = CreateConVar("zm_round_kills_teamjoin_humans", "25", "Human can join team after he is connected depends on round kills");
    
    // (UNSUPPORTED) SourceMod currently doesn't support this feature.
    // Added, but disabled by default
    cvarFog = CreateConVar("zm_env_fog", "0", "1 - Enable fog, 0 - Disable",_,true,0.0,true,1.0);
    cvarFogDensity = CreateConVar("zm_env_fogdensity", "0.65", "Toggle the density of the fog effects", _ , true, 0.0, true, 1.0);
    cvarFogStartDist = CreateConVar("zm_env_fogstart", "0", "Toggle how far away the fog starts", _ , true, 0.0, true, 8000.0);
    cvarFogEndDist = CreateConVar("zm_env_fogend", "500", "Toggle how far away the fog is at its peak", _ , true, 0.0, true, 8000.0);
    cvarFogColor = CreateConVar("zm_env_fogcolor", "200 200 200", "Modify the color of the fog" );
    cvarFogZPlane = CreateConVar("zm_env_zplane", "8000", "Change the Z clipping plane", _ , true, 0.0, true, 8000.0);

    cvarCountDown = CreateConVar("zm_countdown", "10", "Time then zombies will take class",_,true,1.0,true,10.0);
    
    cvarOverlayEnable = CreateConVar("zm_overlay_enable","1","1 - Enable, 0 - Disable",_,true,0.0,true,1.0);
    cvarOverlayCTWin = CreateConVar("zm_overlay_humans_win","overlays/swarm/humans_win","Show overlay then humans win");
    cvarOverlayTWin = CreateConVar("zm_overlay_zombies_win","overlays/swarm/zombies_win","Show overlay then zombies win");
    
    HookConVarChange(cvarFog, OnConVarChange);
    
    HookEvent("player_spawn", eventPlayerSpawn);
    HookEvent("round_start", eventRoundStartNoCopy, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", eventRoundFreezeEnd, EventHookMode_Post);
    HookEvent("cs_win_panel_round", eventWinPanelRound, EventHookMode_Pre);
    HookEvent("player_team", eventTeamChange, EventHookMode_Pre);
    HookEvent("player_death", eventPlayerDeath);
    HookEvent("round_end", eventRoundEnd);
    
    AddCommandListener( blockKill, "kill");
    AddCommandListener( blockKill, "spectate");
    AddCommandListener( blockKill, "explode");
    AddCommandListener( joinTeam, "jointeam");
    
    collisionOffset = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
    
    cvarAlpha = FindConVar("sv_disable_immunity_alpha");
    
    if(cvarAlpha != null) SetConVarInt(cvarAlpha, 1);
    
    // Configs
    BuildPath(Path_SM, downloadFilesPath, sizeof(downloadFilesPath), "configs/zm_downloads.txt");
    AutoExecConfig(true, "zombieswarm", "sourcemod/zombieswarm");
    CreateConVar("sm_zombieswarm_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NONE|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    Call_StartForward(fw_ZSOnLoaded);
    Call_Finish();
}
public void OnConVarChange(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (convar == cvarFog) {
        cvarFog.SetInt(StringToInt(newValue));
        FogEnable(cvarFog.BoolValue);
    }
    else if (convar == cvarFogDensity) {
    	float val = StringToFloat(newValue);
    	cvarFogDensity.SetFloat(val);
    	if (FogIndex != -1) {
    		DispatchKeyValueFloat(FogIndex, "fogmaxdensity", val);
        }
    }
    else if (convar == cvarFogStartDist) {
    	int val = StringToInt(newValue);
    	cvarFogStartDist.SetInt(val);
    	if (FogIndex != -1) {
			SetVariantInt(val);
			AcceptEntityInput(FogIndex, "SetStartDist");
    	}
    }
    else if (convar == cvarFogEndDist) {
    	int val = StringToInt(newValue);
    	cvarFogEndDist.SetInt(val);
    	if (FogIndex != -1) {
			SetVariantInt(val);
			AcceptEntityInput(FogIndex, "SetEndDist");
		}
    }
    else if (convar == cvarFogColor) {
    	cvarFogColor.SetString(newValue);
    	if (FogIndex != -1) {
			SetVariantString(newValue);
			AcceptEntityInput(FogIndex, "SetColor");
			SetVariantString(newValue);
			AcceptEntityInput(FogIndex, "SetColorSecondary");
    	}
    }
    else if (convar == cvarFogZPlane) {
    	int val = StringToInt(newValue);
    	cvarFogZPlane.SetInt(val);
    	if (FogIndex != -1) {
			SetVariantInt(val);
			AcceptEntityInput(FogIndex, "SetFarZ");
    	}
    }
    else if (convar == cvarCountDown) {
        int value = StringToInt(newValue) > 10?10:StringToInt(newValue);
        cvarCountDown.SetInt(value);
        countdownNumber = value;
    }
}
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Register mod library
    RegPluginLibrary("zombieswarm");

	 // Fowards
    forwardZombieSelected = CreateGlobalForward("onZCSelected", ET_Ignore, Param_Cell, Param_Cell);
    forwardZombieRightClick = CreateGlobalForward("onZRightClick", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
    
    CreateNative("isGhost", nativeIsGhost);
    CreateNative("getTeam", nativeGetTeam);
    CreateNative("setTeam", nativeSetTeam);
    CreateNative("getRandomZombieClass", nativeGetRandomZombieClass);

    // Our MethodMap

    // use MethodMapName.FunctionName format
    CreateNative("ZMPlayer.ZMPlayer", Native_ZMPlayer_Constructor);
    // Properties
    CreateNative("ZMPlayer.Client.get", Native_ZMPlayer_ClientGet);
    CreateNative("ZMPlayer.Level.get", Native_ZMPlayer_LevelGet);
    //CreateNative("ZMPlayer.Level.set", Native_ZMPlayer_LevelSet);
    CreateNative("ZMPlayer.XP.get", Native_ZMPlayer_XPGet);
    CreateNative("ZMPlayer.XP.set", Native_ZMPlayer_XPSet);
    CreateNative("ZMPlayer.Ghost.get", Native_ZMPlayer_GhostGet);
    CreateNative("ZMPlayer.Ghost.set", Native_ZMPlayer_GhostSet);
    CreateNative("ZMPlayer.Team.get", Native_ZMPlayer_TeamGet);
    CreateNative("ZMPlayer.Team.set", Native_ZMPlayer_TeamSet);
    CreateNative("ZMPlayer.ZombieClass.get", Native_ZMPlayer_ZMClassGet);
    CreateNative("ZMPlayer.ZombieClass.set", Native_ZMPlayer_ZMClassSet);
    CreateNative("ZMPlayer.LastButtons.get", Native_ZMPlayer_LastButtonsGet);
    CreateNative("ZMPlayer.LastButtons.set", Native_ZMPlayer_LastButtonsSet);
    CreateNative("ZMPlayer.OverrideHint.get", Native_ZMPlayer_OverrideHintGet);
    CreateNative("ZMPlayer.OverrideHint.set", Native_ZMPlayer_OverrideHintSet);
    // Functions
    CreateNative("ZMPlayer.OverrideHintText", Native_ZMPlayer_OverrideHintText);

    // Our MethodMap -> ZombieClass
    CreateNative("ZombieClass.ZombieClass", Native_ZombieClass_Constructor);
    // Class ID
    CreateNative("ZombieClass.ID.get", Native_ZombieClass_IDGet)
    // Properties
    CreateNative("ZombieClass.Health.get", Native_ZombieClass_HealthGet);
    CreateNative("ZombieClass.Health.set", Native_ZombieClass_HealthSet);
    CreateNative("ZombieClass.Speed.get", Native_ZombieClass_SpeedGet);
    CreateNative("ZombieClass.Speed.set", Native_ZombieClass_SpeedSet);
    CreateNative("ZombieClass.Gravity.get", Native_ZombieClass_GravityGet);
    CreateNative("ZombieClass.Gravity.set", Native_ZombieClass_GravitySet);
    CreateNative("ZombieClass.Damage.get", Native_ZombieClass_DamageGet);
    CreateNative("ZombieClass.Damage.set", Native_ZombieClass_DamageSet);
    CreateNative("ZombieClass.Excluded.get", Native_ZombieClass_ExcludedGet);
    CreateNative("ZombieClass.Excluded.set", Native_ZombieClass_ExcludedSet);
    // Functions
    CreateNative("ZombieClass.GetName", Native_ZombieClass_NameGet);
    CreateNative("ZombieClass.SetName", Native_ZombieClass_NameSet);
    CreateNative("ZombieClass.GetDesc", Native_ZombieClass_DescGet);
    CreateNative("ZombieClass.SetDesc", Native_ZombieClass_DescSet);
    CreateNative("ZombieClass.GetModel", Native_ZombieClass_ModelGet);
    CreateNative("ZombieClass.SetModel", Native_ZombieClass_ModelSet);
    CreateNative("ZombieClass.GetArms", Native_ZombieClass_ArmsGet);
    CreateNative("ZombieClass.SetArms", Native_ZombieClass_ArmsSet);
    
    fw_ZSOnLoaded = CreateGlobalForward("ZS_OnLoaded", ET_Ignore);

    return APLRes_Success;
}
public void OnEntityCreated(int entity, const char[] classname) {
    if(!entity)
        return;
    
    if (StrEqual("info_player_terrorist",classname)) {
        SDKHook(entity, SDKHook_SpawnPost, OnTsEntitySpawnPost);
    }
    else if (StrEqual("info_player_counterterrorist",classname)) {
        SDKHook(entity, SDKHook_SpawnPost, OnCTsEntitySpawnPost);
    }
    else if (StrEqual("sky_camera",classname)) {
        SDKHook(entity, SDKHook_SpawnPost, OnSkyCameraSpawnPost);
    }
    else if (StrEqual("env_cascade_light",classname)) {
        SDKHook(entity, SDKHook_SpawnPost, OnCascadeLightSpawnPost);
    }
}

public void OnTsEntitySpawnPost(int EntRef) {
    int entity = EntRefToEntIndex(EntRef);
    float Vec[3];
    
    GetEntPropVector(entity, Prop_Data, "m_vecOrigin", Vec);
    Vec[2] = (Vec[2] + 73);
    Spawns[CS_TEAM_T][TSpawns] = Vec;
    TSpawns++;
    
    SDKUnhook(entity, SDKHook_SpawnPost, OnTsEntitySpawnPost)
}
public void OnCTsEntitySpawnPost(int EntRef) {
    int entity = EntRefToEntIndex(EntRef);
    float Vec[3];

    GetEntPropVector(entity, Prop_Data, "m_vecOrigin", Vec);
    Vec[2] = (Vec[2] + 73);
    Spawns[CS_TEAM_CT][CTSpawns] = Vec;
    CTSpawns++;
    
    SDKUnhook(entity, SDKHook_SpawnPost, OnCTsEntitySpawnPost)
}
public void OnSkyCameraSpawnPost(int EntRef) {
    SkyCameraIndex = EntRefToEntIndex(EntRef);
    AcceptEntityInput(SkyCameraIndex, "Kill");
}
public void OnCascadeLightSpawnPost(int EntRef) {
    CascadeLightIndex = EntRefToEntIndex(EntRef);
}
public void OnMapEnd() {
    float Vec[3];
    Vec[0] = 0.0;
    Vec[1] = 0.0;
    Vec[2] = 0.0;
    for (int i = 0; i <= TSpawns; i++) {
        Spawns[CS_TEAM_T][i] = Vec;
    }
    for (int i = 0; i <= CTSpawns; i++) {
        Spawns[CS_TEAM_T][i] = Vec;
    }
    
    TSpawns = 0;
    CTSpawns = 0;
}
public void OnMapStart()
{
    roundEnded = false;
    
    countdownNumber = cvarCountDown.IntValue > 10?10:cvarCountDown.IntValue;
    
    PrecacheModel(DEFAULT_ARMS);
    
    char soundsPath[PLATFORM_MAX_PATH];
    
    for(int s = 0; s < sizeof(humansWinSounds); s++)
    {
        Format(soundsPath, PLATFORM_MAX_PATH, "sound/%s", humansWinSounds[s]);
        
        if( FileExists(soundsPath) )
        {
            FakePrecacheSoundEx(humansWinSounds[s]);
            AddFileToDownloadsTable( soundsPath );
        }
        else
        {
            LogError("Cannot locate sounds file '%s'", soundsPath);
        }
    }
    
    for(int s = 0; s < sizeof(zombiesWinSounds); s++)
    {
        Format(soundsPath, PLATFORM_MAX_PATH, "sound/%s", zombiesWinSounds[s]);
        
        if( FileExists(soundsPath) )
        {
            FakePrecacheSoundEx(zombiesWinSounds[s]);
            AddFileToDownloadsTable( soundsPath );
        }
        else
        {
            LogError("Cannot locate sounds file '%s'", soundsPath);
        }
    }
    
    for(int s = 0; s < sizeof(countdownSounds); s++)
    {
        Format(soundsPath, PLATFORM_MAX_PATH, "sound/%s", countdownSounds[s]);
        
        if( FileExists(soundsPath) )
        {
            FakePrecacheSoundEx(countdownSounds[s]);
            AddFileToDownloadsTable( soundsPath );
        }
        else
        {
            LogError("Cannot locate sounds file '%s'", soundsPath);
        }
    }
    

    FakePrecacheSoundEx("sound/radio/terwin.wav");
    FakePrecacheSoundEx("sound/radio/ctwin.wav");
    
    char overlay_ct[125], overlay_t[125];
    cvarOverlayTWin.GetString(overlay_t,sizeof(overlay_t));
    cvarOverlayCTWin.GetString(overlay_ct,sizeof(overlay_ct));
    
    PrecacheDecalAnyDownload(overlay_t);
    PrecacheDecalAnyDownload(overlay_ct);
    
    // Set team names
    SetConVarString(FindConVar("mp_teamname_1"), "HUMANS");
    SetConVarString(FindConVar("mp_teamname_2"), "ZOMBIES");
    
    // Get round time
    float roundTime = GetConVarFloat(FindConVar("mp_roundtime"));
    
    // Bug fix for standart maps
    SetConVarFloat(FindConVar("mp_roundtime_hostage"), roundTime);
    SetConVarFloat(FindConVar("mp_roundtime_defuse"),  roundTime);
    
    // Remove free armor
    SetConVarInt(FindConVar("mp_free_armor"), 0);
    
    SetConVarInt(FindConVar("mp_timelimit"), 20);
    SetConVarInt(FindConVar("mp_maxrounds"), 0);
    SetConVarInt(FindConVar("mp_friendlyfire"), 0);

    int ent; 
    ent = FindEntityByClassname(-1, "env_fog_controller");
    if (ent != -1)  {
        FogIndex = ent;
    }
    else {
        FogIndex = CreateEntityByName("env_fog_controller");
        DispatchSpawn(FogIndex);
    }

    SunIndex = FindEntityByClassname(-1, "env_sun");

    CreateFog();
    FogEnable(cvarFog.BoolValue);
    
    // Initialize some chars
    char zBuffer[PLATFORM_MAX_PATH];

    //**********************************************
    //* Zombie class precache                          *
    //**********************************************
    for(int zClass = 0; zClass < numClasses; zClass++)
    {
        //****************  Player ****************//
        // Path should be models/player/custom_player/cso2_zombi/zombie
        
        Format(zBuffer, sizeof(zBuffer), "%s.mdl", zClassModel[zClass]);
        PrecacheModel(zBuffer);
        AddFileToDownloadsTable(zBuffer);

        Format(zBuffer, sizeof(zBuffer), "%s.dx90.vtx", zClassModel[zClass]);
        AddFileToDownloadsTable(zBuffer);
        
        Format(zBuffer, sizeof(zBuffer), "%s.phy", zClassModel[zClass]);
        AddFileToDownloadsTable(zBuffer);
        
        Format(zBuffer, sizeof(zBuffer), "%s.vvd", zClassModel[zClass]);
        AddFileToDownloadsTable(zBuffer);
        
        if (strlen(zClassArms[zClass])) {
            Format(zBuffer,sizeof(zBuffer),"%s",zClassArms[zClass]);
            AddFileToDownloadsTable(zBuffer);
        }
    }

    // Open file
    File iDocument = OpenFile(downloadFilesPath, "r");
    
    // Initialize chars
    char szBuffer[PLATFORM_MAX_PATH];
    int szBufferText = sizeof(szBuffer);
    
    // If doesn't exist turn off server
    if(iDocument == null)
    {
        SetFailState("[ZM] File zm_downloads.txt doesn't exist!\n\n");
        return;
    }
    
    // Read through file
    while (ReadFileLine(iDocument, szBuffer, szBufferText))
    {    
        // If end of file, stop
        if (IsEndOfFile(iDocument))
        break;

        // If char long, make sure that it will be split
        int iLength = strlen(szBuffer);
        
        if (szBuffer[iLength-1] == '\n')
        {
            szBuffer[--iLength] = '\0';
        }
        
        // Removes whitespace at the begin and end of char
        TrimString(szBuffer);
        
        // If char have commentaries, skip
        if(StrContains(szBuffer, "//", false) != -1 || StrContains(szBuffer, "/*", false) != -1 || StrContains(szBuffer, ";", false) != -1)
        continue;
        
        // Read not empty char
        if(!StrEqual(szBuffer, "", false))
        {
            AddFileToDownloadsTable(szBuffer);
        }
    }
    
    if(iDocument != null)
    {
        // We're done with this file now, so we can close it
        delete iDocument;
    }
}

void CreateFog() {
    if(FogIndex != -1)  {
        float FogDensity = GetConVarFloat(cvarFogDensity);
        int FogStartDist = GetConVarInt(cvarFogStartDist);
        int FogEndDist = GetConVarInt(cvarFogEndDist);
        int FogZPlane = GetConVarInt(cvarFogZPlane);
        DispatchKeyValueFloat(FogIndex, "fogmaxdensity", FogDensity);
        SetVariantInt(FogStartDist);
        AcceptEntityInput(FogIndex, "SetStartDist");
        SetVariantInt(FogEndDist);
        AcceptEntityInput(FogIndex, "SetEndDist");
        SetVariantInt(FogZPlane);
        AcceptEntityInput(FogIndex, "SetFarZ");
    
        char FogColor[32];
        GetConVarString(cvarFogColor, FogColor, sizeof(FogColor));    

        SetVariantString(FogColor);
        AcceptEntityInput(FogIndex, "SetColor");
        
        SetVariantString(FogColor);
        AcceptEntityInput(FogIndex, "SetColorSecondary");
        
    }
}

void FogEnable(bool status) {
    if (FogIndex != -1) {
        if (status) {
            AcceptEntityInput(FogIndex, "TurnOn");
        }
        else
            AcceptEntityInput(FogIndex, "TurnOff");
    }
    
    if (SunIndex != -1) {
        if (status)
            AcceptEntityInput(SunIndex, "TurnOff");
        else
            AcceptEntityInput(SunIndex, "TurnOn");
    }
    
    if (status) {
        AcceptEntityInput(CascadeLightIndex, "Disable");
        SetLightStyle(0,"a");
    }
    else {
        AcceptEntityInput(CascadeLightIndex, "Enable");
        SetLightStyle(0,"");
    }
    
    DispatchKeyValue(0, "skyname", "embassy");
}

public void OnGameFrame()
{
    int client;
    for (client = 1; client <= MaxClients; client++) 
    {
        if (IsValidClient(client)) {
            int target = isPlayerStuck(client); 
            
            if (target < 0) {
                shouldCollide[client] = false;
            } else {
                if (IsValidClient(target) && (b_isGhost[client] || b_isGhost[target])) {
                    //if (IsValidClient(target)) {
                    shouldCollide[target] = true;
                    shouldCollide[client] = true;
                }
            }
        }
    }
}

/*public void OnClientPutInServer(client)
{

}*/

public void OnClientPostAdminCheck(int client)
{
    canJoin[client] = true;
    canIgnore[client] = false;
    
    lastPressedButtons[client] = 0.0
    
    SDKHook(client, SDKHook_OnTakeDamage, onTakeDamage);
    SDKHook(client, SDKHook_TraceAttack, onTraceAttack);
    SDKHook(client, SDKHook_WeaponCanUse, onWeaponCanUse);
    // Ghost mod related
    SDKHook(client, SDKHook_ShouldCollide, onShouldCollide);
    SDKHook(client, SDKHook_SetTransmit, onSetTransmit);
    //SDKHook(client, SDKHook_StartTouch, onTouch);
    //SDKHook(client, SDKHook_Touch, onTouch);
    SDKHook(client, SDKHook_PostThinkPost, onPostThinkPost);
}

public void OnClientDisconnect(int client)
{
    if ( IsClientInGame(client) )
    {
        canJoin[client] = false;
        canIgnore[client] = false;
        
        pTeam[client] = CS_TEAM_NONE;

        b_OverrideHint[client] = false;
        
        if (timerGhostHint[client] != null) {
            delete timerGhostHint[client];
        }
        
        if (timerZombieRespawn[client] != null) {
            delete timerZombieRespawn[client];
        }
        timerZombieRespawnLeft[client] = 0;
        g_fLastButtons[client] = 0;
    }
}

public void onPostThinkPost(int client)
{
    if(b_isGhost[client]) {
        SetEntData(client, collisionOffset, 2, 1, true);
    } else {
        SetEntData(client, collisionOffset, 5, 4, true);
    }
}

public Action onWeaponCanUse(int client, int weapon)
{
    if ( !IsValidAlive(client) )
    return Plugin_Handled;
    
    char sWeapon[32];
    GetEdictClassname(weapon, sWeapon, sizeof(sWeapon));
    
    if (GetClientTeam(client) == CS_TEAM_T && !(StrContains(sWeapon, "knife")>=0)) {
        return Plugin_Handled;
    }
    
    return Plugin_Continue;
}

public Action onTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if ( !IsValidClient(victim) )
    return Plugin_Continue;
    
    if (GetClientTeam(victim) == CS_TEAM_T) {
        if (damagetype & DMG_FALL)
        return Plugin_Handled;
    }
    
    if ( !IsValidClient(attacker) )
    return Plugin_Continue;
    
    if (victim == attacker)
    return Plugin_Continue;
    
    if (roundEnded)
    return Plugin_Handled;
    
    if (b_isGhost[victim] || b_isGhost[attacker])
    return Plugin_Handled;
    
    if (GetClientTeam(victim) == CS_TEAM_CT) {
        char sWeapon[32];
        GetClientWeapon(attacker, sWeapon, sizeof(sWeapon));
        if(StrContains(sWeapon, "knife")>=0) {
            damage = zClassDamage[zombieClass[attacker]];
            return Plugin_Changed;
        }
    }
    // If both players in tunnel (ducking), lets give zombie some advantage by making human dmg lower.
    if (GetClientTeam(victim) == CS_TEAM_T && GetClientTeam(attacker) == CS_TEAM_CT && GetEntityFlags(victim) & FL_DUCKING && GetEntityFlags(attacker) & FL_DUCKING) {
        damage *= 0.33;
        return Plugin_Changed;
    }
    
    return Plugin_Continue;

}

public Action onTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    if ( !IsValidClient(victim) )
    return Plugin_Continue;
    
    if ( !IsValidClient(attacker) )
    return Plugin_Continue;
    
    if (victim == attacker)
    return Plugin_Continue;
    
    if (roundEnded)
    return Plugin_Handled;
    
    if (b_isGhost[victim] || b_isGhost[attacker])
    return Plugin_Handled;
    
    return Plugin_Continue;
}

public Action onSetTransmit(int entity, int client) 
{
    if ( !IsValidAlive(entity) || !IsValidAlive(client) ) return Plugin_Continue;
    
    if (entity == client) return Plugin_Continue;
    
    if ( pTeam[entity] != pTeam[client] && !b_isGhost[client]
            && pTeam[entity] == CS_TEAM_T && b_isGhost[entity] )
    return Plugin_Handled; 
    
    // Hide near human for ghost zombie    
    if ( pTeam[entity] != pTeam[client] && !b_isGhost[entity]
            && GetClientTeam(client) == CS_TEAM_T && b_isGhost[client] && shouldCollide[client] && shouldCollide[entity] )
    return Plugin_Handled; 
    
    if (pTeam[entity] == pTeam[client] && !b_isGhost[client] && pTeam[entity] == CS_TEAM_T 
            && b_isGhost[entity])
    return Plugin_Handled;
    
    if (pTeam[entity] == pTeam[client] && b_isGhost[client] && pTeam[entity] == CS_TEAM_T 
            && b_isGhost[entity] && shouldCollide[client] && shouldCollide[entity])
    return Plugin_Handled;
    
    return Plugin_Continue;
}

public bool onShouldCollide(int entity, int collisiongroup, int contentsmask, bool result ) 
{
    if (shouldCollide[entity]) {
        collisiongroup = 2;
        contentsmask = (CONTENTS_SOLID | CONTENTS_MOVEABLE | CONTENTS_PLAYERCLIP | CONTENTS_WINDOW | CONTENTS_MONSTER | CONTENTS_GRATE | CONTENTS_TEAM1 | CONTENTS_TEAM2);
        result = false;
        return false;
    }

    result = true;
    return true;
}

public void onTouch(int ent1, int ent2)
{
    if(ent1 == ent2)
    return;
    
    if(!IsValidClient(ent1))
    return;
    
    if(!IsValidClient(ent2))
    return;
    
    //if(pTeam[ent1] != pTeam[ent2] && b_isGhost[ent1])
    if(pTeam[ent1] != pTeam[ent2])
    {
        shouldCollide[ent1] = true;
        shouldCollide[ent2] = true;
        return;
    }
    
    shouldCollide[ent1] = false;
    shouldCollide[ent2] = false;
}

public Action blockKill(int client, const char[] command, int argc)
{
    return Plugin_Handled;
}

public Action joinTeam(int client, const char[] command, int argc)
{
    if (IsFakeClient(client))
    return Plugin_Continue;
    
    if (!IsValidClient(client)) 
    return Plugin_Handled;
    
    if (IsPlayerAlive(client)) 
    return Plugin_Handled;
    
    if (IsClientSourceTV(client)) 
    return Plugin_Handled;
    
    if (!canJoin[client])
    return Plugin_Handled;
    
    char sTeam[4];
    GetCmdArg( 1, sTeam, sizeof(sTeam));
    int iTeam = StringToInt(sTeam);

    if ( iTeam == CS_TEAM_CT || iTeam == CS_TEAM_T || iTeam == CS_TEAM_NONE
            || iTeam == CS_TEAM_SPECTATOR ) {
        canJoin[client] = false;
        
        if (getHumans() >= GetConVarInt(cvarRoundStartZombies)) {
            CS_SwitchTeam( client, CS_TEAM_T );
            CreateTimer( 0.5, respawnClientOnConnect, client, TIMER_FLAG_NO_MAPCHANGE);
        } else {
            if ( getHumans() > getZombies() ) {
                CS_SwitchTeam( client, CS_TEAM_T );    
                CreateTimer( 0.5, respawnClientOnConnect, client, TIMER_FLAG_NO_MAPCHANGE);
            } else {
                CS_SwitchTeam( client, CS_TEAM_CT );
                if ( roundKillCounter < GetConVarInt(cvarRoundKillsTeamJoinHumans) )    
                CreateTimer( 0.5, respawnClientOnConnect, client, TIMER_FLAG_NO_MAPCHANGE);
            }
        }

        if(getTrueCT() == getTrueT()) {
            pTeam[client] = CS_TEAM_CT;
        } else if (getTrueCT() > getTrueT()) {
            pTeam[client] = CS_TEAM_T;
        } else {
            pTeam[client] = CS_TEAM_CT;
        }


    }
    
    return Plugin_Handled;
}

public void eventPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    roundKillCounter++;
    
    int victim = GetClientOfUserId(GetEventInt(event, "userid"));

    if ( !IsValidClient(victim) )
    return;
    if (IsClientSourceTV(victim)) 
    return;

    if (timerGhostHint[victim] != null) {
        delete timerGhostHint[victim];
    }
    if (GetClientTeam(victim) == CS_TEAM_CT && getHumans() > 1) {
        canIgnore[victim] = true;
        //CS_SwitchTeam( victim, CS_TEAM_T );
        timerZombieRespawnLeft[victim] = (IsClientVip(victim)) ? GetConVarInt(cvarRespawnTimeSVip) : GetConVarInt(cvarRespawnTimeS);
        timerZombieRespawn[victim] = CreateTimer( 1.0, timerZombieRespawnCallback, victim, TIMER_FLAG_NO_MAPCHANGE);
    } else if (GetClientTeam(victim) == CS_TEAM_T) {
        timerZombieRespawnLeft[victim] = (IsClientVip(victim)) ? GetConVarInt(cvarRespawnTimeZVip) : GetConVarInt(cvarRespawnTimeZ);
        timerZombieRespawn[victim] = CreateTimer( 1.0, timerZombieRespawnCallback, victim, TIMER_FLAG_NO_MAPCHANGE);
    }
}

stock bool IsClientVip(int client)
{
    if (GetUserFlagBits(client) & ADMFLAG_RESERVATION || GetUserFlagBits(client) & ADMFLAG_ROOT) 
    return true;
    return false;
}

public void eventPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    if ( !IsValidAlive(client) )
    return;
    
    if (timerZombieRespawn[client] != null) {
        delete timerZombieRespawn[client];
    }
    
    f_HintSpeed[client] = TIMER_SPEED;
    b_OverrideHint[client] = false;

    timerZombieRespawnLeft[client] = 0;
    
    SetEntData(client, collisionOffset, 2, 1, true);
    
    setZombieGhostMode(client, false);

    if (GetClientTeam(client) == CS_TEAM_T) {
        
        // Set zombie ghost mode
        setZombieGhostMode(client, true);
        
        timerGhostHint[client] = CreateTimer( 1.0, ghostHint, client, TIMER_FLAG_NO_MAPCHANGE);

        // Set random zombie class
        zombieClass[client] = getRandZombieClass();
        
        setZombieClassParameters(client);
        
        callZombieSelected(client, zombieClass[client]);
        
        //CreateTimer( 0.1, teleportZombieToHuman, client, TIMER_FLAG_NO_MAPCHANGE );
    } else if (GetClientTeam(client) == CS_TEAM_CT) {
        SetEntityGravity(client, 0.8); 
    }
    // Hide RADAR
    CreateTimer(0.0, RemoveRadar, client);
}

public Action eventRoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    isGhostCanSpawn = false;
    if (timerCountDown != INVALID_HANDLE) {
        KillTimer(timerCountDown);
    }
    
    timerCountDown = CreateTimer(1.0, CountDown, _, TIMER_REPEAT);
}

public Action eventRoundStartNoCopy(Event event, const char[] name, bool dontBroadcast)
{
    
    roundKillCounter = 0;
    
    roundEnded = false;
    
    isGhostCanSpawn = false;
    
    int ent = -1;
    while((ent = FindEntityByClassname(ent, "light"))!=-1){
        AcceptEntityInput(ent, "TurnOff");
        break;
    }
    
    // Names of entities, which will be remove every round
    #define ROUNDSTART_OBJECTIVE_ENTITIES "func_bomb_target_hostage_entity_func_hostage_rescue_func_buyzoneprop_physics_overrideprop_physics_multiplayer"
    
    // Removes all entities with a targetname that match in ROUNDSTART_OBJECTIVE_ENTITIES,
    // and removes them, so standart map will avalible for playing
    removeMapEventEntity(ROUNDSTART_OBJECTIVE_ENTITIES); 
    
    ZS_ShowOverlayToAll("");
}

public Action eventWinPanelRound(Event event, const char[] name, bool dontBroadcast)
{
    // Set dont broadcast for panel
    if(dontBroadcast == false) 
    {
        SetEventBroadcast(event, true); 
    }
    
    return Plugin_Continue; 
}

public void eventRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    roundKillCounter = 0;
    
    roundEnded = true;
    
    int winner = GetEventInt(event, "winner");
    
    for (int client = 1; client <= MaxClients; client++) 
    { 
        if (IsValidClient(client) )
        {    
            if (timerZombieRespawn[client] != null) {
                delete timerZombieRespawn[client];
            }

            timerZombieRespawnLeft[client] = 0;
            
            /*StopSound(client, SNDCHAN_STATIC, "radio/ctwin.wav");
            StopSound(client, SNDCHAN_STATIC, "radio/rounddraw.wav");
            StopSound(client, SNDCHAN_STATIC, "radio/terwin.wav");*/
            
            char overlay[125];
            
            if(winner == CS_TEAM_T) {
                int randomSound = GetRandomInt(0, sizeof(zombiesWinSounds)-1);
                cvarOverlayTWin.GetString(overlay,sizeof(overlay));
                
                playClientCommandSound(client, zombiesWinSounds[randomSound]);
            } else if(winner == CS_TEAM_CT) {
                int randomSound = GetRandomInt(0, sizeof(humansWinSounds)-1);
                cvarOverlayCTWin.GetString(overlay,sizeof(overlay));
                
                playClientCommandSound(client, humansWinSounds[randomSound]);
            }
            
            if (cvarOverlayEnable.BoolValue) {
            	if (strlen(overlay) > 0) {
            		ShowOverlayAll(overlay,5.0);
            	}
            }
        }
    }

    // Use custom plugin for handling it.
    //setTeamBalance();
}



public Action eventTeamChange(Event event, const char[] name, bool dontBroadcast)
{
    //int client = GetClientOfUserId(GetEventInt(event, "userid"));
    //int team = GetEventInt(event, "team");
    
    // Block change team message
    if(!dontBroadcast) 
    { 
        // Execute event and block it
        Event sEvent = CreateEvent("player_team", true);  

        SetEventInt(sEvent, "userid", GetEventInt(event, "userid")); 
        SetEventInt(sEvent, "team", GetEventInt(event, "team")); 
        SetEventInt(sEvent, "oldteam", GetEventInt(event, "oldteam")); 
        SetEventBool(sEvent, "disconnect", GetEventBool(event, "disconnect")); 
        
        FireEvent(sEvent, true); 
    }
    
    return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float velocity[3], float angles[3], int &weapon, int &subtype, int &cmdNum, int &tickCount, int &seed, int mouse[2])
{
    if ( !IsValidAlive(client) )
    return Plugin_Continue;
    
    if (GetClientTeam(client) == CS_TEAM_T) {
        if (b_isGhost[client]) {
            float currentTime = GetGameTime();
            
            if (currentTime - lastPressedButtons[client] < 2.0)
            {
                g_fLastButtons[client] = buttons;
                return Plugin_Continue;
            }
            
            /*if((buttons & IN_USE))
            {
                float targetOrigin[3], changedTargetOrigin[3];
                
                int rClient = getRandomClient();
                if (rClient > 0)
                {
                    GetClientAbsOrigin(rClient, targetOrigin);
                    
                    changedTargetOrigin[0] = targetOrigin[0];
                    changedTargetOrigin[1] = targetOrigin[1];
                    changedTargetOrigin[2] = targetOrigin[2];
                    
                    int isStuck = getPlayerStuckVector(client, changedTargetOrigin)
                    if (isStuck < 0) {
                        targetOrigin[0] = changedTargetOrigin[0];
                        targetOrigin[1] = changedTargetOrigin[1];
                        targetOrigin[2] = changedTargetOrigin[2];
                    } else {
                        
                    }
                    
                    TeleportEntity(client, targetOrigin, NULL_VECTOR, NULL_VECTOR);
                }
                
                lastPressedButtons[client] = currentTime;
            }*/
            
            if ((buttons & IN_ATTACK)) {
                if (!IsClientInTargetsView(client)) {
                    if (isGhostCanSpawn) {
                        setZombieGhostMode(client, false);
                        
                        // Set zombie speed
                        SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", zClassSpeed[zombieClass[client]]);
                        
                        showHintMessage(client, "<font color='#FFFFFF'>You've been revived! Slash and Smash!</font>");
                    } else {
                        showHintMessage(client, "<font color='#FF0000'>Wait a little bit! <br/> Players are warming up.</font>");
                    }
                } else {
                    showHintMessage(client, "<font color='#FF0000'>Hide from humans to respawn!</font>");
                }
                
                lastPressedButtons[client] = currentTime;
            }
            if ((buttons & IN_RELOAD)) {
                if (TSpawns > 0) {
                    int random = GetRandomInt(0,TSpawns);
                    float spawn[3];
                    spawn = Spawns[CS_TEAM_T][random];
                    if (IsValidClient(client) && b_isGhost[client] && (spawn[0] != 0.0 && spawn[1] != 0.0 && spawn[2] != 0.0))
                        TeleportEntity(client, spawn, NULL_VECTOR, NULL_VECTOR);
                }
                else {
                    CPrintToChat(client,"{red}No valid spawns found. Can't teleport");
                }
            }
        } else {
            if(!(buttons & IN_ATTACK2))
            {
                g_fLastButtons[client] = buttons;
                return Plugin_Continue;
            }
            
            char sWeapon[32];
            GetClientWeapon(client, sWeapon, sizeof(sWeapon));

            if(StrContains(sWeapon, "knife")>=0)
            {
                callZombieRightClick(client, zombieClass[client], buttons);
                g_fLastButtons[client] = buttons;
                buttons &= ~IN_ATTACK2;
                // disable animation
                int iWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
                if(IsValidEntity(iWeapon))
                SetEntPropFloat(iWeapon, Prop_Send, "m_flNextSecondaryAttack", 99999.0);
                return Plugin_Changed;
            }
            g_fLastButtons[client] = buttons;
            return Plugin_Continue;
        }
    }
    g_fLastButtons[client] = buttons;
    return Plugin_Continue;
}

public Action teleportZombieToHuman(Handle timer, any client)
{
    if ( !IsValidAlive(client) || pTeam[client] != CS_TEAM_T || !b_isGhost[client] ) {
        return Plugin_Continue;
    }
    
    float targetOrigin[3], changedTargetOrigin[3];
    
    int rClient = getRandomClient();
    if (IsValidClient(rClient))
    {
        GetClientAbsOrigin(rClient, targetOrigin);
        changedTargetOrigin[0] = targetOrigin[0];
        changedTargetOrigin[1] = targetOrigin[1];
        changedTargetOrigin[2] = targetOrigin[2];
        
        int isStuck = getPlayerStuckVector(client, changedTargetOrigin)
        if (isStuck < 0) {
            targetOrigin[0] = changedTargetOrigin[0];
            targetOrigin[1] = changedTargetOrigin[1];
            targetOrigin[2] = changedTargetOrigin[2];
        } else {
            
        }
        
        TeleportEntity(client, targetOrigin, NULL_VECTOR, NULL_VECTOR);
    }

    return Plugin_Continue;
}

public Action RemoveRadar(Handle timer, any client) 
{
    if ( !IsValidAlive(client) )
    return Plugin_Continue;

    SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | HIDEHUD_RADAR);
    
    return Plugin_Continue;
} 

public Action ghostHint(Handle timer, any client)
{
    timerGhostHint[client] = null;

    if ( !IsValidAlive(client) || GetClientTeam(client) != CS_TEAM_T )
    return Plugin_Continue;
    
    if (b_OverrideHint[client]) {
        showHintMessage(client, c_OverrideHintText[client]);
    }
    else if (b_isGhost[client]) {
        showHintMessage(client, "<font color='#FFFFFF'>Currently you are a ghost</font>\n<font color='#00FF00'>E</font><font color='#FFFFFF'> to teleport.\n<font color='#00FF00'>MOUSE1</font><font color='#FFFFFF'> to spawn.</font>");
    } else {
        char sHintText[196];
        Format(sHintText, sizeof(sHintText), "<font color='#00FF00'>%s</font><br/><font color='#FFFFFF'>%s</font>", zClassName[zombieClass[client]], zClassDesc[zombieClass[client]]);
        
        showHintMessage(client, sHintText);
    }
    
    timerGhostHint[client] = CreateTimer( f_HintSpeed[client], ghostHint, client, TIMER_FLAG_NO_MAPCHANGE);
    
    return Plugin_Continue;
}

public Action respawnClientOnConnect( Handle timer, any client )
{
    if ( !IsValidClient(client) || IsPlayerAlive(client) )
    {
        return Plugin_Continue;
    }
    
    CS_RespawnPlayer( client );
    
    return Plugin_Continue;
}

public Action timerZombieRespawnCallback( Handle timer, any client )
{    
    timerZombieRespawn[client] = null;
    if ( !IsValidClient(client) )
    return Plugin_Continue;
    
    if (IsPlayerAlive(client))
    return Plugin_Continue;

    if (GetClientTeam(client) == CS_TEAM_SPECTATOR) {
        return Plugin_Continue;
    }

    if (timerZombieRespawnLeft[client] == 0) {
        CS_RespawnPlayer( client );
        showHintMessage(client, "<font color='#FF0000'>Go Go Go!</font>");
    } else {
        char sHintText[196];
        Format(sHintText, sizeof(sHintText), "<font color='#FF0000'>Respawn cooldown! <br/> Wait for %i seconds</font>", timerZombieRespawnLeft[client]);
        showHintMessage(client, sHintText);
        timerZombieRespawnLeft[client]--;
        timerZombieRespawn[client] = CreateTimer( 1.0, timerZombieRespawnCallback, client, TIMER_FLAG_NO_MAPCHANGE);
    }
    
    return Plugin_Continue;
}

public bool IsClientInTargetsView(int client)
{
    int target;
    for (target = 1; target <= MaxClients; target++) 
    {
        if ( IsValidAlive(target) && IsClientInTargetView(client, target) && pTeam[target] == CS_TEAM_CT ) {
            return true;
        }
    }
    
    return false;
}
/*public bool IsClientInTargetView(int client, int target)
{
    float playerOrigin[3];

    bool HitPlayer = false;
    
    float targetOrigin[3], distanceBetween;

    GetClientAbsOrigin( client, playerOrigin);
    GetClientAbsOrigin ( target, targetOrigin );
    distanceBetween = GetVectorDistance ( targetOrigin, playerOrigin );
    
    if ( distanceBetween <= 200.0 )
    {
        HitPlayer = true
        return HitPlayer;
    }
    
    targetOrigin[0] -= 20.0;
    targetOrigin[2] -= 0.0;
    
    playerOrigin[0] -= 20.0
    playerOrigin[2] -= 0.0
    
    for(int pos = 0; pos <= 11; pos++) // Check for position
    {
        targetOrigin[0] += 2.5;
        targetOrigin[2] += 6.0;
        
        playerOrigin[0] += 2.5;
        playerOrigin[2] += 6.0;
        
        Handle trace = TR_TraceRayFilterEx( playerOrigin, targetOrigin, MASK_SOLID, RayType_EndPoint, TraceEntityFilterRay);
        
        if ( !TR_DidHit(trace) )
        {
            HitPlayer = true;
        }

        delete trace;
    }

    return HitPlayer;
}*/

public int isPlayerStuck(int client)
{
    int index = -1;

    float vecMin[3], vecMax[3], vecOrigin[3];
    
    GetClientMins(client, vecMin);
    GetClientMaxs(client, vecMax);
    
    GetClientAbsOrigin(client, vecOrigin);
    
    vecOrigin[0] -= 10.0
    vecOrigin[1] -= 10.0
    vecOrigin[2] -= 0.0
    
    for(int pos = 0; pos <= 11; pos++) // Check for position
    {            
        vecOrigin[0] += 2.5;
        vecOrigin[1] += 2.5;
        vecOrigin[2] += 6.0;
        
        Handle trace = TR_TraceHullFilterEx(vecOrigin, vecOrigin, vecMin, vecMax, MASK_SOLID, TraceEntityFilterHull, client);
        
        if(TR_DidHit(trace))
        {
            index = TR_GetEntityIndex( trace );
        }
        
        delete trace;
    }
    
    return index;
}

public int getPlayerStuckVector(int client, float vecOrigin[3])
{
    int index = -1;

    float vecMin[3], vecMax[3], vecSaved[3];
    
    GetClientMins(client, vecMin);
    GetClientMaxs(client, vecMax);
    
    vecSaved[0] = vecOrigin[0] // x
    vecSaved[1] = vecOrigin[1] // y
    vecSaved[2] = vecOrigin[2]    
    
    vecOrigin[0] -= 100.0 // x
    vecOrigin[1] -= 0.0 // y
    vecOrigin[2] -= 0.0
    
    for(int pos = 0; pos <= 11; pos++) // Check for position
    {            
        vecOrigin[0] += 10.5;
        vecOrigin[1] += 10.5;
        vecOrigin[2] += 10.0;
        
        Handle trace = TR_TraceHullFilterEx(vecOrigin, vecOrigin, vecMin, vecMax, MASK_PLAYERSOLID, TraceEntityFilterHull, client);
        
        if(TR_DidHit(trace))
        {
            index = 1;
        } else {
            index = -1;
            delete trace;
            break;
        }
        
        delete trace;
    }
    
    vecOrigin[0] = vecSaved[0] // x
    vecOrigin[1] = vecSaved[1] // y
    vecOrigin[2] = vecSaved[2]

    vecOrigin[0] -= 100.0 // x
    vecOrigin[1] -= 100.0 // y
    vecOrigin[2] -= 0.0
    
    for(int pos = 0; pos <= 11; pos++) // Check for position
    {            
        vecOrigin[0] += 10.5;
        vecOrigin[1] += 10.5;
        vecOrigin[2] += 10.0;
        
        Handle trace = TR_TraceHullFilterEx(vecOrigin, vecOrigin, vecMin, vecMax, MASK_PLAYERSOLID, TraceEntityFilterHull, client);
        
        if(TR_DidHit(trace))
        {
            index = 1;
        } else {
            index = -1;
            delete trace;
            break;
        }
        
        delete trace;
    }
    
    vecOrigin[0] = vecSaved[0] // x
    vecOrigin[1] = vecSaved[1] // y
    vecOrigin[2] = vecSaved[2]

    vecOrigin[0] -= 0.0 // x
    vecOrigin[1] -= 100.0 // y
    vecOrigin[2] -= 0.0
    
    for(int pos = 0; pos <= 11; pos++) // Check for position
    {            
        vecOrigin[0] += 10.5;
        vecOrigin[1] += 10.5;
        vecOrigin[2] += 10.0;
        
        Handle trace = TR_TraceHullFilterEx(vecOrigin, vecOrigin, vecMin, vecMax, MASK_PLAYERSOLID, TraceEntityFilterHull, client);
        
        if(TR_DidHit(trace))
        {
            index = 1;
        } else {
            index = -1;
            delete trace;
            break;
        }
        
        delete trace;
    }
    
    vecOrigin[0] = vecSaved[0] // x
    vecOrigin[1] = vecSaved[1] // y
    vecOrigin[2] = vecSaved[2]

    vecOrigin[0] -= 0.0 // x
    vecOrigin[1] -= 0.0 // y
    vecOrigin[2] -= 0.0
    
    for(int pos = 0; pos <= 11; pos++) // Check for position
    {            
        vecOrigin[0] += 10.5;
        vecOrigin[1] += 10.5;
        vecOrigin[2] += 10.0;
        
        Handle trace = TR_TraceHullFilterEx(vecOrigin, vecOrigin, vecMin, vecMax, MASK_PLAYERSOLID, TraceEntityFilterHull, client);
        
        if(TR_DidHit(trace))
        {
            index = 1;
        } else {
            index = -1;
            delete trace;
            break;
        }
        
        delete trace;
    }
    
    return index;
}

public bool TraceEntityFilterHull(int entity, int contentsMask, any client)
{
    return entity != client;
} 

public bool TraceEntityFilterRay(int entity, int contentsMask)
{
    return entity > MaxClients;
}

public int getRandomClient() 
{ 
    int[] iClients = new int[MaxClients];
    int iClientsNum, i;
    
    for (i = 1; i <= MaxClients; i++) 
    { 
        if (IsValidAlive(i) && GetClientTeam(i) == CS_TEAM_CT)
        {
            iClients[iClientsNum++] = i; 
        }
    } 
    
    if (iClientsNum > 0)
    {
        return iClients[GetRandomInt(0, iClientsNum-1)]; 
    }
    
    return 0;
}

stock int getZombieHealthRate(int client)
{
    int value = (RoundToCeil(SquareRoot(float(zClassHp[zombieClass[client]])/(getZombies()+1)/2.0))+2)*zClassHp[zombieClass[client]];

    if (getHumans() < getZombies()) {
        value = (RoundToCeil(SquareRoot(float(zClassHp[zombieClass[client]])/(getZombies()+1)/2.0)))*zClassHp[zombieClass[client]];
    }
    
    return value;
}

stock int getHumans(bool alive = false)
{
    int humans, i;
    
    for (i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && !IsClientSourceTV(i) && GetClientTeam(i) == CS_TEAM_CT)
        {
            if (!alive || (alive && IsPlayerAlive(i)))
            humans++;
        }
    }
    
    return humans;
}

stock int getZombies(bool alive = false)
{
    int zombies, i;
    
    for (i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && !IsClientSourceTV(i) && GetClientTeam(i) == CS_TEAM_T)
        {
            if (!alive || (alive && IsPlayerAlive(i)))
            zombies++;
        }
    }
    
    return zombies;
}

stock int getTrueCT(bool alive = false)
{
    int humans, i;
    
    for (i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && !IsClientSourceTV(i) && pTeam[i] == CS_TEAM_CT)
        {
            if (!alive || (alive && IsPlayerAlive(i)))
            humans++;
        }
    }
    
    return humans;
}

stock int getTrueT(bool alive = false)
{
    int zombies, i;
    
    for (i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i) && !IsClientSourceTV(i) && pTeam[i] == CS_TEAM_T)
        {
            if (!alive || (alive && IsPlayerAlive(i)))
            zombies++;
        }
    }
    
    return zombies;
}

public void setZombieGhostMode(int client, bool mode) 
{
    b_isGhost[client] = mode;
    setZombieClassParameters(client);
}

public void removeMapEventEntity(const char[] objects)
{
    // Initialize char
    char sClass[64];
    
    // Save max amount of entities
    int maxEntities = GetMaxEntities();
    
    // Check all entities and remove it
    for (int i = 0; i <= maxEntities; i++)
    {
        if(IsValidEdict(i) && IsValidEntity(i))
        {
            // Get classname
            GetEdictClassname(i, sClass, sizeof(sClass));
            
            // Compare classname
            if(StrContains(objects, sClass) != -1) 
            {
                RemoveEdict(i);
            }
        }
    }
}

public int getRandZombieClass() 
{
    int[] tclasses = new int[numClasses];
    int classCount;
    
    for(int zClass = 0; zClass < numClasses; zClass++)
    {
        if(zClassExcluded[zClass] == false) {
            tclasses[classCount++] = zClass;
        }
    }
    
    return tclasses[GetRandomInt(0, classCount - 1)];
}

public void setZombieClassParameters(int client) 
{
    if (pTeam[client] != CS_TEAM_T) return;
    // Set zombie class model
    char zBuffer[PLATFORM_MAX_PATH];
    Format(zBuffer, sizeof(zBuffer), "%s.mdl", zClassModel[zombieClass[client]]);
    SetEntityModel(client, zBuffer);
    
    // Set zombie arms
    if (strlen(zClassArms[zombieClass[client]]) > 0) {
        int ent = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
        if(ent != -1) {
            AcceptEntityInput(ent, "KillHierarchy");
        }
        SetEntPropString(client, Prop_Send, "m_szArmsModel", zClassArms[zombieClass[client]]);
    }
    else {
        int ent = GetEntPropEnt(client, Prop_Send, "m_hMyWearables");
        if(ent != -1) {
            AcceptEntityInput(ent, "KillHierarchy");
        }
        SetEntPropString(client, Prop_Send, "m_szArmsModel", DEFAULT_ARMS);
    }
    
    // Set zombie health
    SetEntProp(client, Prop_Send, "m_iHealth", getZombieHealthRate(client), 4);
    
    // Set zombie speed
    if(b_isGhost[client])
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.4);
    else
    SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", zClassSpeed[zombieClass[client]])
    
    // Set zombie gravity
    SetEntityGravity(client, zClassGravity[zombieClass[client]]);
}

public Action CountDown(Handle timer) {
    if (countdownNumber <= 0) {
        countdownNumber = cvarCountDown.IntValue > 10?10:cvarCountDown.IntValue;
        isGhostCanSpawn = true;
        timerCountDown = INVALID_HANDLE;
        
        return Plugin_Stop;
    }
    
    for (int client = 1; client <= MaxClients; client++) {
        if (!IsValidClient(client))
            continue;
        if(GetClientTeam(client) != CS_TEAM_T)
            continue;
        playClientCommandSound(client,countdownSounds[(countdownNumber - 1)]);
    }
    
    countdownNumber--;
    isGhostCanSpawn = false;
    
    return Plugin_Continue;
}

public int nativeIsGhost(Handle plugin, int numParams)
{
    int client = GetNativeCell( 1 );

    return b_isGhost[client];
}

public int nativeGetTeam(Handle plugin, int numParams)
{
    int client = GetNativeCell( 1 );
    bool trueform = GetNativeCell( 2 );
    if (trueform == true)
        return pTeam[client];

    return GetClientTeam(client);
}

public int nativeSetTeam(Handle plugin, int numParams)
{
    int client = GetNativeCell( 1 );
    int team = GetNativeCell( 2 );

    pTeam[client] = team;
    if (!IsValidClient(client))
        return;

    if (!IsPlayerAlive(client)) 
        ChangeClientTeam(client, team);
    else 
        CS_SwitchTeam(client, team);
}

public int nativeGetZombieClass(Handle plugin, int numParams)
{
    int client = GetNativeCell( 1 );

    return zombieClass[client];
}

public int nativeGetRandomZombieClass(Handle plugin, int numParams)
{
    return getRandZombieClass();
}

public void callZombieSelected(int client, int zClass)
{
    // Start forward call
    Call_StartForward(forwardZombieSelected);

    // Push the parameters
    Call_PushCell(client);
    Call_PushCell(zClass);

    // Finish the call
    Call_Finish();
}

public void callZombieRightClick(int client, int zClass, int buttons)
{
    // Start forward call
    Call_StartForward(forwardZombieRightClick);

    // Push the parameters
    Call_PushCell(client);
    Call_PushCell(zClass);
    Call_PushCell(buttons);

    // Finish the call
    Call_Finish();
}
//    CreateNative("ZMPlayer.ZMPlayer", Native_ZMPlayer_Constructor);
public int Native_ZMPlayer_Constructor(Handle plugin, int numParams)
{
    int client = view_as<int>(GetNativeCell(1));
    if ( IsValidClient( client ) ) {
        return view_as< int >( GetClientUserId( client ) );
    }
    return view_as< int >(-1);
}

public int Native_ZMPlayer_ClientGet(Handle plugin, int numParams) 
{
    ZMPlayer player = GetNativeCell(1);
    return GetClientOfUserId( int(player) );
}

public int Native_ZMPlayer_LevelGet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    return getPlayerLevel(player.Client);
}

public int Native_ZMPlayer_XPGet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    return getPlayerUnlocks(player.Client);
}

public int Native_ZMPlayer_XPSet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    setPlayerUnlocks( player.Client, GetNativeCell(2));
}

public int Native_ZMPlayer_GhostGet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    return b_isGhost[player.Client];
}

public int Native_ZMPlayer_GhostSet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    setZombieGhostMode(player.Client, GetNativeCell(2));
}

public int Native_ZMPlayer_TeamGet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    return pTeam[player.Client];
}

public int Native_ZMPlayer_TeamSet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    int client = player.Client;
    int team = GetNativeCell( 2 );

    pTeam[client] = team;
    if (!IsValidClient(client))
        return;
    if (GetClientTeam(client) == team)
        return;

    if (!IsPlayerAlive(client)) 
        ChangeClientTeam(client, team);
    else 
        CS_SwitchTeam(client, team);
}

public int Native_ZMPlayer_ZMClassGet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    int client = player.Client;
    return zombieClass[client];
}

public int Native_ZMPlayer_ZMClassSet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    int client = player.Client;
    // Set random zombie class
    zombieClass[client] = GetNativeCell(2);
    setZombieClassParameters(client);
    callZombieSelected(client, zombieClass[client]);
}

public int Native_ZMPlayer_LastButtonsGet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    int client = player.Client;
    return g_fLastButtons[client];
}

public int Native_ZMPlayer_LastButtonsSet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    int client = player.Client;
    g_fLastButtons[client] = GetNativeCell(2);
}

public int Native_ZMPlayer_OverrideHintGet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    int client = player.Client;
    return b_OverrideHint[client];
}

public int Native_ZMPlayer_OverrideHintSet(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    int client = player.Client;
    bool hint = GetNativeCell(2);
    if (b_OverrideHint[client] == hint) return;

    if (!hint) {
        f_HintSpeed[client] = TIMER_SPEED;
    } else {
        f_HintSpeed[client] = 0.1;
    }

    if (timerGhostHint[client] != null) {
        delete timerGhostHint[client];
        timerGhostHint[client] = CreateTimer( f_HintSpeed[client], ghostHint, client, TIMER_FLAG_NO_MAPCHANGE);
    }

    b_OverrideHint[client] = hint;
}

public int Native_ZMPlayer_OverrideHintText(Handle plugin, int numParams)
{
    ZMPlayer player = GetNativeCell(1);
    int client = player.Client;
    GetNativeString(2, c_OverrideHintText[client], MAX_HINT_SIZE);
}

//    Natives for MethodMap ZombieClass
public int Native_ZombieClass_Constructor(Handle plugin, int numParams)
{
    Format(zClassName[numClasses], MAX_CLASS_NAME_SIZE, "%s", DEFAULT_ZM_NAME);
    Format(zClassDesc[numClasses], MAX_CLASS_DESC_SIZE, "%s", DEFAULT_ZM_DESC);
    Format(zClassModel[numClasses], MAX_CLASS_DESC_SIZE, "%s", DEFAULT_ZM_MODEL_PATH);
    Format(zClassArms[numClasses], MAX_CLASS_DESC_SIZE, "%s", DEFAULT_ZM_ARMS_PATH);

    zClassHp[numClasses] = view_as<int>(DEFAULT_ZM_HEALTH);

    zClassDamage[numClasses] = view_as<float>(DEFAULT_ZM_DAMAGE);
    zClassSpeed[numClasses] = view_as<float>(DEFAULT_ZM_SPEED);
    zClassGravity[numClasses] = view_as<float>(DEFAULT_ZM_GRAVITY);
    
    zClassExcluded[numClasses] = view_as<bool>(DEFAULT_ZM_EXCLUDED);
    
    numClasses++;
    
    return numClasses-1;
}
public int Native_ZombieClass_IDGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    return int(class);
}

public int Native_ZombieClass_HealthGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    return zClassHp[class.ID];
}

public int Native_ZombieClass_HealthSet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    zClassHp[class.ID] = GetNativeCell(2);
}

public int Native_ZombieClass_SpeedGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    return view_as<int>(zClassSpeed[class.ID]);
}

public int Native_ZombieClass_SpeedSet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    zClassSpeed[class.ID] = GetNativeCell(2);
}

public int Native_ZombieClass_GravityGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    return view_as<int>(zClassGravity[class.ID]);
}

public int Native_ZombieClass_GravitySet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    zClassGravity[class.ID] = GetNativeCell(2);
}

public int Native_ZombieClass_ExcludedGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    return view_as<int>(zClassExcluded[class.ID]);
}

public int Native_ZombieClass_ExcludedSet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    zClassExcluded[class.ID] = GetNativeCell(2);
}

public int Native_ZombieClass_DamageGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    return view_as<int>(zClassDamage[class.ID]);
}

public int Native_ZombieClass_DamageSet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    zClassDamage[class.ID] = GetNativeCell(2);
}

public int Native_ZombieClass_NameGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    int bytes = 0;
    SetNativeString(2, zClassName[class.ID], GetNativeCell(3), true, bytes);
    return bytes;
}

public int Native_ZombieClass_NameSet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    int bytes = 0;
    GetNativeString(2, zClassName[class.ID], GetNativeCell(3), bytes);
    return bytes;
}

public int Native_ZombieClass_DescGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    int bytes = 0;
    SetNativeString(2, zClassDesc[class.ID], GetNativeCell(3), true, bytes);
    return bytes;
}

public int Native_ZombieClass_DescSet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    int bytes = 0;
    GetNativeString(2, zClassDesc[class.ID], GetNativeCell(3), bytes);
    return bytes;
}

public int Native_ZombieClass_ModelGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    int bytes = 0;
    SetNativeString(2, zClassModel[class.ID], GetNativeCell(3), true, bytes);
    return bytes;
}

public int Native_ZombieClass_ModelSet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    int bytes = 0;
    GetNativeString(2, zClassModel[class.ID], GetNativeCell(3), bytes);
    return bytes;
}

public int Native_ZombieClass_ArmsGet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    int bytes = 0;
    SetNativeString(2, zClassArms[class.ID], GetNativeCell(3), true, bytes);
    return bytes;
}

public int Native_ZombieClass_ArmsSet(Handle plugin, int numParams)
{
    ZombieClass class = GetNativeCell(1);
    int bytes = 0;
    GetNativeString(2, zClassArms[class.ID], GetNativeCell(3), bytes);
    return bytes;
}
