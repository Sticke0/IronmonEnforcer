local customCodeFolder = FileManager.getCustomFolderPath() .. "\\IronmonEnforcer\\"
local utils = dofile(customCodeFolder .. "Utils.lua")
local CONSTANT = dofile(customCodeFolder .. "Constants.lua")
local SelectionScreen = dofile(customCodeFolder .. "Display.lua")

local function IronmonEnforcer()
	-- Constants/Plugin info
	local self = {}
	self.version = "0.3"
	self.name = "Ironmon Enforcer"
	self.author = "Sticke"
	self.description = "Enforces the Ironmon rules depending on which version you want to play"
	self.github = "Sticke0/IronmonEnforcer"
	self.url = string.format("https://github.com/%s", self.github or "")

	-- Options
	self.mode = CONSTANT.VERSION.KAIZO

	-- Variables
	self.allowXP = true
	self.allowCatch = true
	self.shouldTrackBattle = false
	self.startedWithoutItem = {}
	self.mustBeSlave = false
	-- self.highestLevel = 0
	-- self.allowedGrind = 0

	-- Variables to save per attempt/game
	-- self.lavenderTownState = 0
	self.lastArea = -1
	self.visitedAreas = {}
	self.hasMadeDecisionPerEncounterArea = {}
	self.mustPivot = false
	self.allowedToLeaveArea = true
	self.hasUsedTM = {}
	self.hasHMSlave = false -- Could/should be made into a function
	-- self.caughtPokemonCount = 0

	-- Other "Variables"
	self.isAllowedToHoldItem = {
		function(itemID)
			return CONSTANT.BANNED_ITEMS[CONSTANT.VERSION.STANDARD][itemID] ~= true
		end,
		function(itemID)
			return CONSTANT.BANNED_ITEMS[CONSTANT.VERSION.STANDARD][itemID] ~= true
				and CONSTANT.BANNED_ITEMS[CONSTANT.VERSION.ULTIMATE][itemID] ~= true
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
				return self.isAllowedToHoldItem[CONSTANT.VERSION.KAIZO](itemID)
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

		self.replaceShops()

		-- Ultimate and onwards
		if self.mode < CONSTANT.VERSION.ULTIMATE then
			return
		end

		self.replaceHMMovePP()

		-- Kaizo and onwards
		if self.mode < CONSTANT.VERSION.KAIZO then
			return
		end

		self.replaceHealingItemsFieldUse()
	end

	-- Executed only once: When the extension is disabled by the user, necessary to undo any customizations, if able
	function self.unload()
		Options["Show on new game screen"] = self.oldShowOnNewGameScreen
		Options["Show random ball picker"] = self.oldShowRandomBallPicker

		self.restoreShops()

		if self.mode >= CONSTANT.VERSION.KAIZO then
			self.restoreHealingItemsFieldUse()
		end
	end

	function self.replaceHealingItemsFieldUse()
		for itemID, data in pairs(MiscData.HealingItems) do
			memory.write_u16_le(
				CONSTANT.gItems + CONSTANT.ITEMSTRUCT_SIZE * itemID + CONSTANT.ITEMSTRUCT_FIELD_USE_FUNCTION_OFFSET,
				CONSTANT.FieldUseFunc_OakStopsYou
			)
		end
	end

	function self.restoreHealingItemsFieldUse()
		for itemID, data in pairs(MiscData.HealingItems) do
			memory.write_u16_le(
				CONSTANT.gItems + CONSTANT.ITEMSTRUCT_SIZE * itemID + CONSTANT.ITEMSTRUCT_FIELD_USE_FUNCTION_OFFSET,
				CONSTANT.FieldUseFunc_Medicine
			)
		end
	end

	function self.replaceHMMovePP()
		for _, moveID in pairs(CONSTANT.HM_MOVES) do
			local address = CONSTANT.gBattleMoves + CONSTANT.MOVESTRUCT_SIZE * moveID + CONSTANT.MOVE_PP_OFFSET
			Memory.writebyte(address, 0)
		end
	end

	function self.replaceShop(address)
		-- Check if shop is already backedup/modified so we don't lose the original (just to be nice)
		if memory.read_u32_le(address + 0x00E00000) ~= 0xFFFFFFFF then
			return
		end

		local offset = 0
		local items = {
			allowed = {},
			banned = {},
		}

		while true do
			local itemID = Memory.readword(address + offset)
			if itemID == 0 then
				break
			end

			if CONSTANT.ALLOWED_BUY[itemID] then
				items.allowed[#items.allowed + 1] = itemID
			else
				items.banned[#items.banned + 1] = itemID
			end

			offset = offset + 2
		end

		-- Make a backup for if something bad would happen
		local backup = memory.read_bytes_as_array(address, offset)
		memory.write_bytes_as_array(address + 0x00E00000, backup)

		offset = 0
		for _, itemID in pairs(items.allowed) do
			Memory.writeword(address + offset, itemID)
			memory.write_u16_le(address + offset, itemID)
			offset = offset + 2
		end

		Memory.writeword(address + offset, 0) -- Trick the game into thinking shop ends here
		memory.write_u16_le(address + offset, 0)
		offset = offset + 2

		for _, itemID in pairs(items.banned) do
			Memory.writeword(address + offset, itemID)
			memory.write_u16_le(address + offset, itemID)
			offset = offset + 2
		end
	end

	function self.restoreShop(address)
		local backup = memory.read_bytes_as_array(address + 0x00E00000, CONSTANT.SHOP_ADDRESSES[address] * 2)
		memory.write_bytes_as_array(address, backup)

		for i = 1, #backup, 2 do
			local itemID = Utils.bit_lshift(backup[i + 1], 8) + backup[i]
			Memory.writeword(address + i - 1, itemID)
			memory.write_u16_le(address + i - 1 + 0x00E00000, 0xFFFF)
		end

		Memory.writeword(address + #backup, 0)
		memory.write_u16_le(address + #backup, 0)
	end

	function self.replaceShops()
		for address, _ in pairs(CONSTANT.SHOP_ADDRESSES) do
			self.replaceShop(address)
		end
	end

	function self.restoreShops()
		for address, _ in pairs(CONSTANT.SHOP_ADDRESSES) do
			self.restoreShop(address)
		end
	end

	function self.getAreaId()
    local mapId = Program.GameData.mapId
    mapId = CONSTANT.SAME_AREA[mapId] or mapId
		return Battle.CurrentRoute.encounterArea .. "-" .. mapId
	end

	function self.isGym()
		return Memory.readword(GameSettings.gMapHeader + 0x1B) == 1 -- 0x1B: battleType
	end

	-- Executed once every 30 frames, after any battle related data from game memory is read in
	function self.afterBattleDataUpdate()
		if not self.allowXP then
			-- Sets sent in to none, tricks the game into thinking no pokémon are available for XP
			Memory.writebyte(0x02023F4E, 0x00)
		end

		-- TODO: Check if has died
		-- Maybe not needed
	end

	function self.afterRedraw()
		if Program.currentScreen == TrackerScreen and not Battle.isViewingOwn then
			if not self.allowXP then
				-- Drawing.drawButton(CustomDisplay.Buttons.UncatchableIcon, shadowcolor)
				Drawing.drawImage(
					customCodeFolder .. "NoXP.png",
					Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1,
					6,
					30,
					12
				)
			end

			if not self.allowCatch then
				-- Drawing.drawButton(CustomDisplay.Buttons.NoXPIcon, shadowcolor)
				Drawing.drawImage(
					customCodeFolder .. "NoCatch.png",
					Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 1,
					18,
					30,
					12
				)
			end
		end
	end

	function self.isPokemonIDLegal(pokemonID)
		-- No legendaries
		if CONSTANT.LEGENDARY_POKEMON[pokemonID] then
			return false
		end

		-- Kaizo only after this
		if self.mode ~= CONSTANT.VERSION.KAIZO then
			return true
		end

		local basePokemon = PokemonData.Pokemon[pokemonID]

		-- No 600+ BST Pokemon
		if basePokemon.bstCalculated >= 600 then
			return false
		end

		return true
	end

	function self.isPokemonLegal(pokemon)
		if self.mode < CONSTANT.VERSION.KAIZO then
			return true
		end

		-- Banned abilities (Huge Power/Pure Power)
		local basePokemon = PokemonData.Pokemon[pokemon.pokemonID]
		if basePokemon.bstCalculated >= 400 then
			local ability = basePokemon.abilities[pokemon.abilityNum]
			if ability == CONSTANT.ABILITY_HUGE_POWER or ability == CONSTANT.ABILITY_PURE_POWER then
				return false
			end
		end

		return true
	end

	function self.checkCatchability()
		-- Must be able to catch when needing to pivot
		if self.mustPivot then
			return
		end

		-- Allows 1 Catch OR Kill
		local area = self.getAreaId()
		if self.hasMadeDecisionPerEncounterArea[area] then
			self.allowCatch = false
			return
		end

		-- Check legality
		local wildPokemon = Tracker.getPokemon(1, false)
		if not self.isPokemonIDLegal(wildPokemon.pokemonID) then
			self.allowCatch = false
			return
		end

		-- Allows for catching current level +4 (Kaizo only)
		if self.mode == CONSTANT.VERSION.KAIZO then
			local mainPokemon = Tracker.getPokemon(1, true)

			if wildPokemon.level > mainPokemon.level + 4 then
				self.allowCatch = false
				return
			end
		end

		-- Only allow cathing 5 Pokémon for a total of 6 (Ultimate & Kaizo only)
		-- Still allow cathing if you only have 1 pokemon left as safeguard for HM Friends
		if self.mode >= CONSTANT.VERSION.ULTIMATE then
			local partySize = 0
			for i = 1, 6 do
				local pokemon = Tracker.getPokemon(i, true, false) or {}
				if PokemonData.isValid(pokemon.pokemonID) or pokemon.isEgg == 1 then
					partySize = partySize + 1
				end
			end

			-- if self.caughtPokemonCount > 5 and partySize == 1 then
			-- 	self.allowCatch = false
			-- 	return
			-- end

			if Utils.getGameStat(Constants.GAME_STATS.POKEMON_CAPTURES) > 5 and partySize == 1 then
				self.mustBeSlave = true
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
		if self.mode == CONSTANT.VERSION.KAIZO then
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
		if self.isAllowedToHoldItem[self.mode](mainPokemon.heldItem) then
			return
		end

		-- Remove the item from the Pokémon
		utils.addItemToBag(mainPokemon.heldItem, 1)
		utils.setPokemonItem(1, 0)
	end

	function self.moveContraband()
		-- local bannedItems = {}
		for i = 1, self.mode do
			for itemID, _ in pairs(CONSTANT.BANNED_ITEMS[i]) do
				-- bannedItems[#bannedItems + 1] = itemID
				-- local amount = self.getBagItemCount(itemID)
				local amount = utils.getBagItemCount(itemID)
				if amount > 0 then
					utils.moveItem(itemID) -- Moves to PC
				end
			end
		end

		-- for i = 1, #bannedItems do
		-- 	local itemID = bannedItems[i]
		-- 	local amount = self.getBagItemCount(itemID)
		-- 	if amount > 0 then
		-- 		self.moveItem(itemID) -- Moves to PC
		-- 	end
		-- end
	end

	-- Executed after a new battle begins (wild or trainer), and only once per battle
	function self.afterBattleBegins()
		local tutorial_flag = Utils.getbits(Memory.readdword(GameSettings.gBattleTypeFlags), 9, 1) == 1
		if tutorial_flag then
			return
		end

		-- Only 1 Main (Kaizo only)
		-- Better way to do this
		-- if self.mode == CONSTANT.VERSION.KAIZO then
		-- 	for i = 2, 6 do
		-- 		utils.killPokemon(i)
		-- 	end
		-- end

		self.checkHeldItems()

		if not Battle.isWildEncounter then
			return
		end

		self.checkCatchability()
		self.checkXPAbility()

		self.startedWithoutItem = {}
		for i = 1, 6 do
			local pokemon = Tracker.getPokemon(i, true)
			if pokemon ~= nil then
				self.startedWithoutItem[i] = pokemon.heldItem == 0
			end
		end

		if not self.allowCatch then
			Memory.writedword(0x08250902, 0x00000000) -- Set ball multipliers as 0 (Still allows masterball, no fix for that yet)
		end

		if self.mustBeSlave then
			utils.setPokemonTag(1, CONSTANT.TAGS.SLAVE)
		elseif self.mustPivot then
			utils.setPokemonTag(1, CONSTANT.TAGS.MUST_BE_NEW_MAIN)
		end
	end

	function self.handleNonTagCatch(caughtIndex)
		if self.mode >= CONSTANT.VERSION.KAIZO then
			-- Ask if new main or slave
			-- Would be better with emu.yield, but currently broken
			client.pause()

			-- This is nice and all, but as emu.yield is broken, should probably just use a form
			local chosenOption = nil
			SelectionScreen.Question = "Is this your new Main?"
			SelectionScreen.Callback = function(option)
				chosenOption = option
				client.unpause()
			end

			local x, y, w, h, lineHeight = 20, 15, 300, 150, 20
			local form = Utils.createBizhawkForm("Please select an option", w, h, 80, 20)

			forms.label(form, "Will this be your new main?", x, y, w - 40, lineHeight)
			y = y + 20

			forms.button(form, "Yes", function()
				-- chosenOption = true
				self.replaceMain(caughtIndex)
				Utils.closeBizhawkForm(form)
				client.unpause()
			end, x + 70, y)

			forms.button(form, "No", function()
				-- chosenOption = false
				utils.killPokemon(caughtIndex)
				Utils.closeBizhawkForm(form)
				client.unpause()
			end, x + 170, y)

			-- Program.changeScreenView(SelectionScreen)

			-- while chosenOption == nil do
			-- local input = joypad.get()

			-- joypad.set{A=false, B=false, Down=false, L=false, Left=false, R=false, Right=false, Select=false, Start=false, Up=false}
			-- emu.frameadvance()
			-- emu.yield()
			-- Program.currentScreen.drawScreen()
			-- end

			-- print("Chosen option", chosenOption)
			--
			-- Program.changeScreenView(previousScreen or SingleExtensionScreen)
			-- previousScreen = nil

			-- Should be in a loop
			-- Program.currentScreen.drawScreen()
		end
	end

	function self.replaceMain(newMain)
		utils.swapPokemon(1, newMain)
		utils.killPokemon(newMain)

		utils.setPokemonTag(1, CONSTANT.TAGS.NO_TAG)
	end

	self.handlePokemonTagFunctions = {
		[CONSTANT.TAGS.NO_TAG] = self.handleNonTagCatch,
		[CONSTANT.TAGS.SLAVE] = utils.killPokemon,
		[CONSTANT.TAGS.MUST_BE_NEW_MAIN] = self.replaceMain,
	}

	function self.handlePokemonTag(pokemon)
		local tag = utils.getPokemonTag(pokemon)
		local func = self.handlePokemonTagFunctions[tag]
		if func == nil then
			return
		end

		func(pokemon)
	end

	function self.isWarpDisabled(id)
		local eventsPointer = Memory.readdword(Constants.gMapHeader + 0x04)
		local warpCount = Memory.readbyte(eventsPointer + 0x01)

		if id > warpCount then
			return true -- Does not exist
		end

		local warpEvents = Memory.readdowrd(eventsPointer + 0x08)
		local warp_x = memory.read_s16_le(warpEvents + 0x8 * (id - 1))
		local warp_y = memory.read_s16_le(warpEvents + 0x8 * (id - 1))

		return warp_x <= -10 and warp_y <= -10
	end

	function self.toggleWarp(id)
		local eventsPointer = Memory.readdword(Constants.gMapHeader + 0x04)
		local warpCount = Memory.readbyte(eventsPointer + 0x01)

		if id > warpCount then
			return true -- Does not exist
		end

		local warpEvents = Memory.readdowrd(eventsPointer + 0x08)
		local warp_x = memory.read_s16_le(warpEvents + CONSTANT.WARP_EVENT_SIZE * (id - 1) + CONSTANT.WARP_X_OFFSET)
			* -10
		local warp_y = memory.read_s16_le(warpEvents + CONSTANT.WARP_EVENT_SIZE * (id - 1) + CONSTANT.WARP_Y_OFFSET)
			* -10

		memory.write_s16_le(warpEvents + CONSTANT.WARP_EVENT_SIZE * (id - 1) + CONSTANT.WARP_X_OFFSET, warp_x)
		memory.write_s16_le(warpEvents + CONSTANT.WARP_EVENT_SIZE * (id - 1) + CONSTANT.WARP_Y_OFFSET, warp_y)
	end

	function self.disableDungeonWarps(dungeon)
		for warp, map in dungeon do
			if self.visitedAreas[map] and not self.isWarpDisabled(warp) then
				self.toggleWarp(warp)
			end
		end
	end

	function self.reEnableAllWarps()
		local eventsPointer = Memory.readdword(Constants.gMapHeader + 0x04)
		local warpCount = Memory.readbyte(eventsPointer + 0x01)

		for id = 1, warpCount do
			local warpEvents = Memory.readdowrd(eventsPointer + 0x08)
			local warp_x = memory.read_s16_le(warpEvents + CONSTANT.WARP_EVENT_SIZE * (id - 1) + CONSTANT.WARP_X_OFFSET)
				* -10
			local warp_y = memory.read_s16_le(warpEvents + CONSTANT.WARP_EVENT_SIZE * (id - 1) + CONSTANT.WARP_Y_OFFSET)
				* -10

			if not (warp_x <= -10 and warp_y <= -10) then
				memory.write_s16_le(warpEvents + CONSTANT.WARP_EVENT_SIZE * (id - 1) + CONSTANT.WARP_X_OFFSET, warp_x)
				memory.write_s16_le(warpEvents + CONSTANT.WARP_EVENT_SIZE * (id - 1) + CONSTANT.WARP_Y_OFFSET, warp_y)
			end
		end
	end

	function self.fixWarps()
		local mapId = Program.GameData.mapId

		local dungeon = CONSTANT.DISABLE_DUNGEON_WARP[mapId]
		if dungeon ~= nil then
			self.disableDungeonWarps(dungeon)
			return
		end

		local silphCoDungeon = CONSTANT.SILPH_CO[utils.getFlag(CONSTANT.BEAT_SILPH_CO)][mapId]
		if silphCoDungeon ~= nil then
			self.disableDungeonWarps(dungeon)
			return
		end

		local rocketHideoutDungeon = CONSTANT.TEAM_ROCKET_HIDEOUT[utils.getBagItemCount(CONSTANT.SILPH_SCOPE)][mapId]
		if rocketHideoutDungeon ~= nil then
			self.disableDungeonWarps(rocketHideoutDungeon)
			return
		end

		local lavenderTownState = 0
		if utils.getBagItemCount(CONSTANT.SILPH_SCOPE) > 0 then
			lavenderTownState = 2
		elseif utils.getFlag(CONSTANT.LAVENDER_TOWN_RIVAL) then
			lavenderTownState = 1
		end

		local pokemonTower = CONSTANT.POKEMON_TOWER[lavenderTownState][mapId]
		if pokemonTower ~= nil then
			self.disableDungeonWarps(pokemonTower)
			return
		end
	end

	function self.disallowLeavingArea()
		Utils.printDebug("Not allowed to leave area (not implemented)")
		self.allowedToLeaveArea = false
	end

	-- Executed after a battle ends, and only once per battle
	function self.afterBattleEnds()
		local tutorial_flag = Utils.getbits(Memory.readdword(GameSettings.gBattleTypeFlags), 9, 1) == 1
		if tutorial_flag then
			return
		end

		self.allowXP = true
		self.allowCatch = true
		Memory.writedword(0x08250902, 0x0F0A0F14) -- Set ball multipliers back to normal

		-- local mainPokemon = Tracker.getPokemon(1, true)
		-- if self.highestLevel < mainPokemon.level then
		-- 	self.highestLevel = mainPokemon.level
		-- end

		-- Check if any pokémon has died
		-- Probably unnecesary here

		local battleFlags = Memory.readdword(GameSettings.gBattleTypeFlags)
		local isWildEncounter = Utils.getbits(battleFlags, 3, 1) == 0

		if not isWildEncounter then
			return
		end

		-- Decision has been made
		local area = self.getAreaId()
		self.hasMadeDecisionPerEncounterArea[area] = true

		-- BattleStatus [0 = In battle, 1 = Won the match, 2 = Lost the match, 4 = Fled, 7 = Caught]
		local battleOutcome = Memory.readbyte(GameSettings.gBattleOutcome) -- For current or the last battle (gBattleOutcome isn't cleared when a battle ends)
		if battleOutcome == 2 then
			-- Player lost, loser
			return
		end

		-- Pokémon was caught
		if battleOutcome == 7 then
			-- 	self.caughtPokemonCount = self.caughtPokemonCount + 1
			local caughtPokemon = Tracker.getPokemon(1, false)
			local caughtAsParty = utils.findPartyPokemon(caughtPokemon)
			if caughtAsParty == nil then
				Utils.printDebug("Unable to find caught pokemon in party")
				return
			end

			utils.setPokemonTag(
				caughtAsParty,
				(self.mustPivot == true and CONSTANT.TAGS.MUST_BE_NEW_MAIN)
					or (self.mustBeSlave and CONSTANT.TAGS.SLAVE)
					or CONSTANT.TAGS.NO_TAG
			)

			self.handlePokemonTag(caughtAsParty)

			self.mustPivot = false
			self.mustBeSlave = false
			-- print(caughtPokemon)
			return
		end

		-- We did not catch that wild
		-- Has any party pokemon gained an item?
		for index, startedWithout in pairs(self.startedWithoutItem) do
			local pokemon = Tracker.getPokemon(index, true)
			local hasItem = pokemon.heldItem ~= 0
			if hasItem and startedWithout then
				-- Got item from stealing
				-- Remove it as we did not catch it
				utils.setPokemonItem(index, 0)
			end
		end

		-- Player fled, only killing from here on out
		if battleOutcome == 4 then
			return
		end

		if self.mode >= CONSTANT.VERSION.KAIZO then
			-- Killed wild pokémon when not allowed
			self.mustPivot = true
			self.disallowLeavingArea()
		end
	end

	function self.enforceOptions()
		local saveBlock2 = Memory.readdword(GameSettings.gSaveBlock2ptr)

		Memory.writebyte(saveBlock2 + 0x13, 1)

		local options = Memory.readword(saveBlock2 + 0x14)

		local textSpeed = Utils.getbits(options, 0, 2)
		local frameType = Utils.getbits(options, 3, 5)
		local sound = Utils.getbits(options, 8, 1)
		local battleStyle = Utils.getbits(options, 9, 1)
		local battleSceneOff = Utils.getbits(options, 10, 1)
		local mapZoom = Utils.getbits(options, 11, 1)

		-- Battle style forced to "SET"
		if self.mode >= CONSTANT.VERSION.ULTIMATE then
			battleStyle = 1
		end

		textSpeed = 2
		-- battleSceneOff = 1

		options = 0
		options = Utils.bit_or(options, textSpeed)
		options = Utils.bit_or(options, Utils.bit_lshift(frameType, 3))
		options = Utils.bit_or(options, Utils.bit_lshift(sound, 8))
		options = Utils.bit_or(options, Utils.bit_lshift(battleStyle, 9))
		options = Utils.bit_or(options, Utils.bit_lshift(battleSceneOff, 10))
		options = Utils.bit_or(options, Utils.bit_lshift(mapZoom, 11))

		Memory.writeword(saveBlock2 + 0x14, options)
	end

	function self.rekillPokemon()
		for i = 1, 6 do
			local tag = utils.getPokemonTag(i)
			local pokemon = Tracker.getPokemon(i, true)
			if pokemon ~= nil and (tag == CONSTANT.TAGS.DEAD or tag == CONSTANT.TAGS.SLAVE or pokemon.curHP == 0) then
				utils.killPokemon(i)
			end
		end
	end

	function self.resetVsSeeker()
		local saveBlock1Addr = Utils.getSaveBlock1Addr()

		Memory.writeword(saveBlock1Addr + 0x638, 0)
	end

	-- Need to test so that it doesn't completely disable them
	function self.resetRenewableHiddenItemsCounter()
		local saveBlock1Addr = Utils.getSaveBlock1Addr()

		Memory.writebyte(saveBlock1Addr + GameSettings.gameVarsOffset + 0x23, 0)
	end

	function self.isTMAllowed(tmID)
		local flag = CONSTANT.TM_FLAGS[tmID]
		local quantity = utils.getBagItemCount(tmID + CONSTANT.TM_START)

		if flag == nil then
			return quantity == 0
		end

		if self.hasUsedTM[tmID] then
			return false
		end

		if quantity == 0 then
			if utils.getFlag(flag) then
				self.hasUsedTM[tmID] = true
				return false
			end

			return true
		end

		return utils.getFlag(flag)
	end

	function self.checkTMs()
		-- Currently just deletes all TMs that aren't allowed
		for tmID = 1, CONSTANT.TM_COUNT do
			if not self.isTMAllowed(tmID) then
				utils.setBagItemCount(tmID + CONSTANT.TM_START, 0)
			end
		end
	end

	function self.onMapUpdate(oldId, newId)
		self.visitedAreas[newId] = true
		-- self.restoreWarps()
		self.fixWarps()
	end

	function self.updateMap()
		local currentMap = Program.GameData.mapId
		if currentMap ~= self.lastArea then
			self.onMapUpdate(self.lastArea, currentMap)
			self.lastArea = currentMap
		end
	end

	-- Executed once every 30 frames, after most data from game memory is read in
	function self.afterProgramDataUpdate()
		self.updateMap()

		self.enforceOptions()
		self.checkHeldItems()

		-- Should we just delete instead of moving to PC?
		self.moveContraband()

		-- ReKill already dead Pokémon
		self.rekillPokemon()

		self.resetVsSeeker()
		self.resetRenewableHiddenItemsCounter()

		-- Check if gained Unallowed TMs
		if self.mode >= CONSTANT.VERSION.ULTIMATE then
			self.checkTMs()
		end
	end

	StreamerScreen.openPokemonPickerWindow = function(iconButton, initPokemonID)
		if iconButton == nil then
			return
		end

		if not PokemonData.isValid(initPokemonID) then
			initPokemonID = Utils.randomPokemonID()
		end

		local form = Utils.createBizhawkForm(Resources.StreamerScreen.PromptChooseFavoriteTitle, 330, 145)

		local allPokemon = PokemonData.namesToList()
		if self.mode == CONSTANT.VERSION.KAIZO then
			for pokemonID, _ in pairs(allPokemon) do
				if pokemonID >= 252 then
					pokemonID = pokemonID + 25
				end

				if
					PokemonData.Pokemon[pokemonID]
					and PokemonData.Pokemon[pokemonID].bst ~= nil
					and PokemonData.Pokemon[pokemonID].bst >= 600
				then
					allPokemon[pokemonID] = nil
				end
			end
		end

		if utils.hasLegendaryFavorite() then
			for pokemonID, _ in pairs(self.legendaries) do
				allPokemon[pokemonID] = nil
			end
		end

		forms.label(form, Resources.StreamerScreen.PromptChooseFavoriteDesc, 24, 10, 300, 20)
		local pokedexDropdown = forms.dropdown(form, { ["Init"] = "Loading Pokedex" }, 50, 30, 145, 30)
		forms.setdropdownitems(pokedexDropdown, allPokemon, true) -- true = alphabetize the list
		forms.setproperty(pokedexDropdown, "AutoCompleteSource", "ListItems")
		forms.setproperty(pokedexDropdown, "AutoCompleteMode", "Append")
		forms.settext(pokedexDropdown, PokemonData.Pokemon[initPokemonID].name)

		forms.button(form, Resources.AllScreens.Save, function()
			local optionSelected = forms.gettext(pokedexDropdown)
			iconButton.pokemonID = PokemonData.getIdFromName(optionSelected) or 0

			StreamerScreen.saveFavorites()
			Program.redraw(true)

			Utils.closeBizhawkForm(form)
		end, 200, 29)

		forms.button(form, Resources.AllScreens.Cancel, function()
			Utils.closeBizhawkForm(form)
		end, 120, 69)
	end

	-- Override random balls (For favorite clause & Legenday clause)
	TrackerScreen.randomlyChooseBall = function()
		local validIndexes = {}
		local validPokemon = {
			Memory.readword(CONSTANT.STARTER_BASE_OFFSET),
			Memory.readword(CONSTANT.STARTER_BASE_OFFSET + CONSTANT.STARTER2_BASE_OFFSET),
			Memory.readword(CONSTANT.STARTER_BASE_OFFSET + CONSTANT.STARTER3_BASE_OFFSET),
		}

		for i = 1, 3 do
			local pokemonID = validPokemon[i]
			if self.isPokemonIDLegal(pokemonID) then
				validIndexes[#validIndexes + 1] = i
			end
		end

		local favorites = {}
		for index, pokemonID in pairs(validPokemon) do
			if
				utils.isFavorite(pokemonID)
				and not (self.mode == CONSTANT.VERSION.KAIZO and PokemonData.Pokemon[pokemonID].bstCalculated >= 600)
			then
				favorites[#favorites + 1] = index
			end
		end

		if #favorites ~= 0 then
			validIndexes = favorites
		end

		local index = math.random(#validIndexes)
		TrackerScreen.PokeBalls.chosenBall = validIndexes[index]

		return TrackerScreen.PokeBalls.chosenBall
	end

	TrackerScreen.PokeBalls.chosenBall = -1
	TrackerScreen.randomlyChooseBall()

	return self
end

return IronmonEnforcer
