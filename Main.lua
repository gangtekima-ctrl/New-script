-- OrbitScript_BloxFruits.lua
-- LocalScript â†’ StarterPlayerScripts
-- Fixes: smooth target swap (no TP), distance independent of speed, frame-rate tween

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  SETTINGS
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local settings = {
	orbitSpeed    = 1.5,
	orbitDistance = 10,
	orbitHeight   = 0,
	lerpAlpha     = 0.25,  -- 0.05 floaty Â· 1.0 instant
	checkSafeZone = true,
	checkTeam     = true,
	checkPvP      = true,
}

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  SAFE ZONES  (XZ radius, Y ignored)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local SAFE_ZONES = {
	-- Sea 1
	{ name = "Marine Starter",    pos = Vector3.new(-1397, 0,  -892), radius = 230 },
	{ name = "Pirate Starter",    pos = Vector3.new( 1018, 0,  1520), radius = 230 },
	-- Sea 2
	{ name = "Cafe",              pos = Vector3.new( -130, 0, -3374), radius = 210 },
	{ name = "Kingdom of Rose",   pos = Vector3.new(-1196, 0, -3002), radius = 340 },
	-- Sea 3
	{ name = "Port Town",         pos = Vector3.new(  460, 0,  6000), radius = 290 },
	{ name = "Castle on the Sea", pos = Vector3.new( 6220, 0,  -435), radius = 310 },
	{ name = "Mansion",           pos = Vector3.new( 2900, 0, -1000), radius = 240 },
}

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  STATE
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local isOrbiting    = false
local targetPlayer  = nil
local targetIndex   = 1
local angle         = 0
local heartbeatConn = nil
local currentTween  = nil
local orbitPaused   = false

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  HELPERS
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function getCharRoot(plr)
	local char = plr and plr.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function isAlive(plr)
	local char = plr and plr.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

local function isInSafeZone(plr)
	local root = getCharRoot(plr)
	if not root then return false, nil end
	local p = root.Position
	for _, zone in ipairs(SAFE_ZONES) do
		local dx = p.X - zone.pos.X
		local dz = p.Z - zone.pos.Z
		if math.sqrt(dx*dx + dz*dz) < zone.radius then
			return true, zone.name
		end
	end
	return false, nil
end

local function isSameTeam(plr)
	if not settings.checkTeam then return false end
	local t1, t2 = localPlayer.Team, plr.Team
	return t1 ~= nil and t1 == t2
end

local PVP_NAMES = { "PvpEnabled", "IsPvp", "pvpEnabled", "PVPEnabled", "pvp" }
local function isPvPEnabled(plr)
	if not settings.checkPvP then return true end
	local char = plr and plr.Character
	if not char then return false end
	for _, n in ipairs(PVP_NAMES) do
		local v = char:FindFirstChild(n)
		if v and v:IsA("BoolValue") then return v.Value end
	end
	return true
end

local function canOrbit(plr)
	if not isAlive(plr)      then return false, "dead"         end
	if isSameTeam(plr)       then return false, "same team"    end
	if not isPvPEnabled(plr) then return false, "pvp disabled" end
	if settings.checkSafeZone then
		local inZone, zoneName = isInSafeZone(plr)
		if inZone then return false, "safe zone: "..(zoneName or "?") end
	end
	return true, nil
end

local function getOtherPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer then table.insert(list, p) end
	end
	table.sort(list, function(a,b) return a.Name < b.Name end)
	return list
end

local function findIndex(list, plr)
	for i, p in ipairs(list) do if p == plr then return i end end
	return 1
end

local function pickFirstValid()
	local list = getOtherPlayers()
	for i, p in ipairs(list) do
		if canOrbit(p) then targetIndex = i; return p end
	end
end

local function cycleTarget()
	local list = getOtherPlayers()
	if #list == 0 then return nil end
	local startIdx = findIndex(list, targetPlayer)
	for _ = 1, #list do
		local idx = (startIdx % #list) + 1
		startIdx  = idx
		local c   = list[idx]
		if c ~= targetPlayer and canOrbit(c) then
			targetIndex = idx; return c
		end
	end
end

local function pickReplacement()
	local list = getOtherPlayers()
	for i, p in ipairs(list) do
		if p ~= targetPlayer and canOrbit(p) then
			targetIndex = i; return p
		end
	end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  SWAP TARGET â€” keeps heartbeat running, no TP
--  Recalculates angle from current position so orbit
--  continues smoothly from wherever we already are.
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function swapTarget(newTarget)
	if not newTarget then return end
	local myRoot  = getCharRoot(localPlayer)
	local newRoot = getCharRoot(newTarget)
	if myRoot and newRoot then
		local diff = myRoot.Position - newRoot.Position
		angle = math.atan2(diff.Z, diff.X)
	end
	targetPlayer = newTarget
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  BUILD GUI
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "OrbitGUI"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = localPlayer.PlayerGui

local panel = Instance.new("Frame")
panel.Name             = "Panel"
panel.Size             = UDim2.new(0, 290, 0, 500)
panel.Position         = UDim2.new(0, 16, 0.5, -250)
panel.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
panel.BorderSizePixel  = 0
panel.Active           = true
panel.Draggable        = true
panel.Parent           = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke")
stroke.Color     = Color3.fromRGB(90, 70, 240)
stroke.Thickness = 1.5
stroke.Parent    = panel

local header = Instance.new("Frame")
header.Size             = UDim2.new(1, 0, 0, 46)
header.BackgroundColor3 = Color3.fromRGB(28, 18, 58)
header.BorderSizePixel  = 0
header.Parent           = panel
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

local headerFix = Instance.new("Frame")
headerFix.Size             = UDim2.new(1, 0, 0, 12)
headerFix.Position         = UDim2.new(0, 0, 1, -12)
headerFix.BackgroundColor3 = Color3.fromRGB(28, 18, 58)
headerFix.BorderSizePixel  = 0
headerFix.Parent           = header

local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 60, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 20, 120)),
})
grad.Rotation = 90; grad.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Size                   = UDim2.new(1, -10, 1, 0)
titleLabel.Position               = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text                   = "ðŸŒ€  ORBIT  Â·  Blox Fruits"
titleLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
titleLabel.Font                   = Enum.Font.GothamBold
titleLabel.TextSize               = 15
titleLabel.TextXAlignment         = Enum.TextXAlignment.Left
titleLabel.Parent                 = header

local function makeLabel(parent, text, y)
	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(1, -24, 0, 16)
	lbl.Position               = UDim2.new(0, 12, 0, y)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = text
	lbl.TextColor3             = Color3.fromRGB(150, 130, 210)
	lbl.Font                   = Enum.Font.GothamSemibold
	lbl.TextSize               = 11
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.Parent                 = parent
	return lbl
end

makeLabel(panel, "TARGET", 56)
local targetBox = Instance.new("Frame")
targetBox.Size             = UDim2.new(1, -24, 0, 34)
targetBox.Position         = UDim2.new(0, 12, 0, 74)
targetBox.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
targetBox.BorderSizePixel  = 0
targetBox.Parent           = panel
Instance.new("UICorner", targetBox).CornerRadius = UDim.new(0, 8)

local targetLabel = Instance.new("TextLabel")
targetLabel.Size                   = UDim2.new(1, -8, 1, 0)
targetLabel.Position               = UDim2.new(0, 8, 0, 0)
targetLabel.BackgroundTransparency = 1
targetLabel.Text                   = "None"
targetLabel.TextColor3             = Color3.fromRGB(180, 255, 180)
targetLabel.Font                   = Enum.Font.Gotham
targetLabel.TextSize               = 13
targetLabel.TextXAlignment         = Enum.TextXAlignment.Left
targetLabel.Parent                 = targetBox

local statusBox = Instance.new("Frame")
statusBox.Size             = UDim2.new(1, -24, 0, 24)
statusBox.Position         = UDim2.new(0, 12, 0, 112)
statusBox.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
statusBox.BorderSizePixel  = 0
statusBox.Visible          = false
statusBox.Parent           = panel
Instance.new("UICorner", statusBox).CornerRadius = UDim.new(0, 7)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size                   = UDim2.new(1, -8, 1, 0)
statusLabel.Position               = UDim2.new(0, 8, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text                   = ""
statusLabel.TextColor3             = Color3.fromRGB(255, 200, 80)
statusLabel.Font                   = Enum.Font.Gotham
statusLabel.TextSize               = 11
statusLabel.TextXAlignment         = Enum.TextXAlignment.Left
statusLabel.Parent                 = statusBox

local function makeSlider(parent, labelText, yPos, minVal, maxVal, defaultVal, callback)
	makeLabel(parent, labelText, yPos)
	local valLabel = Instance.new("TextLabel")
	valLabel.Size                   = UDim2.new(0, 40, 0, 16)
	valLabel.Position               = UDim2.new(1, -52, 0, yPos)
	valLabel.BackgroundTransparency = 1
	valLabel.Text                   = tostring(defaultVal)
	valLabel.TextColor3             = Color3.fromRGB(190, 170, 255)
	valLabel.Font                   = Enum.Font.GothamBold
	valLabel.TextSize               = 11
	valLabel.TextXAlignment         = Enum.TextXAlignment.Right
	valLabel.Parent                 = parent

	local track = Instance.new("Frame")
	track.Size             = UDim2.new(1, -24, 0, 8)
	track.Position         = UDim2.new(0, 12, 0, yPos + 20)
	track.BackgroundColor3 = Color3.fromRGB(38, 36, 56)
	track.BorderSizePixel  = 0
	track.Parent           = parent
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local hitArea = Instance.new("TextButton")
	hitArea.Size                   = UDim2.new(1, 0, 0, 24)
	hitArea.Position               = UDim2.new(0, 0, 0.5, -12)
	hitArea.BackgroundTransparency = 1
	hitArea.Text                   = ""
	hitArea.Parent                 = track

	local fill = Instance.new("Frame")
	fill.Size             = UDim2.new((defaultVal-minVal)/(maxVal-minVal), 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(100, 60, 240)
	fill.BorderSizePixel  = 0
	fill.Parent           = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.Size             = UDim2.new(0, 16, 0, 16)
	knob.AnchorPoint      = Vector2.new(0.5, 0.5)
	knob.Position         = UDim2.new((defaultVal-minVal)/(maxVal-minVal), 0, 0.5, 0)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel  = 0
	knob.Parent           = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local dragging = false
	local function applyX(absX)
		local tw, tx = track.AbsoluteSize.X, track.AbsolutePosition.X
		if tw == 0 then return end
		local rel   = math.clamp((absX - tx) / tw, 0, 1)
		local value = math.round((minVal + rel*(maxVal-minVal)) * 10) / 10
		local vis   = (value - minVal) / (maxVal - minVal)
		fill.Size     = UDim2.new(vis, 0, 1, 0)
		knob.Position = UDim2.new(vis, 0, 0.5, 0)
		valLabel.Text = tostring(value)
		callback(value)
	end
	hitArea.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
		or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; applyX(i.Position.X)
		end
	end)
	knob.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
		or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if not dragging then return end
		if i.UserInputType == Enum.UserInputType.MouseMovement
		or i.UserInputType == Enum.UserInputType.Touch then
			applyX(i.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
		or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

makeSlider(panel, "ORBIT SPEED",    148, 0.1, 5,    settings.orbitSpeed,    function(v) settings.orbitSpeed    = v end)
makeSlider(panel, "ORBIT DISTANCE", 196, 3,   40,   settings.orbitDistance, function(v) settings.orbitDistance = v end)
makeSlider(panel, "HEIGHT OFFSET",  244, -10, 10,   settings.orbitHeight,   function(v) settings.orbitHeight   = v end)
makeSlider(panel, "SMOOTH",         292, 0.05, 1.0, settings.lerpAlpha,     function(v) settings.lerpAlpha     = v end)

local function makeToggle(parent, labelText, yPos, settingKey)
	local box = Instance.new("Frame")
	box.Size             = UDim2.new(1, -24, 0, 26)
	box.Position         = UDim2.new(0, 12, 0, yPos)
	box.BackgroundColor3 = Color3.fromRGB(22, 22, 32)
	box.BorderSizePixel  = 0
	box.Parent           = parent
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.new(1, -50, 1, 0)
	lbl.Position               = UDim2.new(0, 10, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text                   = labelText
	lbl.TextColor3             = Color3.fromRGB(200, 195, 230)
	lbl.Font                   = Enum.Font.GothamSemibold
	lbl.TextSize               = 12
	lbl.TextXAlignment         = Enum.TextXAlignment.Left
	lbl.Parent                 = box

	local on = settings[settingKey]
	local pill = Instance.new("Frame")
	pill.Size             = UDim2.new(0, 36, 0, 18)
	pill.Position         = UDim2.new(1, -44, 0.5, -9)
	pill.BackgroundColor3 = on and Color3.fromRGB(80,210,120) or Color3.fromRGB(60,60,80)
	pill.BorderSizePixel  = 0
	pill.Parent           = box
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

	local thumb = Instance.new("Frame")
	thumb.Size             = UDim2.new(0, 14, 0, 14)
	thumb.AnchorPoint      = Vector2.new(0.5, 0.5)
	thumb.Position         = on and UDim2.new(1,-9,0.5,0) or UDim2.new(0,9,0.5,0)
	thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	thumb.BorderSizePixel  = 0
	thumb.Parent           = pill
	Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)

	local btn = Instance.new("TextButton")
	btn.Size                   = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text                   = ""
	btn.Parent                 = box
	btn.MouseButton1Click:Connect(function()
		settings[settingKey] = not settings[settingKey]
		local s = settings[settingKey]
		TweenService:Create(pill,  TweenInfo.new(0.15), {
			BackgroundColor3 = s and Color3.fromRGB(80,210,120) or Color3.fromRGB(60,60,80)
		}):Play()
		TweenService:Create(thumb, TweenInfo.new(0.15), {
			Position = s and UDim2.new(1,-9,0.5,0) or UDim2.new(0,9,0.5,0)
		}):Play()
	end)
end

makeLabel(panel, "FILTERS", 356)
makeToggle(panel, "Shield  Block safe zones", 374, "checkSafeZone")
makeToggle(panel, "Team    Block same team",  404, "checkTeam")
makeToggle(panel, "Sword   Block PvP-off",    434, "checkPvP")

local function makeButton(parent, text, xScale, color, callback)
	local btn = Instance.new("TextButton")
	btn.Size             = UDim2.new(0.48, 0, 0, 34)
	btn.Position         = UDim2.new(xScale, 0, 0, 0)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel  = 0
	btn.Text             = text
	btn.TextColor3       = Color3.fromRGB(255, 255, 255)
	btn.Font             = Enum.Font.GothamBold
	btn.TextSize         = 12
	btn.AutoButtonColor  = false
	btn.Parent           = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), {
			BackgroundColor3 = color:Lerp(Color3.fromRGB(255,255,255), 0.15)
		}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = color}):Play()
	end)
	btn.MouseButton1Click:Connect(callback)
	return btn
end

local btnRow = Instance.new("Frame")
btnRow.Size                   = UDim2.new(1, -24, 0, 34)
btnRow.Position               = UDim2.new(0, 12, 0, 468)
btnRow.BackgroundTransparency = 1
btnRow.Parent                 = panel

local orbitBtn  = makeButton(btnRow, "START",    0,    Color3.fromRGB(70, 195, 110), function() end)
local changeBtn = makeButton(btnRow, "TARGET",   0.52, Color3.fromRGB(70, 110, 215), function() end)

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  GUI HELPERS
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function showStatus(text, color)
	if text and text ~= "" then
		statusLabel.Text       = text
		statusLabel.TextColor3 = color or Color3.fromRGB(255, 200, 80)
		statusBox.Visible      = true
	else
		statusBox.Visible = false
	end
end

local function updateTargetLabel(flash)
	if targetPlayer then
		targetLabel.Text       = "  " .. targetPlayer.DisplayName
		targetLabel.TextColor3 = flash or Color3.fromRGB(180, 255, 180)
	else
		targetLabel.Text       = "None"
		targetLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  ORBIT CORE
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function cancelTween()
	if currentTween then currentTween:Cancel(); currentTween = nil end
end

local function stopOrbit()
	isOrbiting = false; orbitPaused = false
	cancelTween()
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	local char = localPlayer.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.PlatformStand = false end
	end
	orbitBtn.Text             = "START"
	orbitBtn.BackgroundColor3 = Color3.fromRGB(70, 195, 110)
	showStatus("")
end

local function startOrbit(target)
	if not target then return end
	swapTarget(target)
	updateTargetLabel()

	local char = localPlayer.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum  = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return end

	hum.PlatformStand         = true
	isOrbiting                = true
	orbitPaused               = false
	orbitBtn.Text             = "STOP"
	orbitBtn.BackgroundColor3 = Color3.fromRGB(210, 55, 55)

	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not targetPlayer then stopOrbit(); return end

		local ok, reason = canOrbit(targetPlayer)

		if not ok then
			if not isAlive(targetPlayer) then
				local nxt = pickReplacement()
				if nxt then
					swapTarget(nxt)
					updateTargetLabel(Color3.fromRGB(255, 230, 100))
					task.delay(0.8, updateTargetLabel)
					showStatus(""); orbitPaused = false
				else
					stopOrbit()
					targetLabel.Text       = "  No valid targets"
					targetLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
				end
			else
				if not orbitPaused then
					orbitPaused = true
					cancelTween()
					showStatus("Paused - "..(reason or "blocked"),
						Color3.fromRGB(255, 180, 60))
				end
			end
			return
		end

		if orbitPaused then orbitPaused = false; showStatus("") end

		local targetRoot = getCharRoot(targetPlayer)
		if not targetRoot then return end

		-- Angle advances by speed only â€” distance is separate
		angle = angle + settings.orbitSpeed * dt * math.pi * 2

		-- Desired position: distance is ONLY from orbitDistance slider
		local desiredPos = Vector3.new(
			targetRoot.Position.X + math.cos(angle) * settings.orbitDistance,
			targetRoot.Position.Y + settings.orbitHeight,
			targetRoot.Position.Z + math.sin(angle) * settings.orbitDistance
		)

		local myChar = localPlayer.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if not myRoot then return end

		-- Face target flat (no Y pitch)
		local flatLook = targetRoot.Position
			- Vector3.new(myRoot.Position.X, targetRoot.Position.Y, myRoot.Position.Z)
		local targetCF = flatLook.Magnitude > 0.1
			and CFrame.new(desiredPos, desiredPos + flatLook)
			or  CFrame.new(desiredPos)

		-- Frame-rate-independent lerp then tween for the remaining dt
		-- This ensures distance never drifts with speed changes
		local alpha    = math.clamp(settings.lerpAlpha * (dt / (1/60)), 0.01, 1)
		local smoothCF = myRoot.CFrame:Lerp(targetCF, alpha)

		cancelTween()
		currentTween = TweenService:Create(
			myRoot,
			TweenInfo.new(dt, Enum.EasingStyle.Linear),
			{ CFrame = smoothCF }
		)
		currentTween:Play()
	end)
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--  BUTTON CALLBACKS
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
orbitBtn.MouseButton1Click:Connect(function()
	if isOrbiting then
		stopOrbit()
	else
		local first = pickFirstValid()
		if not first then
			targetLabel.Text       = "  No valid players!"
			targetLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			showStatus("Check filters or wait", Color3.fromRGB(255, 140, 60))
			return
		end
		startOrbit(first)
	end
end)

-- Swaps mid-orbit without stopping â†’ zero TP, pure smooth transition
changeBtn.MouseButton1Click:Connect(function()
	local nxt = cycleTarget()
	if not nxt then
		showStatus("No other valid targets!", Color3.fromRGB(255, 140, 60))
		task.delay(1.5, function() showStatus("") end)
		return
	end
	if isOrbiting then
		swapTarget(nxt)  -- heartbeat keeps running, angle recalculated from current pos
		updateTargetLabel(Color3.fromRGB(100, 220, 255))
		task.delay(0.6, updateTargetLabel)
	else
		targetPlayer = nxt
		updateTargetLabel()
	end
end)

localPlayer.CharacterAdded:Connect(function()
	cancelTween()
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	isOrbiting = false; orbitPaused = false
	orbitBtn.Text             = "START"
	orbitBtn.BackgroundColor3 = Color3.fromRGB(70, 195, 110)
	showStatus(""); updateTargetLabel()
end)
