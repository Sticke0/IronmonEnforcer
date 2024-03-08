local SelectionScreen = {
	Question = "",
	Callback = nil,
}

SelectionScreen.Colors = {
	text = "Default text",
	highlight = "Intermediate text",
	border = "Upper box border",
	fill = "Upper box background",
}

SelectionScreen.Buttons = {
	Question = {
		type = Constants.ButtonTypes.NO_BORDER,
		getText = function(self)
			return self.Question
		end,
		box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2, Constants.SCREEN.MARGIN + 20, 65, 11 },
		isVisible = function(self)
			return true
		end,
		-- onClick = function(self)
		-- 	self.getTextInput(
		-- 		"Please enter player name",
		-- 		"Player name",
		-- 		self.DefaultOptions.player.name,
		-- 		function(input)
		-- 			self.DefaultOptions.player.name = input
		-- 			Program.redraw(true)
		-- 			self.saveOptionsToFile(self.DefaultOptions)
		-- 		end
		-- 	)
		-- end,
	},
	Yes = {
		type = Constants.ButtonTypes.NO_BORDER,
		getText = function(self)
			return "Yes"
		end,
		box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2, Constants.SCREEN.MARGIN + 20, 65, 11 },
		isVisible = function(self)
			return true
		end,
		onClick = function(self)
			if self.Callback ~= nil then
				self.Callback(true)
			end
			-- self.getTextInput(
			-- 	"Please enter player name",
			-- 	"Player name",
			-- 	self.DefaultOptions.player.name,
			-- 	function(input)
			-- 		self.DefaultOptions.player.name = input
			-- 		Program.redraw(true)
			-- 		self.saveOptionsToFile(self.DefaultOptions)
			-- 	end
			-- )
		end,
	},
	No = {
		type = Constants.ButtonTypes.NO_BORDER,
		getText = function(self)
			return "No"
		end,
		box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 2, Constants.SCREEN.MARGIN + 30, 65, 11 },
		isVisible = function(self)
			return true
		end,
		onClick = function(self)
			if self.Callback ~= nil then
				self.Callback(false)
			end
			-- self.getTextInput("Please enter rival name", "Player rival", self.DefaultOptions.rival.name, function(input)
			-- 	self.DefaultOptions.rival.name = input
			-- 	Program.redraw(true)
			-- 	self.saveOptionsToFile(self.DefaultOptions)
			-- end)
		end,
	},

	-- Back = Drawing.createUIElementBackButton(function()
	-- 	Program.changeScreenView(previousScreen or SingleExtensionScreen)
	-- 	previousScreen = nil
	-- end, SelectionScreen.Colors.text),
}

for _, button in pairs(SelectionScreen.Buttons) do
	if button.textColor == nil then
		button.textColor = SelectionScreen.Colors.text
	end
	if button.boxColors == nil then
		button.boxColors = { SelectionScreen.Colors.border, SelectionScreen.Colors.fill }
	end
end

function SelectionScreen.refreshButtons()
	for _, button in pairs(SelectionScreen.Buttons or {}) do
		if type(button.updateSelf) == "function" then
			button:updateSelf()
		end
	end
end

function SelectionScreen.checkInput(xmouse, ymouse)
	Input.checkButtonsClicked(xmouse, ymouse, SelectionScreen.Buttons or {})
end

function SelectionScreen.drawScreen()
	local canvas = {
		x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN,
		y = Constants.SCREEN.MARGIN,
		w = Constants.SCREEN.RIGHT_GAP - (Constants.SCREEN.MARGIN * 2),
		h = Constants.SCREEN.HEIGHT - (Constants.SCREEN.MARGIN * 2),
		text = Theme.COLORS[SelectionScreen.Colors.text],
		border = Theme.COLORS[SelectionScreen.Colors.border],
		fill = Theme.COLORS[SelectionScreen.Colors.fill],
		shadow = Utils.calcShadowColor(Theme.COLORS[SelectionScreen.Colors.fill]),
	}
	Drawing.drawBackgroundAndMargins()
	gui.defaultTextBackground(canvas.fill)

	-- Draw the canvas box
	gui.drawRectangle(canvas.x, canvas.y, canvas.w, canvas.h, canvas.border, canvas.fill)

	-- Draw the pokemon icon first
	-- Drawing.drawButton(SelectionScreen.Buttons.PokemonIcon, canvas.shadow)

	-- Title text
	local topText
	topText = Utils.formatSpecialCharacters("Choose an option" or self.name)

	local centeredX = Utils.getCenteredTextX(topText, canvas.w) - 2
	Drawing.drawTransparentTextbox(canvas.x + centeredX, canvas.y + 2, topText, canvas.text, canvas.fill, canvas.shadow)

	-- Draw all other the buttons
	for _, button in pairs(SelectionScreen.Buttons or {}) do
		-- if button ~= SelectionScreen.Buttons.PokemonIcon then
			Drawing.drawButton(button, canvas.shadow)
		-- end
	end
end

return SelectionScreen
