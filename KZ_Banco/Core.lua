-- KZ_Banco: escaneia bags + bau da guilda
local ADDON = "|cff00ccff[KZ Banco]|r"

local function esc(s)
    if not s then return "" end
    s = string.gsub(s, "|", "_")
    s = string.gsub(s, ";", "_")
    s = string.gsub(s, ":", "_")
    return s
end

local function getItemID(link)
    if not link then return "0" end
    local _, _, id = string.find(link, "item:(%d+)")
    return id or "0"
end

local function stripColor(s)
    if not s then return "" end
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = string.gsub(s, "|r", "")
    return s
end

-- Detecta qualidade pelo RGB do nome no tooltip
local function colorToQuality(r, g, b)
    r = r or 1; g = g or 1; b = b or 1
    -- laranja = legendario
    if r > 0.9 and g > 0.4 and g < 0.6 and b < 0.1 then return 5 end
    -- roxo = epico
    if r > 0.5 and b > 0.7 and g < 0.3 then return 4 end
    -- azul = raro
    if b > 0.7 and r < 0.2 then return 3 end
    -- verde = incomum
    if g > 0.8 and r < 0.2 and b < 0.2 then return 2 end
    -- branco = comum
    if r > 0.9 and g > 0.9 and b > 0.9 then return 1 end
    -- cinza = pobre
    return 0
end

-- ======================== SCAN DE CONTAINERS ========================

-- Texturas de UI que nao sao icones de item
local BAD_ICONS = {
    ["ui-quickslot2"] = true, ["ui-quickslot"] = true,
    ["inv_misc_questionmark"] = true, ["interface"] = true,
}

local function getIconName(texture)
    if not texture then return "" end
    local _, _, icon = string.find(texture, "([^\\/]+)$")
    if not icon then return "" end
    icon = string.lower(icon)
    -- Remove extensao .blp se houver
    icon = string.gsub(icon, "%.blp$", "")
    if BAD_ICONS[icon] then return "" end
    return icon
end

-- Extrai nome e qualidade direto do item link (funciona sem cache)
-- Link format: |cffCOLOR|Hitem:ID:...|h[Nome]|h|r
local function parseLink(link)
    if not link then return nil, 1 end
    local _, _, name = string.find(link, "%[(.-)%]")
    local quality = 1
    local _, _, hex = string.find(link, "|c(%x%x%x%x%x%x%x%x)")
    if hex then
        local low = string.lower(hex)
        if     low == "ff9d9d9d" then quality = 0
        elseif low == "ff1eff00" then quality = 2
        elseif low == "ff0070dd" then quality = 3
        elseif low == "ffa335ee" then quality = 4
        elseif low == "ffff8000" then quality = 5
        else quality = 1 end
    end
    return name, quality
end

-- Forca o cache de um item usando SetHyperlink no GameTooltip
local function cacheItem(link)
    if not link then return end
    local name = GetItemInfo(link)
    if name then return end  -- ja cacheado
    -- Forca via tooltip (nao visivel)
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Hide()
end

local function scanContainer(bag)
    local items = {}
    local slots = GetContainerNumSlots(bag)
    if not slots or slots == 0 then return items end
    for slot = 1, slots do
        local texture, count = GetContainerItemInfo(bag, slot)
        if texture then
            local link = GetContainerItemLink(bag, slot)
            -- Forca cache se necessario
            cacheItem(link)
            -- Nome e qualidade do link (sempre funciona)
            local name, quality = parseLink(link)
            -- GetItemInfo para ilvl, icone e tipo
            local ilvl, itexture, itype, isubtype = 0, nil, "", ""
            if link then
                local _, _, _, il, _, t, st, _, _, itex = GetItemInfo(link)
                ilvl     = il or 0
                itexture = itex
                itype    = t or ""
                isubtype = st or ""
            end
            table.insert(items, {
                id      = getItemID(link),
                name    = name or "?",
                count   = count and math.abs(count) or 1,
                quality = quality,
                ilvl    = ilvl,
                icon    = getIconName(itexture or texture),
                itype   = itype,
                isubtype= isubtype,
            })
        end
    end
    return items
end

local function scanBags()
    local items = {}
    for bag = 0, 4 do
        local got = scanContainer(bag)
        for _, v in ipairs(got) do table.insert(items, v) end
    end
    return items
end

local function scanBank()
    local items = {}
    local main = scanContainer(-1)
    for _, v in ipairs(main) do table.insert(items, v) end
    for bag = 5, 10 do
        local got = scanContainer(bag)
        for _, v in ipairs(got) do table.insert(items, v) end
    end
    return items
end

-- ======================== SCAN GUILD BANK (AUTO) ========================

local function autoScanGuildTab()
    local char = UnitName("player")
    if not KZ_BancoDB then KZ_BancoDB = {} end
    if not KZ_BancoDB[char] then KZ_BancoDB[char] = {} end
    if not KZ_BancoDB[char].guildbank then KZ_BancoDB[char].guildbank = {} end

    local countTab = 0
    -- Verifica ate 150 frames de slot de banco por garantia
    for i = 1, 150 do
        local frame = getglobal("GuildBankFrameItem" .. i)
        if frame and frame:IsVisible() then
            local link = frame.link or frame.itemLink
            local name, quality
            
            -- Fallback brutal: Se o frame nao expoe o link diretamente, disparamos o OnEnter
            -- para preencher o GameTooltip e lemos o nome dele.
            if not link then
                GameTooltip:SetOwner(frame, "ANCHOR_NONE")
                local onEnter = frame:GetScript("OnEnter")
                if onEnter then
                    local oldThis = getglobal("this")
                    setglobal("this", frame)
                    onEnter()
                    setglobal("this", oldThis)
                    
                    local nameObj = GameTooltipTextLeft1
                    if nameObj then
                        local rawName = nameObj:GetText()
                        if rawName and rawName ~= "" then
                            name = stripColor(rawName)
                            local r, g, b = nameObj:GetTextColor()
                            quality = colorToQuality(r, g, b)
                        end
                    end
                end
                GameTooltip:Hide()
            end

            if link or name then
                local itemID = getItemID(link)
                if not name then name, quality = parseLink(link) end
                
                -- Remove colchetes do nome se vieram do link
                if name then
                    name = string.gsub(name, "%[", "")
                    name = string.gsub(name, "%]", "")
                end

                if link then cacheItem(link) end
                
                -- Usa o link ou o nome para puxar todas as infos reais do cliente WoW
                local query = link or name
                local _, _, _, il, _, t, st, _, _, itex = GetItemInfo(query)
                
                local iconStr = ""
                if itex then iconStr = getIconName(itex) end
                
                -- Se não achou ícone, tenta pegar da textura do frame
                if iconStr == "" then
                    local tex = getglobal("GuildBankFrameItem" .. i .. "IconTexture")
                    if tex and tex.GetTexture then
                        iconStr = getIconName(tex:GetTexture())
                    else
                        local ntex = frame:GetNormalTexture()
                        if ntex and ntex.GetTexture then iconStr = getIconName(ntex:GetTexture()) end
                    end
                end
                
                -- Count fallback
                local count = 1
                local countText = getglobal("GuildBankFrameItem" .. i .. "Count")
                if countText and countText.GetText then
                    local txt = countText:GetText()
                    if txt and txt ~= "" then count = tonumber(txt) or 1 end
                elseif frame.count then
                    count = tonumber(frame.count) or 1
                end

                table.insert(KZ_BancoDB[char].guildbank, {
                    id      = itemID,
                    name    = name or "?",
                    count   = count,
                    quality = quality or 1,
                    icon    = iconStr,
                    ilvl    = il or 0,
                    itype   = t or "",
                    isubtype= st or "",
                })
                countTab = countTab + 1
            end
        end
    end
    
    if countTab > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " |cff00ff00Escaneado:|r " .. countTab .. " itens nesta aba.")
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " Total acumulado no banco da guilda: " .. table.getn(KZ_BancoDB[char].guildbank))
    else
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " |cffff0000Erro:|r Nenhum item encontrado na tela (ou a aba esta vazia).")
    end
end

local function clearGuildScan()
    local char = UnitName("player")
    if KZ_BancoDB and KZ_BancoDB[char] then
        KZ_BancoDB[char].guildbank = {}
        KZ_BancoDB[char].logs = {}
    end
    DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " |cffff9900Banco da Guilda e Logs Resetados!|r Abra uma aba e use /banco guild.")
end

local function scanGuildLog()
    local possibleFrames = {
        "GuildBankFrameLog",
        "GuildBankMoneyLogFrame",
        "GuildBankFrameMoneyLog",
        "GuildBankLogMoney",
        "GuildBankMoneyFrame"
    }

    local count = 0
    local char = UnitName("player")
    if not KZ_BancoDB then KZ_BancoDB = {} end
    if not KZ_BancoDB[char] then KZ_BancoDB[char] = {} end
    if not KZ_BancoDB[char].logs then KZ_BancoDB[char].logs = {} end

    -- Busca recursiva em todos os filhos e regioes
    local function searchFontStrings(frame)
        if not frame then return end
        
        -- Busca nas regioes do frame
        if type(frame.GetRegions) == "function" then
            local regions = { frame:GetRegions() }
            for _, r in ipairs(regions) do
                if r and type(r.GetObjectType) == "function" and r:GetObjectType() == "FontString" then
                    local text = r:GetText()
                    if text and text ~= "" and (string.find(text, "deposited") or string.find(text, "withdrew")) then
                        text = stripColor(text)
                        local isDup = false
                        for _, exist in ipairs(KZ_BancoDB[char].logs) do
                            if exist == text then isDup = true; break end
                        end
                        if not isDup then
                            table.insert(KZ_BancoDB[char].logs, text)
                            count = count + 1
                        end
                    end
                end
            end
        end

        -- Busca nos filhos do frame
        if type(frame.GetChildren) == "function" then
            local children = { frame:GetChildren() }
            for _, c in ipairs(children) do
                searchFontStrings(c)
            end
        end
    end

    local foundAnyFrame = false
    for _, fname in ipairs(possibleFrames) do
        local f = getglobal(fname)
        if f then
            foundAnyFrame = true
            searchFontStrings(f)
        end
    end

    if not foundAnyFrame then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " |cffff0000Erro:|r Nenhuma aba de logs foi encontrada na tela. Abra a aba de Log ou Money Log primeiro.")
        return
    end

    if count > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " |cff00ff00Logs Escaneados:|r " .. count .. " novas linhas capturadas.")
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " Total acumulado: " .. table.getn(KZ_BancoDB[char].logs) .. " linhas.")
    else
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " Nenhuma linha nova de log encontrada nesta tela. (Pode estar vazia ou a janela e protegida)")
    end
end

-- ======================== POPUP ========================

local popup = CreateFrame("Frame", "KZ_BancoPopup", UIParent)
popup:SetWidth(500)
popup:SetHeight(130)
popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
popup:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
popup:SetBackdropColor(0, 0, 0, 0.95)
popup:SetFrameStrata("DIALOG")
popup:EnableMouse(true)
popup:SetMovable(true)
popup:RegisterForDrag("LeftButton")
popup:SetScript("OnDragStart", function() this:StartMoving() end)
popup:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
popup:Hide()

local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", popup, "TOP", 0, -10)
title:SetText("|cffffd700KZ Banco — Codigo para o Site|r")

local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 2, 2)
closeBtn:SetScript("OnClick", function() KZ_BancoPopup:Hide() end)

local eb = CreateFrame("EditBox", "KZ_BancoCodeBox", popup, "InputBoxTemplate")
eb:SetWidth(462)
eb:SetHeight(28)
eb:SetPoint("TOP", title, "BOTTOM", 0, -12)
eb:SetAutoFocus(false)
eb:SetMaxLetters(0)
eb:SetScript("OnEscapePressed", function() KZ_BancoPopup:Hide() end)
eb:SetScript("OnEnterPressed", function() this:HighlightText() end)

local hint = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hint:SetPoint("BOTTOM", popup, "BOTTOM", 0, 10)
hint:SetText("|cff888888Clique no campo → Ctrl+A → Ctrl+C|r")

local function showCode(code)
    KZ_BancoCodeBox:SetText(code)
    KZ_BancoPopup:Show()
    KZ_BancoCodeBox:SetFocus()
    KZ_BancoCodeBox:HighlightText()
end

-- ======================== SERIALIZE / GENERATE ========================

local function serializeItems(items)
    local result = ""
    for i, item in ipairs(items) do
        if i > 1 then result = result .. "|" end
        result = result .. item.id
            .. ":" .. esc(item.name)
            .. ":" .. item.quality
            .. ":" .. item.count
            .. ":" .. (item.icon or "")
            .. ":" .. (item.ilvl or 0)
            .. ":" .. esc(item.itype or "")
            .. ":" .. esc(item.isubtype or "")
    end
    return result
end

local function serializeLogs(logs)
    if not logs or table.getn(logs) == 0 then return "" end
    local result = ""
    for i, line in ipairs(logs) do
        if i > 1 then result = result .. "|" end
        result = result .. esc(line)
    end
    return result
end

local function generateCode(char, bagItems, bankItems, guildItems2, logs)
    local code = "BANCO1;" .. esc(char) .. ";" .. date("%Y-%m-%d %H:%M:%S")
    code = code .. ";" .. serializeItems(bagItems)
    code = code .. ";" .. serializeItems(bankItems)
    code = code .. ";" .. (guildItems2 and serializeItems(guildItems2) or "")
    code = code .. ";" .. serializeLogs(logs)
    return code
end

-- ======================== FRAME DE EVENTOS ========================

local frame = CreateFrame("Frame", "KZ_BancoFrame", UIParent)
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:RegisterEvent("BANKFRAME_CLOSED")

local bankOpen = false

frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if not KZ_BancoDB then KZ_BancoDB = {} end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        this:SetScript("OnUpdate", function()
            this:SetScript("OnUpdate", nil)
            local char  = UnitName("player")
            local items = scanBank()
            if not KZ_BancoDB then KZ_BancoDB = {} end
            if not KZ_BancoDB[char] then KZ_BancoDB[char] = {} end
            KZ_BancoDB[char].bank = items
            DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " Bau pessoal: " .. table.getn(items) .. " itens.")
        end)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    end
end)

-- ======================== COMANDOS ========================

local function cmdCodigo()
    local char = UnitName("player")
    if not KZ_BancoDB then KZ_BancoDB = {} end
    if not KZ_BancoDB[char] then KZ_BancoDB[char] = {} end

    local bagItems   = scanBags()
    local bankItems  = KZ_BancoDB[char].bank or {}
    local guildItems2 = KZ_BancoDB[char].guildbank or {}
    local logs = KZ_BancoDB[char].logs or {}
    local code = generateCode(char, bagItems, bankItems, guildItems2, logs)

    showCode(code)
    if ExportFile then ExportFile("kz_banco_" .. char .. ".txt", code) end

    DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " Bags: " .. table.getn(bagItems) ..
        " | Bau: " .. table.getn(bankItems) ..
        " | Guilda: " .. table.getn(guildItems2) ..
        " | Logs: " .. table.getn(logs))
end

SLASH_KZ_BANCO1 = "/banco"
SLASH_KZ_BANCO2 = "/kzbanco"
SlashCmdList["KZ_BANCO"] = function(msg)
    local cmd = string.lower(msg or "")
    if cmd == "guild" then
        autoScanGuildTab()
    elseif cmd == "guild clear" then
        clearGuildScan()
    elseif cmd == "log" then
        scanGuildLog()
    elseif cmd == "codigo" or cmd == "code" or cmd == "" then
        cmdCodigo()
    elseif cmd == "scan" then
        local char = UnitName("player")
        if not KZ_BancoDB then KZ_BancoDB = {} end
        if not KZ_BancoDB[char] then KZ_BancoDB[char] = {} end
        local bagItems = scanBags()
        KZ_BancoDB[char].bags = bagItems
        if bankOpen then
            local bankItems = scanBank()
            KZ_BancoDB[char].bank = bankItems
            DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " Bags: " .. table.getn(bagItems) .. " | Bau: " .. table.getn(bankItems))
        else
            DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " Bags: " .. table.getn(bagItems) .. " itens.")
        end
    elseif cmd == "help" then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " /banco             — gera codigo (popup para copiar)")
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " /banco guild       — escaneia a aba aberta do banco da guilda imediatamente")
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " /banco log         — escaneia o painel de LOG (Items ou Money) aberto no banco")
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " /banco guild clear — zera o banco da guilda e logs acumulados")
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " /banco scan        — escaneia bags manualmente")
    else
        DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " Use /banco help")
    end
end

DEFAULT_CHAT_FRAME:AddMessage(ADDON .. " Carregado! |cffffd700/banco help|r para ver comandos atualizados!")
