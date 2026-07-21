#include <sourcemod>
#include <sdktools>
#include <sf2>
#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
    name        = "[SF2] Dynamic Boss Config Fog Handler",
    author      = "bruh.clippy aka cerealcan",
    description = "Reads global_fog from boss KV configs and applies fog on all maps. Based on the original code by @TheGaben and @CookieCat.",
    version     = "1.2.0",
    url         = ""
};
//I would also add the support to dynamically remove/add the fog when adding or removing bosses midround along with enabling the map fog, but I'm lazy.
int g_iFogController = -1;

public void OnPluginStart()
{
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("teamplay_round_win", Event_RoundEnd, EventHookMode_PostNoCopy);
}

public void OnMapStart()
{
    g_iFogController = -1;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetAndDestroyCustomFog();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    ResetAndDestroyCustomFog();
}

// Automatically called by SF2 core when a boss is added to the game.
public void SF2_OnBossAdded(int bossIndex)
{
    PrintToServer("[SF2 Fog Debug] SF2_OnBossAdded triggered for boss index %d!", bossIndex);
    // Re-evaluate active bosses and apply fog if needed
    CheckAndReevaluateBossFog();
}

public void SF2_OnBossRemoved(int bossIndex)
{
    PrintToServer("[SF2 Fog Debug] SF2_OnBossRemoved triggered for boss index %d!", bossIndex);
    // Check if any remaining active bosses still require custom fog
    CheckAndReevaluateBossFog();
}

// Safely destroys our custom fog entity so the map's default environment takes back control
public void ResetAndDestroyCustomFog()
{
    if (g_iFogController != -1 && IsValidEntity(g_iFogController))
    {
        // Unlink players from our custom controller before deleting it
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && GetEntPropEnt(i, Prop_Send, "m_hFogController") == g_iFogController)
            {
                SetEntPropEnt(i, Prop_Send, "m_hFogController", -1);
            }
        }

        AcceptEntityInput(g_iFogController, "TurnOff");
        RemoveEntity(g_iFogController); // Completely delete entity so map fog takes over
    }
    
    g_iFogController = -1;
}

public void CheckAndReevaluateBossFog()
{
    SF2_ProfileObject fogSection = view_as<SF2_ProfileObject>(INVALID_HANDLE);

    // 1. Scan active boss profiles
    for (int i = 0; i < SF2_GetMaxBossCount(); i++)
    {
            SF2_BaseBossProfile profile = SF2_GetProfileFromBossIndex(i);
            
            if (profile != null)
            {
                // Fetch the "global_fog" sub-section directly from the profile
                SF2_ProfileObject sec = profile.GetSection("global_fog");
                
                if (sec != null && sec != view_as<SF2_ProfileObject>(INVALID_HANDLE))
                {
                    fogSection = sec; // Found a valid fog config!
                    break;           // Stop at the first boss needing fog
                }
            }
    }

    // 2. Apply or clear fog based on what was found
    if (fogSection != view_as<SF2_ProfileObject>(INVALID_HANDLE))
    {
        ApplyBossFogFromProfile(fogSection);
    }
    else
    {
        ResetAndDestroyCustomFog();
    }
}

// Function to call whenever a boss with a dynamic config spawns
public void ApplyBossFogFromProfile(SF2_ProfileObject fog)
{
    if (fog == null || fog == view_as<SF2_ProfileObject>(INVALID_HANDLE))
        return;

    // 1. Fetch parameters natively from SF2's profile wrapper
    char szStart[16], szEnd[16], szDensity[16], szColorPrimary[64], szColorSecondary[64];

    fog.GetString("start", szStart, sizeof(szStart), "0.0");
    fog.GetString("end", szEnd, sizeof(szEnd), "1000.0");
    fog.GetString("density", szDensity, sizeof(szDensity), "0.5");
    fog.GetString("color_primary", szColorPrimary, sizeof(szColorPrimary), "255 0 0 0");
    fog.GetString("color_secondary", szColorSecondary, sizeof(szColorSecondary), "255 0 0 0");

    int iBlend  = fog.GetInt("blend", 0);
    int iRadial = fog.GetInt("radial", 0);

    // 2. Create the fog controller if it doesn't exist
    if (g_iFogController == -1 || !IsValidEntity(g_iFogController))
    {
        g_iFogController = CreateEntityByName("env_fog_controller");
        if (g_iFogController == -1)
            return;

        // Apply initial KV properties BEFORE spawning for proper setup
        DispatchKeyValue(g_iFogController, "targetname", "sf2_dynamic_fog");
        DispatchKeyValue(g_iFogController, "fogstart", szStart);
        DispatchKeyValue(g_iFogController, "fogend", szEnd);
        DispatchKeyValue(g_iFogController, "fogmaxdensity", szDensity);
        DispatchKeyValue(g_iFogController, "fogcolor", szColorPrimary);
        DispatchKeyValue(g_iFogController, "fogcolor2", szColorSecondary);
        DispatchKeyValue(g_iFogController, "fogblend", (iBlend > 0) ? "1" : "0");
        DispatchKeyValue(g_iFogController, "use_angles", "0");
        DispatchKeyValue(g_iFogController, "farz", "-1");

        DispatchSpawn(g_iFogController);
    }
    else
    {
        // 3. Dynamically update properties if controller already exists (e.g., new boss spawned)
        SetEntPropFloat(g_iFogController, Prop_Send, "m_fog.start", StringToFloat(szStart));
        SetEntPropFloat(g_iFogController, Prop_Send, "m_fog.end", StringToFloat(szEnd));
        SetEntPropFloat(g_iFogController, Prop_Send, "m_fog.maxdensity", StringToFloat(szDensity));

        SetVariantString(szColorPrimary);
        AcceptEntityInput(g_iFogController, "SetColor");

        SetVariantString(szColorSecondary);
        AcceptEntityInput(g_iFogController, "SetColor2");
    }

    // Ensure the fog is turned on and active
    SetEntProp(g_iFogController, Prop_Send, "m_fog.isMaster", 1);
    SetEntProp(g_iFogController, Prop_Send, "m_fog.enable", 1);
    SetEntProp(g_iFogController, Prop_Send, "m_fog.radial", iRadial);
    AcceptEntityInput(g_iFogController, "TurnOn");

    // 4. Bind all active RED team players to this fog controller
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            SetEntPropEnt(i, Prop_Send, "m_hFogController", g_iFogController);
        }
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsClientInGame(client))
    {
        CreateTimer(0.2, Timer_ApplyPlayerFogNetprop, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_ApplyPlayerFogNetprop(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    
    // Only assign controller IF custom boss fog is actively running
    if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
    {
        if (g_iFogController != -1 && IsValidEntity(g_iFogController))
        {
            SetEntPropEnt(client, Prop_Send, "m_hFogController", g_iFogController);
        }
    }
    return Plugin_Stop;
}