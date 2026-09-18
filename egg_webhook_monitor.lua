-- Steal an Egg — Discord Egg Monitor GUI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Assets = require(ReplicatedStorage.Data.Assets)
local Areas = require(ReplicatedStorage.Data.Areas)
local AssetEarnings = require(ReplicatedStorage.Shared.Util.AssetEarnings)
local EggRecords = require(ReplicatedStorage.Shared.Util.EggRecords)

local httpRequest = (syn and syn.request) or http_request or request
assert(type(httpRequest) == "function", "Your executor does not support HTTP requests.")

local state = getgenv()
local WEBHOOK_CONFIG_FILE = "egg_webhook_monitor_config.json"

local function loadSavedConfig()
    if type(readfile) ~= "function" then
        return {}
    end

    local readOK, raw = pcall(readfile, WEBHOOK_CONFIG_FILE)
    if not readOK then
        return {}
    end

    local decodeOK, config = pcall(HttpService.JSONDecode, HttpService, raw)
    if decodeOK and type(config) == "table" then
        return config
    end

    return {}
end

local function saveConfig(webhook, uiKeyName)
    if type(writefile) ~= "function" then
        return false
    end

    local encodeOK, encoded = pcall(HttpService.JSONEncode, HttpService, {
        webhook = webhook,
        uiToggleKey = uiKeyName,
    })

    if not encodeOK then
        return false
    end

    return pcall(writefile, WEBHOOK_CONFIG_FILE, encoded)
end

local savedConfig = loadSavedConfig()
local savedWebhook = state.EggWebhookLastURL or savedConfig.webhook or ""

local function keyCodeFromName(name)
    local keyCode = type(name) == "string" and Enum.KeyCode[name]
    return keyCode and keyCode ~= Enum.KeyCode.Unknown and keyCode or Enum.KeyCode.F8
end

local uiToggleKey = keyCodeFromName(state.EggWebhookUiToggleKey or savedConfig.uiToggleKey)
state.EggWebhookUiToggleKey = uiToggleKey.Name

-- Clear a prior copy when re-executed.
for _, connection in ipairs(state.EggWebhookGuiConnections or {}) do
    pcall(function()
        connection:Disconnect()
    end)
end

state.EggWebhookGuiConnections = {}
local connections = state.EggWebhookGuiConnections

local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
local oldGui = guiParent:FindFirstChild("EggWebhookMonitor")

if oldGui then
    oldGui:Destroy()
end

local function create(className, properties, parent)
    local object = Instance.new(className)

    for property, value in pairs(properties) do
        object[property] = value
    end

    object.Parent = parent
    return object
end

-- GUI
local gui = create("ScreenGui", {
    Name = "EggWebhookMonitor",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999999,
}, guiParent)

local panel = create("Frame", {
    Size = UDim2.fromOffset(820, 260),
    Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(25, 28, 34),
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
    Draggable = true,
}, gui)

create("UICorner", {
    CornerRadius = UDim.new(0, 12),
}, panel)

create("UIStroke", {
    Color = Color3.fromRGB(70, 75, 88),
    Thickness = 1,
}, panel)

local title = create("TextLabel", {
    Size = UDim2.new(1, -32, 0, 30),
    Position = UDim2.fromOffset(16, 14),
    BackgroundTransparency = 1,
    Text = "Egg Collection Monitor",
    Font = Enum.Font.GothamBold,
    TextSize = 19,
    TextColor3 = Color3.fromRGB(245, 245, 245),
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)

local webhookBox = create("TextBox", {
    Size = UDim2.new(1, -32, 0, 42),
    Position = UDim2.fromOffset(16, 58),
    BackgroundColor3 = Color3.fromRGB(40, 44, 53),
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    PlaceholderText = "Discord webhook URL",
    PlaceholderColor3 = Color3.fromRGB(150, 155, 165),
    Text = savedWebhook,
    TextColor3 = Color3.fromRGB(245, 245, 245),
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)

create("UICorner", {
    CornerRadius = UDim.new(0, 8),
}, webhookBox)

create("UIPadding", {
    PaddingLeft = UDim.new(0, 12),
    PaddingRight = UDim.new(0, 12),
}, webhookBox)

local keybindButton = create("TextButton", {
    Size = UDim2.fromOffset(210, 32),
    Position = UDim2.fromOffset(16, 112),
    BackgroundColor3 = Color3.fromRGB(54, 59, 70),
    BorderSizePixel = 0,
    Text = "UI key: " .. uiToggleKey.Name,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(245, 245, 245),
}, panel)

create("UICorner", {
    CornerRadius = UDim.new(0, 8),
}, keybindButton)

local keybindHint = create("TextLabel", {
    Size = UDim2.new(1, -258, 0, 32),
    Position = UDim2.fromOffset(242, 112),
    BackgroundTransparency = 1,
    Text = "Click to choose the key that minimizes/restores the UI.",
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(175, 180, 190),
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)

local toggle = create("TextButton", {
    Size = UDim2.new(1, -32, 0, 44),
    Position = UDim2.fromOffset(16, 156),
    BackgroundColor3 = Color3.fromRGB(105, 50, 50),
    BorderSizePixel = 0,
    Text = "Monitoring: OFF",
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = Color3.fromRGB(255, 255, 255),
}, panel)

create("UICorner", {
    CornerRadius = UDim.new(0, 8),
}, toggle)

local status = create("TextLabel", {
    Size = UDim2.new(1, -32, 0, 24),
    Position = UDim2.fromOffset(16, 213),
    BackgroundTransparency = 1,
    Text = "Paste a webhook URL, then enable monitoring.",
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(175, 180, 190),
    TextXAlignment = Enum.TextXAlignment.Left,
}, panel)

local minimizedStatus = create("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "Monitoring: OFF",
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Visible = false,
}, panel)

-- State and display helpers
local enabled = false
local seenEggs = {}
local minimized = false
local choosingKey = false
local expandedPanelSize = UDim2.fromOffset(820, 260)
local minimizedPanelSize = UDim2.fromOffset(180, 42)

local function setStatus(text, color)
    status.Text = text
    status.TextColor3 = color or Color3.fromRGB(175, 180, 190)
end

local function updateToggle()
    toggle.Text = enabled and "Monitoring: ON" or "Monitoring: OFF"
    toggle.BackgroundColor3 = enabled
        and Color3.fromRGB(35, 170, 90)
        or Color3.fromRGB(105, 50, 50)
    minimizedStatus.Text = enabled and "Monitoring: ON" or "Monitoring: OFF"
    minimizedStatus.TextColor3 = enabled
        and Color3.fromRGB(90, 220, 130)
        or Color3.fromRGB(235, 120, 120)
end

local function setMinimized(value)
    minimized = value
    panel.Size = minimized and minimizedPanelSize or expandedPanelSize
    title.Visible = not minimized
    webhookBox.Visible = not minimized
    keybindButton.Visible = not minimized
    keybindHint.Visible = not minimized
    toggle.Visible = not minimized
    status.Visible = not minimized
    minimizedStatus.Visible = minimized

    if not minimized and not choosingKey then
        keybindButton.Text = "UI key: " .. uiToggleKey.Name
    end
end

local function validWebhook(url)
    return url:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+/?$") ~= nil
        or url:match("^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+/?$") ~= nil
end

local function mutationList(value)
    if type(value) == "table" then
        return value
    end

    local result = {}

    for mutation in tostring(value or ""):gmatch("[^,%s]+") do
        table.insert(result, mutation)
    end

    return result
end

local function mutationText(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    return text ~= "" and text or "None"
end

local function formatRate(value)
    local suffixes = {
        { 1e15, "Qa" },
        { 1e12, "T" },
        { 1e9, "B" },
        { 1e6, "M" },
        { 1e3, "K" },
    }

    for _, entry in ipairs(suffixes) do
        if value >= entry[1] then
            return string.format("%.2f%s/s", value / entry[1], entry[2])
        end
    end

    return string.format("%.2f/s", value)
end

local imageCache = {}
local FANDOM_API = "https://stealanegg.fandom.com/api.php?action=query&format=json&prop=imageinfo&iiprop=url&titles="

local function responseSucceeded(response)
    return type(response) == "table"
        and type(response.StatusCode) == "number"
        and response.StatusCode >= 200
        and response.StatusCode < 300
end

-- Download an image first and upload it to Discord as an attachment.  Discord
-- then displays its own file rather than trying to hotlink a third-party URL.
local function fetchImage(url)
    local success, response = pcall(httpRequest, {
        Url = url,
        Method = "GET",
        Headers = {
            ["User-Agent"] = "EggWebhookMonitor/1.0",
        },
    })

    if not success or not responseSucceeded(response) or type(response.Body) ~= "string" or #response.Body == 0 then
        return nil
    end

    local headers = response.Headers or {}
    local contentType = headers["Content-Type"] or headers["content-type"] or "image/png"

    if type(contentType) ~= "string" or not contentType:lower():match("^image/") then
        contentType = "image/png"
    end

    local mediaType = contentType:lower():match("^[^;]+")
    local extensions = {
        ["image/png"] = "png",
        ["image/jpeg"] = "jpg",
        ["image/jpg"] = "jpg",
        ["image/webp"] = "webp",
        ["image/gif"] = "gif",
    }

    return {
        bytes = response.Body,
        contentType = contentType,
        filename = "egg." .. (extensions[mediaType] or "png"),
    }
end

-- The Eggs wiki stores files as "<pet name> Egg.png", for example
-- File:Duckling Egg.png.  Ask its MediaWiki API for the current direct image
-- URL rather than guessing the static.wikia.nocookie.net path.
local function fandomEggImage(eggDisplayName)
    local cacheKey = tostring(eggDisplayName or "")

    if imageCache[cacheKey] ~= nil then
        return imageCache[cacheKey] or nil
    end

    local title = "File:" .. cacheKey .. ".png"
    local success, response = pcall(httpRequest, {
        Url = FANDOM_API .. HttpService:UrlEncode(title),
        Method = "GET",
        Headers = {
            ["User-Agent"] = "EggWebhookMonitor/1.0",
        },
    })

    local image

    if success and responseSucceeded(response) then
        local decodedOK, decoded = pcall(HttpService.JSONDecode, HttpService, response.Body)
        local pages = decodedOK and decoded and decoded.query and decoded.query.pages

        if type(pages) == "table" then
            for _, page in pairs(pages) do
                local imageInfo = type(page) == "table" and page.imageinfo and page.imageinfo[1]
                local imageUrl = type(imageInfo) == "table" and imageInfo.url

                if type(imageUrl) == "string" and imageUrl:match("^https://") then
                    image = fetchImage(imageUrl)
                    break
                end
            end
        end
    end

    imageCache[cacheKey] = image or false
    return image
end

-- The pet category is looked up in each area's official egg DropTable.
-- Example: Duckling belongs to Lake, so the egg is reported as "Lake Egg".
local function tableContains(value, needle, visited)
    if value == needle then
        return true
    end

    if type(value) ~= "table" then
        return false
    end

    visited = visited or {}
    if visited[value] then
        return false
    end
    visited[value] = true

    for key, child in pairs(value) do
        if key == needle or tableContains(child, needle, visited) then
            return true
        end
    end

    return false
end

local function areaForEgg(category)
    local matches = {}

    for _, area in pairs(Areas.Directory) do
        if tableContains(area.DropTable, category) then
            table.insert(matches, area.DisplayName or area._id)
        end
    end

    table.sort(matches)
    return #matches > 0 and table.concat(matches, ", ") or "Unknown"
end

-- EggRecords.WeightKgForScale is the game's exact Backpack weight formula.
local function backpackWeight(data, asset)
    local scale = tonumber(data.AssetScale or data.Scale)

    if scale then
        local success, weight = pcall(EggRecords.WeightKgForScale, asset._id, scale)
        if success then
            return weight
        end
    end

    for _, key in ipairs({ "Weight", "AssetWeight", "HatchWeight", "PetWeight" }) do
        local directWeight = tonumber(data[key])
        if directWeight then
            return directWeight
        end
    end

    return nil
end

-- Return the current player's EggInventory table.  Profiles for other players
-- can also exist in memory, so match it against UUIDs shown in GrowingEggs.
local function currentEggInventory(newEggUid)
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    local growingEggs = playerGui and playerGui:FindFirstChild("GrowingEggs")
    local frame = growingEggs and growingEggs:FindFirstChild("Frame")
    local list = frame and frame:FindFirstChild("ScrollingFrame")
    local placedUids = {}

    if list then
        for _, item in ipairs(list:GetChildren()) do
            if item:IsA("GuiObject") and #item.Name == 32 and item.Name:match("^[%x]+$") then
                placedUids[item.Name] = true
            end
        end
    end

    local gcOK, objects = pcall(getgc, true)
    if not gcOK or type(objects) ~= "table" then
        return nil
    end

    local bestInventory
    local bestScore = 0

    for _, object in ipairs(objects) do
        if type(object) == "table" then
            local inventory = rawget(object, "EggInventory")

            if type(inventory) == "table" then
                local score = newEggUid and rawget(inventory, newEggUid) and 10000 or 0

                for uid in pairs(placedUids) do
                    if rawget(inventory, uid) then
                        score += 1
                    end
                end

                if score > bestScore then
                    bestInventory = inventory
                    bestScore = score
                end
            end
        end
    end

    return bestInventory
end

-- Eggs that have been placed down have a Placement record.  The actual egg
-- inventory consists only of the records that do not have one.
local function eggInventory(newEggUid)
    local inventory = currentEggInventory(newEggUid)

    if inventory then
        local count = 0

        for _, egg in pairs(inventory) do
            if type(egg) == "table" and egg.Placement == nil then
                count += 1
            end
        end

        -- The Tool may arrive one client frame before the profile record.  Count
        -- that newly collected egg once, without including any placed eggs.
        if newEggUid and rawget(inventory, newEggUid) == nil then
            count += 1
        end

        return string.format("%d egg%s", count, count == 1 and "" or "s")
    end

    -- Conservative fallback if the Egg UI has not loaded yet: only count eggs,
    -- never pets or the pet-inventory capacity.
    local count = 0
    for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and item:GetAttribute("ItemType") == "AssetEgg" then
                    count += 1
                end
            end
        end
    end

    return string.format("%d egg%s", count, count == 1 and "" or "s")
end

local function postJson(url, payload)
    return pcall(httpRequest, {
        Url = url,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
        },
        Body = HttpService:JSONEncode(payload),
    })
end

local function sendWebhook(webhook, payload, image)
    if not image then
        return postJson(webhook, payload)
    end

    local boundary = "EggMonitor" .. HttpService:GenerateGUID(false):gsub("%-", "")
    payload.embeds[1].thumbnail = {
        url = "attachment://" .. image.filename,
    }
    payload.attachments = {
        {
            id = 0,
            filename = image.filename,
        },
    }

    local lineBreak = "\r\n"
    local body = "--" .. boundary .. lineBreak
        .. "Content-Disposition: form-data; name=\"payload_json\"" .. lineBreak
        .. "Content-Type: application/json" .. lineBreak .. lineBreak
        .. HttpService:JSONEncode(payload) .. lineBreak
        .. "--" .. boundary .. lineBreak
        .. "Content-Disposition: form-data; name=\"files[0]\"; filename=\"" .. image.filename .. "\"" .. lineBreak
        .. "Content-Type: " .. image.contentType .. lineBreak .. lineBreak
        .. image.bytes .. lineBreak
        .. "--" .. boundary .. "--" .. lineBreak

    return pcall(httpRequest, {
        Url = webhook,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
        },
        Body = body,
    })
end

local function notify(tool)
    if not enabled then
        return
    end

    local data = tool:GetAttributes()

    if data.ItemType ~= "AssetEgg" or not data.UID or seenEggs[data.UID] then
        return
    end

    local category = data.AssetCategory
    local asset = category and Assets.Directory[category]

    if not asset then
        return
    end

    local webhook = webhookBox.Text:match("^%s*(.-)%s*$")

    if not validWebhook(webhook) then
        setStatus("Enter a valid Discord webhook URL.", Color3.fromRGB(235, 90, 90))
        return
    end

    -- Mark it before image/network work. The Tool can be seen in both the
    -- Backpack and Character during collection, which otherwise sends twice.
    seenEggs[data.UID] = true

    local eggData = asset.Egg or {}
    local areaName = areaForEgg(category)
    local eggName = areaName ~= "Unknown" and areaName .. " Egg" or tool.Name
    local petName = asset.DisplayName or category
    local eggWeight = backpackWeight(data, asset)
    local rarity = asset.Rarity or {}
    local rarityName = rarity.DisplayName or rarity._id or "Unknown"

    local earningsOK, earnings = pcall(AssetEarnings.RatePerSecond, {
        Category = category,
        Scale = data.AssetScale or data.Scale or 1,
        Mutations = mutationList(data.Mutations),
    })

    local payload = {
        username = "Egg Collection Monitor",
        allowed_mentions = {
            parse = {},
        },
        embeds = {{
            title = "Egg collected",
            color = 0x32B45E,
            fields = {
                {
                    name = "Egg",
                    value = eggName,
                    inline = true,
                },
                {
                    name = "Hatches into",
                    value = petName,
                    inline = true,
                },
                {
                    name = "Backpack weight",
                    value = eggWeight and string.format("%.2f kg", eggWeight) or "Unknown",
                    inline = true,
                },
                {
                    name = "Money per second",
                    value = earningsOK and formatRate(earnings) or "Unavailable",
                    inline = true,
                },
                {
                    name = "Mutations",
                    value = mutationText(data.Mutations),
                    inline = true,
                },
                {
                    name = "Rarity",
                    value = rarityName,
                    inline = true,
                },
                {
                    name = "Area",
                    value = areaName,
                    inline = true,
                },
                {
                    name = "Egg inventory",
                    value = eggInventory(data.UID),
                    inline = true,
                },
                {
                    name = "Account username",
                    value = player.Name,
                    inline = true,
                },
            },
        }},
    }

    task.spawn(function()
        -- Use the matching image from the Eggs wiki.  It is uploaded with the
        -- message, so Discord never has to fetch a hotlinked external image.
        local wikiEggName = eggData.DisplayName or (petName .. " Egg")
        local image = fandomEggImage(wikiEggName)
        local success, response = sendWebhook(webhook, payload, image)

        if success and responseSucceeded(response) then
            if image then
                setStatus("Sent with wiki egg image: " .. eggName, Color3.fromRGB(90, 220, 130))
            else
                setStatus("Sent, but this egg has no matching wiki image.", Color3.fromRGB(240, 185, 75))
            end
        else
            setStatus("Webhook request failed.", Color3.fromRGB(235, 90, 90))
            warn(response)
        end
    end)
end

local function watch(container)
    table.insert(connections, container.ChildAdded:Connect(function(child)
        if not child:IsA("Tool") then
            return
        end

        -- Run on the next frame so the Tool's attributes are available,
        -- without adding a visible delay before the webhook request.
        task.defer(function()
            if child.Parent then
                notify(child)
            end
        end)
    end))
end

watch(player:WaitForChild("Backpack"))

if player.Character then
    watch(player.Character)
end

table.insert(connections, player.CharacterAdded:Connect(watch))

table.insert(connections, webhookBox.FocusLost:Connect(function()
    state.EggWebhookLastURL = webhookBox.Text
    if saveConfig(webhookBox.Text, uiToggleKey.Name) then
        setStatus("Webhook URL saved locally.", Color3.fromRGB(90, 220, 130))
    else
        setStatus("Webhook ready; local saving is unavailable in this executor.", Color3.fromRGB(175, 180, 190))
    end
end))

table.insert(connections, keybindButton.MouseButton1Click:Connect(function()
    if choosingKey then
        return
    end

    choosingKey = true
    keybindButton.Text = "Press a keyboard key..."
    keybindHint.Text = "Press Esc to cancel. The chosen key is saved locally."
    setStatus("Waiting for a UI toggle key.", Color3.fromRGB(175, 180, 190))
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode == Enum.KeyCode.Unknown then
        return
    end

    if choosingKey then
        choosingKey = false

        if input.KeyCode == Enum.KeyCode.Escape then
            keybindButton.Text = "UI key: " .. uiToggleKey.Name
            keybindHint.Text = "Click to choose the key that minimizes/restores the UI."
            setStatus("Keybind selection cancelled.", Color3.fromRGB(175, 180, 190))
            return
        end

        uiToggleKey = input.KeyCode
        state.EggWebhookUiToggleKey = uiToggleKey.Name
        keybindButton.Text = "UI key: " .. uiToggleKey.Name
        keybindHint.Text = "Click to choose the key that minimizes/restores the UI."

        if saveConfig(webhookBox.Text, uiToggleKey.Name) then
            setStatus("UI key " .. uiToggleKey.Name .. " saved locally.", Color3.fromRGB(90, 220, 130))
        else
            setStatus("UI key set; local saving is unavailable in this executor.", Color3.fromRGB(175, 180, 190))
        end

        return
    end

    if input.KeyCode == uiToggleKey then
        setMinimized(not minimized)
    end
end))

table.insert(connections, toggle.MouseButton1Click:Connect(function()
    local webhook = webhookBox.Text:match("^%s*(.-)%s*$")

    if not enabled and not validWebhook(webhook) then
        setStatus("Enter a valid Discord webhook URL first.", Color3.fromRGB(235, 90, 90))
        return
    end

    state.EggWebhookLastURL = webhook
    saveConfig(webhook, uiToggleKey.Name)
    enabled = not enabled
    updateToggle()

    setStatus(
        enabled and "Monitoring new egg collections." or "Monitoring paused.",
        enabled and Color3.fromRGB(90, 220, 130) or Color3.fromRGB(175, 180, 190)
    )
end))

updateToggle()
setMinimized(false)
