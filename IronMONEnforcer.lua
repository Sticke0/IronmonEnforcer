local function IronMONEnforcer()
	-- Define descriptive attributes of the custom extension that are displayed on the Tracker settings
	local self = {}
	self.version = "0.1"
	self.name = "IronMON Enforcer"
	self.author = "Sticke"
	self.description = "Enforces the IronMON rules depending on which version you want to play"
	self.github = "Sticke0/IronMONEnforcer"
	self.url = string.format("https://github.com/%s", self.github or "") -- Remove this attribute if no host website available for this extension

	self.highestLevel = 0
	self.allowedGrind = 0
	self.allowXP = true
	self.allowCatch = true
	self.hasMadeDecisionPerEncounterArea = {}
	self.caughtPokemonCount = 0
	self.hasHMSlave = false
	self.shouldTrackBattle = false

	local VERSION = {
		STANDARD = 1,
		ULTIMATE = 2,
		KAIZO = 3,
	}

	self.mode = VERSION.KAIZO

	self.bannedItems = {
		{ [0xC5] = true, [0x2D] = true }, -- Lucky Egg, Sacred Ash
		{ [0xC8] = true, [0xBF] = true, [0xC3] = true }, -- Leftovers, Soul Dew, Everstone
		{ [0x27] = true, [0x28] = true, [0x29] = true, [0x2A] = true, [0x2B] = true }, -- Flutes
	}

	self.allowedBuy = {
		-- Balls
		[0x01] = true,
		[0x02] = true,
		[0x03] = true,
		[0x04] = true,
		[0x05] = true,
		[0x06] = true,
		[0x07] = true,
		[0x08] = true,
		[0x09] = true,
		[0x0A] = true,
		[0x0B] = true,
		[0x0C] = true,
		[0xC2] = true,
		[0xCA] = true,
		-- Repels
		[0x53] = true,
		[0x54] = true,
		[0x56] = true,
	}

	self.heldItemAllowed = {
		function(itemID)
			return self.bannedItems[VERSION.STANDARD][itemID] ~= true
		end,
		function(itemID)
			return self.bannedItems[VERSION.STANDARD][itemID] ~= true
				and self.bannedItems[VERSION.ULTIMATE][itemID] ~= true
		end,
		function(itemID)
			-- Allow berries
			if itemID >= 0x85 and itemID <= 0xAF then
				return true
			end

			-- Evolution stones
			if itemID >= 0x5D and itemID <= 0x62 then
				return true
			end

			-- Allow Deep Sea Tooth? (0xC0)
			-- Allow Deep Sea Scale? (0xC1)
			-- Allow Metal Coat? (0xC7)

			-- Other consumables
			if itemID == 0xB4 or itemID == 0xB9 or itemID == 0xC9 or itemID == 0xDA then
				return true
			end

			return false
		end,
		function(itemID)
			local mainPokemon = Tracker.getPokemon(1, true)
			local hasCut = false

			for i = 1, 4 do
				if mainPokemon.moves[i].id == 0x0F then
					hasCut = true
					break
				end
			end

			if not hasCut then
				return self.heldItemAllowed[VERSION.KAIZO](itemID)
			end

			-- Still ban Lucky Egg and Everstone
			return itemID ~= 0xC5 and itemID ~= 0xC3
		end,
	}

	--------------------------------------
	-- INTENRAL TRACKER FUNCTIONS BELOW
	-- Add any number of these below functions to your extension that you want to use.
	-- If you don't need a function, don't add it at all; leave ommitted for faster code execution.
	--------------------------------------

	function self.boolToBit(b)
		if b then
			return 1
		end
		return 0
	end

	function self.getAreaId()
		return Battle.CurrentRoute.encounterArea .. "-" .. Program.GameData.mapId
	end

	function self.getBagItemCount(itemID)
		local key = Utils.getEncryptionKey(2) -- Want a 16-bit key
		local saveBlock1Addr = Utils.getSaveBlock1Addr()
		local address = saveBlock1Addr + GameSettings.bagPocket_Items_offset
		local size = GameSettings.bagPocket_Items_Size

		for i = 0, (size - 1) do
			local itemid_and_quantity = Memory.readdword(address + i * 0x4)
			local itemid = Utils.getbits(itemid_and_quantity, 0, 16)

			if itemid == itemID then
				local quantity = Utils.getbits(itemid_and_quantity, 16, 16)

				if key ~= nil then
					quantity = Utils.bit_xor(quantity, key)
				end

				return quantity
			end
		end

		return 0
	end

	function self.getPCItemCount(itemID)
		local saveBlock1Addr = Utils.getSaveBlock1Addr()
		local address = saveBlock1Addr + 0x298
		local size = 30

		for i = 0, (size - 1) do
			local itemid_and_quantity = Memory.readdword(address + i * 0x4)
			local itemid = Utils.getbits(itemid_and_quantity, 0, 16)

			if itemid == itemID then
				local quantity = Utils.getbits(itemid_and_quantity, 16, 16)

				return quantity
			end
		end

		return 0
	end

	function self.setBagItemCount(itemID, ammount)
		local key = Utils.getEncryptionKey(2) -- Want a 16-bit key
		local saveBlock1Addr = Utils.getSaveBlock1Addr()
		local address = saveBlock1Addr + GameSettings.bagPocket_Items_offset
		local size = GameSettings.bagPocket_Items_Size
		local clear = ammount == 0

		if key ~= nil then
			ammount = Utils.bit_xor(ammount, key)
		end

		for i = 0, (size - 1) do
			local itemid_and_quantity = Memory.readdword(address + i * 0x4)
			local itemid = Utils.getbits(itemid_and_quantity, 0, 16)
			local quantity = Utils.getbits(itemid_and_quantity, 16, 16)

			if key ~= nil then
				quantity = Utils.bit_xor(quantity, key)
			end

			if itemid == 0 or quantity == 0 or itemid == itemID then
				if clear then
					itemID = 0
				end
				itemid_and_quantity = itemID + (ammount << 16)
				Memory.writedword(address + i * 0x4, itemid_and_quantity)
				break
			end
		end
	end

	function self.setPCItemCount(itemID, ammount)
		local saveBlock1Addr = Utils.getSaveBlock1Addr()
		local address = saveBlock1Addr + 0x298
		local size = 30
		local clear = ammount == 0

		for i = 0, (size - 1) do
			local itemid_and_quantity = Memory.readdword(address + i * 0x4)
			local itemid = Utils.getbits(itemid_and_quantity, 0, 16)
			local quantity = Utils.getbits(itemid_and_quantity, 16, 16)

			if itemid == 0 or quantity == 0 or itemid == itemID then
				if clear then
					itemID = 0
				end
				itemid_and_quantity = itemID + (ammount << 16)
				Memory.writedword(address + i * 0x4, itemid_and_quantity)
				break
			end
		end
	end

	function self.addItemToBag(itemID, ammount)
		local total = self.getBagItemCount(itemID) + ammount
		if total < 0 then
			total = 0
		end

		self.setBagItemCount(itemID, total)
	end

	function self.addItemToPC(itemID, ammount)
		local total = self.getPCItemCount(itemID) + ammount
		if total < 0 then
			total = 0
		end

		self.setPCItemCount(itemID, total)
	end

	function self.moveItem(itemID, toBag)
		if toBag == nil then
			toBag = false
		end

		if toBag then
			local itemCount = self.getBagItemCount(itemID) + self.getPCItemCount(itemID)
			self.setPCItemCount(itemID, 0)
			self.setBagItemCount(itemID, itemCount)
		else
			local itemCount = self.getBagItemCount(itemID) + self.getPCItemCount(itemID)
			self.setBagItemCount(itemID, 0)
			self.setPCItemCount(itemID, itemCount)
		end
	end

	function self.copyPokemon(source, destination)
		local addressOffsetSource = 100 * (source - 1)
		local addressOffsetDestination = 100 * (destination - 1)
		memory.write_bytes_as_array(
			GameSettings.pstats + addressOffsetSource,
			memory.read_bytes_as_array(GameSettings.pstats + addressOffsetDestination, 100)
		)
	end

	function self.tagPokemon(t)
		local index = t.index

		local addressOffset = 100 * (index - 1) + 0x1E
		local pokemonData = memory.read_u16_le(GameSettings.pstats + addressOffset)

		local isMain = Utils.getbits(pokemonData, 0, 1)
		local isSlave = Utils.getbits(pokemonData, 1, 1)
		local isDead = Utils.getbits(pokemonData, 2, 1)

		if t.isMain ~= nil then
			isMain = self.boolToBit(t.isMain)
		end
		if t.isSlave ~= nil then
			isSlave = self.boolToBit(t.isSlave)
		end
		if t.isDead ~= nil then
			isDead = self.boolToBit(t.isDead)
		end

		pokemonData = 0
		pokemonData = pokemonData | (isMain << 0)
		pokemonData = pokemonData | (isSlave << 1)
		pokemonData = pokemonData | (isDead << 2)

		memory.write_u16_le(GameSettings.pstats + addressOffset, pokemonData)
	end

	function self.getPokemonTags(index)
		local addressOffset = 100 * (index - 1) + 0x1E
		local pokemonData = memory.read_u16_le(GameSettings.pstats + addressOffset)

		local isMain = Utils.getbits(pokemonData, 0, 1)
		local isSlave = Utils.getbits(pokemonData, 1, 1)
		local isDead = Utils.getbits(pokemonData, 2, 1)

		return { isMain = isMain, isSlave = isSlave, isDead = isDead }
	end

	function self.killPokemon(i)
		local addressOffset = 100 * (i - 1)
		local personality = Memory.readdword(GameSettings.pstats + addressOffset)
		local trainerID = Memory.readdword(GameSettings.pstats + addressOffset + 4)

		if personality ~= 0 or trainerID ~= 0 then
			local pokemon = Program.readNewPokemon(GameSettings.pstats + addressOffset, personality)
			if Program.validPokemonData(pokemon) and pokemon.hp > 0 then
				memory.write_u8(GameSettings.pstats + addressOffset + 0x54, 0x01) -- Level
				memory.write_u32_le(GameSettings.pstats + addressOffset + 0x56, 0x00000000) -- Max Hp, Current Hp
				memory.write_u32_le(GameSettings.pstats + addressOffset + 0x5A, 0x00010000) -- Defense, Attack
				memory.write_u16_le(GameSettings.pstats + addressOffset + 0x5E, 0x0000) -- Speed
				memory.write_u32_le(GameSettings.pstats + addressOffset + 0x60, 0x00010000) -- Sp. Defense, Sp. Attack
			end

			self.tagPokemon({ index = i, isDead = true })
		end
	end

	function self.setPokemonItem(index, itemID)
		local addressOffset = 100 * (index - 1)
		-- Lookup information on the player's Pokemon first
		local personality = Memory.readdword(GameSettings.pstats + addressOffset)
		local trainerID = Memory.readdword(GameSettings.pstats + addressOffset + 4)

		local magicword = Utils.bit_xor(personality, trainerID) -- The XOR encryption key for viewing the Pokemon data

		local aux = personality % 24 + 1
		local growthoffset = (MiscData.TableData.growth[aux] - 1) * 12

		-- Pokemon Data substructure: https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_data_substructures_(Generation_III)
		local growth1 =
			Utils.bit_xor(Memory.readdword(GameSettings.pstats + addressOffset + 0x20 + growthoffset), magicword)
		local species = Utils.getbits(growth1, 0, 16)

		local itemDifference = itemID - Utils.getbits(growth1, 16, 16)

		growth1 = species | (itemID << 16)

		Memory.writedword(GameSettings.pstats + addressOffset + 0x20 + growthoffset, Utils.bit_xor(growth1, magicword))

		local checksum = memory.read_u16_le(GameSettings.pstats + addressOffset + 0x1C)
		checksum = checksum + itemDifference
		if checksum < 0 then
			checksum = 0xFFFF + checksum
		elseif checksum > 0xFFFF then
			checksum = checksum % 0x10000
		end

		memory.write_u16_le(GameSettings.pstats + addressOffset + 0x1C, checksum)
	end

	-- Executed when the user clicks the "Check for Updates" button while viewing the extension details within the Tracker's UI
	-- Returns [true, downloadUrl] if an update is available (downloadUrl auto opens in browser for user); otherwise returns [false, downloadUrl]
	-- Remove this function if you choose not to implement a version update check for your extension
	function self.checkForUpdates()
		-- Update the pattern below to match your version. You can check what this looks like by visiting the latest release url on your repo
		local versionResponsePattern = '"tag_name":%s+"%w+(%d+%.%d+)"' -- matches "1.0" in "tag_name": "v1.0"
		local versionCheckUrl = string.format("https://api.github.com/repos/%s/releases/latest", self.github or "")
		local downloadUrl = string.format("%s/releases/latest", self.url or "")
		local compareFunc = function(a, b)
			return a ~= b and not Utils.isNewerVersion(a, b)
		end -- if current version is *older* than online version
		local isUpdateAvailable =
			Utils.checkForVersionUpdate(versionCheckUrl, self.version, versionResponsePattern, compareFunc)
		return isUpdateAvailable, downloadUrl
	end

	-- Executed only once: When the extension is enabled by the user, and/or when the Tracker first starts up, after it loads all other required files and code
	function self.startup()
		-- Ensure player is able to select favorite & knows about it
		self.oldShowOnNewGameScreen = Options["Show on new game screen"]
		Options["Show on new game screen"] = true

    self.oldShowRandomBallPicker = Options["Show random ball picker"]
    Options["Show random ball picker"] = true
	end

	-- Executed only once: When the extension is disabled by the user, necessary to undo any customizations, if able
	function self.unload()
		Options["Show on new game screen"] = self.oldShowOnNewGameScreen
	  Options["Show random ball picker"] = self.oldShowRandomBallPicker
 end

	-- Executed once every 30 frames, after any battle related data from game memory is read in
	function self.afterBattleDataUpdate()
		if not self.allowXP then
			memory.write_u8(0x02023F4E, 0x00) -- Sets sent in to none, tricks the game into thinking no pokémon are available for XP
		end

		-- TODO: Check if has died
    -- Maybe not needed
	end

	function self.checkCatchability()
		-- Allows 1 Catch OR Kill
		local area = TrackerAPI.getMapId()
		if self.hasMadeDecisionPerEncounterArea[area] then
			self.allowCatch = false
			return
		end

		-- Allows for catching current level +4 & No Uber (600+ BST) (Kaizo only)
		if self.mode == VERSION.KAIZO then
			local wildPokemon = Tracker.getPokemon(1, false)
			local mainPokemon = Tracker.getPokemon(1, true)

			if
				wildPokemon.level > mainPokemon.level + 4
				or PokemonData.Pokemon[wildPokemon.pokemonID].bstCalculated >= 600
			then
				self.allowCatch = false
				return
			end
		end

		-- Only allow cathing 5 Pokémon for a total of 6
		-- Still allow cathing if you only have 1 pokemon left as safeguard for HM Friends
		-- Ultimate & Kaizo only
		if self.mode >= VERSION.ULTIMATE then
			local partySize = 0
			for i = 1, 6 do
				local pokemon = Tracker.getPokemon(i, true, false) or {}
				if PokemonData.isValid(pokemon.pokemonID) or pokemon.isEgg == 1 then
					partySize = partySize + 1
				end
			end

			if self.caughtPokemonCount > 5 and partySize == 1 then
				self.allowCatch = false
				return
			end
		end
	end

	function self.checkXPAbility()
		-- Shiny clause
		local wildPokemon = Tracker.getPokemon(1, false)
		if wildPokemon.isShiny then
			self.allowXP = true
			return
		end

		-- No Killing Wild Pokémon (Kaizo only)
		if self.mode == VERSION.KAIZO then
			self.allowXP = false
			return
		end

		-- Allow 1 Kill OR Catch (non Kaizo)
		local area = self.getAreaId()
		if self.hasMadeDecisionPerEncounterArea[area] then
			self.allowXP = false
			return
		end
	end

	function self.checkHeldItems()
		local mainPokemon = Tracker.getPokemon(1, true)

		-- Has not gotten pokémon yet
		if mainPokemon == nil then
			return
		end

		-- Pokémon is not holding an item
		if mainPokemon.heldItem == 0 then
			return
		end

		-- Check if Pokémon is holding an allowed item
		if self.heldItemAllowed[self.mode](mainPokemon.heldItem) then
			return
		end

		-- Remove the item from the Pokémon
		self.addItemToBag(mainPokemon.heldItem, 1)
		self.setPokemonItem(1, 0)
	end

	function self.moveContraband()
		local bannedItems = {}
		for i = 1, self.mode do
			for k, _ in pairs(self.bannedItems[i]) do
				bannedItems[#bannedItems + 1] = k
			end
		end

		for i = 1, #bannedItems do
			local itemID = bannedItems[i]
			local ammount = self.getBagItemCount(itemID)
			if ammount > 0 then
				self.moveItem(itemID) -- Moves to PC
			end
		end
	end

	-- Executed after a new battle begins (wild or trainer), and only once per battle
	function self.afterBattleBegins()
		-- Only 1 Main (Kaizo only)
		if self.mode == VERSION.KAIZO then
			for i = 2, 6 do
				self.killPokemon(i)
			end
		end

		self.checkHeldItems()

		if not Battle.isWildEncounter then
			self.trackBattle = false
			return
		end

		self.trackBattle = true

		self.checkCatchability()
		self.checkXPAbility()

		if not self.allowCatch then
			memory.write_u32_le(0x08250902, 0x00000000) -- Set ball multipliers as 0 (Still allows masterball, no fix for that yet)
		end
	end

	-- Executed after a battle ends, and only once per battle
	function self.afterBattleEnds()
		self.allowXP = true
		self.allowCatch = true
		memory.write_u32_le(0x08250902, 0x0F0A0F14) -- Set ball multipliers back to normal

		local mainPokemon = Tracker.getPokemon(1, true)
		if self.highestLevel < mainPokemon.level then
			self.highestLevel = mainPokemon.level
		end

		-- Check if any pokémon has died
    -- Probably unnecesary here

		if not self.trackBattle then
			return
		end

		-- Decision has been made
		local area = self.getAreaId()
		self.hasMadeDecisionPerEncounterArea[area] = true

		-- Pokémon was caught
		if memory.read_u8(0x02023E8A) == 0x07 then
			self.caughtPokemonCount = self.caughtPokemonCount + 1
		end
	end

	function self.enforceOptions()
		local saveBlock2 = memory.read_u32_le(0x0300500C) -- Save Block 2 (DMA Protected)

		memory.write_u8(saveBlock2 + 0x13, 1)

		local options = memory.read_u16_le(saveBlock2 + 0x14)
		local textSpeed = Utils.getbits(options, 0, 2)
		local frameType = Utils.getbits(options, 3, 5)
		local sound = Utils.getbits(options, 8, 1)
		local battleStyle = Utils.getbits(options, 9, 1)
		local battleSceneOff = Utils.getbits(options, 10, 1)
		local mapZoom = Utils.getbits(options, 11, 1)

		-- Battle style forced to "SET"
		if self.mode >= VERSION.ULTIMATE then
			battleStyle = 1
		end

		options = 0
		options = options | textSpeed
		options = options | (frameType << 3)
		options = options | (sound << 8)
		options = options | (battleStyle << 9)
		options = options | (battleSceneOff << 10)
		options = options | (mapZoom << 11)

		memory.write_u16_le(saveBlock2 + 0x14, options)
	end

	-- Executed once every 30 frames, after most data from game memory is read in
	function self.afterProgramDataUpdate()
		self.enforceOptions()
		self.checkHeldItems()

		-- Should we just delete instead of moving to PC?
		self.moveContraband()

		-- ReKill already dead Pokémon
		for i = 1, 6 do
			local tags = self.getPokemonTags(i)
			local pokemon = Tracker.getPokemon(i, true)
			if pokemon ~= nil and (tags.isDead or pokemon.hp == 0) then
				self.killPokemon(i)
			end
		end
	end

	return self
end

-- Override random balls (For favorite clause) 
-- TrackerScreen.randomlyChooseBall = function ()
--   local validPokemon = {}
--
--
-- 	-- TrackerScreen.PokeBalls.chosenBall = math.random(3)
-- 	return TrackerScreen.PokeBalls.chosenBall
-- end

return IronMONEnforcer
