local customCodeFolder = FileManager.getCustomFolderPath()
local CONSTANT = dofile(customCodeFolder .. "\\IronmonEnforcer\\Constants.lua")

local function utils()
	local self = {}

	function self.boolToBit(b)
		if b then
			return 1
		end
		return 0
	end

	function self.getFlag(flagID)
		local saveBlock1Addr = Utils.getSaveBlock1Addr()
		local addressOffset = math.floor(flagID) / 8
		local flagBit = flagID % 8
		local address = saveBlock1Addr + GameSettings.gameFlagsOffset + addressOffset
		local result = Memory.readbyte(address)
		return Utils.getbits(result, flagBit, 1) == 1
	end

	function self.setFlag(flagID, bool)
		local saveBlock1Addr = Utils.getSaveBlock1Addr()
		local addressOffset = math.floor(flagID) / 8
		local flagBit = flagID % 8
		local address = saveBlock1Addr + GameSettings.gameFlagsOffset + addressOffset
		local result = Memory.readbyte(address)

		result = Utils.bit_and(result, Utils.bit_xor(0xFF, Utils.bit_lshift(1, flagBit)))
		if bool then
			result = Utils.bit_or(result, Utils.bit_lshift(1, flagBit))
		end

		Memory.writebyte(address, result)
	end

	function self.isFavorite(pokemonID)
		return StreamerScreen.Buttons.PokemonFavorite1.pokemonID == pokemonID
			or StreamerScreen.Buttons.PokemonFavorite2.pokemonID == pokemonID
			or StreamerScreen.Buttons.PokemonFavorite3.pokemonID == pokemonID
	end

	function self.hasLegendaryFavorite()
		return CONSTANT.LEGENDARY_POKEMON[StreamerScreen.Buttons.PokemonFavorite1.pokemonID]
			or CONSTANT.LEGENDARY_POKEMON[StreamerScreen.Buttons.PokemonFavorite2.pokemonID]
			or CONSTANT.LEGENDARY_POKEMON[StreamerScreen.Buttons.PokemonFavorite3.pokemonID]
	end

	function self.setPokemonItem(index, itemID)
		local addressOffset = 100 * (index - 1)

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

		-- growth1 = species | (itemID << 16)
		growth1 = species + Utils.bit_lshift(itemID, 16)

		Memory.writedword(GameSettings.pstats + addressOffset + 0x20 + growthoffset, Utils.bit_xor(growth1, magicword))

		local checksum = Memory.readword(GameSettings.pstats + addressOffset + 0x1C)
		checksum = checksum + itemDifference
		if checksum < 0 then
			checksum = 0xFFFF + checksum
		elseif checksum > 0xFFFF then
			checksum = checksum % 0x10000
		end

		Memory.writeword(GameSettings.pstats + addressOffset + 0x1C, checksum)
	end

	function self.setPokemonTag(index, tag, opponent)
		local pokemonAddress = not opponent and GameSettings.pstats or GameSettings.estats

		local addressOffset = 100 * (index - 1) + 0x1E
		local address = pokemonAddress + addressOffset

		local tagData = Memory.readword(address)

		tagData = tag

		-- local isMain = Utils.getbits(pokemonData, 0, 1)
		-- local isSlave = Utils.getbits(pokemonData, 1, 1)
		-- local isDead = Utils.getbits(pokemonData, 2, 1)

		-- if t.isMain ~= nil then
		-- 	isMain = self.boolToBit(t.isMain)
		-- end
		-- if t.isSlave ~= nil then
		-- 	isSlave = self.boolToBit(t.isSlave)
		-- end
		-- if t.isDead ~= nil then
		-- 	isDead = self.boolToBit(t.isDead)
		-- end

		-- pokemonData = 0
		-- pokemonData = pokemonData | (isMain << 0)
		-- pokemonData = pokemonData | (isSlave << 1)
		-- pokemonData = pokemonData | (isDead << 2)
		-- pokemonData = pokemonData + isMain
		-- pokemonData = pokemonData + isSlave * 0x2
		-- pokemonData = pokemonData + isDead * 0x4

		Memory.writeword(address, tagData)
	end

	function self.findPartyPokemon(pokemonToFind)
		for i = 1, 6 do
			local testPokemon = Tracker.getPokemon(i)
			if testPokemon.personality == pokemonToFind.personality then
				return i
			end
		end

		return nil
	end

	-- Super dirty but gets the job done
	function self.getPokemonTag(index)
		local addressOffset = 100 * (index - 1) + 0x1E
		local tagData = Memory.readword(GameSettings.pstats + addressOffset)

		-- local isMain = Utils.getbits(pokemonData, 0, 1)
		-- local isSlave = Utils.getbits(pokemonData, 1, 1)
		-- local isDead = Utils.getbits(pokemonData, 2, 1)

		-- return { isMain = isMain == 1, isSlave = isSlave == 1, isDead = isDead == 1 }
		return tagData
	end

	function self.killPokemon(i)
		local addressOffset = 100 * (i - 1)
		local personality = Memory.readdword(GameSettings.pstats + addressOffset)
		local trainerID = Memory.readdword(GameSettings.pstats + addressOffset + 4)

		if personality ~= 0 or trainerID ~= 0 then
			local pokemon = Program.readNewPokemon(GameSettings.pstats + addressOffset, personality)
			if Program.validPokemonData(pokemon) and pokemon.curHP > 0 then
				Memory.writebyte(GameSettings.pstats + addressOffset + 0x54, 0x01) -- Level
				Memory.writedword(GameSettings.pstats + addressOffset + 0x56, 0x00000000) -- Max Hp, Current Hp
				Memory.writedword(GameSettings.pstats + addressOffset + 0x5A, 0x00010000) -- Defense, Attack
				Memory.writeword(GameSettings.pstats + addressOffset + 0x5E, 0x0000) -- Speed
				Memory.writedword(GameSettings.pstats + addressOffset + 0x60, 0x00010000) -- Sp. Defense, Sp. Attack
			end

			self.setPokemonTag(i, CONSTANT.TAGS.DEAD)
      self.setPokemonItem(i, 0)
		end
	end

	function self.swapPokemon(old, new)
		-- Utils.printDebug('Swapping %d <--> %d', old, new)
		local addressOffsetOld = 100 * (old - 1)
		local addressOffsetNew = 100 * (new - 1)

		local old_bytes = memory.read_bytes_as_array(GameSettings.pstats + addressOffsetOld, 100)
		local new_bytes = memory.read_bytes_as_array(GameSettings.pstats + addressOffsetNew, 100)

		memory.write_bytes_as_array(GameSettings.pstats + addressOffsetOld, new_bytes)
		memory.write_bytes_as_array(GameSettings.pstats + addressOffsetNew, old_bytes)
	end

	function self.copyPokemon(source, destination)
		local addressOffsetSource = 100 * (source - 1)
		local addressOffsetDestination = 100 * (destination - 1)

		memory.write_bytes_as_array(
			GameSettings.pstats + addressOffsetSource,
			memory.read_bytes_as_array(GameSettings.pstats + addressOffsetDestination, 100)
		)
	end

	function self.getBagItemCount(itemID)
		local key = Utils.getEncryptionKey(2) -- Want a 16-bit key

		local pocket = self.getItemPocket(itemID) - 1
		local address = Memory.readdword(CONSTANT.gBagPockets + 8 * pocket)
		local size = Memory.readbyte(CONSTANT.gBagPockets + 8 * pocket + 4)

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

	function self.getItemPocket(itemID)
		return Memory.readbyte(CONSTANT.gItems + CONSTANT.ITEMSTRUCT_SIZE * itemID + CONSTANT.ITEMSTRUCT_POCKET_OFFSET)
	end

	function self.setBagItemCount(itemID, amount)
		local key = Utils.getEncryptionKey(2) -- Want a 16-bit key

		local pocket = self.getItemPocket(itemID) - 1
		local address = Memory.readdword(CONSTANT.gBagPockets + 8 * pocket)
		local size = Memory.readbyte(CONSTANT.gBagPockets + 8 * pocket + 4)

		if pocket == CONSTANT.POCKET_TM_CASE then
			self.setBagItemCount(CONSTANT.ITEM_TM_CASE, 1)
		elseif pocket == CONSTANT.POCKET_BETTY_POUCH then
			self.setBagItemCount(CONSTANT.ITEM_BERRY_POUCH, 1)
		end

		local clear = amount == 0

		if key ~= nil then
			amount = Utils.bit_xor(ammount, key)
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

				-- itemid_and_quantity = itemID + (amount << 16)
				itemid_and_quantity = itemID + Utils.bit_lshift(amount, 16)
				Memory.writedword(address + i * 0x4, itemid_and_quantity)
				break
			end
		end
	end

	function self.setPCItemCount(itemID, amount)
		local saveBlock1Addr = Utils.getSaveBlock1Addr()
		local address = saveBlock1Addr + 0x298
		local size = 30
		local clear = amount == 0

		for i = 0, (size - 1) do
			local itemid_and_quantity = Memory.readdword(address + i * 0x4)
			local itemid = Utils.getbits(itemid_and_quantity, 0, 16)
			local quantity = Utils.getbits(itemid_and_quantity, 16, 16)

			if itemid == 0 or quantity == 0 or itemid == itemID then
				if clear then
					itemID = 0
				end

				-- itemid_and_quantity = itemID + (amount << 16)
				itemid_and_quantity = itemID + Utils.bit_lshift(amount, 16)
				Memory.writedword(address + i * 0x4, itemid_and_quantity)
				break
			end
		end
	end

	function self.addItemToBag(itemID, amount)
		local total = self.getBagItemCount(itemID) + amount
		if total < 0 then
			total = 0
		end

		self.setBagItemCount(itemID, total)
	end

	function self.addItemToPC(itemID, amount)
		local total = self.getPCItemCount(itemID) + amount
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

	return self
end

return utils()
