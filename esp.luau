local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local ESP = {}
ESP.__index = ESP

local DEFAULTS = {
	Enabled = true,
	MaxDistance = 2000,
	UseTeamCheck = false,
	OnlyIfAlive = false,
	Box = true,
	Outline = true,
	Name = true,
	Distance = true,
	BoxColor = Color3.fromRGB(255, 255, 255),
	OutlineColor = Color3.fromRGB(0, 0, 0),
	TextColor = Color3.fromRGB(255, 255, 255),
	DistanceColor = Color3.fromRGB(200, 200, 200),
	BoxThickness = 1,
	OutlineThickness = 3,
	TextSize = 13,
	Font = 2,
	WidthScale = 0.6,
	YPadding = 0,
	NameFormat = "%s",
	DistanceFormat = "[%dm]",
	Preset = nil,
	Whitelist = nil,
	Blacklist = nil,
}

local PRESETS = {}

local function copyTable(source)
	local result = {}
	for key, value in pairs(source or {}) do
		result[key] = value
	end
	return result
end

local function cloneOptions(options)
	local result = copyTable(DEFAULTS)
	for key, value in pairs(options or {}) do
		result[key] = value
	end
	return result
end

local function getCamera()
	return workspace.CurrentCamera
end

local function getPlayerCharacter(player)
	return player and player.Character or nil
end

local function getPlayerRootPart(player)
	local character = getPlayerCharacter(player)
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getLocalRootPart()
	return getPlayerRootPart(LocalPlayer)
end

local function getCharacterFromInstance(instance)
	if not instance then
		return nil
	end

	if instance:IsA("Player") then
		return getPlayerCharacter(instance)
	end

	if instance:IsA("Model") then
		return instance
	end

	if instance:IsA("Humanoid") then
		local parent = instance.Parent
		if parent and parent:IsA("Model") then
			return parent
		end
	end

	local model = instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return model
	end

	return nil
end

local function getTrackedPlayer(instance)
	if not instance then
		return nil
	end

	if instance:IsA("Player") then
		return instance
	end

	local character = getCharacterFromInstance(instance)
	if character then
		return Players:GetPlayerFromCharacter(character)
	end

	return nil
end

local function getModelSize(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local success, size = pcall(function()
		return model:GetExtentsSize()
	end)

	if success then
		return size
	end

	return nil
end

local function resolveAdornee(instance)
	if not instance or not instance.Parent then
		return nil
	end

	if instance:IsA("Player") then
		return getPlayerRootPart(instance)
	end

	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart
			or instance:FindFirstChild("HumanoidRootPart")
			or instance:FindFirstChildWhichIsA("BasePart", true)
	end

	if instance:IsA("Humanoid") then
		local model = instance.Parent
		if model and model:IsA("Model") then
			return model.PrimaryPart
				or model:FindFirstChild("HumanoidRootPart")
				or model:FindFirstChildWhichIsA("BasePart", true)
		end
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function createDrawing(drawType, props)
	local drawing = Drawing.new(drawType)
	for key, value in pairs(props) do
		drawing[key] = value
	end
	return drawing
end

local function createDrawings()
	return {
		Box = createDrawing("Square", { Visible = false, Filled = false }),
		Outline = createDrawing("Square", { Visible = false, Filled = false }),
		Name = createDrawing("Text", { Visible = false, Center = true, Outline = true }),
		Distance = createDrawing("Text", { Visible = false, Center = true, Outline = true }),
	}
end

local function hideDrawings(drawings)
	if not drawings then
		return
	end

	for _, drawing in pairs(drawings) do
		drawing.Visible = false
	end
end

local function removeDrawings(drawings)
	if not drawings then
		return
	end

	for _, drawing in pairs(drawings) do
		drawing:Remove()
	end
end

local function createFilter()
	return {
		Instances = {},
		Players = {},
		Names = {},
		UserIds = {},
		Teams = {},
		Count = 0,
	}
end

local function addFilterBucket(filter, bucketName, value)
	if value == nil or filter[bucketName][value] then
		return
	end

	filter[bucketName][value] = true
	filter.Count = filter.Count + 1
end

local function addFilterValue(filter, value)
	if value == nil then
		return
	end

	if typeof(value) == "Instance" then
		if value:IsA("Player") then
			addFilterBucket(filter, "Players", value)
			if value.UserId and value.UserId ~= 0 then
				addFilterBucket(filter, "UserIds", value.UserId)
			end
		else
			addFilterBucket(filter, "Instances", value)
		end
		return
	end

	if typeof(value) == "string" then
		addFilterBucket(filter, "Names", value)
		return
	end

	if typeof(value) == "number" then
		addFilterBucket(filter, "UserIds", value)
		return
	end
end

local function parseTeams(filter, teams)
	if type(teams) ~= "table" then
		if teams ~= nil then
			addFilterBucket(filter, "Teams", teams)
		end
		return
	end

	for index, value in pairs(teams) do
		if type(index) == "number" then
			addFilterBucket(filter, "Teams", value)
		elseif value == true then
			addFilterBucket(filter, "Teams", index)
		end
	end
end

local function parseFilterValues(filter, values)
	if type(values) ~= "table" then
		addFilterValue(filter, values)
		return
	end

	local hasArrayValues = #values > 0
	if hasArrayValues then
		for _, value in ipairs(values) do
			addFilterValue(filter, value)
		end
	end

	for key, value in pairs(values) do
		if type(key) ~= "number" then
			if key == "Instances" or key == "Players" or key == "Names" or key == "UserIds" then
				parseFilterValues(filter, value)
			elseif key == "Teams" then
				parseTeams(filter, value)
			elseif value == true then
				addFilterValue(filter, key)
			end
		end
	end
end

local function appendFilterValue(existingList, value)
	if type(existingList) ~= "table" then
		existingList = {}
	end

	table.insert(existingList, value)
	return existingList
end

local function normalizeFilter(values)
	if not values then
		return nil
	end

	local filter = createFilter()
	parseFilterValues(filter, values)

	if filter.Count == 0 then
		return nil
	end

	return filter
end

local function disconnectConnections(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
end

PRESETS.Default = {}

PRESETS.Player = {
	OnlyIfAlive = true,
	UseTeamCheck = true,
	GetAdornee = function(instance)
		return resolveAdornee(instance)
	end,
	GetSize = function(instance, adornee)
		local character = getCharacterFromInstance(instance)
		return getModelSize(character) or (adornee and adornee.Size) or Vector3.new(4, 6, 2)
	end,
	GetName = function(instance)
		local player = getTrackedPlayer(instance)
		if player then
			if player.DisplayName and player.DisplayName ~= player.Name then
				return string.format("%s (@%s)", player.DisplayName, player.Name)
			end
			return player.Name
		end

		local character = getCharacterFromInstance(instance)
		return character and character.Name or instance.Name
	end,
}

PRESETS.Character = {
	OnlyIfAlive = true,
	GetAdornee = function(instance)
		return resolveAdornee(instance)
	end,
	GetSize = function(instance, adornee)
		local character = getCharacterFromInstance(instance)
		return getModelSize(character) or (adornee and adornee.Size) or Vector3.new(4, 6, 2)
	end,
}

PRESETS.Object = {
	OnlyIfAlive = false,
}

function ESP.new(globalOptions)
	local self = setmetatable({}, ESP)
	self.globalOptions = cloneOptions(globalOptions)
	self.profiles = {}
	for name, preset in pairs(PRESETS) do
		self.profiles[name] = copyTable(preset)
	end
	self.entries = {}
	self.folderTrackers = {}
	self.playerTrackerConnections = {}
	self.whitelist = normalizeFilter(self.globalOptions.Whitelist)
	self.blacklist = normalizeFilter(self.globalOptions.Blacklist)
	self.connection = nil
	return self
end

function ESP:SetEnabled(enabled)
	self.globalOptions.Enabled = enabled
	if not enabled then
		for _, entry in pairs(self.entries) do
			hideDrawings(entry.drawings)
		end
	end
	return self
end

function ESP:Enable()
	return self:SetEnabled(true)
end

function ESP:Disable()
	return self:SetEnabled(false)
end

function ESP:Toggle(state)
	if state == nil then
		state = not self.globalOptions.Enabled
	end

	return self:SetEnabled(state)
end

function ESP:SetOptions(options)
	for key, value in pairs(options or {}) do
		self.globalOptions[key] = value
	end

	if options and options.Whitelist ~= nil then
		self.whitelist = normalizeFilter(options.Whitelist)
	end

	if options and options.Blacklist ~= nil then
		self.blacklist = normalizeFilter(options.Blacklist)
	end
	return self
end

function ESP:SetWhitelist(list)
	self.whitelist = normalizeFilter(list)
	self.globalOptions.Whitelist = list
	return self
end

function ESP:SetBlacklist(list)
	self.blacklist = normalizeFilter(list)
	self.globalOptions.Blacklist = list
	return self
end

function ESP:AddToWhitelist(value)
	local values = appendFilterValue(self.globalOptions.Whitelist, value)
	return self:SetWhitelist(values)
end

function ESP:AddToBlacklist(value)
	local values = appendFilterValue(self.globalOptions.Blacklist, value)
	return self:SetBlacklist(values)
end

function ESP:ClearWhitelist()
	return self:SetWhitelist(nil)
end

function ESP:ClearBlacklist()
	return self:SetBlacklist(nil)
end

function ESP:_resolvePreset(options)
	local merged = cloneOptions(options)
	if merged.Preset == nil then
		merged.Preset = self.globalOptions.Preset
	end
	local presetName = merged.Preset
	local preset = presetName and self.profiles[presetName] or nil
	if preset then
		for key, value in pairs(preset) do
			if merged[key] == nil then
				merged[key] = value
			end
		end
	end
	return merged
end

function ESP:_createEntry(instance, options)
	return {
		instance = instance,
		options = self:_resolvePreset(options),
		drawings = createDrawings(),
		manual = false,
		trackerRefs = 0,
	}
end

function ESP:_tryRemoveEntry(entry)
	if entry and not entry.manual and entry.trackerRefs <= 0 then
		self:Remove(entry.instance)
	end
end

function ESP:Add(instance, options)
	if not instance then
		return nil
	end

	if self.entries[instance] then
		return self.entries[instance]
	end

	local entry = self:_createEntry(instance, options)
	entry.manual = true
	self.entries[instance] = entry
	return entry
end

function ESP:Remove(instance)
	local entry = self.entries[instance]
	if not entry then
		return
	end

	removeDrawings(entry.drawings)
	self.entries[instance] = nil
	return self
end

function ESP:Clear()
	for _, tracker in pairs(self.folderTrackers) do
		disconnectConnections(tracker.connections)
	end

	self.folderTrackers = {}
	self:UntrackPlayers()

	for instance in pairs(self.entries) do
		self:Remove(instance)
	end
	return self
end

function ESP:Get(instance)
	return self.entries[instance]
end

function ESP:Has(instance)
	return self.entries[instance] ~= nil
end

function ESP:SetDefaultOptions(options)
	return self:SetOptions(options)
end

function ESP:SetDefaultPreset(name)
	self.globalOptions.Preset = name
	return self
end

function ESP:SetEntryOptions(instance, options)
	local entry = self.entries[instance]
	if not entry then
		return nil
	end
	entry.options = self:_resolvePreset(options)
	return entry
end

function ESP:RegisterPreset(name, options)
	if type(name) ~= "string" or name == "" then
		return nil
	end

	self.profiles[name] = copyTable(options or {})
	return self
end

function ESP:AddList(list, options)
	if type(list) ~= "table" then
		return self
	end

	for _, instance in ipairs(list) do
		self:Add(instance, options)
	end

	return self
end

function ESP:RemoveList(list)
	if type(list) ~= "table" then
		return self
	end

	for _, instance in ipairs(list) do
		self:Remove(instance)
	end

	return self
end

function ESP:_trackInstance(instance, options)
	local entry = self.entries[instance]
	if not entry then
		entry = self:_createEntry(instance, options)
		self.entries[instance] = entry
	end

	entry.trackerRefs = (entry.trackerRefs or 0) + 1
	return entry
end

function ESP:_untrackInstance(instance)
	local entry = self.entries[instance]
	if not entry then
		return
	end

	entry.trackerRefs = math.max((entry.trackerRefs or 0) - 1, 0)
	self:_tryRemoveEntry(entry)
end

function ESP:_getOption(entry, key)
	local value = entry.options[key]
	if value ~= nil then
		return value
	end
	return self.globalOptions[key]
end

function ESP:_matchesFilter(filter, entry)
	if not filter then
		return false
	end

	local instance = entry.instance
	local player = self:_getTrackedPlayer(entry)
	local displayName = self:_getDisplayName(entry)

	if filter.Instances[instance] then
		return true
	end

	if filter.Names[instance.Name] or filter.Names[displayName] then
		return true
	end

	if player then
		if filter.Players[player] then
			return true
		end
		if filter.UserIds[player.UserId] then
			return true
		end
		if filter.Names[player.Name] or filter.Names[player.DisplayName] then
			return true
		end
		if player.Team ~= nil and filter.Teams[player.Team] then
			return true
		end
	end

	return false
end

function ESP:_getTrackedPlayer(entry)
	local customPlayer = self:_getOption(entry, "Player")
	if customPlayer then
		return customPlayer
	end

	return getTrackedPlayer(entry.instance)
end

function ESP:_shouldSkip(entry)
	local instance = entry.instance
	if not instance or not instance.Parent then
		return true
	end

	local onlyIfAlive = self:_getOption(entry, "OnlyIfAlive")
	if onlyIfAlive then
		local character = getCharacterFromInstance(instance)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
		if not humanoid or humanoid.Health <= 0 then
			return true
		end
	end

	local trackedPlayer = self:_getTrackedPlayer(entry)
	if self:_getOption(entry, "UseTeamCheck") and trackedPlayer and LocalPlayer and LocalPlayer.Team ~= nil and trackedPlayer.Team == LocalPlayer.Team then
		return true
	end

	local entryWhitelist = normalizeFilter(self:_getOption(entry, "Whitelist"))
	if entryWhitelist and not self:_matchesFilter(entryWhitelist, entry) then
		return true
	end

	if self.whitelist and not self:_matchesFilter(self.whitelist, entry) then
		return true
	end

	local entryBlacklist = normalizeFilter(self:_getOption(entry, "Blacklist"))
	if entryBlacklist and self:_matchesFilter(entryBlacklist, entry) then
		return true
	end

	if self.blacklist and self:_matchesFilter(self.blacklist, entry) then
		return true
	end

	return false
end

function ESP:_getAdornee(entry)
	local custom = self:_getOption(entry, "GetAdornee")
	if custom then
		return custom(entry.instance)
	end
	return resolveAdornee(entry.instance)
end

function ESP:_getSize(entry, adornee)
	local custom = self:_getOption(entry, "GetSize")
	if custom then
		return custom(entry.instance, adornee)
	end

	local character = getCharacterFromInstance(entry.instance)
	return getModelSize(character) or adornee.Size
end

function ESP:_getDisplayName(entry)
	local custom = self:_getOption(entry, "GetName")
	if custom then
		return custom(entry.instance)
	end

	local trackedPlayer = self:_getTrackedPlayer(entry)
	if trackedPlayer then
		if trackedPlayer.DisplayName and trackedPlayer.DisplayName ~= trackedPlayer.Name then
			return string.format("%s (@%s)", trackedPlayer.DisplayName, trackedPlayer.Name)
		end
		return trackedPlayer.Name
	end

	return entry.instance.Name
end

function ESP:_formatName(entry, rawName)
	local formatter = self:_getOption(entry, "NameFormat")
	if type(formatter) == "function" then
		return formatter(entry.instance, rawName)
	end
	return string.format(formatter, rawName)
end

function ESP:_formatDistance(entry, distance)
	local formatter = self:_getOption(entry, "DistanceFormat")
	if type(formatter) == "function" then
		return formatter(entry.instance, distance)
	end
	return string.format(formatter, math.floor(distance))
end

function ESP:_getColor(entry, colorOptionName, fallbackOptionName, distance)
	local value = self:_getOption(entry, colorOptionName)
	if type(value) == "function" then
		return value(entry.instance, distance, self:_getTrackedPlayer(entry))
	end

	if value ~= nil then
		return value
	end

	return self:_getOption(entry, fallbackOptionName)
end

function ESP:_updateEntry(entry, camera, localRoot)
	if self:_shouldSkip(entry) then
		hideDrawings(entry.drawings)
		return
	end

	local adornee = self:_getAdornee(entry)
	if not adornee then
		hideDrawings(entry.drawings)
		return
	end

	local size = self:_getSize(entry, adornee)
	if not size then
		hideDrawings(entry.drawings)
		return
	end

	local distance = localRoot and (localRoot.Position - adornee.Position).Magnitude or math.huge
	if distance > self:_getOption(entry, "MaxDistance") then
		hideDrawings(entry.drawings)
		return
	end

	local center, visible = camera:WorldToViewportPoint(adornee.Position)
	if not visible then
		hideDrawings(entry.drawings)
		return
	end

	local yPadding = self:_getOption(entry, "YPadding")
	local heightOffset = (size.Y * 0.5) + yPadding
	local top = camera:WorldToViewportPoint(adornee.Position + Vector3.new(0, heightOffset, 0))
	local bottom = camera:WorldToViewportPoint(adornee.Position - Vector3.new(0, heightOffset, 0))

	local height = math.abs(top.Y - bottom.Y)
	local width = math.max(height * self:_getOption(entry, "WidthScale"), 4)
	local x = center.X - width / 2
	local y = top.Y

	local showBox = self:_getOption(entry, "Box")
	local showOutline = showBox and self:_getOption(entry, "Outline")
	entry.drawings.Box.Visible = showBox and self.globalOptions.Enabled
	entry.drawings.Outline.Visible = showOutline and self.globalOptions.Enabled
	if showBox then
		entry.drawings.Box.Color = self:_getColor(entry, "BoxColor", "TextColor", distance)
		entry.drawings.Box.Thickness = self:_getOption(entry, "BoxThickness")
		entry.drawings.Box.Position = Vector2.new(x, y)
		entry.drawings.Box.Size = Vector2.new(width, height)

		if showOutline then
			entry.drawings.Outline.Color = self:_getColor(entry, "OutlineColor", "BoxColor", distance)
			entry.drawings.Outline.Thickness = self:_getOption(entry, "OutlineThickness")
			entry.drawings.Outline.Position = Vector2.new(x - 1, y - 1)
			entry.drawings.Outline.Size = Vector2.new(width + 2, height + 2)
		end
	end

	local showName = self:_getOption(entry, "Name")
	entry.drawings.Name.Visible = showName and self.globalOptions.Enabled
	if showName then
		entry.drawings.Name.Text = self:_formatName(entry, self:_getDisplayName(entry))
		entry.drawings.Name.Color = self:_getColor(entry, "TextColor", "BoxColor", distance)
		entry.drawings.Name.Size = self:_getOption(entry, "TextSize")
		entry.drawings.Name.Font = self:_getOption(entry, "Font")
		entry.drawings.Name.Position = Vector2.new(center.X, y - 16)
	end

	local showDistance = self:_getOption(entry, "Distance")
	entry.drawings.Distance.Visible = showDistance and self.globalOptions.Enabled
	if showDistance then
		entry.drawings.Distance.Text = self:_formatDistance(entry, distance)
		entry.drawings.Distance.Color = self:_getColor(entry, "DistanceColor", "TextColor", distance)
		entry.drawings.Distance.Size = self:_getOption(entry, "TextSize")
		entry.drawings.Distance.Font = self:_getOption(entry, "Font")
		entry.drawings.Distance.Position = Vector2.new(center.X, y + height + 2)
	end
end

function ESP:_resolveTrackedInstance(candidate, options)
	if not candidate then
		return nil
	end

	local getInstance = options and options.GetInstance
	if getInstance then
		return getInstance(candidate)
	end

	if candidate:IsA("Player") then
		return candidate
	end

	local targetClass = options and options.TargetClass
	if targetClass and not candidate:IsA(targetClass) then
		return nil
	end

	if options and options.RequireHumanoid then
		local character = getCharacterFromInstance(candidate)
		if not character or not character:FindFirstChildOfClass("Humanoid") then
			return nil
		end
	end

	return candidate
end

function ESP:AddFolder(folder, options)
	if not folder or self.folderTrackers[folder] then
		return self.folderTrackers[folder]
	end

	local tracker = {
		folder = folder,
		options = copyTable(options or {}),
		connections = {},
	}

	local useDescendants = tracker.options.Descendants ~= false

	local function addCandidate(candidate)
		local instance = self:_resolveTrackedInstance(candidate, tracker.options)
		if instance and instance ~= folder then
			self:_trackInstance(instance, tracker.options)
		end
	end

	local function removeCandidate(candidate)
		local instance = self:_resolveTrackedInstance(candidate, tracker.options)
		if instance then
			self:_untrackInstance(instance)
		end
	end

	if useDescendants then
		for _, descendant in ipairs(folder:GetDescendants()) do
			addCandidate(descendant)
		end

		table.insert(tracker.connections, folder.DescendantAdded:Connect(addCandidate))
		table.insert(tracker.connections, folder.DescendantRemoving:Connect(removeCandidate))
	else
		for _, child in ipairs(folder:GetChildren()) do
			addCandidate(child)
		end

		table.insert(tracker.connections, folder.ChildAdded:Connect(addCandidate))
		table.insert(tracker.connections, folder.ChildRemoved:Connect(removeCandidate))
	end

	self.folderTrackers[folder] = tracker
	return tracker
end

function ESP:AddFolderChildren(folder, options)
	local folderOptions = copyTable(options or {})
	folderOptions.Descendants = false
	self:AddFolder(folder, folderOptions)
	return self
end

function ESP:AddFolderDescendants(folder, options)
	local folderOptions = copyTable(options or {})
	folderOptions.Descendants = true
	self:AddFolder(folder, folderOptions)
	return self
end

function ESP:RemoveFolder(folder)
	local tracker = self.folderTrackers[folder]
	if not tracker then
		return self
	end

	disconnectConnections(tracker.connections)

	local useDescendants = tracker.options.Descendants ~= false
	local existing = useDescendants and folder:GetDescendants() or folder:GetChildren()
	for _, candidate in ipairs(existing) do
		local instance = self:_resolveTrackedInstance(candidate, tracker.options)
		if instance then
			self:_untrackInstance(instance)
		end
	end

	self.folderTrackers[folder] = nil
	return self
end

function ESP:TrackPlayers(options)
	if #self.playerTrackerConnections > 0 then
		return self
	end

	local trackerOptions = copyTable(options or {})
	trackerOptions.Preset = trackerOptions.Preset or "Player"

	local function addPlayer(player)
		if player ~= LocalPlayer then
			self:_trackInstance(player, trackerOptions)
		end
	end

	local function removePlayer(player)
		self:_untrackInstance(player)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		addPlayer(player)
	end

	table.insert(self.playerTrackerConnections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(self.playerTrackerConnections, Players.PlayerRemoving:Connect(removePlayer))
	return self
end

function ESP:UntrackPlayers()
	if #self.playerTrackerConnections == 0 then
		return self
	end

	disconnectConnections(self.playerTrackerConnections)
	self.playerTrackerConnections = {}

	for _, player in ipairs(Players:GetPlayers()) do
		self:_untrackInstance(player)
	end
	return self
end

function ESP:Update()
	if not self.globalOptions.Enabled then
		for _, entry in pairs(self.entries) do
			hideDrawings(entry.drawings)
		end
		return
	end

	local camera = getCamera()
	if not camera then
		return
	end

	local localRoot = getLocalRootPart()

	for instance, entry in pairs(self.entries) do
		if not instance or not instance.Parent then
			self:Remove(instance)
		else
			self:_updateEntry(entry, camera, localRoot)
		end
	end
end

function ESP:Start()
	if self.connection then
		return self
	end

	self.connection = RunService.RenderStepped:Connect(function()
		self:Update()
	end)
	return self
end

function ESP:Stop()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end

	for _, entry in pairs(self.entries) do
		hideDrawings(entry.drawings)
	end
	return self
end

ESP.add = ESP.Add
ESP.remove = ESP.Remove
ESP.clear = ESP.Clear
ESP.start = ESP.Start
ESP.stop = ESP.Stop
ESP.get = ESP.Get
ESP.has = ESP.Has
ESP.toggle = ESP.Toggle
ESP.enable = ESP.Enable
ESP.disable = ESP.Disable
ESP.setOptions = ESP.SetOptions
ESP.setDefaultOptions = ESP.SetDefaultOptions
ESP.setDefaultPreset = ESP.SetDefaultPreset
ESP.setEntryOptions = ESP.SetEntryOptions
ESP.registerPreset = ESP.RegisterPreset
ESP.addList = ESP.AddList
ESP.removeList = ESP.RemoveList
ESP.addFolderChildren = ESP.AddFolderChildren
ESP.addFolderDescendants = ESP.AddFolderDescendants

return ESP
