-- Connected Discord-GitHub | Roblox Username: squiddy092 | Discord Username: tyler.is.cool

-- // CONFIGURATION

local SPEED = 100
local ROTATION_SPEED = 20
local HITBOX_SIZE = 2.5

-- // SERVICES

local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Projectile variables

local Projectile = {}
Projectile.__index = Projectile

local ProjectileParams = RaycastParams.new()
ProjectileParams.FilterType = Enum.RaycastFilterType.Exclude
ProjectileParams.IgnoreWater = true

-- // FUNCTIONS

-- Initialize projectile
function Projectile.new(player: Player, originCframe: CFrame, targetPos: Vector3)
	local self = setmetatable({}, Projectile) :: any

	self.Player = player
	self.Character = player.Character or player.CharacterAdded:Wait()
	self.HumanoidRootPart = self.Character:WaitForChild("HumanoidRootPart") :: BasePart

	self.Origin = originCframe.Position
	self.Target = targetPos
	self.CurrentPosition = originCframe.Position
	self.TimePassed = 0
	self.Returning = false
	self.Active = true

	self.Hits = {}

	self.Direction = (self.Target - self.Origin).Unit
	self.Distance = (self.Target - self.Origin).Magnitude

	self.RightVector = originCframe.RightVector * (self.Distance * .25)

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

	-- Trail setup for aesthetics
	local attachment0 = Instance.new("Attachment", part)
	attachment0.Position = Vector3.new(0, 2, 0)
	local attachment1 = Instance.new("Attachment", part)
	attachment1.Position = Vector3.new(0, -2, 0)

	local trail = Instance.new("Trail")
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
		-- If it's going outward
		local p = self.Origin:Lerp(self.Target, .5) + self.RightVector

		--Implemented bezier curve equation
		return (1 - t)^2 * self.Origin + 2 * (1 - t) * t * p + t^2 * self.Target
	else
		-- Returning to player
		local returnTarget = self.HumanoidRootPart.Position
		local leftVector = -self.RightVector
		local p = self.Origin:Lerp(returnTarget, .5) + leftVector

		--Implemented bezier curve equation
		return (1 - t)^2 * self.Origin + 2 * (1 - t) * t * p + t^2 * returnTarget
	end
end

-- Use raycasts to see if the projectile has hit anything
function Projectile:HasLanded(lastPos: Vector3, currentPos: Vector3): boolean
	local dir = currentPos - lastPos
	local dis = dir.Magnitude

	if dis <= 0 then 
		return false 
	end

	-- So that it doesn't detect the player who threw it or itself as a hit
	ProjectileParams.FilterDescendantsInstances = {self.Character, self.Part}

	local result = workspace:Raycast(lastPos, dir.Unit * dis, ProjectileParams)
	
	if not result then 
		return false 
	end

	local hit: BasePart = result.Instance
	local targetModel = hit:FindFirstAncestorOfClass("Model")
	local hum: Humanoid = targetModel and targetModel:FindFirstChildOfClass("Humanoid")

	-- If we hit a player and they're alive then continue
	if hum and hum.Health > 0 then
		self:Hit(hum)
		return true
	end

	return false
end

-- Update the projectile's position and spin
function Projectile:Update(deltaTime: number)
	-- If it is being destroyed then don't continue, since this is a function that's being run continously we
	-- don't want to risk running it while the projectile is being destroyed to prevent errors
	if not self.Active or not self.Part or not self.HumanoidRootPart then return end

	self.TimePassed += deltaTime
	-- Updating new position, so old position is the current position
	local lastPosition = self.CurrentPosition

	-- Total time it will take
	local totalDuration = self.Distance / SPEED
	-- % of time has passed
	local t = math.clamp(self.TimePassed / totalDuration, 0, 1)

	if not self.Returning then
		-- Going outward
		self.CurrentPosition = self:GetPath(t)

		if t >= 1 then
			self.Returning = true
			self.TimePassed = 0
			self.Origin = self.CurrentPosition
		end
	else
		-- Homing back to player
		self.CurrentPosition = self:GetPath(t)

		local returnTarget = self.HumanoidRootPart.Position
		-- Distance-based check to see if it hit the target
		if t >= 1 or (self.CurrentPosition - returnTarget).Magnitude <= HITBOX_SIZE then
			self:Destroy()
			return
		end
	end

	-- If we have already hit something then we don't have to continue
	local didHit = self:HasLanded(lastPosition, self.CurrentPosition)
	
	if didHit then return end

	-- CFrame and spinning math
	local spinAngle = self.TimePassed * ROTATION_SPEED
	local newDir = self.CurrentPosition - lastPosition

	if newDir.Magnitude > 0.001 then
		self.Part.CFrame = CFrame.lookAt(self.CurrentPosition, self.CurrentPosition + newDir.Unit) * CFrame.Angles(0, spinAngle, 0)
	else
		self.Part.CFrame = CFrame.new(self.CurrentPosition) * CFrame.Angles(0, spinAngle, 0)
	end
end

-- On hit
function Projectile:Hit(hum: Humanoid)
	if not self.Hits[hum] then
		self.Hits[hum] = true
		hum:TakeDamage(50)

		-- Audio on hit
		local targetHrp = hum.Parent and hum.Parent:FindFirstChild("HumanoidRootPart")
		
		if targetHrp then
			local hitSound = Instance.new("Sound")
			hitSound.SoundId = "rbxassetid://140731142140725"
			hitSound.Volume = 0.4
			hitSound.Parent = targetHrp
			hitSound:Play()

			Debris:AddItem(hitSound, 1.5)
		end
	end
end

-- Destroy projectile and all memory associated with it
function Projectile:Destroy()
	-- Don't start destroying if it's already being destroyed
	if not self.Active then return end
	
	self.Active = false

	if self.Part then
		-- Smoothly fade it away rather than instantly delete it
		local part = self.Part
		local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(part, tweenInfo, {Transparency = 1, Size = Vector3.new(0,0,0)})

		tween.Completed:Connect(function()
			part:Destroy()
		end)

		tween:Play()
	end

	-- Erasing the memory
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
	for index = #CurrentProjectiles, 1, -1 do
		local projectile = CurrentProjectiles[index]
		
		if projectile.Active then
			projectile:Update(deltaTime)
		else
			table.remove(CurrentProjectiles, index)
		end
	end
end)

-- Remote event to launch a projectile (fired from client on click)
ReplicatedStorage.LaunchProjectile.OnServerEvent:Connect(function(player: Player, targetPos: Vector3)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- Ensure player is alive
	if hrp and humanoid and humanoid.Health > 0 then
		local spawnCFrame = hrp.CFrame * CFrame.new(0, 0, -3)
		local newProjectile = Projectile.new(player, spawnCFrame, targetPos)
		table.insert(CurrentProjectiles, newProjectile)
	end
end)
