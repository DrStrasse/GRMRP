-- GRM Computer Social backend: persistent social feed and chat rooms.
if not SERVER then return end
GRM=GRM or {}; GRM.Computer=GRM.Computer or {}; local S=GRM.Computer.Social or {}; GRM.Computer.Social=S
S.Posts=S.Posts or {}; S.Messages=S.Messages or {}; S.NextPost=S.NextPost or {}; S.NextMessage=S.NextMessage or {}; local FILE="grm_computer/social.json"
local function save() file.CreateDir("grm_computer"); file.Write(FILE,util.TableToJSON({posts=S.Posts,messages=S.Messages},true)) end
local function load() if not file.Exists(FILE,"DATA") then return end; local ok,d=pcall(util.JSONToTable,file.Read(FILE,"DATA"),false,true); if ok and istable(d) then S.Posts=d.posts or {}; S.Messages=d.messages or {} end end
local function trim(v,n) return string.sub(string.Trim(tostring(v or "")),1,n) end
local function send(ply,name,data) net.Start(name); net.WriteTable(data or {}); net.Send(ply) end
util.AddNetworkString("GRM_Computer_Social_Request"); util.AddNetworkString("GRM_Computer_Social_Snapshot"); util.AddNetworkString("GRM_Computer_Social_Post"); util.AddNetworkString("GRM_Computer_Social_Delete"); util.AddNetworkString("GRM_Computer_Chat_Send")
load()
net.Receive("GRM_Computer_Social_Request",function(_,ply) send(ply,"GRM_Computer_Social_Snapshot",{posts=S.Posts,messages=S.Messages}) end)
net.Receive("GRM_Computer_Social_Post",function(_,ply) if (S.NextPost[ply:SteamID64()] or 0)>CurTime() then return end; S.NextPost[ply:SteamID64()]=CurTime()+3; local text=trim(net.ReadString(),1000); if text=="" then return end; S.Posts[#S.Posts+1]={id=os.time().."_"..math.random(1000,9999),author=ply:Nick(),sid=ply:SteamID64(),text=text,created=os.time()}; while #S.Posts>200 do table.remove(S.Posts,1) end; save(); for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do send(p,"GRM_Computer_Social_Snapshot",{posts=S.Posts,messages=S.Messages}) end end)
net.Receive("GRM_Computer_Social_Delete",function(_,ply) local id=net.ReadString(); for i=#S.Posts,1,-1 do local post=S.Posts[i]; if post.id==id and (post.sid==ply:SteamID64() or ply:IsAdmin()) then table.remove(S.Posts,i); save(); break end end end)
net.Receive("GRM_Computer_Chat_Send",function(_,ply) if (S.NextMessage[ply:SteamID64()] or 0)>CurTime() then return end; S.NextMessage[ply:SteamID64()]=CurTime()+0.4; local room=trim(net.ReadString(),32); local text=trim(net.ReadString(),500); if room=="" or text=="" then return end; S.Messages[room]=S.Messages[room] or {}; S.Messages[room][#S.Messages[room]+1]={author=ply:Nick(),sid=ply:SteamID64(),text=text,created=os.time()}; while #S.Messages[room]>300 do table.remove(S.Messages[room],1) end; save(); send(ply,"GRM_Computer_Social_Snapshot",{posts=S.Posts,messages=S.Messages}) end)
concommand.Add("grm_computer_social_save",function(ply) if IsValid(ply) and not ply:IsSuperAdmin() then return end save() end)
print("[GRM Computer] persistent social/chat backend loaded")
