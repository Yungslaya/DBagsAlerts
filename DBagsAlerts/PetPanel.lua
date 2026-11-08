-- Native pet frame and manual controls. Works independently of rotation modules.
local secret=issecretvalue or function() return false end
local function plain(v) if not secret(v) then return v end end
local FONT="Fonts\\FRIZQT__.TTF"
local state={actions={},utilities={},status="No pet"}
DBagsAlertsState.petPanel=state
local function config()
    DBagsAlertsDB=DBagsAlertsDB or {}
    if type(DBagsAlertsDB.petPanel)~="table" then DBagsAlertsDB.petPanel={} end
    local c=DBagsAlertsDB.petPanel
    if c.enabled==nil then c.enabled=true end
    if c.locked==nil then c.locked=true end
    if c.utilities==nil then c.utilities=true end
    c.scale=math.max(0.7,math.min(1.6,tonumber(c.scale) or 1))
    return c
end
local panel=CreateFrame("Button","DBagsAlertsPetFrame",UIParent,"SecureUnitButtonTemplate")
panel:SetSize(356,88);panel:SetFrameStrata("MEDIUM")
panel:SetAttribute("unit","pet");panel:SetAttribute("*type1","target");panel:SetAttribute("*type2","togglemenu")
panel:RegisterForClicks("AnyUp");panel:SetMovable(true);panel:SetClampedToScreen(true);panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart",function(self) if not InCombatLockdown() and not config().locked then self:StartMoving() end end)
panel:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing();local p,_,rp,x,y=self:GetPoint()
    local dx,dy=0,0
    if DBagsAlertsState.geometry then local w,h;w,h,dx,dy=DBagsAlertsState.geometry("pet",356,19) end
    local scale=config().scale*(DBagsAlertsState.partScale and DBagsAlertsState.partScale("pet") or 1)
    config().point={p,rp,x-dx/scale,y-dy/scale}
end)
panel:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetUnit("pet");GameTooltip:Show() end)
panel:SetScript("OnLeave",function() GameTooltip:Hide() end)
state.frame=panel
local name=panel:CreateFontString(nil,"OVERLAY");name:SetFont(FONT,14,"OUTLINE");name:SetPoint("TOPLEFT");name:SetWidth(270);name:SetJustifyH("LEFT")
local level=panel:CreateFontString(nil,"OVERLAY");level:SetFont(FONT,12,"OUTLINE");level:SetPoint("TOPRIGHT")
local health=CreateFrame("StatusBar",nil,panel);health:SetPoint("TOPLEFT",0,-20);health:SetSize(356,19)
health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");health:SetStatusBarColor(0.18,0.65,0.32)
local hpbg=health:CreateTexture(nil,"BACKGROUND");hpbg:SetAllPoints();hpbg:SetColorTexture(0.04,0.04,0.04,0.8)
health.text=health:CreateFontString(nil,"OVERLAY");health.text:SetFont(FONT,13,"OUTLINE");health.text:SetPoint("CENTER")
local power=CreateFrame("StatusBar",nil,panel);power:SetPoint("TOPLEFT",0,-41);power:SetSize(356,5)
power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
state.health,state.power,state.name=health,power,name
local tools=CreateFrame("Frame",nil,UIParent);tools:SetSize(356,63);tools:SetPoint("TOPLEFT",panel,"BOTTOMLEFT",0,-8)
state.tools=tools
local care=tools:CreateFontString(nil,"OVERLAY");care:SetFont(FONT,12,"OUTLINE");care:SetPoint("TOPLEFT",0,-49);care:SetWidth(356);care:SetJustifyH("LEFT")
state.care=care
local function boolAlpha(v,yes,no)
    if secret(v) then
        if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then return C_CurveUtil.EvaluateColorValueFromBoolean(v,yes,no) end
        return 0
    end
    return v and yes or no
end
local function border(parent)
    local f=CreateFrame("Frame",nil,parent);f:SetAllPoints()
    for _,edge in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
        local t=f:CreateTexture(nil,"OVERLAY");t:SetColorTexture(1,0.82,0.25,1)
        if edge=="TOP" or edge=="BOTTOM" then t:SetPoint(edge.."LEFT");t:SetPoint(edge.."RIGHT");t:SetHeight(1)
        else t:SetPoint("TOP"..edge);t:SetPoint("BOTTOM"..edge);t:SetWidth(1) end
    end
    return f
end
for i=1,10 do
    local b=CreateFrame("Button",nil,panel,"SecureActionButtonTemplate")
    b:SetID(i);b.slot=i;b:SetSize(32,32);b:SetPoint("TOPLEFT",panel,"TOPLEFT",(i-1)*36,-53)
    b:RegisterForClicks("AnyDown","AnyUp");b:SetAttribute("useOnKeyDown",true)
    b:SetAttribute("type1","pet");b:SetAttribute("action1",i);b:SetAttribute("shift-type1","")
    b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetAllPoints();b.icon:SetTexCoord(0.08,0.92,0.08,0.92)
    b.active=border(b)
    b.auto=b:CreateFontString(nil,"OVERLAY");b.auto:SetFont(FONT,10,"OUTLINE");b.auto:SetPoint("BOTTOMRIGHT",-1,1);b.auto:SetText("A");b.auto:SetTextColor(0.25,1,0.35)
    b.cd=CreateFrame("Cooldown",nil,b,"CooldownFrameTemplate");b.cd:SetAllPoints();b.cd:SetDrawBling(false);b.cd:SetHideCountdownNumbers(false)
    b:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT");if GameTooltip.SetPetAction then GameTooltip:SetPetAction(self.slot) end;GameTooltip:Show() end)
    b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    -- Right-click is delegated by the secure click action to Blizzard's own
    -- pet button. Its trusted handler toggles autocast; addon Lua never calls
    -- TogglePetAutocast (which is protected even from an OnClick hook).
    b:RegisterForDrag("LeftButton")
    local function pickup(self)
        if not InCombatLockdown() and IsShiftKeyDown and IsShiftKeyDown() and PickupPetAction then PickupPetAction(self.slot) end
    end
    b:SetScript("OnDragStart",pickup);b:SetScript("OnReceiveDrag",pickup)
    state.actions[i]=b
end
local abilityLists={
    HUNTER={{"Call Pet","Call"},{"Revive Pet","Revive"},{"Mend Pet","Heal"},{"Feed Pet","Feed"},{"Beast Training","Train"},{"Dismiss Pet","Dismiss"}},
    WARLOCK={{"Summon Imp","Imp"},{"Summon Voidwalker","Void"},{"Summon Succubus","Succubus"},{"Summon Incubus","Incubus"},{"Summon Felhunter","Felhunter"},{"Health Funnel","Heal"}},
}
local known={}
local function readKnown()
    wipe(known)
    local api=C_SpellBook
    if not api or not api.GetNumSpellBookSkillLines or not api.GetSpellBookSkillLineInfo or not api.GetSpellBookItemInfo then return end
    local n=plain(api.GetNumSpellBookSkillLines()) or 0
    for line=1,n do
        local info=api.GetSpellBookSkillLineInfo(line)
        if type(info)=="table" and not secret(info) and not (issecrettable and issecrettable(info)) then
            local offset,count=plain(info.itemIndexOffset),plain(info.numSpellBookItems)
            if type(offset)=="number" and type(count)=="number" then
                for index=offset+1,offset+count do
                    local item=api.GetSpellBookItemInfo(index,Enum.SpellBookSpellBank.Player)
                    if type(item)=="table" and not secret(item) and not (issecrettable and issecrettable(item)) then
                        local nm,id=plain(item.name),plain(item.spellID)
                        if type(nm)=="string" and type(id)=="number" then known[nm]=id end
                    end
                end
            end
        end
    end
end
local function utility(i)
    if state.utilities[i] then return state.utilities[i] end
    local b=CreateFrame("Button",nil,tools,"SecureActionButtonTemplate")
    b:SetSize(32,32);b:RegisterForClicks("AnyDown","AnyUp");b:SetAttribute("useOnKeyDown",true);b:SetAttribute("type1","spell")
    b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetAllPoints();b.icon:SetTexCoord(0.08,0.92,0.08,0.92)
    b.label=b:CreateFontString(nil,"OVERLAY");b.label:SetFont(FONT,9,"OUTLINE");b.label:SetPoint("TOP",b,"BOTTOM",0,-2)
    b.safety=CreateFrame("Frame",nil,b);b.safety:SetAllPoints()
    b.warn=border(b.safety);b.warn:SetAlpha(0)
    b:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT");if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spellID) end
        if self.spellName=="Feed Pet" then
            GameTooltip:AddLine("Click Feed, then choose food in your bags.",1,0.85,0.25,true)
            if C_PetInfo and C_PetInfo.GetPetFoodTypes then
                local types=C_PetInfo.GetPetFoodTypes()
                if type(types)=="table" and not secret(types) and not (issecrettable and issecrettable(types)) then
                    local food={};for _,value in ipairs(types) do if type(plain(value))=="string" then food[#food+1]=value end end
                    if #food>0 then GameTooltip:AddLine("Eats: "..table.concat(food,", "),1,1,1,true) end
                end
            end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    state.utilities[i]=b;return b
end
local pending=true
local function configure()
    if InCombatLockdown() then pending=true;return end
    pending=false
    for i,b in ipairs(state.actions) do
        local native=_G["PetActionButton"..i]
        b:SetAttribute("type2",native and "click" or nil)
        b:SetAttribute("clickbutton2",native)
    end
    local c=config();local pos=c.point or {"CENTER","CENTER",-440,-160}
    local width,height,dx,dy=356,19,0,0
    if DBagsAlertsState.geometry then width,height,dx,dy=DBagsAlertsState.geometry("pet",width,height) end
    local scale=c.scale*(DBagsAlertsState.partScale and DBagsAlertsState.partScale("pet") or 1)
    panel:ClearAllPoints();panel:SetScale(scale);tools:SetScale(scale)
    panel:SetPoint(pos[1],UIParent,pos[2],pos[3]+dx/scale,pos[4]+dy/scale)
    health:SetSize(width,height);power:SetWidth(width);power:ClearAllPoints();power:SetPoint("TOPLEFT",0,-22-height)
    name:SetWidth(width-50)
    local cols=math.max(1,math.floor(width/36));local actionY=34+height
    for i,b in ipairs(state.actions) do
        b:ClearAllPoints();b:SetPoint("TOPLEFT",panel,"TOPLEFT",((i-1)%cols)*36,-actionY-math.floor((i-1)/cols)*36)
    end
    panel:SetSize(width,actionY+math.ceil(10/cols)*36-1)
    tools:SetWidth(width);care:SetWidth(width)
    local utilityCols=math.max(1,math.floor(width/52))
    if RegisterStateDriver then RegisterStateDriver(panel,"visibility",c.enabled and "[pet] show; hide" or "hide") end
    readKnown();local _,class=UnitClass("player");class=plain(class)
    state.class=class
    for _,b in ipairs(state.utilities) do b:Hide() end
    local n=0
    if c.enabled and c.utilities then
        for _,a in ipairs(abilityLists[class] or {}) do
            local id=known[a[1]]
            if id then
                n=n+1;local b=utility(n);b.spellID=id;b.spellName=a[1]
                b:SetAttribute("spell1",id);b.icon:SetTexture(C_Spell.GetSpellTexture(id));b.label:SetText(a[2])
                b:ClearAllPoints();b:SetPoint("TOPLEFT",tools,"TOPLEFT",((n-1)%utilityCols)*52,-math.floor((n-1)/utilityCols)*49);b:Show()
            end
        end
    end
    if RegisterStateDriver then RegisterStateDriver(tools,"visibility",c.enabled and n>0 and "show" or "hide") end
    local toolRows=math.max(1,math.ceil(n/utilityCols))
    care:ClearAllPoints();care:SetPoint("TOPLEFT",0,-toolRows*49)
    tools:SetHeight(toolRows*49+14)
    state.utilityCount=n
end
state.configure=configure
local function healthCurve(below,threshold)
    if not C_CurveUtil or not C_CurveUtil.CreateCurve or not Enum.LuaCurveType then return end
    local c=C_CurveUtil.CreateCurve();c:SetType(Enum.LuaCurveType.Step)
    c:AddPoint(0,below and 1 or 0);c:AddPoint(threshold,below and 0 or 1);return c
end
local petLow,ownerSafe
local function update()
    local c=config()
    if not c.enabled then return end
    local exists=plain(UnitExists("pet"))
    if exists then
        name:SetText(UnitName("pet"));level:SetText(UnitLevel("pet"))
        health:SetMinMaxValues(0,UnitHealthMax("pet"));health:SetValue(UnitHealth("pet"),Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut)
        local h,m=plain(UnitHealth("pet")),plain(UnitHealthMax("pet"))
        if type(h)=="number" and type(m)=="number" and m>0 then
            health.text:SetFormattedText("%.0f%%",h/m*100)
            health:SetStatusBarColor(h/m<0.3 and 0.9 or 0.18,h/m<0.3 and 0.2 or 0.65,0.3)
        elseif UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
            health.text:SetFormattedText("%.0f%%",UnitHealthPercent("pet",false,CurveConstants.ScaleTo100))
        end
        local pt=plain(UnitPowerType("pet")) or 0
        power:SetMinMaxValues(0,UnitPowerMax("pet",pt));power:SetValue(UnitPower("pet",pt))
        power:SetStatusBarColor(pt==2 and 1 or 0.2,pt==2 and 0.65 or 0.45,pt==2 and 0.1 or 1)
        if plain(UnitIsDeadOrGhost("pet")) then health.text:SetText("DEAD") end
    end
    local threatSpell
    for i,b in ipairs(state.actions) do
        if GetPetActionInfo then
            local nm,texture,token,active,allowed,auto=GetPetActionInfo(i)
            token=plain(token)
            if token and type(plain(texture))=="string" then texture=_G[texture] or texture end
            b.icon:SetTexture(texture)
            b.active:SetAlpha(boolAlpha(active,1,0));b.auto:SetAlpha(boolAlpha(auto,1,0))
            local realName=plain(nm)
            if not realName and not secret(nm) then b.icon:SetTexture(nil);b.active:SetAlpha(0);b.auto:SetAlpha(0) end
            if (realName=="Growl" or realName=="Torment") and plain(auto)==true then threatSpell=realName end
            if GetPetActionCooldown then
                local start,duration,enabled=GetPetActionCooldown(i)
                if CooldownFrame_Set then CooldownFrame_Set(b.cd,start,duration,enabled)
                else b.cd:SetCooldown(start,duration) end
            end
        end
    end
    local status={}
    if state.class=="HUNTER" and exists and C_PetInfo then
        if C_PetInfo.GetPetHappiness then
            local happy=plain(C_PetInfo.GetPetHappiness())
            if happy==1 then status[#status+1]="FEED PET";care:SetTextColor(1,0.65,0.15)
            elseif happy==2 then status[#status+1]="CONTENT";care:SetTextColor(1,0.85,0.3)
            elseif happy==3 then status[#status+1]="HAPPY";care:SetTextColor(0.4,1,0.4) end
        end
        if C_PetInfo.GetPetLoyalty then local loyalty=plain(C_PetInfo.GetPetLoyalty());if type(loyalty)=="string" then status[#status+1]=loyalty end end
        if C_PetInfo.GetPetTrainingPoints then
            local total,used=C_PetInfo.GetPetTrainingPoints();total,used=plain(total),plain(used)
            if type(total)=="number" and type(used)=="number" and total>used then status[#status+1]=string.format("%d TP",total-used) end
        end
    end
    if threatSpell and IsInGroup() and IsInInstance then
        local inside,kind=IsInInstance()
        if plain(inside)==true and plain(kind)=="party" then status[#status+1]=threatSpell:upper().." ON";care:SetTextColor(1,0.65,0.15) end
    end
    if exists==false and state.utilityCount and state.utilityCount>0 then status[#status+1]="NO PET";care:SetTextColor(1,0.75,0.25) end
    care:SetText(table.concat(status,"  "));state.status=#status>0 and table.concat(status,", ") or (exists and "Pet active" or "No pet")
    for _,b in ipairs(state.utilities) do
        local heal=b.spellName=="Mend Pet" or b.spellName=="Health Funnel"
        local a=0
        b.safety:SetAlpha(1)
        if heal and exists and not plain(UnitIsDeadOrGhost("pet")) then
            local h,m=plain(UnitHealth("pet")),plain(UnitHealthMax("pet"))
            if type(h)=="number" and type(m)=="number" and m>0 then a=h/m<0.35 and 1 or 0
            elseif UnitHealthPercent then petLow=petLow or healthCurve(true,0.35);if petLow then a=UnitHealthPercent("pet",false,petLow) end end
            if b.spellName=="Health Funnel" then
                -- A reminder must not encourage trading away your last health.
                local oh,om=plain(UnitHealth("player")),plain(UnitHealthMax("player"))
                if type(oh)=="number" and type(om)=="number" and om>0 then
                    if oh/om<0.6 then a=0 end
                elseif UnitHealthPercent then
                    ownerSafe=ownerSafe or healthCurve(false,0.6)
                    if ownerSafe then b.safety:SetAlpha(UnitHealthPercent("player",false,ownerSafe)) else a=0 end
                else a=0 end
            end
        end
        b.warn:SetAlpha(a)
    end
end
state.update=update
local elapsed=0
local driver=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_REGEN_ENABLED","UNIT_PET","PET_BAR_UPDATE","PET_BAR_UPDATE_COOLDOWN","SPELLS_CHANGED","UNIT_HEALTH","UNIT_POWER_UPDATE"}) do driver:RegisterEvent(event) end
driver:SetScript("OnEvent",function(_,event,unit)
    if event=="PLAYER_LOGIN" or event=="SPELLS_CHANGED" then pending=true end
    if event=="PLAYER_LOGIN" or event=="PLAYER_REGEN_ENABLED" or (event=="SPELLS_CHANGED" and not InCombatLockdown()) then configure() end
    if event=="UNIT_PET" then pending=true end
end)
driver:SetScript("OnUpdate",function(_,dt)
    elapsed=elapsed+dt;if elapsed<0.2 then return end;elapsed=0
    if pending and not InCombatLockdown() then configure() end
    local ok,err=pcall(update)
    if not ok and state.lastError~=tostring(err) then state.lastError=tostring(err);if geterrorhandler then geterrorhandler()(err) end end
end)
local window
DBagsAlertsState.openPetSettings=function()
    local c=config()
    if not window then
        local w=CreateFrame("Frame","DBagsAlertsPetSettings",UIParent);window=w
        w:SetSize(390,590);w:SetPoint("CENTER");w:SetFrameStrata("DIALOG")
        DBagsAlertsState.prepareSettingsWindow(w,"pet")
        if DBagsAlertsState.alerts then DBagsAlertsState.settingsBackButton(w,function() SlashCmdList.DBAGSALERTS("") end) end
        local bg=w:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0.055,0.055,0.065,1)
        local function text(label,x,y,size)
            local t=w:CreateFontString(nil,"OVERLAY");t:SetFont(FONT,size or 13,"OUTLINE");t:SetText(label);t:SetPoint("TOPLEFT",x,y);return t
        end
        text("Pet controls",18,-16,21)
        local close=CreateFrame("Button",nil,w,"UIPanelButtonTemplate");close:SetSize(28,24);close:SetPoint("TOPRIGHT",-10,-10);close:SetText("X");close:SetScript("OnClick",function() w:Hide() end)
        local function check(label,key,y)
            local b=CreateFrame("CheckButton",nil,w,"UICheckButtonTemplate");b:SetPoint("TOPLEFT",12,y);text(label,46,y-9)
            b:SetScript("OnClick",function(self)
                if InCombatLockdown() then self:SetChecked(config()[key]);w.status:SetText("Change pet layout after combat.");return end
                config()[key]=self:GetChecked() and true or false;configure()
            end);return b
        end
        w.enabled=check("Show pet frame and controls","enabled",-48)
        w.locked=check("Lock pet frame","locked",-80)
        w.utilities=check("Summon and care buttons","utilities",-112)
        local sizeLabel=text("",18,-158)
        w.scale=CreateFrame("Slider",nil,w,"OptionsSliderTemplate");w.scale:SetPoint("TOPLEFT",24,-184);w.scale:SetSize(320,18)
        w.scale:SetMinMaxValues(0.7,1.6);w.scale:SetValueStep(0.05);w.scale:SetObeyStepOnDrag(true)
        w.scale:SetScript("OnValueChanged",function(_,v)
            if InCombatLockdown() then return end
            config().scale=v;sizeLabel:SetFormattedText("Size: %.2fx",v);configure()
        end)
        w.geometry={}
        for i,entry in ipairs({{"width","Width",120,600,5,356},{"height","Health bar height",3,80,1,19},
            {"x","Left / right",-800,800,5,0},{"y","Up / down",-600,600,5,0}}) do
            local key,label,lo,hi,step,default=unpack(entry)
            local t=text(label,18,-226-(i-1)*62)
            local slider=CreateFrame("Slider",nil,w,"OptionsSliderTemplate")
            slider:SetSize(285,18);slider:SetPoint("TOPLEFT",24,-250-(i-1)*62)
            slider:SetMinMaxValues(lo,hi);slider:SetValueStep(step);slider:SetObeyStepOnDrag(true)
            local value=text("",320,-250-(i-1)*62)
            slider:SetScript("OnValueChanged",function(self,v)
                if self.refreshing or InCombatLockdown() then return end
                v=math.floor(v/step+0.5)*step
                DBagsAlertsDB.customSizes=true;DBagsAlertsDB.geometry=DBagsAlertsDB.geometry or {}
                DBagsAlertsDB.geometry.pet=DBagsAlertsDB.geometry.pet or {};DBagsAlertsDB.geometry.pet[key]=v
                value:SetFormattedText("%d",v);configure()
            end)
            slider.refresh=function()
                local g=DBagsAlertsDB.geometry and DBagsAlertsDB.geometry.pet or {}
                local v=DBagsAlertsDB.customSizes and g[key] or default;v=v or default
                slider.refreshing=true;slider:SetValue(v);slider.refreshing=false;value:SetFormattedText("%d",v)
            end
            w.geometry[key]=slider
        end
        text("Right-click ability: autocast. Shift-drag: move.",18,-500,12)
        text("Layout changes apply after combat.",18,-520,12)
        w.status=text("",18,-548,12);w.status:SetWidth(350)
        table.insert(UISpecialFrames,"DBagsAlertsPetSettings")
    end
    window.enabled:SetChecked(c.enabled);window.locked:SetChecked(c.locked);window.utilities:SetChecked(c.utilities)
    for _,slider in pairs(window.geometry) do slider.refresh() end
    window.scale:SetValue(c.scale);window.status:SetText(state.status);DBagsAlertsState.showSettingsWindow(window,"pet")
end
SLASH_DBAGSPET1="/dbapet"
SlashCmdList.DBAGSPET=DBagsAlertsState.openPetSettings
