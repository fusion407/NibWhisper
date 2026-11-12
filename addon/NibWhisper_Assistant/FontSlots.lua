-- Receives the helper's replies through font files instead of load-on-demand addons.
-- The helper writes each packet into a font whose glyph widths encode the bytes (tools/font-transport.mjs).
-- This file measures those widths. Rules learned from trials on this client:
--   a font file is read from disk the first time it loads and is then fixed for the session, so each file is used once;
--   a file that was tried before the helper had written it cannot be relied on afterwards, so it is never tried twice;
--   a character measured alone reports its drawing, so characters are measured in a run before a known tail.
--
-- Each request owns a block of files. The first LADDER files are a ladder: the game tries one fresh rung at a time,
-- a few seconds apart. The helper writes its receipt to every rung, and later a "reply ready" note to every rung,
-- so whichever rung the game tries next is one it has never touched. The reply itself sits in the files after the
-- ladder, which the game only opens once a rung has said they are ready.
local A = _G.NibWhisper
if not A then return end
local Slots = {}
A.FontSlots = Slots

local POOL, BLOCK, LADDER = 8000, 32, 22   -- must match POOL_SIZE, BLOCK and LADDER in tools/font-transport.mjs
local FIRST, LIMIT = 0xE000, 6400          -- DATA_FIRST and DATA_LIMIT
local folder = "Interface\\AddOns\\NibWhisper_Assistant\\Fonts\\"
local tail, repeats = "AA", 4
local LOAD_WAIT = 1.5                      -- a real font loads in about half a second; a placeholder never does
Slots.POOL, Slots.BLOCK, Slots.LADDER = POOL, BLOCK, LADDER

local function character(code)
    return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end
local function measure(text, value)
    if not pcall(text.SetText, text, value) then return 0 end
    return (text.GetUnboundedStringWidth and text:GetUnboundedStringWidth()) or text:GetStringWidth() or 0
end
local function advance(text, index, base)
    return (measure(text, string.rep(character(FIRST + index), repeats) .. tail) - base) / repeats
end
local function clock() return (GetTime and GetTime()) or 0 end
local function wallClock() local stamp = date or (os and os.date); return stamp and stamp("%H:%M:%S") or "?" end

function Slots.Path(index) return string.format("%sR%04d.ttf", folder, index) end

-- Seconds to wait before trying the next rung: quick at first, slower while a long answer is being written.
function Slots.Gap(rung)
    return rung < 6 and 2 or rung < 10 and 3 or rung < 14 and 5 or 8
end

-- Reads the bytes a loaded font carries. Returns a string, or nil and the reason.
function Slots:Decode(text)
    local base = measure(text, tail)
    local low, high = advance(text, 0, base), advance(text, 255, base)
    if high - low < 64 then return nil, "no data" end
    local step = (high - low) / 255
    local function value(index)
        local exact = (advance(text, index, base) - low) / step
        local rounded = math.floor(exact + 0.5)
        -- A width halfway between two values cannot be trusted.
        if math.abs(exact - rounded) > 0.4 then return nil end
        return rounded
    end
    for i = 0, 255 do if value(i) ~= i then return nil, "calibration" end end
    local high8, low8 = value(256), value(257)
    if not high8 or not low8 then return nil, "length" end
    local length = high8 * 256 + low8
    if length < 1 or 258 + length > LIMIT then return nil, "length" end
    local characters = {}
    for i = 1, length do
        local byte = value(257 + i)
        if not byte or byte < 0 or byte > 255 then return nil, "byte" end
        characters[i] = string.char(byte)
    end
    return table.concat(characters)
end

local function adler(bytes)
    local a, b = 1, 0
    for i = 1, #bytes do a = (a + bytes:byte(i)) % 65521; b = (b + a) % 65521 end
    return b * 65536 + a
end

-- A part is "NF1", its number, the part count, a four-byte checksum, then a slice of the packet.
-- Part number 0 is the "reply ready" note: it carries no data, only how many reply files to read.
function Slots.Unwrap(bytes)
    if type(bytes) ~= "string" or #bytes < 9 or bytes:sub(1, 3) ~= "NF1" then return nil end
    local part, count, c1, c2, c3, c4 = bytes:byte(4, 9)
    local chunk = bytes:sub(10)
    if part > count or count < 1 or count > BLOCK - LADDER - 1 then return nil end
    if adler(chunk) ~= ((c1 * 256 + c2) * 256 + c3) * 256 + c4 then return nil end
    return chunk, part, count
end

-- Every file gets a text object of its own. The trials that proved this transport each read a font through a
-- fresh one; moving one object from a file that failed to load onto the next file is not something they covered.
function Slots:NewText()
    if not self.holder then
        self.holder = CreateFrame("Frame", nil, UIParent)
        self.holder:SetSize(1, 1); self.holder:SetPoint("TOPLEFT"); self.holder:SetAlpha(0)
    end
    local text = self.holder:CreateFontString(nil, "OVERLAY")
    text:SetPoint("TOPLEFT")
    return text
end

-- Whether the reply-file folder is installed, decided once per login from a font that is always there.
-- A request never switches transport half way: the helper has already chosen from what the request named.
function Slots:Present()
    if self.present == nil then
        local text = self:NewText()
        local ok, problem = pcall(text.SetFont, text, folder .. "Base.ttf", 64, "")
        self.present = ok or not tostring(problem):find("not found", 1, true)
    end
    return self.present
end

-- Reserves the next block of files for one request. Returns the first file number, or nil when this
-- game session has used the whole pool or the files are not installed.
function Slots:Reserve()
    local db = A.db
    if not db or not self:Present() then return nil end
    if not self.checked then
        self.checked = true
        local started = debugprofilestop and debugprofilestop() or 0
        -- The clock restarts with the game. A smaller value than the one saved at logout means every file can be read again.
        if type(db.fontClock) ~= "number" or started < db.fontClock or type(db.fontUsed) ~= "number" then db.fontUsed = 0 end
        db.fontClock = started
    end
    if db.fontUsed + BLOCK > POOL then self.spent = true; return nil end
    local index = tonumber(db.fontNext) or 1
    if index % 1 ~= 0 or index < 1 or index + BLOCK - 1 > POOL then index = 1 end
    db.fontNext, db.fontUsed = index + BLOCK, db.fontUsed + BLOCK
    return index
end

function Slots:Logout()
    if A.db and debugprofilestop then A.db.fontClock = debugprofilestop() end
end

-- What the reader was doing, for the message shown when a request times out.
function Slots:Describe(pending)
    local state = pending.fontState
    if not state then return "" end
    if state.data then return string.format(" (reading reply file %d of %d)", state.data.index, state.data.count) end
    return string.format(" (tried %d reply files in %d s from file %d, %d readable)", state.rung + (state.file and 1 or 0), math.floor(clock() - state.started), pending.font, state.read or 0)
end

-- A line-by-line account of what the reader tried, with clock times that can be set beside the helper's log.
function Slots:Report(pending)
    local state = pending.fontState
    if not state or #state.log == 0 then return nil end
    return string.format("Nib reply files, block %d, asked at %s\n%s", pending.font, state.asked, table.concat(state.log, "\n"))
end

-- Tries to load one file. Returns "loaded", "waiting", or "empty" once it has had long enough.
local function load(self, state, index, now)
    if state.file ~= index then state.file, state.since, state.ready, state.text = index, now, false, self:NewText() end
    local text = state.text
    local ok, loaded = pcall(text.SetFont, text, self.Path(index), 64, "")
    state.answer = ok and ("SetFont returned " .. tostring(loaded)) or ("SetFont error: " .. tostring(loaded):match("^[^\n]*"):sub(-80))
    if ok and loaded ~= false then
        -- Measure on the poll after loading, once the font has been applied.
        if not state.ready then state.ready = true; return "waiting" end
        return "loaded"
    end
    state.ready = false
    return now - state.since >= LOAD_WAIT and "empty" or "waiting"
end

-- Called a few times a second while a request with reserved files is waiting.
-- Returns a message when the files cannot deliver this reply; otherwise nil.
function Slots:Poll(pending)
    local now = clock()
    local state = pending.fontState
    if not state then
        -- The helper needs a few seconds to read the request off the screen, so the first rung waits.
        state = {rung = 0, nextAt = now + 4, read = 0, started = now, asked = wallClock(), log = {}}
        pending.fontState = state
    end
    local unreadable = "Nib could not read the reply file. Ask again, or use AI copy and paste."

    if state.data then
        -- The reply files were complete before the note that named them was written, so each loads on its first try.
        local data = state.data
        local result = load(self, state, pending.font + LADDER + data.index - 1, now)
        if result == "waiting" then return end
        state.log[#state.log + 1] = string.format("%s reply file %d: %s (%s)", wallClock(), state.file, result, state.answer)
        if result == "empty" then return unreadable end
        local chunk, part, count = self.Unwrap(self:Decode(state.text))
        state.text:SetText(""); state.file = nil
        if not chunk or part ~= data.index or count ~= data.count then return unreadable end
        data.parts[part] = chunk
        if part < count then data.index = part + 1; return end
        pending.fontState = nil
        if not _G.NibWhisper_Receive(table.concat(data.parts)) and A.pending == pending then return "That reply did not match this question. Ask again." end
        return
    end

    if not state.file then
        if now < state.nextAt or state.rung >= LADDER then return end
    end
    local result = load(self, state, pending.font + state.rung, now)
    if result == "waiting" then return end
    -- Loaded or not, this rung is finished with. The next one is a file the game has never tried.
    state.log[#state.log + 1] = string.format("%s rung file %d: %s (%s)", wallClock(), state.file, result, state.answer)
    state.file = nil
    state.rung = state.rung + 1
    state.nextAt = now + self.Gap(state.rung)
    if result == "empty" then return end
    local chunk, part, count = self.Unwrap(self:Decode(state.text))
    state.text:SetText("")
    if not chunk then return unreadable end
    state.read = state.read + 1
    if part == 0 then
        state.data = {index = 1, count = count, parts = {}}
    elseif not pending.received then
        -- The receipt. One for some other request means this block held an old file.
        if count ~= 1 or not _G.NibWhisper_Receive(chunk) then return "Nib found an old reply file. Ask again." end
        -- The answer usually follows within seconds, so look again soon.
        state.nextAt = now + 2
    end
end
