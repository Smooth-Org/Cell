local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@class CellIndicatorFuncs
local I = Cell.iFuncs

local DF = Cell.DF

-- ============================================================================
-- Cell indicator -> Blizzard aura container
-- ============================================================================
-- Translates a Cell custom-indicator definition into a container config. Cell's model
-- is "enumerate the unit's auras, match them against my spell list, draw what matched".
-- That model is dead in restricted content on 12.1. The container model is "declare
-- what you want to see, style what Blizzard draws", and this file is the translation
-- between the two.
--
-- WHAT TRANSLATES
--   auras (spell list)  -> candidateFilters.includeSpellIDs
--   auraType buff/debuff -> HELPFUL / HARMFUL
--   castBy me/others     -> the PLAYER / !PLAYER filter tokens
--   num                  -> maxFrameCount
--
-- WHAT DOES NOT
--   Per-spell priority ordering. Cell orders by a user-assigned number per spell and
--   single-aura indicators show the top one. Selecting the top requires knowing which
--   aura is present, which is a read. Container order is Blizzard's sort rule only, so
--   only the "show up to N" types are converted here. See ICONS ONLY below.
--
--   trackByName. Filtering is by numeric spell ID, so a name that maps to several IDs
--   cannot be expressed. Indicators using it are left on the legacy path.
-- ============================================================================

-- ============================================================================
-- support
-- ============================================================================
-- Thin pass-through to the container layer's own probe, which creates a throwaway
-- container to verify the widget type and template both exist on this build. It never
-- probes in combat and does not cache a combat-refused answer.
function I.IsAuraContainerSupported()
    if not DF or not DF.AuraContainer or not DF.AuraContainer.IsSupported then return false end
    return DF.AuraContainer.IsSupported() and true or false
end

-- ============================================================================
-- container registry
-- ============================================================================
-- Live handles, so a container can be deregistered when its indicator is destroyed.
-- Cell tears down and rebuilds indicators on every layout update, and a container that
-- is merely reparented to nil leaks a live Blizzard widget.
local liveHandles = {}

-- ============================================================================
-- spell list
-- ============================================================================
-- Cell stores auras as a map of spellID -> priority (or -> {priority, color}). The
-- container only wants the IDs; priority is discarded here, which is precisely the
-- information loss described above.
-- includeSpellIDs is a MAP keyed by spell ID, not an array: Blizzard tests
-- includeSpellIDs[spellID], so a list produces nil for every lookup and silently filters
-- everything out. Cell already keys its aura table by spell ID, so this is a value swap.
-- Returns the map and its size, since # is meaningless on a keyed table.
local function BuildSpellIDList(auras)
    if type(auras) ~= "table" then return nil end

    -- Cell stores the raw list as an ARRAY: the index is the spell's priority and the
    -- VALUE is the spell ID (see F.ConvertSpellTable, which iterates with ipairs and keys
    -- its output by the value). Reading the key instead builds a filter for spell IDs
    -- 1..N, which matches nothing.
    local ids, count = {}, 0
    for _, spell in ipairs(auras) do
        -- name-tracked entries are strings and cannot be expressed as a spell ID filter
        if type(spell) == "number" then
            ids[spell] = true
            count = count + 1
        end
    end

    if count == 0 then return nil end
    return ids, count
end

-- Same array shape as above: inspect the VALUES, not the keys. Reading keys made this
-- always return false, so a name-tracked indicator would have been wrongly accepted.
local function UsesNameTracking(auras)
    if type(auras) ~= "table" then return false end
    for _, spell in ipairs(auras) do
        if type(spell) ~= "number" then return true end
    end
    return false
end

-- ============================================================================
-- layout coercion
-- ============================================================================
-- Cell stores geometry as {x, y} pairs; Blizzard's container requires plain numbers and
-- rejects a whole aura group if any layout value is not one. Tolerates a bare number too,
-- since not every indicator type stores a pair.
local function Axis(value, index, fallback)
    if type(value) == "table" then
        return tonumber(value[index]) or fallback
    end
    return tonumber(value) or fallback
end

-- ============================================================================
-- filter string
-- ============================================================================
-- Returned as a LIST of filter strings. The container layer documents a bare string as
-- acceptable, but every shipping caller wraps it, and the list form is what its own row
-- builder produces, so match that rather than the doc.
local function BuildFilterString(auraType, castBy)
    local base = (auraType == "debuff") and "HARMFUL" or "HELPFUL"

    if castBy == "me" then
        return {base .. "|PLAYER"}
    elseif castBy == "others" then
        return {base .. "|!PLAYER"}
    end

    return {base}
end

-- ============================================================================
-- convertibility
-- ============================================================================
-- Answered per indicator rather than per type, because the same type can be
-- convertible or not depending on whether it uses name tracking.
function I.CanConvertIndicatorToContainer(indicatorTable)
    if not I.IsAuraContainerSupported() then return false end
    if type(indicatorTable) ~= "table" then return false end

    -- ICONS ONLY. Every other type either shows a single top-priority aura (needs a
    -- read to select) or renders outside a button subtree in ways not yet ported.
    if indicatorTable["type"] ~= "icons" then return false end
    if indicatorTable["trackByName"] or UsesNameTracking(indicatorTable["auras"]) then return false end
    if not BuildSpellIDList(indicatorTable["auras"]) then return false end

    return true
end

-- ============================================================================
-- config
-- ============================================================================
function I.BuildContainerConfig(indicatorTable, unit)
    local ids, count = BuildSpellIDList(indicatorTable["auras"])
    if not ids then return nil end

    return {
        -- diagnostic only; the container layer shallow-copies the config and ignores
        -- keys it does not know, and # cannot count a table keyed by spell ID
        spellIDCount = count,
        unit = unit,
        mode = "row",
        filter = BuildFilterString(indicatorTable["auraType"], indicatorTable["castBy"]),
        candidateFilters = {
            includeSpellIDs = ids,
        },
        max = tonumber(indicatorTable["num"]) or 3,
        enabled = true,
        -- Cell stores size and spacing as {x, y} pairs. Blizzard requires plain numbers
        -- and rejects the group outright ("elementSpacing must be a number"), which fails
        -- AddAuraGroup and leaves a healthy-looking container with no buttons at all.
        layout = {
            sizeX = Axis(indicatorTable["size"], 1, 20),
            sizeY = Axis(indicatorTable["size"], 2, 20),
            spacingX = Axis(indicatorTable["spacing"], 1, 0),
            spacingY = Axis(indicatorTable["spacing"], 2, 0),
        },
        style = {
            icon = {show = true, zoom = indicatorTable["iconZoom"] and true or false},
            -- The swipe is what makes an aura icon read as timed rather than as a static
            -- picture, so it stays on regardless of Cell's duration-text setting. Passing
            -- show=false here is what suppressed it entirely.
            -- numbers drives Blizzard's own countdown text (SetHideCountdownNumbers), which
            -- is the only timer available: the addon cannot write text into these buttons
            -- while auras are secret.
            cooldown = {
                show = true,
                swipe = true,
                -- Cell's own aura icons call SetReverse(true) (Indicators/Base.lua), so the
                -- icon reads lit while the aura is full and darkens as it expires. Without
                -- this the swipe runs the opposite way to every other Cell indicator.
                reverse = true,
                numbers = indicatorTable["showDuration"] and true or false,
            },
            stacks = indicatorTable["showStack"] and {} or nil,
        },
    }
end

-- ============================================================================
-- lifecycle
-- ============================================================================
-- Containers are keyed per unit button per indicator, since each renders one unit.
function I.CreateContainerIndicator(parent, indicatorTable)
    if not I.CanConvertIndicatorToContainer(indicatorTable) then return nil end
    if not DF or not DF.AuraContainer then return nil end

    local unit = parent.states and parent.states.displayedUnit
    local config = I.BuildContainerConfig(indicatorTable, unit)
    if not config then return nil end

    local handle = DF.AuraContainer:Create(parent.widgets.indicatorFrame, config)
    if not handle then return nil end

    liveHandles[#liveHandles + 1] = handle

    -- Cell's layout code positions and sizes indicators directly, so hand it the plain
    -- anchor frame rather than the container itself
    local frame = handle:GetFrame()
    frame.containerHandle = handle
    frame.indicatorType = "icons-container"

    -- isContainer marks this indicator as Blizzard-driven. The aura update path checks it
    -- and skips the indicator entirely: Cell must not try to feed something it cannot read
    -- the contents of.
    frame.isContainer = true

    -- Cell's own show path is bypassed for containers, so intent has to be stated here.
    -- Enable arms aura-event registration; without it the container renders nothing.
    if handle.SetShown then handle:SetShown(true) end
    if handle.Enable then handle:Enable() end

    I.StubContainerIndicatorInterface(frame)
    return frame
end

-- ============================================================================
-- legacy interface
-- ============================================================================
-- Cell's layout and appearance code drives indicators through a wide method surface
-- built for widgets it owns. A container renders itself, so those calls have nothing to
-- do, but they still have to EXIST or every settings change errors. Size and position
-- are the exception: those are real frame methods and stay live, because Cell still
-- decides where the container sits and how large it is.
local function Noop() end

function I.StubContainerIndicatorInterface(frame)
    frame.UpdateSize = Noop
    frame.SetFont = Noop
    frame.SetOrientation = Noop
    frame.SetSpacing = Noop
    frame.SetNumPerLine = Noop
    frame.ShowDuration = Noop
    frame.ShowStack = Noop
    frame.ShowAnimation = Noop
    frame.SetupGlow = Noop
    frame.UpdatePixelPerfect = Noop
    frame.SetCooldown = Noop
end

function I.UpdateContainerIndicatorUnit(frame, unit)
    if not frame or not frame.containerHandle then return end


    frame.containerHandle:SetUnit(unit)
end

-- Retargets every container-backed indicator on a unit button. Called wherever
-- displayedUnit changes, alongside the private-aura anchor, which has the same need for
-- the same reason: both render a unit Cell hands them rather than data Cell reads.
-- SetUnit is a no-op when the unit is unchanged, so this is cheap to call broadly.
function I.UpdateContainerIndicatorsUnit(unitButton)
    if not unitButton or not unitButton.indicators then return end

    local unit = unitButton.states and unitButton.states.displayedUnit
    if not unit then return end

    for _, indicator in next, unitButton.indicators do
        if type(indicator) == "table" and indicator.isContainer then
            I.UpdateContainerIndicatorUnit(indicator, unit)
        end
    end
end

function I.DestroyContainerIndicator(frame)
    if type(frame) ~= "table" or not frame.containerHandle then return end

    local handle = frame.containerHandle
    for i = #liveHandles, 1, -1 do
        if liveHandles[i] == handle then tremove(liveHandles, i) end
    end

    handle:Destroy()
    frame.containerHandle = nil
    frame.isContainer = nil
end
