-- ZeusHub bootstrap loader.
-- Displays immediately, then downloads and starts the standalone build.

local MAIN_URL = "https://raw.githubusercontent.com/Blood8ound/zeushubstandalone/e5dd94f958d37cfeb9431c830594424eaa90cabe/zeushub"

local previous = _G.ZeusHubBootstrap
if type(previous) == "table" and previous.Stop then
    pcall(previous.Stop)
end

local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local Loader = { running = true, drawings = {} }
_G.ZeusHubBootstrap = Loader

local function make(kind, properties)
    local object = Drawing.new(kind)
    for key, value in pairs(properties) do
        pcall(function() object[key] = value end)
    end
    Loader.drawings[#Loader.drawings + 1] = object
    return object
end

local shade = make("Square", {
    Filled = true,
    Color = Color3.fromRGB(7, 8, 13),
    Transparency = 0.86,
    Visible = true,
})
local card = make("Square", {
    Filled = true,
    Color = Color3.fromRGB(18, 20, 30),
    Transparency = 1,
    Rounding = 12,
    Visible = true,
})
local border = make("Square", {
    Filled = false,
    Color = Color3.fromRGB(137, 126, 255),
    Transparency = 1,
    Thickness = 1,
    Rounding = 12,
    Visible = true,
})
local accent = make("Square", {
    Filled = true,
    Color = Color3.fromRGB(151, 126, 255),
    Transparency = 1,
    Rounding = 3,
    Visible = true,
})
local progressBack = make("Square", {
    Filled = true,
    Color = Color3.fromRGB(41, 44, 61),
    Transparency = 1,
    Rounding = 3,
    Visible = true,
})
local progress = make("Square", {
    Filled = true,
    Color = Color3.fromRGB(151, 126, 255),
    Transparency = 1,
    Rounding = 3,
    Visible = true,
})
local title = make("Text", {
    Text = "ZEUSHUB",
    Size = 24,
    Font = 2,
    Center = true,
    Outline = true,
    Color = Color3.fromRGB(240, 240, 255),
    Transparency = 1,
    Visible = true,
})
local statusText = make("Text", {
    Text = "Preparing",
    Size = 15,
    Font = 0,
    Center = true,
    Outline = true,
    Color = Color3.fromRGB(198, 200, 218),
    Transparency = 1,
    Visible = true,
})
local detailText = make("Text", {
    Text = "Standalone UI",
    Size = 12,
    Font = 0,
    Center = true,
    Outline = true,
    Color = Color3.fromRGB(128, 132, 154),
    Transparency = 1,
    Visible = true,
})

local stage = "Preparing"
local detail = "Standalone UI"
local started = tick()
local progressShown = 0.03
local progressTarget = 0.08
local connection

local function shorten(value, limit)
    value = tostring(value or "Unknown error"):gsub("[\r\n]+", " ")
    if #value > limit then return value:sub(1, limit - 3) .. "..." end
    return value
end

local function setStage(nextStage, nextDetail, nextProgress)
    stage = nextStage
    detail = nextDetail or detail
    if nextProgress then progressTarget = math.max(0, math.min(1, nextProgress)) end
end

function Loader.Stop()
    if not Loader.running then return end
    Loader.running = false
    if connection then pcall(function() connection:Disconnect() end) end
    for i = 1, #Loader.drawings do
        pcall(function() Loader.drawings[i]:Remove() end)
    end
    Loader.drawings = {}
    if _G.ZeusHubBootstrap == Loader then _G.ZeusHubBootstrap = nil end
end

connection = RunService.RenderStepped:Connect(function(dt)
    if not Loader.running then return end

    Camera = workspace.CurrentCamera or Camera
    local viewport = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
    local width, height = 390, 190
    local x = math.floor((viewport.X - width) * 0.5)
    local y = math.floor((viewport.Y - height) * 0.5)
    local elapsed = tick() - started
    local dots = string.rep(".", math.floor(elapsed * 2.5) % 4)
    local blend = math.min((dt or 0.016) * 7, 1)
    progressShown = progressShown + (progressTarget - progressShown) * blend
    local fillWidth = math.max(4, math.floor((width - 56) * progressShown))

    shade.Position = Vector2.new(0, 0)
    shade.Size = Vector2.new(viewport.X, viewport.Y)
    card.Position = Vector2.new(x, y)
    card.Size = Vector2.new(width, height)
    border.Position = Vector2.new(x, y)
    border.Size = Vector2.new(width, height)
    accent.Position = Vector2.new(x + 28, y + 25)
    accent.Size = Vector2.new(width - 56, 3)
    progressBack.Position = Vector2.new(x + 28, y + 139)
    progressBack.Size = Vector2.new(width - 56, 6)
    progress.Position = Vector2.new(x + 28, y + 139)
    progress.Size = Vector2.new(fillWidth, 6)
    title.Position = Vector2.new(x + width * 0.5, y + 51)
    statusText.Text = stage .. dots
    statusText.Position = Vector2.new(x + width * 0.5, y + 94)
    detailText.Text = detail
    detailText.Position = Vector2.new(x + width * 0.5, y + 116)
end)

task.spawn(function()
    task.wait(0.12)
    setStage("Downloading ZeusHub", "Fetching standalone build", 0.18)
    task.wait(0.35)

    local okDownload, source = pcall(httpget, MAIN_URL)
    if not okDownload or type(source) ~= "string" or #source < 1000 then
        setStage("Download failed", shorten(source, 54), 1)
        pcall(function() notify("ZeusHub", "Download failed", 5) end)
        task.wait(7)
        Loader.Stop()
        return
    end

    setStage("Download complete", tostring(#source) .. " bytes received", 0.58)
    task.wait(0.22)
    setStage("Compiling ZeusHub", "Preparing bundled UI", 0.72)
    task.wait(0.28)
    local chunk, compileError = loadstring(source)
    if not chunk then
        setStage("Compile failed", shorten(compileError, 54), 1)
        pcall(function() notify("ZeusHub", "Compile failed", 5) end)
        task.wait(7)
        Loader.Stop()
        return
    end

    setStage("Starting ZeusHub", "Initializing bundled UI", 0.9)
    task.wait(0.3)
    local okRun, runError = pcall(chunk)
    if not okRun then
        setStage("Startup failed", shorten(runError, 54), 1)
        pcall(function() notify("ZeusHub", "Startup failed", 5) end)
        task.wait(7)
        Loader.Stop()
        return
    end

    setStage("Ready", "Press H to open the menu", 1)
    task.wait(0.85)
    Loader.Stop()
end)
