-- Source: Scriptblox "[open source] Silent aim + Infinite Stamina + Tackle aim" (keyless, 540 views, 2026-11-23)
-- Game: Illegal Soccer (placeId 126987974021910)
-- Page: https://scriptblox.com/script/Illegal-Soccer-open-source-Silent-aim-Infinite-Stamina-Tackle-aim-238020
local rs, plrs, ws = game:GetService("ReplicatedStorage"), game:GetService("Players"), game:GetService("Workspace")
local lp = plrs.LocalPlayer

local chukunhax = {
	silent = true,
	hitchance = 80,
	corner = 78,
	spread = 1.4,
	perfectcharge = true,
	tackleaim = true,
	stamina = true,
}

local function mod(...)
	local n = rs
	for _, v in ipairs({ ... }) do n = n and n:FindFirstChild(v) end
	local ok, m = pcall(require, n)
	return ok and m or nil
end

local proto = mod("Modules", "Actions", "ActionRemoteProtocol")
local cmds = mod("Modules", "Actions", "ActionCommands")
local sprint = mod("Modules", "Actions", "Sprint")
local teams = mod("Client", "Gameplay", "ActorTeams")
local match = mod("Modules", "Gameplay", "MatchSettings")

local function getroot(c)
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function goals()
	local d = ws:FindFirstChild("Map") and ws.Map:FindFirstChild("Data")
	local a, b = d and d:FindFirstChild("Team1"), d and d:FindFirstChild("Team2")
	return a and a:FindFirstChild("Goal"), b and b:FindFirstChild("Goal")
end

local function enemygoal()
	local a, b = goals()
	if not (a and b) then return a or b end
	local ok, mine = pcall(teams.GetCharacterTeamName, lp.Character)
	local ok2, opp = ok and pcall(match.GetOpposingTeamName, mine)
	if ok2 and opp == "Team1" then return a end
	if ok2 and opp == "Team2" then return b end
	local r = getroot(lp.Character)
	if not r then return a end
	return (a.Position - r.Position).Magnitude > (b.Position - r.Position).Magnitude and a or b
end

local function keeper(goal)
	local best, dist = nil, 1e9
	for _, p in ipairs(plrs:GetPlayers()) do
		local r = p ~= lp and p.Team ~= lp.Team and getroot(p.Character)
		if r then
			local d = (r.Position - goal.Position).Magnitude
			if d < dist then best, dist = r, d end
		end
	end
	return best
end

local function spot(goal)
	local side = math.random() > 0.5 and 1 or -1
	local k = keeper(goal)
	if k then side = goal.CFrame:PointToObjectSpace(k.Position).X > 0 and -1 or 1 end
	local x = side * goal.Size.X / 2 * (chukunhax.corner / 100)
	local y = goal.Size.Y / 2 * 0.8
	local jx = (math.random() - 0.5) * 2 * chukunhax.spread
	local jy = (math.random() - 0.5) * chukunhax.spread
	return (goal.CFrame * CFrame.new(x + jx, y + jy, 0)).Position
end

local function isshot(c)
	if c.Mode == "Volley" then return true end
	if cmds and typeof(cmds.IsVolley) == "function" then
		local ok, v = pcall(cmds.IsVolley, c)
		if ok and v then return true end
	end
	return c.PassType == "Shot"
end

local function closest()
	local me = getroot(lp.Character)
	local best, dist = nil, 25
	for _, p in ipairs(plrs:GetPlayers()) do
		local r = p ~= lp and p.Team ~= lp.Team and getroot(p.Character)
		if r and me then
			local d = (r.Position - me.Position).Magnitude
			if d < dist then best, dist = p, d end
		end
	end
	return best
end

local function aimat(c, pos)
	local aim = c.AimDirection
	local has = typeof(aim) == "table"
	local origin = has and aim.Origin
	if typeof(origin) ~= "Vector3" then
		local r = getroot(lp.Character)
		origin = r and r.Position
	end
	if not origin or (pos - origin).Magnitude < 0.1 then return end
	local dir = (pos - origin).Unit
	if has then
		aim.TargetPosition = pos
		aim.Direction = dir
	end
	c.TargetPosition = pos
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude > 0 then c.KickDirection = flat.Unit end
end

local function edit(c)
	if chukunhax.perfectcharge and c.MaximumChargeSeconds then
		c.ChargeSeconds = c.MaximumChargeSeconds
	end
	if chukunhax.silent and isshot(c) and math.random(100) <= chukunhax.hitchance then
		local g = enemygoal()
		if g then aimat(c, spot(g)) end
	end
	if chukunhax.tackleaim and cmds and c.Kind == cmds.Kinds.Tackle and typeof(c.AimDirection) == "table" then
		local p = closest()
		local r = p and getroot(p.Character)
		if r then
			c.AimDirection.ClientHit = { Kind = "Player", UserId = p.UserId }
			c.TargetUserId = p.UserId
			aimat(c, r.Position)
		end
	end
end

for _, name in ipairs({ "Send", "Start", "Update", "Release" }) do
	local og = proto[name]
	if typeof(og) == "function" then
		proto[name] = function(c, ...)
			if typeof(c) == "table" then pcall(edit, c) end
			return og(c, ...)
		end
	end
end

if chukunhax.stamina and sprint and sprint.SetUnlimitedStamina then
	pcall(sprint.SetUnlimitedStamina, lp, "hax", true)
end