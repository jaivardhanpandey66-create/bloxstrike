--!strict
-- BLOXSTRIKE: Neon Arena
-- ShooterClient (LocalScript)
-- Rojo: LocalScript at StarterPlayer.StarterPlayerScripts.ShooterClient
-- Manual: create a LocalScript named "ShooterClient" in
--         StarterPlayer > StarterPlayerScripts.
--
-- Handles: HUD (crosshair, ammo, health, score), firing input, ADS zoom,
-- recoil, reload, local tracers, hitmarker and floating damage numbers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("ShooterConfig"))
local FireRemote = ReplicatedStorage:WaitForChild("Fire") :: RemoteEvent
local FireEffect = ReplicatedStorage:WaitForChild("FireEffect") :: RemoteEvent
local HitConfirm = ReplicatedStorage:WaitForChild("HitConfirm") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local weaponCfg = Config.Weapons[Config.DefaultWeapon]
local TOOL_NAME = "NeonBlaster"

-- ===========================================================================
-- State
-- ===========================================================================
local state = {
	equipped = false,
	firing = false,
	reloading = false,
	ammo = weaponCfg.MagSize,
	reserve = weaponCfg.ReserveAmmo,
	nextShot = 0,
	ads = false,
	recoilPitch = 0,
	recoilYaw = 0,
}

-- ===========================================================================
-- UI construction
-- ===========================================================================
local function new(class: string, props: { [string]: any }, children: { Instance }?)
	local inst = Instance.new(class)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	return inst
end

local gui = new("ScreenGui", {
	Name = "BLOXSTRIKE_HUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}) :: ScreenGui
gui.Parent = player:WaitForChild("PlayerGui")

-- Crosshair -----------------------------------------------------------------
local crosshair = new("Frame", {
	Name = "Crosshair",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(40, 40),
	BackgroundTransparency = 1,
}, { new("UIScale", { Name = "Scale", Scale = 1 }) }) :: Frame
crosshair.Parent = gui

local function crossLine(size: UDim2, pos: UDim2, anchor: Vector2)
	local line = new("Frame", {
		Size = size,
		Position = pos,
		AnchorPoint = anchor,
		BackgroundColor3 = Color3.fromRGB(80, 240, 120),
		BorderSizePixel = 0,
		Name = "Line",
	})
	line.Parent = crosshair
	return line
end
local gap = 6
local thickness = 2
crossLine(UDim2.fromOffset(thickness, 10), UDim2.new(0.5, 0, 0.5, -gap), Vector2.new(0.5, 1))
crossLine(UDim2.fromOffset(thickness, 10), UDim2.new(0.5, 0, 0.5, gap), Vector2.new(0.5, 0))
crossLine(UDim2.fromOffset(10, thickness), UDim2.new(0.5, -gap, 0.5, 0), Vector2.new(1, 0.5))
crossLine(UDim2.fromOffset(10, thickness), UDim2.new(0.5, gap, 0.5, 0), Vector2.new(0, 0.5))
new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(2, 2),
	BackgroundColor3 = Color3.fromRGB(80, 240, 120),
	BorderSizePixel = 0,
	Parent = crosshair,
})

-- Hitmarker ----------------------------------------------------------------
local hitmarker = new("Frame", {
	Name = "Hitmarker",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(22, 22),
	BackgroundTransparency = 1,
	Visible = false,
}) :: Frame
hitmarker.Parent = gui
for i = 1, 4 do
	local rot = (i - 1) * 90
	local dash = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0) + UDim2.fromOffset(0, -4),
		Size = UDim2.fromOffset(2, 9),
		Rotation = 45 + rot,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = hitmarker,
	})
	dash.Visible = true
end

-- Damage numbers container --------------------------------------------------
local dmgFolder = new("Frame", {
	Name = "DamageNumbers",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}) :: Frame
dmgFolder.Parent = gui

-- Bottom-left: health bar ---------------------------------------------------
local healthBox = new("Frame", {
	Name = "Health",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 24, 1, -24),
	Size = UDim2.fromOffset(240, 26),
	BackgroundColor3 = Color3.fromRGB(12, 14, 20),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
}, {
	new("UICorner", { CornerRadius = UDim.new(0, 6) }),
	new("UIStroke", { Color = Color3.fromRGB(60, 220, 140), Thickness = 1.5, Transparency = 0.3 }),
}) :: Frame
healthBox.Parent = gui
local healthFill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(60, 220, 140),
	BorderSizePixel = 0,
	Parent = healthBox,
}) :: Frame
new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = healthFill })
local healthText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "100",
	TextStrokeTransparency = 0.6,
	Parent = healthBox,
}) :: TextLabel

-- Bottom-right: ammo --------------------------------------------------------
local ammoBox = new("Frame", {
	Name = "Ammo",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -24, 1, -24),
	Size = UDim2.fromOffset(200, 60),
	BackgroundTransparency = 1,
}) :: Frame
ammoBox.Parent = gui
local ammoText = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromOffset(200, 44),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 40,
	TextColor3 = Color3.fromRGB(80, 240, 120),
	Text = "30",
	TextXAlignment = Enum.TextXAlignment.Right,
	TextStrokeTransparency = 0.7,
	Parent = ammoBox,
}) :: TextLabel
local reserveText = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 1),
	Size = UDim2.fromOffset(200, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 16,
	TextColor3 = Color3.fromRGB(200, 205, 220),
	Text = "150 reserve",
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = ammoBox,
}) :: TextLabel

-- Top-center: score / kills --------------------------------------------------
local scoreLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 16),
	Size = UDim2.fromOffset(400, 34),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextStrokeTransparency = 0.6,
	Text = "Kills 0   |   Score 0",
	Parent = gui,
}) :: TextLabel

-- Reload prompt --------------------------------------------------------------
local reloadLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 60),
	Size = UDim2.fromOffset(220, 30),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(255, 210, 80),
	TextStrokeTransparency = 0.6,
	Text = "RELOADING...",
	Visible = false,
	Parent = gui,
}) :: TextLabel

-- ===========================================================================
-- UI helpers
-- ===========================================================================
local function setCrosshairColor(color: Color3)
	for _, line in crosshair:GetChildren() do
		if line:IsA("Frame") then
			line.BackgroundColor3 = color
		end
	end
end

local function updateAmmo()
	ammoText.Text = tostring(state.ammo)
	reserveText.Text = tostring(state.reserve) .. " reserve"
	ammoText.TextColor3 = (state.ammo == 0)
		and Color3.fromRGB(255, 90, 90)
		or Color3.fromRGB(80, 240, 120)
end

local function setCrosshairSpread(spread: number)
	local target = 1 + spread * 0.06
	local scale = crosshair:FindFirstChild("Scale") :: UIScale
	TweenService:Create(scale, TweenInfo.new(0.08), { Scale = target }):Play()
end

local function flashHitmarker(killed: boolean, headshot: boolean)
	local color = killed and Color3.fromRGB(255, 80, 80)
		or (headshot and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(255, 255, 255))
	for _, dash in hitmarker:GetChildren() do
		if dash:IsA("Frame") then
			dash.BackgroundColor3 = color
		end
	end
	hitmarker.Visible = true
	hitmarker.Size = UDim2.fromOffset(30, 30)
	TweenService:Create(hitmarker, TweenInfo.new(Config.Effects.HitmarkerTime), {
		Size = UDim2.fromOffset(20, 20),
	}):Play()
	task.delay(Config.Effects.HitmarkerTime, function()
		hitmarker.Visible = false
	end)
end

local function spawnDamageNumber(worldPos: Vector3, amount: number, headshot: boolean)
	local screen, onScreen = camera:WorldToViewportPoint(worldPos)
	if not onScreen then
		return
	end
	local label = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(screen.X, screen.Y),
		Size = UDim2.fromOffset(120, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = headshot and 24 or 19,
		TextColor3 = headshot and Color3.fromRGB(255, 210, 60) or Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.4,
		Text = (headshot and "HEADSHOT " or "") .. tostring(amount),
	}) :: TextLabel
	label.Parent = dmgFolder
	TweenService:Create(label, TweenInfo.new(Config.Effects.DamageNumberTime), {
		Position = label.Position - UDim2.fromOffset(0, 60),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(Config.Effects.DamageNumberTime, function()
		label:Destroy()
	end)
end

-- ===========================================================================
-- Tracer effects
-- ===========================================================================
local function createTracer(from: Vector3, to: Vector3, color: Color3)
	local distance = (to - from).Magnitude
	if distance < 1 then
		return
	end

	local beam = new("Part", {
		Name = "Tracer",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Material = Enum.Material.Neon,
		Color = color,
		Size = Vector3.new(0.12, 0.12, distance),
		CFrame = CFrame.lookAt(from + (to - from) / 2, to),
		Transparency = 0.1,
		Parent = workspace,
	}) :: Part

	local spark = new("Part", {
		Name = "Impact",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Material = Enum.Material.Neon,
		Color = color,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.6, 0.6, 0.6),
		CFrame = CFrame.new(to),
		Transparency = 0.2,
		Parent = workspace,
	}) :: Part

	task.delay(Config.Effects.TracerLifetime, function()
		beam:Destroy()
		spark:Destroy()
	end)
end

FireEffect.OnClientEvent:Connect(function(from, to, color)
	createTracer(from, to, color)
end)

-- ===========================================================================
-- Muzzle flash
-- ===========================================================================
local function muzzleFlash()
	local char = player.Character
	local tool = char and char:FindFirstChild(TOOL_NAME)
	local handle = tool and tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if not muzzle then
		return
	end
	local flash = new("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Material = Enum.Material.Neon,
		Color = weaponCfg.Color,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1, 1, 1),
		CFrame = muzzle.WorldCFrame,
		Transparency = 0.2,
		Parent = workspace,
	}) :: Part
	TweenService:Create(flash, TweenInfo.new(Config.Effects.MuzzleFlashTime), {
		Size = Vector3.new(0.3, 0.3, 0.3),
		Transparency = 1,
	}):Play()
	task.delay(Config.Effects.MuzzleFlashTime, function()
		flash:Destroy()
	end)
end

-- ===========================================================================
-- Firing
-- ===========================================================================
local function getMuzzlePosition(): Vector3
	local char = player.Character
	local tool = char and char:FindFirstChild(TOOL_NAME)
	local handle = tool and tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if muzzle then
		return muzzle.WorldPosition
	end
	local head = char and char:FindFirstChild("Head")
	return head and head.Position or camera.CFrame.Position
end

local function startReload()
	if state.reloading then
		return
	end
	if state.ammo >= weaponCfg.MagSize or state.reserve <= 0 then
		return
	end
	state.reloading = true
	reloadLabel.Visible = true
	task.wait(weaponCfg.ReloadTime)
	local needed = weaponCfg.MagSize - state.ammo
	local take = math.min(needed, state.reserve)
	state.ammo += take
	state.reserve -= take
	state.reloading = false
	reloadLabel.Visible = false
	updateAmmo()
end

local function attemptFire()
	if not state.equipped or state.reloading then
		return
	end
	if os.clock() < state.nextShot then
		return
	end
	if state.ammo <= 0 then
		task.spawn(startReload)
		return
	end

	state.nextShot = os.clock() + weaponCfg.FireRate
	state.ammo -= 1
	updateAmmo()

	-- Recoil kick
	state.recoilPitch += weaponCfg.RecoilKick + math.random() * weaponCfg.RecoilKick * 0.5
	state.recoilYaw += (math.random() * 2 - 1) * weaponCfg.RecoilKick * 0.8
	setCrosshairSpread(weaponCfg.Spread)

	-- Aim ray from camera through the mouse
	local mouseLoc = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLoc.X, mouseLoc.Y)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local origin = head and head.Position or camera.CFrame.Position
	local targetPoint = ray.Origin + ray.Direction * weaponCfg.Range
	local direction = (targetPoint - origin).Unit

	-- Local tracer for instant feedback
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char :: any }
	local localHit = workspace:Raycast(origin, direction * weaponCfg.Range, params)
	local endpoint = localHit and localHit.Position or targetPoint
	createTracer(getMuzzlePosition(), endpoint, weaponCfg.Color)
	muzzleFlash()

	FireRemote:FireServer(origin, direction)
end

-- ===========================================================================
-- Input
-- ===========================================================================
local function onToolEquipped()
	state.equipped = true
	state.ammo = weaponCfg.MagSize
	state.reserve = weaponCfg.ReserveAmmo
	state.reloading = false
	updateAmmo()
	crosshair.Visible = true
	reloadLabel.Visible = false
end

local function onToolUnequipped()
	state.equipped = false
	state.firing = false
	crosshair.Visible = false
	hitmarker.Visible = false
	reloadLabel.Visible = false
	if state.ads then
		state.ads = false
	end
end

local function watchCharacter(char: Model)
	task.wait(0.2)
	local tool = char:FindFirstChild(TOOL_NAME) or player:FindFirstChild("Backpack")
		and player.Backpack:FindFirstChild(TOOL_NAME)
	if not tool then
		return
	end
	tool.Equipped:Connect(onToolEquipped)
	tool.Unequipped:Connect(onToolUnequipped)
	if tool.Parent == char then
		onToolEquipped()
	end
end

player.CharacterAdded:Connect(function(char)
	local backpack = player:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(function(child)
		if child.Name == TOOL_NAME then
			task.wait(0.05)
			watchCharacter(char)
		end
	end)
	watchCharacter(char)
end)

if player.Character then
	task.spawn(function()
		local backpack = player:WaitForChild("Backpack")
		local tool = backpack:FindFirstChild(TOOL_NAME)
		if tool then
			watchCharacter(player.Character :: Model)
		end
		backpack.ChildAdded:Connect(function(child)
			if child.Name == TOOL_NAME then
				task.wait(0.05)
				watchCharacter(player.Character :: Model)
			end
		end)
	end)
end

-- Fire input
local fireLoop: thread?
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not weaponCfg.Automatic then
			attemptFire()
			return
		end
		state.firing = true
		if fireLoop then
			return
		end
		fireLoop = task.spawn(function()
			while state.firing do
				attemptFire()
				task.wait(0.01)
			end
			fireLoop = nil
		end)
	elseif input.KeyCode == Enum.KeyCode.R then
		task.spawn(startReload)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		state.firing = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		state.ads = false
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.UserInputType == Enum.UserInputType.MouseButton2 then
		state.ads = true
	end
end)

-- ===========================================================================
-- Recoil recovery + ADS zoom
-- ===========================================================================
RunService:BindToRenderStep("BLOXSTRIKE_Camera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if state.recoilPitch ~= 0 or state.recoilYaw ~= 0 then
		camera.CFrame = camera.CFrame * CFrame.Angles(state.recoilPitch, state.recoilYaw, 0)
		local decay = math.clamp(weaponCfg.RecoilRecovery * dt, 0, 1)
		state.recoilPitch += (0 - state.recoilPitch) * decay
		state.recoilYaw += (0 - state.recoilYaw) * decay
		if math.abs(state.recoilPitch) < 0.0001 then
			state.recoilPitch = 0
		end
		if math.abs(state.recoilYaw) < 0.0001 then
			state.recoilYaw = 0
		end
	end

	local targetFov = state.ads and weaponCfg.ZoomFov or weaponCfg.DefaultFov
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.clamp(dt * 12, 0, 1)
end)

-- ===========================================================================
-- Server feedback
-- ===========================================================================
HitConfirm.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then
		return
	end
	flashHitmarker(data.killed == true, data.headshot == true)
	if data.position and data.damage then
		spawnDamageNumber(data.position, data.damage, data.headshot == true)
	end
end)

-- ===========================================================================
-- Score display
-- ===========================================================================
local function bindStats()
	local leaderstats = player:WaitForChild("leaderstats")
	local kills = leaderstats:WaitForChild("Kills") :: IntValue
	local score = leaderstats:WaitForChild("Score") :: IntValue
	local function refresh()
		scoreLabel.Text = ("Kills %d   |   Score %d"):format(kills.Value, score.Value)
	end
	kills:GetPropertyChangedSignal("Value"):Connect(refresh)
	score:GetPropertyChangedSignal("Value"):Connect(refresh)
	refresh()
end
task.spawn(bindStats)

-- ===========================================================================
-- Health display
-- ===========================================================================
local function bindHealth(char: Model)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	local function refresh()
		local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(ratio, 1)
		healthFill.BackgroundColor3 = Color3.fromRGB(
			math.floor(60 + 195 * (1 - ratio)),
			math.floor(220 * ratio),
			90
		)
		healthText.Text = tostring(math.ceil(humanoid.Health))
	end
	humanoid.HealthChanged:Connect(refresh)
	refresh()
end
player.CharacterAdded:Connect(bindHealth)
if player.Character then
	task.spawn(bindHealth, player.Character)
end

setCrosshairColor(Color3.fromRGB(80, 240, 120))
updateAmmo()
print("[BLOXSTRIKE] Client ready.")
