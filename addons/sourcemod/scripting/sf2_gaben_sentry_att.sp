#include <sf2>
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>


bool g_bSlenderAttackDeploySentry[MAX_BOSSES];
int g_iSlenderAttackSentryLevel[MAX_BOSSES];
bool g_bSlenderAttackSentryIsMini[MAX_BOSSES];
bool g_bSlenderAttackSentryIsDisposable[MAX_BOSSES];
float g_fSlenderAttackSentryDelay[MAX_BOSSES];
float g_fSlenderAttackSentryLifetime[MAX_BOSSES];
float g_fSlenderAttackSentryVectorXOffset[MAX_BOSSES];
int g_iSlenderAttackSentryTeam[MAX_BOSSES];



public Plugin myinfo =
{
	name = "[SF2]The Gaben's Attack Sentries",
	description = "Now ur bosses can be their own engineers",
	author = "The Gaben",
	version = "1.0.1",
	url = "http://steamcommunity.com/profiles/76561198075611624/"
};


public void OnPluginStart()
{
}


public void SF2_OnBossAdded(int iBossIndex)
{
	char sProfile[SF2_MAX_PROFILE_NAME_LENGTH];
	SF2_GetBossName(iBossIndex, sProfile, sizeof(sProfile));
	
	g_bSlenderAttackDeploySentry[iBossIndex] = view_as<bool>(SF2_GetBossProfileNum(sProfile, "attacks_deploy_sentry", 0));
	g_iSlenderAttackSentryLevel[iBossIndex] = view_as<int>(SF2_GetBossProfileNum(sProfile, "attack_sentry_level", 1));
	g_iSlenderAttackSentryTeam[iBossIndex] = view_as<int>(SF2_GetBossProfileNum(sProfile, "attack_sentry_team", 3));
	g_bSlenderAttackSentryIsMini[iBossIndex] = view_as<bool>(SF2_GetBossProfileNum(sProfile, "attacks_sentry_mini", 0));
	g_bSlenderAttackSentryIsDisposable[iBossIndex] = view_as<bool>(SF2_GetBossProfileNum(sProfile, "attacks_sentry_disposable", 0));
	g_fSlenderAttackSentryDelay[iBossIndex] = view_as<float>(SF2_GetBossProfileFloat(sProfile, "attacks_deploy_sentry_delay", 0.1));
	g_fSlenderAttackSentryLifetime[iBossIndex] = view_as<float>(SF2_GetBossProfileFloat(sProfile, "attacks_deploy_sentry_lifetime", 5.0));
	g_fSlenderAttackSentryVectorXOffset[iBossIndex] = view_as<float>(SF2_GetBossProfileFloat(sProfile, "attacks_deploy_sentry_x_offset", 10.0));
}

public void SF2_OnBossChangeState(int iBossIndex, int iOldState, int iNewState)
{
	if (MAX_BOSSES > iBossIndex >= 0 && g_bSlenderAttackDeploySentry[iBossIndex])
	{
		switch (iNewState)
		{
			case STATE_ATTACK:
			{
				int iAttackIndex = SF2_GetBossCurrentAttackIndex(iBossIndex);
				int iAttackType = SF2_GetBossAttackIndexType(iBossIndex, iAttackIndex);
				if (iAttackType == 7)
				{
					CreateTimer(g_fSlenderAttackSentryDelay[iBossIndex], Timer_AttackDeploySentryDelay, iBossIndex, TIMER_FLAG_NO_MAPCHANGE);
				}
			}
		}
	}
}

public Action Timer_AttackDeploySentryDelay(Handle timer, any iBossIndex)
{
	float position[3];
	float angles[3];
	int slenderent = SF2_BossIndexToEntIndex(iBossIndex);
	GetEntPropVector(slenderent, Prop_Send, "m_vecOrigin", position);
	GetEntPropVector(slenderent, Prop_Send, "m_angRotation", angles);
	
	position[0] += g_fSlenderAttackSentryVectorXOffset[iBossIndex];
	
	int iSentry = SF2_SpawnSentry(iBossIndex, position, angles, g_iSlenderAttackSentryLevel[iBossIndex], g_bSlenderAttackSentryIsMini[iBossIndex], g_bSlenderAttackSentryIsDisposable[iBossIndex], _);
	
	CreateTimer(g_fSlenderAttackSentryLifetime[iBossIndex], Timer_SF2DestroySentry, iSentry, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SF2DestroySentry(Handle timer, any entref)
{
	int ent = EntRefToEntIndex(entref);
	if (!IsValidEdict(ent)) return Plugin_Stop;
	
	SetVariantInt(1000);
	AcceptEntityInput(ent, "RemoveHealth");

	return Plugin_Stop;
}


// Original code by Pelipoika, slightly modified by The Gaben
stock int SF2_SpawnSentry(int iBossIndex, float Position[3], float Angle[3], int level, bool mini=false, bool disposable=false, int flags=4)
{

	float m_vecMinsMini[3] = {-15.0, -15.0, 0.0}, m_vecMaxsMini[3] = {15.0, 15.0, 49.5};
	float m_vecMinsDisp[3] = {-13.0, -13.0, 0.0}, m_vecMaxsDisp[3] = {13.0, 13.0, 42.9};

	int sentry = CreateEntityByName("obj_sentrygun");

	if(!IsValidEntity(sentry)) return 0;

	int iTeam = g_iSlenderAttackSentryTeam[iBossIndex];

//	SetEntPropEnt(sentry, Prop_Send, "m_hBuilder", builder);

	SetVariantInt(iTeam);
	AcceptEntityInput(sentry, "SetTeam");

	DispatchKeyValueVector(sentry, "origin", Position);
	DispatchKeyValueVector(sentry, "angles", Angle);

	if(mini){
		SetEntProp(sentry, Prop_Send, "m_bMiniBuilding", 1);
		SetEntProp(sentry, Prop_Send, "m_iUpgradeLevel", level);
		SetEntProp(sentry, Prop_Send, "m_iHighestUpgradeLevel", level);
		SetEntProp(sentry, Prop_Data, "m_spawnflags", flags);
		SetEntProp(sentry, Prop_Send, "m_bBuilding", 1);
		SetEntProp(sentry, Prop_Send, "m_nSkin", level == 1 ? iTeam : iTeam -2);
		DispatchSpawn(sentry);

		SetVariantInt(100);
		AcceptEntityInput(sentry, "SetHealth");

		SetEntPropFloat(sentry, Prop_Send, "m_flModelScale", 0.75);
		SetEntPropVector(sentry, Prop_Send, "m_vecMins", m_vecMinsMini);
		SetEntPropVector(sentry, Prop_Send, "m_vecMaxs", m_vecMaxsMini);
	}else if(disposable){
		SetEntProp(sentry, Prop_Send, "m_bMiniBuilding", 1);
		SetEntProp(sentry, Prop_Send, "m_bDisposableBuilding", 1);
		SetEntProp(sentry, Prop_Send, "m_iUpgradeLevel", level);
		SetEntProp(sentry, Prop_Send, "m_iHighestUpgradeLevel", level);
		SetEntProp(sentry, Prop_Data, "m_spawnflags", flags);
		SetEntProp(sentry, Prop_Send, "m_bBuilding", 1);
		SetEntProp(sentry, Prop_Send, "m_nSkin", level == 1 ? iTeam : iTeam -2);
		DispatchSpawn(sentry);

		SetVariantInt(100);
		AcceptEntityInput(sentry, "SetHealth");

		SetEntPropFloat(sentry, Prop_Send, "m_flModelScale", 0.60);
		SetEntPropVector(sentry, Prop_Send, "m_vecMins", m_vecMinsDisp);
		SetEntPropVector(sentry, Prop_Send, "m_vecMaxs", m_vecMaxsDisp);
	}else{
		SetEntProp(sentry, Prop_Send, "m_iUpgradeLevel", level);
		SetEntProp(sentry, Prop_Send, "m_iHighestUpgradeLevel", level);
		SetEntProp(sentry, Prop_Data, "m_spawnflags", flags);
		SetEntProp(sentry, Prop_Send, "m_bBuilding", 1);
		SetEntProp(sentry, Prop_Send, "m_nSkin", iTeam -2);
		DispatchSpawn(sentry);
	}
	return sentry;
}
