-- Connected Discord-GitHub : Roblox Username: squiddy092 : Discord Username: tyler.is.cool

-- // CONFIGURATION

local SPEED = 100
local ROTATION_SPEED = 20
local HITBOX_SIZE = 4

-- // SERVICES

local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Projectile variables

local Projectile = {}
Projectile.__index = Projectile

-- Reuse one RaycastParams instance globally to save memory and avoid garbage collection lag
local ProjectileParams = RaycastParams.new()
ProjectileParams.FilterType = Enum.RaycastFilterType.Exclude
ProjectileParams.IgnoreWater = true

-- Pre-create OverlapParams so we aren't creating a new object every frame
local BoxOverlapParams = OverlapParams.new()
BoxOverlapParams.FilterType = Enum.RaycastFilterType.Exclude

-- // FUNCTIONS

-- Initialize projectile
function Projectile.new(player: Player, originCframe: CFrame, targetPos: Vector3)
	local self = setmetatable({}, Projectile)
	
	-- Player and character references are explained when used later in the script
	self.Player = player
	self.Character = player.Character or player.CharacterAdded:Wait()
	self.HumanoidRootPart = self.Character:WaitForChild("HumanoidRootPart")

	self.Origin = originCframe.Position
	self.Target = targetPos
	self.CurrentPosition = originCframe.Position
	self.TimePassed = 0
	self.Returning = false
	self.Active = true

	self.Hits = {}

	self.Direction = (self.Target - self.Origin).Unit
	self.Distance = (self.Target - self.Origin).Magnitude

	-- Randomly choose left or right offset so multiple projectiles don't stack perfectly on top of each other
	local randomOffset = math.random(1, 2) == 1 and 1 or -1

	self.RightVector = originCframe.RightVector * (self.Distance * .25) * randomOffset
	self.UpVector = Vector3.new(0, math.random(2, 5), 0)

	-- Create the physical projectile part
	self:CreateProjectile(originCframe)

	return self
end

-- Create actual projectile
function Projectile:CreateProjectile(origin: CFrame)
	local part = Instance.new("Part")
	part.Size = Vector3.new(4, 1, 1)
	part.Color = Color3.fromRGB(255, 0, 0)
	part.Material = Enum.Material.Neon
	part.CanCollide = false
	part.Anchored = true
	part.CFrame = origin
	part.Parent = workspace

	-- Set up attachments on both sides of the part to define the trail width
	local attachment0 = Instance.new("Attachment")
	attachment0.Position = Vector3.new(0, 2, 0)
	attachment0.Parent = part

	local attachment1 = Instance.new("Attachment")
	attachment1.Position = Vector3.new(0, -2, 0)
	attachment1.Parent = part

	-- Creating a trail for aesthetics
	local trail = Instance.new("Trail")
	-- Trail works between two attachments
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.FaceCamera = true
	trail.Lifetime = 0.4
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(part.Color)
	trail.Parent = part

	self.Part = part
end

-- Projectile movement using "Bezier Curve"
function Projectile:GetPath(t: number): Vector3
	if not self.Returning then
		-- Quadratic Bezier curve that arcs outward on the way to the target
		local p = self.Origin:Lerp(self.Target, .5) + self.RightVector
		return (1 - t)^2 * self.Origin + 2 * (1 - t) * t * p + t^2 * self.Target
	else
		-- Return path that arcs symmetrically back to the player's current position
		local returnTarget = self.HumanoidRootPart.Position
		local leftVector = -self.RightVector
		-- Linear interpolation between the projectile's current position and the player's position
		local p = self.Origin:Lerp(returnTarget, .5) + leftVector
		return (1 - t)^2 * self.Origin + 2 * (1 - t) * t * p + t^2 * returnTarget
	end
end

-- Use raycasts to see if the projectile has hit anything
function Projectile:HasLanded(lastPos: Vector3, currentPos: Vector3): boolean
	local dir = currentPos - lastPos
	local dis = dir.Magnitude

	-- Don't raycast if the projectile didn't move
	if dis <= 0 then 
		return false 
	end

	-- Ignore the shooter and the projectile itself
	ProjectileParams.FilterDescendantsInstances = {self.Character, self.Part}

	-- Fires a ray from the projectile's last position to its direction
	local result = workspace:Raycast(lastPos, dir.Unit * dis, ProjectileParams)

	if not result then 
		return false 
	end

	local hit: BasePart = result.Instance
	local targetModel = hit:FindFirstAncestorOfClass("Model")
	local hum: Humanoid = targetModel and targetModel:FindFirstChildOfClass("Humanoid")

	-- Make sure we only hit living players/NPCs
	if hum and hum.Health > 0 then
		self:Hit(hum)
		return true
	end

	return false
end

-- Update the projectile's position and spin
function Projectile:Update(deltaTime: number)
	-- Break out if the projectile or player gets destroyed elsewhere
	if not self.Active or not self.Part or not self.HumanoidRootPart then 
		self:Destroy()
		return
	end

	self.TimePassed += deltaTime
	local lastPosition = self.CurrentPosition

	-- Calculate the alpha (0 to 1) based on speed and distance
	local totalDuration = self.Distance / SPEED
	local t = math.clamp(self.TimePassed / totalDuration, 0, 1)

	if not self.Returning then
		self.CurrentPosition = self:GetPath(t)

		-- Switch to return mode once it reaches the target destination
		if t >= 1 then
			self.Returning = true
			self.TimePassed = 0
			self.Origin = self.CurrentPosition
		end
	else
		self.CurrentPosition = self:GetPath(t)

		local returnTarget = self.HumanoidRootPart.Position
		-- Check if it made it back, or got close enough to the hitbox to count as caught
		if t >= 1 or (self.CurrentPosition - returnTarget).Magnitude <= HITBOX_SIZE then
			self:Destroy()
			return
		end
	end

	-- Function returns a boolean if it hits a target by firing raycasts
	local didHit = self:HasLanded(lastPosition, self.CurrentPosition)

	-- Update hitbox filter to ignore shooter and projectile
	BoxOverlapParams.FilterDescendantsInstances = {self.Character, self.Part}

	-- Gets all parts in a cubical region of the projectile
	local partsInBox = workspace:GetPartBoundsInBox(self.Part.CFrame, Vector3.new(HITBOX_SIZE, HITBOX_SIZE, HITBOX_SIZE), BoxOverlapParams)

	-- Secondary hitbox check to catch fast-moving targets that raycasts might miss
	for _, part in partsInBox do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			didHit = true
			self:Hit(hum)
			break
		end
	end

	-- Calculate spinning rotation
	local spinAngle = self.TimePassed * ROTATION_SPEED
	local newDir = self.CurrentPosition - lastPosition

	-- Avoid CFrame errors/stuttering if the projectile isn't moving
	if newDir.Magnitude > 0.001 then
		self.Part.CFrame = CFrame.lookAt(self.CurrentPosition, self.CurrentPosition + newDir.Unit) * CFrame.Angles(0, spinAngle, 0)
	else
		self.Part.CFrame = CFrame.new(self.CurrentPosition) * CFrame.Angles(0, spinAngle, 0)
	end
end

-- On hit
function Projectile:Hit(hum: Humanoid)
	-- Debounce using the humanoid object to prevent damaging the same target multiple times
	if not self.Hits[hum] then
		self.Hits[hum] = true
		-- Damage the player hit
		hum:TakeDamage(50)

		local targetHrp = hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart")

		if targetHrp then
			-- Created and play the sound
			local hitSound = Instance.new("Sound")
			hitSound.SoundId = "rbxassetid://140731142140725"
			hitSound.Volume = 0.4
			hitSound.Parent = targetHrp
			hitSound:Play()

			-- Destroy the sound after 1.5 seconds
			Debris:AddItem(hitSound, 1.5)
		end
	end
end

-- Destroy projectile and all memory associated with it
function Projectile:Destroy()
	-- Prevent this function from running twice if called multiple times in one frame
	if not self.Active then
		return
	end

	self.Active = false

	if self.Part then
		local part = self.Part
		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(part, tweenInfo, {Transparency = 1, Size = Vector3.new(0,0,0)})

		-- Clean up the part once the fade-out tween finishes
		tween.Completed:Connect(function()
			part:Destroy()
		end)

		tween:Play()
	end

	-- Clear references to prevent memory leaks
	self.Player = nil
	self.Character = nil
	self.HumanoidRootPart = nil
	self.Hits = nil
	self.Part = nil
end

-- // ENGINE

local CurrentProjectiles = {}

-- Heartbeat loop for updating the projectile's position
RunService.Heartbeat:Connect(function(deltaTime: number)
	-- Loop backwards so we can safely remove dead projectiles without breaking the table
	for index = #CurrentProjectiles, 1, -1 do
		local projectile = CurrentProjectiles[index]

		if projectile.Active then
			projectile:Update(deltaTime)
		else
			table.remove(CurrentProjectiles, index)
		end
	end
end)

-- For cooldowns
local Debounces = {}

-- Remote event to launch a projectile (fired from client on click)
ReplicatedStorage.LaunchProjectile.OnServerEvent:Connect(function(player: Player, targetPos: Vector3)
	-- If the player is not on cooldown then
	if not Debounces[player] then
		-- Put them on cooldown
		Debounces[player] = true

		-- Define some variables of the player
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if hrp and humanoid and humanoid.Health > 0 then
			-- If they're alive then
			local spawnCFrame = hrp.CFrame * CFrame.new(0, 0, -3)
			-- Create a new projectile at the spawnCFrame we just determined
			local newProjectile = Projectile.new(player, spawnCFrame, targetPos)
			table.insert(CurrentProjectiles, newProjectile)
		end

		-- 1 second cooldown
		task.wait(1)

		Debounces[player] = false
	end
end)

-- Memory cleanup
PlayerService.PlayerRemoving:Connect(function(player)
	if Debounces[player] then
		Debounces[player] = nil
	end
end)
