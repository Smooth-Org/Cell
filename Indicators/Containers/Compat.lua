local _, Cell = ...
---@type CellFuncs
local F = Cell.funcs
---@type PixelPerfectFuncs
local P = Cell.pixelPerfectFuncs

-- ============================================================================
-- Compatibility shim for the Blizzard aura container layer
-- ============================================================================
-- The container layer in this folder is adapted from DandersFrames and expects that
-- addon's `DF` namespace. This file provides that namespace, backed by Cell's own
-- equivalents where one exists and safely stubbed where it does not.
--
-- PRIVATE USE ONLY. This is a personal fork; none of this is redistributable.
--
-- The stubs are deliberately permissive: an unimplemented styling hook should make a
-- visual degrade, never error. The container lifecycle itself is what has to work.

Cell.DF = Cell.DF or {}
local DF = Cell.DF

-- ============================================================================
-- debug logging
-- ============================================================================
-- The container layer logs heavily during builds. Routed to Cell's own debug channel
-- so it is silent unless explicitly enabled.
local DEBUG = false

function DF:Debug(...)
    if not DEBUG then return end
    if F and F.Debug then F.Debug("[Container]", ...) end
end

-- Warnings are NOT silenced. The container layer reports real failures through this,
-- including "AddAuraGroup failed", which is the difference between a container that has
-- nothing to show and one that was never given a filter to show it with. Each distinct
-- message is surfaced once so a per-button failure cannot flood.
local warned = {}

function DF:DebugWarn(tag, fmt, ...)
    local msg
    if type(fmt) ~= "string" then
        msg = tostring(fmt)
    elseif select("#", ...) == 0 then
        msg = fmt
    else
        local ok, formatted = pcall(string.format, fmt, ...)
        msg = ok and formatted or fmt
    end

    local key = tostring(tag) .. "|" .. tostring(msg)
    if warned[key] then return end
    warned[key] = true

    geterrorhandler()("Cell container WARN [" .. tostring(tag) .. "] " .. tostring(msg))
end

function DF:DebugActive()
    return DEBUG
end

DF.DebugActive = DF.DebugActive

function DF:Say(...) end

-- Structured debug output objects. Every method chains, so an unused report costs a
-- few table lookups and produces nothing.
local OutProto = {}
OutProto.__index = OutProto
function OutProto:Section() return self end
function OutProto:Field() return self end
function OutProto:Line() return self end
function OutProto:Siblings() return self end

function DF:Out()
    return setmetatable({}, OutProto)
end

DF.OUT = DF.OUT or {}

-- ============================================================================
-- settings
-- ============================================================================
-- Only two keys are actually read by the container layer: pixelPerfect and
-- dispelColors. Both are given Cell-appropriate defaults rather than being wired to
-- Cell's saved variables, so container behaviour stays independent of layout config.
local containerDB = {
    pixelPerfect = true,
    dispelColors = nil, -- nil = use the game's own dispel palette
}

function DF:GetDB()
    return containerDB
end

DF.db = containerDB

function DF:GetFrameDB()
    return containerDB
end

-- ============================================================================
-- pixel perfect
-- ============================================================================
function DF:PixelPerfect(v)
    if type(v) ~= "number" then return v end
    if P and P.Scale then return P.Scale(v) end
    return v
end

function DF:PixelPerfectThickness(v)
    return DF:PixelPerfect(v)
end

function DF:GetPixelScale()
    if P and P.GetPixelScale then return P.GetPixelScale() end
    return UIParent and UIParent:GetEffectiveScale() or 1
end

DF.GetPixelScale = DF.GetPixelScale

-- ============================================================================
-- safe setters
-- ============================================================================
-- Aura buttons refuse tainted writes while auras are secret, so every write into that
-- subtree has to tolerate refusal rather than propagate an error.
function DF:SafeSetTexture(tex, path)
    if not tex or not path then return end
    pcall(function() tex:SetTexture(path) end)
end

function DF:SafeSetStatusBarTexture(bar, path)
    if not bar or not path then return end
    pcall(function() bar:SetStatusBarTexture(path) end)
end

function DF:SafeSetFont(fs, font, size, outline)
    if not fs or not font then return end
    pcall(function() fs:SetFont(font, size or 10, outline or "NONE") end)
end

DF.SafeSetStatusBarTexture = DF.SafeSetStatusBarTexture
DF.SafeSetFont = DF.SafeSetFont

-- ============================================================================
-- colors
-- ============================================================================
function DF:GetClassColor(class)
    if F and F.GetClassColor then return F.GetClassColor(class) end
    return 1, 1, 1
end

DF.GetClassColor = DF.GetClassColor

DF.DispelDefaultColors = {
    Magic   = {0.2, 0.6, 1.0},
    Curse   = {0.6, 0.0, 1.0},
    Disease = {0.6, 0.4, 0.0},
    Poison  = {0.0, 0.6, 0.0},
    Bleed   = {0.8, 0.0, 0.0},
    none    = {0.8, 0.8, 0.8},
}

function DF:GetDispelColorMap()
    return DF.DispelDefaultColors
end

function DF:GetGameDispelTextMap()
    return DF._gameDispelTextMap or {}
end

DF.GetGameDispelTextMap = DF.GetGameDispelTextMap

function DF:GetGameDispelPalette()
    return DF._gameDispelPalette or DF.DispelDefaultColors
end

DF.GetGameDispelPalette = DF.GetGameDispelPalette
DF._gameDispelTextMap = {}
DF._gameDispelPalette = DF.DispelDefaultColors

function DF:InvalidateDispelColorCurve() end
function DF:ResolveDispelTextureStyle() return nil end

DF.dispelCurveGen = 0

-- ============================================================================
-- misc hooks
-- ============================================================================
-- Duration text refresh cadence. The native binding forwards this to Blizzard, so a
-- sane constant is enough; Cell has no account-wide equivalent to wire it to.
function DF:GetAuraDurationUpdateInterval()
    return 0.1
end

DF.GetAuraDurationUpdateInterval = DF.GetAuraDurationUpdateInterval

function DF:GetBorderTexturePath()
    return "Interface\\Buttons\\WHITE8X8"
end

DF.GetBorderTexturePath = DF.GetBorderTexturePath

function DF:UpdateBorderAppearance() end
function DF:ApplyBarFillOrientation() end

function DF:GetUnitRole(unit)
    if not unit then return "NONE" end
    return UnitGroupRolesAssigned(unit) or "NONE"
end

function DF:MemTestDisabled()
    return true
end

-- ============================================================================
-- test mode
-- ============================================================================
-- Cell has its own preview system, so the container layer's test path stays inert.
DF.testMode = false
DF.TestData = {}

function DF:GetTestUnitData() return nil end
function DF:GetTestDebuffDispelType() return nil end

DF.GetTestUnitData = DF.GetTestUnitData

-- ============================================================================
-- optional subsystems
-- ============================================================================
-- Expiration and GUI are DandersFrames features Cell does not have. The container
-- layer guards its calls into them, so leaving them absent disables those visuals
-- without affecting aura rendering.
DF.Expiration = nil
DF.GUI = nil
