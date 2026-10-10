--!strict
-- BLOXSTRIKE: Neon Arena
-- ShooterServer
-- Rojo: Script at ServerScriptService.ShooterServer
-- Manual: create a Script named "ShooterServer" in ServerScriptService.
--
-- Responsibilities:
--   * build the neon arena + lighting
--   * build the weapon Tool and hand it to players
--   * spawn blocky enemy rigs with simple chase/attack AI
--   * authoritative raycast hit detection, damage, headshots
--   * scoring / leaderstats and kill credit
--   * broadcast tracers and hit confirmations

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ShooterConfig"))

-- ===========================================================================
-- Remotes
-- ===========================================================================
local function ensureRemote(name: string, class: string)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(class)
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local FireRemote = ensureRemote("Fire", "RemoteEvent")
local FireEffect = ensureRemote("FireEffect", "RemoteEvent")
local HitConfirm = ensureRemote("HitConfirm", "RemoteEvent")

-- ===========================================================================
-- Helper: random point inside the arena
-- ===========================================================================
local ARENA = Config.Arena
local HALF = ARENA.Size / 2 - 8

local function randomArenaPoint(y: number): Vector3
	return Vector3.new(
		math.random(-HALF, HALF),
		y,
		math.random(-HALF, HALF)
	)
end

-- ===========================================================================
-- Lighting
-- ===========================================================================
local function setupLighting()
	Lighting.Ambient = Color3.fromRGB(60, 64, 82)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 74, 92)
	Lighting.ClockTime = 20
	Lighting.Brightness = 2.4
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.32
		atmo.Offset = 0.1
		atmo.Color = Color3.fromRGB(120, 130, 175)
		atmo.Decay = Color3.fromRGB(70, 60, 120)
		atmo.Glare = 0.25
		atmo.Haze = 1.2
		atmo.Parent = Lighting
	end

	local function makeEffect(class, props)
		local fx = Lighting:FindFirstChildOfClass(class) or Instance.new(class)
		for k, v in props do
			(fx :: any)[k] = v
		end
		fx.Parent = Lighting
	end

	makeEffect("BloomEffect", {
		Intensity = 0.9,
		Size = 24,
		Threshold = 0.9,
	})
	makeEffect("ColorCorrectionEffect", {
		Saturation = 0.12,
		Contrast = 0.08,
		TintColor = Color3.fromRGB(226, 232, 255),
	})
end

-- ===========================================================================
-- Arena
-- ===========================================================================
local function buildArena()
	local old = Workspace:FindFirstChild("ShooterArena")
	if old then
		old:Destroy()
	end

	local arena = Instance.new("Folder")
	arena.Name = "ShooterArena"
	arena.Parent = Workspace

	local function makePart(name, size, cframe, color, material, parent)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.Parent = parent or arena
		return part
	end

	-- Ground
	local ground = makePart(
		"Ground",
		Vector3.new(ARENA.Size, 4, ARENA.Size),
		CFrame.new(0, -2, 0),
		ARENA.GroundColor,
		Enum.Material.Concrete
	)
	ground.Locked = true

	-- Neon border strip around the ground edges
	local stripY = 0.2
	local stripT = 0.6
	for _, sign in { -1, 1 } do
		makePart("StripX", Vector3.new(ARENA.Size, stripT, 1),
			CFrame.new(0, stripY, sign * (ARENA.Size / 2 - 0.5)),
			ARENA.AccentColor, Enum.Material.Neon)
		makePart("StripZ", Vector3.new(1, stripT, ARENA.Size),
			CFrame.new(sign * (ARENA.Size / 2 - 0.5), stripY, 0),
			ARENA.AccentColor, Enum.Material.Neon)
	end

	-- Perimeter walls
	local wallH = ARENA.WallHeight
	local t = 4
	for _, sign in { -1, 1 } do
		makePart("WallX", Vector3.new(ARENA.Size, wallH, t),
			CFrame.new(0, wallH / 2, sign * (ARENA.Size / 2)),
			ARENA.WallColor, Enum.Material.Concrete)
		makePart("WallZ", Vector3.new(t, wallH, ARENA.Size),
			CFrame.new(sign * (ARENA.Size / 2), wallH / 2, 0),
			ARENA.WallColor, Enum.Material.Concrete)
	end

	-- Cover / obstacles
	for i = 1, ARENA.CoverCount do
		local h = math.random(6, 20)
		local w = math.random(6, 18)
		local d = math.random(6, 18)
		local pos = randomArenaPoint(h / 2)
		local cover = makePart(
			"Cover" .. i,
			Vector3.new(w, h, d),
			CFrame.new(pos) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0),
			ARENA.WallColor,
			Enum.Material.Concrete
		)
		-- Neon rim on tall blocks
		if h >= 14 then
			local rimColor = (i % 2 == 0) and ARENA.AccentColor or ARENA.AccentColor2
			makePart("Rim" .. i, Vector3.new(w + 0.4, 0.5, d + 0.4),
				cover.CFrame * CFrame.new(0, h / 2, 0), rimColor, Enum.Material.Neon)
		end
	end

	return arena
end

-- ===========================================================================
-- Enemy rigs (programmatic R6 dummy)
-- ===========================================================================
local ENEMY = Config.Enemies

local function buildRig(position: Vector3, parent: Instance): (Model, Humanoid, BasePart)
	local model = Instance.new("Model")
	model.Name = "Enemy"
	model.Parent = parent

	local base = CFrame.new(position)
	local color = ENEMY.BodyColor

	local function makePart(name, size, offset, collide)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = base * offset
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = collide
		p.Parent = model
		return p
	end

	local hrp = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 0, 0), true)
	hrp.Transparency = 1
	hrp.Locked = true

	local torso = makePart("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 0, 0), false)
	local head = makePart("Head", Vector3.new(2, 1, 1), CFrame.new(0, 1.5, 0), false)
	local rArm = makePart("Right Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0), false)
	local lArm = makePart("Left Arm", Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0), false)
	local rLeg = makePart("Right Leg", Vector3.new(1, 2, 1), CFrame.new(-0.5, -2, 0), false)
	local lLeg = makePart("Left Leg", Vector3.new(1, 2, 1), CFrame.new(0.5, -2, 0), false)

	-- Glowing eye on the head
	local eye = Instance.new("Part")
	eye.Name = "Eye"
	eye.Size = Vector3.new(1.2, 0.3, 0.1)
	eye.Color = ARENA.AccentColor
	eye.Material = Enum.Material.Neon
	eye.CanCollide = false
	eye.CFrame = head.CFrame * CFrame.new(0, 0.1, -0.5)
	eye.Parent = model
	local eyeWeld = Instance.new("WeldConstraint")
	eyeWeld.Part0 = head
	eyeWeld.Part1 = eye
	eyeWeld.Parent = eye

	model.PrimaryPart = hrp

	local function makeJoint(name, part0, part1, c0, c1)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		m.C0 = c0
		m.C1 = c1
		m.Parent = part0
		return m
	end

	makeJoint("RootJoint", hrp, torso, CFrame.new(), CFrame.new())
	makeJoint("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
	makeJoint("Right Shoulder", torso, rArm, CFrame.new(-1, 1, 0), CFrame.new(0.5, 1, 0))
	makeJoint("Left Shoulder", torso, lArm, CFrame.new(1, 1, 0), CFrame.new(-0.5, 1, 0))
	makeJoint("Right Hip", torso, rLeg, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0))
	makeJoint("Left Hip", torso, lLeg, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.MaxHealth = ENEMY.MaxHealth
	humanoid.Health = ENEMY.MaxHealth
	humanoid.WalkSpeed = ENEMY.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	model:SetAttribute("Enemy", true)

	-- Overhead health bar
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.fromOffset(64, 8)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 250
	billboard.Parent = head

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.fromScale(1, 1)
	barBg.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	barBg.BorderSizePixel = 0
	barBg.Parent = billboard
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 3)
	bgCorner.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = barFill

	humanoid.HealthChanged:Connect(function(hp)
		local ratio = math.clamp(hp / humanoid.MaxHealth, 0, 1)
		barFill.Size = UDim2.fromScale(ratio, 1)
		barFill.BackgroundColor3 = Color3.fromRGB(
			255,
			math.floor(60 + 195 * ratio),
			60
		)
	end)

	return model, humanoid, hrp
end

-- ===========================================================================
-- Enemy AI + lifecycle
-- ===========================================================================
local enemyFolder = Workspace:FindFirstChild("Enemies")
if enemyFolder then
	enemyFolder:Destroy()
end
enemyFolder = Instance.new("Folder")
enemyFolder.Name = "Enemies"
enemyFolder.Parent = Workspace

local function nearestPlayerCharacter(fromPos: Vector3): (Model?, Player?)
	local best: Model? = nil
	local bestPlr: Player? = nil
	local bestDist = math.huge
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if char and hum and root and hum.Health > 0 then
			local d = (root.Position - fromPos).Magnitude
			if d < bestDist then
				bestDist = d
				best = char
				bestPlr = plr
			end
		end
	end
	return best, bestPlr
end

local function startAI(model: Model, humanoid: Humanoid, hrp: BasePart)
	task.spawn(function()
		while model.Parent and humanoid.Health > 0 do
			local target = nearestPlayerCharacter(hrp.Position)
			if target then
				local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart
				local dist = (targetRoot.Position - hrp.Position).Magnitude
				if dist > ENEMY.AttackRange then
					humanoid:MoveTo(targetRoot.Position)
				else
					local now = os.clock()
					if now >= (model:GetAttribute("NextAttack") or 0) then
						model:SetAttribute("NextAttack", now + ENEMY.AttackCooldown)
						local th = target:FindFirstChildOfClass("Humanoid")
						if th and th.Health > 0 then
							th:TakeDamage(ENEMY.AttackDamage)
						end
					end
				end
			else
				local wander = hrp.Position + Vector3.new(
					math.random(-30, 30), 0, math.random(-30, 30)
				)
				humanoid:MoveTo(wander)
			end
			task.wait(0.15)
		end
	end)
end

local function awardKill(player: Player, headshot: boolean)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local kills = leaderstats:FindFirstChild("Kills")
	local score = leaderstats:FindFirstChild("Score")
	if kills then
		(kills :: IntValue).Value += 1
	end
	if score then
		local gain = Config.Player.ScorePerKill
		if headshot then
			gain += Config.Player.HeadshotBonus
		end
		(score :: IntValue).Value += gain
	end
end

local function spawnEnemy()
	local pos = randomArenaPoint(6)
	local model, humanoid, hrp = buildRig(pos, enemyFolder)

	humanoid.Died:Connect(function()
		local attackerId = model:GetAttribute("LastAttacker")
		if typeof(attackerId) == "number" then
			local attacker = Players:GetPlayerByUserId(attackerId :: number)
			if attacker then
				awardKill(attacker, model:GetAttribute("LastHeadshot") == true)
			end
		end

		local torso = model:FindFirstChild("Torso")
		if torso then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = false
				end
			end
		end

		task.delay(ENEMY.RespawnDelay, function()
			if model.Parent then
				model:Destroy()
			end
			spawnEnemy()
		end)
	end)

	startAI(model, humanoid, hrp)
end

local function populateEnemies()
	for _ = 1, ENEMY.Count do
		spawnEnemy()
	end
end

-- ===========================================================================
-- Weapon tool
-- ===========================================================================
local TOOL_NAME = "NeonBlaster"

local function buildTool(): Tool
	local weaponCfg = Config.Weapons[Config.DefaultWeapon]

	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = weaponCfg.DisplayName

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 1.1, 0.5)
	handle.Color = Color3.fromRGB(30, 34, 44)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	local function grip(name, size, offset, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.CanCollide = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = handle.CFrame * offset
		p.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	-- Body, barrel and glowing core
	grip("Body", Vector3.new(0.55, 0.55, 1.6), CFrame.new(0, 0.45, 0), Color3.fromRGB(40, 46, 60))
	grip("Barrel", Vector3.new(0.3, 0.3, 1.1), CFrame.new(0, 0.45, -1.2), Color3.fromRGB(20, 22, 30))
	local core = grip("Core", Vector3.new(0.62, 0.18, 1.62),
		CFrame.new(0, 0.45, 0), weaponCfg.Color, Enum.Material.Neon)
	core.Transparency = 0.1

	-- Nozzle + muzzle attachment
	local nozzle = grip("Nozzle", Vector3.new(0.34, 0.34, 0.3),
		CFrame.new(0, 0.45, -1.75), weaponCfg.Color, Enum.Material.Neon)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.45, -1.9)
	muzzle.Parent = handle

	local pointLight = Instance.new("PointLight")
	pointLight.Color = weaponCfg.Color
	pointLight.Range = 8
	pointLight.Brightness = 1.5
	pointLight.Parent = nozzle

	return tool
end

local toolTemplate = buildTool()

local function giveTool(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	for _, child in backpack:GetChildren() do
		if child.Name == TOOL_NAME then
			child:Destroy()
		end
	end
	local char = player.Character
	if char and char:FindFirstChild(TOOL_NAME) then
		char:FindFirstChild(TOOL_NAME):Destroy()
	end
	local clone = toolTemplate:Clone()
	clone.Parent = backpack
end

-- ===========================================================================
-- Players
-- ===========================================================================
local function onCharacter(char: Model)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	humanoid.MaxHealth = Config.Player.MaxHealth
	humanoid.Health = Config.Player.MaxHealth
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	humanoid.BreakJointsOnDeath = true
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = leaderstats

	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Parent = leaderstats

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	giveTool(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- ===========================================================================
-- Firing (server-authoritative raycast)
-- ===========================================================================
local lastFire: { [Player]: number } = {}
local weaponCfg = Config.Weapons[Config.DefaultWeapon]

local function applySpread(dir: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return dir
	end
	local rad = math.rad(degrees)
	local ax = math.random() * 2 - 1
	local ay = math.random() * 2 - 1
	local randomVec = Vector3.new(ax, ay, 0) * math.tan(rad)
	local cam = CFrame.lookAt(Vector3.zero, dir)
	return (cam * CFrame.new(randomVec)).LookVector
end

FireRemote.OnServerEvent:Connect(function(player, origin, direction)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end

	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Simple fire-rate guard
	local now = os.clock()
	local last = lastFire[player]
	if last and now - last < weaponCfg.FireRate * 0.85 then
		return
	end
	lastFire[player] = now

	local dir = applySpread(direction.Unit, weaponCfg.Spread)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, dir * weaponCfg.Range, params)
	local endpoint = result and result.Position or (origin + dir * weaponCfg.Range)

	FireEffect:FireAllClients(origin, endpoint, weaponCfg.Color)

	if not result then
		return
	end

	local hit = result.Instance
	local hitModel = hit:FindFirstAncestorOfClass("Model")
	local hitHum = hitModel and hitModel:FindFirstChildOfClass("Humanoid")
	if not (hitModel and hitHum) then
		return
	end
	if hitHum == humanoid then
		return
	end

	local isHeadshot = hit.Name == "Head"
	local damage = weaponCfg.Damage
	if isHeadshot then
		damage *= weaponCfg.HeadshotMultiplier
	end

	if hitModel:GetAttribute("Enemy") then
		hitModel:SetAttribute("LastAttacker", player.UserId)
		hitModel:SetAttribute("LastHeadshot", isHeadshot)
	end

	local willKill = (hitHum.Health - damage) <= 0
	hitHum:TakeDamage(damage)

	HitConfirm:FireClient(player, {
		position = result.Position,
		damage = math.floor(damage),
		headshot = isHeadshot,
		killed = willKill,
	})
end)

Players.PlayerRemoving:Connect(function(player)
	lastFire[player] = nil
end)

-- ===========================================================================
-- Boot
-- ===========================================================================
setupLighting()
buildArena()
populateEnemies()

print(("[%s] Server ready. Game: %s"):format(TOOL_NAME, Config.GameName))
