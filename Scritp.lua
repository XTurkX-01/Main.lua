-- ====================================================================
-- X MENÜ V45 - DÜZELTİLMİŞ SÜRÜM
-- GitHub loadstring uyumlu
-- ====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Settings = {
    FlingPower = 2000, MinFlingPower = 100, MaxFlingPower = 50000,
    MaxSpinSpeed = 500, FlingCooldown = 0.2, FlingRange = 50, FlingDamage = 50,
    FlySpeed = 70, WaypointSpeed = 90, WaypointFlingCooldown = 0.15,
    NoclipActive = false, IsFlying = false, ClickFlingActive = false,
    IsFlingEveryone = false, IsNormalFling = false, RespawnProtection = false,
    IsWaypointRunning = false, WaypointDirection = 1,
    UseBanSafe = false, AntiDetection = false,
    FlingDelayMin = 5, FlingDelayMax = 15, MaxTargetsPerFrame = 3,
}

local VehicleData = {Current=nil, MainPart=nil, SavedCFrame=nil, IsAnchored=false, LastVehicleCheck=0, VehicleCheckInterval=0.5, LastNoclipVehicle=nil}
local WaypointData = {Point1=nil, Point2=nil}
local State = {
    lastFlingTime=0, isFollowingPlayer=false, targetPlayer=nil,
    targetPosition=nil, isSelectingTarget=false, lastStatusUpdate=0,
    isRespawning=false, lastSoundTime=0, lastEffectTime=0,
    isShuttingDown=false, killCount=0, lastRespawnCheck=0,
    lastPatrolFlingTime=0, lastWaypointFlingTime=0, lastAIMode=nil,
    lastNoclipState=nil, lastMobileToggleTime=0, lastAIStatusUpdate=0,
    isSelectingPlayer=false, deathCount=0, currentStreak=0, bestStreak=0,
    sessionKills=0, sessionDeaths=0,
}
local MoveDirection = Vector3.new(0,0,0)
local ActiveDirBtns = {}
local AIData = {
    Enabled=false, Mode="auto", Target=nil, LastTargetSwitch=0,
    TargetSwitchCooldown=2, ThreatRadius=60, AttackRadius=30,
    RetreatHP=30, PatrolPoints={}, MaxPatrolPoints=20,
    CurrentPatrolIndex=1, ScanInterval=0.3, LastScan=0,
    Personality=math.random(),
}
local FlingQueue = {}
local isAutoPilotActive = false
local currentQueueIndex = 1
local KillcamBuffer = {}
local KillcamRecording = false
local KILLCAM_MAX = 60

local Connections = {}
local Timers = {}

local function AddConnection(conn)
    table.insert(Connections, conn)
    return conn
end

local function AddTimer()
    local token = {cancelled=false}
    table.insert(Timers, token)
    return token
end

local function TrackTimer(token)
    if not token then return end
    local idx = table.find(Timers, token)
    if idx then table.remove(Timers, idx) end
end

local function CleanupConnections()
    for _, conn in ipairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Connections = {}
    for _, token in ipairs(Timers) do
        pcall(function() token.cancelled = true end)
    end
    Timers = {}
end

local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then warn("Hata: " .. tostring(result)) return nil end
    return result
end

local StatusLabel, KillLabel, StatsLabel
local function SetStatus(text, color)
    if State.isShuttingDown then return end
    if not StatusLabel or not StatusLabel.Parent then return end
    local now = os.clock()
    if text == StatusLabel.Text and now - State.lastStatusUpdate < 0.1 then return end
    State.lastStatusUpdate = now
    StatusLabel.Text = text
    StatusLabel.TextColor3 = color or Color3.fromRGB(0, 255, 0)
end

local function ScheduleFlingWithDelay(root, power, spinSpeed)
    if not root or not root.Parent then return end
    if not Settings.AntiDetection then
        root.AssemblyLinearVelocity = Vector3.new(math.random(-power,power), math.random(power/2,power*2), math.random(-power,power))
        root.AssemblyAngularVelocity = Vector3.new(math.random(-spinSpeed,spinSpeed), math.random(-spinSpeed,spinSpeed), math.random(-spinSpeed,spinSpeed))
        return
    end
    local token = AddTimer()
    local delay = math.random(Settings.FlingDelayMin, Settings.FlingDelayMax) / 1000
    task.delay(delay, function()
        TrackTimer(token)
        if token.cancelled or State.isShuttingDown then return end
        if not root or not root.Parent then return end
        local humanoid = root.Parent:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        root.AssemblyLinearVelocity = Vector3.new(math.random(-power,power), math.random(power/2,power*2), math.random(-power,power))
        root.AssemblyAngularVelocity = Vector3.new(math.random(-spinSpeed,spinSpeed), math.random(-spinSpeed,spinSpeed), math.random(-spinSpeed,spinSpeed))
    end)
end

local CachedRayParams = RaycastParams.new()
CachedRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function UpdateRayFilter()
    local list = {}
    if LocalPlayer.Character then table.insert(list, LocalPlayer.Character) end
    if VehicleData.Current and VehicleData.Current.Parent then table.insert(list, VehicleData.Current) end
    CachedRayParams.FilterDescendantsInstances = list
end

local KillTracker = {}
local playerKills = {}
local playerDeaths = {}
local playerStreaks = {}
local playerBestStreaks = {}
local recentKillTimestamps = {}

function KillTracker.RegisterKill(killer, victim)
    if killer then
        playerKills[killer] = (playerKills[killer] or 0) + 1
        playerStreaks[killer] = (playerStreaks[killer] or 0) + 1
        playerBestStreaks[killer] = math.max(playerBestStreaks[killer] or 0, playerStreaks[killer])
        if not recentKillTimestamps[killer] then recentKillTimestamps[killer] = {} end
        table.insert(recentKillTimestamps[killer], os.clock())
        local streak = playerStreaks[killer]
        for _, threshold in ipairs({3, 5, 10, 15, 20}) do
            if streak == threshold then
                SetStatus("KILL STREAK: " .. killer.Name .. " x" .. threshold, Color3.fromRGB(255, 200, 0))
            end
        end
        if killer == LocalPlayer then
            State.sessionKills = State.sessionKills + 1
            State.currentStreak = State.currentStreak + 1
            State.bestStreak = math.max(State.bestStreak, State.currentStreak)
            State.killCount = State.killCount + 1
            if KillLabel and KillLabel.Parent then
                KillLabel.Text = "Kill: " .. State.killCount .. " | Streak: " .. State.currentStreak
            end
        end
    end
    if victim then
        playerDeaths[victim] = (playerDeaths[victim] or 0) + 1
        playerStreaks[victim] = 0
        if victim == LocalPlayer then
            State.sessionDeaths = State.sessionDeaths + 1
            State.deathCount = State.deathCount + 1
            State.currentStreak = 0
        end
    end
    KillTracker.UpdateStats()
end

function KillTracker.GetKD(player)
    local kills = playerKills[player] or 0
    local deaths = math.max(playerDeaths[player] or 0, 1)
    return kills / deaths
end

function KillTracker.GetRecentKills(player, window)
    window = window or 15
    local now = os.clock()
    local count = 0
    if recentKillTimestamps[player] then
        for _, t in ipairs(recentKillTimestamps[player]) do
            if now - t <= window then count = count + 1 end
        end
    end
    return count
end

function KillTracker.GetAllStats()
    local result = {}
    for _, player in ipairs(Players:GetPlayers()) do
        result[player] = {
            killsInWindow = KillTracker.GetRecentKills(player, 15),
            currentStreak = playerStreaks[player] or 0,
            kd = KillTracker.GetKD(player),
        }
    end
    return result
end

function KillTracker.UpdateStats()
    if not StatsLabel or not StatsLabel.Parent then return end
    local kd = State.sessionDeaths > 0 and (State.sessionKills / State.sessionDeaths) or State.sessionKills
    StatsLabel.Text = string.format("K: %d | D: %d | K/D: %.2f | Streak: %d | Best: %d",
        State.sessionKills, State.sessionDeaths, kd, State.currentStreak, State.bestStreak)
end

function KillTracker.CalculateMVP()
    local best, bestScore = nil, -math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        local kills = playerKills[player] or 0
        local deaths = playerDeaths[player] or 0
        local bestStreak = playerBestStreaks[player] or 0
        local score = (kills * 2) - deaths + (bestStreak * 1.5)
        if score > bestScore then
            bestScore = score
            best = player
        end
    end
    return best, bestScore
end

local KillTrackerConnections = {}

local function AttachPlayerKillTracking(player)
    if not player or player == LocalPlayer then return end
    if KillTrackerConnections[player] then return end
    KillTrackerConnections[player] = true
    local activeHumanoidConn = nil
    local function attachToHumanoid(humanoid)
        if not humanoid then return end
        if activeHumanoidConn then pcall(function() activeHumanoidConn:Disconnect() end) activeHumanoidConn = nil end
        activeHumanoidConn = AddConnection(humanoid.Died:Connect(function()
            if State.isShuttingDown then return end
            local killer = nil
            pcall(function()
                local creator = humanoid:FindFirstChild("creator")
                if creator and creator.Value then
                    killer = Players:GetPlayerFromCharacter(creator.Value.Parent)
                end
            end)
            KillTracker.RegisterKill(killer, player)
        end))
    end
    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then attachToHumanoid(humanoid) end
    end
    AddConnection(player.CharacterAdded:Connect(function(newChar)
        if State.isShuttingDown then return end
        task.delay(0.3, function()
            if State.isShuttingDown then return end
            local humanoid = newChar:FindFirstChildOfClass("Humanoid")
            if humanoid then attachToHumanoid(humanoid) end
        end)
    end))
end

local function UnanchorVehicle()
    return SafeCall(function()
        if VehicleData.MainPart and VehicleData.MainPart.Parent then
            local obj = VehicleData.MainPart:FindFirstChild("FlingGyro")
            if obj then obj:Destroy() end
            local align = VehicleData.MainPart:FindFirstChild("VehicleAlignOrientation")
            if align then align:Destroy() end
            local attach = VehicleData.MainPart:FindFirstChild("StabilizerAttachment")
            if attach then attach:Destroy() end
        end
        VehicleData.IsAnchored = false
        VehicleData.SavedCFrame = nil
    end)
end

local function GetVehicle(forceRefresh)
    local now = os.clock()
    local char = LocalPlayer.Character
    if not char then VehicleData.Current = nil return nil end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or not humanoid.SeatPart or not humanoid.SeatPart.Parent then
        if VehicleData.Current then
            UnanchorVehicle()
            VehicleData.Current = nil
            VehicleData.MainPart = nil
            State.lastNoclipState = nil
        end
        return nil
    end
    local vehicleModel = humanoid.SeatPart:FindFirstAncestorOfClass("Model") or humanoid.SeatPart.Parent
    if VehicleData.Current and VehicleData.Current ~= vehicleModel then
        UnanchorVehicle()
        State.lastNoclipState = nil
        VehicleData.LastNoclipVehicle = nil
    end
    if not forceRefresh and VehicleData.Current and VehicleData.Current == vehicleModel and VehicleData.Current.Parent then
        if now - VehicleData.LastVehicleCheck < VehicleData.VehicleCheckInterval then
            VehicleData.LastVehicleCheck = now
            return VehicleData.Current
        end
    end
    VehicleData.LastVehicleCheck = now
    VehicleData.Current = vehicleModel
    return vehicleModel
end

local function ResetVehicleData()
    UnanchorVehicle()
    VehicleData.Current = nil
    VehicleData.MainPart = nil
    VehicleData.LastVehicleCheck = 0
    VehicleData.LastNoclipVehicle = nil
    State.lastNoclipState = nil
end

local function StabilizeWithAlign(mainPart)
    local attach = mainPart:FindFirstChild("StabilizerAttachment")
    if not attach then
        attach = Instance.new("Attachment")
        attach.Name = "StabilizerAttachment"
        attach.Parent = mainPart
    end
    local align = mainPart:FindFirstChild("VehicleAlignOrientation")
    if not align then
        align = Instance.new("AlignOrientation")
        align.Name = "VehicleAlignOrientation"
        align.Attachment0 = attach
        align.Mode = Enum.OrientationAlignmentMode.OneAttachment
        align.MaxTorque = math.huge
        align.Responsiveness = 25
        align.RigidityEnabled = false
        local currentLook = mainPart.CFrame.LookVector
        local flatLook = Vector3.new(currentLook.X, 0, currentLook.Z)
        if flatLook.Magnitude > 0.01 then
            align.CFrame = CFrame.lookAt(Vector3.zero, flatLook.Unit)
        else
            align.CFrame = CFrame.new()
        end
        align.Parent = mainPart
    end
    return align
end

local function CreateFlingEffect(position)
    if State.isShuttingDown then return end
    local now = os.clock()
    if now - State.lastEffectTime < 0.1 then return end
    State.lastEffectTime = now
    return SafeCall(function()
        for i = 1, 3 do
            local part = Instance.new("Part")
            part.Position = position + Vector3.new(math.random(-5,5), math.random(-5,5), math.random(-5,5))
            part.Size = Vector3.new(1,1,1)
            part.Shape = Enum.PartType.Ball
            part.Material = Enum.Material.Neon
            part.BrickColor = BrickColor.new("Bright red")
            part.Anchored = true
            part.CanCollide = false
            part.CastShadow = false
            part.Transparency = 0.1
            part.Parent = Workspace
            TweenService:Create(part, TweenInfo.new(0.7, Enum.EasingStyle.Quad), {Size=Vector3.new(8,8,8), Transparency=1}):Play()
            Debris:AddItem(part, 0.8)
        end
    end)
end

local function PlayFlingSound(position)
    if State.isShuttingDown then return end
    local now = os.clock()
    if now - State.lastSoundTime < 0.3 then return end
    State.lastSoundTime = now
    return SafeCall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://138091579"
        sound.Volume = 0.4
        sound.Parent = Workspace
        sound.Position = position
        sound:Play()
        Debris:AddItem(sound, 5)
    end)
end

local function DoFlingAction(multiplier)
    if State.isShuttingDown then return end
    return SafeCall(function()
        local vehicle = GetVehicle()
        if not vehicle then SetStatus("ARAC YOK!", Color3.fromRGB(255,0,0)) return end
        local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart or vehicle:FindFirstChildWhichIsA("BasePart")
        if not mainPart then return end
        VehicleData.SavedCFrame = mainPart.CFrame
        VehicleData.MainPart = mainPart
        StabilizeWithAlign(mainPart)
        local hitCount = 0
        local count = 0
        for _, player in pairs(Players:GetPlayers()) do
            if count >= Settings.MaxTargetsPerFrame then break end
            if player ~= LocalPlayer and player.Character then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                local humanoid = player.Character:FindFirstChild("Humanoid")
                if root and humanoid and humanoid.Health > 0 then
                    local dist = (root.Position - mainPart.Position).Magnitude
                    if dist <= Settings.FlingRange then
                        local power = Settings.FlingPower * (multiplier or 1)
                        ScheduleFlingWithDelay(root, power, Settings.MaxSpinSpeed)
                        if not Settings.UseBanSafe then
                            humanoid.Health = math.max(0, humanoid.Health - Settings.FlingDamage)
                        end
                        CreateFlingEffect(root.Position)
                        PlayFlingSound(root.Position)
                        hitCount = hitCount + 1
                        count = count + 1
                    end
                end
            end
        end
        if hitCount > 0 then SetStatus(hitCount .. " oyuncu uctu!", Color3.fromRGB(255,200,0)) end
    end)
end

local function WaypointLoop()
    if State.isShuttingDown then return end
    return SafeCall(function()
        if not Settings.IsWaypointRunning then return end
        if not WaypointData.Point1 or not WaypointData.Point2 then return end
        local vehicle = GetVehicle()
        if not vehicle then return end
        local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
        if not mainPart then return end
        if VehicleData.IsAnchored then UnanchorVehicle() end
        local targetCF = Settings.WaypointDirection == 1 and WaypointData.Point1 or WaypointData.Point2
        if not targetCF then return end
        local targetPos = targetCF.Position + Vector3.new(0, 2, 0)
        local currentPos = mainPart.Position
        local diff = targetPos - currentPos
        local distance = diff.Magnitude
        if distance > 2 then
            local direction = diff.Unit
            local speed = math.min(Settings.WaypointSpeed, distance / 1.5)
            local newPos = currentPos + direction * speed
            mainPart.CFrame = CFrame.lookAt(newPos, newPos + direction)
            mainPart.AssemblyLinearVelocity = direction * speed
            mainPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            local now = os.clock()
            if now - State.lastWaypointFlingTime > Settings.WaypointFlingCooldown then
                State.lastWaypointFlingTime = now
                for _, player in pairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer and player.Character then
                        local root = player.Character:FindFirstChild("HumanoidRootPart")
                        local humanoid = player.Character:FindFirstChild("Humanoid")
                        if root and humanoid and humanoid.Health > 0 then
                            local dist = (root.Position - mainPart.Position).Magnitude
                            if dist <= Settings.FlingRange then
                                local power = Settings.FlingPower
                                root.AssemblyLinearVelocity = Vector3.new(math.random(-power,power), math.random(power/2,power*2), math.random(-power,power))
                                root.AssemblyAngularVelocity = Vector3.new(math.random(-Settings.MaxSpinSpeed,Settings.MaxSpinSpeed), math.random(-Settings.MaxSpinSpeed,Settings.MaxSpinSpeed), math.random(-Settings.MaxSpinSpeed,Settings.MaxSpinSpeed))
                                if not Settings.UseBanSafe then humanoid.Health = math.max(0, humanoid.Health - Settings.FlingDamage) end
                                CreateFlingEffect(root.Position)
                            end
                        end
                    end
                end
            end
            SetStatus("YOL + FLING!", Color3.fromRGB(255,200,0))
        else
            mainPart.CFrame = targetCF + Vector3.new(0, 2, 0)
            mainPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            Settings.WaypointDirection = Settings.WaypointDirection * -1
        end
    end)
end

local function GetPredictedPosition(targetRoot, leadTime)
    leadTime = leadTime or 1.2
    return targetRoot.Position + (targetRoot.AssemblyLinearVelocity * leadTime)
end

local function SelectBestTarget()
    local vehicle = GetVehicle()
    if not vehicle then return nil end
    local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
    if not mainPart then return nil end
    local bestTarget, bestScore = nil, -math.huge
    local now = os.clock()
    local myPos = mainPart.Position
    local playerStats = KillTracker.GetAllStats()
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer or not player.Character then continue end
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if not root or not humanoid or humanoid.Health <= 0 then continue end
        local distance = (root.Position - myPos).Magnitude
        if distance > AIData.ThreatRadius then continue end
        local baseScore = (AIData.ThreatRadius - distance) * 1.5
        if humanoid.Health < 30 then baseScore = baseScore + 40 end
        local myLook = mainPart.CFrame.LookVector
        local toTarget = (root.Position - myPos).Unit
        if myLook:Dot(toTarget) < 0 then baseScore = baseScore + 25 end
        local predictedPos = GetPredictedPosition(root)
        local predDist = (myPos - predictedPos).Magnitude
        local leadBonus = math.clamp(distance - predDist, 0, 15)
        local hysteresis = (player == AIData.Target) and 20 or 0
        local stats = playerStats[player]
        local threatScore = 0
        if stats then threatScore = (stats.killsInWindow + stats.currentStreak) * 8 end
        local aggression = 0.7 + (AIData.Personality * 0.6)
        local finalScore = (baseScore * aggression) + leadBonus + hysteresis + (threatScore * aggression)
        if finalScore > bestScore then
            bestScore = finalScore
            bestTarget = player
        end
    end
    return bestTarget
end

local function FindNearestThreat()
    local vehicle = GetVehicle()
    if not vehicle then return nil end
    local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
    if not mainPart then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer or not player.Character then continue end
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        local dist = (root.Position - mainPart.Position).Magnitude
        if dist < nearestDist and dist < AIData.ThreatRadius then
            nearestDist = dist nearest = player
        end
    end
    return nearest, nearestDist
end

local function UpdateAI()
    if State.isShuttingDown or not AIData.Enabled then return end
    local now = os.clock()
    if now - AIData.LastScan < AIData.ScanInterval then return end
    AIData.LastScan = now
    local localChar = LocalPlayer.Character
    if not localChar then return end
    local humanoid = localChar:FindFirstChild("Humanoid")
    if not humanoid then return end
    local vehicle = GetVehicle()
    if not vehicle then return end
    local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
    if not mainPart then return end
    local mode = AIData.Mode
    if mode == "auto" then
        mode = (humanoid.Health / humanoid.MaxHealth < AIData.RetreatHP / 100) and "defensive" or "aggressive"
    end
    if mode == "defensive" then
        local threat, dist = FindNearestThreat()
        if threat and dist then
            local threatRoot = threat.Character and threat.Character:FindFirstChild("HumanoidRootPart")
            if threatRoot then
                local awayDir = (mainPart.Position - threatRoot.Position).Unit
                mainPart.CFrame = CFrame.lookAt(mainPart.Position, mainPart.Position + awayDir)
                mainPart.AssemblyLinearVelocity = awayDir * Settings.FlySpeed * 1.5
                SetStatus("KACIYOR: " .. threat.Name, Color3.fromRGB(255,100,100))
                if dist < Settings.FlingRange and now - State.lastFlingTime > Settings.FlingCooldown then
                    State.lastFlingTime = now
                    DoFlingAction(1.2)
                end
            end
        end
        return
    end
    if mode == "aggressive" then
        if now - AIData.LastTargetSwitch > AIData.TargetSwitchCooldown or not AIData.Target then
            local newTarget = SelectBestTarget()
            if newTarget and newTarget ~= AIData.Target then
                AIData.Target = newTarget
                AIData.LastTargetSwitch = now
                SetStatus("HEDEF: " .. newTarget.Name, Color3.fromRGB(255,200,0))
            elseif not newTarget then
                AIData.LastTargetSwitch = now
            end
        end
        local target = AIData.Target
        if not target or not target.Character then return end
        local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
        local targetHum = target.Character:FindFirstChild("Humanoid")
        if not targetRoot or not targetHum or targetHum.Health <= 0 then
            AIData.Target = nil
            return
        end
        local dist = (targetRoot.Position - mainPart.Position).Magnitude
        if dist > AIData.AttackRadius then
            local dir = (targetRoot.Position - mainPart.Position).Unit
            mainPart.CFrame = CFrame.lookAt(mainPart.Position, targetRoot.Position)
            mainPart.AssemblyLinearVelocity = dir * Settings.FlySpeed
            SetStatus("KOVALIYOR: " .. target.Name, Color3.fromRGB(255,150,0))
        else
            if now - State.lastFlingTime > Settings.FlingCooldown then
                State.lastFlingTime = now
                DoFlingAction(1.5)
                SetStatus("VURULDU: " .. target.Name, Color3.fromRGB(255,50,50))
            end
        end
    end
    if mode == "patrol" and #AIData.PatrolPoints > 0 then
        local targetCF = AIData.PatrolPoints[AIData.CurrentPatrolIndex]
        if targetCF then
            local targetPos = targetCF.Position + Vector3.new(0, 2, 0)
            local dist = (targetPos - mainPart.Position).Magnitude
            if dist < 5 then
                AIData.CurrentPatrolIndex = AIData.CurrentPatrolIndex % #AIData.PatrolPoints + 1
            else
                local dir = (targetPos - mainPart.Position).Unit
                mainPart.CFrame = CFrame.lookAt(mainPart.Position, targetPos)
                mainPart.AssemblyLinearVelocity = dir * Settings.WaypointSpeed
            end
        end
    end
end

local function StartKillcamRecording()
    if KillcamRecording then return end
    KillcamRecording = true
    task.spawn(function()
        while KillcamRecording and not State.isShuttingDown do
            task.wait(0.05)
            local vehicle = GetVehicle()
            if vehicle then
                local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
                if mainPart then
                    table.insert(KillcamBuffer, {cframe = mainPart.CFrame, timestamp = os.clock()})
                    if #KillcamBuffer > KILLCAM_MAX then table.remove(KillcamBuffer, 1) end
                end
            end
        end
    end)
end

local function StopKillcamRecording()
    KillcamRecording = false
end

local function PlayKillcam(replayPart)
    if #KillcamBuffer == 0 then return end
    task.spawn(function()
        local startTime = os.clock()
        local firstTimestamp = KillcamBuffer[1].timestamp
        for _, sample in ipairs(KillcamBuffer) do
            local elapsed = sample.timestamp - firstTimestamp
            local waitTime = (startTime + elapsed) - os.clock()
            if waitTime > 0 then task.wait(waitTime) end
            if replayPart and replayPart.Parent then
                replayPart.CFrame = sample.cframe
            end
        end
    end)
end

-- ====================================================================
-- UI OLUŞTURMA
-- ====================================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CarFlingXMenuV45"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ScreenGui.Parent = PlayerGui

local DragStates = {}
local DRAG_THRESHOLD = 5

local function MakeDraggable(frame, onClick, onDragEnd)
    local dragStart, startPos, moved, activeInput = nil, nil, false, nil
    local function inputPosition(input)
        return Vector2.new(input.Position.X, input.Position.Y)
    end
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragStart = inputPosition(input)
            startPos = frame.Position
            moved = false
            activeInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if activeInput and dragStart then
            local delta = inputPosition(input) - dragStart
            if not moved and delta.Magnitude > DRAG_THRESHOLD then moved = true end
            if moved then
                frame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if activeInput and input == activeInput then
            if moved then
                if onDragEnd then onDragEnd(frame.Position) end
            else
                if onClick then onClick() end
            end
            dragStart, activeInput = nil, nil
        end
    end)
end

local XMenu = Instance.new("Frame")
XMenu.Name = "XMenu"
XMenu.Size = UDim2.new(0, 540, 0, 440)
XMenu.Position = UDim2.new(0.5, -270, 0.5, -220)
XMenu.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
XMenu.BorderSizePixel = 0
XMenu.Active = true
XMenu.Draggable = false
XMenu.Visible = false
XMenu.Parent = ScreenGui
Instance.new("UICorner", XMenu).CornerRadius = UDim.new(0, 12)

local XMenuStroke = Instance.new("UIStroke")
XMenuStroke.Color = Color3.fromRGB(255, 0, 0)
XMenuStroke.Thickness = 3
XMenuStroke.Transparency = 0.2
XMenuStroke.Parent = XMenu

local pulseStopped = false
local function pulseStep(toColor, fromColor)
    if pulseStopped or not XMenu.Parent then return end
    local tween = TweenService:Create(XMenuStroke, TweenInfo.new(1, Enum.EasingStyle.Sine), {Color=toColor, Transparency=0.3})
    tween:Play()
    tween.Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed and not pulseStopped then
            pulseStep(fromColor, toColor)
        end
    end)
end
task.spawn(function() pulseStep(Color3.fromRGB(120,0,0), Color3.fromRGB(255,0,0)) end)

local XTitleBar = Instance.new("Frame")
XTitleBar.Size = UDim2.new(1, 0, 0, 35)
XTitleBar.BackgroundColor3 = Color3.fromRGB(30, 5, 5)
XTitleBar.Parent = XMenu
Instance.new("UICorner", XTitleBar).CornerRadius = UDim.new(0, 12)

local XTitleText = Instance.new("TextLabel")
XTitleText.Text = "X MENU | V45"
XTitleText.Size = UDim2.new(1, -80, 1, 0)
XTitleText.Position = UDim2.new(0, 10, 0, 0)
XTitleText.BackgroundTransparency = 1
XTitleText.TextColor3 = Color3.fromRGB(255, 50, 50)
XTitleText.Font = Enum.Font.GothamBold
XTitleText.TextSize = 14
XTitleText.TextXAlignment = Enum.TextXAlignment.Left
XTitleText.Parent = XTitleBar

local XMinBtn = Instance.new("TextButton")
XMinBtn.Text = "-"
XMinBtn.Size = UDim2.new(0, 25, 0, 25)
XMinBtn.Position = UDim2.new(1, -60, 0, 5)
XMinBtn.BackgroundColor3 = Color3.fromRGB(180, 130, 0)
XMinBtn.TextColor3 = Color3.fromRGB(255,255,255)
XMinBtn.Font = Enum.Font.GothamBold
XMinBtn.TextSize = 16
XMinBtn.Parent = XTitleBar
Instance.new("UICorner", XMinBtn).CornerRadius = UDim.new(0, 6)

local XCloseBtn = Instance.new("TextButton")
XCloseBtn.Text = "X"
XCloseBtn.Size = UDim2.new(0, 25, 0, 25)
XCloseBtn.Position = UDim2.new(1, -30, 0, 5)
XCloseBtn.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
XCloseBtn.TextColor3 = Color3.fromRGB(255,255,255)
XCloseBtn.Font = Enum.Font.GothamBold
XCloseBtn.TextSize = 14
XCloseBtn.Parent = XTitleBar
Instance.new("UICorner", XCloseBtn).CornerRadius = UDim.new(0, 6)

MakeDraggable(XMenu)

local XLeftMenu = Instance.new("ScrollingFrame")
XLeftMenu.Size = UDim2.new(0, 130, 1, -35)
XLeftMenu.Position = UDim2.new(0, 0, 0, 35)
XLeftMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
XLeftMenu.BorderSizePixel = 0
XLeftMenu.ScrollBarThickness = 3
XLeftMenu.CanvasSize = UDim2.new(0, 0, 0, 0)
XLeftMenu.Parent = XMenu

local LeftMenuLayout = Instance.new("UIListLayout")
LeftMenuLayout.Padding = UDim.new(0, 4)
LeftMenuLayout.Parent = XLeftMenu

LeftMenuLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    XLeftMenu.CanvasSize = UDim2.new(0, 0, 0, LeftMenuLayout.AbsoluteContentSize.Y + 10)
end)

local function CreateTabBtn(text)
    local btn = Instance.new("TextButton")
    btn.Text = text
    btn.Size = UDim2.new(1, -10, 0, 32)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    btn.TextColor3 = Color3.fromRGB(200, 200, 200)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.Parent = XLeftMenu
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local TabFling = CreateTabBtn("Fling")
local TabAI = CreateTabBtn("AI")
local TabFly = CreateTabBtn("Fly/Noclip")
local TabWaypoint = CreateTabBtn("Waypoint")
local TabTrack = CreateTabBtn("Takip")
local TabQueue = CreateTabBtn("Fling Sirasi")
local TabPlayers = CreateTabBtn("Oyuncular")
local TabSettings = CreateTabBtn("Ayarlar")
local TabGarage = CreateTabBtn("Garaj")
local TabKillcam = CreateTabBtn("Killcam")
local TabStats = CreateTabBtn("Istatistik")

local XMidPanel = Instance.new("Frame")
XMidPanel.Size = UDim2.new(1, -130, 1, -35)
XMidPanel.Position = UDim2.new(0, 130, 0, 35)
XMidPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
XMidPanel.Parent = XMenu

local function CreatePage()
    local p = Instance.new("ScrollingFrame")
    p.Size = UDim2.new(1, 0, 1, 0)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 3
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    p.Visible = false
    p.Parent = XMidPanel
    return p
end

local PageFling = CreatePage()
local PageAI = CreatePage()
local PageFly = CreatePage()
local PageWaypoint = CreatePage()
local PageTrack = CreatePage()
local PageQueue = CreatePage()
local PagePlayers = CreatePage()
local PageSettings = CreatePage()
local PageGarage = CreatePage()
local PageKillcam = CreatePage()
local PageStats = CreatePage()

local AllPages = {PageFling, PageAI, PageFly, PageWaypoint, PageTrack, PageQueue, PagePlayers, PageSettings, PageGarage, PageKillcam, PageStats}
local AllTabs = {TabFling, TabAI, TabFly, TabWaypoint, TabTrack, TabQueue, TabPlayers, TabSettings, TabGarage, TabKillcam, TabStats}

local function SwitchTab(activePage, activeBtn)
    for _, p in ipairs(AllPages) do p.Visible = false end
    for _, b in ipairs(AllTabs) do
        b.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        b.TextColor3 = Color3.fromRGB(200, 200, 200)
    end
    activePage.Visible = true
    activeBtn.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
    activeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
end

TabFling.MouseButton1Click:Connect(function() SwitchTab(PageFling, TabFling) end)
TabAI.MouseButton1Click:Connect(function() SwitchTab(PageAI, TabAI) end)
TabFly.MouseButton1Click:Connect(function() SwitchTab(PageFly, TabFly) end)
TabWaypoint.MouseButton1Click:Connect(function() SwitchTab(PageWaypoint, TabWaypoint) end)
TabTrack.MouseButton1Click:Connect(function() SwitchTab(PageTrack, TabTrack) end)
TabQueue.MouseButton1Click:Connect(function() SwitchTab(PageQueue, TabQueue) end)
TabPlayers.MouseButton1Click:Connect(function() SwitchTab(PagePlayers, TabPlayers) end)
TabSettings.MouseButton1Click:Connect(function() SwitchTab(PageSettings, TabSettings) end)
TabGarage.MouseButton1Click:Connect(function() SwitchTab(PageGarage, TabGarage) end)
TabKillcam.MouseButton1Click:Connect(function() SwitchTab(PageKillcam, TabKillcam) end)
TabStats.MouseButton1Click:Connect(function() SwitchTab(PageStats, TabStats) end)

local function CreatePageLayout(page)
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
    end)
end

CreatePageLayout(PageFling)
CreatePageLayout(PageAI)
CreatePageLayout(PageFly)
CreatePageLayout(PageWaypoint)
CreatePageLayout(PageTrack)
CreatePageLayout(PageQueue)
CreatePageLayout(PagePlayers)
CreatePageLayout(PageSettings)
CreatePageLayout(PageGarage)
CreatePageLayout(PageKillcam)
CreatePageLayout(PageStats)

local function CreateBtn(parent, text, color, order)
    local btn = Instance.new("TextButton")
    btn.Text = text
    btn.Size = UDim2.new(1, -20, 0, 32)
    btn.BackgroundColor3 = color
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.LayoutOrder = order or 0
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    return btn
end

local function CreateInput(parent, placeholder, order)
    local box = Instance.new("TextBox")
    box.PlaceholderText = placeholder
    box.Size = UDim2.new(1, -20, 0, 28)
    box.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    box.TextColor3 = Color3.fromRGB(255,255,255)
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.LayoutOrder = order or 0
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
    return box
end

local function CreateLabel(parent, text, color, order)
    local lbl = Instance.new("TextLabel")
    lbl.Text = text
    lbl.Size = UDim2.new(1, -20, 0, 22)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = color or Color3.fromRGB(200,200,200)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = order or 0
    lbl.Parent = parent
    return lbl
end

-- ===== SAYFA FLING =====
CreateLabel(PageFling, "FLING KONTROLLERI", Color3.fromRGB(255, 100, 100), 1)
local FlingBtn = CreateBtn(PageFling, "TUMUNU UCUR", Color3.fromRGB(200, 0, 0), 2)
local NormalFlingBtn = CreateBtn(PageFling, "FLING AC (Normal)", Color3.fromRGB(0, 80, 80), 3)
local ClickBtn = CreateBtn(PageFling, "CLICK FLING: KAPALI", Color3.fromRGB(120, 20, 20), 4)
CreateLabel(PageFling, "Fling Gucu (100-50000):", nil, 5)
local PowerInput = CreateInput(PageFling, "2000", 6)
local PowerSetBtn = CreateBtn(PageFling, "GUCU AYARLA", Color3.fromRGB(20, 80, 20), 7)
CreateLabel(PageFling, "Menzil:", nil, 8)
local RangeInput = CreateInput(PageFling, "50", 9)
local RangeSetBtn = CreateBtn(PageFling, "MENZILI AYARLA", Color3.fromRGB(20, 80, 20), 10)
CreateLabel(PageFling, "Hasar:", nil, 11)
local DamageInput = CreateInput(PageFling, "50", 12)
local DamageSetBtn = CreateBtn(PageFling, "HASARI AYARLA", Color3.fromRGB(20, 80, 20), 13)
CreateLabel(PageFling, "Spin Hizi:", nil, 14)
local SpeedInput = CreateInput(PageFling, "500", 15)
local SpeedSetBtn = CreateBtn(PageFling, "SPIN HIZINI AYARLA", Color3.fromRGB(20, 80, 20), 16)
local CancelBtn = CreateBtn(PageFling, "TUMUNU IPTAL ET", Color3.fromRGB(80, 20, 20), 17)

-- ===== SAYFA AI =====
CreateLabel(PageAI, "AI SISTEMI", Color3.fromRGB(200, 100, 255), 1)
local AIBtn = CreateBtn(PageAI, "AI: KAPALI", Color3.fromRGB(80, 0, 120), 2)
local AIModeBtn = CreateBtn(PageAI, "MOD: OTO", Color3.fromRGB(60, 0, 80), 3)
local PatrolAddBtn = CreateBtn(PageAI, "DEVIRIYE NOKTASI EKLE", Color3.fromRGB(40, 40, 100), 4)
CreateLabel(PageAI, "AI aktifken arac hedefe kendi gider.", Color3.fromRGB(0, 200, 255), 5)

-- ===== SAYFA FLY =====
CreateLabel(PageFly, "UCUS KONTROLLERI", Color3.fromRGB(100, 200, 255), 1)
local FlyBtn = CreateBtn(PageFly, "FLY: KAPALI", Color3.fromRGB(120, 20, 20), 2)
local NoclipBtn = CreateBtn(PageFly, "NOCLIP: KAPALI", Color3.fromRGB(80, 30, 30), 3)
local RespawnBtn = CreateBtn(PageFly, "RESPAWN: KAPALI", Color3.fromRGB(60, 60, 60), 4)
CreateLabel(PageFly, "Ucus Hizi:", nil, 5)
local FlySpeedInput = CreateInput(PageFly, "70", 6)
local FlySpeedSetBtn = CreateBtn(PageFly, "UCUS HIZINI AYARLA", Color3.fromRGB(20, 80, 20), 7)

-- ===== SAYFA WAYPOINT =====
CreateLabel(PageWaypoint, "YOL NOKTALARI", Color3.fromRGB(255, 200, 100), 1)
local Point1Btn = CreateBtn(PageWaypoint, "1. NOKTayi KAYDET", Color3.fromRGB(30, 60, 30), 2)
local Point2Btn = CreateBtn(PageWaypoint, "2. NOKTayi KAYDET", Color3.fromRGB(30, 60, 30), 3)
local GoPoint1Btn = CreateBtn(PageWaypoint, "1. NOKTaya GIT", Color3.fromRGB(20, 120, 20), 4)
local GoPoint2Btn = CreateBtn(PageWaypoint, "2. NOKTaya GIT", Color3.fromRGB(120, 50, 20), 5)
local WaypointLoopBtn = CreateBtn(PageWaypoint, "SUREKLI TUR: KAPALI", Color3.fromRGB(60, 60, 20), 6)
CreateLabel(PageWaypoint, "Yol Hizi:", nil, 7)
local SpeedInputWaypoint = CreateInput(PageWaypoint, "90", 8)
local SpeedSetBtnWaypoint = CreateBtn(PageWaypoint, "YOL HIZINI AYARLA", Color3.fromRGB(20, 80, 20), 9)

-- ===== SAYFA TAKIP =====
CreateLabel(PageTrack, "TAKIP / HEDEF", Color3.fromRGB(100, 255, 200), 1)
local TargetBtn = CreateBtn(PageTrack, "HEDEF BELIRLE", Color3.fromRGB(30, 30, 80), 2)
local SelectPlayerBtn = CreateBtn(PageTrack, "OYUNCU SEC", Color3.fromRGB(30, 80, 30), 3)
local FollowBtn = CreateBtn(PageTrack, "TAKIP: KAPALI", Color3.fromRGB(70, 30, 70), 4)
local GotoBtn = CreateBtn(PageTrack, "GEMIYI GETIR", Color3.fromRGB(0, 80, 80), 5)

-- ===== SAYFA KUYRUK =====
CreateLabel(PageQueue, "FLING SIRASI", Color3.fromRGB(255, 200, 0), 1)
local QueueScroll = Instance.new("ScrollingFrame")
QueueScroll.Size = UDim2.new(1, -20, 0, 200)
QueueScroll.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
QueueScroll.BorderSizePixel = 0
QueueScroll.ScrollBarThickness = 4
QueueScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
QueueScroll.LayoutOrder = 2
QueueScroll.Parent = PageQueue
Instance.new("UICorner", QueueScroll).CornerRadius = UDim.new(0, 8)
local QueueLayout = Instance.new("UIListLayout")
QueueLayout.Padding = UDim.new(0, 3)
QueueLayout.Parent = QueueScroll
local AutoPilotBtn = CreateBtn(PageQueue, "ARAC FLING (AUTO-PILOT)", Color3.fromRGB(0, 120, 200), 3)
local QueueCancelBtn = CreateBtn(PageQueue, "SIRAYI TEMIZLE", Color3.fromRGB(180, 0, 0), 4)

local function UpdateQueueUI()
    for _, child in ipairs(QueueScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    for i, name in ipairs(FlingQueue) do
        local btn = Instance.new("TextButton")
        btn.Text = i .. ". " .. name .. " [X]"
        btn.Size = UDim2.new(1, 0, 0, 26)
        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.Parent = QueueScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
        btn.MouseButton1Click:Connect(function()
            for j, n in ipairs(FlingQueue) do
                if n == name then table.remove(FlingQueue, j) break end
            end
            SetStatus("Cikarildi: " .. name, Color3.fromRGB(255,100,0))
            UpdateQueueUI()
        end)
    end
    QueueScroll.CanvasSize = UDim2.new(0, 0, 0, #FlingQueue * 30)
end

-- ===== SAYFA OYUNCULAR =====
CreateLabel(PagePlayers, "OYUNCU LISTESI", Color3.fromRGB(0, 200, 255), 1)
local PlayerScroll = Instance.new("ScrollingFrame")
PlayerScroll.Size = UDim2.new(1, -20, 0, 300)
PlayerScroll.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
PlayerScroll.BorderSizePixel = 0
PlayerScroll.ScrollBarThickness = 4
PlayerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayerScroll.LayoutOrder = 2
PlayerScroll.Parent = PagePlayers
Instance.new("UICorner", PlayerScroll).CornerRadius = UDim.new(0, 8)
local PlayerLayout = Instance.new("UIListLayout")
PlayerLayout.Padding = UDim.new(0, 3)
PlayerLayout.Parent = PlayerScroll

local function RefreshPlayerList()
    for _, child in ipairs(PlayerScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            count = count + 1
            local kd = KillTracker.GetKD(player)
            local btn = Instance.new("TextButton")
            btn.Text = player.Name .. " [K/D: " .. string.format("%.2f", kd) .. "]"
            btn.Size = UDim2.new(1, 0, 0, 28)
            btn.BackgroundColor3 = Color3.fromRGB(35, 35, 60)
            btn.TextColor3 = Color3.fromRGB(255,255,255)
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 11
            btn.Parent = PlayerScroll
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
            btn.MouseButton1Click:Connect(function()
                local exists = false
                for _, n in ipairs(FlingQueue) do
                    if n == player.Name then exists = true break end
                end
                if exists then SetStatus("Zaten sirada!", Color3.fromRGB(255,200,0)) return end
                table.insert(FlingQueue, player.Name)
                SetStatus("Eklendi: " .. player.Name, Color3.fromRGB(0,255,0))
                UpdateQueueUI()
            end)
        end
    end
    PlayerScroll.CanvasSize = UDim2.new(0, 0, 0, count * 32)
end

Players.PlayerAdded:Connect(function() task.wait(0.5) RefreshPlayerList() end)
Players.PlayerRemoving:Connect(function() task.wait(0.5) RefreshPlayerList() end)

-- ===== SAYFA AYARLAR =====
CreateLabel(PageSettings, "GELISMIS AYARLAR", Color3.fromRGB(200, 200, 200), 1)
local AntiDetectBtn = CreateBtn(PageSettings, "Anti-Detection: KAPALI", Color3.fromRGB(60, 0, 60), 2)
local BanSafeBtn = CreateBtn(PageSettings, "Ban-Safe Mod: KAPALI", Color3.fromRGB(60, 0, 60), 3)
CreateLabel(PageSettings, "Anti-Detection: Fling gecikmeli yapilir", Color3.fromRGB(255, 200, 0), 4)
CreateLabel(PageSettings, "Ban-Safe: Hasar vermez, sadece ucurur", Color3.fromRGB(255, 200, 0), 5)

-- ===== SAYFA GARAJ =====
CreateLabel(PageGarage, "ARAC GARAJ", Color3.fromRGB(255, 150, 50), 1)
local ColorRedBtn = CreateBtn(PageGarage, "Kirmizi Yap", Color3.fromRGB(200, 0, 0), 2)
local ColorBlueBtn = CreateBtn(PageGarage, "Mavi Yap", Color3.fromRGB(0, 50, 200), 3)
local ColorGreenBtn = CreateBtn(PageGarage, "Yesil Yap", Color3.fromRGB(0, 150, 0), 4)
local ColorRandomBtn = CreateBtn(PageGarage, "Rastgele Renk", Color3.fromRGB(100, 50, 150), 5)
CreateLabel(PageGarage, "Aractayken renk degistirir", Color3.fromRGB(200, 200, 100), 6)

-- ===== SAYFA KILLCAM =====
CreateLabel(PageKillcam, "KILLCAM / REPLAY", Color3.fromRGB(200, 100, 100), 1)
local StartRecordBtn = CreateBtn(PageKillcam, "KAYDI BASLAT", Color3.fromRGB(150, 0, 0), 2)
local StopRecordBtn = CreateBtn(PageKillcam, "KAYDI DURDUR", Color3.fromRGB(80, 80, 80), 3)
local PlayRecordBtn = CreateBtn(PageKillcam, "KAYDI OYNAT (3 sn)", Color3.fromRGB(0, 120, 0), 4)
CreateLabel(PageKillcam, "Aractayken kayit yapar, sonra replay", Color3.fromRGB(200, 200, 100), 5)

-- ===== SAYFA ISTATISTIK =====
CreateLabel(PageStats, "SESSION ISTATISTIKLERI", Color3.fromRGB(100, 255, 200), 1)
local StatsInfoLabel = CreateLabel(PageStats, "K: 0 | D: 0 | K/D: 0.00", Color3.fromRGB(255, 255, 255), 2)
local MVPBtn = CreateBtn(PageStats, "MVP HESAPLA", Color3.fromRGB(200, 150, 0), 3)
local ResetStatsBtn = CreateBtn(PageStats, "ISTATISTIKLERI SIFIRLA", Color3.fromRGB(100, 50, 50), 4)

-- ===== AUTO-PILOT =====
local function StartAutoPilot()
    if #FlingQueue == 0 then SetStatus("Sira bos!", Color3.fromRGB(255,0,0)) return end
    if isAutoPilotActive then
        isAutoPilotActive = false
        AutoPilotBtn.Text = "ARAC FLING (AUTO-PILOT)"
        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
        SetStatus("AUTO-PILOT DURDU", Color3.fromRGB(255,200,0))
        return
    end
    isAutoPilotActive = true
    currentQueueIndex = 1
    AutoPilotBtn.Text = "DURDUR (AKTIF)"
    AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    SetStatus("AUTO-PILOT BASLADI!", Color3.fromRGB(0,255,0))
    spawn(function()
        while isAutoPilotActive and currentQueueIndex <= #FlingQueue do
            local targetName = FlingQueue[currentQueueIndex]
            local targetPlayer = Players:FindFirstChild(targetName)
            if targetPlayer and targetPlayer.Character then
                local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                local targetHumanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
                if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
                    SetStatus("Hedefe gidiliyor: " .. targetName, Color3.fromRGB(0,200,255))
                    local vehicle = GetVehicle()
                    if vehicle then
                        local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
                        if mainPart then
                            local targetPos = targetRoot.Position + Vector3.new(0, 3, 0)
                            mainPart.CFrame = CFrame.new(targetPos)
                            mainPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
                            task.wait(0.2)
                            local power = Settings.FlingPower
                            targetRoot.AssemblyLinearVelocity = Vector3.new(math.random(-power,power), math.random(power/2,power*1.5), math.random(-power,power))
                            targetRoot.AssemblyAngularVelocity = Vector3.new(math.random(-500,500), math.random(-500,500), math.random(-500,500))
                            targetHumanoid.Health = math.max(0, targetHumanoid.Health - Settings.FlingDamage)
                            CreateFlingEffect(targetRoot.Position)
                            PlayFlingSound(targetRoot.Position)
                            SetStatus("Ucuruldu: " .. targetName, Color3.fromRGB(255,100,0))
                            task.wait(0.5)
                        end
                    else
                        SetStatus("Arac yok!", Color3.fromRGB(255,0,0))
                        isAutoPilotActive = false
                        AutoPilotBtn.Text = "ARAC FLING (AUTO-PILOT)"
                        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
                        return
                    end
                end
            end
            currentQueueIndex = currentQueueIndex + 1
            task.wait(0.3)
        end
        isAutoPilotActive = false
        AutoPilotBtn.Text = "ARAC FLING (AUTO-PILOT)"
        AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
        SetStatus("SIRA TAMAMLANDI!", Color3.fromRGB(0,255,0))
    end)
end

AutoPilotBtn.MouseButton1Click:Connect(StartAutoPilot)
QueueCancelBtn.MouseButton1Click:Connect(function()
    isAutoPilotActive = false
    FlingQueue = {}
    currentQueueIndex = 1
    UpdateQueueUI()
    SetStatus("SIRA TEMIZLENDI!", Color3.fromRGB(0,255,0))
end)

-- ===== BUTON ISLEVLERI =====
PowerSetBtn.MouseButton1Click:Connect(function()
    local val = tonumber(PowerInput.Text)
    if val and val >= Settings.MinFlingPower and val <= Settings.MaxFlingPower then
        Settings.FlingPower = val
        SetStatus("GUC: " .. val, Color3.fromRGB(0,255,0))
        PowerInput.Text = ""
    else SetStatus("Gecersiz!", Color3.fromRGB(255,0,0)) end
end)

RangeSetBtn.MouseButton1Click:Connect(function()
    local val = tonumber(RangeInput.Text)
    if val and val >= 1 then
        Settings.FlingRange = val
        SetStatus("MENZIL: " .. val, Color3.fromRGB(0,255,0))
        RangeInput.Text = ""
    end
end)

DamageSetBtn.MouseButton1Click:Connect(function()
    local val = tonumber(DamageInput.Text)
    if val and val >= 0 then
        Settings.FlingDamage = val
        SetStatus("HASAR: " .. val, Color3.fromRGB(0,255,0))
        DamageInput.Text = ""
    end
end)

SpeedSetBtn.MouseButton1Click:Connect(function()
    local val = tonumber(SpeedInput.Text)
    if val and val >= 1 then
        Settings.MaxSpinSpeed = val
        SetStatus("SPIN: " .. val, Color3.fromRGB(0,255,0))
        SpeedInput.Text = ""
    end
end)

FlySpeedSetBtn.MouseButton1Click:Connect(function()
    local val = tonumber(FlySpeedInput.Text)
    if val and val >= 1 then
        Settings.FlySpeed = val
        SetStatus("UCUS: " .. val, Color3.fromRGB(0,255,0))
        FlySpeedInput.Text = ""
    end
end)

SpeedSetBtnWaypoint.MouseButton1Click:Connect(function()
    local val = tonumber(SpeedInputWaypoint.Text)
    if val and val >= 1 then
        Settings.WaypointSpeed = val
        SetStatus("YOL HIZI: " .. val, Color3.fromRGB(0,255,0))
        SpeedInputWaypoint.Text = ""
    end
end)

FlingBtn.MouseButton1Click:Connect(function()
    Settings.IsFlingEveryone = not Settings.IsFlingEveryone
    Settings.IsNormalFling = false
    NormalFlingBtn.Text = "FLING AC (Normal)"
    NormalFlingBtn.BackgroundColor3 = Color3.fromRGB(0,80,80)
    FlingBtn.Text = Settings.IsFlingEveryone and "UCUYOR!" or "TUMUNU UCUR"
    FlingBtn.BackgroundColor3 = Settings.IsFlingEveryone and Color3.fromRGB(0,200,0) or Color3.fromRGB(200,0,0)
    SetStatus(Settings.IsFlingEveryone and "HERKES UCUYOR!" or "DURDU", Settings.IsFlingEveryone and Color3.fromRGB(255,200,0) or Color3.fromRGB(255,0,0))
end)

NormalFlingBtn.MouseButton1Click:Connect(function()
    Settings.IsNormalFling = not Settings.IsNormalFling
    Settings.IsFlingEveryone = false
    FlingBtn.Text = "TUMUNU UCUR"
    FlingBtn.BackgroundColor3 = Color3.fromRGB(200,0,0)
    NormalFlingBtn.Text = Settings.IsNormalFling and "FLING:ON!" or "FLING AC (Normal)"
    NormalFlingBtn.BackgroundColor3 = Settings.IsNormalFling and Color3.fromRGB(0,200,200) or Color3.fromRGB(0,80,80)
    SetStatus(Settings.IsNormalFling and "FLING AKTIF!" or "DURDU", Settings.IsNormalFling and Color3.fromRGB(0,200,200) or Color3.fromRGB(255,0,0))
end)

ClickBtn.MouseButton1Click:Connect(function()
    Settings.ClickFlingActive = not Settings.ClickFlingActive
    ClickBtn.Text = Settings.ClickFlingActive and "CLICK: ACIK" or "CLICK FLING: KAPALI"
    ClickBtn.BackgroundColor3 = Settings.ClickFlingActive and Color3.fromRGB(20,150,20) or Color3.fromRGB(120,20,20)
end)

CancelBtn.MouseButton1Click:Connect(function()
    Settings.IsFlingEveryone = false
    Settings.IsNormalFling = false
    Settings.IsWaypointRunning = false
    Settings.IsFlying = false
    Settings.ClickFlingActive = false
    Settings.UseBanSafe = false
    Settings.AntiDetection = false
    State.isFollowingPlayer = false
    State.targetPosition = nil
    State.targetPlayer = nil
    State.killCount = 0
    if KillLabel then KillLabel.Text = "Kill: 0" end
    AIData.Enabled = false
    AIData.Target = nil
    AIData.PatrolPoints = {}
    isAutoPilotActive = false
    FlingQueue = {}
    UpdateQueueUI()
    FlingBtn.Text = "TUMUNU UCUR"
    FlingBtn.BackgroundColor3 = Color3.fromRGB(200,0,0)
    NormalFlingBtn.Text = "FLING AC (Normal)"
    NormalFlingBtn.BackgroundColor3 = Color3.fromRGB(0,80,80)
    WaypointLoopBtn.Text = "SUREKLI TUR: KAPALI"
    WaypointLoopBtn.BackgroundColor3 = Color3.fromRGB(60,60,20)
    FlyBtn.Text = "FLY: KAPALI"
    FlyBtn.BackgroundColor3 = Color3.fromRGB(120,20,20)
    ClickBtn.Text = "CLICK FLING: KAPALI"
    ClickBtn.BackgroundColor3 = Color3.fromRGB(120,20,20)
    AIBtn.Text = "AI: KAPALI"
    AIBtn.BackgroundColor3 = Color3.fromRGB(80,0,120)
    AIModeBtn.Text = "MOD: OTO"
    AutoPilotBtn.Text = "ARAC FLING (AUTO-PILOT)"
    AutoPilotBtn.BackgroundColor3 = Color3.fromRGB(0,120,200)
    UnanchorVehicle()
    SetStatus("IPTAL", Color3.fromRGB(0,255,0))
end)

FlyBtn.MouseButton1Click:Connect(function()
    Settings.IsFlying = not Settings.IsFlying
    FlyBtn.Text = Settings.IsFlying and "FLY: ACIK" or "FLY: KAPALI"
    FlyBtn.BackgroundColor3 = Settings.IsFlying and Color3.fromRGB(20,150,20) or Color3.fromRGB(120,20,20)
end)

NoclipBtn.MouseButton1Click:Connect(function()
    Settings.NoclipActive = not Settings.NoclipActive
    NoclipBtn.Text = Settings.NoclipActive and "NOCLIP: ACIK" or "NOCLIP: KAPALI"
    NoclipBtn.BackgroundColor3 = Settings.NoclipActive and Color3.fromRGB(20,150,20) or Color3.fromRGB(80,30,30)
    State.lastNoclipState = nil
end)

RespawnBtn.MouseButton1Click:Connect(function()
    Settings.RespawnProtection = not Settings.RespawnProtection
    RespawnBtn.Text = Settings.RespawnProtection and "RESPAWN: ACIK" or "RESPAWN: KAPALI"
    RespawnBtn.BackgroundColor3 = Settings.RespawnProtection and Color3.fromRGB(0,200,0) or Color3.fromRGB(60,60,60)
end)

AIBtn.MouseButton1Click:Connect(function()
    AIData.Enabled = not AIData.Enabled
    AIBtn.Text = AIData.Enabled and "AI: ACIK" or "AI: KAPALI"
    AIBtn.BackgroundColor3 = AIData.Enabled and Color3.fromRGB(150,0,200) or Color3.fromRGB(80,0,120)
    if AIData.Enabled then
        AIData.Mode = "auto"
        AIModeBtn.Text = "MOD: OTO"
        SetStatus("AI AKTIF!", Color3.fromRGB(200,0,255))
    else
        AIData.Target = nil
        SetStatus("AI KAPALI", Color3.fromRGB(150,150,150))
    end
end)

AIModeBtn.MouseButton1Click:Connect(function()
    local modes = {"auto", "aggressive", "defensive", "patrol"}
    local names = {"MOD: OTO", "MOD: AGRESIF", "MOD: DEFANSIF", "MOD: DEVIRIYE"}
    local idx = 1
    for i, m in ipairs(modes) do
        if m == AIData.Mode then idx = i break end
    end
    idx = idx % #modes + 1
    AIData.Mode = modes[idx]
    AIModeBtn.Text = names[idx]
    SetStatus("MOD: " .. names[idx], Color3.fromRGB(200,0,255))
end)

PatrolAddBtn.MouseButton1Click:Connect(function()
    if #AIData.PatrolPoints >= AIData.MaxPatrolPoints then
        SetStatus("Max nokta!", Color3.fromRGB(255,0,0))
        return
    end
    local char = LocalPlayer.Character
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            table.insert(AIData.PatrolPoints, root.CFrame)
            SetStatus("Nokta " .. #AIData.PatrolPoints, Color3.fromRGB(0,255,0))
        end
    end
end)

Point1Btn.MouseButton1Click:Connect(function()
    local char = LocalPlayer.Character
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            WaypointData.Point1 = root.CFrame
            Point1Btn.Text = "1. NOKTA KAYITLI"
            Point1Btn.BackgroundColor3 = Color3.fromRGB(0,200,0)
            SetStatus("1. Nokta kaydedildi!", Color3.fromRGB(0,255,0))
        end
    end
end)

Point2Btn.MouseButton1Click:Connect(function()
    local char = LocalPlayer.Character
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            WaypointData.Point2 = root.CFrame
            Point2Btn.Text = "2. NOKTA KAYITLI"
            Point2Btn.BackgroundColor3 = Color3.fromRGB(0,200,0)
            SetStatus("2. Nokta kaydedildi!", Color3.fromRGB(0,255,0))
        end
    end
end)

WaypointLoopBtn.MouseButton1Click:Connect(function()
    if Settings.IsWaypointRunning then
        Settings.IsWaypointRunning = false
        WaypointLoopBtn.Text = "SUREKLI TUR: KAPALI"
        WaypointLoopBtn.BackgroundColor3 = Color3.fromRGB(60,60,20)
        SetStatus("SUREKLI DURDU", Color3.fromRGB(255,200,0))
        UnanchorVehicle()
    else
        if WaypointData.Point1 and WaypointData.Point2 then
            Settings.IsWaypointRunning = true
            Settings.WaypointDirection = 1
            UnanchorVehicle()
            WaypointLoopBtn.Text = "SUREKLI: ACIK"
            WaypointLoopBtn.BackgroundColor3 = Color3.fromRGB(200,0,0)
            SetStatus("SUREKLI YOL!", Color3.fromRGB(255,200,0))
        else
            SetStatus("1. ve 2. noktayi kaydet!", Color3.fromRGB(255,0,0))
        end
    end
end)

GoPoint1Btn.MouseButton1Click:Connect(function()
    if not WaypointData.Point1 then
        SetStatus("1. nokta yok!", Color3.fromRGB(255,0,0))
        return
    end
    local vehicle = GetVehicle()
    if not vehicle then return end
    local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
    if not mainPart then return end
    if VehicleData.IsAnchored then UnanchorVehicle() end
    local targetPos = WaypointData.Point1.Position + Vector3.new(0, 2, 0)
    local distance = (targetPos - mainPart.Position).Magnitude
    local time = math.max(0.1, distance / Settings.WaypointSpeed)
    mainPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
    TweenService:Create(mainPart, TweenInfo.new(time, Enum.EasingStyle.Linear), {CFrame=CFrame.new(targetPos)}):Play()
    SetStatus("1. Noktaya gidiliyor!", Color3.fromRGB(0,255,0))
end)

GoPoint2Btn.MouseButton1Click:Connect(function()
    if not WaypointData.Point2 then
        SetStatus("2. nokta yok!", Color3.fromRGB(255,0,0))
        return
    end
    local vehicle = GetVehicle()
    if not vehicle then return end
    local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
    if not mainPart then return end
    if VehicleData.IsAnchored then UnanchorVehicle() end
    local targetPos = WaypointData.Point2.Position + Vector3.new(0, 2, 0)
    local distance = (targetPos - mainPart.Position).Magnitude
    local time = math.max(0.1, distance / Settings.WaypointSpeed)
    mainPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
    TweenService:Create(mainPart, TweenInfo.new(time, Enum.EasingStyle.Linear), {CFrame=CFrame.new(targetPos)}):Play()
    SetStatus("2. Noktaya gidiliyor!", Color3.fromRGB(0,255,0))
end)

AntiDetectBtn.MouseButton1Click:Connect(function()
    Settings.AntiDetection = not Settings.AntiDetection
    AntiDetectBtn.Text = Settings.AntiDetection and "Anti-Detection: ACIK" or "Anti-Detection: KAPALI"
    AntiDetectBtn.BackgroundColor3 = Settings.AntiDetection and Color3.fromRGB(150,0,200) or Color3.fromRGB(60,0,60)
end)

BanSafeBtn.MouseButton1Click:Connect(function()
    Settings.UseBanSafe = not Settings.UseBanSafe
    BanSafeBtn.Text = Settings.UseBanSafe and "Ban-Safe: ACIK" or "Ban-Safe Mod: KAPALI"
    BanSafeBtn.BackgroundColor3 = Settings.UseBanSafe and Color3.fromRGB(150,0,200) or Color3.fromRGB(60,0,60)
end)

TargetBtn.MouseButton1Click:Connect(function()
    State.isSelectingTarget = true
    TargetBtn.Text = "TIKLA"
    TargetBtn.BackgroundColor3 = Color3.fromRGB(200,150,0)
    SetStatus("Bir yere tikla!", Color3.fromRGB(255,200,0))
end)

SelectPlayerBtn.MouseButton1Click:Connect(function()
    State.isSelectingPlayer = true
    SelectPlayerBtn.Text = "TIKLA"
    SelectPlayerBtn.BackgroundColor3 = Color3.fromRGB(0,200,0)
    SetStatus("Bir oyuncuya tikla!", Color3.fromRGB(0,200,0))
end)

FollowBtn.MouseButton1Click:Connect(function()
    if State.targetPlayer then
        State.isFollowingPlayer = not State.isFollowingPlayer
        FollowBtn.Text = State.isFollowingPlayer and "TAKIP: ACIK" or "TAKIP: KAPALI"
        FollowBtn.BackgroundColor3 = State.isFollowingPlayer and Color3.fromRGB(0,200,200) or Color3.fromRGB(70,30,70)
    else
        SetStatus("Once oyuncu sec!", Color3.fromRGB(255,0,0))
    end
end)

GotoBtn.MouseButton1Click:Connect(function()
    local vehicle = GetVehicle()
    if not vehicle then
        SetStatus("GEMI YOK!", Color3.fromRGB(255,0,0))
        return
    end
    local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
    if not mainPart then return end
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    TweenService:Create(mainPart, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {CFrame = root.CFrame + Vector3.new(0, 2, 0)}):Play()
    SetStatus("GEMI GELDI!", Color3.fromRGB(0,255,0))
end)

local function ApplyColorToVehicle(color)
    local vehicle = GetVehicle()
    if not vehicle then
        SetStatus("Arac yok!", Color3.fromRGB(255,0,0))
        return
    end
    for _, part in ipairs(vehicle:GetDescendants()) do
        if part:IsA("BasePart") and not part.Parent:FindFirstChildOfClass("Humanoid") then
            pcall(function() part.Color = color end)
        end
    end
    SetStatus("Arac rengi degisti!", Color3.fromRGB(0,255,0))
end

ColorRedBtn.MouseButton1Click:Connect(function() ApplyColorToVehicle(Color3.fromRGB(200, 0, 0)) end)
ColorBlueBtn.MouseButton1Click:Connect(function() ApplyColorToVehicle(Color3.fromRGB(0, 50, 200)) end)
ColorGreenBtn.MouseButton1Click:Connect(function() ApplyColorToVehicle(Color3.fromRGB(0, 150, 0)) end)
ColorRandomBtn.MouseButton1Click:Connect(function()
    ApplyColorToVehicle(Color3.fromRGB(math.random(0,255), math.random(0,255), math.random(0,255)))
end)

StartRecordBtn.MouseButton1Click:Connect(function()
    KillcamBuffer = {}
    StartKillcamRecording()
    SetStatus("Kayit basladi!", Color3.fromRGB(255,100,0))
end)

StopRecordBtn.MouseButton1Click:Connect(function()
    StopKillcamRecording()
    SetStatus("Kayit durdu (" .. #KillcamBuffer .. " frame)", Color3.fromRGB(200,200,200))
end)

PlayRecordBtn.MouseButton1Click:Connect(function()
    if #KillcamBuffer == 0 then
        SetStatus("Kayit yok!", Color3.fromRGB(255,0,0))
        return
    end
    SetStatus("Replay oynatiliyor...", Color3.fromRGB(0,255,0))
    local vehicle = GetVehicle()
    if vehicle then
        local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
        if mainPart then
            PlayKillcam(mainPart)
        end
    end
end)

MVPBtn.MouseButton1Click:Connect(function()
    local mvp, score = KillTracker.CalculateMVP()
    if mvp then
        SetStatus("MVP: " .. mvp.Name .. " (Skor: " .. string.format("%.1f", score) .. ")", Color3.fromRGB(255,200,0))
    else
        SetStatus("MVP hesaplanamadi", Color3.fromRGB(255,0,0))
    end
end)

ResetStatsBtn.MouseButton1Click:Connect(function()
    State.sessionKills = 0
    State.sessionDeaths = 0
    State.currentStreak = 0
    State.bestStreak = 0
    KillTracker.UpdateStats()
    SetStatus("Istatistikler sifirlandi!", Color3.fromRGB(0,255,0))
end)

-- ===== INPUT HANDLER =====
AddConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or State.isShuttingDown then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    UpdateRayFilter()
    if State.isSelectingTarget then
        local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
        local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, CachedRayParams)
        if result then
            State.targetPosition = result.Position
            State.isSelectingTarget = false
            TargetBtn.Text = "HEDEF BELIRLE"
            TargetBtn.BackgroundColor3 = Color3.fromRGB(30,30,80)
            SetStatus("Hedef kaydedildi!", Color3.fromRGB(0,255,0))
        end
        return
    end
    if State.isSelectingPlayer then
        local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
        local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, CachedRayParams)
        if result and result.Instance then
            local character = result.Instance:FindFirstAncestorOfClass("Model")
            if character then
                local player = Players:GetPlayerFromCharacter(character)
                if player and player ~= LocalPlayer then
                    State.targetPlayer = player
                    State.isSelectingPlayer = false
                    SelectPlayerBtn.Text = "OYUNCU SEC"
                    SelectPlayerBtn.BackgroundColor3 = Color3.fromRGB(30,80,30)
                    SetStatus(player.Name .. " secildi!", Color3.fromRGB(0,255,0))
                end
            end
        end
        return
    end
    if Settings.ClickFlingActive then
        local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
        local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, CachedRayParams)
        if result and result.Instance then
            local character = result.Instance:FindFirstAncestorOfClass("Model")
            if character then
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                local player = Players:GetPlayerFromCharacter(character)
                if humanoid and player and player ~= LocalPlayer then
                    local root = character:FindFirstChild("HumanoidRootPart")
                    if root then
                        ScheduleFlingWithDelay(root, Settings.FlingPower, Settings.MaxSpinSpeed)
                        CreateFlingEffect(root.Position)
                        PlayFlingSound(root.Position)
                        SetStatus(player.Name .. " firlatildi!", Color3.fromRGB(255,200,0))
                    end
                end
            end
        end
    end
end))

-- ===== ANA DONGU =====
local function MainLoop()
    if State.isShuttingDown then return end
    local now = os.clock()
    local vehicle = GetVehicle()

    if vehicle and Settings.NoclipActive then
        for _, part in pairs(vehicle:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end

    if vehicle and Settings.IsWaypointRunning then
        WaypointLoop()
    elseif vehicle and AIData.Enabled then
        UpdateAI()
    elseif vehicle and State.isFollowingPlayer and State.targetPlayer then
        local targetRoot = State.targetPlayer.Character and State.targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
            if mainPart then
                mainPart.CFrame = targetRoot.CFrame + Vector3.new(0, 2, 0)
                mainPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            end
        end
    elseif vehicle and State.targetPosition then
        local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
        if mainPart then
            local dist = (mainPart.Position - State.targetPosition).Magnitude
            if dist < 3 then
                State.targetPosition = nil
            else
                mainPart.CFrame = CFrame.new(State.targetPosition) + Vector3.new(0, 2, 0)
            end
        end
    end

    if Settings.IsNormalFling and now - State.lastFlingTime > Settings.FlingCooldown then
        DoFlingAction(1)
        State.lastFlingTime = os.clock()
    end
    if Settings.IsFlingEveryone and now - State.lastFlingTime > Settings.FlingCooldown then
        DoFlingAction(1.5)
        State.lastFlingTime = os.clock()
    end

    if Settings.IsFlying and vehicle then
        local mainPart = vehicle:FindFirstChild("VehicleSeat") or vehicle.PrimaryPart
        if mainPart and MoveDirection.Magnitude > 0 then
            mainPart.AssemblyLinearVelocity = MoveDirection * Settings.FlySpeed
        end
    end

    if Settings.RespawnProtection and not State.isRespawning then
        if now - State.lastRespawnCheck > 1 then
            State.lastRespawnCheck = now
            local char = LocalPlayer.Character
            if not char or not char:FindFirstChild("Humanoid") or char.Humanoid.Health <= 0 then
                State.isRespawning = true
                ResetVehicleData()
                SafeCall(function() LocalPlayer:LoadCharacter() end)
                local token = AddTimer()
                task.delay(3, function()
                    TrackTimer(token)
                    if token.cancelled then return end
                    State.isRespawning = false
                end)
            end
        end
    end
end

AddConnection(RunService.Heartbeat:Connect(MainLoop))

AddConnection(LocalPlayer.CharacterAdded:Connect(function()
    task.delay(0.5, function()
        if State.isShuttingDown then return end
        ResetVehicleData()
        State.isRespawning = false
    end)
end))

for _, player in pairs(Players:GetPlayers()) do
    AttachPlayerKillTracking(player)
end
AddConnection(Players.PlayerAdded:Connect(AttachPlayerKillTracking))
AddConnection(Players.PlayerRemoving:Connect(function(player)
    KillTrackerConnections[player] = nil
end))

-- ===== TOGGLE BUTTON =====
local XToggleBtn = Instance.new("TextButton")
XToggleBtn.Name = "XToggleBtn"
XToggleBtn.Size = UDim2.new(0, 70, 0, 70)
XToggleBtn.Position = UDim2.new(0.87, 0, 0.75, 0)
XToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
XToggleBtn.Text = "X"
XToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
XToggleBtn.Font = Enum.Font.GothamBold
XToggleBtn.TextSize = 24
XToggleBtn.Parent = ScreenGui
Instance.new("UICorner", XToggleBtn).CornerRadius = UDim.new(1, 0)

local XToggleStroke = Instance.new("UIStroke")
XToggleStroke.Color = Color3.fromRGB(255, 100, 100)
XToggleStroke.Thickness = 3
XToggleStroke.Parent = XToggleBtn

task.spawn(function()
    while XToggleBtn.Parent and not State.isShuttingDown do
        local t1 = TweenService:Create(XToggleStroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine), {Color=Color3.fromRGB(255,0,0), Thickness=5})
        t1:Play()
        t1.Completed:Wait()
        if not XToggleBtn.Parent then break end
        local t2 = TweenService:Create(XToggleStroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine), {Color=Color3.fromRGB(120,0,0), Thickness=2})
        t2:Play()
        t2.Completed:Wait()
    end
end)

MakeDraggable(XToggleBtn)

local function ToggleXMenu()
    XMenu.Visible = not XMenu.Visible
    if XMenu.Visible then
        SetStatus("X MENU ACIK", Color3.fromRGB(255,50,50))
    else
        SetStatus("X MENU KAPALI", Color3.fromRGB(255,200,0))
    end
end

XToggleBtn.MouseButton1Click:Connect(ToggleXMenu)
XToggleBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then ToggleXMenu() end
end)

XCloseBtn.MouseButton1Click:Connect(function() XMenu.Visible = false end)

XMinBtn.MouseButton1Click:Connect(function()
    XMenu.Size = UDim2.new(0, 540, 0, 35)
    task.wait(0.3)
    XMenu.Size = UDim2.new(0, 540, 0, 440)
end)

-- ===== STATUS LABELS =====
StatusLabel = Instance.new("TextLabel")
StatusLabel.Text = "X MENU V45 HAZIR!"
StatusLabel.Size = UDim2.new(0, 300, 0, 22)
StatusLabel.Position = UDim2.new(0.5, -150, 0.92, 0)
StatusLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
StatusLabel.BackgroundTransparency = 0.3
StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
StatusLabel.Font = Enum.Font.GothamBold
StatusLabel.TextSize = 11
StatusLabel.ZIndex = 5
StatusLabel.Parent = ScreenGui
Instance.new("UICorner", StatusLabel).CornerRadius = UDim.new(0, 6)

KillLabel = Instance.new("TextLabel")
KillLabel.Text = "Kill: 0 | Streak: 0"
KillLabel.Size = UDim2.new(0, 180, 0, 22)
KillLabel.Position = UDim2.new(0.5, 160, 0.92, 0)
KillLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
KillLabel.BackgroundTransparency = 0.3
KillLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
KillLabel.Font = Enum.Font.GothamBold
KillLabel.TextSize = 11
KillLabel.ZIndex = 5
KillLabel.Parent = ScreenGui
Instance.new("UICorner", KillLabel).CornerRadius = UDim.new(0, 6)

StatsLabel = Instance.new("TextLabel")
StatsLabel.Text = "K: 0 | D: 0 | K/D: 0.00"
StatsLabel.Size = UDim2.new(0, 300, 0, 22)
StatsLabel.Position = UDim2.new(0.5, -150, 0.95, 0)
StatsLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
StatsLabel.BackgroundTransparency = 0.3
StatsLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
StatsLabel.Font = Enum.Font.GothamBold
StatsLabel.TextSize = 11
StatsLabel.ZIndex = 5
StatsLabel.Parent = ScreenGui
Instance.new("UICorner", StatsLabel).CornerRadius = UDim.new(0, 6)

-- ===== CLEANUP =====
local function Cleanup()
    if State.isShuttingDown then return end
    State.isShuttingDown = true
    pulseStopped = true
    StopKillcamRecording()
    CleanupConnections()
    SafeCall(UnanchorVehicle)
end

AddConnection(ScreenGui.Destroying:Connect(Cleanup))

-- ===== BASLANGIC =====
SafeCall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "X MENU V45 HAZIR!",
        Text = "X butonuna bas!",
        Duration = 5
    })
end)

SetStatus("X MENU V45 HAZIR!", Color3.fromRGB(0, 255, 0))
UpdateQueueUI()
KillTracker.UpdateStats()
task.spawn(function() task.wait(1) RefreshPlayerList() end)

print("X MENU V45 YUKLENDI!")
