-- SANDWORM HUB v1.0 | Auto Farm + Auto Eat + Inf Stamina | by ZynexDev
-- Game: Kum Solucani Oyun Alani (u10774386745)
-- Mobile + PC | Client-authoritative worm state (u134) uzerinde calisir
-- Dogrulama modu: her ozellik KSWH.log'a olay yazar, teker teker test edilebilir

-- =============================== GEN GUARD ===============================
local GEN = (getgenv().KSWH_GEN or 0) + 1
getgenv().KSWH_GEN = GEN
if getgenv().KSWH_CLEANUP then pcall(getgenv().KSWH_CLEANUP) end

local KSWH = {
    GEN = GEN,
    cfg = getgenv().KSWH and getgenv().KSWH.cfg or {
        farm = false, farmPin = 0.3,
        autoEat = false,
        infStamina = false,
        speed = false, speedVal = 45,
        eventMon = true,
        showNotify = true,
    },
    log = {},
    ui = {},
    fn = {},
    stats = { smashed = 0, npcs = 0 },
}
getgenv().KSWH = KSWH

function KSWH.addLog(tag, msg)
    local entry = string.format("[%s] %s", tostring(tag), tostring(msg))
    table.insert(KSWH.log, entry)
    if #KSWH.log > 300 then table.remove(KSWH.log, 1) end
end

-- baglantilari toplayip reload'da temizle
local baglantilar = {}
local function connect(sg, fn) table.insert(baglantilar, sg:Connect(fn)) end
getgenv().KSWH_CLEANUP = function()
    for _, c in ipairs(baglantilar) do pcall(function() c:Disconnect() end) end
end

-- =============================== SERVISLER ===============================
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local SetForm = RS.Sandworm.Remotes.SetForm

local Act = RS.Sandworm.Remotes.Act
local XpEvent = RS.Xp.XpEvent

-- =============================== WORM STATE ===============================
-- u134 state tablosu: SandwormClient'in worm fizigi state'i.
-- Erisim: filtergc Constants={"Unbury"} -> 1. fonksiyonun upvalue 1
-- (canli dogrulanmis yontem; filtergc table yolu bayat referans donduruyor)
local function findWormState()
    local ok, fs = pcall(function() return filtergc("function", { Constants = { "Unbury" } }) end)
    if not ok or not fs then return nil end
    for _, f in ipairs(fs) do
        for i = 1, 40 do
            local ok2, up = pcall(debug.getupvalue, f, i)
            if not ok2 then break end
            if type(up) == "table" and typeof(up.pos) == "Vector3"
                and type(up.speed) == "number" and type(up.biteAt) == "number" then
                return up
            end
        end
    end
    return nil
end

local state = findWormState()
KSWH.addLog("INIT", "worm state found: " .. tostring(state ~= nil))

local function refreshState()
    state = findWormState()
    return state
end

local function isWorm()
    local ch = LP.Character
    return ch and ch:GetAttribute("Worm") == true, ch
end

-- pozisyon yardimcilari: solucansa state.pos, degilse HRP CFrame
local function posAl()
    local ch = LP.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.Position end
    return Vector3.zero
end

-- NOT: isinla() fonksiyonu TAMAMEN KALDIRILDI (kullanici talimati: isinlanma
-- yapan HICBIR kod kalmayacak). TP ve tum hareket SADECE surunerek yapilir.

-- =============================== FLUENT UI ===============================
getgenv().KSWH_STAGE = "fluent-oncesi"
local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/myheisenberg/Fluent-Renewed/main/Fluent.luau"))()
getgenv().KSWH_STAGE = "fluent-yuklendi: " .. type(Fluent)
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/myheisenberg/Fluent-Renewed/main/Addons/SaveManager.luau"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/myheisenberg/Fluent-Renewed/main/Addons/InterfaceManager.luau"))()
getgenv().KSWH_STAGE = "addonlar-yuklendi"

-- MOBIL TESPIT (ROCHESS BIREBIR): SADECE TouchEnabled - KeyboardEnabled
-- eklemeyin! Emulator KeyboardEnabled=true donebilir -> PC mode bug'i
-- (kullanici: 'pc mode algiliyor aq' - bu yuzden buton/goz calismiyordu)
local isMobile = (UIS.TouchEnabled == true)
local vp = workspace.CurrentCamera.ViewportSize
-- ROCHESS BIREBIR boyutlandirma: vp.Y-90, max 440 (500 yapinca alt tasiyordu)
local WIN_W = isMobile and math.clamp(vp.X - 24, 300, 480) or 580
local WIN_H = isMobile and math.clamp(vp.Y - 90, 320, 440) or 460

-- HAYALET PENCERE TEMIZLIGI: onceki yuklemelerden kalan Fluent GUI'leri yok et
-- (CreateWindow'dan ONCE calisir - kendimize dokunmaz; sonda isim ZynexSandworm yapilir)
do
    local kokOk, kok = pcall(function()
        return (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
    end)
    if kokOk and kok then
        pcall(function()
            for _, sg in ipairs(kok:GetChildren()) do
                if sg:IsA("ScreenGui") and (sg.Name:find("FluentRenewed", 1, true) or sg.Name == "ZynexSandworm") then
                    sg:Destroy()
                end
            end
        end)
    end
end

-- BILDIRIM KONTROLU (Rochess kalibi): kutuphane seviyesinde Fluent.Notify override
-- - ilk 4sn sessiz (yukleme bildirimleri yutulur)
-- - 'to toggle the interface' bildirimi her zaman yutulur
-- - showNotify kapaliysa hicbir bildirim cikmaz
getgenv().KSWH_SILENT = true
task.delay(4, function() getgenv().KSWH_SILENT = false end)
local orgFluentNotify = Fluent.Notify
Fluent.Notify = function(self, opts)
    if getgenv().KSWH_SILENT then return end
    if KSWH.cfg.showNotify == false then return end
    if type(opts) == "table" and type(opts.Content) == "string"
        and opts.Content:find("to toggle the interface", 1, true) then
        return
    end
    return orgFluentNotify(self, opts)
end
local function notify(title, content, dur)
    pcall(function() Fluent:Notify({ Title = title, Content = content, Duration = dur or 3 }) end)
end

local Window = Fluent:CreateWindow({
    Title = "Zynex | Sandworm",
    SubTitle = isMobile and "by ZynexDev | MOBILE" or "by ZynexDev",
    TabWidth = isMobile and 110 or 148,
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    Theme = "Dark",
    Acrylic = false,
    MinimizeKey = Enum.KeyCode.RightControl,
})
-- kurulum sirasinda pencere GIZLI - her sey hazir olunca acilir
-- ('yuklenirken tab gui gozukme' sorununun Rochess'teki cozumu)
pcall(function() Fluent.GUI.Enabled = false end)
getgenv().KSWH_STAGE = "window-ok"
KSWH.window = Window

-- ---- FLUENT BUG KALKANI (v3.8 genel tanimli: tab + section + addon) ----
local ddYontemleri = { CreateDropdown = true, AddDropdown = true }
local bolumYontemleri = { AddSection = true, CreateSection = true }
local function tabKalkan(tab)
    if type(tab) ~= "table" then return end
    for _, mname in ipairs({
        "CreateToggle", "CreateSlider", "CreateDropdown", "CreateButton",
        "CreateKeybind", "CreateInput", "CreateColorPicker", "CreateParagraph",
        "CreateSection", "AddToggle", "AddDropdown", "AddSlider", "AddKeybind",
        "AddInput", "AddColorPicker", "AddButton", "AddSection",
    }) do
        local orig = tab[mname]
        if type(orig) == "function" then
            tab[mname] = function(_, ...)
                local n = select("#", ...)
                for i = 1, n do
                    local v = select(i, ...)
                    if type(v) == "table" then
                        if type(v.Callback) == "function" then
                            local ocb = v.Callback
                            v.Callback = function(...) return pcall(ocb, ...) end
                        end
                        if type(v.ChangedCallback) == "function" then
                            local occ = v.ChangedCallback
                            v.ChangedCallback = function(...) return pcall(occ, ...) end
                        end
                    end
                end
                local sonuc = orig(tab, ...)
                -- dropdown secimde kapanma fixi
                if ddYontemleri[mname] and type(sonuc) == "table"
                    and type(sonuc.Close) == "function"
                    and type(sonuc.SetValue) == "function"
                    and sonuc.Multi ~= true then
                    local osv = sonuc.SetValue
                    sonuc.SetValue = function(a, ...)
                        local r = osv(a, ...)
                        task.delay(0.06, function()
                            pcall(function() sonuc:Close() end)
                        end)
                        return r
                    end
                end
                if bolumYontemleri[mname] and type(sonuc) == "table" then
                    tabKalkan(sonuc)
                end
                return sonuc
            end
        end
    end
end

local TabDash = Window:CreateTab({ Title = "Dashboard", Icon = "home" })
local TabFarm = Window:CreateTab({ Title = "Farm", Icon = "cpu" })
local TabExtra = Window:CreateTab({ Title = "Extra", Icon = "puzzle" })
local TabSettings = Window:CreateTab({ Title = "Settings", Icon = "settings" })
local TabDiscord = Window:CreateTab({ Title = "Discord", Icon = "globe" })
getgenv().KSWH_STAGE = "tablar-ok"

tabKalkan(TabDash); tabKalkan(TabFarm); tabKalkan(TabExtra)
tabKalkan(TabSettings); tabKalkan(TabDiscord)
getgenv().KSWH_TABS = { Dash = TabDash, Farm = TabFarm, Extra = TabExtra, Settings = TabSettings, Discord = TabDiscord }

-- =============================== OZELLIKLER ===============================

-- ---- 1) AUTO FARM (surekli supurme farmi) ----
-- ============================================================
-- AUTO PROP FARM v2 - EVENT DRIVEN (sifirdan kurulum)
-- KOK NEDEN COZULDU (MCP inbound spy): sunucu her TAZE prop
-- dogumunu duyurur: WormProps.TownFx "Rebuild"(model),
-- WormProps.Fx "BoulderRespawn"(model), OilField.OilFx "Rebuild"
-- (olcum: ~10 dogum/dakika; bir barrel kumesi her ~30sn'de
-- yeniden doguyor!). Eski farm havuz/census tahmin yurutuyordu ve
-- nerede olacagi bilinmeyen olu prop'larda vakit yakiyordu.
-- Yeni farm SADECE sunucunun TAZE dedigi prop'lari kovalar:
-- dinle -> yuzerek git -> dolan -> XP al. Isinlanma YOK.
-- ============================================================
KSWH.canli = {} -- taze dogum kuyrugu {c = model, p = pos, t = zaman}

local function canliEkle(c, p)
    if not c or not c.Parent then return end
    -- HAVA HEDEFLERI KUYRUGA GIRMEZ (Balloon/Blimp - hava destegi yok)
    if c.Name:match("Balloon") or c.Name:match("Blimp") then return end
    for _, e in ipairs(KSWH.canli) do
        if e.c == c then
            e.t = os.clock()
            e.p = p -- yeniden dogdu, konumu tazele
            return
        end
    end
    if #KSWH.canli < 40 then
        KSWH.canli[#KSWH.canli + 1] = { c = c, p = p, t = os.clock() }
    end
end

local function canliCikar(c)
    for i = #KSWH.canli, 1, -1 do
        if KSWH.canli[i].c == c then table.remove(KSWH.canli, i) end
    end
end

-- dinleyiciler: farm kapaliyken de bagli kalir (ucuz, sadece bilgi)
local dinlenenUzaklar = {
    { RS:FindFirstChild("WormProps"), "TownFx" }, -- Rebuild: evler/duvarlar/ficilar
    { RS:FindFirstChild("WormProps"), "Fx" },     -- BoulderRespawn + Rebuild
    { RS:FindFirstChild("OilField"), "OilFx" },   -- Rebuild: oilfield
    { RS:FindFirstChild("Chests"), "Fx" },        -- odul sandigi olaylari
}
for _, d in ipairs(dinlenenUzaklar) do
    local r = d[1] and d[1]:FindFirstChild(d[2])
    if r then
        r.OnClientEvent:Connect(function(a1, a2)
            if (a1 == "Rebuild" or a1 == "BoulderRespawn" or a1 == "Spawn")
                and typeof(a2) == "Instance" and a2.Parent then
                local pv = a2:FindFirstChildWhichIsA("BasePart", true)
                if pv then canliEkle(a2, pv.Position) end
            elseif a1 == "Fade" and typeof(a2) == "Instance" then
                canliCikar(a2) -- biri yedi (biz veya rakip) - kuyruktan dus
            end
        end)
    end
end

-- (eski propHavuzu/hedefEkle kaldirildi - event kuyrugu onlarin yerine gecti)

-- DURU-PIN (MCP ile 90sn dogrulandi: +1130 XP, 35 smash): hedefin merkezine
-- BIR KEZ yaz, sim'i serbest birak. KRITIK: state.g (zemin yuksekligi) ESKI
-- bolgenin degeri - hedef dagliksa fark 30+ stud olur ve sim pos'u geri
-- ceker = gorsel rubber-band. Cozum: hedefte RAYCAST ile gercek zemini bul,
-- state.g'yi oraya tasi, sonra pos yaz. Her frame yazmak sim ile kavgadir.
local function zeminY(x, z)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LP.Character }
    local r = workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -600, 0), params)
    -- Iskalarsa NIL dondur - CAGRILARAK ILERLE: 0 donmek solucani aninda
    -- Y=0'a shotiyor (kanyon/prop ustu) sonra geri yukari = DUSEY ISINLANMA
    -- (kullanicinin gordugu 'isilanma' buydu - yatay surunus zaten duzgun)
    return r and r.Position.Y or nil
end

-- SURUKLENMELI FARM (kullanici tarifi, MCP dogrulandi: 48.9 XP/sn, 7/8 hedef,
-- SURUNE-SURUNE GIT (kullanici kurali: ISINLANMA YOK, hizli SURUNUS): hedefe
-- kadar surekli pozisyon yazimi ile ilerle. Zaman asimi MESAFE BAZLI
-- (mesafe/hiz + 2sn pay) - uzak lunapark 500+ stud olsa bile YOLDA BIRAKILMAZ
-- (eski 3sn sabit asimi 330 stud sonra yolu kesiyor, bos kumda dolaniyordu =
-- 'gidiyor ama xp alamiyor' bug'i). Hedef hareketliyse (tren/kaya) canli
-- takip edilir.
local function yuz(h)
    if not state or not h.c.Parent then return end
    -- SPEED ENTEGRASYONU + TELEMETRI BULGU #2: 70 stud/sn yol = 500 stud
    -- hedefe 8sn = yolun yarisi bos col. Taban surunus hizi 135 (vel=0
    -- oldugu icin isinlanma riski yok, sadece hizli suret).
    local carpan = KSWH.cfg.speed and math.max(1, KSWH.cfg.speedVal / 70) or 1
    local hiz = math.max(135, (KSWH.cfg.farmHiz or 135) * carpan)
    local pv = h.pv or h.c:FindFirstChildWhichIsA("BasePart", true)
    local hedefXZ = pv and pv.Parent and Vector3.new(pv.Position.X, 0, pv.Position.Z)
        or Vector3.new(h.p.X, 0, h.p.Z)
    -- mesafe bazli guvenlik suresi: her zaman varis saglanir
    local mesafe = (hedefXZ - Vector3.new(state.pos.X, 0, state.pos.Z)).Magnitude
    local tGuv = os.clock() + mesafe / hiz + 2
    while os.clock() < tGuv do
        if KSWH.GEN ~= GEN or not KSWH.cfg.farm then break end
        -- TELEMETRI KOK BULGU #1: hedef yolda BASKASI tarafindan yenilip
        -- silinirse hayalet hedefe kadar bos colde yurumeye devam ediyordu
        -- ('etrafinda 0 hedef' durmalari). Aninda cik, yeni hedef sec.
        if not h.c.Parent then return end
        -- hareketli hedef (tren/kaya): hedefi canli guncelle
        if pv and pv.Parent then
            hedefXZ = Vector3.new(pv.Position.X, 0, pv.Position.Z)
        else
            local pvNow = h.c:FindFirstChildWhichIsA("BasePart", true)
            if pvNow then
                pv = pvNow
                hedefXZ = Vector3.new(pvNow.Position.X, 0, pvNow.Position.Z)
            end
        end
        local dt = task.wait()
        -- OYUNUN YAVASLATMASINI EZ (kok neden: prop'a/NPC'ye carpisma
        -- hitSlowUntil'i tetikler, sim worm'u 1sn+ kilitler = 'dusunup durma'
        -- hissi; farm sirasinda hicbir yavaslama istemiyoruz)
        if state.hitSlowUntil and state.hitSlowUntil > os.clock() then
            state.hitSlowUntil = -99
        end
        local fark = hedefXZ - Vector3.new(state.pos.X, 0, state.pos.Z)
        if fark.Magnitude < 8 then break end -- varis
        local yon = fark.Unit
        -- VEL SIFIR (kok neden: vel=hiz yazinca SIM DE ayni yonde pos'u itiyor
        -- = cift hiz = isinlanma gorunumu). Sadece kendi adimimizla ilerle.
        local gy = zeminY(state.pos.X + yon.X * 15, state.pos.Z + yon.Z * 15)
        if gy then
            state.g = state.g + (gy - state.g) * math.min(1, dt * 10)
        end
        state.vel = Vector3.zero
        state.pos = Vector3.new(
            state.pos.X + yon.X * hiz * dt,
            state.g + 3,
            state.pos.Z + yon.Z * hiz * dt
        )
    end
    state.vel = Vector3.zero
    state.vy = 0
end

-- HEDEFTA DOLANMA: merkezden gecen salinim (ic-dis) - XP gelene kadar don.
-- HAREKETLI HEDEF TAKIBI: kayalar (Boulder) worm yaklasinca KACAR (BoulderRoll
-- olayi var!) - sabit merkezde dolanmak bosuna. Merkez her frame HEDEFIN
-- GERCEK KONUMUNDAN tazele-nir (pv referansi).
local function dolan(h)
    if not state or not h.c.Parent then return 0 end
    local once = LP:GetAttribute("XpTotal") or 0
    -- GAIN SAYACI: XpTotal attribute 1-2sn gecikmeli - dolan erken cikiyor
    -- ve hedef 'yenemedi' saniliyordu. Gain olayi ANLIK gelir.
    local gainOldu = false
    local gainBag = XpEvent.OnClientEvent:Connect(function(a1)
        if a1 == "Gain" then gainOldu = true end
    end)
    local pv = h.pv or h.c:FindFirstChildWhichIsA("BasePart", true)
    local p0 = pv and pv.Position or h.p
    -- HAVA DESTEGI TAMAMEN KALDIRILDI (kullanici talimati): Balloon/Blimp
    -- hedefleri artik HIC secilmez (tarama asamasinda elenir). Burada
    -- hava/lift kodu YOK - sadece yer hedefleri.
    local merkez = Vector3.new(p0.X, 0, p0.Z)
    local faz, aci = 0, math.random() * math.pi * 2
    local bekleme = math.max(1.2, KSWH.cfg.farmPin or 2.2)
    local t0 = os.clock()
    while os.clock() - t0 < bekleme do
        if KSWH.GEN ~= GEN or not KSWH.cfg.farm then break end
        if not h.c.Parent then break end
        local dt = task.wait()
        -- kacan tasa/carcanlari CANLI takip: merkez her frame guncellenir
        if pv and pv.Parent then
            merkez = Vector3.new(pv.Position.X, 0, pv.Position.Z)
        else
            local pvNow = h.c:FindFirstChildWhichIsA("BasePart", true)
            if pvNow then
                pv = pvNow
                merkez = Vector3.new(pvNow.Position.X, 0, pvNow.Position.Z)
            end
        end
        faz += dt * 7 -- salinim hizi (merkezden gecis frekansi - yeme ICIN)
        aci += dt * 1.2 -- yavas donus
        -- yavaslatma ezi (dolan sirasinda da - prop icinde dolanirken
        -- surekli carpisma tetikleniyor, her yemede 1sn kilitleme olmasin)
        if state.hitSlowUntil and state.hitSlowUntil > os.clock() then
            state.hitSlowUntil = -99
        end
        -- r=9: propun ICINDEN gecis (r=16 kenardan siyiriyordu = nadir vurma
        -- sikayetinin kaynagi); sin egrisi her geciste merkezi tam deler
        local r = math.sin(faz) * 9
        local hPos = merkez + Vector3.new(math.cos(aci) * r, 0, math.sin(aci) * r)
        -- dusey: sadece zemin lerp (hava modu kaldirildi)
        local gy = zeminY(hPos.X, hPos.Z)
        if gy then
            state.g = state.g + (gy - state.g) * math.min(1, dt * 10)
        end
        -- ARTIMLI TAKIP (isinlanma YOK): hedef noktaya frame basina max
        -- hiz*dt kadar ilerle - vel SIFIR (sim'in cift hiz itmesi engellenir)
        local simdikiXZ = Vector3.new(state.pos.X, 0, state.pos.Z)
        local vektor = hPos - simdikiXZ
        local dolanHiz = math.max(KSWH.cfg.farmHiz or 70,
            (KSWH.cfg.farmHiz or 70) * (KSWH.cfg.speed and math.max(1, KSWH.cfg.speedVal / 70) or 1))
        local adim = math.min(vektor.Magnitude, dolanHiz * dt)
        if adim > 0 then
            local yon = vektor.Unit
            state.vel = Vector3.zero
            state.pos = Vector3.new(
                state.pos.X + yon.X * adim,
                state.g + 3,
                state.pos.Z + yon.Z * adim
            )
        else
            state.vel = Vector3.zero
        end
        if gainOldu or (LP:GetAttribute("XpTotal") or 0) > once then
            gainBag:Disconnect()
            task.wait(0.1)
            return (LP:GetAttribute("XpTotal") or 0) - once
        end
    end
    gainBag:Disconnect()
    return (LP:GetAttribute("XpTotal") or 0) - once
end

-- XP DEGER TABLOSU (oyunun kendi RS.Xp.Config tablosundan, MCP ile okundu):
-- hedef secimi EN COK XP'den en aza dogru (kullanici istegi) - GoldExpress 600,
-- EiffelTower 150, FerrisWheel 120, House 25, Boulder/Obelisk 15, PowderBarrel 6...
local XP_DEGER = {
    Gold = 600, Chest = 200, EiffelTower = 150, Eiffel = 150, FerrisWheel = 120,
    Pyramid = 80, Train = 60, Trestle = 60, WaterTower = 45,
    OilTank = 40, Headframe = 40, Buggy = 30, Camel = 30,
    Pumpjack = 30, TunnelPortal = 25, MineCart = 25, Watchtower = 25,
    House = 25, Npc = 25, StuntRing = 25, MarketStall = 22, OilShack = 20,
    Grandstand = 20, AdobeHut = 20, StartGate = 20, Crusher = 15, Ramp = 15,
    Boulder = 15, Obelisk = 15, EiffelPiece = 12, TownWall = 12, Palm = 12,
    RuinsWall = 10, Column = 10, Gondola = 10, TireWall = 8, OrePile = 8,
    OilPipe = 8, TrackPiece = 6, CoasterTrack = 6, Tumbleweed = 6,
    BowlingPin = 6, PowderBarrel = 6, Cactus = 5, Rails = 4,
}
local function xpDeger(ad)
    local enIyi, anahtarUzun = 10, 0 -- bilinmeyen tur = DEFAULT 10
    for ana, deger in pairs(XP_DEGER) do
        if #ana > anahtarUzun and ad:find(ana, 1, true) then
            enIyi = deger
            anahtarUzun = #ana
        end
    end
    return enIyi
end

-- BIRLESIK DEGER TARAMASI v2 - BOLGE ZIHNIYETI (kullanici istegi):
-- tek hedefin XP'sine degil BOLGENIN TOPLAM XP'sine bak: 150 stud cevresindeki
-- tum yenebilir hedeflerin XP toplami = bolge zenginligi. Solucan en zengin
-- bolgeye gider, orayi TAMAMEN temizler (parcalar dahil), sonra yeni zengin
-- bolge. Kaynaklar: dinamikler (tek basina bolge gibi) + event kuyrugu + prop'lar.
-- HIZ: hedef listesi 0.75sn'de bir onbelleklenir (her aday icin 500 model
-- taramak = mikro-donma; onbellekle donma yok).
local hedefCache, hedefCacheT = nil, 0
local function hedefListesi()
    if hedefCache and os.clock() - hedefCacheT < 0.75 then return hedefCache end
    local liste = {}
    local simdi = os.clock()
    for _, ad in ipairs({
        "WormProps", "DesertTown", "OilField", "Ruins", "Mine",
        "Landmarks", "Railway", "PalmGrove", "Kaktus", "Stunts",
    }) do
        local f = workspace:FindFirstChild(ad)
        if f then
            for _, c in ipairs(f:GetChildren()) do
                if c:IsA("Model") and c.Parent then
                    local n = c.Name
                    if not (n:match("Balloon") or n:match("Blimp")) then
                        local cd = KSWH.cd[c]
                        if not cd or simdi >= cd then
                            liste[#liste + 1] = { c = c, p = c:GetPivot().Position, v = xpDeger(n) }
                        end
                    end
                end
            end
        end
    end
    hedefCache, hedefCacheT = liste, os.clock()
    return liste
end

local function bolgeZenginligi(p)
    local toplam, adet = 0, 0
    for _, h in ipairs(hedefListesi()) do
        if (h.p - p).Magnitude < 150 then
            toplam += h.v
            adet += 1
        end
    end
    return toplam, adet
end

local function enDegerliHedef()
    if not state then return nil end
    KSWH.cd = KSWH.cd or {}
    local simdi = os.clock()

    -- ADAYLAR TOPLA (tek gecis - ucuz)
    local adaylar = {}
    local function adayEkle(c, p, altin)
        if not c or not c.Parent then return end
        local n = c.Name
        if n:match("Balloon") or n:match("Blimp") then return end
        local cd = KSWH.cd[c]
        if cd and simdi < cd then return end
        adaylar[#adaylar + 1] = { c = c, p = p, ad = n, deger = xpDeger(n), altin = altin }
    end

    -- 1) dinamikler (kok + 2 seviye derinlik)
    local function dinamikMi(n)
        -- Balloon/Blimp HARIc (hava destegi kaldirildi)
        return n:match("Train") or n:match("Camel") or n:match("^Chest")
            or n:match("Gold")
    end
    for _, c in ipairs(workspace:GetChildren()) do
        if c:IsA("Model") and dinamikMi(c.Name) then
            adayEkle(c, c:GetPivot().Position, true)
        elseif c:IsA("Folder") then
            for _, cc in ipairs(c:GetChildren()) do
                if cc:IsA("Model") then
                    if dinamikMi(cc.Name) then
                        adayEkle(cc, cc:GetPivot().Position, true)
                    end
                elseif cc:IsA("Folder") then
                    for _, ccc in ipairs(cc:GetChildren()) do
                        if ccc:IsA("Model") and dinamikMi(ccc.Name) then
                            adayEkle(ccc, ccc:GetPivot().Position, true)
                        end
                    end
                end
            end
        end
    end

    -- 2) event kuyrugu
    for _, e in ipairs(KSWH.canli) do
        if e.c.Parent then
            adayEkle(e.c, e.c:GetPivot().Position, false)
        end
    end

    -- 3) harita prop'lari (onbellek - SkyLocal haric)
    for _, h in ipairs(hedefListesi()) do
        adayEkle(h.c, h.p, false)
    end

    -- DYNAMIC HER ZAMAN ONE GECER
    for _, a in ipairs(adaylar) do
        if a.altin then return a end
    end

    -- IKI GECIS BOLGE AKLI (onceki tek-gecis surumde her aday icin 500 model
    -- taramasi = 250.000 hesap = hedef arasi KITLENME (kullanicinin 'salak
    -- salak bekleme' sikayeti). Simdi: once kendi degerine gore en iyi 15,
    -- SADECE onlara bolge puani (15 x 500 = hizli).
    table.sort(adaylar, function(x, y)
        local sx = x.deger * 1000 - (x.p - state.pos).Magnitude * 2
        local sy = y.deger * 1000 - (y.p - state.pos).Magnitude * 2
        return sx > sy
    end)
    local enIyiH, enSkor = nil, -math.huge
    local sinir = math.min(15, #adaylar)
    for i = 1, sinir do
        local a = adaylar[i]
        local toplam, adet = bolgeZenginligi(a.p)
        local skor = toplam * 10 + a.deger * 100 - (a.p - state.pos).Magnitude * 2
        if adet < 2 then skor -= 3000 end
        if skor > enSkor then
            enSkor = skor
            enIyiH = a
        end
    end
    return enIyiH
end

-- HEDEFI YE: yuz + dolan + Gain olcumu + cd + SMASH log + kuyruk dusus
local function hedefiYe(hedef)
    if not hedef or not hedef.c or not hedef.c.Parent then return end
    local gainSayi = 0
    local gainBag = XpEvent.OnClientEvent:Connect(function(a1)
        if a1 == "Gain" then gainSayi += 1 end
    end)
    local gitmedenOnce = LP:GetAttribute("XpTotal") or 0
    yuz(hedef)
    dolan(hedef)
    task.wait(0.12) -- son gain paketini bekle (0.3 uzun - duraksama hissi veriyordu)
    gainBag:Disconnect()
    local artis = gainSayi > 0
        and ((LP:GetAttribute("XpTotal") or 0) - gitmedenOnce)
        or 0
    if gainSayi > 0 then
        -- dinamikler (sandik/tren/balon) yenilince MODEL haritada KALABILIR
        -- (gorsel kalinti) - tekrar secilmesin diye DINAMIKLER ICIN UZUN cd
        -- (sandik tekrar dogarsa EventChests kuyrugundan yeniden girer)
        local dinamikAd = hedef.altin and hedef.ad or nil
        KSWH.cd[hedef.c] = os.clock() + (dinamikAd and 900 or 140)
        KSWH.stats.smashed = (KSWH.stats.smashed or 0) + 1
        KSWH.addLog("FARM", string.format("SMASHED: %s (%d gain)", hedef.ad, gainSayi))
    else
        -- yenmeyen hedef: uzun cd
        KSWH.cd[hedef.c] = os.clock() + 600
        KSWH.addLog("FARM", hedef.ad .. " gave nothing - cooldown")
    end
    for i = #KSWH.canli, 1, -1 do
        if KSWH.canli[i].c == hedef.c then table.remove(KSWH.canli, i) end
    end
end

task.spawn(function()
    while true do
        task.wait(0.2)
        if KSWH.GEN ~= GEN then return end
        if KSWH.cfg.farm then
            -- solucan degilsek otomatik solucan ol
            local worm, ch = isWorm()
            if not worm then
                KSWH.addLog("FARM", "not a worm -> SetForm(true)")
                pcall(function() SetForm:FireServer(true) end)
                task.wait(1.5)
                refreshState()
            end
            state = state or refreshState()
            if state then
                -- DEGER-GREEDY + YEREL SUPURME (kullanici tarifi): en cok XP
                -- veren hedefe surunerek git, YE; sonra AYNI BOLGEDEKI duran
                -- diger parcalari da ye (tek parca kirip gitmek YOK - 'diger
                -- parcalar hala duruyo' sikayeti); bolge temiz olunca yeni
                -- deger taramasi.
                KSWH.farmBusy = true
                KSWH.cd = KSWH.cd or {}
                local hedef = enDegerliHedef()
                if hedef then
                    if hedef.altin then
                        KSWH.addLog("FARM", "PRIORITY: " .. hedef.ad .. " (" .. hedef.deger .. " XP!)")
                    end
                    hedefiYe(hedef)
                    -- YEREL SUPURME: 200 stud icindeki diger duran parcalar
                    -- (150 -> 200: parcalanan yapi parcalari genis saciliyor -
                    -- kullanici: 'parcasina gidiyor ama parcalanmayi anlayamiyor')
                    -- DINAMIK KESME: altin tren/sandik/deve spawn olursa aninda
                    -- birak ve ustune git.
                    local tSweep = os.clock() + 25
                    while os.clock() < tSweep do
                        if KSWH.GEN ~= GEN or not KSWH.cfg.farm then break end
                        -- once dinamik kontrol (ucuz: kok ~100 cocuk, isim match)
                        -- EventChests klasoru ici DAHIL (GoldTrain/sandik orada dogar)
                        -- YENILMIS SANDIK ATLA: sandik yenilince de MODEL olarak
                        -- kalabilir (gorsel) - cd'de olan dinamike gitme!
                        local dinamik = nil
                        local function dinamikAtla(c)
                            return KSWH.cd[c] and os.clock() < KSWH.cd[c]
                        end
                        for _, c in ipairs(workspace:GetChildren()) do
                            if c:IsA("Model") and (c.Name:match("Train")
                                or c.Name:match("^Chest") or c.Name:match("Camel"))
                                and not dinamikAtla(c) then
                                dinamik = c
                                break
                            end
                            if c:IsA("Folder") and c.Name == "EventChests" then
                                for _, cc in ipairs(c:GetChildren()) do
                                    if cc:IsA("Model") and (cc.Name:match("Train")
                                        or cc.Name:match("^Chest")) and not dinamikAtla(cc) then
                                        dinamik = cc
                                        break
                                    end
                                end
                                if dinamik then break end
                            end
                        end
                        if dinamik then
                            -- ayni dinamige ust uste gitme (tek noktaya kasma bug'i:
                            -- yenilmis sandik modeli kalir, DYNAMIC surekli onu secer)
                            if KSWH.sonDinamik == dinamik then
                                KSWH.cd[dinamik] = os.clock() + 900
                            end
                            KSWH.sonDinamik = dinamik
                            KSWH.addLog("FARM", "DYNAMIC! abandoning sweep -> " .. dinamik.Name)
                            break
                        end
                        local yerel, enM = nil, 200
                        local simdi = os.clock()
                        -- SkyLocal HARIc (balonlar orada - hava destegi yok)
                        for _, ad in ipairs({
                            "WormProps", "DesertTown", "OilField", "Ruins", "Mine",
                            "Landmarks", "Railway", "PalmGrove", "Kaktus", "Stunts",
                        }) do
                            local f = workspace:FindFirstChild(ad)
                            if f then
                                for _, c in ipairs(f:GetChildren()) do
                                    if c:IsA("Model") and c.Parent then
                                        local n = c.Name
                                        if not (n:match("Balloon") or n:match("Blimp")) then
                                            local cd = KSWH.cd[c]
                                            if not cd or simdi >= cd then
                                                local m = (c:GetPivot().Position - state.pos).Magnitude
                                                if m < enM then
                                                    enM = m
                                                    yerel = { c = c, p = c:GetPivot().Position, ad = c.Name }
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if not yerel then break end -- bolge temiz
                        hedefiYe(yerel)
                    end
                    task.wait(0.1)
                else
                    task.wait(3) -- her sey cd'de / harita bos: respawn bekle
                end
                KSWH.farmBusy = false
            else
                KSWH.addLog("FARM", "worm state missing, waiting...")
                task.wait(2)
            end
        else
            task.wait(1)
        end
    end
end)

-- ---- 2) AUTO EAT (NPC + deve kovala + bite) ----
local function canliHedefler()
    local liste = {}
    local np = workspace:FindFirstChild("Npcs")
    if np then
        for _, c in ipairs(np:GetChildren()) do
            local pv = c:IsA("Model") and c:FindFirstChildWhichIsA("BasePart", true)
            if pv and c.Parent then liste[#liste + 1] = { c = c, pv = pv, ad = "NPC", p = pv.Position } end
        end
    end
    -- develer (spawn oldugu yerde bulunur)
    for _, d in ipairs(workspace:GetChildren()) do
        if d:IsA("Model") and d.Name:match("Camel") then
            local pv = d:FindFirstChildWhichIsA("BasePart", true)
            if pv then liste[#liste + 1] = { c = d, pv = pv, ad = "CAMEL", p = pv.Position } end
        end
    end
    return liste
end

task.spawn(function()
    local sonBite = 0
    while true do
        task.wait(0.1)
        if KSWH.GEN ~= GEN then return end
        if KSWH.cfg.autoEat and select(1, isWorm()) then
            -- CAKISMA ONLEMI: farm sweep aktifken eat beklemeye gecer
            -- (ikisi de state.pos yazdigi icin ayni anda calisirlarsa pozisyon titrer).
            -- Sweep bitince respawn beklemedesinde eat devreye girer (NPC + streak).
            if KSWH.cfg.farm and KSWH.farmBusy then
                task.wait(0.3)
            else
                local hedefler = canliHedefler()
                local hedef = nil
                local benim = posAl()
                local enYakin = math.huge
                for _, h in ipairs(hedefler) do
                    if h.c.Parent then
                        local d = (h.p - benim).Magnitude
                        if d < enYakin then enYakin = d; hedef = h end
                    end
                end
                if hedef and state then
                    -- SURUNEREK YAKLAS + ICINDEN GECIS: once NPC'ye dek surun
                    -- (ISINLANMA YOK - uzak NPC'ye anlik pos yazimi kullanici
                    -- 'isinalma' goruyordu), yaklasinca gecis salinimi ile ye.
                    local eats0 = LP:GetAttribute("EatsLifetime") or 0
                    local tBasla = os.clock()
                    while hedef.c.Parent and os.clock() - tBasla < 12 do
                        if KSWH.GEN ~= GEN or not KSWH.cfg.autoEat then break end
                        if KSWH.cfg.farm and KSWH.farmBusy then break end
                        local pvNow = hedef.c:FindFirstChildWhichIsA("BasePart", true)
                        if not pvNow then break end
                        local n = pvNow.Position
                        local dt = task.wait(0.05)
                        local fark = Vector3.new(n.X, 0, n.Z) - Vector3.new(state.pos.X, 0, state.pos.Z)
                        if fark.Magnitude > 18 then
                            -- UZAK: surunerek yaklas (artimli pozisyon, yumusak g)
                            local yon = fark.Unit
                            local eatCarpan = KSWH.cfg.speed and math.max(1, KSWH.cfg.speedVal / 70) or 1
                            local hiz = (KSWH.cfg.farmHiz or 70) * eatCarpan
                            local gy = zeminY(state.pos.X + yon.X * 12, state.pos.Z + yon.Z * 12)
                            if gy then
                                state.g = state.g + (gy - state.g) * math.min(1, dt * 10)
                            end
                            state.vel = Vector3.zero
                            state.pos = Vector3.new(
                                state.pos.X + yon.X * hiz * dt,
                                state.g + 3,
                                state.pos.Z + yon.Z * hiz * dt
                            )
                        else
                            -- YAKIN: ileri-geri gecis salinimi (agiz suretler)
                            -- ARTIMLI: frame basina max hiz*dt ilerle (anlik yazim yok)
                            local faz = (os.clock() * 2.2) % 2
                            local yonIsaret = faz < 1 and 1 or -1
                            local hedefNokta = Vector3.new(n.X, 0, n.Z + yonIsaret * 7)
                            local vektor = hedefNokta - Vector3.new(state.pos.X, 0, state.pos.Z)
                            local adim = math.min(vektor.Magnitude, 70 * dt)
                            if adim > 0 then
                                local yon = vektor.Unit
                                state.vel = Vector3.zero
                                state.pos = Vector3.new(
                                    state.pos.X + yon.X * adim,
                                    state.g + 3,
                                    state.pos.Z + yon.Z * adim
                                )
                            end
                        end
                        local ch = LP.Character
                        local biteAt = ch and ch:GetAttribute("BiteAt") or 0
                        if os.time() >= (biteAt or 0) and os.clock() - sonBite > 1.9 then
                            pcall(function() Act:FireServer("Bite") end)
                            sonBite = os.clock()
                        end
                        if not hedef.c.Parent
                            or (LP:GetAttribute("EatsLifetime") or 0) > eats0 then
                            KSWH.stats.npcs = (KSWH.stats.npcs or 0) + 1
                            KSWH.addLog("EAT", hedef.ad .. " EATEN (total: "
                                .. (LP:GetAttribute("EatsLifetime") or 0) .. ")")
                            break
                        end
                    end
                end
            end
        else
            task.wait(0.5)
        end
    end
end)

-- ---- 3) INFINITE STAMINA ----
task.spawn(function()
    while true do
        task.wait(0.05)
        if KSWH.GEN ~= GEN then return end
        if KSWH.cfg.infStamina then
            if not state then refreshState() end
            if state and state.stamina and state.stamina < 1 then
                state.stamina = 1
            end
        else
            task.wait(0.2)
        end
    end
end)

-- ---- 4) SPEED ----
-- Speed + Farm birlikte calissin: speed ACIK + farm CALISIYORKEN state.speed
-- ZORLANMAZ (sim 'ileri git' komutu alir, duz iter, farm yolu ezer - kullanici
-- sikayeti). Bunun yerine farm adimlari hizlanir (yuz/dolan hiz carpani).
-- Sadece farm bosken (beklemede) speed zorlanir - duz ilerleme o zaman zararsiz.
task.spawn(function()
    while true do
        task.wait(0.05)
        if KSWH.GEN ~= GEN then return end
        if KSWH.cfg.speed then
            if not state then refreshState() end
            if state then
                local farmAktif = KSWH.cfg.farm and KSWH.farmBusy
                if not farmAktif and (state.speed or 0) < KSWH.cfg.speedVal then
                    state.speed = KSWH.cfg.speedVal
                end
            end
        else
            task.wait(0.2)
        end
    end
end)

-- ---- 5) EVENT MONITOR (BloodMoon vs.) ----
task.spawn(function()
    local sonEvent = nil
    while true do
        task.wait(3)
        if KSWH.GEN ~= GEN then return end
        if KSWH.cfg.eventMon then
            local we = workspace:FindFirstChild("WormEvents")
            local cur = we and we:GetAttribute("Current")
            if cur ~= sonEvent then
                sonEvent = cur
                KSWH.addLog("EVENT", "event: " .. tostring(cur))
                if cur == "BloodMoon" then
                    KSWH.addLog("EVENT", "BLOOD MOON! Double XP active - farm at full speed!")
                    notify("BLOOD MOON!", "Double XP until the moon sets!", 6)
                end
            end
        end
    end
end)

-- =============================== FONKSIYONLAR (dogrulama API) ===============================
-- TP ARTIK SURUNEREK gidiyor (isinla yok edildi): worm isen yuz-usulu artimli
-- ilerleme, insan isen Humanoid:MoveTo (CFrame yazimi YOK).
KSWH.fn.tp = function(nereye)
    local hedefler = {
        DesertTown = workspace:FindFirstChild("DesertTown"),
        OilField = workspace:FindFirstChild("OilField"),
        Ruins = workspace:FindFirstChild("Ruins"),
        Mine = workspace:FindFirstChild("Mine"),
        FloodTower = workspace:FindFirstChild("FloodTower"),
        Train = workspace:FindFirstChild("Railway"),
    }
    local m = hedefler[nereye]
    if not m then KSWH.addLog("TP", nereye .. " not found") return false end
    local hedefPos = m:GetPivot().Position
    local once = posAl()
    if select(1, isWorm()) and state then
        -- surunerek git: artikli pozisyon, vel SIFIR (cift hiz = isinlanma)
        local hiz = KSWH.cfg.farmHiz or 70
        local hXZ = Vector3.new(hedefPos.X, 0, hedefPos.Z)
        local mesafe = (hXZ - Vector3.new(state.pos.X, 0, state.pos.Z)).Magnitude
        local tGuv = os.clock() + mesafe / hiz + 2
        while os.clock() < tGuv do
            local dt = task.wait()
            local fark = hXZ - Vector3.new(state.pos.X, 0, state.pos.Z)
            if fark.Magnitude < 10 then break end
            local yon = fark.Unit
            local gy = zeminY(state.pos.X + yon.X * 15, state.pos.Z + yon.Z * 15)
            if gy then
                state.g = state.g + (gy - state.g) * math.min(1, dt * 10)
            end
            state.vel = Vector3.zero
            state.pos = Vector3.new(
                state.pos.X + yon.X * hiz * dt,
                state.g + 3,
                state.pos.Z + yon.Z * hiz * dt
            )
        end
        state.vel = Vector3.zero
    else
        local ch = LP.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:MoveTo(hedefPos)
            local t0 = os.clock()
            while os.clock() - t0 < mesafe and (ch:FindFirstChild("HumanoidRootPart").Position - hedefPos).Magnitude > 12 do
                task.wait(0.1)
                hum:MoveTo(hedefPos)
            end
        end
    end
    task.wait(0.3)
    local sonra = posAl()
    local d = (sonra - once).Magnitude
    KSWH.addLog("TP", string.format("%s: %d studs crawled", nereye, d))
    return true
end

KSWH.fn.setForm = function(wormOlsun)
    local worm = select(1, isWorm())
    if worm == wormOlsun then KSWH.addLog("FORM", "already " .. (worm and "worm" or "human")) return true end
    pcall(function() SetForm:FireServer(wormOlsun) end)
    task.wait(1.5)
    local simdi = select(1, isWorm())
    KSWH.addLog("FORM", "SetForm(" .. tostring(wormOlsun) .. ") -> Worm=" .. tostring(simdi))
    if wormOlsun then refreshState() end
    return simdi == wormOlsun
end

KSWH.fn.skinPreview = function(id)
    if not KSWH.realSkin then KSWH.realSkin = LP:GetAttribute("WormSkin") end
    LP:SetAttribute("WormSkin", id)
    task.wait(0.3)
    local simdi = LP:GetAttribute("WormSkin")
    KSWH.addLog("SKIN", "preview -> " .. tostring(simdi) .. " (local cosmetic)")
    return simdi == id
end

KSWH.fn.resetSkin = function()
    -- server'a sahip olunan skini geri giydir + lokal attr'i esitle
    local gercek = KSWH.realSkin or "Maw"
    pcall(function() RS.Sandworm.Remotes.EquipSkin:InvokeServer(gercek) end)
    LP:SetAttribute("WormSkin", gercek)
    KSWH.realSkin = nil
    task.wait(0.3)
    KSWH.addLog("SKIN", "reset -> " .. tostring(LP:GetAttribute("WormSkin")))
end

-- AUTO BEST SKIN: kullanilabilir EN IYI skini bul ve DIRECT kusan (sirayla
-- deneme yok). Tier listesi SkinConfig decompile'indan hardcode - executor'da
-- require() game modulunde ASILI KALIYOR (MCP testi kanitladi), o yuzden yok.
-- Sira = tier (Pharaoh en premium, sonra Elder/Void, sonra Hydra...).
-- Kilit kurallari (canUse birebir): level >= skin.level YA DA Unlock_<id>
-- gamepass attr; Void/Elder pass sahiplik attr'i ister; Pharaoh: OwnsPharaoh
-- veya Unlock_Pharaoh. Sunucu EquipSkin'de zaten dogrular (yanlissa false).
local SKIN_TIER = {
    { id = "Normal", level = 0 },
    { id = "Maw", level = 5 },
    { id = "Viper", level = 10 },
    { id = "Antlion", level = 15 },
    { id = "Shark", level = 20 },
    { id = "DeathWorm", level = 25 },
    { id = "GlassWyrm", level = 30 },
    { id = "Leviathan", level = 35 },
    { id = "Apocalypse", level = 40 },
    { id = "Mecha", level = 45 },
    { id = "Hydra", level = 50 },
    { id = "Void", ownedAttr = "OwnsVoidDevourer" },
    { id = "Elder", ownedAttr = "OwnsElderWorm" },
    { id = "Pharaoh", ownedAttr = "OwnsPharaoh", unlockAttr = "Unlock_Pharaoh" },
}

KSWH.fn.bestSkin = function()
    local lvl = tonumber(LP:GetAttribute("Level")) or 1
    for i = #SKIN_TIER, 1, -1 do
        local s = SKIN_TIER[i]
        if s.ownedAttr then
            -- pass/reward skin: sahiplik (veya unlock gamepass) gerekir
            if LP:GetAttribute(s.ownedAttr) == true
                or (s.unlockAttr and LP:GetAttribute(s.unlockAttr) == true) then
                return s
            end
        else
            -- level skin: seviye yeterli YA DA unlock gamepass alinmis
            if lvl >= (s.level or 0)
                or LP:GetAttribute("Unlock_" .. s.id) == true then
                return s
            end
        end
    end
    return nil
end

KSWH.fn.equipBest = function()
    local best = KSWH.fn.bestSkin()
    if not best then
        KSWH.addLog("SKIN", "bestSkin: kullanilabilir skin yok")
        return nil
    end
    local simdiki = LP:GetAttribute("WormSkin")
    if best.id == simdiki then return best.id end -- zaten ustunde
    -- InvokeServer DONUS DEGERI GUVENILMEZ (oyun kendisi yanlis false dondurur
    -- - MCP test kaniti: false dondu ama sunucu giydirdi). Gercek dogrulama:
    -- sunucu WormSkin attribute'unu replicate eder - invoke sonrasi bak.
    pcall(function() RS.Sandworm.Remotes.EquipSkin:InvokeServer(best.id) end)
    task.wait(0.5)
    local simdi = LP:GetAttribute("WormSkin")
    if simdi == best.id then
        KSWH.realSkin = nil
        KSWH.addLog("SKIN", string.format("BEST equipped: %s (old: %s)", best.id, tostring(simdiki)))
        notify("Best Skin", best.id .. " equipped!", 4)
        return best.id
    end
    KSWH.addLog("SKIN", "equip failed: " .. best.id .. " (server kept " .. tostring(simdi) .. ")")
    return nil
end

-- =============================== UI ELEMANLARI ===============================

-- ---- DASHBOARD (Rochess kalibi: Player paragrafi + avatar + canli istatistik) ----
local dashPara
pcall(function()
    dashPara = TabDash:CreateParagraph("DashInfo", {
        Title = "Player",
        Content = "Loading...",
    })
end)

-- Avatar: Dashboard TAB butonunun ikonu yerine oyuncu avatar fotoografi
-- (Rochess'te olculmus yapi: sidebar TextButton > [TextLabel(baslik) + ImageLabel(ikon)])
task.delay(1.5, function()
    pcall(function()
        local icerik, _ = Players:GetUserThumbnailAsync(LP.UserId,
            Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
        local gui = Fluent.GUI
        for _, d in ipairs(gui:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text == "Dashboard"
                and d.Parent and d.Parent:IsA("TextButton") then
                for _, k in ipairs(d.Parent:GetChildren()) do
                    if k:IsA("ImageLabel") then
                        k.Image = icerik
                    end
                end
                break
            end
        end
    end)
end)

-- Canli istatistik: paragrafin icerik TextLabel'ini bulup .Text yaz
-- (bu Fluent surumunde paragraph:Set YOK - canli testle kanitlandi)
local function dashIcerikBul()
    local gui = Fluent and Fluent.GUI
    if not gui then return nil end
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Player" and d.Parent then
            for _, k in ipairs(d.Parent:GetChildren()) do
                if k:IsA("TextLabel") and k ~= d and #k.Text > 0 then
                    return k
                end
            end
        end
    end
    return nil
end

task.spawn(function()
    while KSWH.GEN == GEN do
        pcall(function()
            local lbl = dashIcerikBul()
            if lbl then
                local we = workspace:FindFirstChild("WormEvents")
                local ev = we and we:GetAttribute("Current") or "-"
                local st = KSWH.stats or {}
                lbl.Text = string.format(
                    "%s (@%s)\nPlatform: %s\n\nLevel: %s | XP Total: %s\nEats: %s | Event: %s\nProps smashed: %d | NPCs eaten: %d\n\nFarm: %s | Auto Eat: %s\nInf Stamina: %s | Speed: %s",
                    LP.DisplayName, LP.Name,
                    isMobile and "Mobile" or "PC",
                    tostring(LP:GetAttribute("Level")),
                    tostring(LP:GetAttribute("XpTotal")),
                    tostring(LP:GetAttribute("EatsLifetime")),
                    tostring(ev),
                    st.smashed or 0, st.npcs or 0,
                    KSWH.cfg.farm and "ON" or "OFF",
                    KSWH.cfg.autoEat and "ON" or "OFF",
                    KSWH.cfg.infStamina and "ON" or "OFF",
                    KSWH.cfg.speed and "ON" or "OFF"
                )
            end
        end)
        task.wait(5)
    end
end)

TabDash:AddButton({
    Title = "Re-scan Worm State",
    Description = "Finds the worm physics state again after respawn",
    Callback = function()
        state = findWormState()
        KSWH.addLog("INIT", "manual state rescan: " .. tostring(state ~= nil))
        notify("Sandworm", state and "Worm state found" or "Worm state not found (become a worm first)", 3)
    end,
})

-- ---- FARM TAB ----
KSWH.ui.farmToggle = TabFarm:AddToggle("KSWH_Farm", {
    Title = "Auto Prop Farm",
    Description = "Sweeps WormProps + DesertTown, waits for respawn",
    Default = false,
    Callback = function(v)
        KSWH.cfg.farm = v
        KSWH.addLog("UI", "AutoFarm = " .. tostring(v))
    end,
})
KSWH.ui.farmPin = TabFarm:AddSlider("KSWH_FarmPin", {
    Title = "Prop Circle Time",
    Description = "Seconds circling inside each prop for XP",
    Default = 2.2, Min = 1.2, Max = 4, Rounding = 1,
    Callback = function(v) KSWH.cfg.farmPin = v end,
})
KSWH.ui.farmHiz = TabFarm:AddSlider("KSWH_FarmHiz", {
    Title = "Crawl Speed",
    Description = "Worm crawl speed (studs/sec)",
    Default = 135, Min = 80, Max = 250, Rounding = 0,
    Callback = function(v) KSWH.cfg.farmHiz = v end,
})
KSWH.ui.eatToggle = TabFarm:AddToggle("KSWH_Eat", {
    Title = "Auto NPC/Camel Eat",
    Description = "Chases the nearest NPC + Bite (respects cooldown)",
    Default = false,
    Callback = function(v)
        KSWH.cfg.autoEat = v
        KSWH.addLog("UI", "AutoEat = " .. tostring(v))
    end,
})
KSWH.ui.staminaToggle = TabFarm:AddToggle("KSWH_Stamina", {
    Title = "Infinite Stamina",
    Description = "Free alternative to the Robux gamepass",
    Default = false,
    Callback = function(v)
        KSWH.cfg.infStamina = v
        KSWH.addLog("UI", "InfStamina = " .. tostring(v))
    end,
})

-- ---- EXTRA TAB ----
KSWH.ui.speedToggle = TabExtra:AddToggle("KSWH_Speed", {
    Title = "Speed Hack",
    Default = false,
    Callback = function(v)
        KSWH.cfg.speed = v
        KSWH.addLog("UI", "Speed = " .. tostring(v))
    end,
})
KSWH.ui.speedSlider = TabExtra:AddSlider("KSWH_SpeedVal", {
    Title = "Speed",
    Default = 45, Min = 20, Max = 150, Rounding = 0,
    Callback = function(v)
        KSWH.cfg.speedVal = v
        KSWH.addLog("UI", "SpeedVal = " .. tostring(v))
    end,
})
TabExtra:AddButton({
    Title = "Toggle Worm Form",
    Description = "Become a worm / human without any keybind",
    Callback = function()
        local worm = select(1, isWorm())
        KSWH.fn.setForm(not worm)
    end,
})
KSWH.ui.tpDropdown = TabExtra:AddDropdown("KSWH_TP", {
    Title = "Teleport",
    Description = "Pick a location to travel to",
    Values = { "DesertTown", "OilField", "Ruins", "Mine", "FloodTower", "Train" },
    Default = nil,
    Callback = function(v)
        KSWH.fn.tp(v)
    end,
})
KSWH.ui.skinDropdown = TabExtra:AddDropdown("KSWH_Skin", {
    Title = "Skin Preview",
    Description = "Local cosmetic - only you see it",
    Values = { "Normal", "Maw", "Viper", "Antlion", "Shark" },
    Default = nil,
    Callback = function(v)
        if v then KSWH.fn.skinPreview(v) end
    end,
})
TabExtra:AddButton({
    Title = "Reset Skin",
    Description = "Restore your real skin",
    Callback = function() KSWH.fn.resetSkin() end,
})
KSWH.ui.bestSkinToggle = TabExtra:AddToggle("KSWH_BestSkin", {
    Title = "Auto Best Skin",
    Description = "Instantly wear the best worm you can use - updates on level up",
    Default = false,
    Callback = function(v)
        KSWH.cfg.autoBestSkin = v
        if v then
            task.spawn(function()
                task.wait(0.2)
                KSWH.fn.equipBest()
            end)
        end
    end,
})

-- ANLIK IZLEYICI: level atlayinca / yeni skin acilinca hemen en iyiyi kusan.
-- Preview aktifken (realSkin set) karismaz. Gecis atlamalarindan sonra
-- 3sn'de bir tarama yeterli - InvokeServer sadece degisince atilir.
task.spawn(function()
    while true do
        task.wait(3)
        if KSWH.GEN ~= GEN then return end
        if KSWH.cfg.autoBestSkin and not KSWH.realSkin then
            local best = KSWH.fn.bestSkin()
            local simdiki = LP:GetAttribute("WormSkin")
            if best and best.id ~= simdiki then
                pcall(function()
                    return RS.Sandworm.Remotes.EquipSkin:InvokeServer(best.id)
                end)
                task.wait(0.5)
                if LP:GetAttribute("WormSkin") == best.id then
                    KSWH.addLog("SKIN", "auto-best -> " .. best.id .. " (new unlock!)")
                    notify("Best Skin", best.id .. " - new best available!", 4)
                end
            end
        end
    end
end)

-- ---- SETTINGS TAB ----
TabSettings:AddToggle("KSWH_Notify", {
    Title = "Notifications",
    Default = KSWH.cfg.showNotify,
    Callback = function(v) KSWH.cfg.showNotify = v end,
})
TabSettings:AddToggle("KSWH_AntiAFK", {
    Title = "Anti-AFK",
    Description = "Blocks the 20-min idle kick - leave it on while farming AFK",
    Default = true,
    Callback = function(v) KSWH.cfg.antiAFK = v end,
})
KSWH.ui.antiAFKToggle = true -- referans isareti (eleman TabSettings'te)
TabSettings:AddToggle("KSWH_EventMon", {
    Title = "Event Monitor (Blood Moon)",
    Description = "Notifies when server events go live",
    Default = true,
    Callback = function(v) KSWH.cfg.eventMon = v end,
})

-- ---- ANTI-AFK ENGINE ----
-- (1) oyunun 20 dk Idle kick sayacini blokla: Idled sinyali gelince
--     VirtualUser:CaptureController + ClickButton2 sayaci sifirlar.
-- (2) yedek: her 3 dakikada bir canlilik sinyali (Idled yolda kaybolursa).
local VUSuccess = false
pcall(function()
    local vu = getgenv().VirtualUser or (game:FindService("VirtualUser") ~= nil and game:GetService("VirtualUser"))
    if vu then VUSuccess = true end
end)
local idledBaglanti
pcall(function()
    local lpAFK = LP
    idledBaglanti = lpAFK.Idled:Connect(function()
        if KSWH.cfg.antiAFK ~= false then
            pcall(function()
                local vu = game:GetService("VirtualUser")
                vu:CaptureController()
                vu:ClickButton2(Vector2.new())
            end)
        end
    end)
end)
-- yedek: periyodik canlik sinyali (Idled sinyali yakalanamazsa da calisir)
task.spawn(function()
    while true do
        task.wait(180)
        if KSWH.GEN ~= GEN then return end
        if KSWH.cfg.antiAFK ~= false then
            pcall(function()
                local vu = game:GetService("VirtualUser")
                vu:CaptureController()
                vu:ClickButton2(Vector2.new())
            end)
        end
    end
end)
KSWH.addLog("INIT", "Anti-AFK active (Idled block + 3min heartbeat)")
local logParagraf = TabSettings:CreateParagraph("LogP", { Title = "Activity Log", Content = "-" })
TabSettings:AddButton({
    Title = "Refresh Logs",
    Callback = function()
        pcall(function()
            local gui = Fluent and Fluent.GUI
            if not gui then return end
            -- 'Activity Log' basliginin kardes icerik labelini bul (Rochess yontemi)
            for _, d in ipairs(gui:GetDescendants()) do
                if d:IsA("TextLabel") and d.Text == "Activity Log" and d.Parent then
                    for _, k in ipairs(d.Parent:GetChildren()) do
                        if k:IsA("TextLabel") and k ~= d then
                            local son = {}
                            for i = math.max(1, #KSWH.log - 7), #KSWH.log do
                                son[#son + 1] = KSWH.log[i]
                            end
                            k.Text = table.concat(son, "\n")
                            return
                        end
                    end
                end
            end
        end)
    end,
})

-- ---- DISCORD TAB ----
TabDiscord:CreateParagraph("DiscordInfo", {
    Title = "Zynex Community",
    Content = "Join our Discord! Come hang out with us.",
})
TabDiscord:AddButton({
    Title = "Copy Discord Link",
    Callback = function()
        pcall(function() setclipboard("https://discord.gg/ehbX2MVbTw") end)
        notify("Copied!", "Discord link copied.", 3)
    end,
})

-- =============================== SAVE MANAGER ===============================
getgenv().KSWH_STAGE = "ui-elemanlari-ok"
pcall(function()
    SaveManager:SetLibrary(Fluent)
    SaveManager:SetIgnoreIndexes({ "MenuButton" })
    SaveManager:SetFolder("SandwormHub")
    InterfaceManager:SetLibrary(Fluent)
    InterfaceManager:BuildInterfaceSection(TabSettings)
    SaveManager:BuildConfigSection(TabSettings)
end)
getgenv().KSWH_STAGE = "savemanager-ok"

-- =============================== MOBIL ZYNEX BUTON (ROCHESS BIREBIR) ===============================
-- (1) Fluent'in GOZ IKONU tamamen YOK EDILIR (Destroy - kullanicinin istegi,
--     Rochess ile ayni yontem: geri gelmez cunku nesne silinir).
-- (2) Rochess'teki 'Zynex' butonu birebir: 74x30 sagda, mor stroke, tam
--     yuvarlak, suruklenebilir + 6px tap esigi, dokun = Window:Minimize().
if isMobile then
    task.spawn(function()
        task.wait(1)
        pcall(function()
            local gui = Fluent and Fluent.GUI
            if not (gui and gui.Parent) then return end
            -- 1) GOZ SIMGESINI TAMAMEN YOK ET (Destroy: bir daha asla gorunmez)
            for _, c in ipairs(gui:GetChildren()) do
                if c:IsA("ImageButton") then c:Destroy() end
            end
            -- 2) Zynex butonu (Rochess birebir kopya)
            local UIS2 = game:GetService("UserInputService")
            local btn = Instance.new("TextButton")
            btn.Name = "ZynexToggle"
            btn.Text = "Zynex"
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 13
            btn.TextColor3 = Color3.new(1, 1, 1)
            btn.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
            btn.BackgroundTransparency = 0.15
            btn.Size = UDim2.fromOffset(74, 30)
            btn.Position = UDim2.new(1, -84, 0.5, -15)
            btn.AutoButtonColor = false
            btn.BorderSizePixel = 0
            btn.ZIndex = 50
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = btn
            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(130, 95, 255)
            stroke.Thickness = 1.5
            stroke.Transparency = 0.25
            stroke.Parent = btn
            btn.Parent = gui
            -- surukleme + dokunma ayristi (6px esik: alti = tap, ustu = tasi)
            local surukleniyor = false
            local tapGecerli = false
            local baslangicInput, baslangicPos
            btn.InputBegan:Connect(function(g)
                if g.UserInputType == Enum.UserInputType.Touch
                    or g.UserInputType == Enum.UserInputType.MouseButton1 then
                    surukleniyor = true
                    tapGecerli = true
                    baslangicInput = g.Position
                    baslangicPos = btn.Position
                end
            end)
            btn.InputEnded:Connect(function(g)
                if g.UserInputType == Enum.UserInputType.Touch
                    or g.UserInputType == Enum.UserInputType.MouseButton1 then
                    surukleniyor = false
                end
            end)
            UIS2.InputChanged:Connect(function(g)
                if surukleniyor
                    and (g.UserInputType == Enum.UserInputType.Touch
                        or g.UserInputType == Enum.UserInputType.MouseMovement) then
                    local dx = g.Position.X - baslangicInput.X
                    local dy = g.Position.Y - baslangicInput.Y
                    if math.abs(dx) > 6 or math.abs(dy) > 6 then tapGecerli = false end
                    btn.Position = UDim2.new(
                        baslangicPos.X.Scale, baslangicPos.X.Offset + dx,
                        baslangicPos.Y.Scale, baslangicPos.Y.Offset + dy
                    )
                end
            end)
            btn.Activated:Connect(function()
                if tapGecerli then
                    pcall(function() Window:Minimize() end)
                end
            end)
            KSWH.addLog("UI", "Zynex button installed (Rochess style) - eye icon destroyed")
        end)
    end)
end

-- =============================== ZORLA INGILIZCE ===============================
task.spawn(function()
    task.wait(1)
    local function temizle()
        local sgui = Fluent and Fluent.GUI
        if not sgui then return end
        pcall(function()
            sgui.AutoLocalize = false
            for _, d in ipairs(sgui:GetDescendants()) do
                if d:IsA("GuiBase2d") then pcall(function() d.AutoLocalize = false end) end
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    local ceviri = {
                        ["Ayarlar"] = "Settings", ["Yukle"] = "Load", ["Kaydet"] = "Save",
                        ["Tema"] = "Theme", ["Arayuz"] = "Interface", ["Klasor"] = "Folder",
                        ["Kisayol"] = "Hotkey", ["Dosya Olustur"] = "Create File",
                        ["Yapilandirma"] = "Configuration", ["Sil"] = "Delete",
                    }
                    if ceviri[d.Text] then d.Text = ceviri[d.Text] end
                end
            end
        end)
    end
    temizle()
    task.wait(2)
    temizle()
end)

-- =============================== FINAL: PENCEREYI AC ===============================
-- Kurulum sirasi boyunca gizliydi; her sey hazir oldugunda simdi ac
KSWH.addLog("INIT", "Sandworm Hub loaded (" .. (isMobile and "mobile" or "pc") .. ")")
Window:SelectTab(1)
pcall(function() Fluent.GUI.Name = "ZynexSandworm" end)
pcall(function() Fluent.GUI.Enabled = true end)
-- TEK acilis bildirimi: sessizlik (4sn) bittikten hemen sonra
task.delay(4.2, function()
    if KSWH.GEN == GEN then
        notify("Zynex | Sandworm", (isMobile and "MOBILE" or "PC") .. " mode loaded", 4)
    end
end)
