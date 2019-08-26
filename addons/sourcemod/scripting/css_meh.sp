#include <sourcemod>
#include <sdkhooks>
#include <sdktools_engine>
#include <sdktools_functions>

#pragma semicolon 1
#pragma newdecls required

enum GrenadeType
{
    He,
    Flash,
    Smoke
};

bool              g_bAssister[MAXPLAYERS+1][MAXPLAYERS+1],
                  g_bFlashed[MAXPLAYERS+1][MAXPLAYERS+1],
                  g_bNotFreezepanel;

int               g_iDmg[MAXPLAYERS+1][MAXPLAYERS+1],
                  g_iCountObstacles[MAXPLAYERS+1],
                  g_iFlashOwner,
                  g_iHits[MAXPLAYERS+1][MAXPLAYERS+1],
                  g_iNearVictim,
                  g_iNearEnt[GrenadeType],
                  g_iMaxClients,
                  m_flFlashDuration,
                  m_hThrower,
                  m_vecOrigin;

static const char g_sUserID[] = "userid",
                  g_sAttacker[] = "attacker";

// css_meh.sp
public Plugin myinfo = 
{
	name = "[CS:S] Modern Event Hooks", 
    version = "1.0.8",
	author = "Wend4r", 
	url = "Discord: Wend4r#0001 | VK: vk.com/wend4r"
}

public APLRes AskPluginLoad2()
{
    EngineVersion Engine = GetEngineVersion();

    if(Engine != Engine_CSS && Engine != Engine_SourceSDK2006)
    {
        SetFailState("This plugin works only on CS:S OB and CS:S v34");
    }
}

public void OnPluginStart()
{
    HookEvent("hegrenade_detonate", view_as<EventHook>(Events_Grenade), EventHookMode_Pre);
    HookEvent("flashbang_detonate", view_as<EventHook>(Events_Grenade), EventHookMode_Pre);
    HookEvent("smokegrenade_detonate", view_as<EventHook>(Events_Grenade), EventHookMode_Pre);
    HookEvent("player_blind", view_as<EventHook>(Event_OnFlashPlayer), EventHookMode_Pre);
    HookEvent("player_hurt", view_as<EventHook>(Event_Hurt));

    HookEvent("bullet_impact", view_as<EventHook>(Event_Bullet));
    HookEvent("weapon_fire", view_as<EventHook>(Event_Bullet));

    HookEvent("player_death", view_as<EventHook>(Event_Death), EventHookMode_Pre);

    // For CS:S v34
    if(!HookEventEx("show_freezepanel", view_as<EventHook>(Event_FreezePanel), EventHookMode_Pre))
    {
        g_bNotFreezepanel = true;
    }

    HookEvent("player_spawn", view_as<EventHook>(Event_Spawn));

    m_flFlashDuration = FindSendPropInfo("CCSPlayer", "m_flFlashDuration");
    m_hThrower = FindSendPropInfo("CBaseGrenade", "m_hThrower");
    m_vecOrigin = FindSendPropInfo("CBaseEntity", "m_vecOrigin");

    g_iMaxClients = GetMaxHumanPlayers()+1;
}

public void OnEntityCreated(int iEnt, const char[] sClassname)
{
    if(StrContains(sClassname, "_projectile", false) != -1)
    {
        switch(sClassname[0])
        {
            case 'h':
            {
                g_iNearEnt[He] = iEnt;
            }

            case 'f':
            {
                g_iNearEnt[Flash] = iEnt;

                int iOwner = GetEntDataEnt2(iEnt, m_hThrower);

                g_iFlashOwner = iOwner == -1 ? 0 : IsClientInGame(iOwner) ? iOwner : 0;
            }

            case 's':
            {
                g_iNearEnt[Smoke] = iEnt;
            }
        }
    }
}
public void OnEntityDestroyed(int iEnt)
{
    if(IsValidEntity(iEnt))
    {
        static char sClassname[32];
        GetEntityClassname(iEnt, sClassname, sizeof(sClassname));

        if(StrEqual(sClassname, "smokegrenade_projectile"))
        {
            Event hEvent = CreateEvent("smokegrenade_expired", true);

            if(hEvent)
            {
                int iOwner = GetEntDataEnt2(iEnt, m_hThrower);

                hEvent.SetInt(g_sUserID, iOwner == -1 ? 0 : GetClientUserId(iOwner));
                hEvent.SetInt("entityid", iEnt);

                float vecSmoke[3];
                GetEntDataVector(iEnt, m_vecOrigin, vecSmoke);

                hEvent.SetFloat("x", vecSmoke[0]);
                hEvent.SetFloat("y", vecSmoke[1]);
                hEvent.SetFloat("z", vecSmoke[2]);

                hEvent.Fire();
            }
        }
    }
}

Action Events_Grenade(Event hEvent, const char sName[2])
{
    GrenadeType Type;

    switch(sName[0])
    {
        case 'h': Type = He;

        case 'f': Type = Flash;

        default: Type = Smoke;
    }

    hEvent.SetInt("entityid", g_iNearEnt[Type]);

    return Plugin_Changed;
}

Action Event_OnFlashPlayer(Event hEvent)
{
    int iClient = GetClientOfUserId(hEvent.GetInt(g_sUserID));

    g_bFlashed[iClient][g_iFlashOwner] = true;

    hEvent.SetInt(g_sAttacker, g_iFlashOwner ? GetClientUserId(g_iFlashOwner) : 0);
    hEvent.SetInt("entityid", g_iNearEnt[Flash]);

    hEvent.SetInt("flashoffset", m_flFlashDuration);
    hEvent.SetFloat("blind_duration", GetEntDataFloat(iClient, m_flFlashDuration));

    return Plugin_Changed;
}

void Event_Hurt(Event hEvent)
{
    int iClient = GetClientOfUserId(hEvent.GetInt(g_sUserID)),
        iAttacker = GetClientOfUserId(hEvent.GetInt(g_sAttacker));

    if((g_iDmg[iClient][iAttacker] += hEvent.GetInt("dmg_health")) >= 40)
    {
        if(!g_bAssister[iClient][iAttacker])
        {
            g_bAssister[iClient][iAttacker] = true;
        }
    }

    g_iHits[iClient][iAttacker]++;
}

void Event_Bullet(Event hEvent, const char sName[2])
{
    if(sName[0] == 'b')
    {
        g_iCountObstacles[GetClientOfUserId(hEvent.GetInt(g_sUserID))]++;
    }
    else
    {
        g_iCountObstacles[GetClientOfUserId(hEvent.GetInt(g_sUserID))] = 0;
    }
}

Action Event_Death(Event hEvent)
{
    int iClient = (g_iNearVictim = GetClientOfUserId(hEvent.GetInt(g_sUserID))),
        iAttacker = GetClientOfUserId(hEvent.GetInt(g_sAttacker)),
        iAssister;

    if(iClient && iAttacker && iClient != iAttacker)
    {
        for(int i = 1; i != g_iMaxClients; i++)
        {
            if(g_bAssister[iClient][i])
            {
                if(i != iAttacker)
                {
                    iAssister = i;
                    break;
                }
            }
        }

        if(g_iCountObstacles[iAttacker] > 1)
        {
            static char sWeapon[8];

            hEvent.GetString("weapon", sWeapon, sizeof(sWeapon));

            if(!StrEqual(sWeapon, "m3") && !StrEqual(sWeapon, "xm1014") && !StrEqual(sWeapon, "knife"))
            {
                hEvent.SetInt("penetrated", g_iCountObstacles[iAttacker]);
            }
        }
    }

    if(g_bNotFreezepanel)
    {
        Event hEvent2 = CreateEvent("show_freezepanel", true);

        // I love you, CS:S v34
        if(hEvent2)
        {
            hEvent2.SetInt("killer", iAttacker);

            Event_FreezePanel(hEvent2);

            hEvent2.Fire();
        }
    }

    if(iAssister)
    {
        if(IsClientInGame(iAssister))
        {
            hEvent.SetInt("assister", GetClientUserId(iAssister));
            hEvent.SetBool("assistedflash", g_bFlashed[iClient][iAssister]);
        }
    }

    return Plugin_Changed;
}

Action Event_FreezePanel(Event hEvent)
{
    int iAttacker = hEvent.GetInt("killer");

    hEvent.SetInt("victim", g_iNearVictim);
    hEvent.SetInt("hits_taken", g_iHits[iAttacker][g_iNearVictim]);
    hEvent.SetInt("damage_taken", g_iDmg[iAttacker][g_iNearVictim]);
    hEvent.SetInt("hits_given", g_iHits[g_iNearVictim][iAttacker]);
    hEvent.SetInt("damage_given", g_iDmg[g_iNearVictim][iAttacker]);

    return Plugin_Changed;
}

void Event_Spawn(Event hEvent)
{
    for(int i = 1, iClient = GetClientOfUserId(hEvent.GetInt(g_sUserID)); i != g_iMaxClients; i++)
    {
        g_iDmg[iClient][i] = 0;
        g_iHits[iClient][i] = 0;
        g_bAssister[iClient][i] = false;
        g_bFlashed[iClient][i] = false;
    }
}