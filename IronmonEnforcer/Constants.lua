local function getHMs()
	local moves = {}
	local address = 0x0825E084
	while true do
		local moveID = Memory.readword(address)
		if moveID == 0xFFFF then
			break
		end

		moves[#moves + 1] = moveID
		address = address + 2
	end

	return moves
end

local function getIsHM()
	local moves = {}
	local address = 0x0825E084
	while true do
		local moveID = Memory.readword(address)
		if moveID == 0xFFFF then
			break
		end

		moves[moveID] = true
		address = address + 2
	end

	return moves
end

local CONSTANT = {
	VERSION = {
		STANDARD = 1,
		ULTIMATE = 2,
		KAIZO = 3,
		SURVIVAL = 4,
	},

	STARTER_BASE_OFFSET = 0x08169C2D,
	STARTER2_BASE_OFFSET = 0x1CD,
	STARTER3_BASE_OFFSET = 0x203,

	ABILITY_HUGE_POWER = 37,
	ABILITY_PURE_POWER = 74,

	TAGS = {
		NO_TAG = 0,
		DEAD = 1,
		SLAVE = 2,
		MUST_BE_NEW_MAIN = 3,
	},

	gBattleMoves = 0x08250C74,
	sHMMoves = 0x0825E084,

	HM_MOVES = getHMs(),
	IS_HM_MOVE = getIsHM(),

	MOVESTRUCT_SIZE = 9,
	MOVE_PP_OFFSET = 5,

	TM_START = 0x120,
	TM_COUNT = 50,
	TM_FLAGS = {
		[34] = 0x231,
		[42] = 0x236,
		[28] = 0x23F,
		[29] = 0x245,
		[38] = 0x24E,
		[39] = 0x254,
		[06] = 0x259,
		[19] = 0x293,
		[33] = 0x294,
		[20] = 0x295,
		[16] = 0x296,
		[03] = 0x297,
		[26] = 0x298,
		[04] = 0x29A,
	},

	LEGENDARY_POKEMON = {
		[144] = true, -- Articuno
		[145] = true, -- Zapdos
		[146] = true, -- Moltres
		[150] = true, -- Mewto
		[151] = true, -- Mew
		[243] = true, -- Raikou
		[244] = true, -- Entei
		[245] = true, -- Suicune
		[249] = true, -- Lugia
		[250] = true, -- Ho-Oh
		[251] = true, -- Celebi
		[377] = true, -- Regirock
		[378] = true, -- Regice
		[379] = true, -- Registeel
		[380] = true, -- Latias
		[381] = true, -- Latios
		[382] = true, -- Kyogre
		[383] = true, -- Groudon
		[384] = true, -- Rayquaza
		[385] = true, -- Jirachi
	},

	gBagPockets = 0x0203988C,
	gItems = 0x083DB098,
	ITEMSTRUCT_SIZE = 0x2C,
	ITEMSTRUCT_POCKET_OFFSET = 0x1A,
	ITEMSTRUCT_FIELD_USE_FUNCTION_OFFSET = 0x1C,
	FieldUseFunc_OakStopsYou = 0x080A224C + 1,
	FieldUseFunc_Medicine = 0x080A16F4 + 1,

	POCKET_TM_CASE = 4,
	POCKET_BETTY_POUCH = 5,
	ITEM_TM_CASE = 364,
	ITEM_BERRY_POUCH = 365,

	BANNED_ITEMS = {
		{ [0xC5] = true, [0x2D] = true }, -- Lucky Egg, Sacred Ash
		{ [0xC8] = true, [0xBF] = true, [0xC3] = true }, -- Leftovers, Soul Dew, Everstone
		{ [0x27] = true, [0x28] = true, [0x29] = true, [0x2A] = true, [0x2B] = true }, -- Flutes
	},

	ALLOWED_BUY = {
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
	},

	SHOP_ADDRESSES = {
		[0x08164A30] = 9, -- TrainerTower Lobby
		[0x0816A310] = 4, -- Viridian City
		[0x0816A780] = 8, -- Pewter City
		[0x0816AD50] = 9, -- Cerulean City
		[0x0816B408] = 9, -- Lavender Town
		[0x0816B704] = 7, -- Vermillion City
		[0x0816D590] = 6, -- Fuchsia City
		[0x0816EAC0] = 7, -- Cinnabar Island
		[0x0816F054] = 6, -- Saffron City
		[0x08170BD0] = 9, -- Seven Island
		[0x0817192C] = 6, -- Three Island
		[0x08171D4C] = 8, -- Four Island
		[0x08171F04] = 8, -- Six Island
	},
}

return CONSTANT
