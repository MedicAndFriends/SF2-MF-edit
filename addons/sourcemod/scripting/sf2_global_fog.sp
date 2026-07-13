#include <sf2>
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <sourcemod>
#include <cbasenpc>

static int g_bossFogEnt[MAXPLAYERS] = {INVALID_ENT_REFERENCE, ...};
static int g_oldFogController[MAXPLAYERS] = {INVALID_ENT_REFERENCE, ...};
static bool g_FogFadingOut[MAXPLAYERS];
static ConVar g_skyName;
static StringMap g_StringMap;

#pragma tabsize 0

enum struct SF2GlobalFogInfo
{
	float Start;
	float End;
	float MaxDensity;
	int FarZ;
	int ColorPrimary[4];
	int ColorSecondary[4];
	float Direction[3];
	bool Blend;
	bool Radial;
	char SkyName[PLATFORM_MAX_PATH];

	void Init()
	{
		this.Start = 1000.0;
		this.End = 1500.0;
		this.MaxDensity = 0.75;
		this.FarZ = -1;
		this.ColorPrimary = {255, 255, 255, 255};
		this.ColorSecondary = {255, 255, 255, 255};
		this.Direction = {0.0, 0.0, 0.0};
		this.Blend = false;
		this.Radial = true;
		this.SkyName[0] = '\0';
	}

	void Load(KeyValues kv)
	{
		this.Start = kv.GetFloat("start", this.Start);
		this.End = kv.GetFloat("end", this.End);
		this.MaxDensity = kv.GetFloat("density", this.MaxDensity);
		this.FarZ = kv.GetNum("farz", this.FarZ);
		kv.GetVector("direction", this.Direction, this.Direction);
        this.Radial = kv.GetNum("radial", this.Radial) != 0;

		GetProfileColorNoBacks(kv, "color_primary", this.ColorPrimary[0], this.ColorPrimary[1], this.ColorPrimary[2], this.ColorPrimary[3]);
		GetProfileColorNoBacks(kv, "color_secondary", this.ColorSecondary[0], this.ColorSecondary[1], this.ColorSecondary[2], this.ColorSecondary[3]);
        this.Blend = kv.GetNum("blend", this.Blend) != 0;
		kv.GetString("custom_sky_name", this.SkyName, sizeof(this.SkyName), this.SkyName);
	}
}

// Huge thanks to CookieCat for some of this stuff

int CreateFog(int client, int bossIndex)
{
	if (IsValidEntity(g_bossFogEnt[client]))
    {
		RemoveEntity(g_bossFogEnt[client]);
    }

	char profile[SF2_MAX_PROFILE_NAME_LENGTH];
	SF2_GetBossName(bossIndex, profile, sizeof(profile));
	SF2GlobalFogInfo fogData;
	g_StringMap.GetArray(profile, fogData, sizeof(fogData));
	g_bossFogEnt[client] = EntIndexToEntRef(CreateEntityByName("env_fog_controller"));
    CBaseEntity fog = CBaseEntity(g_bossFogEnt[client]);

	fog.KeyValue("targetname", profile);
	fog.KeyValue("fogenable", "1");
	fog.KeyValueFloat("fogstart", fogData.Start);
	fog.KeyValueFloat("fogend", fogData.End);
	DispatchKeyValueInt(g_bossFogEnt[client], "farz", fogData.FarZ);
	DispatchKeyValueInt(g_bossFogEnt[client], "fogblend", fogData.Blend);
	DispatchKeyValueInt(g_bossFogEnt[client], "fogRadial", fogData.Radial);
	fog.KeyValueVector("fogdir", fogData.Direction);

	SetVariantColor(fogData.ColorPrimary);
	fog.AcceptInput("SetColor");
	SetVariantColor(fogData.ColorSecondary);
	fog.AcceptInput("SetColorSecondary");
	DispatchSpawn(g_bossFogEnt[client]);
	fog.AcceptInput("TurnOn");
	fog.KeyValueFloat("fogmaxdensity", 0.0);

	DataPack pack;
	CreateDataTimer(0.1, Timer_BossFogFadeIn, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(g_bossFogEnt[client]);
	pack.WriteFloat(fogData.MaxDensity);
	pack.WriteString(fogData.SkyName);

	return g_bossFogEnt[client];
}

static Action Timer_BossFogFadeIn(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = pack.ReadCell();
	int fog = pack.ReadCell();
	if (!(client = GetClientOfUserId(client)))
	{
		if (IsValidEntity(fog))
		{
			RemoveEntity(fog);
		}

		return Plugin_Stop;
	}

	if (!IsValidEntity(fog))
	{
		return Plugin_Stop;
	}

	float maxDensity = pack.ReadFloat();
	float density = GetEntPropFloat(fog, Prop_Data, "m_fog.maxdensity");
	density += 0.04;
	if (density > maxDensity)
		density = maxDensity;

	SetVariantFloat(density);
	AcceptEntityInput(fog, "SetMaxDensity");
	if (density >= maxDensity)
	{
		char skyName[PLATFORM_MAX_PATH];
		pack.ReadString(skyName, sizeof(skyName));
		if (skyName[0])
		{
			SendConVarValue(client, g_skyName, skyName);
		}

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Plugin myinfo =
{
	name = "[SF2] Global Boss Fog",
	description = "Smoked with the boss too much. Now I can't see a thing.",
	author = "The Gaben",
	version = "1.0.0",
	url = "https://github.com/The-Gaben"
};

public void OnPluginStart()
{
	g_StringMap = new StringMap();
	g_skyName = FindConVar("sv_skyname");
	HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnClientDisconnect(int client)
{
	if (IsValidEntity(g_bossFogEnt[client]))
    {
		RemoveEntity(g_bossFogEnt[client]);
    }
	g_bossFogEnt[client] = INVALID_ENT_REFERENCE;
	g_FogFadingOut[client] = false;
}

public void SF2_OnBossAdded(int bossIndex)
{
	char profile[SF2_MAX_PROFILE_NAME_LENGTH];
	SF2_GetBossName(bossIndex, profile, sizeof(profile));
	SF2GlobalFogInfo fogInfo;
	int fogController;
	if (g_StringMap.GetArray(profile, fogInfo, sizeof(fogInfo)))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_bossFogEnt[i] != INVALID_ENT_REFERENCE || !IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}

			if (!g_FogFadingOut[i])
			{
				fogController = GetEntPropEnt(i, Prop_Data, "m_hCtrl");
				if (IsValidEntity(fogController) && EntIndexToEntRef(fogController) != g_bossFogEnt[i])
				{
					// Double checking.
					char name[64];
					GetEntPropString(fogController, Prop_Data, "m_iName", name, sizeof(name));
					if (strcmp(name, profile) != 0)
					{
						g_oldFogController[i] = EntIndexToEntRef(fogController);
					}
				}
			}
			if (TF2_GetClientTeam(i) == TFTeam_Red || SF2_IsClientInGhostMode(i) || SF2_IsClientProxy(i))
			{

				CreateFog(i, bossIndex);
				g_FogFadingOut[i] = false;
				SetEntPropEnt(i, Prop_Data, "m_hCtrl", g_bossFogEnt[i]);
			}
		}
	}
}

public void SF2_OnBossRemoved(int bossIndex)
{
	if (SF2_GetBossMaster(bossIndex) != -1)
	{
		return;
	}

	char profile[SF2_MAX_PROFILE_NAME_LENGTH];
	SF2_GetBossName(bossIndex, profile, sizeof(profile));
	SF2GlobalFogInfo fogInfo;
	if (g_StringMap.GetArray(profile, fogInfo, sizeof(fogInfo)))
	{
		char value[PLATFORM_MAX_PATH];
		g_skyName.GetString(value, sizeof(value));
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidEntity(g_bossFogEnt[i]))
			{
				char fogName[64];
				GetEntPropString(g_bossFogEnt[i], Prop_Data, "m_iName", fogName, sizeof(fogName));
				if (strcmp(profile, fogName) == 0)
				{
					RemoveEntity(g_bossFogEnt[i]);
					g_bossFogEnt[i] = INVALID_ENT_REFERENCE;
				}
			}

			if (SF2_IsValidClient(i) && !IsFakeClient(i))
			{
				SendConVarValue(i, g_skyName, value);
			}
		}
	}
}

Action Event_PlayerSpawn(Handle event, const char[] name, bool dB)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client <= 0)
	{
		return Plugin_Continue;
	}

	if (IsValidEntity(g_bossFogEnt[client]))
	{
		if (TF2_GetClientTeam(client) == TFTeam_Red || SF2_IsClientInGhostMode(client) || SF2_IsClientProxy(client))
		{
			SetEntPropEnt(client, Prop_Data, "m_hCtrl", g_bossFogEnt[client]);
		}

	}

	return Plugin_Continue;
}

public void SF2_OnBossProfileLoaded(const char[] profile, KeyValues kv)
{
	if (kv.JumpToKey("global_fog"))
	{
		SF2GlobalFogInfo fogData;
		fogData.Init();
		fogData.Load(kv);
		g_StringMap.SetArray(profile, fogData, sizeof(fogData));
		kv.GoBack();
	}
}

public void SF2_OnBossProfileUnloaded(const char[] profile)
{
	SF2GlobalFogInfo fogData;
	if (g_StringMap.GetArray(profile, fogData, sizeof(fogData)))
	{
		g_StringMap.Remove(profile);
	}
}