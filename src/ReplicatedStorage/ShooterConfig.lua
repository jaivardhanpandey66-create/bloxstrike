--!strict
-- BLOXSTRIKE: Neon Arena
-- ShooterConfig
-- Shared tuning values used by both the server and the client.
-- Rojo: ModuleScript at ReplicatedStorage.ShooterConfig
-- Manual: create a ModuleScript named "ShooterConfig" in ReplicatedStorage.

local Config = {}

Config.GameName = "BLOXSTRIKE: Neon Arena"

-- ---------------------------------------------------------------------------
-- Weapons
-- ---------------------------------------------------------------------------
Config.Weapons = {
	Blaster = {
		DisplayName = "Neon Blaster",
		Damage = 24,
		HeadshotMultiplier = 2.0,
		FireRate = 0.10,          -- seconds between shots (~600 RPM)
		Automatic = true,
		Spread = 1.4,             -- cone half-angle in degrees
		Range = 500,              -- studs
		MagSize = 30,
		ReserveAmmo = 150,
		ReloadTime = 1.6,
		RecoilKick = 0.010,       -- radians added per shot
		RecoilRecovery = 12,      -- how fast recoil settles
		Color = Color3.fromRGB(80, 220, 255),
		ZoomFov = 55,
		DefaultFov = 70,
	},
}

Config.DefaultWeapon = "Blaster"

-- ---------------------------------------------------------------------------
-- Arena
-- ---------------------------------------------------------------------------
Config.Arena = {
	Size = 320,               -- total footprint (studs)
	WallHeight = 26,
	CoverCount = 34,
	GroundColor = Color3.fromRGB(24, 28, 38),
	WallColor = Color3.fromRGB(34, 40, 56),
	AccentColor = Color3.fromRGB(0, 225, 255),
	AccentColor2 = Color3.fromRGB(255, 60, 170),
}

-- ---------------------------------------------------------------------------
-- Enemies
-- ---------------------------------------------------------------------------
Config.Enemies = {
	Count = 10,
	MaxHealth = 100,
	WalkSpeed = 13,
	BodyColor = Color3.fromRGB(200, 55, 70),
	AttackRange = 6,          -- studs
	AttackDamage = 9,
	AttackCooldown = 0.9,
	RespawnDelay = 3,
	AggroRange = 400,         -- beyond this they wander
	ScorePerKill = 10,
}

-- ---------------------------------------------------------------------------
-- Player
-- ---------------------------------------------------------------------------
Config.Player = {
	MaxHealth = 100,
	WalkSpeed = 18,
	ScorePerKill = 10,
	HeadshotBonus = 5,
}

-- ---------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------
Config.Effects = {
	TracerLifetime = 0.09,
	HitmarkerTime = 0.12,
	DamageNumberTime = 0.8,
	MuzzleFlashTime = 0.05,
}

return Config
