/*
	Based on Arkarr's Cross Server Chat
	Written in 1.7 SM Syntax
*/

/*
CHANGELOG -

v1.0.4rel
+ Added player death notification
+ Added CVARs to choose whether or not to forward connection / disconnection message
+ Added Steam ID info upon connection
* Changed OnClientConnected to OnClientAuthorized in order to obtain Steam ID info
* Minor ForwardToClient optimization
* Changed char out size to MAX_BUFFER_LENGTH
- Removed unused error messages, for now

v1.0.3rel
* Fixed callback not executable error
* Added GetTeamName function to get rid of the shitty hardcoded team name code

*/

#include <sourcemod>
#include <sdktools>
#include <socket>
#include <bytebuffer>
#include <SteamWorks>
#include <smlib>
#define PLUGIN_AUTHOR "Still / 341464"
#define PLUGIN_VERSION "1.0.4rel"
#define DEBUG 

#define PTYPE_IDENTITY_STRING 0x00
#define PTYPE_HEARTBEAT 0x01
#define PTYPE_CONNECTION_REQUEST  0x02
#define PTYPE_CONNECTION_FAILURE  0x03
#define PTYPE_CONNECTION_SUCCESS  0x04
#define PTYPE_MESSAGE_DATA  0x05

Handle serverSocket = INVALID_HANDLE;
Handle ARRAY_Connections;
Handle ARRAY_ConnectionsIP;
ConVar g_ConnectionPort;
ConVar g_ConnectionPassword;
ConVar g_ConnectionNotify;
ConVar g_KillNotify;
ConVar g_KillBotNotify;
//ConVar g_ConnectionLimit;

char success[]="E OK";
// char emptyPacket[]="E Empty packet";
// char invalidPacket[]="E Invalid packet";
// char invalidContentLength[]="E Invalid content length";
char badPassword[]="E Bad password";
char badIP[]="E Bad IP address";
char badPort[]="E Bad port number";
// char tooMany[]="E Too many connections";

char out[MAX_BUFFER_LENGTH];
int out_size;


public Plugin myinfo = 
{
	name = "[ANY] CheckValve Chat Relay Plugin",
	author = PLUGIN_AUTHOR,
	description = "Based on the mobile app CheckValve, mimics the standalone chat relay server.",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net"
};
public void OnPluginStart()
{
	g_ConnectionPort = CreateConVar("sm_checkvalve_port", "23456", "Port to send & listen to client messages.", FCVAR_PROTECTED | FCVAR_PRINTABLEONLY, true, 2000.0, true, 65565.0);
	g_ConnectionPassword = CreateConVar("sm_checkvalve_pw", "changeme", "Password required to connect to the server. Must not be empty for security reasons.", FCVAR_PROTECTED | FCVAR_PRINTABLEONLY);
	g_ConnectionNotify = CreateConVar("sm_checkvalve_notify_connection", "1", "Should CheckValve forward player connection notifications?", FCVAR_REPLICATED, true, 0.0, true, 1.0);
	g_KillNotify = CreateConVar("sm_checkvalve_notify_kill", "1", "Should CheckValve forward player kill events?", FCVAR_REPLICATED, true, 0.0, true, 1.0);
	g_KillBotNotify = CreateConVar("sm_checkvalve_notify_kill_bots", "0", "Should CheckValve forward bot kill events?", FCVAR_REPLICATED, true, 0.0, true, 1.0);
	//g_ConnectionLimit = CreateConVar("sm_checkvalve_clientlimit", "8", "Maximum client allowed at once.", FCVAR_PROTECTED | FCVAR_PRINTABLEONLY);
	HookConVarChange(g_ConnectionPort, OnConVarChange);
	HookEvent("player_death", Event_PlayerDeath);
	// HookEvent("player_disconnect", Event_Disconnect);
	//HookConVarChange(g_ConnectionLimit, OnConVarChange);
	AutoExecConfig(true, "CheckValve.ChatRelay");
	CreateServer();
	//ARRAY_Connections = CreateArray(g_ConnectionLimit.IntValue);
	ARRAY_Connections = CreateArray();
	ARRAY_ConnectionsIP = CreateArray();
}
public void OnPluginEnd()
{
	int clientCount;
	for(int i = 0; i < GetArraySize(ARRAY_Connections); i++)
	{
		clientCount++;
	}
	PrintToServer("Chat Relay server shutting down...");
	PrintToServer("Dropping %i clients...",clientCount);
	CloseHandle(serverSocket);
	serverSocket = INVALID_HANDLE;
}
// public Action Event_Disconnect(Event event, const char[] name, bool dontBroadcast)
// {
// 	if(g_ConnectionNotify.BoolValue == true)
// 	{
// 		int client = GetClientUserId(GetEventInt(event, "userid"));
// 		char reason[64];
// 		GetEventString(event, "reason", reason, sizeof(reason));
// 		ForwardToClient(_, _, client, "Disconnection", reason);
// 	}
// 	return Plugin_Continue;
// }
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (g_KillNotify.BoolValue == true)
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
		if (IsValidClient(client) && g_KillBotNotify.BoolValue == true)
		{
			if (IsValidClient(attacker))
			{
				char attackerName[MAX_NAME_LENGTH];
				char buffer[64];
				GetClientName(attacker, attackerName, sizeof(attackerName));
				Format(buffer, sizeof(buffer), "was killed by %s", attackerName);
				ForwardToClient(_, _, client, "Death", buffer);
			}
		}
	}
	return Plugin_Continue;
}
public OnConVarChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	PrintToServer("==============================================================");
	PrintToServer("Ignore this if you just started up the server but if not -");
	PrintToServer("THE CONVAR YOU JUST CHANGED DOES NOT AFFECT THE RELAY SERVER");
	PrintToServer("YOU NEED TO CHANGE IT INSIDE THE PLUGIN CONFIG FILE INSTEAD.");
	PrintToServer("==============================================================");
}
//Create the server
public void CreateServer()
{
	if(serverSocket == INVALID_HANDLE)
	{
		serverSocket = SocketCreate(SOCKET_TCP, OnServerSocketError);
		SocketBind(serverSocket, "0.0.0.0", g_ConnectionPort.IntValue); //Listen everything
		SocketListen(serverSocket, OnSocketIncoming);	
		PrintToServer("============================");
		PrintToServer("|Chat Relay server up!|");
		PrintToServer("|Port: %i|", g_ConnectionPort.IntValue);
		//PrintToServer("|Maximum client allowed: %i|", g_ConnectionLimit.IntValue);
		PrintToServer("============================");
	}
}
public OnServerSocketError(Handle socket, const errorType, const errorNum, any arg)
{
	LogError("socket error %d (errno %d)", errorType, errorNum);
	int index = FindValueInArray(ARRAY_Connections, socket);
	if(index != -1)
	{
		RemoveFromArray(ARRAY_Connections, index); 
		RemoveFromArray(ARRAY_ConnectionsIP, index); 
	}
	CloseHandle(socket);
}
public OnChildSocketDisconnected(Handle socket, any hFile)
{
	PrintToServer("Lost connection to client");	
	int index = FindValueInArray(ARRAY_Connections, socket);
	if(index != -1)
	{
		RemoveFromArray(ARRAY_Connections, index);
		RemoveFromArray(ARRAY_ConnectionsIP, index);
	}
	CloseHandle(socket);
}
public OnSocketIncoming(Handle socket, Handle newSocket, const char[] remoteIP, remotePort, any arg)
{
	PrintToServer("Connection detected! (%s:%d)", remoteIP, remotePort);
	SendIdentity(newSocket);
	SocketSetReceiveCallback(newSocket, OnChildSocketReceive);			//Bla bla bla, you got it.	
	SocketSetDisconnectCallback(newSocket, OnChildSocketDisconnected);	//Bla bla bla, you got it.
	SocketSetErrorCallback(newSocket, OnServerSocketError);	//Bla bla bla, you got it.
	PushArrayCell(ARRAY_Connections, newSocket); 
}
public OnChildSocketReceive(Handle socket, char[] receiveData, const int dataSize, any hFile)
{
	ByteBuffer status = CreateByteBuffer(true, out, sizeof(out));
	status.WriteInt(0xFFFFFFFF);

	bool err = false;
	char server_key[64];
	char client_key[64];
	//Obtain server password
	g_ConnectionPassword.GetString(server_key, sizeof(server_key));
	//Obtain client password
	strcopy(client_key, sizeof(client_key), receiveData[9]);
	if (strlen(client_key) == 0 || !StrEqual(client_key, server_key, true))
	{
		PrintToServer("Client has a different password!");
		status.WriteByte(PTYPE_CONNECTION_FAILURE);
		status.WriteShort(sizeof(badPassword));
		status.WriteString(badPassword);
		err = true;
	}
	else
	{
		char client_IP[16];
		int key_length = 9 + strlen(client_key) + 1;
		strcopy(client_IP, sizeof(client_IP), receiveData[key_length]);
		PushArrayString(ARRAY_ConnectionsIP, client_IP);

		char client_Port[6];
		int ip_length = key_length + strlen(client_IP) + 1;
		strcopy(client_Port, sizeof(client_Port), receiveData[ip_length]);

		if (StrEqual(client_IP, getIPInfo(0)) || StrEqual(client_IP, getIPInfo(1)))
		{

			if(StrEqual(client_Port, getIPInfo(2)))
			{
				PrintToServer("Accepting connection...");
				status.WriteByte(PTYPE_CONNECTION_SUCCESS);
				status.WriteShort(sizeof(success));
				status.WriteString(success);
			}
			else
			{
				PrintToServer("Client requested a different server port!");
				status.WriteByte(PTYPE_CONNECTION_FAILURE);
				status.WriteShort(sizeof(badPort));
				status.WriteString(badPort);
				err = true;
			}
		}
		else
		{
			PrintToServer("Client requested a different server IP!");
			status.WriteByte(PTYPE_CONNECTION_FAILURE);
			status.WriteShort(sizeof(badIP));
			status.WriteString(badIP);
			err = true;
		}
	}


	out_size = status.Dump(out,sizeof(out));
	SocketSend(socket, out, out_size);
	status.Close();
	if (err)
	{
		int index = FindValueInArray(ARRAY_Connections, socket);
		if(index != -1)
		{
			RemoveFromArray(ARRAY_Connections, index);
			RemoveFromArray(ARRAY_ConnectionsIP, index);
		}
		CloseHandle(socket);
		PrintToServer("Kicked client off!");
	}
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (g_ConnectionNotify.BoolValue == true)
	{
		if (GetArraySize(ARRAY_Connections) != 0)
		{
			char buffer[64];
			Format(buffer, sizeof(buffer), "Connection [%s]", auth);
			ForwardToClient(_, _, client, buffer, "has joined the game.");
		}
	}
}

public void OnClientDisconnect(int client)
{
	if (g_ConnectionNotify.BoolValue == true)
	{
		if (GetArraySize(ARRAY_Connections) != 0)
		{
			char buffer[64];
			Format(buffer, sizeof(buffer), "Disconnection");
			ForwardToClient(_, _, client, buffer, "has left the game.");
		}
	}
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (GetArraySize(ARRAY_Connections) != 0)
	{
		char teamBuffer[16];
		int iClientTeam = GetClientTeam(client);
		GetTeamName(iClientTeam, teamBuffer, sizeof(teamBuffer));
		ForwardToClient(_, command, client, teamBuffer, sArgs);
	}
}

/*
=============================
Stock function / code section
=============================
*/

/*
=========
Mode 0 = Public IP
Mode 1 = Private IP
Mode 2 = IP Port
=========
*/
stock char[] getIPInfo(int mode)
{
	char ipOut[16];
	switch (mode)
	{
		case 0:
		{
			int ip;
			int octets[4];
			SteamWorks_GetPublicIP(octets);
			ip =
				octets[0] << 24	|
				octets[1] << 16	|
				octets[2] << 8	|
				octets[3];
			LongToIP(ip, ipOut, sizeof(ipOut));
		}
		case 1:
		{
			Server_GetIPString(ipOut, sizeof(ipOut), false);
		}
		case 2:
		{
			int ipPort = Server_GetPort();
			IntToString(ipPort, ipOut, sizeof(ipOut));
		}
	}
	return ipOut;
}

stock void SendIdentity(Handle socket)
{
	PrintToServer("Communicating with the client...");
	char identity[64];
	Format(identity, sizeof(identity), "CheckValve SourceMod Plugin %s", PLUGIN_VERSION);
	ByteBuffer ident = CreateByteBuffer(true, out, sizeof(out));
	ident.WriteInt(0xFFFFFFFF);
	ident.WriteByte(PTYPE_IDENTITY_STRING);
	ident.WriteShort(sizeof(identity));
	ident.WriteString(identity);
	out_size = ident.Dump(out,sizeof(out));
	SocketSend(socket, out, out_size);
	PrintToServer("Sent identity packets, version %s", identity);
	ident.Close();
}


//short is again, yet to be determined
stock void ForwardToClient(int short = 230, const char[] command = "", int client, char[] team ,const char[] msg)
{
	int teamOrNot = 0x01;
	if (StrContains(command, "say_team",false)){teamOrNot = 0x00;}
	char clientName[MAX_NAME_LENGTH];
	char timeBuffer[64];
	char ipBuffer[16];
	GetClientName(client, clientName, sizeof(clientName));
	FormatTime(timeBuffer, sizeof(timeBuffer), "%m/%d/%Y - %H:%M:%S");
	for(int i = 0; i < GetArraySize(ARRAY_Connections); i++)
	{
		Handle clientSocket = GetArrayCell(ARRAY_Connections, i);
		ByteBuffer chat = CreateByteBuffer(true, out, sizeof(out));
		chat.WriteInt(0xFFFFFFFF);
		chat.WriteByte(PTYPE_MESSAGE_DATA);
		chat.WriteShort(short);
		chat.WriteByte(0x01);
		chat.WriteInt(GetTime());
		chat.WriteByte(teamOrNot);
		GetArrayString(ARRAY_ConnectionsIP, i, ipBuffer, sizeof(ipBuffer));
		chat.WriteString(ipBuffer);
		chat.WriteString(getIPInfo(2));
		chat.WriteString(timeBuffer);
		chat.WriteString(clientName);
		chat.WriteString(team);
		chat.WriteString(msg);
		out_size = chat.Dump(out,sizeof(out));
		SocketSend(clientSocket, out, out_size);
		chat.Close();
	}
}
stock bool IsValidClient(client, bool:replaycheck = true)
{
    if(client <= 0 || client > MaxClients)
    {
        return false;
    }
    if(!IsClientInGame(client))
    {
        return false;
    }
    if(GetEntProp(client, Prop_Send, "m_bIsCoaching"))
    {
        return false;
    }
    if(replaycheck)
    {
        if(IsClientSourceTV(client) || IsClientReplay(client)) return false;
    }
    return true;
} 