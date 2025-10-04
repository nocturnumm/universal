-- Spinbot + Triggerbot + Optimized Bhop + ESP/Aimbot
-- Drop this LocalScript into StarterPlayer -> StarterPlayerScripts
-- Toggle Spinbot with BackSlash '\' (configurable)
-- WARNING: Using spin/trigger features in online games can violate Terms of Service.

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local ContextActionService = game:GetService("ContextActionService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("LocalPlayer not ready. Script will not run.")
    return
end

local Camera = Workspace.CurrentCamera
if not Camera then
    warn("Camera not available. Script will not run.")
    return
end

-- CONFIG
local CONFIG = {
    FOV_RADIUS = 500,
    AIMBOT_SMOOTHNESS = 2,
    KEY_ESP = Enum.KeyCode.E,
    KEY_AIMBOT = Enum.KeyCode.Y,
    KEY_FOV = Enum.KeyCode.V,
    KEY_SPINBOT = Enum.KeyCode.BackSlash, -- '\'

    SPINBOT_SPIN_SPEED = 1600,            -- degrees per second (yaw for spinbot)
    TRIGGER_RATE = 0.06,
    TRIGGER_FOV = 90,
    TRIGGER_MAX_DIST = 1200,
    WALLBANG_CLIENT = true,
    TRIGGER_HOLD = 0.02,

    BHOP_REAPPLY_DELAY = 0.03,
}

-- STATE
local STATE = {
    ESP = true,
    AIMBOT = true,
    FOV = true,
    SPINBOT = false,
    holdingRMB = false,
    jumping = false,
    typing = false,
    bhopStoredVelocity = nil,
}

-- Performance reused objects
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Blacklist

local nameTagMap = {}
local lastTrigger = 0
local spinYaw = 0 -- degrees

-- Drawing setup (minimal) - guard if Drawing not available (some environments)
local DrawingLib = Drawing
local safeDrawing = true
if not DrawingLib then safeDrawing = false end

local FOVCircle, Tracer, Watermark, Keybinds
if safeDrawing then
    FOVCircle = DrawingLib.new("Circle")
    FOVCircle.NumSides, FOVCircle.Thickness, FOVCircle.Filled = 100, 2, false
    FOVCircle.Radius, FOVCircle.Transparency = CONFIG.FOV_RADIUS, 0.6
    FOVCircle.Visible = true

    Tracer = DrawingLib.new("Line")
    Tracer.Visible = false

    Watermark = DrawingLib.new("Text")
    Watermark.Text = "made by nocturnumm on discord add me for a surprise :3"
    Watermark.Size = 18
    Watermark.Outline = true
    Watermark.Visible = false

    Keybinds = DrawingLib.new("Text")
    Keybinds.Size = 18
    Keybinds.Outline = true
    Keybinds.Visible = true
else
    warn("Drawing library unavailable; HUD will not draw.")
end

-- Helpers
local function isKO(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return not hum or hum.Health <= 0
end

-- Improved isVisible: raycast from camera towards part and allow if hit is descendant of target character
local function isVisible(part)
    if not part or not part.Position then return false end
    -- blacklist local player's character so ray doesn't immediately hit own body
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
    local origin = Camera.CFrame.Position
    local dir = (part.Position - origin)
    if dir.Magnitude == 0 then return true end
    local result = Workspace:Raycast(origin, dir, rayParams)
    if not result then
        return true
    end
    local hitInst = result.Instance
    if not hitInst then return true end
    -- allow if the hit instance belongs to the same character as the requested part
    return hitInst:IsDescendantOf(part.Parent)
end

-- safer team check (handles nil teams)
local function sameTeam(a, b)
    if not a or not b then return false end
    if a.Team and b.Team then return a.Team == b.Team end
    return false
end

local function getBestTarget(maxDist, fovDeg)
    local bestPart, bestPlayer, bestScore
    local camCF = Camera.CFrame
    local camPos = camCF.Position
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and not sameTeam(pl, LocalPlayer) then
            local char = pl.Character
            if char and not isKO(char) then
                local head = char:FindFirstChild("Head")
                local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
                local aimPart = head or root
                if aimPart and aimPart.Position then
                    local toTarget = (aimPart.Position - camPos)
                    local dist = toTarget.Magnitude
                    if dist <= maxDist then
                        local forward = camCF.LookVector
                        local dot = forward:Dot(toTarget.Unit)
                        if dot > 0 then
                            local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
                            if angle <= fovDeg then
                                local score = angle + (dist / 1000)
                                if (not bestScore) or score < bestScore then
                                    bestScore = score
                                    bestPart = aimPart
                                    bestPlayer = pl
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return bestPart, bestPlayer
end

local function doTriggerFireAt(mousePos)
    -- VirtualUser functions can error in some environments; guard with pcall
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button1Down()
        task.wait(CONFIG.TRIGGER_HOLD)
        VirtualUser:Button1Up()
    end)
end

-- Nametag creation (light) - avoid duplicates
local function createNameTag(player)
    if not player or player == LocalPlayer then return end
    if nameTagMap[player] then return end
    -- spawn separate thread to wait for character & head
    local conn
    conn = player.CharacterAdded:Connect(function(char)
        task.spawn(function()
            local head = char:WaitForChild("Head", 2)
            if head and head.Parent and not head:FindFirstChild("NameTag") then
                if not player.Parent then return end
                local billboard = Instance.new("BillboardGui")
                billboard.Name, billboard.Adornee, billboard.AlwaysOnTop = "NameTag", head, true
                billboard.Size, billboard.StudsOffset, billboard.MaxDistance = UDim2.new(0,140,0,28), Vector3.new(0,2.6,0), 1000
                billboard.Enabled, billboard.Parent = STATE.ESP, head

                local label = Instance.new("TextLabel")
                label.Size, label.BackgroundTransparency, label.Text = UDim2.new(1,0,1,0), 1, player.Name
                label.TextColor3, label.TextStrokeTransparency, label.Font, label.TextScaled = Color3.fromRGB(255,255,255), 0.2, Enum.Font.SourceSansBold, true
                label.Parent = billboard

                nameTagMap[player] = billboard
            end
        end)
    end)
    -- If player already has character, attempt to create immediately
    if player.Character and player.Character.Parent then
        task.spawn(function()
            local head = player.Character:FindFirstChild("Head")
            if head and not head:FindFirstChild("NameTag") then
                local billboard = Instance.new("BillboardGui")
                billboard.Name, billboard.Adornee, billboard.AlwaysOnTop = "NameTag", head, true
                billboard.Size, billboard.StudsOffset, billboard.MaxDistance = UDim2.new(0,140,0,28), Vector3.new(0,2.6,0), 1000
                billboard.Enabled, billboard.Parent = STATE.ESP, head

                local label = Instance.new("TextLabel")
                label.Size, label.BackgroundTransparency, label.Text = UDim2.new(1,0,1,0), 1, player.Name
                label.TextColor3, label.TextStrokeTransparency, label.Font, label.TextScaled = Color3.fromRGB(255,255,255), 0.2, Enum.Font.SourceSansBold, true
                label.Parent = billboard

                nameTagMap[player] = billboard
            end
        end)
    end
    -- cleanup when player leaves
    player.AncestryChanged:Connect(function(_, parent)
        if not parent and nameTagMap[player] then
            pcall(function() nameTagMap[player]:Destroy() end)
            nameTagMap[player] = nil
            if conn then conn:Disconnect() end
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do createNameTag(p) end
Players.PlayerAdded:Connect(createNameTag)
Players.PlayerRemoving:Connect(function(p)
    if nameTagMap[p] then
        pcall(function() nameTagMap[p]:Destroy() end)
        nameTagMap[p] = nil
    end
end)

-- Keybind UI update
local function updateKeybindText()
    if not safeDrawing or not Keybinds then return end
    Keybinds.Text = string.format("[Keybinds]\nE - ESP: %s\nY - Aimbot: %s\nV - FOV: %s\\ - SPINBOT: %s",
        STATE.ESP and "ON" or "OFF", STATE.AIMBOT and "ON" or "OFF", STATE.FOV and "ON" or "OFF", STATE.SPINBOT and "ON" or "OFF")
end
updateKeybindText()

-- Manage typing state using UserInputService events for TextBox focus
if UserInputService.TextBoxFocused and UserInputService.TextBoxFocusReleased then
    UserInputService.TextBoxFocused:Connect(function() STATE.typing = true end)
    UserInputService.TextBoxFocusReleased:Connect(function() STATE.typing = false end)
end

-- bhop logic
local function handleBhop(hum, hrp, jumpingState)
    if jumpingState and STATE.bhopStoredVelocity == nil and hrp then
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics or st == Enum.HumanoidStateType.Landed then
            STATE.bhopStoredVelocity = Vector3.new(hrp.Velocity.X, 0, hrp.Velocity.Z)
        end
    end

    if jumpingState then
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.Landed or st == Enum.HumanoidStateType.RunningNoPhysics then
            local stored = STATE.bhopStoredVelocity
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
            if stored and hrp then
                task.spawn(function()
                    task.wait(CONFIG.BHOP_REAPPLY_DELAY)
                    if hrp and hrp.Parent then
                        hrp.Velocity = Vector3.new(stored.X, hrp.Velocity.Y, stored.Z)
                    end
                end)
            end
        end
    else
        STATE.bhopStoredVelocity = nil
    end
end

-- Input handling (allow spinbot toggle even if gameProcessed or typing)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    local allowedForSpinToggle = (input.KeyCode == CONFIG.KEY_SPINBOT)
    -- if the game processed the input and it's not allowed for spin toggle, ignore
    if gameProcessed and not allowedForSpinToggle then return end
    if STATE.typing and not allowedForSpinToggle then return end

    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        STATE.holdingRMB = true
    elseif input.KeyCode == Enum.KeyCode.Space then
        STATE.jumping = true
    elseif input.KeyCode == CONFIG.KEY_ESP then
        STATE.ESP = not STATE.ESP
        for _, gui in pairs(nameTagMap) do if gui then pcall(function() gui.Enabled = STATE.ESP end) end end
        updateKeybindText()
    elseif input.KeyCode == CONFIG.KEY_AIMBOT then
        STATE.AIMBOT = not STATE.AIMBOT
        updateKeybindText()
    elseif input.KeyCode == CONFIG.KEY_FOV then
        STATE.FOV = not STATE.FOV
        if safeDrawing and FOVCircle then FOVCircle.Visible = STATE.FOV end
        updateKeybindText()
    elseif input.KeyCode == CONFIG.KEY_SPINBOT then
        STATE.SPINBOT = not STATE.SPINBOT
        if STATE.SPINBOT then
            STATE.ESP = true
            STATE.AIMBOT = true
            STATE.FOV = true
            if safeDrawing and FOVCircle then FOVCircle.Visible = true end
            spinYaw = 0
        else
            STATE.bhopStoredVelocity = nil
        end
        updateKeybindText()
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        STATE.holdingRMB = false
    elseif input.KeyCode == Enum.KeyCode.Space then
        STATE.jumping = false
        STATE.bhopStoredVelocity = nil
    end
end)

-- ensure we restore on focus lost (avoid being stuck)
game:GetService("GuiService").MenuOpened:Connect(function()
    -- nothing special to restore now (no mouse locking), placeholder for future
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    STATE.bhopStoredVelocity = nil
    -- restore camera subject to humanoid on respawn if available
    pcall(function()
        Camera.CameraType = Enum.CameraType.Custom
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then Camera.CameraSubject = hum end
    end)
end)

-- Main RenderStepped loop
local renderConn
renderConn = RunService.RenderStepped:Connect(function(dt)
    -- guard camera/canvas
    if not Camera then return end
    local vp = Camera.ViewportSize
    local mpos = UserInputService:GetMouseLocation()
    if safeDrawing and FOVCircle then
        FOVCircle.Position, FOVCircle.Radius = mpos, CONFIG.FOV_RADIUS
        Watermark.Position = Vector2.new(vp.X - 420, vp.Y - 40)
        Keybinds.Position = Vector2.new(20, 20)
    end

    -- nametag enabling
    for pl, gui in pairs(nameTagMap) do
        local char = pl.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local head = char and char:FindFirstChild("Head")
        if gui and hum and head then
            pcall(function()
                gui.Enabled = STATE.ESP and hum.Health > 0 and not sameTeam(pl, LocalPlayer)
            end)
        end
    end

    -- Aimbot (camera smoothing)
    if STATE.AIMBOT and STATE.holdingRMB then
        local bestHead = nil
        local bestDist = CONFIG.FOV_RADIUS
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LocalPlayer and not sameTeam(pl, LocalPlayer) then
                local char = pl.Character
                local head = char and char:FindFirstChild("Head")
                if head and not isKO(char) then
                    local v2, onScreen = Camera:WorldToViewportPoint(head.Position)
                    if onScreen and isVisible(head) then
                        local dist = (Vector2.new(v2.X, v2.Y) - mpos).Magnitude
                        if dist < bestDist then
                            bestDist = dist
                            bestHead = head
                        end
                    end
                end
            end
        end
        if bestHead then
            local camCF, dir = Camera.CFrame, (bestHead.Position - Camera.CFrame.Position).Unit
            Camera.CFrame = camCF:Lerp(CFrame.new(camCF.Position, camCF.Position + dir), 1 / math.max(1, CONFIG.AIMBOT_SMOOTHNESS))
            local pos, onScreen = Camera:WorldToViewportPoint(bestHead.Position)
            if onScreen and Tracer then
                Tracer.From, Tracer.To, Tracer.Visible = Vector2.new(vp.X/2, vp.Y/2), Vector2.new(pos.X, pos.Y), true
            elseif Tracer then
                Tracer.Visible = false
            end
        else
            if Tracer then Tracer.Visible = false end
        end
    end

    -- Triggerbot (spinbot fast)
    if STATE.SPINBOT then
        local now = tick()
        if now - lastTrigger >= CONFIG.TRIGGER_RATE then
            lastTrigger = now
            local targetPart, targetPlayer = getBestTarget(CONFIG.TRIGGER_MAX_DIST, CONFIG.TRIGGER_FOV)
            if targetPart and targetPlayer then
                if CONFIG.WALLBANG_CLIENT or isVisible(targetPart) then
                    doTriggerFireAt(UserInputService:GetMouseLocation())
                end
            end
        end
    end

    -- SPINBOT (character spin visible to others) - rotate HRP yaw rapidly
    if STATE.SPINBOT then
        local char = LocalPlayer.Character
        local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
        if hrp and hrp.Parent then
            spinYaw = (spinYaw + CONFIG.SPINBOT_SPIN_SPEED * dt) % 360
            local pos = hrp.Position
            local vel = hrp.Velocity
            hrp.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(spinYaw), 0)
            hrp.Velocity = vel
        end
    end

    -- Bhop
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        if hum and hrp then
            handleBhop(hum, hrp, STATE.jumping and not STATE.typing)
        end
    end
end)

-- Clean up / restore function
local function cleanup()
    if safeDrawing then
        if FOVCircle then pcall(function() FOVCircle:Remove() end) end
        if Tracer then pcall(function() Tracer:Remove() end) end
        if Watermark then pcall(function() Watermark:Remove() end) end
        if Keybinds then pcall(function() Keybinds:Remove() end) end
    end
    if renderConn then renderConn:Disconnect() end
    -- restore mouse behaviour/camera
    pcall(function()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
        if Camera then Camera.CameraType = Enum.CameraType.Custom end
    end)
    -- destroy nametags
    for pl, gui in pairs(nameTagMap) do
        pcall(function() gui:Destroy() end)
        nameTagMap[pl] = nil
    end
end

-- restore on character removal (ensure camera restored)
LocalPlayer.CharacterRemoving:Connect(function()
    STATE.bhopStoredVelocity = nil
    pcall(function()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
        if Camera then Camera.CameraType = Enum.CameraType.Custom end
    end)
end)
