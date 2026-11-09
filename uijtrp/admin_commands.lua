local commands = {}
local commandByName = {}

local function add(level, names)
    for name in names:gmatch("%S+") do
        if commandByName[name] then
            commandByName[name].level = math.min(commandByName[name].level, level)
        else
            local command = { name = name, level = level }
            commands[#commands + 1] = command
            commandByName[name] = command
        end
    end
end

-- Main staff commands and the permission tiers checked by the server.
add(1, [[
camerapos tesspawn ufo unufo entercar checkmypoint checkdiscorducp aweap tpmap
onlinelist playtimelist listafk fightstyle changegender respawnallveh torture
checkmask masked makewarga panel near ainv sound qa servertick checknetwork id
gotosf gotols gotoasur gotocarnaval goto p2p sendto gethere freeze arevive spec
slap astats ostats jetpack getip aka akaip vmodels vehname oreco jail unjail kick
warn unwarn reco setvip playsong stopsong joblist checkucp fixes coord setvw setint
kickallplayer respawnjobvehicle adveh dveh veh o ahelp ajail makefire aduty cd a
]])
add(2, [[
dynhelp makequiz togooc unfreeze areviveall owarn ojail aunarrest blockucp
respawnsidejob respawnrad banip awarn setjob setbone ann unbanip
]])
add(3, [[
afactduty ahealth makewargaoff restart togspy peject acuff auncuff ban oban
sethp sethpall setboneall setam vsethealth afix annp setstress setstressall
goodmood sethbe sethbeall earthquake takemoney explode resetweap reloadweap vote
unban clearask clearreports bisproduct addnewbie removenewbie trunkfix setfuel vinvis
lulusuniv gotoatm gotokanabis createdoor editdoor
]])
add(4, [[
resetdelay arelease setskin settime gotoco setlevel setweather clearallchat giveweap
schedulemt animnear billcreate billremove avcolor addbank removebank addbrankas
destroybrankas editbrankas gotobrankas addbutton editbutton removebutton edittrash
doorlist gotointhouse garkotlist toggleelectric
]])
add(5, [[
setpaycheck noclip gmessage setredmoney setfaction playnearsong updatedb
]])
add(6, [[
atoggle setthestars osetstars removestars customnumber customrek giveredmoney
stafflist ahide admins setadminname customplate custombagasi setadmin kickall
resetweapoff resetplaytime resetpt clearwarn achangename addvehslot addhslot
]])
add(7, [[
giveweapall setmoney givemoney givemoneyall setbankmoney jailall rall oresetharta
resetharta aresetpoint aresign forceahide addapoint deletechar
]])

-- Admin commands in supporting gameplay, staff, and dynamic-world modules.
add(1, [[
adlog itemlist ntag createobject editmonitor deletemonitor avehlist aveh sendveh
takeoutveh getveh gotoveh respawnveh gotogarkot gotodeer gotoslot ogoto
gotoobjecttext gotospeedcam asks ans ar reports
]])
add(2, [[
deltrack gotorusun gotorobbery gotobutton gotodoor gototrash gotogate
gotolabel gototoll aeject gotobisnis
]])
add(5, [[
avl vkeys createredeem addkompensasi removekompensasi addatm editatm removeatm
addsign arvl removelabel addrental addrusun editrusun addslot editslot removeslot
cotext destroyobjecttext eotext resetrobbery createbjtable setmarjunpass seturanpass
addtrash editgate addbisnis editkanabis removekanabis
removedeer
]])
add(6, [[
asetitem aremoveinv clearitems cvc addicon editicon addgarkot editgarkot adddeer
editdeer destroyicon addgudang editgudang removegudang gotogudang
edithouse customint speedmenu setblounge setbpolice addrobbery editrobbery addkanabis
addtoll opentoll closetoll removetoll addgate adduranium edituranium addrusuns
removerusun createbisnis editbisnis edittoll
gotoicon
]])
add(3, [[atakeradio]])
add(7, [[
giveitem giveitemall setitem setvehdonation co eo clone oswap dobject
]])

-- Aliases supported by the server command processor.
add(1, [[cmp cdu stp st]])
add(4, [[cca cac]])
add(6, [[setstars setaname]])
add(7, [[setbmoney setalevel]])

local limitedCommands = {
    jail = true,
    mute = true,
    ban = true,
    aduty = true,
    ar = true,
    ans = true,
    apm = true,
}

for name in pairs(limitedCommands) do
    if commandByName[name] then
        commandByName[name].level = 2
    else
        add(2, name)
    end
end

for _, name in ipairs({ "jailall", "rall", "oresetharta", "resetharta" }) do
    if commandByName[name] then commandByName[name].level = 8 end
end
for _, name in ipairs({ "setadmin", "setalevel" }) do
    if commandByName[name] then commandByName[name].level = 10 end
end

for _, command in ipairs(commands) do
    command.limitedAccess = limitedCommands[command.name] == true
end

table.sort(commands, function(a, b)
    if a.level == b.level then return a.name < b.name end
    return a.level < b.level
end)

return commands
