--[[
    EGG HUNTER HUB - LÓGICA (usa EggHunterHub_UI.lua para el diseño)

    INSTALACIÓN (carpeta workspace de tu ejecutor):
      1) EggHunterHub_UI.lua   -> el diseño
      2) EggHunterHub.lua      -> este archivo (ponlo en autoexec si quieres)

    Valor = PrecioBase * FactorTamaño * MultiplicadorMutaciones
      Tamaño <= 5 -> Tamaño ^ 1.85
      Tamaño >  5 -> (Tamaño / 5) ^ 1.2 * 19.637875755794113

    MODO CACERÍA (corregido 26-Nov-2026):
      - Sin Secret/Eternal/Divine disponible en ESTA sala → NO salta.
      - Solo salta cuando hay un raro CONFIRMADO (2 escaneos seguidos) en la sala actual.
      - Después de la renovación espera a que salgan/llenen los huevos antes de decidir.
      - Termina al pasar SEARCH_WINDOW o tras HUNT_IDLE_SECONDS sin ver raros.

    CAMBIOS:
      - DROP_UNKNOWN_STATE = false: los huevos sin State (eventos admin abuse) ya se muestran y avisan.
      - Salto de servidor: 2-5 jugadores ideal, máximo 7; lista pedida ~1 vez por salto + prefetch.
      - FIX: ya no salta "por gusto" cuando no hay nada bueno.
      - FIX: espera mejor el llenado de huevos después de la renovación.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local canFile = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

--==================================================
-- CONFIG
--==================================================
local C = {}
C.BASE_URL = C.BASE_URL = "https://raw.githubusercontent.com/X-Force-Egg/EggScanner/main/"
C.UI_FILE = "EggHunterHub_UI.lua"
C.AUTO_REFRESH_SECONDS = 4
C.FAST_RETRY_SECONDS = 1.5

-- Rendimiento de UI
C.MAX_CARDS = 10
C.ANIMATE_BORDER = false
C.BORDER_FPS = 12

-- Frescura / disponibilidad
C.AVAILABLE_STATES = { Slot = true, Dropped = true }
C.NOTIFY_UNKNOWN_STATE = true
C.DROP_UNKNOWN_STATE = false
C.STALE_CLEAR_SECONDS = 12
C.REVALIDATE_SETTLE = 1.2
C.REVALIDATE_TIMEOUT = 6
C.NOTIFY_MIN_REMAINING = 25
C.NOTIFY_RENEW_SETTLE = 6
C.DROPPED_PRIORITY_BOOST = 2
C.VALIDATION_DEBUG = false
C.NOTIFY_HOP_GRACE = 10

-- Espera a que el servidor se llene tras una renovación
C.EXPECTED_EGGS = 70
C.FILL_RATIO = 0.85                 -- un poco más estricto
C.FILL_WAIT_MAX = 55                -- espera más después de la renovación
C.FILL_STABLE_SECONDS = 8

-- Salto de servidor
C.SCRIPT_URL = "https://raw.githubusercontent.com/X-Force-Egg/EggScanner/main/EggHunterHub.lua"
C.HOP_DELAY_SECONDS = 6
C.SCAN_TIMEOUT = 25
C.RARE_MIN_VALUE = 0
C.HUNT_IDLE_SECONDS = 300
C.HUNT_MAX_DRY_SERVERS = 8
C.MIN_PLAYERS = 2
C.MAX_PLAYERS_PREF = 5
C.MAX_PLAYERS_HARD = 7
C.HOP_PAGES = 2
C.LIST_MAX_AGE = 25
C.CACHE_SECONDS = 60
C.PICK_FAILS_BEFORE_RANDOM = 5
C.MIN_FREE_SLOTS = 1
C.VISITED_TTL = 1800
C.HOP_RETRY_SECONDS = 6
C.MIN_TELEPORT_GAP = 4
C.TELEPORT_WAIT = 45
C.BAD_SERVER_TTL = 900
C.HOP_MODE = "list"
C.FAILS_BEFORE_RANDOM = 3
C.SAVE_FILE = "EggHunterHub_state.json"

-- Ciclo
C.CYCLE_MODE = "auto"
C.CYCLE_SECONDS = 300
C.CYCLE_OFFSET = 0
C.SEARCH_WINDOW = 180
C.CALIBRATION_TIMEOUT = 1500
C.MIN_NEW_FOR_SAMPLE = 10
C.CYCLE_RESET = false
C.CYCLE_DEBUG = false

-- Discord
C.RELAY_URL = "https://egg-radar.danielgamas83.workers.dev"
C.RELAY_KEY = "Adrian2230@"
C.NOTIFY_RARITIES = { Secret = true, Eternal = true, Divine = true }
C.MIN_NOTIFY_VALUE = 300e6

C.RELAY_KEY_MISSING = C.RELAY_URL ~= "" and C.RELAY_KEY == ""
C.DISCORD_CONFIGURED = C.RELAY_URL ~= "" and not C.RELAY_KEY_MISSING

C.DEFAULT_PRICE = 10
C.SCALE_THRESHOLD = 5
C.SCALE_BIG_CONSTANT = 19.637875755794113
C.SCALE_SMALL_EXPONENT = 1.85
C.SCALE_BIG_EXPONENT = 1.2
C.MUTATION_MULTIPLIERS = { Golden = 2, Silver = 1.5, Rainbow = 3 }

-- Ajustes automáticos para móvil
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
if IS_MOBILE then
	C.AUTO_REFRESH_SECONDS = 5.5
	C.MAX_CARDS = 7
	C.HOP_DELAY_SECONDS = 7
end

--==================================================
-- CARGA DEL DISEÑO
--==================================================
local SORTS = {
	{ title = "Valor", field = "moneyRaw" },
	{ title = "Prioridad", field = "priority" },
	{ title = "Tamaño", field = "scale" },
}

local okUI, buildUI = pcall(function()
	local src
	if canFile and isfile(C.UI_FILE) then
		src = readfile(C.UI_FILE)
	else
		src = game:HttpGet(C.BASE_URL .. C.UI_FILE)
	end
	return loadstring(src)()
end)
if not okUI or type(buildUI) ~= "function" then
	warn("[EggHunter] No se pudo cargar " .. C.UI_FILE .. " (guárdalo en la carpeta workspace):", buildUI)
	return
end

local sortTitles = {}
for i, s in ipairs(SORTS) do sortTitles[i] = s.title end

local UI = buildUI({
	maxCards = C.MAX_CARDS,
	animateBorder = C.ANIMATE_BORDER,
	borderFps = C.BORDER_FPS,
	sortTitles = sortTitles,
})
local THEME, RARITIES, UNKNOWN_RARITY = UI.THEME, UI.RARITIES, UI.UNKNOWN_RARITY

if C.RELAY_KEY_MISSING then
	warn("[EggHunter] Falta RELAY_KEY: los avisos a Discord están desactivados.")
end

--==================================================
-- PRECIOS
--==================================================
local okLoad, PRICE_LIST = pcall(function()
	return loadstring(game:HttpGet(C.BASE_URL .. "precios.lua"))()
end)
if not okLoad or type(PRICE_LIST) ~= "table" then
	warn("No se pudo cargar precios.lua:", PRICE_LIST)
	PRICE_LIST = {}
end

local PRICE_TABLE, RARITY_TABLE = {}, {}
for _, entry in ipairs(PRICE_LIST) do
	PRICE_TABLE[entry[2]] = entry[1]
	RARITY_TABLE[entry[2]] = entry[3]
end

--==================================================
-- LÓGICA DE HUEVOS
--==================================================
local function formatMoney(num)
	if num >= 1e12 then return string.format("%.2fT", num / 1e12) end
	if num >= 1e9 then return string.format("%.2fB", num / 1e9) end
	if num >= 1e6 then return string.format("%.2fM", num / 1e6) end
	if num >= 1e3 then return string.format("%.2fK", num / 1e3) end
	return string.format("%.2f", num)
end

local function serverClock()
	local okT, now = pcall(workspace.GetServerTimeNow, workspace)
	return okT and now or os.time()
end

local function getMutations(egg)
	local muts, seen = {}, {}
	if type(egg.Mutations) == "table" then
		for _, m in ipairs(egg.Mutations) do
			table.insert(muts, tostring(m))
			seen[tostring(m)] = true
		end
	end
	local base = egg.BaseMutation
	if base and base ~= "" and base ~= "None" and not seen[tostring(base)] then
		table.insert(muts, 1, tostring(base))
	end
	return muts
end

local function calculateValue(name, scale, muts)
	local scaleFactor
	if scale > C.SCALE_THRESHOLD then
		scaleFactor = (scale / C.SCALE_THRESHOLD) ^ C.SCALE_BIG_EXPONENT * C.SCALE_BIG_CONSTANT
	else
		scaleFactor = scale ^ C.SCALE_SMALL_EXPONENT
	end

	local mutMult, unknown = 1, {}
	for _, m in ipairs(muts) do
		local mult = C.MUTATION_MULTIPLIERS[m]
		if mult then
			mutMult *= mult
		else
			table.insert(unknown, m)
		end
	end
	return (PRICE_TABLE[name] or C.DEFAULT_PRICE) * scaleFactor * mutMult, unknown
end

local function dropAge(droppedAt, now)
	if type(droppedAt) ~= "number" then return nil end
	local age = now - droppedAt
	if age < -15 or age > 7 * 86400 then return nil end
	return math.max(age, 0)
end

local warnedStates = {}
local function evaluateAvailability(stateName, carrier)
	if carrier ~= nil then return "unavailable", "lo lleva alguien" end
	if stateName == "Carried" then return "unavailable", "cargado" end
	if stateName ~= nil and C.AVAILABLE_STATES[stateName] then return "available", nil end
	if stateName == nil then return "unknown", "sin dato de estado" end
	if not warnedStates[stateName] then
		warnedStates[stateName] = true
		warn("[EggHunter] State desconocido en el snapshot:", stateName)
	end
	return "unknown", "estado desconocido: " .. stateName
end

local function buildEgg(egg, now)
	local muts = getMutations(egg)
	local name = egg.AssetCategory or egg.Name or egg.name or egg.Type or "Desconocido"
	local scale = tonumber(egg.AssetScale or egg.Scale or egg.Size) or 0
	local money, unknownMuts = calculateValue(name, scale, muts)

	local stateName = type(egg.State) == "string" and egg.State or nil
	local dropped = stateName == "Dropped"
	local status, reason = evaluateAvailability(stateName, egg.CarrierUserId)
	local area = egg.AreaId or egg.Area or egg.Zone

	return {
		uid = egg.Uid or egg.UID or egg.uid or egg.Id or egg.id
			or string.format("%s|%.4f|%s|%s", name, scale, tostring(area), table.concat(muts, ",")),
		name = name,
		area = area or "Zona",
		scale = scale,
		mutList = muts,
		unknownMuts = unknownMuts,
		money = formatMoney(money),
		moneyRaw = money,
		priority = money * (dropped and C.DROPPED_PRIORITY_BOOST or 1),
		rarity = RARITIES[RARITY_TABLE[name]] or UNKNOWN_RARITY,
		knownPrice = PRICE_TABLE[name] ~= nil,
		state = stateName,
		version = tonumber(egg.Version) or 0,
		age = dropped and dropAge(egg.DroppedAt, now) or nil,
		status = status,
		reason = reason,
	}
end

local function eggKey(e) return tostring(e.uid) .. "|" .. e.name end
local function notifyKey(e) return game.JobId .. "|" .. eggKey(e) end

local function isNotifiable(e)
	return e.status == "available" or (e.status == "unknown" and C.NOTIFY_UNKNOWN_STATE)
end

local function byField(field)
	return function(a, b)
		local ua, ub = a.status == "unavailable", b.status == "unavailable"
		if ua ~= ub then return not ua end
		if a[field] == b[field] then return tostring(a.uid) < tostring(b.uid) end
		return a[field] > b[field]
	end
end
for _, s in ipairs(SORTS) do s.compare = byField(s.field) end

--==================================================
-- ESTADO
--==================================================
local eggs, sortIndex = {}, 1
local isLoading, autoRefresh = false, true
local discordOn = C.DISCORD_CONFIGURED
_G.EggHunterSent = _G.EggHunterSent or {}
local sentUids, sending = _G.EggHunterSent, false
local INSTANCE_ID = {}
local previousInstance = _G.EggHunterInstance
if type(previousInstance) == "table" and type(previousInstance.stop) == "function" then
	pcall(previousInstance.stop)
end
_G.EggHunterInstance = INSTANCE_ID
INSTANCE_ID.stop = function()
	pcall(function() if UI and UI.Gui then UI.Gui:Destroy() end end)
end
local connections = {}
local scannedOnce = false
local state = { autoHop = false, visited = {}, huntActive = false }
local cycleSamples = {}
local saveState, pullEggs, commitEggs, cyclePhase

local lastScan = { at = 0 }
local lastCount, lastGrowAt = 0, 0
local invoking = false
local scanDelay = C.AUTO_REFRESH_SECONDS
local failStreak = 0

local lastScanMsg = "Preparando..."
local discordStatus, discordStatusUntil = "", 0
local discordBlockedUntil = 0

-- Contador de confirmación de raro
local rareConfirmCount = 0
local confirmedScanRevision = -1
local scanRevision = 0

local function refreshSubtitle()
	if discordStatus ~= "" and os.clock() < discordStatusUntil then
		UI.setSubtitle(discordStatus)
	else
		UI.setSubtitle(lastScanMsg)
	end
end

local function setDiscordStatus(text, seconds)
	discordStatus = text
	discordStatusUntil = os.clock() + seconds
	refreshSubtitle()
end

if C.RELAY_KEY_MISSING then
	setDiscordStatus("Discord apagado: falta RELAY_KEY", 60)
end

local httpRequest = request or http_request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)

--==================================================
-- RENDER
--==================================================
local function render()
	local best, availableCount = nil, 0
	for _, e in ipairs(eggs) do
		if e.status ~= "unavailable" then
			availableCount += 1
			if not best or e.moneyRaw > best.moneyRaw then best = e end
		end
	end

	local total = #eggs
	local blocked = total - availableCount
	local shown = math.min(total, C.MAX_CARDS)
	UI.setStats(
		tostring(availableCount),
		best and ("$" .. formatMoney(best.moneyRaw) .. "/s") or "—",
		string.format("Top %d de %d%s", shown, total, blocked > 0 and (" • " .. blocked .. " no disp.") or ""),
		total == 0
	)
	UI.setSort(sortIndex)

	if UI.minimized then return end

	local sorted = table.clone(eggs)
	table.sort(sorted, SORTS[sortIndex].compare)
	UI.renderCards(table.move(sorted, 1, shown, 1, {}))
end

UI.onSort = function(i)
	sortIndex = i
	render()
end
UI.onMinimize = function(minimized)
	if not minimized then render() end
end

--==================================================
-- DATOS DEL SERVIDOR
--==================================================
local snapshotRemote
local lastFullSearch = 0

local function getSnapshotRemote()
	if snapshotRemote and snapshotRemote.Parent then return snapshotRemote end
	snapshotRemote = nil

	local okP, direct = pcall(function()
		return ReplicatedStorage.Packages.Networking:FindFirstChild("RF/EggWorld/AskFieldEggSnapshot")
	end)
	if okP and direct and direct:IsA("RemoteFunction") then
		snapshotRemote = direct
		return direct
	end

	local target = ReplicatedStorage:FindFirstChild("AskFieldEggSnapshot", true)
	if target and target:IsA("RemoteFunction") then
		snapshotRemote = target
		return target
	end

	if os.clock() - lastFullSearch < 10 then return nil end
	lastFullSearch = os.clock()
	for _, obj in ipairs(game:GetDescendants()) do
		if obj:IsA("RemoteFunction") and string.find(string.lower(obj.Name), "eggsnapshot", 1, true) then
			snapshotRemote = obj
			return obj
		end
	end
end

local function invokeSnapshot(remote, timeout)
	local thread = coroutine.running()
	local finished, timedOut, ok, data = false, false, false, nil

	task.spawn(function()
		local o, d = pcall(function() return remote:InvokeServer() end)
		if timedOut then return end
		finished, ok, data = true, o, d
		task.spawn(thread)
	end)
	task.delay(timeout, function()
		if finished then return end
		timedOut = true
		task.spawn(thread)
	end)

	coroutine.yield()
	return finished, ok, data
end

--==================================================
-- CICLO DE RENOVACIÓN
--==================================================
function cyclePhase()
	local offset
	if C.CYCLE_MODE == "auto" then
		offset = state.cycleOffset
	elseif C.CYCLE_MODE == "reloj" then
		offset = C.CYCLE_OFFSET
	end
	if not offset then return nil end
	return (serverClock() - offset) % C.CYCLE_SECONDS
end

local function cycleBlocksNotify()
	local phase = cyclePhase()
	if not phase then return false end
	local remaining = C.CYCLE_SECONDS - phase
	if remaining < C.NOTIFY_MIN_REMAINING then
		return true, "renovación en " .. math.ceil(remaining) .. "s"
	end
	if phase < C.NOTIFY_RENEW_SETTLE then
		return true, "renovación en curso"
	end
	return false
end

local lastEggKeys
local function trackChanges(list)
	local current, newCount = {}, 0
	for _, e in ipairs(list) do
		local k = eggKey(e)
		current[k] = true
		if lastEggKeys and not lastEggKeys[k] then newCount += 1 end
	end

	if lastEggKeys and newCount > 0 then
		local phase = serverClock() % C.CYCLE_SECONDS

		if C.CYCLE_DEBUG then
			print(string.format("[EggHunter] +%d huevos nuevos | hora UTC %s | seg%%%d = %d",
				newCount, os.date("!%H:%M:%S", math.floor(serverClock())), C.CYCLE_SECONDS, math.floor(phase)))
		end

		if C.CYCLE_MODE == "auto" and state.cycleOffset == nil and newCount >= C.MIN_NEW_FOR_SAMPLE then
			table.insert(cycleSamples, phase)
			if #cycleSamples > 20 then table.remove(cycleSamples, 1) end
			saveState()

			for _, anchor in ipairs(cycleSamples) do
				local n, earliest = 0, anchor
				for _, other in ipairs(cycleSamples) do
					if (other - anchor) % C.CYCLE_SECONDS <= 20 then n += 1 end
					if (anchor - other) % C.CYCLE_SECONDS <= 20 then earliest = other end
				end
				if n >= 3 then
					state.cycleOffset = math.floor((earliest - 5) % C.CYCLE_SECONDS)
					table.clear(cycleSamples)
					saveState()
					print("[EggHunter] Ciclo calibrado: huevos nuevos en el segundo " .. state.cycleOffset .. " de cada " .. C.CYCLE_SECONDS .. "s")
					break
				end
			end
		end
	end
	lastEggKeys = current
end

--==================================================
-- ESCANEO
--==================================================
local function buildList(records)
	local fresh, now = {}, serverClock()
	for _, egg in pairs(records) do
		if type(egg) == "table" then
			if C.VALIDATION_DEBUG and egg.State == nil and not _G.EggDbgDone then
				_G.EggDbgDone = true
				local parts = {}
				for k, v in pairs(egg) do
					parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
				end
				print("[EggHunter] huevo sin State:", table.concat(parts, ", "))
			end

			local okEgg, built = pcall(buildEgg, egg, now)
			if okEgg then
				if built.status == "unknown" and C.DROP_UNKNOWN_STATE then
					if C.VALIDATION_DEBUG then
						print("[EggHunter] ignorado (sin estado válido):", built.name, tostring(built.uid), built.reason)
					end
				else
					fresh[#fresh + 1] = built
				end
			else
				warn("[EggHunter] huevo ignorado:", built)
			end
		end
	end
	return fresh
end

local function pullEggsRaw(timeout)
	local remote = getSnapshotRemote()
	if not remote then return nil, "No se encontró AskFieldEggSnapshot" end

	local done, ok, data = invokeSnapshot(remote, timeout)
	if not done then return nil, "El servidor tardó demasiado" end
	if not ok or type(data) ~= "table" then
		snapshotRemote = nil
		return nil, "Respuesta inválida del servidor"
	end

	if C.VALIDATION_DEBUG and not _G.EggDbgSnap then
		_G.EggDbgSnap = true
		local keys = {}
		for k, v in pairs(data) do
			keys[#keys + 1] = tostring(k) .. "=" .. (type(v) == "table" and "table" or tostring(v))
		end
		print("[EggHunter] snapshot:", table.concat(keys, ", "))
	end

	return buildList(data.Records or data.records or data)
end

function pullEggs(timeout)
	local waited = 0
	while invoking and waited < timeout do
		waited += task.wait(0.05)
	end
	if invoking then return nil, "otro escaneo sigue en curso" end

	invoking = true
	local okRun, list, err = pcall(pullEggsRaw, timeout)
	invoking = false

	if not okRun then
		warn("[EggHunter] error al escanear:", list)
		return nil, "Error al escanear (mira la consola)"
	end
	if not list then return nil, err end

	lastScan.at = os.clock()
	scanRevision += 1
	return list
end

local lastListSig
local function listSignature(list)
	local parts = table.create(#list)
	for i, e in ipairs(list) do
		parts[i] = string.format("%s|%s|%s|%s|%.0f", eggKey(e), tostring(e.version), e.status,
			e.age and math.floor(e.age / 10) or "-", e.moneyRaw)
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

function commitEggs(list)
	pcall(trackChanges, list)
	if lastCount > 0 and #list > lastCount then lastGrowAt = os.clock() end
	lastCount = #list
	eggs = list
	scannedOnce = true

	local sig = listSignature(list)
	if sig ~= lastListSig then
		lastListSig = sig
		render()
	end
end

--==================================================
-- DISCORD
--==================================================
local function post(url, payload)
	local ok, res = pcall(httpRequest, {
		Url = url,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode(payload),
	})
	if not ok or type(res) ~= "table" then return false, 0, tostring(res) end
	local code = res.StatusCode or 0
	local success = res.Success
	if success == nil then success = code ~= 0 and code < 300 end
	return success, code, tostring(res.Body or "")
end

local function buildRelayEgg(e)
	return {
		uid = tostring(e.uid),
		name = e.name,
		rarity = e.rarity.name,
		value = "$" .. e.money .. "/s",
		valueRaw = e.moneyRaw,
		scale = string.format("x%.2f", e.scale),
		area = tostring(e.area),
		mutations = table.concat(e.mutList, ", "),
		jobId = game.JobId,
		placeId = tostring(game.PlaceId),
		state = e.state or "unknown",
		version = e.version,
		validatedAt = serverClock(),
	}
end

local function sendBatch(batch, force)
	local chunk = {}
	for _, e in ipairs(batch) do table.insert(chunk, buildRelayEgg(e)) end
	return post(C.RELAY_URL, { key = C.RELAY_KEY, force = force == true, eggs = chunk })
end

local function sendErrorText(code)
	if code == 403 then return "clave incorrecta (403)" end
	if code == 429 then return "límite del Worker (429)" end
	if code == 502 then return "Discord rechazó el aviso (502)" end
	if code == 500 then return "Worker sin WEBHOOK_URL (500)" end
	if code == 400 then return "petición inválida (400)" end
	if code == 0 then return "sin respuesta del Worker" end
	return "error " .. tostring(code)
end

local function revalidate(candidates, skipSettle)
	if not skipSettle and C.REVALIDATE_SETTLE > 0 then task.wait(C.REVALIDATE_SETTLE) end
	local list, err = pullEggs(C.REVALIDATE_TIMEOUT)
	if not list then return nil, err or "sin datos frescos" end
	pcall(commitEggs, list)

	local byUid = {}
	for _, e in ipairs(list) do byUid[tostring(e.uid)] = e end

	local valid = {}
	for _, old in ipairs(candidates) do
		local now = byUid[tostring(old.uid)]
		local why
		if not now then
			why = "ya no está en el servidor"
		elseif now.version ~= old.version then
			why = string.format("cambió (v%d -> v%d)", old.version, now.version)
		elseif not isNotifiable(now) then
			why = now.reason or "no disponible"
		end
		if why then
			if C.VALIDATION_DEBUG then
				print(string.format("[EggHunter] descartado antes de avisar: %s (%s) -> %s", old.name, tostring(old.uid), why))
			end
		else
			table.insert(valid, now)
		end
	end
	return valid
end

local function deliver(pending)
	local sent, discarded = 0, 0
	local i = 1
	while i <= #pending do
		local candidates = {}
		for n = i, math.min(i + 9, #pending) do
			table.insert(candidates, pending[n])
		end
		i += 10

		if _G.EggHunterInstance ~= INSTANCE_ID then
			return sent, false, 0, "", discarded, "otra instancia tomó el control"
		end
		local blocked, why = cycleBlocksNotify()
		if blocked then return sent, false, 0, "", discarded, why end

		local valid, verr = revalidate(candidates)
		if not valid then return sent, false, 0, "", discarded, verr end
		discarded += #candidates - #valid

		local claimed = {}
		for _, e in ipairs(valid) do
			local k = notifyKey(e)
			if not sentUids[k] then
				sentUids[k] = true
				table.insert(claimed, e)
			end
		end

		if #claimed > 0 then
			local okSend, code, body = sendBatch(claimed, false)
			if not okSend then
				if code ~= 0 then
					for _, e in ipairs(claimed) do sentUids[notifyKey(e)] = nil end
				end
				return sent, true, code, body, discarded
			end
			sent += #claimed
			if i <= #pending then task.wait(1.5) end
		end
	end
	return sent, false, 0, "", discarded
end

local function isAutoNotifyCandidate(e)
	return C.NOTIFY_RARITIES[e.rarity.name] and e.moneyRaw >= C.MIN_NOTIFY_VALUE
		and isNotifiable(e) and not sentUids[notifyKey(e)]
end

local function notifyDiscord(list)
	if not discordOn or not C.DISCORD_CONFIGURED or not httpRequest or sending then return end
	if _G.EggHunterInstance ~= INSTANCE_ID then return end
	if os.clock() < discordBlockedUntil then return end

	local blocked, why = cycleBlocksNotify()
	if blocked then
		setDiscordStatus("Discord en pausa: " .. why, 6)
		return
	end

	local pending, unknownNames = {}, {}
	for _, e in ipairs(list) do
		if isAutoNotifyCandidate(e) then
			table.insert(pending, e)
		elseif e.rarity == UNKNOWN_RARITY then
			unknownNames[e.name] = true
		end
	end

	local unknownList = {}
	for name in pairs(unknownNames) do table.insert(unknownList, name) end
	local unknownNote = ""
	if #unknownList > 0 then
		table.sort(unknownList)
		unknownNote = " • sin rareza: " .. table.concat(unknownList, ", ")
		warn("[EggHunter] huevos sin rareza (faltan en precios.lua):", table.concat(unknownList, ", "))
	end

	if #pending == 0 then
		if unknownNote ~= "" then setDiscordStatus("Discord: nada nuevo" .. unknownNote, 10) end
		return
	end
	table.sort(pending, function(a, b)
		if a.priority == b.priority then return tostring(a.uid) < tostring(b.uid) end
		return a.priority > b.priority
	end)

	sending = true
	task.spawn(function()
		local okRun, sent, failed, failCode, failBody, discarded, verr = pcall(deliver, pending)
		sending = false

		if not okRun then
			warn("[EggHunter] error en avisos:", sent)
			return
		end

		local discardNote = (discarded or 0) > 0 and string.format(" • %d descartado(s): ya no disponibles", discarded) or ""
		if failed then
			local block = (failCode == 403 or failCode == 400 or failCode == 500) and 300 or 60
			discordBlockedUntil = os.clock() + block
			warn("[EggHunter] aviso automático falló:", failCode, failBody)
			setDiscordStatus(string.format("Discord falló: %s • reintento en %ds", sendErrorText(failCode), block), block)
		elseif verr then
			setDiscordStatus("Discord: no pude validar (" .. tostring(verr) .. "), reintento pronto" .. discardNote, 10)
		else
			setDiscordStatus(string.format("Discord: %d aviso(s) enviado(s)", sent) .. discardNote .. unknownNote, 15)
		end
	end)
end

--==================================================
-- ESCANEO AUTOMÁTICO
--==================================================
local loadingSince = 0

local function loadEggs(manual)
	if isLoading and os.clock() - loadingSince < 30 then return end
	isLoading = true
	loadingSince = os.clock()
	if manual == true then
		UI.setRefreshing(true)
		lastScanMsg = "Actualizando..."
		refreshSubtitle()
	end

	task.spawn(function()
		local list, err = pullEggs(10)
		local msg

		if list then
			local okC, errC = pcall(commitEggs, list)
			if okC then
				local free = 0
				for _, e in ipairs(list) do
					if e.status ~= "unavailable" then free += 1 end
				end
				msg = manual == true
					and string.format("Actualizado %s  •  %d huevos (%d disp.)", os.date("%H:%M:%S"), #list, free)
					or string.format("En vivo  •  %d huevos (%d disp.)", #list, free)
				failStreak = (#list == 0) and (failStreak + 1) or 0
			else
				warn("[EggHunter] error al mostrar huevos:", errC)
				msg = "Error al escanear (mira la consola)"
				list = nil
				failStreak += 1
			end
		else
			msg = err or "Error al escanear"
			failStreak += 1
		end

		if not list and #eggs > 0 and os.clock() - lastScan.at > C.STALE_CLEAR_SECONDS then
			eggs = {}
			lastCount = 0
			lastListSig = nil
			pcall(render)
		end

		scanDelay = (failStreak > 0 and failStreak <= 4) and C.FAST_RETRY_SECONDS or C.AUTO_REFRESH_SECONDS

		isLoading = false
		if manual == true then UI.setRefreshing(false) end
		lastScanMsg = msg
		refreshSubtitle()

		if list then
			local okN, errN = pcall(notifyDiscord, list)
			if not okN then warn("[EggHunter] error en avisos:", errN) end
		end
	end)
end

--==================================================
-- SALTO DE SERVIDOR
--==================================================
local hopping, queued = false, false
local hopRetryAt = 0
local badServers = {}
local teleportFails = 0
local lastTeleportAt = 0
local fastRetry = false
local currentTarget = nil
local hopToken = 0

local function isBad(id)
	local t = badServers[id]
	if t and os.clock() - t < C.BAD_SERVER_TTL then return true end
	badServers[id] = nil
	return false
end

function saveState()
	if not canFile then return end
	pcall(function() writefile(C.SAVE_FILE, HttpService:JSONEncode(state)) end)
end

local function loadState()
	if canFile then
		pcall(function()
			if isfile(C.SAVE_FILE) then
				local d = HttpService:JSONDecode(readfile(C.SAVE_FILE))
				if type(d) == "table" then
					state.autoHop = d.autoHop == true
					local sameCycle = d.cycleSeconds == C.CYCLE_SECONDS and not C.CYCLE_RESET
					if type(d.cycleOffset) == "number" and sameCycle then
						state.cycleOffset = d.cycleOffset
					end
					if type(d.samples) == "table" and sameCycle then
						for _, v in ipairs(d.samples) do
							if type(v) == "number" then table.insert(cycleSamples, v) end
						end
					end
					if type(d.visited) == "table" then state.visited = d.visited end
					if type(d.serverList) == "table" and type(d.serverListAt) == "number" then
						state.serverList, state.serverListAt = d.serverList, d.serverListAt
					end
					if type(d.blockedUntil) == "number" then state.blockedUntil = d.blockedUntil end
					-- NO restauramos huntActive automáticamente al reiniciar
					-- Solo se activa de nuevo si realmente ve un raro
					state.huntActive = false
					if type(d.huntLastRare) == "number" then state.huntLastRare = d.huntLastRare end
					if type(d.huntDry) == "number" then state.huntDry = d.huntDry end
				end
			end
		end)
	end

	state.samples = cycleSamples
	state.cycleSeconds = C.CYCLE_SECONDS
	local now = os.time()
	for id, t in pairs(state.visited) do
		if type(t) ~= "number" or now - t > C.VISITED_TTL then state.visited[id] = nil end
	end
	state.visited[game.JobId] = now
	saveState()
end
loadState()

local function applyHopState()
	UI.setAutoHop(state.autoHop)
	if not state.autoHop then UI.setHop("Salto automático apagado") end
end

local serverCache, cacheAt = {}, 0
local rateLimitHits = 0
local fetchBlockedUntil = 0
local fetching = false
local sortFlip = false
local pickFails = 0

local function setCache(list)
	serverCache, cacheAt = list, os.clock()
	state.serverList, state.serverListAt = list, os.time()
	saveState()
end

if type(state.serverList) == "table" and type(state.serverListAt) == "number"
	and os.time() - state.serverListAt < C.CACHE_SECONDS then
	serverCache = state.serverList
	cacheAt = os.clock() - (os.time() - state.serverListAt)
else
	state.serverList, state.serverListAt = nil, nil
end
if type(state.blockedUntil) == "number" and state.blockedUntil > os.time() then
	fetchBlockedUntil = os.clock() + (state.blockedUntil - os.time())
end

local function inRange(s)
	local n = s.playing or 0
	return n >= C.MIN_PLAYERS and n <= C.MAX_PLAYERS_PREF
end

local function usable(s)
	local n = s.playing or 0
	return n <= C.MAX_PLAYERS_HARD and (s.maxPlayers or 0) - n >= C.MIN_FREE_SLOTS
end

local function fetchServers()
	local list, cursor, good = {}, nil, 0
	for _ = 1, C.HOP_PAGES do
		local url = string.format(
			"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&excludeFullGames=true&limit=100",
			game.PlaceId, sortFlip and "Desc" or "Asc"
		)
		if cursor then url = url .. "&cursor=" .. HttpService:UrlEncode(cursor) end

		local ok, res = pcall(httpRequest, { Url = url, Method = "GET" })
		if not ok or type(res) ~= "table" then
			return list, "no se pudo consultar la lista"
		end
		if res.StatusCode == 429 then
			local h = res.Headers
			return list, "limit", h and tonumber(h["retry-after"] or h["Retry-After"])
		end

		local okJson, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
		if not okJson or type(data) ~= "table" or type(data.data) ~= "table" then
			return list, "respuesta inválida de Roblox"
		end
		for _, s in ipairs(data.data) do
			if usable(s) then
				table.insert(list, { id = s.id, playing = s.playing, maxPlayers = s.maxPlayers })
				if inRange(s) then good += 1 end
			end
		end
		if good >= 15 then break end

		cursor = data.nextPageCursor
		if not cursor then break end
		task.wait(1.2)
	end
	return list
end

local function refreshList(force)
	if fetching or not httpRequest then return end
	if os.clock() < fetchBlockedUntil then return end
	if not force and #serverCache > 0 and os.clock() - cacheAt < C.LIST_MAX_AGE then return end

	fetching = true
	local okRun, list, err, retryAfter = pcall(fetchServers)
	fetching = false
	if not okRun then
		warn("[EggHunter] error al pedir servidores:", list)
		return
	end

	if err == "limit" then
		rateLimitHits += 1
		local wait = retryAfter and math.clamp(retryAfter + 2, 5, 180) or math.min(20 * rateLimitHits, 180)
		fetchBlockedUntil = os.clock() + wait
		state.blockedUntil = os.time() + wait
		saveState()
		if #list > 0 then setCache(list) end
	elseif #list > 0 then
		rateLimitHits = 0
		setCache(list)
	end
end

local function prefetchList()
	if fetching then return end
	if #serverCache > 0 and os.clock() - cacheAt < C.LIST_MAX_AGE then return end
	task.spawn(refreshList)
end

local TIERS = {
	function(s) return not state.visited[s.id] and inRange(s) end,
	function(s) return not state.visited[s.id] and (s.playing or 0) >= 1 end,
	function(s) return not state.visited[s.id] end,
	function(s) return true end,
}

local function pickServer()
	local waited = 0
	while fetching and waited < 15 do waited += task.wait(0.2) end
	refreshList()

	if #serverCache == 0 then
		if os.clock() < fetchBlockedUntil then
			return nil, string.format("Roblox limitó las consultas (%ds)", math.ceil(fetchBlockedUntil - os.clock()))
		end
		return nil, "Roblox no devolvió servidores"
	end

	for _, accept in ipairs(TIERS) do
		local pool = {}
		for i, s in ipairs(serverCache) do
			if s.id ~= game.JobId and not isBad(s.id) and usable(s) and accept(s) then
				table.insert(pool, i)
			end
		end
		if #pool > 0 then
			return table.remove(serverCache, pool[math.random(#pool)])
		end
	end

	serverCache = {}
	state.serverList = nil
	sortFlip = not sortFlip
	return nil, "Sin servidores de 0-" .. C.MAX_PLAYERS_HARD .. " jugadores, pido otra lista"
end

local function hopServer()
	if hopping then return end
	if C.HOP_MODE ~= "random" and not httpRequest then
		UI.setHop("Tu ejecutor no tiene request()", THEME.Warn)
		return
	end

	local gap = C.MIN_TELEPORT_GAP - (os.clock() - lastTeleportAt)
	if gap > 0 then
		hopRetryAt = os.clock() + gap
		return
	end

	hopping = true
	hopToken += 1
	local myToken = hopToken

	task.spawn(function()
		local useRandom = C.HOP_MODE == "random"
		local server

		if not useRandom then
			UI.setHop("Buscando servidor...", THEME.Cyan)
			local err
			server, err = pickServer()
			if server then
				pickFails = 0
				state.visited[server.id] = os.time()
				saveState()
			else
				pickFails += 1
				if pickFails >= C.PICK_FAILS_BEFORE_RANDOM or teleportFails >= C.FAILS_BEFORE_RANDOM then
					useRandom = true
					UI.setHop("Sin lista (" .. tostring(err) .. "): salto aleatorio", THEME.Warn)
				else
					UI.setHop(tostring(err) .. " • reintento en 3s", THEME.Warn)
					hopRetryAt = os.clock() + 3
					hopping = false
					return
				end
			end
		end

		if not queued and C.SCRIPT_URL ~= "" and type(queue_on_teleport) == "function" then
			queued = true
			pcall(queue_on_teleport, string.format('loadstring(game:HttpGet("%s"))()', C.SCRIPT_URL))
		end

		lastTeleportAt = os.clock()
		fastRetry = false
		currentTarget = server and server.id or nil

		local ok, perr
		if useRandom then
			pickFails = 0
			teleportFails = 0
			UI.setHop("Saltando a un servidor aleatorio...", THEME.Green)
			ok, perr = pcall(function()
				TeleportService:Teleport(game.PlaceId, LocalPlayer)
			end)
		else
			UI.setHop(string.format("Saltando (%d/%d jugadores)...", server.playing or 0, server.maxPlayers or 0), THEME.Green)
			ok, perr = pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
			end)
		end

		if not ok then
			warn("[EggHunter] el teleport no pudo iniciar:", perr)
			if server then badServers[server.id] = os.clock() end
			teleportFails += 1
			fastRetry = true
			UI.setHop("Falló el teleport, probando otro servidor...", THEME.Warn)
			hopRetryAt = os.clock() + 2
			hopping = false
			return
		end

		task.delay(C.TELEPORT_WAIT, function()
			if UI.alive() and hopping and hopToken == myToken then
				hopping = false
				if currentTarget then badServers[currentTarget] = os.clock() end
				hopRetryAt = os.clock() + C.HOP_RETRY_SECONDS
			end
		end)
	end)
end

local SOFT_FAILS = {
	[Enum.TeleportResult.GameFull] = true,
	[Enum.TeleportResult.GameEnded] = true,
	[Enum.TeleportResult.GameNotFound] = true,
	[Enum.TeleportResult.Unauthorized] = true,
}

table.insert(connections, TeleportService.TeleportInitFailed:Connect(function(player, result, message)
	if player ~= LocalPlayer then return end
	local resultName = result and result.Name or "?"
	warn("[EggHunter] TeleportInitFailed:", resultName, message)

	if result == Enum.TeleportResult.IsTeleporting then
		UI.setHop("Ya hay un teleport en curso, espero...", THEME.Warn)
		return
	end

	if currentTarget then badServers[currentTarget] = os.clock() end

	local wait
	if result == Enum.TeleportResult.Flooded then
		wait = 20
	elseif SOFT_FAILS[result] then
		wait = 1
		fastRetry = true
	else
		teleportFails += 1
		fastRetry = true
		wait = math.min(1 + 2 * teleportFails, 15)
	end

	UI.setHop(string.format("Teleport falló (%s), reintento en %ds", resultName, wait), THEME.Warn)
	hopRetryAt = os.clock() + wait
	hopping = false
end))

local function hasRareHere()
	for _, e in ipairs(eggs) do
		if C.NOTIFY_RARITIES[e.rarity.name] and e.moneyRaw >= C.RARE_MIN_VALUE and isNotifiable(e) then
			return true
		end
	end
	return false
end

local function hasPendingNotify()
	if not discordOn or not C.DISCORD_CONFIGURED or not httpRequest then return false end
	if os.clock() < discordBlockedUntil then return false end
	if cycleBlocksNotify() then return false end
	for _, e in ipairs(eggs) do
		if isAutoNotifyCandidate(e) then return true end
	end
	return false
end

-- ¿Se están llenando todavía los huevos?
local function fillStatus()
	if C.EXPECTED_EGGS <= 0 or not scannedOnce then return false end
	local n = #eggs
	local phase = cyclePhase()
	if phase ~= nil and phase < C.FILL_STABLE_SECONDS then return true, n end
	if n >= math.ceil(C.EXPECTED_EGGS * C.FILL_RATIO) then return false end
	if phase then
		-- Después de la renovación espera más tiempo
		return phase < C.FILL_WAIT_MAX, n
	end
	if lastGrowAt > 0 and os.clock() - lastGrowAt < C.FILL_STABLE_SECONDS then return true, n end
	return false
end

--==================================================
-- BUCLE DE CAZA (CORREGIDO)
--==================================================
-- REGLA PRINCIPAL:
-- Solo salta si HAY un raro confirmado en ESTA sala ahora mismo.
-- Si no hay nada → se queda quieto escaneando.
task.spawn(function()
	local startedAt = os.clock()
	local hopAt, hopCap

	while UI.alive() and _G.EggHunterInstance == INSTANCE_ID do
		task.wait(1)

		if not (state.autoHop and not hopping and os.clock() >= hopRetryAt) then
			hopAt, hopCap = nil, nil
			continue
		end

		local ready = scannedOnce or (os.clock() - startedAt) > C.SCAN_TIMEOUT
		local phase = cyclePhase()
		local stale = phase ~= nil and phase >= C.SEARCH_WINDOW
		local calibrating = C.CYCLE_MODE == "auto" and state.cycleOffset == nil
			and (os.clock() - startedAt) < C.CALIBRATION_TIMEOUT
		local now = os.time()

		-- Confirma solo con dos respuestas nuevas del servidor, no dos vueltas del bucle.
		if scanRevision ~= confirmedScanRevision then
			confirmedScanRevision = scanRevision
			local rareNow = scannedOnce and (os.clock() - lastScan.at) < 25 and hasRareHere()
			if rareNow then rareConfirmCount += 1 else rareConfirmCount = 0 end
		end
		local rareConfirmed = rareConfirmCount >= 2 and scannedOnce
			and (os.clock() - lastScan.at) < 25 and hasRareHere()

		if rareConfirmed then
			state.huntLastRare = now
			if not state.huntActive and not stale then
				state.huntActive = true
				state.huntDry = 0
				saveState()
				print("[EggHunter] Raro CONFIRMADO → cacería activa")
			end
		end

		-- Apagar cacería si se acaba la ventana o pasa mucho tiempo sin raros
		if state.huntActive then
			local endReason
			if stale then
				endReason = "terminó la ventana de búsqueda"
			elseif now - (state.huntLastRare or 0) > C.HUNT_IDLE_SECONDS then
				endReason = "sin ver raros en " .. C.HUNT_IDLE_SECONDS .. "s"
			end
			if endReason then
				state.huntActive = false
				rareConfirmCount = 0
				hopAt, hopCap = nil, nil
				saveState()
				print("[EggHunter] Cacería terminada: " .. endReason)
			end
		end

		if not ready then
			hopAt, hopCap = nil, nil
			UI.setHop("Escaneando este servidor...", THEME.Cyan)

		elseif calibrating then
			hopAt, hopCap = nil, nil
			UI.setHop(string.format("Calibrando ciclo: %d/3 renovaciones vistas", math.min(#cycleSamples, 3)), THEME.Cyan)

		elseif stale then
			hopAt, hopCap = nil, nil
			UI.setHop(string.format("Descansando: nuevos huevos en %ds", math.ceil(C.CYCLE_SECONDS - phase)), THEME.Gold)

		-- ========== SOLO SALTA SI HAY RARO AQUÍ ==========
		elseif rareConfirmed then
			local filling, fillN = fillStatus()

			if filling then
				-- Todavía se están llenando los huevos → espera
				hopAt = nil
				UI.setHop(string.format("Esperando huevos nuevos: %d/%d", fillN or 0, C.EXPECTED_EGGS), THEME.Cyan)
			else
				if not hopAt then
					hopAt = os.clock() + (fastRetry and 1 or C.HOP_DELAY_SECONDS)
					hopCap = hopAt + C.NOTIFY_HOP_GRACE
				end
				if sending or isLoading or hasPendingNotify() then
					hopAt = math.min(math.max(hopAt, os.clock() + 2), hopCap)
				end

				local left = math.ceil(hopAt - os.clock())
				if left > 0 and left <= 4 then prefetchList() end

				if left > 0 then
					local windowLeft = phase and math.max(0, math.ceil(C.SEARCH_WINDOW - phase)) or nil
					UI.setHop(
						string.format("¡Raro aquí! Saltando en %ds%s", left,
							windowLeft and (" • ventana: " .. windowLeft .. "s") or ""),
						THEME.Gold
					)
				else
					hopAt, hopCap = nil, nil
					print("[EggHunter] Salto porque hay raro confirmado en esta sala")
					hopServer()
				end
			end

		-- No hay raro → se queda quieto
		else
			hopAt, hopCap = nil, nil
			if phase then
				UI.setHop(string.format("Sin raro aquí • no salta • reinicio en %ds", math.ceil(C.CYCLE_SECONDS - phase)), THEME.Muted)
			else
				UI.setHop("Sin raro aquí • esperando (no salta)", THEME.Muted)
			end
		end
	end
end)

--==================================================
-- EVENTOS Y ARRANQUE
--==================================================
UI.onRefresh = function() loadEggs(true) end
UI.onHopNow = function()
	hopRetryAt = 0
	hopServer()
end
UI.onAuto = function()
	autoRefresh = not autoRefresh
	UI.setAuto(autoRefresh)
end
UI.onAutoHop = function()
	state.autoHop = not state.autoHop
	saveState()
	applyHopState()
	if state.autoHop then
		UI.setHop("Salto automático activado: solo salta si hay raro aquí", THEME.Green)
	end
end

task.spawn(function()
	while UI.alive() and _G.EggHunterInstance == INSTANCE_ID do
		task.wait(scanDelay)
		if autoRefresh then loadEggs() end
	end
end)

UI.Gui.Destroying:Connect(function()
	for _, c in ipairs(connections) do c:Disconnect() end
end)

UI.setAuto(autoRefresh)
applyHopState()
UI.setSort(sortIndex)

if state.autoHop then
	UI.setHop("Salto automático activado: solo salta si hay raro aquí", THEME.Green)
end

task.delay(0.8, loadEggs)
