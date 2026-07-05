-- NAKRUF Logic v2.0 - AI Code Generator
-- Tüm sistem tek dosyadır. Plugin klasörüne atıp doğrudan kullanabilirsiniz.


-- /// Ayarlar ///
local Settings = (function()
    local M,_p={},nil
    local Hs=game:GetService("HttpService")
    local function sg(k) local ok,v=pcall(function() return _p:GetSetting(k) end); return ok and v or nil end
    local function ss(k,v) pcall(function() _p:SetSetting(k,v) end) end
    local function jE(t) local ok,s=pcall(function() return Hs:JSONEncode(t) end); return ok and s or nil end
    local function jD(s)
        if type(s)~="string" then return nil end
        local ok,d=pcall(function() return Hs:JSONDecode(s) end)
        return (ok and type(d)=="table") and d or nil
    end
    local function mask(k)
        if type(k)~="string" or #k<1 then return "<empty>" end
        local n=math.min(4,#k); return ("*"):rep(#k-n)..k:sub(-n)
    end
    function M.init(p) _p=p end
    function M.saveKey(k)
        if type(k)~="string" then return false end
        local t=k:match("^%s*(.-)%s*$"); if t=="" then return false end
        ss("NakrufKey",t); print("[NAKRUF] key "..mask(t)); return true
    end
    function M.getKey()
        local v=sg("NakrufKey")
        return (type(v)=="string" and not v:match("^%s*$")) and v or nil
    end
    function M.hasKey() return M.getKey()~=nil end
    function M.saveProv(p) ss("NakrufProv2",p) end
    function M.getProv() return sg("NakrufProv2") end
    function M.saveModel(p,m) ss("NakrufMdl_"..p,m) end
    function M.getModel(p) local v=sg("NakrufMdl_"..p); return type(v)=="string" and v or nil end
    function M.savePrompt(t) if type(t)=="string" then ss("NakrufPrompt",t:sub(1,4000)) end end
    function M.getPrompt() local v=sg("NakrufPrompt"); return type(v)=="string" and v or nil end
    function M.saveTemp(t) ss("NakrufTemp2",tostring(t)) end
    function M.getTemp()
        local v=sg("NakrufTemp2"); local n=tonumber(v)
        return n and math.clamp(n,0,1) or 0.2
    end
    function M.saveLang(l) ss("NakrufLang",l) end
    function M.getLang() local v=sg("NakrufLang"); return v=="en" and "en" or "tr" end
    function M.saveHist(a) local s=jE(a); if s then ss("NakrufHist2",s) end end
    function M.getHist() return jD(sg("NakrufHist2")) or {} end
    function M.saveSnip(a) local s=jE(a); if s then ss("NakrufSnip2",s) end end
    function M.getSnip() return jD(sg("NakrufSnip2")) or {} end
    return M
end)()


-- /// Modeller ve Yapay Zeka Sağlayıcıları ///
local PROVS = {
    {key="openai",   lbl="OpenAI",
     mdls={"gpt-4o","gpt-4o-mini","gpt-4-turbo","o1-mini"},
     def="gpt-4o"},
    {key="gemini",   lbl="Gemini",
     mdls={"gemini-2.5-flash","gemini-2.5-pro","gemini-2.0-flash","gemini-1.5-flash"},
     def="gemini-2.5-flash"},
    {key="claude",   lbl="Claude",
     mdls={"claude-opus-4-5","claude-sonnet-4-5","claude-3-5-haiku-20241022","claude-3-5-sonnet-20241022"},
     def="claude-sonnet-4-5"},
    {key="deepseek", lbl="DeepSeek",
     mdls={"deepseek-ai/deepseek-r1","deepseek-ai/deepseek-v3"},
     def="deepseek-ai/deepseek-r1"},
}
local PMAP={}
for _,p in ipairs(PROVS) do PMAP[p.key]=p end


-- /// API İstekleri ///
local API = (function()
    local M={}
    local Hs=game:GetService("HttpService")
    local SP={
        tr=[[Sen profesyonel bir Roblox gelistiricisisin. Kurallara kesinlikle uy:
1. ETIKET: Ilk satir --TYPE:GUI veya --TYPE:SCRIPT ve --NAME:Isim olmali
2. CONTEXT: [Context] varsa -> O objeyi guncelle, ismini birebir kullan, YENi DOSYA OLUSTURMA
3. BASLANGIC: game:IsLoaded() ile basla
4. PARENT: GUI -> tum UI objeleri script.Parent a parent la (Visible=true, ortalanmis, duzgun boyut)
5. FORMAT: Yalnizca saf calisir Lua kodu. Aciklama yok, markdown yok.
6. KALITE: Optimize, hatasiz, modern Luau. Harika gorsel tasarim.]],
        en=[[You are a professional Roblox developer. Follow strictly:
1. TAG: First line must be --TYPE:GUI or --TYPE:SCRIPT and --NAME:Name
2. CONTEXT: If [Context] present -> update that exact object, use name verbatim. NO new files.
3. START: Begin with game:IsLoaded() check
4. PARENT: GUI -> parent all UI to script.Parent (Visible=true, centered, sized)
5. FORMAT: Pure runnable Lua code only. No explanations, no markdown.
6. QUALITY: Optimized, error-free, modern Luau. Great visual design.]],
    }
    local HE={
        [400]="Bad Request",[401]="API key gecersiz",[403]="Erisim reddedildi",
        [404]="Endpoint yok",[429]="Rate limit -- bekle",[500]="Sunucu hatasi",
        [502]="Bad Gateway",[503]="Servis kapali"
    }
    local function strip(t)
        t=t:gsub("^%s*```+%a*%s*\n?",""); t=t:gsub("\n?```+%s*$","")
        return t:match("^%s*(.-)%s*$")
    end
    local function mask(k)
        if type(k)~="string" or #k<1 then return "<>" end
        local n=math.min(4,#k); return ("*"):rep(#k-n)..k:sub(-n)
    end
    local function buildReq(pk,mdl,key,hist,temp,lang)
        local sp=SP[lang] or SP.tr
        local t=tonumber(temp) or 0.2
        if pk=="openai" then
            local msgs={{role="system",content=sp}}
            for _,h in ipairs(hist) do table.insert(msgs,h) end
            return {
                url="https://api.openai.com/v1/chat/completions",
                hdrs={["Content-Type"]="application/json",["Authorization"]="Bearer "..key},
                body={model=mdl,temperature=t,max_tokens=4096,messages=msgs}
            }
        elseif pk=="gemini" then
            local contents={}
            for _,h in ipairs(hist) do
                table.insert(contents,{
                    role=h.role=="assistant" and "model" or "user",
                    parts={{text=h.content}}
                })
            end
            return {
                url="https://generativelanguage.googleapis.com/v1beta/models/"..mdl..":generateContent?key="..key,
                hdrs={["Content-Type"]="application/json"},
                body={
                    system_instruction={parts={{text=sp}}},
                    contents=contents,
                    generationConfig={temperature=t,maxOutputTokens=8192}
                }
            }
        elseif pk=="claude" then
            local msgs={}
            for _,h in ipairs(hist) do table.insert(msgs,h) end
            return {
                url="https://api.anthropic.com/v1/messages",
                hdrs={["Content-Type"]="application/json",["x-api-key"]=key,["anthropic-version"]="2023-06-01"},
                body={model=mdl,max_tokens=4096,system=sp,messages=msgs}
            }
        elseif pk=="deepseek" then
            local msgs={{role="system",content=sp}}
            for _,h in ipairs(hist) do table.insert(msgs,h) end
            return {
                url="https://integrate.api.nvidia.com/v1/chat/completions",
                hdrs={["Content-Type"]="application/json",["Authorization"]="Bearer "..key},
                body={model=mdl,temperature=t,max_tokens=4096,messages=msgs}
            }
        end
        return nil
    end
    local function extract(pk,data)
        if pk=="openai" or pk=="deepseek" then
            local c=data and data.choices
            if type(c)~="table" or #c==0 then return nil end
            local m=c[1].message
            return (type(m)=="table" and type(m.content)=="string") and m.content or nil
        elseif pk=="gemini" then
            local c=data and data.candidates
            if type(c)~="table" or #c==0 then return nil end
            local pt=c[1].content and c[1].content.parts
            return (type(pt)=="table" and #pt>0 and type(pt[1].text)=="string") and pt[1].text or nil
        elseif pk=="claude" then
            local c=data and data.content
            if type(c)~="table" then return nil end
            for _,b in ipairs(c) do
                if b.type=="text" and type(b.text)=="string" then return b.text end
            end
        end
        return nil
    end
    -- hist=[{role,content}]  promptText=new user msg NOT yet in hist
    function M.send(key,promptText,ctx,pk,mdl,hist,temp,lang)
        if type(key)~="string" or key:match("^%s*$") then return false,"API Key gerekli." end
        if type(promptText)~="string" or promptText:match("^%s*$") then return false,"Prompt bos." end
        local prov=PMAP[pk]; if not prov then return false,"Gecersiz provider." end
        local msg=promptText
        if type(ctx)=="string" and ctx~="" and ctx~="No active selection." then
            msg="[Context]\n"..ctx.."\n\n[Task]\n"..promptText
        end
        -- Trim history: keep last 6 + new = 7 msgs total
        local h={}
        local s=math.max(1,#hist-5)
        for i=s,#hist do table.insert(h,hist[i]) end
        table.insert(h,{role="user",content=msg})
        local req=buildReq(pk,mdl,key,h,temp,lang)
        if not req then return false,"Build hatasi." end
        local bodyJ=""
        local ok,err=pcall(function() bodyJ=Hs:JSONEncode(req.body) end)
        if not ok then return false,"JSON: "..tostring(err) end
        local rok,resp
        for i=1,3 do
            rok,resp=pcall(function()
                return Hs:RequestAsync({Url=req.url,Method="POST",Headers=req.hdrs,Body=bodyJ})
            end)
            if rok and resp and resp.Success then break end
            if rok and resp and resp.StatusCode==429 and i<3 then
                warn("[NAKRUF] Rate limit, retry "..i); task.wait(5)
            else break end
        end
        if not rok then
            local e=tostring(resp):gsub(key,mask(key))
            if e:find("Http requests are not enabled") then
                return false,"HTTP kapali -- Game Settings > Security > Allow HTTP Requests"
            end
            return false,"Ag hatasi."
        end
        if not resp.Success then
            warn("[NAKRUF] HTTP "..tostring(resp.StatusCode))
            return false,(HE[resp.StatusCode] or "HTTP "..tostring(resp.StatusCode))
        end
        local dok,data=pcall(function() return Hs:JSONDecode(resp.Body) end)
        if not dok then return false,"Parse hatasi." end
        local raw=extract(pk,data)
        if type(raw)~="string" or raw=="" then return false,prov.lbl.." bos yanit dondurdu." end
        local code=strip(raw)
        if code=="" then return false,"Bos icerik." end
        return true,code
    end
    return M
end)()


-- /// Kod İşleme ve Enjeksiyon ///
local Proc=(function()
    local M={}
    function M.clean(r)
        if type(r)~="string" then return "" end
        local s=r
        s=s:gsub("^%s*```+%a*%s*\n?",""); s=s:gsub("\n?```+%s*$","")
        for e,c in pairs({["&amp;"]="&",["&lt;"]="<",["&gt;"]=">",[" &quot;"]='\"',["&nbsp;"]=" "}) do
            s=s:gsub(e,c)
        end
        s=s:gsub("\r\n","\n"):gsub("\r","\n"):gsub("%z","")
        return s:match("^%s*(.-)%s*$")
    end
    function M.check(c)
        if type(c)~="string" or c:match("^%s*$") then return false,"Kod bos." end
        local fn,err=loadstring(c); if fn then return true end
        local ln,d=tostring(err):match(":(%d+):%s*(.+)$")
        return false,(ln and "Satir "..ln..": "..d or "Syntax hatasi.")
    end
    function M.inject(raw)
        local c=M.clean(raw); if c=="" then return false,"Bos kod." end
        local ok2,err=M.check(c); if not ok2 then return false,err end
        local r,a,b=pcall(function()
            local isG=c:find("%-%-TYPE:GUI")
            local isS=c:find("%-%-TYPE:SCRIPT")
            local nm=c:match("%-%-NAME:(%S+)") or (isG and "NAKRUF_GUI" or "NAKRUF_Script")
            local ct,obj
            if isG then
                ct=game:GetService("StarterGui"); obj=ct:FindFirstChild(nm)
                if obj and not obj:IsA("ScreenGui") then obj:Destroy(); obj=nil end
                if not obj then obj=Instance.new("ScreenGui"); obj.Name=nm; obj.Parent=ct end
                for _,ch in ipairs(obj:GetChildren()) do ch:Destroy() end
                local ls=Instance.new("LocalScript"); ls.Source=c; ls.Parent=obj
            elseif isS then
                ct=game:GetService("StarterPlayer").StarterPlayerScripts
                obj=ct:FindFirstChild(nm)
                if obj and not obj:IsA("LocalScript") then obj:Destroy(); obj=nil end
                if not obj then obj=Instance.new("LocalScript"); obj.Name=nm; obj.Parent=ct end
                obj.Source=c
            else
                ct=game:GetService("Workspace"); obj=ct:FindFirstChild(nm)
                if obj and not obj:IsA("Script") then obj:Destroy(); obj=nil end
                if not obj then
                    obj=Instance.new("Script"); obj.Name=nm; obj.Disabled=true; obj.Parent=ct
                end
                obj.Source=c
            end
            return ct.Name,obj.Name
        end)
        if not r then return false,"Inject: "..tostring(a) end
        return true,"OK "..tostring(b).." > "..tostring(a)
    end
    function M.updateSel(raw)
        local c=M.clean(raw); if c=="" then return false,"Bos kod." end
        local ok2,err=M.check(c); if not ok2 then return false,err end
        for _,obj in ipairs(game:GetService("Selection"):Get()) do
            if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
                local ok3,e=pcall(function() obj.Source=c end)
                return ok3 and true or false,
                       ok3 and ("OK "..obj.Name.." guncellendi.") or tostring(e)
            end
        end
        return false,"Secili script yok. Explorer'dan bir Script/LocalScript sec."
    end
    return M
end)()


-- /// Seçili Obje Bağlamı ///
local function getCtx()
    local sel=game:GetService("Selection"):Get()
    if #sel==0 then return "No active selection." end
    local b={"Selection ("..#sel.." objects):"}
    for i=1,math.min(#sel,5) do
        local obj=sel[i]
        local ok,d=pcall(function()
            local l={"  ["..i.."] "..obj.Name.." ("..obj.ClassName..")"}
            local function tp(p) local o,v=pcall(function() return obj[p] end); return o and v or nil end
            local pos=tp("Position")
            if typeof(pos)=="Vector3" then
                table.insert(l,"      Pos:"..string.format("(%.1f,%.1f,%.1f)",pos.X,pos.Y,pos.Z))
            end
            local src=tp("Source")
            if type(src)=="string" and #src>0 then
                table.insert(l,"      Src["..#src.."]: "..src:sub(1,200):gsub("\n"," "))
            end
            return table.concat(l,"\n")
        end)
        table.insert(b,ok and d or "  ["..i.."] <err>")
    end
    if #sel>5 then table.insert(b,"  ..."..(#sel-5).." more.") end
    return table.concat(b,"\n")
end


-- /// Arayüz Renkleri ve Araçları ///
local C={
    BG=Color3.fromRGB(10,10,16),   SF=Color3.fromRGB(18,18,26),
    SF2=Color3.fromRGB(28,28,38),  SF3=Color3.fromRGB(38,38,50),
    AC=Color3.fromRGB(210,40,40),  ACD=Color3.fromRGB(155,18,18),
    BL=Color3.fromRGB(65,125,255), BLD=Color3.fromRGB(45,95,205),
    GR=Color3.fromRGB(65,195,100), RE=Color3.fromRGB(255,72,72),
    WA=Color3.fromRGB(255,185,45),
    TX=Color3.fromRGB(225,225,238),DM=Color3.fromRGB(118,118,142),
    BO=Color3.fromRGB(42,42,58),
}
local function aC(p,r)
    local o=Instance.new("UICorner"); o.CornerRadius=UDim.new(0,r or 6); o.Parent=p
end
local function aS(p,c,t)
    local o=Instance.new("UIStroke"); o.Color=c or C.BO; o.Thickness=t or 1
    o.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; o.Parent=p; return o
end
local function aP(p,t,r,b,l)
    local o=Instance.new("UIPadding")
    o.PaddingTop=UDim.new(0,t); o.PaddingRight=UDim.new(0,r)
    o.PaddingBottom=UDim.new(0,b); o.PaddingLeft=UDim.new(0,l); o.Parent=p
end
local function aVL(p,pad)
    local o=Instance.new("UIListLayout"); o.Padding=UDim.new(0,pad or 6)
    o.HorizontalAlignment=Enum.HorizontalAlignment.Left
    o.VerticalAlignment=Enum.VerticalAlignment.Top
    o.FillDirection=Enum.FillDirection.Vertical
    o.SortOrder=Enum.SortOrder.LayoutOrder; o.Parent=p; return o
end
local function aHL(p,pad)
    local o=Instance.new("UIListLayout"); o.Padding=UDim.new(0,pad or 4)
    o.HorizontalAlignment=Enum.HorizontalAlignment.Left
    o.VerticalAlignment=Enum.VerticalAlignment.Center
    o.FillDirection=Enum.FillDirection.Horizontal
    o.SortOrder=Enum.SortOrder.LayoutOrder; o.Parent=p; return o
end
local function mkSec(par,lo)
    local f=Instance.new("Frame"); f.BackgroundColor3=C.SF; f.LayoutOrder=lo or 0
    f.Size=UDim2.new(1,0,0,0); f.AutomaticSize=Enum.AutomaticSize.Y
    f.ClipsDescendants=false; aC(f,8); aS(f,C.BO,1); aP(f,10,12,10,12); aVL(f,6)
    f.Parent=par; return f
end
local function mkTag(p,t,lo)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,11)
    l.BackgroundTransparency=1; l.Font=Enum.Font.GothamBold; l.Text=t
    l.TextColor3=C.DM; l.TextSize=9;l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=lo or 0; l.Parent=p; return l
end
local function mkHov(b,n,h,d)
    local nc=n or C.SF2
    b.MouseEnter:Connect(function() b.BackgroundColor3=h or C.SF3 end)
    b.MouseLeave:Connect(function() b.BackgroundColor3=nc end)
    if d then
        b.MouseButton1Down:Connect(function() b.BackgroundColor3=d end)
        b.MouseButton1Up:Connect(function() b.BackgroundColor3=nc end)
    end
end
local function mkToggle(arr,body,loadFn)
    arr.MouseButton1Click:Connect(function()
        body.Visible=not body.Visible
        arr.Text=body.Visible and "V KAPAT" or "> AC"
        if body.Visible and loadFn then loadFn() end
    end)
end


-- /// Ana Pencere (Widget) ///
Settings.init(plugin)
local widget=plugin:CreateDockWidgetPluginGui("NakrufLogicV2",
    DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float,true,false,320,600,260,440))
widget.Name="NAKRUF Logic v2"; widget.Title="NAKRUF Logic"
widget.ZIndexBehavior=Enum.ZIndexBehavior.Sibling

local root=Instance.new("ScrollingFrame"); root.Name="Root"
root.Size=UDim2.fromScale(1,1); root.BackgroundColor3=C.BG; root.BorderSizePixel=0
root.ScrollBarThickness=3; root.ScrollBarImageColor3=C.AC
root.CanvasSize=UDim2.new(0,0,0,0); root.AutomaticCanvasSize=Enum.AutomaticSize.Y
root.ScrollingDirection=Enum.ScrollingDirection.Y; root.ClipsDescendants=true
root.Parent=widget; aP(root,12,10,24,10); aVL(root,8)


-- /// Üst Kısım (Header) ///
do
    local hdr=Instance.new("Frame"); hdr.Size=UDim2.new(1,0,0,46)
    hdr.BackgroundColor3=C.SF; hdr.LayoutOrder=1; aC(hdr,8); aS(hdr,C.AC,1)
    aP(hdr,8,12,8,12); hdr.Parent=root
    local t1=Instance.new("TextLabel"); t1.Size=UDim2.new(0.65,0,0,19)
    t1.BackgroundTransparency=1; t1.Font=Enum.Font.GothamBold; t1.Text="NAKRUF Logic"
    t1.TextColor3=C.TX; t1.TextSize=15; t1.TextXAlignment=Enum.TextXAlignment.Left; t1.Parent=hdr
    local t2=Instance.new("TextLabel"); t2.Position=UDim2.new(0.65,0,0,0)
    t2.Size=UDim2.new(0.35,0,0,19); t2.BackgroundTransparency=1
    t2.Font=Enum.Font.GothamBold; t2.Text="v2.0"; t2.TextColor3=C.AC; t2.TextSize=13
    t2.TextXAlignment=Enum.TextXAlignment.Right; t2.Parent=hdr
    local t3=Instance.new("TextLabel"); t3.Position=UDim2.new(0,0,0,23)
    t3.Size=UDim2.new(1,0,0,12); t3.BackgroundTransparency=1; t3.Font=Enum.Font.Gotham
    t3.Text="AI Code Generator - Roblox Studio"; t3.TextColor3=C.DM; t3.TextSize=9
    t3.TextXAlignment=Enum.TextXAlignment.Left; t3.Parent=hdr
end
do
    local dv=Instance.new("Frame"); dv.Size=UDim2.new(1,0,0,1)
    dv.BackgroundColor3=C.AC; dv.BorderSizePixel=0; dv.LayoutOrder=2; dv.Parent=root
end


-- /// API Giriş Kısmı ///
local apiSec=mkSec(root,3)
mkTag(apiSec,"API KEY",1)
local apiBox=Instance.new("TextBox"); apiBox.Size=UDim2.new(1,0,0,26)
apiBox.BackgroundColor3=C.SF2; apiBox.Font=Enum.Font.Code
apiBox.PlaceholderText="API Key girin..."; apiBox.PlaceholderColor3=C.DM
apiBox.Text=""; apiBox.TextColor3=C.TX; apiBox.TextSize=10
apiBox.ClearTextOnFocus=false; apiBox.TextXAlignment=Enum.TextXAlignment.Left
apiBox.LayoutOrder=2; aC(apiBox,5); local apiStroke=aS(apiBox,C.BO,1)
aP(apiBox,0,8,0,8); apiBox.Parent=apiSec

local apiSt=Instance.new("TextLabel"); apiSt.Size=UDim2.new(1,0,0,10)
apiSt.BackgroundTransparency=1; apiSt.Font=Enum.Font.Gotham; apiSt.Text=""
apiSt.TextColor3=C.RE; apiSt.TextSize=9; apiSt.TextXAlignment=Enum.TextXAlignment.Left
apiSt.LayoutOrder=3; apiSt.Parent=apiSec

mkTag(apiSec,"AI PROVIDER  /  MODEL",4)

local pvRow=Instance.new("Frame"); pvRow.Size=UDim2.new(1,0,0,26)
pvRow.BackgroundTransparency=1; pvRow.LayoutOrder=5; pvRow.Parent=apiSec

local pvBtn=Instance.new("TextButton"); pvBtn.Size=UDim2.new(0.46,0,1,0)
pvBtn.BackgroundColor3=C.SF2; pvBtn.Font=Enum.Font.GothamMedium
pvBtn.Text="OpenAI v"; pvBtn.TextColor3=C.TX; pvBtn.TextSize=11
pvBtn.AutoButtonColor=false; aC(pvBtn,5); aS(pvBtn,C.BO,1); pvBtn.Parent=pvRow

local mdlBtn=Instance.new("TextButton"); mdlBtn.Position=UDim2.new(0.52,0,0,0)
mdlBtn.Size=UDim2.new(0.48,0,1,0); mdlBtn.BackgroundColor3=C.SF2
mdlBtn.Font=Enum.Font.GothamMedium; mdlBtn.Text="gpt-4o v"; mdlBtn.TextColor3=C.BL
mdlBtn.TextSize=10; mdlBtn.AutoButtonColor=false
mdlBtn.TextTruncate=Enum.TextTruncate.AtEnd
aC(mdlBtn,5); aS(mdlBtn,C.BL,1); mdlBtn.Parent=pvRow

local mdlDrop=Instance.new("Frame"); mdlDrop.Size=UDim2.new(1,0,0,0)
mdlDrop.AutomaticSize=Enum.AutomaticSize.Y; mdlDrop.BackgroundColor3=C.SF3
mdlDrop.Visible=false; mdlDrop.LayoutOrder=6
aC(mdlDrop,6); aS(mdlDrop,C.BL,1); aP(mdlDrop,4,6,4,6); aVL(mdlDrop,2)
mdlDrop.Parent=apiSec


-- /// Şablonlar ///
local tplSec=mkSec(root,4)
mkTag(tplSec,"SABLONLAR -- hizli baslangic",1)

local tplScroll=Instance.new("ScrollingFrame"); tplScroll.Size=UDim2.new(1,0,0,26)
tplScroll.BackgroundTransparency=1; tplScroll.ScrollBarThickness=0
tplScroll.CanvasSize=UDim2.new(0,0,0,0); tplScroll.AutomaticCanvasSize=Enum.AutomaticSize.X
tplScroll.ScrollingDirection=Enum.ScrollingDirection.X; tplScroll.LayoutOrder=2
tplScroll.Parent=tplSec

local tplRow=Instance.new("Frame"); tplRow.Size=UDim2.fromScale(1,1)
tplRow.BackgroundTransparency=1; aHL(tplRow,4); tplRow.Parent=tplScroll

local TPLS={
    {n="Leaderboard",  p="Leaderstats sistemi olustur. Coins ve Kills degerleri olsun, guzel tasarim."},
    {n="Shop GUI",     p="Coin ile alinan 3 itemli animasyonlu ve modern bir Shop GUI olustur."},
    {n="NPC AI",       p="Yakindaki oyunculari tespit eden ve kovalayan NPC scripti yaz. PathfindingService kullan."},
    {n="Kapi",         p="ProximityPrompt ile acilip kapanan Tween animasyonlu kapi sistemi yap."},
    {n="Admin Panel",  p="Kick Ban Speed God mode ve TP komutlari olan admin panel GUI yap."},
    {n="Coin",         p="Haritaya dagilan toplanabilen coin sistemi yap. Ses efekti ve GUI counter."},
    {n="Timer",        p="60 saniye geri sayan bitince Sure Doldu gosteren modern timer GUI yap."},
    {n="DataStore",    p="PlayerData sistemi: Coins Level XP kaydet ve yukle. LeaveEvent ve otosave."},
    {n="Tween",        p="Parti surekli hareket ettiren ve donduran Tween animasyon scripti yap."},
    {n="Silah",        p="Tool tabanli silah: ates et ses cal Raycast hasar sistemi animasyon."},
}
local tplBtns={}
for i,tpl in ipairs(TPLS) do
    local b=Instance.new("TextButton"); b.Size=UDim2.new(0,0,1,-2)
    b.AutomaticSize=Enum.AutomaticSize.X; b.BackgroundColor3=C.SF2
    b.Font=Enum.Font.GothamMedium; b.Text=tpl.n; b.TextColor3=C.TX
    b.TextSize=10; b.AutoButtonColor=false; b.LayoutOrder=i
    aC(b,5); aS(b,C.BO,1); aP(b,0,8,0,8); b.Parent=tplRow
    mkHov(b,C.SF2,C.SF3,C.SF); tplBtns[i]=b
end


-- /// Prompt Girişi ///
local pmSec=mkSec(root,5)

local pmHdr=Instance.new("Frame"); pmHdr.Size=UDim2.new(1,0,0,14)
pmHdr.BackgroundTransparency=1; pmHdr.LayoutOrder=1; pmHdr.Parent=pmSec

local pmLbl=Instance.new("TextLabel"); pmLbl.Size=UDim2.new(0.4,0,1,0)
pmLbl.BackgroundTransparency=1; pmLbl.Font=Enum.Font.GothamBold; pmLbl.Text="PROMPT"
pmLbl.TextColor3=C.DM; pmLbl.TextSize=9;pmLbl.TextXAlignment=Enum.TextXAlignment.Left; pmLbl.Parent=pmHdr

local convLbl=Instance.new("TextLabel"); convLbl.Position=UDim2.new(0.4,0,0,0)
convLbl.Size=UDim2.new(0.35,0,1,0); convLbl.BackgroundTransparency=1
convLbl.Font=Enum.Font.Gotham; convLbl.Text=""; convLbl.TextColor3=C.BL
convLbl.TextSize=9; convLbl.TextXAlignment=Enum.TextXAlignment.Center; convLbl.Parent=pmHdr

local clrBtn=Instance.new("TextButton"); clrBtn.Position=UDim2.new(0.75,0,0,0)
clrBtn.Size=UDim2.new(0.25,0,1,0); clrBtn.BackgroundTransparency=1
clrBtn.Font=Enum.Font.Gotham; clrBtn.Text="Temizle"; clrBtn.TextColor3=C.RE
clrBtn.TextSize=8; clrBtn.AutoButtonColor=false
clrBtn.TextXAlignment=Enum.TextXAlignment.Right; clrBtn.Parent=pmHdr

local pmBox=Instance.new("TextBox"); pmBox.Size=UDim2.new(1,0,0,110)
pmBox.BackgroundColor3=C.SF2; pmBox.Font=Enum.Font.Gotham
pmBox.PlaceholderText="Ne uretmemi istiyorsun?..."; pmBox.PlaceholderColor3=C.DM
pmBox.Text=""; pmBox.TextColor3=C.TX; pmBox.TextSize=12
pmBox.TextWrapped=true; pmBox.MultiLine=true; pmBox.ClearTextOnFocus=false
pmBox.TextXAlignment=Enum.TextXAlignment.Left; pmBox.TextYAlignment=Enum.TextYAlignment.Top
pmBox.LayoutOrder=2; aC(pmBox,6); local pmStroke=aS(pmBox,C.BO,1)
aP(pmBox,7,9,7,9); pmBox.Parent=pmSec

local charLbl=Instance.new("TextLabel"); charLbl.Size=UDim2.new(1,0,0,10)
charLbl.BackgroundTransparency=1; charLbl.Font=Enum.Font.Gotham; charLbl.Text="0 / 4000"
charLbl.TextColor3=C.DM; charLbl.TextSize=9; charLbl.TextXAlignment=Enum.TextXAlignment.Right
charLbl.LayoutOrder=3; charLbl.Parent=pmSec


-- /// Ayarlar Çubuğu ///
local optSec=mkSec(root,6)
local optRow=Instance.new("Frame"); optRow.Size=UDim2.new(1,0,0,26)
optRow.BackgroundTransparency=1; optRow.LayoutOrder=1; optRow.Parent=optSec

local tempLbl=Instance.new("TextLabel"); tempLbl.Size=UDim2.new(0.5,0,1,0)
tempLbl.BackgroundTransparency=1; tempLbl.Font=Enum.Font.GothamMedium
tempLbl.Text="Yaraticilik: 0.2"; tempLbl.TextColor3=C.TX; tempLbl.TextSize=11
tempLbl.TextXAlignment=Enum.TextXAlignment.Left; tempLbl.Parent=optRow

local tempM=Instance.new("TextButton"); tempM.Size=UDim2.new(0,26,1,0)
tempM.Position=UDim2.new(0.5,0,0,0); tempM.BackgroundColor3=C.SF2
tempM.Font=Enum.Font.GothamBold; tempM.Text="-"; tempM.TextColor3=C.TX
tempM.TextSize=14; tempM.AutoButtonColor=false; aC(tempM,5); aS(tempM,C.BO,1); tempM.Parent=optRow

local tempV=Instance.new("TextLabel"); tempV.Size=UDim2.new(0,36,1,0)
tempV.Position=UDim2.new(0.5,30,0,0); tempV.BackgroundColor3=C.SF3
tempV.Font=Enum.Font.GothamBold; tempV.Text="0.2"; tempV.TextColor3=C.TX
tempV.TextSize=11; tempV.TextXAlignment=Enum.TextXAlignment.Center; aC(tempV,4); tempV.Parent=optRow

local tempP=Instance.new("TextButton"); tempP.Size=UDim2.new(0,26,1,0)
tempP.Position=UDim2.new(0.5,70,0,0); tempP.BackgroundColor3=C.SF2
tempP.Font=Enum.Font.GothamBold; tempP.Text="+"; tempP.TextColor3=C.TX
tempP.TextSize=14; tempP.AutoButtonColor=false; aC(tempP,5); aS(tempP,C.BO,1); tempP.Parent=optRow

local langBtn=Instance.new("TextButton"); langBtn.Size=UDim2.new(0,34,1,0)
langBtn.Position=UDim2.new(1,-34,0,0); langBtn.BackgroundColor3=C.SF3
langBtn.Font=Enum.Font.GothamBold; langBtn.Text="TR"; langBtn.TextColor3=C.BL
langBtn.TextSize=10; langBtn.AutoButtonColor=false
aC(langBtn,5); aS(langBtn,C.BL,1); langBtn.Parent=optRow


-- /// Aksiyon Butonları ///
local actSec=Instance.new("Frame"); actSec.Size=UDim2.new(1,0,0,0)
actSec.AutomaticSize=Enum.AutomaticSize.Y; actSec.BackgroundTransparency=1
actSec.LayoutOrder=7; aVL(actSec,6); actSec.Parent=root

local genBtn=Instance.new("TextButton"); genBtn.Size=UDim2.new(1,0,0,36)
genBtn.BackgroundColor3=C.AC; genBtn.Font=Enum.Font.GothamBold
genBtn.Text="Kod Uret"; genBtn.TextColor3=C.TX; genBtn.TextSize=13
genBtn.AutoButtonColor=false; genBtn.LayoutOrder=1; aC(genBtn,7); genBtn.Parent=actSec

local subRow=Instance.new("Frame"); subRow.Size=UDim2.new(1,0,0,26)
subRow.BackgroundTransparency=1; subRow.LayoutOrder=2; subRow.Parent=actSec

local updBtn=Instance.new("TextButton"); updBtn.Size=UDim2.new(0.48,0,1,0)
updBtn.BackgroundColor3=C.BL; updBtn.Font=Enum.Font.GothamMedium
updBtn.Text="Secili Script"; updBtn.TextColor3=C.TX; updBtn.TextSize=10
updBtn.AutoButtonColor=false; aC(updBtn,5); updBtn.Parent=subRow

local fixBtn=Instance.new("TextButton"); fixBtn.Position=UDim2.new(0.52,0,0,0)
fixBtn.Size=UDim2.new(0.48,0,1,0); fixBtn.BackgroundColor3=C.WA
fixBtn.Font=Enum.Font.GothamMedium; fixBtn.Text="Hatayi Duzelt"
fixBtn.TextColor3=Color3.fromRGB(20,15,0); fixBtn.TextSize=10
fixBtn.AutoButtonColor=false; aC(fixBtn,5); fixBtn.Parent=subRow


-- /// Kod Önizleme Alanı ///
local prevSec=mkSec(root,8)

local prevHdr=Instance.new("Frame"); prevHdr.Size=UDim2.new(1,0,0,20)
prevHdr.BackgroundTransparency=1; prevHdr.LayoutOrder=1; prevHdr.Parent=prevSec

local prevLbl=Instance.new("TextLabel"); prevLbl.Size=UDim2.new(0.4,0,1,0)
prevLbl.BackgroundTransparency=1; prevLbl.Font=Enum.Font.GothamBold
prevLbl.Text="CIKTI / ONIZLEME"; prevLbl.TextColor3=C.DM; prevLbl.TextSize=9; prevLbl.TextXAlignment=Enum.TextXAlignment.Left; prevLbl.Parent=prevHdr

local injBtn=Instance.new("TextButton"); injBtn.Position=UDim2.new(0.41,0,0,0)
injBtn.Size=UDim2.new(0.28,0,1,0); injBtn.BackgroundColor3=C.GR
injBtn.Font=Enum.Font.GothamMedium; injBtn.Text="Inject"
injBtn.TextColor3=Color3.fromRGB(5,25,10); injBtn.TextSize=10
injBtn.AutoButtonColor=false; aC(injBtn,4); injBtn.Parent=prevHdr

local snpBtn=Instance.new("TextButton"); snpBtn.Position=UDim2.new(0.72,0,0,0)
snpBtn.Size=UDim2.new(0.28,0,1,0); snpBtn.BackgroundColor3=C.BL
snpBtn.Font=Enum.Font.GothamMedium; snpBtn.Text="Snippet"; snpBtn.TextColor3=C.TX
snpBtn.TextSize=10; snpBtn.AutoButtonColor=false; aC(snpBtn,4); snpBtn.Parent=prevHdr

local outScroll=Instance.new("ScrollingFrame"); outScroll.Size=UDim2.new(1,0,0,180)
outScroll.BackgroundColor3=C.SF2; outScroll.ScrollBarThickness=3
outScroll.ScrollBarImageColor3=C.AC; outScroll.CanvasSize=UDim2.new(0,0,0,0)
outScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
outScroll.ScrollingDirection=Enum.ScrollingDirection.Y; outScroll.ClipsDescendants=true
outScroll.LayoutOrder=2; aC(outScroll,6); aP(outScroll,6,8,6,8); outScroll.Parent=prevSec

local outBox=Instance.new("TextBox"); outBox.Size=UDim2.new(1,0,0,0)
outBox.AutomaticSize=Enum.AutomaticSize.Y; outBox.BackgroundTransparency=1
outBox.Font=Enum.Font.Code; outBox.Text="-- Kod burada gorunecek..."
outBox.TextColor3=C.DM; outBox.TextSize=10; outBox.TextWrapped=true
outBox.MultiLine=true; outBox.TextXAlignment=Enum.TextXAlignment.Left
outBox.TextYAlignment=Enum.TextYAlignment.Top; outBox.ClearTextOnFocus=false
outBox.Parent=outScroll

local stLbl=Instance.new("TextLabel"); stLbl.Size=UDim2.new(1,0,0,12)
stLbl.BackgroundTransparency=1; stLbl.Font=Enum.Font.Gotham; stLbl.Text=""
stLbl.TextColor3=C.DM; stLbl.TextSize=9; stLbl.TextXAlignment=Enum.TextXAlignment.Left
stLbl.LayoutOrder=3; stLbl.Parent=prevSec


-- /// Sohbet Geçmişi ///
local histSec=mkSec(root,9)

local histHdr=Instance.new("Frame"); histHdr.Size=UDim2.new(1,0,0,22)
histHdr.BackgroundTransparency=1; histHdr.LayoutOrder=1; histHdr.Parent=histSec

local histTL=Instance.new("TextLabel"); histTL.Size=UDim2.new(0.75,0,1,0)
histTL.BackgroundTransparency=1; histTL.Font=Enum.Font.GothamBold
histTL.Text="KOD GECMISI  (son 10)"; histTL.TextColor3=C.DM; histTL.TextSize=9; histTL.TextXAlignment=Enum.TextXAlignment.Left; histTL.Parent=histHdr

local histArr=Instance.new("TextButton"); histArr.Size=UDim2.new(0.25,0,1,0)
histArr.Position=UDim2.new(0.75,0,0,0); histArr.BackgroundTransparency=1
histArr.Font=Enum.Font.GothamBold; histArr.Text="> AC"; histArr.TextColor3=C.BL
histArr.TextSize=9; histArr.AutoButtonColor=false
histArr.TextXAlignment=Enum.TextXAlignment.Right; histArr.Parent=histHdr

local histList=Instance.new("Frame"); histList.Size=UDim2.new(1,0,0,0)
histList.AutomaticSize=Enum.AutomaticSize.Y; histList.BackgroundTransparency=1
histList.Visible=false; histList.LayoutOrder=2; aVL(histList,3); histList.Parent=histSec


-- /// Hata Düzeltici ///
local errSec=mkSec(root,10)

local errHdr=Instance.new("Frame"); errHdr.Size=UDim2.new(1,0,0,22)
errHdr.BackgroundTransparency=1; errHdr.LayoutOrder=1; errHdr.Parent=errSec

local errTL=Instance.new("TextLabel"); errTL.Size=UDim2.new(0.75,0,1,0)
errTL.BackgroundTransparency=1; errTL.Font=Enum.Font.GothamBold
errTL.Text="HATA DUZELTICI"; errTL.TextColor3=C.DM; errTL.TextSize=9; errTL.TextXAlignment=Enum.TextXAlignment.Left; errTL.Parent=errHdr

local errArr=Instance.new("TextButton"); errArr.Size=UDim2.new(0.25,0,1,0)
errArr.Position=UDim2.new(0.75,0,0,0); errArr.BackgroundTransparency=1
errArr.Font=Enum.Font.GothamBold; errArr.Text="> AC"; errArr.TextColor3=C.BL
errArr.TextSize=9; errArr.AutoButtonColor=false
errArr.TextXAlignment=Enum.TextXAlignment.Right; errArr.Parent=errHdr

local errBody=Instance.new("Frame"); errBody.Size=UDim2.new(1,0,0,0)
errBody.AutomaticSize=Enum.AutomaticSize.Y; errBody.BackgroundTransparency=1
errBody.Visible=false; errBody.LayoutOrder=2; aVL(errBody,6); errBody.Parent=errSec

local errBox=Instance.new("TextBox"); errBox.Size=UDim2.new(1,0,0,60)
errBox.BackgroundColor3=C.SF2; errBox.Font=Enum.Font.Code
errBox.PlaceholderText="Hata mesajini buraya yapistir (Output penceresinden)..."
errBox.PlaceholderColor3=C.DM; errBox.Text=""; errBox.TextColor3=C.RE
errBox.TextSize=10; errBox.TextWrapped=true; errBox.MultiLine=true
errBox.ClearTextOnFocus=false; errBox.TextXAlignment=Enum.TextXAlignment.Left
errBox.TextYAlignment=Enum.TextYAlignment.Top; errBox.LayoutOrder=1
aC(errBox,5); aP(errBox,6,8,6,8); aS(errBox,C.RE,1); errBox.Parent=errBody

local errFixBtn=Instance.new("TextButton"); errFixBtn.Size=UDim2.new(1,0,0,26)
errFixBtn.BackgroundColor3=C.WA; errFixBtn.Font=Enum.Font.GothamMedium
errFixBtn.Text="Bu Hatayi AI ile Duzelt"; errFixBtn.TextColor3=Color3.fromRGB(20,15,0)
errFixBtn.TextSize=11; errFixBtn.AutoButtonColor=false; errFixBtn.LayoutOrder=2
aC(errFixBtn,5); errFixBtn.Parent=errBody


-- /// Snippet Kütüphanesi ///
local snipSec=mkSec(root,11)

local snipHdr=Instance.new("Frame"); snipHdr.Size=UDim2.new(1,0,0,22)
snipHdr.BackgroundTransparency=1; snipHdr.LayoutOrder=1; snipHdr.Parent=snipSec

local snipTL=Instance.new("TextLabel"); snipTL.Size=UDim2.new(0.75,0,1,0)
snipTL.BackgroundTransparency=1; snipTL.Font=Enum.Font.GothamBold
snipTL.Text="SNIPPET KUTUPHANESI"; snipTL.TextColor3=C.DM; snipTL.TextSize=9; snipTL.TextXAlignment=Enum.TextXAlignment.Left; snipTL.Parent=snipHdr

local snipArr=Instance.new("TextButton"); snipArr.Size=UDim2.new(0.25,0,1,0)
snipArr.Position=UDim2.new(0.75,0,0,0); snipArr.BackgroundTransparency=1
snipArr.Font=Enum.Font.GothamBold; snipArr.Text="> AC"; snipArr.TextColor3=C.BL
snipArr.TextSize=9; snipArr.AutoButtonColor=false
snipArr.TextXAlignment=Enum.TextXAlignment.Right; snipArr.Parent=snipHdr

local snipBody=Instance.new("Frame"); snipBody.Size=UDim2.new(1,0,0,0)
snipBody.AutomaticSize=Enum.AutomaticSize.Y; snipBody.BackgroundTransparency=1
snipBody.Visible=false; snipBody.LayoutOrder=2; aVL(snipBody,4); snipBody.Parent=snipSec

local snipNameBox=Instance.new("TextBox"); snipNameBox.Size=UDim2.new(1,0,0,26)
snipNameBox.BackgroundColor3=C.SF2; snipNameBox.Font=Enum.Font.Gotham
snipNameBox.PlaceholderText="Snippet adi gir..."; snipNameBox.PlaceholderColor3=C.DM
snipNameBox.Text=""; snipNameBox.TextColor3=C.TX; snipNameBox.TextSize=11
snipNameBox.ClearTextOnFocus=false; snipNameBox.TextXAlignment=Enum.TextXAlignment.Left
snipNameBox.LayoutOrder=1; aC(snipNameBox,5); aP(snipNameBox,0,8,0,8)
aS(snipNameBox,C.BO,1); snipNameBox.Parent=snipBody

local snipSaveBtn=Instance.new("TextButton"); snipSaveBtn.Size=UDim2.new(1,0,0,24)
snipSaveBtn.BackgroundColor3=C.BL; snipSaveBtn.Font=Enum.Font.GothamMedium
snipSaveBtn.Text="Mevcut Kodu Snippet Olarak Kaydet"; snipSaveBtn.TextColor3=C.TX
snipSaveBtn.TextSize=11; snipSaveBtn.AutoButtonColor=false; snipSaveBtn.LayoutOrder=2
aC(snipSaveBtn,5); snipSaveBtn.Parent=snipBody

local snipList=Instance.new("Frame"); snipList.Size=UDim2.new(1,0,0,0)
snipList.AutomaticSize=Enum.AutomaticSize.Y; snipList.BackgroundTransparency=1
snipList.LayoutOrder=3; aVL(snipList,3); snipList.Parent=snipBody


-- /// Alt Kısım ve Toolbar ///
do
    local ft=Instance.new("TextLabel"); ft.Size=UDim2.new(1,0,0,14)
    ft.BackgroundTransparency=1; ft.Font=Enum.Font.Gotham
    ft.Text="NAKRUF Logic v2.0  *  AI Code Generator"; ft.TextColor3=C.DM
    ft.TextSize=9; ft.TextXAlignment=Enum.TextXAlignment.Center
    ft.LayoutOrder=99; ft.Parent=root
end
local tb=plugin:CreateToolbar("NAKRUF")
local tbBtn=tb:CreateButton("NakrufV2","Open NAKRUF Logic v2","")
tbBtn.Click:Connect(function() widget.Enabled=not widget.Enabled end)


-- /// Çalışma Zamanı Verileri ///
local convHist={}
local lastCode=""
local codeHist={}
local snippets={}
local curTemp=0.2
local curLang="tr"
local selProv="openai"
local selMdl={}
for _,p in ipairs(PROVS) do selMdl[p.key]=Settings.getModel(p.key) or p.def end
do local sv=Settings.getProv(); if sv and PMAP[sv] then selProv=sv end end


-- /// Arayüz Fonksiyonları ///
local function mask(k)
    if type(k)~="string" or #k<1 then return "<>" end
    local n=math.min(4,#k); return ("*"):rep(#k-n)..k:sub(-n)
end
local function setStatus(msg,col) stLbl.Text=msg or ""; stLbl.TextColor3=col or C.DM end
local function setOutput(code,col)
    outBox.Text=code or ""; outBox.TextColor3=col or C.TX
    if code and code~="" then lastCode=code end
end
local function setBusy(on)
    genBtn.Active=not on; genBtn.BackgroundColor3=on and C.ACD or C.AC
    genBtn.Text=on and "Uretiliyor..." or "Kod Uret"
end
local function apiMask()
    local k=Settings.getKey()
    if k then
        apiBox.Text=mask(k); apiSt.Text="Key yuklendi."; apiSt.TextColor3=C.GR
    else
        apiBox.Text=""; apiSt.Text="API Key gerekli."; apiSt.TextColor3=C.RE
    end
end
local function updateConvLbl()
    local n=#convHist; convLbl.Text=n>0 and (n.." mesaj") or ""
end
local function shortMdl(m)
    return (m:match("([^/]+)$") or m):gsub("%-20%d%d%d%d%d%d","")
end
local function updatePvUI()
    local pd=PMAP[selProv]; pvBtn.Text=pd.lbl.." v"
    mdlBtn.Text=shortMdl(selMdl[selProv]).." v"
end
local function updateTemp()
    local t=math.floor(curTemp*10+0.5)/10; curTemp=t
    tempV.Text=string.format("%.1f",t)
    local col=t<=0.3 and C.BL or t<=0.6 and C.GR or C.WA; tempV.TextColor3=col
    tempLbl.Text=(curLang=="en" and "Creativity: " or "Yaraticilik: ")..string.format("%.1f",t)
end


-- /// Geçmiş Yönetimi ///
local function loadHistUI()
    for _,ch in ipairs(histList:GetChildren()) do
        if not ch:IsA("UIListLayout") then ch:Destroy() end
    end
    if #codeHist==0 then
        local el=Instance.new("TextLabel"); el.Size=UDim2.new(1,0,0,18)
        el.BackgroundTransparency=1; el.Font=Enum.Font.Gotham
        el.Text="Henuz gecmis yok."; el.TextColor3=C.DM; el.TextSize=10
        el.TextXAlignment=Enum.TextXAlignment.Center; el.LayoutOrder=1; el.Parent=histList
        return
    end
    for i=#codeHist,1,-1 do
        local e=codeHist[i]; local lo=#codeHist-i+1
        local ef=Instance.new("Frame"); ef.Size=UDim2.new(1,0,0,0)
        ef.AutomaticSize=Enum.AutomaticSize.Y; ef.BackgroundColor3=C.SF2
        ef.LayoutOrder=lo; aC(ef,5); aP(ef,5,8,5,8); aVL(ef,2); ef.Parent=histList
        local el=Instance.new("TextLabel"); el.Size=UDim2.new(0.72,0,0,14)
        el.BackgroundTransparency=1; el.Font=Enum.Font.GothamMedium
        el.Text=e.prompt or ""; el.TextColor3=C.TX; el.TextSize=10
        el.TextTruncate=Enum.TextTruncate.AtEnd
        el.TextXAlignment=Enum.TextXAlignment.Left; el.LayoutOrder=1; el.Parent=ef
        local es=Instance.new("TextLabel"); es.Size=UDim2.new(1,0,0,10)
        es.BackgroundTransparency=1; es.Font=Enum.Font.Gotham
        es.Text=(e.ts or "").." - "..(shortMdl(e.mdl or ""))
        es.TextColor3=C.DM; es.TextSize=8
        es.TextXAlignment=Enum.TextXAlignment.Left; es.LayoutOrder=2; es.Parent=ef
        local lb=Instance.new("TextButton"); lb.Size=UDim2.new(0.28,0,0,14)
        lb.Position=UDim2.new(0.72,0,0,0); lb.BackgroundColor3=C.BL
        lb.Font=Enum.Font.GothamMedium; lb.Text="Yukle"; lb.TextColor3=C.TX
        lb.TextSize=9; lb.AutoButtonColor=false; aC(lb,4); lb.LayoutOrder=1; lb.Parent=ef
        local code=e.code or ""
        lb.MouseButton1Click:Connect(function()
            setOutput(code,C.TX); setStatus("Gecmisten yuklendi.",C.BL)
        end)
    end
end
local histIdx=0
local function saveToHist(prompt,code,prov,mdl)
    histIdx=histIdx+1
    table.insert(codeHist,{
        ts="#"..histIdx, prompt=prompt:sub(1,40),
        code=code, prov=prov, mdl=mdl
    })
    while #codeHist>10 do table.remove(codeHist,1) end
    Settings.saveHist(codeHist)
    if histList.Visible then loadHistUI() end
end


-- /// Snippet Yönetimi ///
local function loadSnipUI()
    for _,ch in ipairs(snipList:GetChildren()) do
        if not ch:IsA("UIListLayout") then ch:Destroy() end
    end
    if #snippets==0 then
        local el=Instance.new("TextLabel"); el.Size=UDim2.new(1,0,0,18)
        el.BackgroundTransparency=1; el.Font=Enum.Font.Gotham
        el.Text="Henuz snippet yok."; el.TextColor3=C.DM; el.TextSize=10
        el.TextXAlignment=Enum.TextXAlignment.Center; el.LayoutOrder=1; el.Parent=snipList
        return
    end
    for i,sn in ipairs(snippets) do
        local sf=Instance.new("Frame"); sf.Size=UDim2.new(1,0,0,26)
        sf.BackgroundColor3=C.SF2; sf.LayoutOrder=i; aC(sf,5); aP(sf,0,4,0,8); sf.Parent=snipList
        local sl=Instance.new("TextLabel"); sl.Size=UDim2.new(0.55,0,1,0)
        sl.BackgroundTransparency=1; sl.Font=Enum.Font.GothamMedium
        sl.Text=sn.name or ("Snippet "..i); sl.TextColor3=C.TX; sl.TextSize=10
        sl.TextTruncate=Enum.TextTruncate.AtEnd
        sl.TextXAlignment=Enum.TextXAlignment.Left; sl.Parent=sf
        local lsb=Instance.new("TextButton"); lsb.Size=UDim2.new(0.23,0,0.8,0)
        lsb.Position=UDim2.new(0.56,0,0.1,0); lsb.BackgroundColor3=C.BL
        lsb.Font=Enum.Font.GothamMedium; lsb.Text="Yukle"; lsb.TextColor3=C.TX
        lsb.TextSize=9; lsb.AutoButtonColor=false; aC(lsb,4); lsb.Parent=sf
        local dsb=Instance.new("TextButton"); dsb.Size=UDim2.new(0.18,0,0.8,0)
        dsb.Position=UDim2.new(0.81,0,0.1,0); dsb.BackgroundColor3=C.ACD
        dsb.Font=Enum.Font.GothamMedium; dsb.Text="Sil"; dsb.TextColor3=C.TX
        dsb.TextSize=9; dsb.AutoButtonColor=false; aC(dsb,4); dsb.Parent=sf
        local code=sn.code or ""
        lsb.MouseButton1Click:Connect(function()
            setOutput(code,C.TX); setStatus("Snippet yuklendi: "..tostring(sn.name),C.BL)
        end)
        local idx=i
        dsb.MouseButton1Click:Connect(function()
            table.remove(snippets,idx); Settings.saveSnip(snippets); loadSnipUI()
        end)
    end
end


-- /// Model Menüsü ///
local function rebuildMdlDrop()
    for _,ch in ipairs(mdlDrop:GetChildren()) do
        if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end
    end
    local pd=PMAP[selProv]
    for i,m in ipairs(pd.mdls) do
        local sel=(m==selMdl[selProv])
        local mb=Instance.new("TextButton"); mb.Size=UDim2.new(1,0,0,22)
        mb.BackgroundColor3=sel and Color3.fromRGB(30,55,100) or C.SF2
        mb.Font=Enum.Font.Code; mb.Text=m
        mb.TextColor3=sel and C.BL or C.TX
        mb.TextSize=9; mb.AutoButtonColor=false; mb.LayoutOrder=i
        mb.TextXAlignment=Enum.TextXAlignment.Left
        aC(mb,4); aP(mb,0,4,0,4); mb.Parent=mdlDrop
        mkHov(mb,mb.BackgroundColor3,C.SF3,C.SF2)
        mb.MouseButton1Click:Connect(function()
            selMdl[selProv]=m; Settings.saveModel(selProv,m)
            mdlDrop.Visible=false; updatePvUI()
        end)
    end
end


-- /// Başlangıç ///
do
    local ok,err=pcall(function()
        apiMask(); updatePvUI()
        local p=Settings.getPrompt(); if p and p~="" then pmBox.Text=p end
        curTemp=Settings.getTemp(); updateTemp()
        curLang=Settings.getLang(); langBtn.Text=curLang:upper()
        codeHist=Settings.getHist(); snippets=Settings.getSnip()
        if curLang=="en" then pmBox.PlaceholderText="What do you want me to generate?..." end
    end)
    if not ok then warn("[NAKRUF] Startup: "..tostring(err)) end
end
plugin.Unloading:Connect(function()
    pcall(function() Settings.savePrompt(pmBox.Text) end)
end)


-- /// Açılır/Kapanır Menüler ///
mkToggle(histArr,histList,loadHistUI)
mkToggle(errArr,errBody,nil)
mkToggle(snipArr,snipBody,loadSnipUI)


-- /// Buton Tıklamaları ve Olaylar ///
local PC={}; for _,p in ipairs(PROVS) do table.insert(PC,p.key) end

pvBtn.MouseButton1Click:Connect(function()
    mdlDrop.Visible=false
    local nk=PC[1]
    for i,k in ipairs(PC) do if k==selProv then nk=PC[(i%#PC)+1]; break end end
    selProv=nk; Settings.saveProv(nk); updatePvUI()
end)
mkHov(pvBtn,C.SF2,C.SF3,C.SF)

mdlBtn.MouseButton1Click:Connect(function()
    if not mdlDrop.Visible then rebuildMdlDrop() end
    mdlDrop.Visible=not mdlDrop.Visible; updatePvUI()
end)
mkHov(mdlBtn,C.SF2,C.SF3,C.SF)

apiBox.Focused:Connect(function()
    if Settings.hasKey() then apiBox.Text="" end
    apiStroke.Color=C.AC; apiSt.Text=""
end)
apiBox.FocusLost:Connect(function()
    local raw=apiBox.Text; if raw=="" then apiMask(); return end
    if Settings.saveKey(raw) then
        apiBox.Text=mask(raw); apiSt.Text="Key kaydedildi."; apiSt.TextColor3=C.GR
    else
        apiSt.Text="Gecersiz key."; apiSt.TextColor3=C.RE
    end
    apiStroke.Color=C.BO
end)

pmBox.Focused:Connect(function() pmStroke.Color=C.AC end)
pmBox.FocusLost:Connect(function()
    pmStroke.Color=C.BO; pcall(function() Settings.savePrompt(pmBox.Text) end)
end)
pmBox:GetPropertyChangedSignal("Text"):Connect(function()
    local n=#pmBox.Text; charLbl.Text=n.." / 4000"
    charLbl.TextColor3=n>3800 and C.RE or C.DM
end)

for i,tpl in ipairs(TPLS) do
    local t=tpl.p
    tplBtns[i].MouseButton1Click:Connect(function()
        pmBox.Text=t; charLbl.Text=#t.." / 4000"
    end)
end

tempM.MouseButton1Click:Connect(function()
    curTemp=math.max(0,curTemp-0.1); Settings.saveTemp(curTemp); updateTemp()
end)
tempP.MouseButton1Click:Connect(function()
    curTemp=math.min(1,curTemp+0.1); Settings.saveTemp(curTemp); updateTemp()
end)
mkHov(tempM,C.SF2,C.SF3,C.SF); mkHov(tempP,C.SF2,C.SF3,C.SF)

langBtn.MouseButton1Click:Connect(function()
    curLang=(curLang=="tr") and "en" or "tr"
    Settings.saveLang(curLang); langBtn.Text=curLang:upper()
    updateTemp()
    pmBox.PlaceholderText=curLang=="en" and "What do you want me to generate?..." or "Ne uretmemi istiyorsun?..."
end)

clrBtn.MouseButton1Click:Connect(function()
    convHist={}; updateConvLbl(); setStatus("Sohbet gecmisi temizlendi.",C.WA)
end)

injBtn.MouseButton1Click:Connect(function()
    if lastCode=="" then setStatus("Inject edilecek kod yok.",C.RE); return end
    local ok,msg=Proc.inject(lastCode); setStatus(msg,ok and C.GR or C.RE)
end)

updBtn.MouseButton1Click:Connect(function()
    if lastCode=="" then setStatus("Guncellenecek kod yok.",C.RE); return end
    local ok,msg=Proc.updateSel(lastCode); setStatus(msg,ok and C.GR or C.RE)
end)
mkHov(updBtn,C.BL,C.BLD,C.BLD)

fixBtn.MouseButton1Click:Connect(function()
    errBody.Visible=true; errArr.Text="V KAPAT"; errBox:CaptureFocus()
end)
mkHov(fixBtn,C.WA,Color3.fromRGB(230,155,30),Color3.fromRGB(200,130,10))

snpBtn.MouseButton1Click:Connect(function()
    if lastCode=="" then setStatus("Kaydedilecek kod yok.",C.RE); return end
    snipBody.Visible=true; snipArr.Text="V KAPAT"; loadSnipUI()
    setStatus("Snippet adini gir ve Kaydet butonuna bas.",C.BL)
    snipNameBox:CaptureFocus()
end)

snipSaveBtn.MouseButton1Click:Connect(function()
    if lastCode=="" then setStatus("Kaydedilecek kod yok.",C.RE); return end
    local name=snipNameBox.Text:match("^%s*(.-)%s*$")
    if name=="" then name="Snippet "..(#snippets+1) end
    table.insert(snippets,{name=name,code=lastCode})
    if #snippets>20 then table.remove(snippets,1) end
    Settings.saveSnip(snippets); snipNameBox.Text=""; loadSnipUI()
    setStatus("Snippet kaydedildi: "..name,C.GR)
end)
mkHov(snipSaveBtn,C.BL,C.BLD,C.BLD)
mkHov(genBtn,C.AC,C.ACD,Color3.fromRGB(120,12,12))
mkHov(injBtn,C.GR,Color3.fromRGB(45,160,75),Color3.fromRGB(35,130,60))
mkHov(snpBtn,C.BL,C.BLD,C.BLD)


-- /// Hata Düzeltme İşlemi ///
errFixBtn.MouseButton1Click:Connect(function()
    if genBtn.Active==false then return end
    local errText=errBox.Text:match("^%s*(.-)%s*$")
    if errText=="" then setStatus("Hata mesaji girin.",C.RE); return end
    if not Settings.hasKey() then setStatus("API Key gerekli.",C.RE); return end
    local fixPrompt=(curLang=="en" and "Fix this Roblox Lua error:\n\n"
        or "Bu Roblox Lua hatasini duzelt:\n\n")..errText
    if lastCode~="" then
        fixPrompt=fixPrompt.."\n\n[Mevcut Kod]\n"..lastCode:sub(1,2000)
    end
    setBusy(true); setStatus("AI hatay analiz ediyor...",C.WA)
    task.spawn(function()
        local ok,code=API.send(Settings.getKey(),fixPrompt,"",selProv,selMdl[selProv],{},curTemp,curLang)
        if ok then
            setOutput(code,C.TX)
            setStatus("Duzeltilmis kod hazir. Inject icin butona bas.",C.GR)
            table.insert(convHist,{role="user",content=fixPrompt})
            table.insert(convHist,{role="assistant",content=code})
            while #convHist>20 do table.remove(convHist,1) end
            updateConvLbl()
            saveToHist("[HATA] "..errText:sub(1,30),code,selProv,selMdl[selProv])
        else
            setOutput("-- Hata: "..code,C.RE); setStatus(code,C.RE)
        end
        setBusy(false)
    end)
end)
mkHov(errFixBtn,C.WA,Color3.fromRGB(230,155,30),Color3.fromRGB(200,130,10))


-- /// Kod Üretme İşlemi ///
genBtn.MouseButton1Click:Connect(function()
    if genBtn.Active==false then return end
    if not Settings.hasKey() then
        apiSt.Text="API Key gerekli."; apiSt.TextColor3=C.RE; return
    end
    local prompt=pmBox.Text:match("^%s*(.-)%s*$")
    if prompt=="" then setStatus("Prompt bos.",C.RE); return end
    setBusy(true); setOutput("-- Uretiliyor...",C.DM); setStatus("Context aliniyor...",C.DM)
    task.spawn(function()
        local ctx=""
        pcall(function() ctx=getCtx() end)
        local pLabel=(PMAP[selProv] or {lbl=selProv}).lbl
        setStatus(pLabel.." / "..shortMdl(selMdl[selProv]).."...",C.DM)
        local ok,code=API.send(Settings.getKey(),prompt,ctx,selProv,selMdl[selProv],convHist,curTemp,curLang)
        if not ok then
            setOutput("-- Hata: "..code,C.RE); setStatus(code,C.RE)
            setBusy(false); return
        end
        setOutput(code,C.TX)
        local userMsg=prompt
        if type(ctx)=="string" and ctx~="" and ctx~="No active selection." then
            userMsg="[Context]\n"..ctx.."\n\n[Task]\n"..prompt
        end
        table.insert(convHist,{role="user",content=userMsg})
        table.insert(convHist,{role="assistant",content=code})
        while #convHist>20 do table.remove(convHist,1) end
        updateConvLbl()
        local pOk,pMsg=Proc.inject(code)
        setStatus(pMsg,pOk and C.GR or C.RE)
        saveToHist(prompt,code,selProv,selMdl[selProv])
        setBusy(false)
    end)
end)
