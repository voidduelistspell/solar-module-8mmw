-- Robscript Team - In This World
-- Game: In This World | placeId 98272441761103 | creator "In This Group..."
-- Window: RightControl | Unload: Settings -> Unload | API: getgenv().RobScriptITW
--
-- What it does:
--   World    - reads the current world and its rule straight from the game UI (InThisWorldUI),
--              shows alive count and round time, and assists: auto walk, auto jump, freeze,
--              unchaining in Chained, auto revive.
--   Players  - live roster with level, wins, credits and distance, player ESP, teleport helpers.
--   Movement - speed, jump, infinite jump, fly, noclip, anti fall, saved position.
--   Visuals  - fullbright, no fog, hidden screen effects, field of view.
--   Rewards  - auto claim of the game's own claim buttons plus a progress readout.
--
-- Everything here is client side. Wins, XP and Credits are server owned, so the hub never
-- tries to fake them: it only reads attributes and helps you actually survive the rounds.

do
	local existing = getgenv().RobScriptITW
	if type(existing) == "table" and type(existing.Destroy) == "function" then
		pcall(existing.Destroy)
	end
end

----- Services -----

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local VERSION = "1.0"
local STOP = false
local CONNECTIONS = {}

local function track(connection)
	if connection then
		table.insert(CONNECTIONS, connection)
	end
	return connection
end

----- Library -----

local LIBRARY_URLS = {
	"https://raw.githubusercontent.com/bobloscript/Robly_Airflow/main/Source.luau",
	"https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau",
}

local Airflow = nil
local fallbackLibrary = nil
for _, url in ipairs(LIBRARY_URLS) do
	local ok, library = pcall(function()
		return loadstring(game:HttpGet(url))()
	end)
	if ok and type(library) == "table" and type(library.CreateWindow) == "function" then
		if not fallbackLibrary then
			fallbackLibrary = library
		end
		if type(library.ThemePresets) == "table" then
			Airflow = library
			break
		end
	end
end

Airflow = Airflow or fallbackLibrary

if not Airflow then
	error("[RobScript ITW] Airflow UI could not be loaded")
end

----- Theme -----

local THEME = {
	Background = Color3.fromHex("#0A0A0C"),
	Surface = Color3.fromHex("#141418"),
	Surface2 = Color3.fromHex("#1A1A20"),
	Surface3 = Color3.fromHex("#2A2A33"),
	Stroke = Color3.fromHex("#26262E"),
	StrokeHover = Color3.fromHex("#3C3C49"),
	Accent = Color3.fromHex("#FF3B7F"),
	AccentDark = Color3.fromHex("#1A0710"),
	Text = Color3.fromHex("#F5F5F7"),
	Muted = Color3.fromHex("#8D8D99"),
}

Airflow.ThemePresets.Robscript = THEME
Airflow:SetDefaultTheme(THEME)

----- Language -----


----- State -----

local S = {
	SpeedOn = false,
	SpeedValue = 60,
	JumpOn = false,
	JumpValue = 70,
	InfJump = false,
	FlyOn = false,
	FlySpeed = 55,
	Noclip = false,
	AntiFall = false,
	EspOn = false,
	AutoJump = false,
	AutoWalk = false,
	Freeze = false,
	Unchain = false,
	AutoRevive = false,
	AutoClaim = false,
	Fullbright = false,
	NoFog = false,
	HideFx = false,
	Fov = 70,
	SavedPosition = nil,
}

local RUNTIME = {
	WorldName = "Lobby",
	Rule = "",
	Detail = "",
	Alive = 0,
	Total = 0,
	RoundStart = os.clock(),
	LastWorld = "",
}

local DEFAULTS = nil

----- Helpers -----

local function escapeText(text)
	if type(text) ~= "string" then
		return ""
	end
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	return text
end

local function shortNumber(value)
	value = tonumber(value) or 0
	if value >= 1000000 then
		return string.format("%.1fM", value / 1000000)
	elseif value >= 1000 then
		return string.format("%.1fk", value / 1000)
	end
	return tostring(math.floor(value))
end

local function getCharacter()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil
end

local function isAlive(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function distanceToRoot(root)
	local _, _, myRoot = getCharacter()
	if not root or not myRoot then
		return 0
	end
	return math.floor((root.Position - myRoot.Position).Magnitude)
end

local function pressButton(button)
	if not button or not button:IsA("TextButton") then
		return false
	end
	if type(firesignal) ~= "function" then
		return false
	end
	local ok = pcall(firesignal, button.Activated)
	return ok
end

local function visibleButton(pattern, onlyIn)
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	for _, object in ipairs(playerGui:GetDescendants()) do
		if object:IsA("TextButton") and object.Visible and object.Text and object.Text:lower():find(pattern) then
			local screen = object:FindFirstAncestorWhichIsA("ScreenGui")
			if screen and screen.Enabled and (not onlyIn or screen.Name == onlyIn) then
				return object
			end
		end
	end
	return nil
end

----- World reading -----

local function readWorld()
	local name = "Lobby"
	for _, object in ipairs(Workspace:GetChildren()) do
		if object:IsA("Model") and object.Name ~= "Lobby" and object.Name ~= "Sea" and object.Name ~= LocalPlayer.Name then
			local humanoid = object:FindFirstChildOfClass("Humanoid")
			if not humanoid and #object:GetChildren() >= 8 then
				name = object.Name
				break
			end
		end
	end

	local rule = ""
	local detail = ""
	local ui = LocalPlayer.PlayerGui:FindFirstChild("InThisWorldUI")
	if ui then
		for _, object in ipairs(ui:GetDescendants()) do
			if object:IsA("TextLabel") and object.Text and #object.Text > 12 and object.Name ~= "IntroTitle" then
				if object.Name == "IntroLine" then
					rule = object.Text
				elseif #object.Text > #detail and object.Text ~= rule then
					detail = object.Text
				end
			end
		end
	end

	if name ~= RUNTIME.WorldName then
		RUNTIME.RoundStart = os.clock()
	end
	RUNTIME.WorldName = name
	RUNTIME.Rule = rule
	RUNTIME.Detail = detail

	local alive = 0
	local total = 0
	for _, player in ipairs(Players:GetPlayers()) do
		total = total + 1
		if isAlive(player) then
			alive = alive + 1
		end
	end
	RUNTIME.Alive = alive
	RUNTIME.Total = total
end

----- ESP -----

local function espFor(player)
	local character = player.Character
	if not character or character == LocalPlayer.Character then
		return nil, nil
	end
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid then
		return nil, nil
	end

	local highlight = character:FindFirstChild("RT_Highlight")
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "RT_Highlight"
		highlight.Adornee = character
		highlight.FillColor = Color3.fromHex("#FF3B7F")
		highlight.FillTransparency = 0.7
		highlight.OutlineColor = Color3.fromHex("#FFFFFF")
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = character
	end

	local billboard = head:FindFirstChild("RT_Esp")
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "RT_Esp"
		billboard.Size = UDim2.fromOffset(190, 40)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 400
		billboard.Adornee = head
		billboard.Parent = head

		local label = Instance.new("TextLabel")
		label.Name = "Info"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = Color3.fromRGB(245, 245, 247)
		label.TextStrokeTransparency = 0.4
		label.RichText = true
		label.Parent = billboard
	end

	return billboard, humanoid
end

local function clearEsp()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local highlight = character:FindFirstChild("RT_Highlight")
			if highlight then
				highlight:Destroy()
			end
			local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
			local billboard = head and head:FindFirstChild("RT_Esp")
			if billboard then
				billboard:Destroy()
			end
		end
	end
end

local function updateEsp()
	if not S.EspOn then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local billboard, humanoid = espFor(player)
			if billboard and humanoid then
				local label = billboard:FindFirstChild("Info")
				if label then
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					local distance = root and distanceToRoot(root) or 0
					local level = player:GetAttribute("Level") or 1
					local wins = player:GetAttribute("ITW_Wins") or 0
					local health = math.floor(humanoid.Health)
					local color = health > 50 and "#78F06E" or (health > 20 and "#FFDE00" or "#FF4D5E")
					label.Text = string.format(
						"<b>%s</b>  <font color='#8D8D99'>L%s W%s</font>\n<font color='%s'>%d HP</font> <font color='#8D8D99'>· %dm</font>",
						escapeText(player.Name),
						tostring(level),
						tostring(wins),
						color,
						health,
						distance
					)
				end
			end
		end
	end
end

----- Movement helpers -----

local flyVelocity = nil

local function stopFly()
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end
end

local function stepFly(humanoid, root)
	if not flyVelocity or flyVelocity.Parent ~= root then
		stopFly()
		flyVelocity = Instance.new("BodyVelocity")
		flyVelocity.Name = "RT_Fly"
		flyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		flyVelocity.Parent = root
	end

	local camera = Workspace.CurrentCamera
	local direction = Vector3.zero
	if camera then
		local look = camera.CFrame.LookVector
		local right = camera.CFrame.RightVector
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			direction = direction + look
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			direction = direction - look
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			direction = direction + right
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			direction = direction - right
		end
	end

	if direction.Magnitude < 0.05 and humanoid.MoveDirection.Magnitude > 0.05 then
		direction = humanoid.MoveDirection
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		direction = direction + Vector3.yAxis
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		direction = direction - Vector3.yAxis
	end

	if direction.Magnitude < 0.05 then
		flyVelocity.Velocity = Vector3.zero
	else
		flyVelocity.Velocity = direction.Unit * S.FlySpeed
	end
end

local function teleportTo(position)
	local _, _, root = getCharacter()
	if not root then
		return false
	end
	root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	return true
end

local function restoreCollision()
	local character = LocalPlayer.Character
	if not character then
		return
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = true
		end
	end
end

----- Visuals -----

local function storeLighting()
	if DEFAULTS then
		return
	end
	DEFAULTS = {
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		ClockTime = Lighting.ClockTime,
		GlobalShadows = Lighting.GlobalShadows,
		FogEnd = Lighting.FogEnd,
		FogStart = Lighting.FogStart,
	}
end

local function applyVisuals()
	storeLighting()
	if S.Fullbright then
		Lighting.Brightness = 2
		Lighting.Ambient = Color3.fromRGB(150, 150, 160)
		Lighting.OutdoorAmbient = Color3.fromRGB(175, 175, 185)
		Lighting.ClockTime = 12
		Lighting.GlobalShadows = false
	else
		Lighting.Brightness = DEFAULTS.Brightness
		Lighting.Ambient = DEFAULTS.Ambient
		Lighting.OutdoorAmbient = DEFAULTS.OutdoorAmbient
		Lighting.ClockTime = DEFAULTS.ClockTime
		Lighting.GlobalShadows = DEFAULTS.GlobalShadows
	end

	if S.NoFog then
		Lighting.FogEnd = 1000000
		Lighting.FogStart = 1000000
	else
		Lighting.FogEnd = DEFAULTS.FogEnd
		Lighting.FogStart = DEFAULTS.FogStart
	end

	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = S.Fov
	end
end

local WINDOW = nil
local LOG = nil

----- Window -----

WINDOW = Airflow:CreateWindow({
	Name = "In This World",
	LoadingSubtitle = "worlds, players, movement",
	ToggleUIKeybind = "RightControl",
	Size = UDim2.fromOffset(780, 540),
	Backdrop = { Weather = "Fireflies", Tint = 0.35 },
	Theme = THEME,
	ConfigurationSaving = { Enabled = true, FolderName = "RobScriptITW" },
	Home = {
		Title = "In This World",
		Welcome = "Welcome back,",
		Tier = "v" .. VERSION,
		Stats = { "Players", "Session", "FPS", "Ping", "Game", "Executor" },
	},
})

local LogsTab = WINDOW:CreateTab({ Name = "Logs", Icon = "scroll-text" })
local LogsBox = LogsTab:CreateGroupbox({ Name = "Activity", Side = "Left" })
LOG = LogsBox:CreateLog({
	Name = "Activity",
	MaxEntries = 300,
	MaxRows = 14,
	Timestamps = true,
	EmptyText = "Nothing yet",
})

local function log(text, tone)
	if LOG then
		LOG:Push(text, tone)
	end
end

----- World tab -----

local WorldTab = WINDOW:CreateTab({ Name = "World", Icon = "globe" })
local RoundBox = WorldTab:CreateGroupbox({ Name = "Round", Side = "Left" })
local AssistBox = WorldTab:CreateGroupbox({ Name = "Assist", Side = "Right" })

RoundBox:CreateLabel({
	Name = "World",
	UpdateRate = 0.5,
	Update = function()
		return "<Accent>" .. escapeText(RUNTIME.WorldName) .. "</Accent>"
	end,
})

RoundBox:CreateLabel({
	Name = "Rule",
	UpdateRate = 0.5,
	Update = function()
		if RUNTIME.Rule == "" then
			return "<Muted>detecting...</Muted>"
		end
		return escapeText(RUNTIME.Rule)
	end,
})

RoundBox:CreateLabel({
	Name = "Detail",
	UpdateRate = 0.5,
	Update = function()
		return "<Muted>" .. escapeText(RUNTIME.Detail) .. "</Muted>"
	end,
})

RoundBox:CreateLabel({
	Name = "Alive",
	UpdateRate = 0.5,
	Update = function()
		return string.format("Alive <Accent>%d</Accent> / %d", RUNTIME.Alive, RUNTIME.Total)
	end,
})

RoundBox:CreateLabel({
	Name = "Round time",
	UpdateRate = 1,
	Update = function()
		local seconds = math.max(0, math.floor(os.clock() - RUNTIME.RoundStart))
		return string.format("Round time <Accent>%02d:%02d</Accent>", math.floor(seconds / 60), seconds % 60)
	end,
})

AssistBox:CreateToggle({
	Name = "Auto walk",
	Desc = "Keeps you moving, for Keep Walking",
	Flag = "AutoWalk",
	CurrentValue = false,
	Callback = function(value)
		S.AutoWalk = value
		log(value and "Auto walk on" or "Auto walk off", value and "Success" or nil)
	end,
})

AssistBox:CreateToggle({
	Name = "Auto jump",
	Desc = "Jumps every moment you touch the ground",
	Flag = "AutoJump",
	CurrentValue = false,
	Callback = function(value)
		S.AutoJump = value
	end,
})

AssistBox:CreateToggle({
	Name = "Freeze position",
	Desc = "Stops your character, for Statue and Simon Says",
	Flag = "Freeze",
	CurrentValue = false,
	Callback = function(value)
		S.Freeze = value
	end,
})

AssistBox:CreateToggle({
	Name = "Unchain me",
	Desc = "Ignores the chain pull in Chained",
	Flag = "Unchain",
	CurrentValue = false,
	Callback = function(value)
		S.Unchain = value
	end,
})

AssistBox:CreateToggle({
	Name = "Auto revive",
	Desc = "Presses the game's own Revive button",
	Flag = "AutoRevive",
	CurrentValue = false,
	Callback = function(value)
		S.AutoRevive = value
	end,
})

----- Players tab -----

local PlayersTab = WINDOW:CreateTab({ Name = "Players", Icon = "users" })
local RosterBox = PlayersTab:CreateGroupbox({ Name = "Roster", Side = "Left" })
local PlayersBox = PlayersTab:CreateGroupbox({ Name = "Actions", Side = "Right" })

RosterBox:CreateLabel({
	Name = "Roster",
	UpdateRate = 1,
	Update = function()
		local rows = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local level = player:GetAttribute("Level") or 1
			local wins = player:GetAttribute("ITW_Wins") or 0
			local credits = player:GetAttribute("Credits") or 0
			local streak = player:GetAttribute("Streak") or 0
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local distance = root and distanceToRoot(root) or 0
			rows[#rows + 1] = {
				level = level,
				text = string.format(
					"%s%s <font color='#8D8D99'>L%s · W%s · C%s · %dm</font>",
					isAlive(player) and "<font color='#78F06E'>●</font> " or "<font color='#FF4D5E'>●</font> ",
					escapeText(player.Name),
					tostring(level),
					tostring(wins),
					shortNumber(credits),
					distance
				),
				streak = streak,
			}
		end
		table.sort(rows, function(a, b)
			return a.level > b.level
		end)
		local lines = {}
		for index = 1, math.min(#rows, 12) do
			lines[#lines + 1] = rows[index].text
		end
		if #lines == 0 then
			return "<Muted>Reading the server</Muted>"
		end
		return table.concat(lines, "\n")
	end,
})

local PlayerDropdown = nil

local function refreshPlayerOptions()
	if not PlayerDropdown then
		return
	end
	local options = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			options[#options + 1] = player.Name
		end
	end
	PlayerDropdown:SetOptions(options, { KeepSelection = true, Silent = true })
end

PlayerDropdown = PlayersBox:CreateDropdown({
	Name = "Player",
	Options = {},
	Flag = "PlayerTarget",
	Callback = function() end,
})

PlayersBox:CreateButton({
	Name = "Teleport to player",
	Callback = function()
		local targetName = PlayerDropdown.Value
		local target = targetName and Players:FindFirstChild(targetName)
		if not target then
			WINDOW:Notify({ Title = "Player", Content = "No player selected", Type = "Warning" })
			return
		end
		local character = target.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		if teleportTo(root.Position) then
			log("Teleported to " .. escapeText(target.Name))
		end
	end,
})

PlayersBox:CreateButton({
	Name = "Teleport to cursor",
	Callback = function()
		local mouse = LocalPlayer:GetMouse()
		if mouse and mouse.Hit then
			teleportTo(mouse.Hit.Position)
		end
	end,
})

PlayersBox:CreateButton({
	Name = "Save position",
	Callback = function()
		local _, _, root = getCharacter()
		if not root then
			WINDOW:Notify({ Title = "Position", Content = "No character yet", Type = "Warning" })
			return
		end
		S.SavedPosition = root.Position
		WINDOW:Notify({ Title = "Position", Content = "Saved", Type = "Success" })
	end,
})

PlayersBox:CreateButton({
	Name = "Return to saved",
	Callback = function()
		if not S.SavedPosition then
			WINDOW:Notify({ Title = "Position", Content = "No saved position", Type = "Warning" })
			return
		end
		teleportTo(S.SavedPosition)
	end,
})

PlayersBox:CreateToggle({
	Name = "Player ESP",
	Desc = "Names, distance and health above every player",
	Flag = "PlayerEsp",
	CurrentValue = false,
	Callback = function(value)
		S.EspOn = value
		if not value then
			clearEsp()
		end
	end,
})

----- Movement tab -----

local MovementTab = WINDOW:CreateTab({ Name = "Movement", Icon = "move" })
local MovementBox = MovementTab:CreateGroupbox({ Name = "Movement", Side = "Left" })
local SafetyBox = MovementTab:CreateGroupbox({ Name = "Safety", Side = "Right" })

MovementBox:CreateToggle({
	Name = "Speed hack",
	Desc = "Overrides your walk speed",
	Flag = "SpeedHack",
	CurrentValue = false,
	Callback = function(value)
		S.SpeedOn = value
	end,
})

MovementBox:CreateSlider({
	Name = "Walk speed",
	Range = { 20, 220 },
	Increment = 5,
	Suffix = " studs",
	CurrentValue = 60,
	Flag = "WalkSpeed",
	DependsOn = "SpeedHack",
	Callback = function(value)
		S.SpeedValue = value
	end,
})

MovementBox:CreateToggle({
	Name = "Jump boost",
	Desc = "Overrides your jump power",
	Flag = "JumpBoost",
	CurrentValue = false,
	Callback = function(value)
		S.JumpOn = value
	end,
})

MovementBox:CreateSlider({
	Name = "Jump power",
	Range = { 60, 320 },
	Increment = 10,
	CurrentValue = 70,
	Flag = "JumpPower",
	DependsOn = "JumpBoost",
	Callback = function(value)
		S.JumpValue = value
	end,
})

MovementBox:CreateToggle({
	Name = "Infinite jump",
	Desc = "Lets you jump again in mid air",
	Flag = "InfiniteJump",
	CurrentValue = false,
	Callback = function(value)
		S.InfJump = value
	end,
})

MovementBox:CreateToggle({
	Name = "Fly",
	Desc = "Camera direction, Space up, Ctrl down",
	Flag = "Fly",
	CurrentValue = false,
	Callback = function(value)
		S.FlyOn = value
		if not value then
			stopFly()
		end
	end,
})

MovementBox:CreateSlider({
	Name = "Fly speed",
	Range = { 20, 220 },
	Increment = 5,
	CurrentValue = 55,
	Flag = "FlySpeed",
	DependsOn = "Fly",
	Callback = function(value)
		S.FlySpeed = value
	end,
})

SafetyBox:CreateToggle({
	Name = "Noclip",
	Desc = "Walk through walls",
	Flag = "Noclip",
	CurrentValue = false,
	Callback = function(value)
		S.Noclip = value
		if not value then
			restoreCollision()
		end
	end,
})

SafetyBox:CreateToggle({
	Name = "Anti fall",
	Desc = "Pulls you back before you fall out of the map",
	Flag = "AntiFall",
	CurrentValue = false,
	Callback = function(value)
		S.AntiFall = value
	end,
})

----- Visuals tab -----

local VisualsTab = WINDOW:CreateTab({ Name = "Visuals", Icon = "eye" })
local SceneBox = VisualsTab:CreateGroupbox({ Name = "Scene", Side = "Left" })

SceneBox:CreateToggle({
	Name = "Fullbright",
	Desc = "Brighter scene, no darkness",
	Flag = "Fullbright",
	CurrentValue = false,
	Callback = function(value)
		S.Fullbright = value
		applyVisuals()
	end,
})

SceneBox:CreateToggle({
	Name = "No fog",
	Desc = "Removes fog in water and fog worlds",
	Flag = "NoFog",
	CurrentValue = false,
	Callback = function(value)
		S.NoFog = value
		applyVisuals()
	end,
})

SceneBox:CreateToggle({
	Name = "Hide screen effects",
	Desc = "Hurt flash, flashes and shake overlays",
	Flag = "HideFx",
	CurrentValue = false,
	Callback = function(value)
		S.HideFx = value
	end,
})

SceneBox:CreateSlider({
	Name = "Field of view",
	Range = { 60, 120 },
	Increment = 1,
	CurrentValue = 70,
	Flag = "Fov",
	Callback = function(value)
		S.Fov = value
		applyVisuals()
	end,
})

SceneBox:CreateButton({
	Name = "Reset visuals",
	Callback = function()
		S.Fullbright = false
		S.NoFog = false
		S.Fov = 70
		applyVisuals()
		pcall(function()
			Airflow.Flags.Fullbright:Set(false, true)
			Airflow.Flags.NoFog:Set(false, true)
			Airflow.Flags.Fov:Set(70, true)
		end)
	end,
})

----- Rewards tab -----

local RewardsTab = WINDOW:CreateTab({ Name = "Rewards", Icon = "gift" })
local ClaimBox = RewardsTab:CreateGroupbox({ Name = "Claim", Side = "Left" })
local ProgressBox = RewardsTab:CreateGroupbox({ Name = "Progress", Side = "Right" })

local function claimRewards()
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return 0
	end
	local claimed = 0
	for _, object in ipairs(playerGui:GetDescendants()) do
		if claimed >= 4 then
			break
		end
		if object:IsA("TextButton") and object.Visible and object.Text then
			local text = object.Text:lower()
			if (text:find("claim") or text:find("collect") or text:find("free reward")) and not text:find("revive") then
				local screen = object:FindFirstAncestorWhichIsA("ScreenGui")
				if screen and screen.Enabled and pressButton(object) then
					claimed = claimed + 1
				end
			end
		end
	end
	return claimed
end

ClaimBox:CreateToggle({
	Name = "Auto claim rewards",
	Desc = "Clicks every claim button the game shows",
	Flag = "AutoClaim",
	CurrentValue = false,
	Callback = function(value)
		S.AutoClaim = value
		log(value and "Auto claim on" or "Auto claim off", value and "Success" or nil)
	end,
})

ClaimBox:CreateButton({
	Name = "Claim now",
	Callback = function()
		local claimed = claimRewards()
		if claimed > 0 then
			WINDOW:Notify({ Title = "Rewards", Content = "Claimed", Type = "Success" })
		else
			WINDOW:Notify({ Title = "Rewards", Content = "No claim button found", Type = "Warning" })
		end
	end,
})

ProgressBox:CreateLabel({
	Name = "Credits",
	UpdateRate = 1,
	Update = function()
		return string.format("Credits <Accent>%s</Accent>", shortNumber(LocalPlayer:GetAttribute("Credits")))
	end,
})

ProgressBox:CreateLabel({
	Name = "Wins",
	UpdateRate = 1,
	Update = function()
		return string.format(
			"Wins <Accent>%s</Accent> · Streak <Accent>%s</Accent>",
			tostring(LocalPlayer:GetAttribute("ITW_Wins") or 0),
			tostring(LocalPlayer:GetAttribute("Streak") or 0)
		)
	end,
})

ProgressBox:CreateLabel({
	Name = "Level",
	UpdateRate = 1,
	Update = function()
		return string.format(
			"Level <Accent>%s</Accent> · XP %s/%s",
			tostring(LocalPlayer:GetAttribute("Level") or 1),
			tostring(LocalPlayer:GetAttribute("XP") or 0),
			tostring(LocalPlayer:GetAttribute("XPNeed") or 0)
		)
	end,
})

----- Settings tab -----

local SettingsTab = WINDOW:CreateTab({ Name = "Settings", Icon = "settings" })
SettingsTab:CreateConfigManager({ Name = "Configs", Side = "Left" })
SettingsTab:CreateThemeManager({ Name = "Theme", Side = "Right" })

local UnloadBox = SettingsTab:CreateGroupbox({ Name = "Keys", Side = "Right" })
UnloadBox:CreateParagraph({
	Title = "RightControl",
	Content = "RightControl hides and shows this window.",
})

UnloadBox:CreateButton({
	Name = "Unload",
	Style = "Primary",
	Callback = function()
		pcall(function()
			local api = getgenv().RobScriptITW
			if api and api.Destroy then
				api.Destroy()
			end
		end)
	end,
})

----- Runtime loops -----

local function cleanup()
	STOP = true
	stopFly()
	clearEsp()
	restoreCollision()
	if DEFAULTS then
		S.Fullbright = false
		S.NoFog = false
		pcall(applyVisuals)
	end
	for _, connection in ipairs(CONNECTIONS) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	CONNECTIONS = {}
	if WINDOW then
		pcall(function()
			WINDOW:Destroy()
		end)
	end
end

getgenv().RobScriptITW = {
	Version = VERSION,
	State = S,
	Runtime = RUNTIME,
	Airflow = Airflow,
	Log = function(text, tone)
		log(text, tone)
	end,
	Destroy = cleanup,
}

-- Character changes: clear ESP and drop fly body mover so nothing sticks to a new body.
track(LocalPlayer.CharacterAdded:Connect(function()
	stopFly()
	clearEsp()
	if LOG then
		log("Character spawned")
	end
end))

track(Players.PlayerAdded:Connect(function()
	refreshPlayerOptions()
end))
track(Players.PlayerRemoving:Connect(function()
	refreshPlayerOptions()
end))

-- Infinite jump
track(UserInputService.JumpRequest:Connect(function()
	if not S.InfJump then
		return
	end
	local _, humanoid = getCharacter()
	if humanoid then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end)
	end
end))

-- Unchain: swallow the chain pull traffic the client script sends.
do
	local root = ReplicatedStorage:FindFirstChild("InThisWorld")
	local chainRemote = root and root:FindFirstChild("ChainedPull")
	if chainRemote and type(hookmetamethod) == "function" then
		local original
		local ok = pcall(function()
			original = hookmetamethod(game, "__namecall", function(self, ...)
				if S.Unchain and self == chainRemote then
					local method = getnamecallmethod()
					if method == "FireServer" or method == "InvokeServer" then
						return
					end
				end
				return original(self, ...)
			end)
		end)
		if not ok then
			log("Unchain is not available in this executor", "Warning")
		end
	end
end

-- Main per-frame loop: movement, safety, visuals that must not drift.
track(RunService.Heartbeat:Connect(function()
	if STOP then
		return
	end

	local character, humanoid, root = getCharacter()
	if character and humanoid and root then
		if S.Freeze then
			humanoid.WalkSpeed = 0
			humanoid:Move(Vector3.zero, false)
		else
			if S.SpeedOn then
				if not S.BaseWalkSpeed then
					S.BaseWalkSpeed = humanoid.WalkSpeed
				end
				humanoid.WalkSpeed = S.SpeedValue
			elseif S.BaseWalkSpeed then
				humanoid.WalkSpeed = S.BaseWalkSpeed
				S.BaseWalkSpeed = nil
			end
			if S.JumpOn then
				if not S.BaseJumpPower then
					S.BaseJumpPower = humanoid.JumpPower
				end
				pcall(function()
					humanoid.UseJumpPower = true
					humanoid.JumpPower = S.JumpValue
				end)
			elseif S.BaseJumpPower then
				pcall(function()
					humanoid.JumpPower = S.BaseJumpPower
				end)
				S.BaseJumpPower = nil
			end
		end

		if S.FlyOn then
			stepFly(humanoid, root)
		elseif flyVelocity then
			stopFly()
		end

		if S.Noclip then
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					part.CanCollide = false
				end
			end
		end

		if S.AutoWalk and not S.Freeze then
			local camera = Workspace.CurrentCamera
			if camera then
				local direction = camera.CFrame.LookVector
				direction = Vector3.new(direction.X, 0, direction.Z)
				if direction.Magnitude > 0.05 then
					humanoid:Move(direction.Unit, false)
				end
			end
		end

		if S.AntiFall and root.Position.Y < -60 then
			teleportTo(S.SavedPosition or Vector3.new(0, 220, 0))
			log("Anti fall pulled you back", "Warning")
		end
	end
end))

-- Slow loop: world reading, assists, ESP refresh, visuals re-apply.
local lastClaimAt = 0
task.spawn(function()
	while not STOP do
		local ok, errorMessage = pcall(function()
			readWorld()

			if S.AutoJump then
				local _, humanoid = getCharacter()
				if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
					humanoid.Jump = true
				end
			end

			if S.AutoRevive then
				local deathScreen = LocalPlayer.PlayerGui:FindFirstChild("ITW_DeathScreen")
				if deathScreen and (not deathScreen:IsA("ScreenGui") or deathScreen.Enabled) then
					local button = nil
					for _, object in ipairs(deathScreen:GetDescendants()) do
						if object:IsA("TextButton") and object.Visible and object.Text and object.Text:lower():find("revive") then
							button = object
							break
						end
					end
					if button and pressButton(button) then
						log("Revive pressed")
					end
				end
			end

			if S.EspOn then
				updateEsp()
			end

			if S.HideFx then
				local effects = { "HurtFlash", "ITW_CameraFlash", "ITW_WorldFlash", "ITW_PromptDim", "Skull", "Nuke", "ITW_NukeFX" }
				for _, name in ipairs(effects) do
					local gui = LocalPlayer.PlayerGui:FindFirstChild(name)
					if gui then
						if gui:IsA("ScreenGui") then
							gui.Enabled = false
						elseif gui:IsA("ImageLabel") or gui:IsA("GuiObject") then
							gui.Visible = false
						end
					end
				end
			end

			if S.AutoClaim and os.clock() - lastClaimAt >= 5 then
				lastClaimAt = os.clock()
				local claimed = claimRewards()
				if claimed > 0 and LOG then
					log(string.format("Claimed %d reward(s)", claimed))
				end
			end
		end)
		if not ok then
			if LOG then
				LOG:Push("Loop error: " .. tostring(errorMessage), "Error")
			end
		end
		task.wait(0.5)
	end
end)

-- Keep the warm/cold look stable when the game swaps worlds and resets Lighting.
task.spawn(function()
	while not STOP do
		if S.Fullbright or S.NoFog or S.Fov ~= 70 then
			pcall(applyVisuals)
		end
		task.wait(3)
	end
end)

refreshPlayerOptions()

WINDOW:LoadAutoload()

WINDOW:Notify({ Title = "Loaded", Content = "In This World hub is ready", Type = "Success" })
if LOG then
	log(string.format("<Success>Hub v%s loaded</Success>", VERSION))
	log("<Muted>RightControl hides the window</Muted>")
end
