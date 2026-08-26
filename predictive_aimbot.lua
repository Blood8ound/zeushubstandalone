-- ZeusHub experimental predictive aimbot.
-- Kept separate from the main hub while weapon prediction is calibrated.
-- Hold right mouse to aim. Stop with: _G.FallenSurvivalAimbot.Stop()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local previous = _G.FallenSurvivalAimbot
if type(previous) == "table" and previous.Stop then
    pcall(previous.Stop)
end
_G.FallenSurvivalAimbot = nil

local Aim = {
    running = true,
    enabled = true,
    prediction = true,
    verticalPrediction = true,
    pingCompensation = true,
    visibilityCheck = true,
    teamCheck = true,
    drawFov = true,
    showPredictionLine = true,
    leadScale = 1,
    hardLock = true,
    stickyTarget = true,
    lockedUserId = nil,
    fov = 220,
    maxDistance = 1800,
    smoothing = 10,
    aimPart = "Head",
    speedScale = 1,
    gravityScale = 1,
    bulletSpeed = 1000,
    bulletGravity = 1,
    weaponName = "Unknown",
    ballisticReady = false,
    nextBallisticScan = 0,
    targets = {},
    velocities = {},
    connection = nil,
    fovCircle = nil,
}
_G.FallenSurvivalAimbot = Aim

local AIM_GRAVITY = 196.2
local AimToolInfo = _G.FallenSurvivalAimToolInfoCache
if type(AimToolInfo) ~= "table" then
    pcall(function()
        local modules = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
        local toolModule = modules and modules:FindFirstChild("ToolInfo")
        if not toolModule then return end

        local source = decompile(toolModule)
        if type(source) ~= "string" or #source < 1000 then return end
        local returnName = source:match("return%s+([%a_][%w_]*)%s*$")
        if not returnName then return end

        local captureName = "FallenSurvivalAimToolInfoCapture"
        source = source:gsub(
            "return%s+" .. returnName .. "%s*$",
            "_G." .. captureName .. " = " .. returnName
        )
        local chunk = loadstring(source)
        if not chunk then return end
        chunk()

        local captured = _G[captureName]
        _G[captureName] = nil
        if type(captured) == "table" then
            AimToolInfo = captured
            _G.FallenSurvivalAimToolInfoCache = captured
        end
    end)
end

local function aimReadVelocity(root)
    local velocity = Vector3.new(0, 0, 0)
    pcall(function() velocity = root.AssemblyLinearVelocity end)
    if velocity.Magnitude <= 0 then
        pcall(function() velocity = root.Velocity end)
    end
    if velocity.Magnitude > 350 then
        velocity = velocity.Unit * 350
    end
    return velocity
end

function Aim.RefreshBallistics(force)
    local now = tick()
    if not force and now < Aim.nextBallisticScan then
        return Aim.ballisticReady
    end
    Aim.nextBallisticScan = now + 1

    local char = lp.Character
    if not char or type(AimToolInfo) ~= "table" then
        Aim.ballisticReady = false
        return false
    end

    local foundName, foundBullet
    local function inspect(container)
        if not container or foundBullet then return end
        local ok, children = pcall(function() return container:GetChildren() end)
        if not ok then return end
        for _, child in ipairs(children) do
            local info = AimToolInfo[child.Name]
            local bullet = type(info) == "table" and info.Bullet
            if type(bullet) == "table"
                and tonumber(bullet.Speed)
                and tonumber(bullet.Gravity) then
                foundName = child.Name
                foundBullet = bullet
                return
            end
        end
    end

    inspect(char)
    pcall(function() inspect(Workspace.CurrentCamera) end)

    if not foundBullet then
        Aim.ballisticReady = false
        return false
    end

    Aim.weaponName = foundName
    Aim.bulletSpeed = math.max(tonumber(foundBullet.Speed) or 1000, 1)
    Aim.bulletGravity = tonumber(foundBullet.Gravity) or 1
    Aim.ballisticReady = true
    return true
end

local function aimPredict(origin, position, velocity)
    if not Aim.prediction or not Aim.RefreshBallistics(false) then
        return position, 0
    end

    local speed = math.max(Aim.bulletSpeed * Aim.speedScale, 1)
    local gravity = Aim.bulletGravity * Aim.gravityScale
    local leadScale = math.max(tonumber(Aim.leadScale) or 1, 0)
    if not Aim.verticalPrediction then
        velocity = Vector3.new(velocity.X, 0, velocity.Z)
    end

    local latency = 0
    if Aim.pingCompensation then
        pcall(function()
            latency = math.min(math.max((tonumber(GetPingValue()) or 0) / 2000, 0), 0.25)
        end)
    end

    local delayed = position + velocity * latency * leadScale
    local flightTime = (delayed - origin).Magnitude / speed
    for _ = 1, 5 do
        local compensated = delayed
            + velocity * flightTime * leadScale
            + Vector3.new(0, 0.5 * AIM_GRAVITY * gravity * flightTime * flightTime, 0)
        local nextTime = (compensated - origin).Magnitude / speed
        if math.abs(nextTime - flightTime) < 0.0005 then
            flightTime = nextTime
            break
        end
        flightTime = math.min(nextTime, 8)
    end

    if flightTime ~= flightTime or flightTime < 0 or flightTime > 8 then
        return position, 0
    end

    return delayed
        + velocity * flightTime * leadScale
        + Vector3.new(0, 0.5 * AIM_GRAVITY * gravity * flightTime * flightTime, 0),
        flightTime
end

local aimRayParams
pcall(function()
    aimRayParams = RaycastParams.new()
    aimRayParams.FilterType = Enum.RaycastFilterType.Exclude
    aimRayParams.IgnoreWater = true
end)

local function aimVisible(origin, targetPosition, character)
    if not Aim.visibilityCheck or not aimRayParams then return true end
    local visible = true
    pcall(function()
        aimRayParams.FilterDescendantsInstances = lp.Character and { lp.Character } or {}
        local hit = Workspace:Raycast(origin, targetPosition - origin, aimRayParams)
        visible = not hit
            or not hit.Instance
            or hit.Instance:IsDescendantOf(character)
    end)
    return visible
end

local function aimCollectTargets()
    local out = {}
    local localId = tonumber(lp.UserId)
    local localTeam
    pcall(function() localTeam = lp.Team and lp.Team.Name end)

    for _, player in ipairs(Players:GetPlayers()) do
        local userId
        pcall(function() userId = tonumber(player.UserId) end)
        if userId and userId ~= localId then
            local character, humanoid, head, root, teamName
            pcall(function()
                character = player.Character
                humanoid = character and character:FindFirstChildOfClass("Humanoid")
                head = character and character:FindFirstChild("Head")
                root = character and character:FindFirstChild("HumanoidRootPart")
                teamName = player.Team and player.Team.Name
            end)
            if character and humanoid and head and root
                and (not Aim.teamCheck or not localTeam or teamName ~= localTeam) then
                out[#out + 1] = {
                    userId = userId,
                    player = player,
                    character = character,
                    humanoid = humanoid,
                    head = head,
                    root = root,
                }
            end
        end
    end
    Aim.targets = out
end

Aim.fovCircle = Drawing.new("Circle")
Aim.fovCircle.Visible = false
Aim.fovCircle.Filled = false
Aim.fovCircle.Thickness = 1
Aim.fovCircle.NumSides = 64
Aim.fovCircle.Radius = Aim.fov
Aim.fovCircle.Color = Color3.fromRGB(135, 220, 125)
Aim.fovCircle.Transparency = 0.8

Aim.predictionLine = Drawing.new("Line")
Aim.predictionLine.Visible = false
Aim.predictionLine.Thickness = 2
Aim.predictionLine.Color = Color3.fromRGB(255, 205, 90)
Aim.predictionLine.Transparency = 0.85

Aim.collectThread = task.spawn(function()
    while Aim.running do
        if Aim.enabled then
            pcall(aimCollectTargets)
            Aim.RefreshBallistics(false)
        else
            Aim.targets = {}
        end
        task.wait(0.35)
    end
end)

Aim.connection = RunService.RenderStepped:Connect(function(dt)
    local camera = Workspace.CurrentCamera
    if not camera then return end

    local center = camera.ViewportSize * 0.5
    if Aim.predictionLine then Aim.predictionLine.Visible = false end
    if Aim.fovCircle then
        Aim.fovCircle.Position = center
        Aim.fovCircle.Radius = Aim.fov
        Aim.fovCircle.Visible = Aim.enabled and Aim.drawFov
    end

    if not Aim.enabled then
        Aim.lockedUserId = nil
        return
    end
    local held = false
    pcall(function() held = ismouse2pressed() end)
    if not held then
        Aim.lockedUserId = nil
        return
    end
    if not Aim.stickyTarget then Aim.lockedUserId = nil end

    local origin = camera.Position
    local localRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local closest, closestPosition, closestScore

    for _, target in ipairs(Aim.targets) do
        local ok, health = pcall(function() return target.humanoid.Health end)
        if ok and health and health > 0 then
            local part = Aim.aimPart == "Torso" and target.root or target.head
            local partPosition, rootPosition
            pcall(function()
                partPosition = part.Position
                rootPosition = target.root.Position
            end)
            if partPosition and rootPosition then
                local distance = localRoot
                    and (localRoot.Position - rootPosition).Magnitude
                    or (origin - rootPosition).Magnitude
                if distance <= Aim.maxDistance then
                    local isLocked = Aim.stickyTarget and Aim.lockedUserId == target.userId
                    if isLocked then
                        closest = target
                        closestPosition = partPosition
                        closestScore = -1
                        break
                    end
                    local screen, onScreen = WorldToScreen(partPosition)
                    if onScreen then
                        local dx = screen.X - center.X
                        local dy = screen.Y - center.Y
                        local score = math.sqrt(dx * dx + dy * dy)
                        if score <= Aim.fov and (not closestScore or score < closestScore) then
                            closest = target
                            closestPosition = partPosition
                            closestScore = score
                        end
                    end
                end
            end
        end
    end

    if not closest then
        Aim.lockedUserId = nil
        return
    end
    if not aimVisible(origin, closestPosition, closest.character) then return end
    if Aim.stickyTarget then Aim.lockedUserId = closest.userId end

    local rawVelocity = aimReadVelocity(closest.root)
    local previous = Aim.velocities[closest.userId] or rawVelocity
    local velocityAlpha = math.min(math.max(dt * 12, 0), 1)
    local velocity = previous:Lerp(rawVelocity, velocityAlpha)
    Aim.velocities[closest.userId] = velocity

    local targetPosition = aimPredict(origin, closestPosition, velocity)
    if Aim.prediction and Aim.showPredictionLine and Aim.predictionLine then
        local currentScreen, currentVisible = WorldToScreen(closestPosition)
        local predictedScreen, predictedVisible = WorldToScreen(targetPosition)
        if currentVisible and predictedVisible then
            Aim.predictionLine.From = Vector2.new(currentScreen.X, currentScreen.Y)
            Aim.predictionLine.To = Vector2.new(predictedScreen.X, predictedScreen.Y)
            Aim.predictionLine.Visible = true
        end
    end
    local desired = targetPosition - origin
    if desired.Magnitude <= 0.001 then return end

    local direction = desired.Unit
    if not Aim.hardLock then
        local current = camera.CFrame.LookVector
        local aimAlpha = 1 - math.exp(-math.max(Aim.smoothing, 1) * math.min(dt, 0.1))
        direction = current:Lerp(direction, aimAlpha)
    end
    if direction.Magnitude > 0.001 then
        camera.lookAt(origin, origin + direction.Unit * 1000)
    end
end)

function Aim.Stop()
    Aim.running = false
    Aim.enabled = false
    if Aim.connection then pcall(function() Aim.connection:Disconnect() end) end
    if Aim.fovCircle then
        pcall(function() Aim.fovCircle:Remove() end)
    end
    Aim.fovCircle = nil
    if Aim.predictionLine then
        pcall(function() Aim.predictionLine:Remove() end)
    end
    Aim.predictionLine = nil
    Aim.targets = {}
    Aim.velocities = {}
    Aim.lockedUserId = nil
end

pcall(function()
    notify("Predictive Aimbot", "Experimental build loaded - hold right mouse", 4)
end)
