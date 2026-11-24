--!strict
-- Taker screen, built entirely in code. Display only: every number shown comes from
-- the server, and the only thing sent back is the player's choice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiText = require(script.Parent:WaitForChild("UiText"))
local LevelConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelConfig"))

type Action = "buy" | "sell" | "skip"

type Visible = {
	roundId: number,
	tier: number,
	seen: { number },
	hiddenCount: number,
	bid: number,
	ask: number,
}

type Settlement = {
	roundId: number,
	trueTotal: number,
	hidden: { number },
	action: Action,
	pnl: number,
	fairValue: number,
	edge: number,
	bestAction: Action,
	goodCall: boolean,
	streak: number,
	streakTarget: number?,
	newTier: number?,
	sessionPnl: number,
}

type SubmitResult = { ok: boolean, reason: string?, result: Settlement? }

local roundStarted = ReplicatedStorage:WaitForChild("RoundStarted") :: RemoteEvent
local roundResult = ReplicatedStorage:WaitForChild("RoundResult") :: RemoteEvent
local submitAction = ReplicatedStorage:WaitForChild("SubmitAction") :: RemoteEvent
local requestRound = ReplicatedStorage:WaitForChild("RequestRound") :: RemoteEvent

local COLORS = {
	backdrop = Color3.fromRGB(16, 18, 24),
	card = Color3.fromRGB(30, 34, 44),
	text = Color3.fromRGB(240, 242, 248),
	muted = Color3.fromRGB(160, 168, 186),
	seenTile = Color3.fromRGB(236, 239, 246),
	seenTileText = Color3.fromRGB(20, 22, 30),
	hiddenTile = Color3.fromRGB(58, 64, 84),
	revealedTile = Color3.fromRGB(255, 200, 90),
	buy = Color3.fromRGB(38, 130, 84),
	sell = Color3.fromRGB(176, 62, 62),
	skip = Color3.fromRGB(72, 78, 96),
	cont = Color3.fromRGB(52, 108, 200),
	good = Color3.fromRGB(110, 214, 146),
	bad = Color3.fromRGB(240, 110, 110),
	promo = Color3.fromRGB(255, 200, 90),
}

local MAX_TILES = 5
local TILE_WIDTH = 0.18 -- of the dice row; five tiles plus gaps fit exactly
local TILE_GAP = 0.02
local PROMO_DELAY = 1.2 -- seconds the player sees their own result before the promotion banner

-- UI building helpers ---------------------------------------------------------

local function addCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = parent
end

local function newFrame(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Position = position
	frame.Size = size
	frame.Parent = parent
	return frame
end

local function newCard(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local card = newFrame(parent, name, position, size)
	card.BackgroundTransparency = 0
	card.BackgroundColor3 = COLORS.card
	addCorner(card, 0.08)
	return card
end

local function newLabel(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	return label
end

local function newButton(parent: Instance, name: string, size: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.BorderSizePixel = 0
	button.Size = size
	button.BackgroundColor3 = color
	button.Font = Enum.Font.GothamBold
	button.TextColor3 = COLORS.text
	button.TextScaled = true
	button.TextWrapped = true
	button.Text = ""
	button.AutoButtonColor = true
	addCorner(button, 0.2)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = button
	button.Parent = parent
	return button
end

local function newList(parent: Instance, direction: Enum.FillDirection, gap: number): UIListLayout
	local list = Instance.new("UIListLayout")
	list.FillDirection = direction
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(gap, 0)
	list.Parent = parent
	return list
end

local function setButtonEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = if enabled then 0 else 0.55
	button.BackgroundTransparency = if enabled then 0 else 0.5
end

-- Screen ------------------------------------------------------------------------

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "TakerUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- children draw above their parent, so the promotion banner sits over its dim layer
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- clear of the top bar, Roblox menus and device cutouts

local backdrop = newFrame(gui, "Backdrop", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
backdrop.BackgroundTransparency = 0
backdrop.BackgroundColor3 = COLORS.backdrop

local content = newFrame(backdrop, "Content", UDim2.fromScale(0.03, 0.03), UDim2.fromScale(0.94, 0.94))

-- Left column: tier, dice, total, quote
local leftCol = newFrame(content, "LeftColumn", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.46))
local tierLabel = newLabel(leftCol, "Tier", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.1), COLORS.muted)
tierLabel.Text = UiText.loading

local diceRow = newFrame(leftCol, "Dice", UDim2.fromScale(0, 0.12), UDim2.fromScale(1, 0.36))
local diceList = newList(diceRow, Enum.FillDirection.Horizontal, TILE_GAP)
diceList.HorizontalAlignment = Enum.HorizontalAlignment.Center
diceList.VerticalAlignment = Enum.VerticalAlignment.Center

local totalLabel = newLabel(leftCol, "Total", UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.12), COLORS.text)

local quoteRow = newFrame(leftCol, "Quote", UDim2.fromScale(0, 0.64), UDim2.fromScale(1, 0.36))
local bidCard = newCard(quoteRow, "Bid", UDim2.fromScale(0, 0), UDim2.fromScale(0.48, 1))
local askCard = newCard(quoteRow, "Ask", UDim2.fromScale(0.52, 0), UDim2.fromScale(0.48, 1))
local bidCaption = newLabel(bidCard, "Caption", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.26), COLORS.muted)
local bidValue = newLabel(bidCard, "Value", UDim2.fromScale(0.05, 0.36), UDim2.fromScale(0.9, 0.56), COLORS.text)
local askCaption = newLabel(askCard, "Caption", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.26), COLORS.muted)
local askValue = newLabel(askCard, "Value", UDim2.fromScale(0.05, 0.36), UDim2.fromScale(0.9, 0.56), COLORS.text)
bidCaption.Text = UiText.bidCaption
askCaption.Text = UiText.askCaption

-- Right column: either the three action buttons or the result
local rightCol = newFrame(content, "RightColumn", UDim2.fromScale(0, 0.48), UDim2.fromScale(1, 0.52))

local decisionFrame = newFrame(rightCol, "Decision", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
newList(decisionFrame, Enum.FillDirection.Vertical, 0.04)
local buyButton = newButton(decisionFrame, "Buy", UDim2.fromScale(1, 0.3), COLORS.buy)
local sellButton = newButton(decisionFrame, "Sell", UDim2.fromScale(1, 0.3), COLORS.sell)
local skipButton = newButton(decisionFrame, "Skip", UDim2.fromScale(1, 0.3), COLORS.skip)
buyButton.LayoutOrder = 1
sellButton.LayoutOrder = 2
skipButton.LayoutOrder = 3
skipButton.Text = UiText.skip

local resultFrame = newFrame(rightCol, "Result", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
local resultList = newFrame(resultFrame, "Lines", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.78))
newList(resultList, Enum.FillDirection.Vertical, 0)
local actionLine = newLabel(resultList, "Action", UDim2.new(), UDim2.fromScale(1, 0.13), COLORS.muted)
local pnlLine = newLabel(resultList, "Pnl", UDim2.new(), UDim2.fromScale(1, 0.2), COLORS.text)
local fairLine = newLabel(resultList, "FairEdge", UDim2.new(), UDim2.fromScale(1, 0.13), COLORS.muted)
local verdictLine = newLabel(resultList, "Verdict", UDim2.new(), UDim2.fromScale(1, 0.2), COLORS.text)
local streakLine = newLabel(resultList, "Streak", UDim2.new(), UDim2.fromScale(1, 0.13), COLORS.text)
local sessionLine = newLabel(resultList, "Session", UDim2.new(), UDim2.fromScale(1, 0.13), COLORS.muted)
actionLine.LayoutOrder = 1
pnlLine.LayoutOrder = 2
fairLine.LayoutOrder = 3
verdictLine.LayoutOrder = 4
streakLine.LayoutOrder = 5
sessionLine.LayoutOrder = 6
local continueButton = newButton(resultFrame, "Continue", UDim2.fromScale(1, 0.18), COLORS.cont)
continueButton.Position = UDim2.fromScale(0, 0.82)
continueButton.Text = UiText.continue

-- Promotion overlay: a full-width banner over a dimmed screen, above everything else.
local promoOverlay = newFrame(gui, "PromotionOverlay", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
promoOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
promoOverlay.BackgroundTransparency = 0.4
promoOverlay.Active = true -- swallow clicks so nothing underneath can be pressed
promoOverlay.ZIndex = 10
promoOverlay.Visible = false
local promoBanner = newCard(promoOverlay, "Banner", UDim2.fromScale(0, 0.28), UDim2.fromScale(1, 0.44))
local promoTitle = newLabel(promoBanner, "Title", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.34), COLORS.promo)
local promoDetail = newLabel(promoBanner, "Detail", UDim2.fromScale(0.05, 0.44), UDim2.fromScale(0.9, 0.2), COLORS.text)
local promoContinue = newButton(promoBanner, "Continue", UDim2.fromScale(0.5, 0.22), COLORS.cont)
promoContinue.Position = UDim2.fromScale(0.25, 0.7)
promoContinue.Text = UiText.continue

decisionFrame.Visible = false
resultFrame.Visible = false
gui.Parent = playerGui

-- Landscape (wide) screens put the two columns side by side; portrait stacks them.
local function applyLayout()
	local size = content.AbsoluteSize
	if size.X > size.Y * 1.2 then
		leftCol.Position = UDim2.fromScale(0, 0)
		leftCol.Size = UDim2.fromScale(0.5, 1)
		rightCol.Position = UDim2.fromScale(0.52, 0)
		rightCol.Size = UDim2.fromScale(0.48, 1)
	else
		leftCol.Position = UDim2.fromScale(0, 0)
		leftCol.Size = UDim2.fromScale(1, 0.46)
		rightCol.Position = UDim2.fromScale(0, 0.48)
		rightCol.Size = UDim2.fromScale(1, 0.52)
	end
end
content:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
applyLayout()

-- Round state -------------------------------------------------------------------

local currentRound: Visible? = nil
local hiddenTiles: { { tile: Frame, label: TextLabel } } = {}
local busy = false -- true from a click until the server answers
local promoToken = 0 -- bumped whenever the screen changes, so a late banner never shows over the wrong round
local promoPending = false -- a promotion banner is waiting or showing; Continue stays locked until it is dismissed
local knownTier: number? = nil -- the tier the client has been told about, for the promotion check

local function showPromotion(tier: number)
	local config = LevelConfig.tiers[tier]
	if not config then
		return
	end
	promoTitle.Text = UiText.promotionTitle(tier)
	promoDetail.Text = UiText.promotionDetail(config.dice, config.hiddenMin, config.hiddenMax)
	promoOverlay.Visible = true
end

local function actionText(action: Action, round: Visible): string
	if action == "buy" then
		return UiText.buy(round.ask)
	elseif action == "sell" then
		return UiText.sell(round.bid)
	end
	return UiText.skipped
end

local function clearDice()
	for _, child in diceRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(hiddenTiles)
end

local function addTile(label: string, tileColor: Color3, textColor: Color3, order: number): (Frame, TextLabel)
	local tile = newCard(diceRow, "Tile" .. order, UDim2.new(), UDim2.fromScale(TILE_WIDTH, 1))
	tile.BackgroundColor3 = tileColor
	tile.LayoutOrder = order
	local ratio = Instance.new("UIAspectRatioConstraint") -- keep tiles square, shrink to fit
	ratio.AspectRatio = 1
	ratio.Parent = tile
	local text = newLabel(tile, "Number", UDim2.fromScale(0.15, 0.15), UDim2.fromScale(0.7, 0.7), textColor)
	text.Text = label
	return tile, text
end

local function showRound(round: Visible)
	-- Check: the tier may only rise through a result that carried newTier. If it rose without one,
	-- the promotion data never reached us, so fail loudly instead of silently skipping the banner.
	if knownTier and round.tier > knownTier then
		task.spawn(error, string.format("Tier rose %d -> %d without a RoundResult newTier", knownTier, round.tier))
	end
	knownTier = round.tier

	promoToken += 1
	promoPending = false
	promoOverlay.Visible = false
	currentRound = round
	busy = false

	tierLabel.Text = UiText.tier(round.tier)
	totalLabel.Text = UiText.totalHidden
	totalLabel.TextColor3 = COLORS.text
	bidValue.Text = UiText.number(round.bid)
	askValue.Text = UiText.number(round.ask)

	clearDice()
	local order = 0
	for _, value in round.seen do
		order += 1
		addTile(tostring(value), COLORS.seenTile, COLORS.seenTileText, order)
	end
	for _ = 1, math.min(round.hiddenCount, MAX_TILES - #round.seen) do
		order += 1
		local tile, text = addTile(UiText.hiddenTile, COLORS.hiddenTile, COLORS.muted, order)
		table.insert(hiddenTiles, { tile = tile, label = text })
	end

	buyButton.Text = UiText.buy(round.ask)
	sellButton.Text = UiText.sell(round.bid)
	setButtonEnabled(buyButton, true)
	setButtonEnabled(sellButton, true)
	setButtonEnabled(skipButton, true)
	resultFrame.Visible = false
	decisionFrame.Visible = true
end

local function showResult(round: Visible, result: Settlement)
	for index, entry in hiddenTiles do
		local value = result.hidden[index]
		if value then
			entry.tile.BackgroundColor3 = COLORS.revealedTile
			entry.label.Text = tostring(value)
			entry.label.TextColor3 = COLORS.seenTileText
		end
	end
	totalLabel.Text = UiText.total(result.trueTotal)

	actionLine.Text = UiText.youChose(actionText(result.action, round))
	pnlLine.Text = UiText.pnl(result.pnl)
	pnlLine.TextColor3 = if result.pnl > 0 then COLORS.good elseif result.pnl < 0 then COLORS.bad else COLORS.text

	fairLine.Text = UiText.fairEdge(result.fairValue, result.edge)

	verdictLine.Text = UiText.verdict(result.goodCall, result.pnl, actionText(result.bestAction, round))
	verdictLine.TextColor3 = if result.goodCall then COLORS.good else COLORS.bad

	-- After a promotion the banner is the news; streak progress for the new tier waits for the next round.
	local target = result.streakTarget
	streakLine.Visible = result.newTier == nil
	if target then
		streakLine.Text = UiText.streak(result.streak, target, round.tier + 1)
	else
		streakLine.Text = UiText.topStreak(result.streak)
	end

	sessionLine.Text = UiText.session(result.sessionPnl)
	sessionLine.TextColor3 = COLORS.muted

	decisionFrame.Visible = false
	resultFrame.Visible = true

	-- The result is on screen first; the promotion banner follows after a short beat.
	promoToken += 1
	local token = promoToken
	local promoted = result.newTier
	promoPending = promoted ~= nil
	setButtonEnabled(continueButton, promoted == nil)
	if promoted then
		knownTier = promoted
		task.delay(PROMO_DELAY, function()
			if promoToken == token then
				showPromotion(promoted)
			end
		end)
	end
end

-- Input and network -------------------------------------------------------------

local function submit(action: Action)
	local round = currentRound
	if busy or not round then
		return
	end
	busy = true
	setButtonEnabled(buyButton, false)
	setButtonEnabled(sellButton, false)
	setButtonEnabled(skipButton, false)
	submitAction:FireServer(round.roundId, action)
end

buyButton.Activated:Connect(function()
	submit("buy")
end)
sellButton.Activated:Connect(function()
	submit("sell")
end)
skipButton.Activated:Connect(function()
	submit("skip")
end)

local function continueToNextRound()
	if busy or promoPending then
		return
	end
	busy = true
	setButtonEnabled(continueButton, false)
	requestRound:FireServer()
end

-- Same action as the result screen's Continue; the result screen is hidden so it is never seen twice.
promoContinue.Activated:Connect(function()
	promoPending = false
	promoOverlay.Visible = false
	resultFrame.Visible = false
	continueToNextRound()
end)

continueButton.Activated:Connect(continueToNextRound)

roundStarted.OnClientEvent:Connect(function(round: Visible)
	showRound(round)
end)

roundResult.OnClientEvent:Connect(function(submitted: SubmitResult)
	local round = currentRound
	local result = submitted.result
	if not round then
		return
	end
	if not submitted.ok or not result then
		-- rejected: ask the server for the real state of the round
		busy = false
		requestRound:FireServer()
		return
	end
	if result.roundId ~= round.roundId then
		return
	end
	busy = false -- Continue sets it again while it waits for the next round
	showResult(round, result)
end)

requestRound:FireServer()
