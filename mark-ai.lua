--!nocheck
-- ============================================================
--  MARK AI · Cliente Groq para Roblox Executor
--  Pega las 4 partes en un archivo mark_ai.lua en orden.
-- ============================================================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")

local http_request = syn and syn.request or request or http_request
if not http_request then
    warn("[Mark AI] Executor sin soporte HTTP."); return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local config = {
    model = "openai/gpt-oss-20b",
    systemPrompt = "Eres Mark, un asistente de IA amigable y conciso. Respondes en el chat de Roblox con máximo 2 oraciones. Si te mencionan con @markuriel o mark, responde de forma natural.",
    triggers = { "@markuriel", "mark" },
    proximityEnabled = false,
    proximityDistance = 30,
    userCooldown = 15,
    globalCooldown = 3,
    maxCompletionTokens = 512,
    maxHistoryPerPlayer = 20,
    historyFile = "MarkAI_History.json",
    listening = true,
    greetCooldown = 300,
    greetRangeMin = 10,
    greetRangeMax = 45,
}

local state = {
    lastGlobalRequest = 0, userCooldowns = {}, processedMessages = {},
    history = {}, followTarget = nil, followConnection = nil,
    greetedPlayers = {}, autonomyActive = false, autonomyInterval = 15,
    autonomyConnection = nil, listening = true,
}

local order = 0
local function nextOrder() order = order + 1 return order end
local function new(cls, props, parent)
    local i = Instance.new(cls)
    for k, v in pairs(props) do i[k] = v end
    if parent then i.Parent = parent end
    return i
end

local gui = new("ScreenGui", {
    Name = "MarkAI", ResetOnSpawn = false,
    IgnoreGuiInset = true, DisplayOrder = 999, Parent = playerGui,
})
local main = new("Frame", {
    Size = UDim2.new(0.88, 0, 0.85, 0),
    Position = UDim2.new(0.06, 0, 0.07, 0),
    BackgroundColor3 = Color3.fromRGB(28, 28, 38),
    BorderSizePixel = 0, Parent = gui,
})
new("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
new("UIStroke", { Color = Color3.fromRGB(60, 60, 80), Thickness = 1 }, main)

local titleBar = new("Frame", {
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundColor3 = Color3.fromRGB(0, 90, 150),
    BorderSizePixel = 0, Parent = main,
})
new("UICorner", { CornerRadius = UDim.new(0, 10) }, titleBar)
new("TextLabel", {
    Size = UDim2.new(1, -45, 1, 0), Position = UDim2.new(0, 10, 0, 0),
    BackgroundTransparency = 1, Text = "🤖 Mark AI · Groq",
    TextColor3 = Color3.new(1,1,1), Font = Enum.Font.GothamBold,
    TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Parent = titleBar,
})
local closeBtn = new("TextButton", {
    Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -30, 0, 4),
    BackgroundColor3 = Color3.fromRGB(180, 50, 50), Text = "✕",
    TextColor3 = Color3.new(1,1,1), Font = Enum.Font.GothamBold,
    TextSize = 14, Parent = titleBar,
})
new("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

local dragStart, startPos, dragging = nil, nil, false
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, input.Position, main.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)

local scroll = new("ScrollingFrame", {
    Size = UDim2.new(1, -8, 1, -44), Position = UDim2.new(0, 4, 0, 38),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6,
    CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarImageColor3 = Color3.fromRGB(0, 120, 200), Parent = main,
})
new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
new("UIPadding", { PaddingTop = UDim.new(0,5), PaddingBottom = UDim.new(0,5),
    PaddingLeft = UDim.new(0,5), PaddingRight = UDim.new(0,5), Parent = scroll })

local function label(text)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
        Text = text, TextColor3 = Color3.fromRGB(170,170,195),
        Font = Enum.Font.GothamSemibold, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = nextOrder(), Parent = scroll,
    })
end
local function box(placeholder, default, height)
    local h = height or 26
    local b = new("TextBox", {
        Size = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = Color3.fromRGB(48,48,62), TextColor3 = Color3.new(1,1,1),
        PlaceholderText = placeholder, PlaceholderColor3 = Color3.fromRGB(120,120,140),
        Text = default or "", Font = Enum.Font.Code, TextSize = 12,
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = h > 40 and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
        MultiLine = h > 40, LayoutOrder = nextOrder(), Parent = scroll,
    })
    new("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
    new("UIPadding", { PaddingLeft = UDim.new(0,6), PaddingRight = UDim.new(0,6) }, b)
    return b
end
local function row()
    return new("Frame", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1,
        LayoutOrder = nextOrder(), Parent = scroll,
    })
end
-- ==== API KEY ====
label("🔑 API Key de Groq")
local apiKeyBox = box("gsk_...", "", 26)

-- ==== MODELO ====
label("🧠 Modelo")
local modelRow = row()
local btn20 = new("TextButton", {
    Size = UDim2.new(0.5, -3, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 120, 200),
    Text = "⚡ GPT-OSS-20B", TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.GothamBold, TextSize = 11, Parent = modelRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, btn20)
local btn120 = new("TextButton", {
    Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0),
    BackgroundColor3 = Color3.fromRGB(48,48,62), Text = "🧠 GPT-OSS-120B",
    TextColor3 = Color3.fromRGB(150,150,170), Font = Enum.Font.GothamBold,
    TextSize = 11, Parent = modelRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, btn120)
local function selectModel(id, active, inactive)
    config.model = id
    active.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    active.TextColor3 = Color3.new(1,1,1)
    inactive.BackgroundColor3 = Color3.fromRGB(48,48,62)
    inactive.TextColor3 = Color3.fromRGB(150,150,170)
end
btn20.MouseButton1Click:Connect(function() selectModel("openai/gpt-oss-20b", btn20, btn120) end)
btn120.MouseButton1Click:Connect(function() selectModel("openai/gpt-oss-120b", btn120, btn20) end)

-- ==== PROMPT SISTEMA ====
label("📝 Prompt de sistema")
local systemBox = box("Instrucciones...", config.systemPrompt, 70)
systemBox:GetPropertyChangedSignal("Text"):Connect(function() config.systemPrompt = systemBox.Text end)

-- ==== TRIGGERS ====
label("🎯 Triggers (separados por coma)")
local triggerBox = box("@markuriel, mark", table.concat(config.triggers, ", "), 26)
triggerBox:GetPropertyChangedSignal("Text"):Connect(function()
    local list = {}
    for t in string.gmatch(triggerBox.Text, "[^,%s]+") do table.insert(list, t) end
    if #list > 0 then config.triggers = list end
end)

-- ==== PROXIMIDAD ====
label("📍 Proximidad")
local proxRow = row()
local proxBtn = new("TextButton", {
    Size = UDim2.new(0.55, -3, 1, 0), BackgroundColor3 = Color3.fromRGB(80, 40, 40),
    Text = "Proximidad: OFF", TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.GothamBold, TextSize = 11, Parent = proxRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, proxBtn)
local distBox = new("TextBox", {
    Size = UDim2.new(0.45, -3, 1, 0), Position = UDim2.new(0.55, 3, 0, 0),
    BackgroundColor3 = Color3.fromRGB(48,48,62), TextColor3 = Color3.new(1,1,1),
    Text = "30", Font = Enum.Font.Code, TextSize = 11,
    ClearTextOnFocus = false, Parent = proxRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, distBox)
proxBtn.MouseButton1Click:Connect(function()
    config.proximityEnabled = not config.proximityEnabled
    proxBtn.Text = config.proximityEnabled and "Proximidad: ON" or "Proximidad: OFF"
    proxBtn.BackgroundColor3 = config.proximityEnabled and Color3.fromRGB(40,120,60) or Color3.fromRGB(80,40,40)
end)
distBox:GetPropertyChangedSignal("Text"):Connect(function()
    local n = tonumber(distBox.Text); if n and n > 0 then config.proximityDistance = n end
end)

-- ==== ANTISPAM ====
label("🛡️ Antispam (segundos)")
local spamRow = row()
local userCoolBox = new("TextBox", {
    Size = UDim2.new(0.5, -3, 1, 0),
    BackgroundColor3 = Color3.fromRGB(48,48,62), TextColor3 = Color3.new(1,1,1),
    Text = "15", Font = Enum.Font.Code, TextSize = 11,
    ClearTextOnFocus = false, Parent = spamRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, userCoolBox)
local globalCoolBox = new("TextBox", {
    Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0),
    BackgroundColor3 = Color3.fromRGB(48,48,62), TextColor3 = Color3.new(1,1,1),
    Text = "3", Font = Enum.Font.Code, TextSize = 11,
    ClearTextOnFocus = false, Parent = spamRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, globalCoolBox)
userCoolBox:GetPropertyChangedSignal("Text"):Connect(function()
    local n = tonumber(userCoolBox.Text); if n then config.userCooldown = n end
end)
globalCoolBox:GetPropertyChangedSignal("Text"):Connect(function()
    local n = tonumber(globalCoolBox.Text); if n then config.globalCooldown = n end
end)

-- ==== ESCUCHA ====
local listenBtn = new("TextButton", {
    Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(40, 120, 60),
    Text = "🎧 Escuchando: ON", TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.GothamBold, TextSize = 12,
    LayoutOrder = nextOrder(), Parent = scroll,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, listenBtn)
listenBtn.MouseButton1Click:Connect(function()
    config.listening = not config.listening
    listenBtn.Text = config.listening and "🎧 Escuchando: ON" or "🔇 Escuchando: OFF"
    listenBtn.BackgroundColor3 = config.listening and Color3.fromRGB(40,120,60) or Color3.fromRGB(80,40,40)
end)

-- ==== PROMPT MANUAL ====
label("🧪 Prompt manual de prueba")
local testBox = box("Prompt de prueba...", "", 40)
local testBtn = new("TextButton", {
    Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.fromRGB(0, 120, 200),
    Text = "Enviar prompt de prueba", TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.GothamBold, TextSize = 12,
    LayoutOrder = nextOrder(), Parent = scroll,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, testBtn)

-- ==== MEMORIA ====
label("🧠 Memoria de conversación")
local memRow = row()
local saveMemBtn = new("TextButton", {
    Size = UDim2.new(0.5, -3, 1, 0), BackgroundColor3 = Color3.fromRGB(0, 120, 200),
    Text = "💾 Guardar", TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.GothamBold, TextSize = 11, Parent = memRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, saveMemBtn)
local clearMemBtn = new("TextButton", {
    Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0),
    BackgroundColor3 = Color3.fromRGB(180, 50, 50), Text = "🗑️ Borrar",
    TextColor3 = Color3.new(1,1,1), Font = Enum.Font.GothamBold,
    TextSize = 11, Parent = memRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, clearMemBtn)

-- ==== MOVIMIENTO ====
label("🏃 Movimiento")
local moveRow = row()
local followBtn = new("TextButton", {
    Size = UDim2.new(0.5, -3, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 120, 60),
    Text = "Seguir jugador", TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.GothamBold, TextSize = 11, Parent = moveRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, followBtn)
local stopFollowBtn = new("TextButton", {
    Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0),
    BackgroundColor3 = Color3.fromRGB(80, 40, 40), Text = "Detener",
    TextColor3 = Color3.new(1,1,1), Font = Enum.Font.GothamBold,
    TextSize = 11, Parent = moveRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, stopFollowBtn)
local followNameBox = box("Nombre del jugador a seguir", "", 26)

local emoteRow = row()
local EMOTES = { "Wave", "Dance", "Point", "Cheer" }
local emoteBtns = {}
for i, emote in ipairs(EMOTES) do
    local btn = new("TextButton", {
        Size = UDim2.new(0.25, -2, 1, 0), Position = UDim2.new((i-1)*0.25, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(70, 70, 100),
        Text = emote, TextColor3 = Color3.new(1,1,1),
        Font = Enum.Font.GothamBold, TextSize = 10, Parent = emoteRow,
    })
    new("UICorner", { CornerRadius = UDim.new(0, 5) }, btn)
    emoteBtns[emote] = btn
end

-- ==== AUTONOMÍA ====
label("🤖 Autonomía")
local autoRow = row()
local autoBtn = new("TextButton", {
    Size = UDim2.new(0.6, -3, 1, 0), BackgroundColor3 = Color3.fromRGB(80, 40, 40),
    Text = "Autonomía: OFF", TextColor3 = Color3.new(1,1,1),
    Font = Enum.Font.GothamBold, TextSize = 11, Parent = autoRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, autoBtn)
local intervalBox = new("TextBox", {
    Size = UDim2.new(0.4, -3, 1, 0), Position = UDim2.new(0.6, 3, 0, 0),
    BackgroundColor3 = Color3.fromRGB(48,48,62), TextColor3 = Color3.new(1,1,1),
    Text = "15", Font = Enum.Font.Code, TextSize = 11,
    ClearTextOnFocus = false, Parent = autoRow,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, intervalBox)

-- ==== STATUS ====
local statusLabel = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Color3.fromRGB(38, 38, 50),
    TextColor3 = Color3.fromRGB(200, 200, 220), Font = Enum.Font.Code,
    TextSize = 11, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    Text = "Listo. Configura tu API Key.",
    LayoutOrder = nextOrder(), Parent = scroll,
})
new("UICorner", { CornerRadius = UDim.new(0, 5) }, statusLabel)
new("UIPadding", { PaddingLeft = UDim.new(0,6), PaddingRight = UDim.new(0,6),
    PaddingTop = UDim.new(0,4), Parent = statusLabel })

local function setStatus(t)
    statusLabel.Text = t
    print("[Mark AI]", t)
end
local function getGeneralChannel()
    for _, ch in TextChatService:GetDescendants() do
        if ch:IsA("TextChannel") and ch.Name == "RBXGeneral" then return ch end
    end
    for _, ch in TextChatService:GetDescendants() do
        if ch:IsA("TextChannel") then return ch end
    end
end
local function sendToChat(text)
    local ch = getGeneralChannel()
    if ch then
        local ok = pcall(function() ch:SendAsync(text) end)
        if ok then return end
    end
    pcall(function()
        StarterGui:SetCore("ChatMakeSystemMessage", {
            Text = text, Color = Color3.fromRGB(100, 200, 255),
            Font = Enum.Font.GothamBold,
        })
    end)
end

local function getHumanoid()
    local char = player.Character
    if not char then return end
    return char:FindFirstChildOfClass("Humanoid")
end
local function walkTo(pos)
    local hum = getHumanoid(); if hum then hum:MoveTo(pos) end
end
local function followPlayer(targetName)
    local target = Players:FindFirstChild(targetName)
    if not target or not target.Character then
        setStatus("❌ Jugador no encontrado: " .. tostring(targetName)); return
    end
    if state.followConnection then pcall(function() task.cancel(state.followConnection) end) end
    state.followTarget = target
    setStatus("👣 Siguiendo a " .. targetName)
    state.followConnection = task.spawn(function()
        while state.followTarget == target and target.Character do
            local hum = getHumanoid()
            local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
            if hum and targetRoot then hum:MoveTo(targetRoot.Position) else break end
            task.wait(0.4)
        end
        state.followTarget = nil; state.followConnection = nil
    end)
end
local function stopFollowing()
    if state.followConnection then pcall(function() task.cancel(state.followConnection) end) end
    state.followTarget = nil; state.followConnection = nil
    local hum = getHumanoid()
    if hum and hum.RootPart then hum:MoveTo(hum.RootPart.Position) end
    setStatus("🛑 Seguimiento detenido.")
end
local function playEmote(name)
    local hum = getHumanoid(); if not hum then return end
    local ok = pcall(function() hum:PlayEmote(name) end)
    setStatus(ok and ("🎭 Emote: "..name) or ("❌ Emote no disponible: "..name))
end

local assetNameCache = {}
local function getAssetName(id)
    if assetNameCache[id] then return assetNameCache[id] end
    local ok, info = pcall(function() return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Asset) end)
    local name = (ok and info and info.Name) or ("Asset #" .. tostring(id))
    assetNameCache[id] = name; return name
end
local function getAppearanceString(hum)
    if not hum then return "apariencia desconocida" end
    local desc = hum:GetAppliedDescription()
    if not desc then return "sin descripción" end
    local items = {}
    if desc.Shirt and desc.Shirt > 0 then table.insert(items, "camisa: "..getAssetName(desc.Shirt)) end
    if desc.Pants and desc.Pants > 0 then table.insert(items, "pantalón: "..getAssetName(desc.Pants)) end
    local ok, accs = pcall(function() return desc:GetAccessories(true) end)
    if ok and accs then
        for _, acc in ipairs(accs) do
            if acc.AssetId and acc.AssetId > 0 then
                table.insert(items, "accesorio: "..getAssetName(acc.AssetId))
            end
        end
    end
    if #items == 0 then return "ropa básica" end
    return table.concat(items, ", ")
end
local function getWorldContext(maxDist)
    local char = player.Character
    if not char then return "No veo mi personaje." end
    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return "No tengo posición." end
    local lines = { "Mi posición: "..tostring(myRoot.Position), "Jugadores a mi alrededor:" }
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and other.Character then
            local otherRoot = other.Character:FindFirstChild("HumanoidRootPart")
            local otherHum = other.Character:FindFirstChildOfClass("Humanoid")
            if otherRoot and otherHum then
                local dist = (myRoot.Position - otherRoot.Position).Magnitude
                if dist <= (maxDist or 50) then
                    table.insert(lines, string.format("- %s a %.0f studs. Lleva: %s",
                        other.Name, dist, getAppearanceString(otherHum)))
                end
            end
        end
    end
    if #lines == 2 then table.insert(lines, "- Nadie cerca.") end
    return table.concat(lines, "\n")
end

local function loadHistory()
    if not (readfile and isfile) then return end
    local ok, data = pcall(function() if isfile(config.historyFile) then return readfile(config.historyFile) end end)
    if ok and data then
        local okD, decoded = pcall(HttpService.JSONDecode, HttpService, data)
        if okD and type(decoded) == "table" then
            state.history = decoded
            setStatus("🧠 Memoria cargada.")
        end
    end
end
local function saveHistory(manual)
    if not writefile then return end
    local ok = pcall(function() writefile(config.historyFile, HttpService:JSONEncode(state.history)) end)
    if ok and manual then setStatus("💾 Memoria guardada.") end
end
local function clearHistory()
    state.history = {}
    if delfile then pcall(function() delfile(config.historyFile) end) end
    setStatus("🗑️ Memoria borrada.")
end
local function getHistoryFor(userId) return state.history[userId] or {} end
local function addToHistory(userId, role, content)
    state.history[userId] = state.history[userId] or {}
    table.insert(state.history[userId], { role = role, content = content })
    while #state.history[userId] > config.maxHistoryPerPlayer * 2 do
        table.remove(state.history[userId], 1)
    end
    saveHistory(false)
end

local function askAI(prompt, speakerName, speakerId)
    local key = apiKeyBox.Text
    if key == "" then setStatus("⚠️ Falta API Key."); return end
    setStatus("⏳ Consultando Groq...")
    local messages = { { role = "system", content = config.systemPrompt } }
    for _, msg in ipairs(getHistoryFor(speakerId)) do table.insert(messages, msg) end
    table.insert(messages, { role = "user", content = prompt })
    local body = {
        model = config.model, messages = messages,
        max_completion_tokens = config.maxCompletionTokens,
    }
    local json = HttpService:JSONEncode(body)
    task.spawn(function()
        local ok, resp = pcall(function()
            return http_request({
                Url = "https://api.groq.com/openai/v1/chat/completions",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer " .. key },
                Body = json,
            })
        end)
        if ok and resp and resp.StatusCode == 200 then
            local okD, data = pcall(HttpService.JSONDecode, HttpService, resp.Body)
            if okD and data.choices and data.choices[1] then
                local msg = data.choices[1].message.content or "(sin contenido)"
                msg = string.gsub(msg, "\n+", " ")
                if #msg > 190 then msg = string.sub(msg, 1, 187).."..." end
                sendToChat("[" .. speakerName .. " → Mark] " .. msg)
                setStatus("✅ " .. msg)
                addToHistory(speakerId, "user", prompt)
                addToHistory(speakerId, "assistant", msg)
                return
            end
        end
        local code = resp and resp.StatusCode or "?"
        setStatus("❌ Error HTTP " .. tostring(code))
        if resp then warn("[Mark AI]", resp.Body) end
    end)
end
local function handleDirectCommand(cleanText, speakerName)
    local lower = string.lower(cleanText)
    local hum = getHumanoid(); if not hum then return false end
    if string.find(lower, "ven aquí") or string.find(lower, "ven acá") or string.find(lower, "^ven") then
        local speaker = Players:FindFirstChild(speakerName)
        if speaker and speaker.Character then
            local root = speaker.Character:FindFirstChild("HumanoidRootPart")
            if root then hum:MoveTo(root.Position); return true end
        end
    elseif string.find(lower, "sígueme") or string.find(lower, "sigueme") then
        followPlayer(speakerName); return true
    elseif string.find(lower, "baila") then playEmote("Dance"); return true
    elseif string.find(lower, "salta") then hum.Jump = true; return true
    elseif string.find(lower, "saluda") then playEmote("Wave"); return true
    elseif string.find(lower, "para") or string.find(lower, "detente") then
        stopFollowing(); return true
    end
    return false
end

local function initiateGreeting(target)
    local hum = getHumanoid(); if not hum then return end
    local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end
    hum:MoveTo(targetRoot.Position)
    setStatus("🚶 Acercándome a " .. target.Name .. " para saludar...")
    task.wait(1.5)
    local key = apiKeyBox.Text; if key == "" then return end
    local targetHum = target.Character:FindFirstChildOfClass("Humanoid")
    local appearance = getAppearanceString(targetHum)
    local prompt = string.format(
        "Vas a iniciar una conversación con %s. Su apariencia: %s. " ..
        "Genera un saludo corto, amigable y natural (máximo 1-2 oraciones) en español, " ..
        "como si lo acabaras de conocer. Si su apariencia tiene algo llamativo, puedes mencionarlo.",
        target.Name, appearance)
    local body = {
        model = config.model,
        messages = { { role = "system", content = config.systemPrompt },
                     { role = "user", content = prompt } },
        max_completion_tokens = 150,
    }
    local ok, resp = pcall(function()
        return http_request({
            Url = "https://api.groq.com/openai/v1/chat/completions",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. key },
            Body = HttpService:JSONEncode(body),
        })
    end)
    if ok and resp and resp.StatusCode == 200 then
        local okD, data = pcall(HttpService.JSONDecode, HttpService, resp.Body)
        if okD and data.choices and data.choices[1] then
            local msg = data.choices[1].message.content or ""
            msg = string.gsub(msg, "\n+", " ")
            if #msg > 190 then msg = string.sub(msg, 1, 187).."..." end
            sendToChat("[Mark → " .. target.Name .. "] " .. msg)
            setStatus("💬 Saludo autónomo: " .. msg)
            addToHistory(target.UserId, "assistant", msg)
        end
    else
        setStatus("❌ Error al generar saludo.")
    end
end

local function maybeGreetNearbyPlayer()
    if not state.autonomyActive then return false end
    local char = player.Character; if not char then return false end
    local myRoot = char:FindFirstChild("HumanoidRootPart"); if not myRoot then return false end
    local now = os.clock()
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and other.Character then
            local otherRoot = other.Character:FindFirstChild("HumanoidRootPart")
            if otherRoot then
                local dist = (myRoot.Position - otherRoot.Position).Magnitude
                if dist >= config.greetRangeMin and dist <= config.greetRangeMax then
                    local last = state.greetedPlayers[other.UserId]
                    if not last or (now - last) > config.greetCooldown then
                        state.greetedPlayers[other.UserId] = now
                        task.spawn(function() initiateGreeting(other) end)
                        return true
                    end
                end
            end
        end
    end
    return false
end

local AUTONOMY_PROMPT = [[
Eres el controlador de comportamiento de un personaje en Roblox.
Recibirás un contexto del mundo. Debes elegir UNA acción y devolverla
ÚNICAMENTE como un objeto JSON válido, sin texto adicional.
Acciones válidas:
- {"action":"walkToPlayer","target":"Nombre"}
- {"action":"followPlayer","target":"Nombre"}
- {"action":"stop"}
- {"action":"lookAt","target":"Nombre"}
- {"action":"emote","emote":"Wave"}
- {"action":"jump"}
Si no hay jugadores cerca, usa {"action":"jump"} o {"action":"emote","emote":"Wave"}.
]]

local function executeAutonomousAction(action)
    if type(action) ~= "table" or not action.action then return end
    if action.action == "walkToPlayer" and action.target then
        local target = Players:FindFirstChild(action.target)
        if target and target.Character then
            local root = target.Character:FindFirstChild("HumanoidRootPart")
            if root then walkTo(root.Position) end
        end
    elseif action.action == "followPlayer" and action.target then followPlayer(action.target)
    elseif action.action == "stop" then stopFollowing()
    elseif action.action == "lookAt" and action.target then
        local target = Players:FindFirstChild(action.target)
        if target and target.Character then
            local hum = getHumanoid()
            local root = target.Character:FindFirstChild("HumanoidRootPart")
            if hum and root and hum.RootPart then
                hum.RootPart.CFrame = hum.RootPart.CFrame:Lerp(
                    CFrame.lookAt(hum.RootPart.Position, root.Position), 0.5)
            end
        end
    elseif action.action == "emote" and action.emote then playEmote(action.emote)
    elseif action.action == "jump" then
        local hum = getHumanoid(); if hum then hum.Jump = true end
    end
end

local function startAutonomy()
    if state.autonomyConnection then return end
    state.autonomyActive = true
    setStatus("🤖 Autonomía activada.")
    state.autonomyConnection = task.spawn(function()
        while state.autonomyActive do
            task.wait(state.autonomyInterval)
            if not state.autonomyActive then break end
            if maybeGreetNearbyPlayer() then continue end
            local key = apiKeyBox.Text; if key == "" then continue end
            local context = getWorldContext(60)
            local body = {
                model = config.model,
                messages = { { role = "system", content = AUTONOMY_PROMPT },
                             { role = "user", content = "Contexto:\n" .. context } },
                max_completion_tokens = 80,
            }
            local ok, resp = pcall(function()
                return http_request({
                    Url = "https://api.groq.com/openai/v1/chat/completions",
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json",
                        ["Authorization"] = "Bearer " .. key },
                    Body = HttpService:JSONEncode(body),
                })
            end)
            if ok and resp and resp.StatusCode == 200 then
                local okD, data = pcall(HttpService.JSONDecode, HttpService, resp.Body)
                if okD and data.choices and data.choices[1] then
                    local okP, action = pcall(HttpService.JSONDecode, HttpService,
                        data.choices[1].message.content)
                    if okP and type(action) == "table" then
                        executeAutonomousAction(action)
                        setStatus("🤖 Acción: " .. (action.action or "?"))
                    end
                end
            end
        end
    end)
end
local function stopAutonomy()
    state.autonomyActive = false
    if state.autonomyConnection then
        pcall(function() task.cancel(state.autonomyConnection) end)
        state.autonomyConnection = nil
    end
    setStatus("🛑 Autonomía desactivada.")
end

local function isNearby(speakerId)
    if not config.proximityEnabled then return true end
    local other = Players:GetPlayerByUserId(speakerId)
    if not other or not other.Character then return false end
    local myChar = player.Character; if not myChar then return false end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    local otherRoot = other.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot or not otherRoot then return false end
    return (myRoot.Position - otherRoot.Position).Magnitude <= config.proximityDistance
end
local function hasTrigger(text)
    local lower = string.lower(text)
    for _, trig in config.triggers do
        local lt = string.lower(trig)
        if string.sub(lt, 1, 1) == "@" then
            if string.find(lower, lt, 1, true) then return true end
        else
            local escaped = string.gsub(lt, "([^%w])", "%%%1")
            if string.find(lower, "%f[%w]" .. escaped .. "%f[%W]") then return true end
        end
    end
    return false
end
local function stripTrigger(text)
    local lower = string.lower(text)
    for _, trig in config.triggers do
        local lt = string.lower(trig)
        local s = string.find(lower, lt, 1, true)
        if s then
            local cleaned = string.sub(text, 1, s - 1) .. string.sub(text, s + #trig)
            return (string.gsub(cleaned, "^%s+", ""))
        end
    end
    return text
end

local function onChatMessage(message)
    if not config.listening then return end
    local src = message.TextSource
    if not src or not src.UserId then return end
    if src.UserId == player.UserId then return end
    if state.processedMessages[message.MessageId] then return end
    state.processedMessages[message.MessageId] = true
    local text = message.Text or ""
    if not hasTrigger(text) then return end
    if not isNearby(src.UserId) then setStatus("⏭️ Fuera de rango."); return end
    local now = os.clock()
    if now - state.lastGlobalRequest < config.globalCooldown then
        setStatus("🛡️ Antispam global."); return
    end
    local lastUser = state.userCooldowns[src.UserId]
    if lastUser and (now - lastUser) < config.userCooldown then
        setStatus("🛡️ Antispam usuario: " .. src.Name); return
    end
    state.lastGlobalRequest = now
    state.userCooldowns[src.UserId] = now
    local clean = stripTrigger(text)
    if clean == "" then clean = "Hola, ¿me llamaste?" end
    if handleDirectCommand(clean, src.Name) then
        setStatus("⚡ Comando directo."); return
    end
    askAI(clean, src.Name, src.UserId)
end
local function hookChannel(ch)
    if ch:IsA("TextChannel") then ch.MessageReceived:Connect(onChatMessage) end
end
for _, ch in TextChatService:GetDescendants() do hookChannel(ch) end
TextChatService.DescendantAdded:Connect(hookChannel)

saveMemBtn.MouseButton1Click:Connect(function() saveHistory(true) end)
clearMemBtn.MouseButton1Click:Connect(clearHistory)

followBtn.MouseButton1Click:Connect(function()
    if followNameBox.Text ~= "" then followPlayer(followNameBox.Text)
    else setStatus("⚠️ Escribe nombre de jugador.") end
end)
stopFollowBtn.MouseButton1Click:Connect(stopFollowing)

for emoteName, btn in pairs(emoteBtns) do
    btn.MouseButton1Click:Connect(function() playEmote(emoteName) end)
end

autoBtn.MouseButton1Click:Connect(function()
    if state.autonomyActive then
        stopAutonomy()
        autoBtn.Text = "Autonomía: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
    else
        local n = tonumber(intervalBox.Text)
        if n and n >= 5 then state.autonomyInterval = n end
        startAutonomy()
        autoBtn.Text = "Autonomía: ON"
        autoBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
    end
end)

testBtn.MouseButton1Click:Connect(function()
    if testBox.Text == "" then setStatus("⚠️ Escribe prompt."); return end
    askAI(testBox.Text, player.Name, player.UserId)
end)

task.spawn(function()
    while gui.Parent do
        task.wait(60)
        state.processedMessages = {}
        for uid in pairs(state.userCooldowns) do
            if not Players:GetPlayerByUserId(uid) then
                state.userCooldowns[uid] = nil
            end
        end
    end
end)

loadHistory()
setStatus("✅ Mark AI listo. Modelo: " .. config.model)
print("✅ Script completo cargado, longitud:", #(debug and "ok" or "ok"))
