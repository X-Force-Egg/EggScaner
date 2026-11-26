--[[
    EGG HUNTER HUB - DISEÑO (UI)
    Guarda este archivo en la carpeta workspace de tu ejecutor como: EggHunterHub_UI.lua
    Lo carga EggHunterHub.lua; aquí solo hay interfaz, nada de lógica de huevos.

    Mejoras de rendimiento:
      - Las tarjetas se crean UNA vez y se reutilizan (antes se destruían y recreaban en cada cambio).
      - Cada tarjeta solo se actualiza si sus datos cambiaron.
      - El borde animado usa un bucle con task.wait en vez de Heartbeat por frame.
]]

return function(opts)
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")
	local TweenService = game:GetService("TweenService")
	local LocalPlayer = Players.LocalPlayer

	local WHITE = Color3.new(1, 1, 1)
	local HEADER_H, CARD_H = 58, 96
	local MAX_CARDS = opts.maxCards or 10

	--==================================================
	-- TEMA
	--==================================================
	local THEME = {
		Panel = Color3.fromRGB(20, 24, 40),
		Card = Color3.fromRGB(26, 31, 50),
		Stroke = Color3.fromRGB(52, 60, 88),
		Muted = Color3.fromRGB(140, 152, 182),
		Accent = Color3.fromRGB(110, 120, 255),
		Green = Color3.fromRGB(70, 215, 150),
		Purple = Color3.fromRGB(160, 115, 250),
		Red = Color3.fromRGB(240, 85, 105),
		Pink = Color3.fromRGB(255, 90, 175),
		Cyan = Color3.fromRGB(70, 230, 230),
		Gold = Color3.fromRGB(255, 205, 60),
		Silver = Color3.fromRGB(200, 210, 225),
		Bronze = Color3.fromRGB(215, 135, 85),
		Warn = Color3.fromRGB(255, 196, 90),
		BgTop = Color3.fromRGB(36, 22, 66),
		BgBottom = Color3.fromRGB(9, 11, 22),
	}
	local DISCORD_COLOR = Color3.fromRGB(88, 101, 242)
	local DISCORD_COLOR_DARK = Color3.fromRGB(60, 70, 190)
	local RANK_COLORS = { THEME.Gold, THEME.Silver, THEME.Bronze }
	local MUTATION_COLORS = {
		Golden = THEME.Gold,
		Silver = THEME.Silver,
		Rainbow = Color3.fromRGB(255, 90, 230),
	}
	local RARITIES = {
		Common    = { name = "Common",    color = Color3.fromRGB(200, 200, 200) },
		Uncommon  = { name = "Uncommon",  color = Color3.fromRGB(120, 230, 120) },
		Rare      = { name = "Rare",      color = Color3.fromRGB(90, 170, 255) },
		Epic      = { name = "Epic",      color = Color3.fromRGB(190, 120, 255) },
		Legendary = { name = "Legendary", color = Color3.fromRGB(255, 200, 60) },
		Mythic    = { name = "Mythic",    color = Color3.fromRGB(255, 100, 110) },
		Cosmic    = { name = "Cosmic",    color = Color3.fromRGB(90, 230, 240) },
		Secret    = { name = "Secret",    color = Color3.fromRGB(235, 235, 255) },
		Eternal   = { name = "Eternal",   color = Color3.fromRGB(255, 150, 70) },
		Divine    = { name = "Divine",    color = Color3.fromRGB(255, 120, 200) },
	}
	local UNKNOWN_RARITY = { name = "Desconocida", color = Color3.fromRGB(160, 160, 160) }

	local OFF = ColorSequence.new(THEME.Card, THEME.Panel)

	local UI = {
		THEME = THEME,
		RARITIES = RARITIES,
		UNKNOWN_RARITY = UNKNOWN_RARITY,
		minimized = false,
	}

	--==================================================
	-- HELPERS
	--==================================================
	local function tween(obj, time, props, easing)
		TweenService:Create(obj, TweenInfo.new(time, easing or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
	end

	local function new(class, props, parent)
		local obj = Instance.new(class)
		for k, v in pairs(props) do obj[k] = v end
		obj.Parent = parent
		return obj
	end

	local function style(obj, radius, strokeColor, strokeTransparency)
		new("UICorner", { CornerRadius = UDim.new(0, radius) }, obj)
		if strokeTransparency then
			new("UIStroke", {
				Color = strokeColor,
				Thickness = 1,
				Transparency = strokeTransparency,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, obj)
		end
		return obj
	end

	local function gradient(parent, colorA, colorB, rotation)
		return new("UIGradient", {
			Color = ColorSequence.new(colorA, colorB or colorA),
			Rotation = rotation or 90,
		}, parent)
	end

	local LABEL_DEFAULTS = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	local function label(parent, props)
		local p = table.clone(LABEL_DEFAULTS)
		for k, v in pairs(props) do p[k] = v end
		return new("TextLabel", p, parent)
	end

	-- El UIGradient también tiñe el texto, por eso el fondo va en un Frame aparte.
	local function button(parent, text, colorA, colorB, props)
		local holder = new("Frame", {
			Size = props.Size,
			Position = props.Position,
			BackgroundTransparency = 1,
		}, parent)

		local bg = style(new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, holder), 10, WHITE, 0.8)
		local grad = gradient(bg, colorA, colorB)

		local b = new("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = WHITE,
			Font = Enum.Font.GothamBold,
			TextSize = props.TextSize or 12,
			AutoButtonColor = false,
			ZIndex = 2,
		}, holder)

		local scale = new("UIScale", { Scale = 1 }, holder)
		b.MouseEnter:Connect(function() tween(scale, 0.12, { Scale = 1.05 }) end)
		b.MouseLeave:Connect(function() tween(scale, 0.12, { Scale = 1 }) end)
		b.MouseButton1Down:Connect(function() tween(scale, 0.08, { Scale = 0.95 }) end)
		b.MouseButton1Up:Connect(function() tween(scale, 0.1, { Scale = 1.05 }) end)
		return b, grad
	end

	-- Chip reutilizable: se crea una vez y luego solo se cambia texto/color
	local function makeChip(parent, order)
		local c = style(new("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundColor3 = THEME.Muted,
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			Text = "",
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextColor3 = WHITE,
			LayoutOrder = order,
			Visible = false,
		}, parent), 7, THEME.Muted, 0.6)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, c)
		return { label = c, stroke = c:FindFirstChildOfClass("UIStroke") }
	end

	local function setChip(ch, text, color)
		if not text then
			ch.label.Visible = false
			return
		end
		ch.label.Visible = true
		ch.label.Text = text
		ch.label.BackgroundColor3 = color
		ch.label.TextColor3 = color:Lerp(WHITE, 0.45)
		ch.stroke.Color = color
	end

	local function readableTextColor(bg)
		local luminance = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
		return luminance > 0.65 and Color3.fromRGB(25, 28, 38) or WHITE
	end

	--==================================================
	-- VENTANA
	--==================================================
	if _G.UIDExtractorGui then
		pcall(function() _G.UIDExtractorGui:Destroy() end)
	end

	local guiParent = LocalPlayer:WaitForChild("PlayerGui")
	pcall(function()
		if gethui then guiParent = gethui() end
	end)

	local ScreenGui = new("ScreenGui", {
		Name = "UIDExtractorGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, guiParent)
	_G.UIDExtractorGui = ScreenGui
	UI.Gui = ScreenGui

	local conns = {}

	local Main = style(new("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(390, 520),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Active = true,
		ClipsDescendants = true,
	}, ScreenGui), 18)
	gradient(Main, THEME.BgTop, THEME.BgBottom, 115)

	local MainStroke = new("UIStroke", {
		Thickness = 1.8,
		Color = WHITE,
		Transparency = 0.15,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, Main)
	local StrokeGradient = new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, THEME.Pink),
			ColorSequenceKeypoint.new(0.5, THEME.Accent),
			ColorSequenceKeypoint.new(1, THEME.Cyan),
		}),
	}, MainStroke)

	-- Borde animado: bucle liviano, se pausa si la ventana está minimizada
	if opts.animateBorder then
		task.spawn(function()
			local step = 1 / (opts.borderFps or 15)
			local last = os.clock()
			while ScreenGui.Parent do
				task.wait(step)
				local now = os.clock()
				if not UI.minimized then
					StrokeGradient.Rotation = (StrokeGradient.Rotation + (now - last) * 70) % 360
				end
				last = now
			end
		end)
	end

	local MainScale = new("UIScale", { Scale = 0.85 }, Main)
	tween(MainScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	-- Header
	local Header = new("Frame", {
		Size = UDim2.new(1, 0, 0, HEADER_H),
		BackgroundTransparency = 1,
	}, Main)

	new("Frame", {
		Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.new(0, 12, 1, -1),
		BackgroundColor3 = THEME.Stroke,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	}, Header)

	local Icon = style(new("Frame", {
		Size = UDim2.fromOffset(38, 38),
		Position = UDim2.fromOffset(14, 10),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, Header), 12)
	gradient(Icon, THEME.Pink, THEME.Accent, 45)
	style(new("Frame", {
		Size = UDim2.fromOffset(14, 18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, Icon), 7)

	label(Header, {
		Text = "EGG HUNTER HUB",
		Size = UDim2.new(1, -150, 0, 20),
		Position = UDim2.fromOffset(62, 10),
		Font = Enum.Font.GothamBlack,
		TextSize = 15,
	})

	local StatusDot = style(new("Frame", {
		Size = UDim2.fromOffset(6, 6),
		Position = UDim2.fromOffset(62, 36),
		BackgroundColor3 = THEME.Muted,
		BorderSizePixel = 0,
	}, Header), 3)

	local Subtitle = label(Header, {
		Text = "Preparando...",
		Size = UDim2.new(1, -164, 0, 14),
		Position = UDim2.fromOffset(74, 32),
		TextSize = 10,
		Font = Enum.Font.Gotham,
		TextColor3 = THEME.Cyan,
	})

	local MinimizeBtn = button(Header, "—", THEME.Card, THEME.Panel, {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, -78, 0, 14),
		TextSize = 14,
	})
	local CloseBtn = button(Header, "×", THEME.Red, Color3.fromRGB(190, 40, 60), {
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.new(1, -42, 0, 14),
		TextSize = 18,
	})

	-- Body
	local Body = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, HEADER_H + 12),
		Size = UDim2.new(1, -28, 1, -(HEADER_H + 24)),
	}, Main)

	local StatsRow = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
	}, Body)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
	}, StatsRow)

	local function makeStat(title, initial, color)
		local card = style(new("Frame", {
			Size = UDim2.new(0.5, -4, 1, 0),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, StatsRow), 14, color, 0.7)
		gradient(card, color:Lerp(THEME.Panel, 0.78), THEME.Panel, 60)

		style(new("Frame", {
			Size = UDim2.fromOffset(4, 28),
			Position = UDim2.fromOffset(0, 14),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, card), 2)

		label(card, {
			Text = string.upper(title),
			Size = UDim2.new(1, -24, 0, 14),
			Position = UDim2.fromOffset(16, 9),
			Font = Enum.Font.GothamBold,
			TextSize = 9,
			TextColor3 = THEME.Muted,
		})
		return label(card, {
			Text = initial,
			Size = UDim2.new(1, -24, 0, 24),
			Position = UDim2.fromOffset(16, 25),
			Font = Enum.Font.GothamBlack,
			TextSize = 18,
			TextColor3 = color,
		})
	end

	local EggCountStat = makeStat("Disponibles", "0", THEME.Cyan)
	local BestEggStat = makeStat("Mejor huevo", "—", THEME.Green)

	-- Selector de orden
	local sortTitles = opts.sortTitles
	local SortBar = style(new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 66),
		BackgroundColor3 = THEME.Panel,
		BorderSizePixel = 0,
	}, Body), 12, THEME.Stroke, 0.6)

	local SortInner = new("Frame", {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
	}, SortBar)

	local SortPill = style(new("Frame", {
		Size = UDim2.new(1 / #sortTitles, 0, 1, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, SortInner), 9)
	gradient(SortPill, THEME.Pink, THEME.Accent, 0)

	local SortButtonsRow = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, SortInner)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal }, SortButtonsRow)

	local sortButtons = {}
	for i, title in ipairs(sortTitles) do
		local b = new("TextButton", {
			Size = UDim2.new(1 / #sortTitles, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = title,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextColor3 = THEME.Muted,
			AutoButtonColor = false,
		}, SortButtonsRow)
		b.MouseButton1Click:Connect(function()
			if UI.onSort then UI.onSort(i) end
		end)
		sortButtons[i] = b
	end

	-- Barra de acciones
	local Toolbar = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.fromOffset(0, 108),
	}, Body)

	local CountLabel = label(Toolbar, {
		Size = UDim2.new(1, -170, 1, 0),
		Position = UDim2.fromOffset(2, 0),
		TextSize = 11,
		TextColor3 = THEME.Muted,
	})

	local AutoBtn, AutoGradient = button(Toolbar, "AUTO", THEME.Card, THEME.Panel, {
		Size = UDim2.fromOffset(52, 32),
		Position = UDim2.new(1, -160, 0, 0),
		TextSize = 11,
	})
	local RefreshBtn = button(Toolbar, "ACTUALIZAR", THEME.Pink, THEME.Accent, {
		Size = UDim2.fromOffset(100, 32),
		Position = UDim2.new(1, -100, 0, 0),
		TextSize = 11,
	})

	-- Fila de salto de servidor
	local HopRow = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.fromOffset(0, 146),
	}, Body)

	local HopLabel = label(HopRow, {
		Text = "Salto automático apagado",
		Size = UDim2.new(1, -170, 1, 0),
		Position = UDim2.fromOffset(2, 0),
		TextSize = 11,
		TextColor3 = THEME.Muted,
	})

	local AutoHopBtn, AutoHopGradient = button(HopRow, "AUTO HOP", THEME.Card, THEME.Panel, {
		Size = UDim2.fromOffset(84, 32),
		Position = UDim2.new(1, -164, 0, 0),
		TextSize = 10,
	})
	local HopNowBtn = button(HopRow, "SALTAR", THEME.Pink, THEME.Accent, {
		Size = UDim2.fromOffset(72, 32),
		Position = UDim2.new(1, -72, 0, 0),
		TextSize = 11,
	})

	local Scroll = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -186),
		Position = UDim2.fromOffset(0, 186),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = THEME.Pink,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, Body)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, Scroll)
	new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 4) }, Scroll)

	local EmptyLabel = label(Body, {
		Text = "No se encontraron huevos todavía.",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 230),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = THEME.Muted,
		Visible = false,
	})

	--==================================================
	-- TAMAÑO Y ARRASTRE
	--==================================================
	local camera = workspace.CurrentCamera

	local function applySize()
		local vp = camera and camera.ViewportSize or Vector2.new(800, 600)
		local width = math.clamp(vp.X - 24, 300, 410)
		local height = UI.minimized and HEADER_H or math.clamp(vp.Y - 70, 300, 560)
		tween(Main, 0.2, { Size = UDim2.fromOffset(width, height) }, Enum.EasingStyle.Quint)
	end

	if camera then
		table.insert(conns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(applySize))
	end
	applySize()

	do
		local dragging, dragStart, startPos

		Header.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				dragging, dragStart, startPos = true, input.Position, Main.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)

		table.insert(conns, UserInputService.InputChanged:Connect(function(input)
			local t = input.UserInputType
			if dragging and (t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				Main.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				)
			end
		end))
	end

	--==================================================
	-- TARJETAS REUTILIZABLES
	--==================================================
	local slots = {}

	local function createSlot(i)
		local card = style(new("Frame", {
			Size = UDim2.new(1, 0, 0, CARD_H),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			LayoutOrder = i,
			ClipsDescendants = true,
			Visible = false,
		}, Scroll), 14, THEME.Stroke, 0.6)

		local slot = { card = card, baseStroke = 0.6 }
		slot.stroke = card:FindFirstChildOfClass("UIStroke")
		slot.grad = gradient(card, THEME.Card, THEME.Card, 10)

		slot.bar = style(new("Frame", {
			Size = UDim2.new(0, 4, 1, -20),
			Position = UDim2.fromOffset(0, 10),
			BackgroundColor3 = THEME.Muted,
			BorderSizePixel = 0,
		}, card), 2)

		slot.rank = label(card, {
			Size = UDim2.fromOffset(28, 20),
			Position = UDim2.fromOffset(14, 9),
			Font = Enum.Font.GothamBlack,
			TextSize = 11,
		})

		slot.name = label(card, {
			Size = UDim2.new(1, -170, 0, 20),
			Position = UDim2.fromOffset(40, 9),
			Font = Enum.Font.GothamBold,
			TextSize = 14,
		})

		slot.badge = style(new("Frame", {
			Size = UDim2.fromOffset(92, 22),
			Position = UDim2.new(1, -102, 0, 8),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
		}, card), 8)
		slot.badgeText = label(slot.badge, {
			Size = UDim2.fromScale(1, 1),
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Center,
		})

		local chipsFrame = new("Frame", {
			Size = UDim2.new(1, -28, 0, 20),
			Position = UDim2.fromOffset(16, 36),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, card)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, chipsFrame)
		-- 1 estado, 2 zona, 3 tamaño, 4-6 mutaciones, 7 "+N"
		slot.chips = {}
		for n = 1, 7 do slot.chips[n] = makeChip(chipsFrame, n - 1) end

		slot.value = label(card, {
			Size = UDim2.new(0.6, 0, 0, 26),
			Position = UDim2.fromOffset(16, 57),
			Font = Enum.Font.GothamBlack,
			TextSize = 19,
		})
		gradient(slot.value, THEME.Green, THEME.Cyan, 0)


		slot.warn = label(card, {
			Size = UDim2.new(1, -100, 0, 12),
			Position = UDim2.fromOffset(16, 83),
			TextSize = 9,
			Font = Enum.Font.Gotham,
			TextColor3 = THEME.Warn,
			Visible = false,
		})
		return slot
	end

	local function slotSignature(i, e)
		return string.format("%d|%s|%s|%s|%s|%s|%.0f|%.3f", i, tostring(e.uid), e.name, tostring(e.version),
			e.status, e.age and math.floor(e.age / 10) or "-", e.moneyRaw, e.scale)
	end

	local function updateSlot(slot, i, e)
		local sig = slotSignature(i, e)
		slot.card.Visible = true
		if slot.sig == sig then return end
		slot.sig = sig
		slot.egg = e

		local rc = e.rarity.color
		local un = e.status == "unavailable"
		local transp = un and 0.5 or 0

		slot.baseStroke = un and 0.85 or (i == 1 and 0.25 or 0.6)
		slot.stroke.Color = rc
		slot.stroke.Transparency = slot.baseStroke
		slot.grad.Color = ColorSequence.new(rc:Lerp(THEME.Card, un and 0.95 or 0.82), THEME.Card)
		slot.bar.BackgroundColor3 = un and THEME.Muted or rc

		slot.rank.Text = "#" .. i
		slot.rank.TextColor3 = RANK_COLORS[i] or THEME.Muted
		slot.name.Text = e.name
		slot.name.TextTransparency = transp

		slot.badge.BackgroundColor3 = rc
		slot.badge.BackgroundTransparency = un and 0.6 or 0
		slot.badgeText.Text = string.upper(e.rarity.name)
		slot.badgeText.TextColor3 = readableTextColor(rc)

		-- Estado real (Slot no se muestra: es lo normal)
		if un then
			setChip(slot.chips[1], string.upper(e.reason or "NO DISPONIBLE"), THEME.Red)
		elseif e.state == "Dropped" then
			setChip(slot.chips[1], e.age and string.format("SUELTO %ds", math.floor(e.age)) or "SUELTO", THEME.Warn)
		elseif e.status == "unknown" then
			setChip(slot.chips[1], "ESTADO ?", THEME.Muted)
		else
			setChip(slot.chips[1], nil)
		end
		setChip(slot.chips[2], tostring(e.area), THEME.Cyan)
		setChip(slot.chips[3], string.format("x%.2f", e.scale), THEME.Purple)
		for n = 1, 3 do
			local m = e.mutList[n]
			setChip(slot.chips[3 + n], m, m and (MUTATION_COLORS[m] or THEME.Cyan))
		end
		local extra = #e.mutList - 3
		setChip(slot.chips[7], extra > 0 and ("+" .. extra) or nil, THEME.Muted)

		slot.value.Text = "$" .. e.money .. "/s"
		slot.value.TextTransparency = transp


		local warnings = {}
		if not e.knownPrice then table.insert(warnings, "precio base") end
		if #e.unknownMuts > 0 then table.insert(warnings, "mutación desconocida") end
		if #warnings > 0 then
			slot.warn.Text = "⚠ " .. table.concat(warnings, " • ")
			slot.warn.Visible = true
		else
			slot.warn.Visible = false
		end
	end

	--==================================================
	-- API PÚBLICA
	--==================================================
	function UI.alive() return ScreenGui.Parent ~= nil end
	function UI.setSubtitle(text) Subtitle.Text = text end
	function UI.setHop(text, color)
		HopLabel.Text = text
		HopLabel.TextColor3 = color or THEME.Muted
	end
	function UI.setRefreshing(on) RefreshBtn.Text = on and "CARGANDO..." or "ACTUALIZAR" end

	function UI.setStats(available, best, countText, isEmpty)
		EggCountStat.Text = available
		BestEggStat.Text = best
		CountLabel.Text = countText
		EmptyLabel.Visible = isEmpty
	end

	local lastSort
	function UI.setSort(index)
		if lastSort == index then return end
		lastSort = index
		tween(SortPill, 0.25, { Position = UDim2.new((index - 1) / #sortTitles, 0, 0, 0) }, Enum.EasingStyle.Quint)
		for i, b in ipairs(sortButtons) do
			tween(b, 0.18, { TextColor3 = i == index and WHITE or THEME.Muted })
		end
	end

	function UI.setAuto(on)
		AutoGradient.Color = on and ColorSequence.new(THEME.Green, Color3.fromRGB(40, 150, 105)) or OFF
		tween(StatusDot, 0.2, { BackgroundColor3 = on and THEME.Green or THEME.Muted })
	end
	function UI.setAutoHop(on)
		AutoHopGradient.Color = on and ColorSequence.new(THEME.Purple, Color3.fromRGB(110, 70, 200)) or OFF
	end

	-- `top` ya viene ordenado y recortado a MAX_CARDS
	function UI.renderCards(top)
		for i = 1, MAX_CARDS do
			local e = top[i]
			if e then
				slots[i] = slots[i] or createSlot(i)
				updateSlot(slots[i], i, e)
			elseif slots[i] then
				slots[i].card.Visible = false
				slots[i].sig = nil
				slots[i].egg = nil
			end
		end
	end

	function UI.invalidate()
		for _, s in pairs(slots) do s.sig = nil end
	end

	--==================================================
	-- EVENTOS
	--==================================================
	MinimizeBtn.MouseButton1Click:Connect(function()
		UI.minimized = not UI.minimized
		Body.Visible = not UI.minimized
		MinimizeBtn.Text = UI.minimized and "+" or "—"
		if not UI.minimized then UI.invalidate() end
		applySize()
		if UI.onMinimize then UI.onMinimize(UI.minimized) end
	end)
	CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)
	RefreshBtn.MouseButton1Click:Connect(function() if UI.onRefresh then UI.onRefresh() end end)
	AutoBtn.MouseButton1Click:Connect(function() if UI.onAuto then UI.onAuto() end end)
	AutoHopBtn.MouseButton1Click:Connect(function() if UI.onAutoHop then UI.onAutoHop() end end)
	HopNowBtn.MouseButton1Click:Connect(function() if UI.onHopNow then UI.onHopNow() end end)

	ScreenGui.Destroying:Connect(function()
		for _, c in ipairs(conns) do c:Disconnect() end
	end)

	return UI
end
