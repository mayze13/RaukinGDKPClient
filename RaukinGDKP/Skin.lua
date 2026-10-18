-- RaukinGDKP: look & feel shared by RaukinGDKP and RaukinGDKPHost
--   * ElvUI / AddOnSkins: windows, buttons, edit boxes, check boxes, dropdowns and
--     scroll bars get their look when one of them is installed (/rgdkp skin turns it off)
--   * ElvUI media: window/panel backdrops and list rows use the Secondary texture
--     (General -> Media -> Secondary Texture), status bars use the Primary texture.
--     Both follow live changes made in /ec.
--   * Opacity: a small slider in every window sets how see-through the window
--     background is. One value for all windows of both addons (/rgdkp opacity 0-100).
--
-- Public API (global RaukinGDKPSkin). Every method is a safe no-op (or a plain fallback)
-- without ElvUI/AddOnSkins or when skinning is turned off:
--   Skin:Engine()                 -> "elvui" | "addonskins" | false
--   Skin:Window(frame, opts)      main windows (opacity slider, re-skins children on show)
--   Skin:Panel(frame)             sub panels (no slider)
--   Skin:Children(frame, depth)   skins known Blizzard-template children
--   Skin:StatusBar(bar)           ElvUI Primary texture, follows media changes
--   Skin:Row(frame)               flat list-row backdrop + pixel border; keeps later SetBackdropColor tints
--   Skin:EditBox(eb)              any edit box, also hand-made ones; backdrop kept BELOW the text
--   Skin:FontString(fs, size, outline)  ElvUI font on a font string
--   frame.raukinDropdownWidth     width passed to ElvUI's HandleDropDownBox (else ElvUI forces 155)
--   frame.raukinNoSkin            skip this frame in Children()

local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

local Skin = {}
RaukinGDKPSkin = Skin

local pairs, ipairs, type, pcall, select, math, tonumber, unpack = pairs, ipairs, type, pcall, select, math, tonumber, unpack
local hooksecurefunc = hooksecurefunc

local DEFAULT_OPACITY = 0.9
local MIN_OPACITY = 0.1

local FLAT_TEXTURE = "Interface\\ChatFrame\\ChatFrameBackground"
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local windows = {}                                     -- registered windows -> { r, g, b }
local sliders = {}                                     -- all opacity sliders (kept in sync)
local skinned = setmetatable({}, { __mode = "k" })
local rows = setmetatable({}, { __mode = "k" })        -- frames given Skin:Row
local editBoxes = setmetatable({}, { __mode = "k" })   -- edit boxes given Skin:EditBox
local statusBars = setmetatable({}, { __mode = "k" })  -- status bars given Skin:StatusBar

-- ---------------------------------------------------------------------------
-- Which skin engine is there?
-- ---------------------------------------------------------------------------

local engine          -- "elvui", "addonskins" or false
local E, S, AS
local InstallElvUIHooks

local function DetectEngine()
  if engine ~= nil then return engine end
  engine = false
  if RaukinGDKP:GetPref("skinDisabled", false) then return engine end

  if type(ElvUI) == "table" then
    local ok, e = pcall(function() return unpack(ElvUI) end)
    if ok and type(e) == "table" and e.GetModule then
      local okS, s = pcall(e.GetModule, e, "Skins", true)
      if okS and s then
        E, S, engine = e, s, "elvui"
        InstallElvUIHooks()
        return engine
      end
    end
  end

  if type(AddOnSkins) == "table" then
    local ok, as = pcall(function() return unpack(AddOnSkins) end)
    if ok and type(as) == "table" then
      AS, engine = as, "addonskins"
    end
  end
  return engine
end

function Skin:Engine()
  return DetectEngine()
end

local function Try(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok = pcall(fn, ...)
  return ok
end

local function Media(key, fallback)
  if E and E.media and E.media[key] then return E.media[key] end
  return fallback
end

local function PixelSize()
  return (E and E.mult) or 1
end

local function BorderColor()
  local c = E and E.media and E.media.bordercolor
  if type(c) == "table" and c[1] then return c[1], c[2], c[3] end
  return 0, 0, 0
end

-- ---------------------------------------------------------------------------
-- Single widgets
-- ---------------------------------------------------------------------------

local function TexturePath(texture)
  if not texture or not texture.GetTexture then return "" end
  local path = texture:GetTexture()
  return type(path) == "string" and path:lower() or ""
end

local function HasRegionTexture(frame, needle)
  for i = 1, select("#", frame:GetRegions()) do
    local region = select(i, frame:GetRegions())
    if region and region.GetObjectType and region:GetObjectType() == "Texture" then
      if TexturePath(region):find(needle, 1, true) then return true end
    end
  end
  return false
end

-- Hides the InputBoxTemplate border textures. Needed for anonymous edit boxes:
-- ElvUI's HandleEditBox only hides them by global name ($parentLeft/Middle/Right).
local function HideInputBoxTextures(eb)
  for i = 1, select("#", eb:GetRegions()) do
    local region = select(i, eb:GetRegions())
    if region and region.GetObjectType and region:GetObjectType() == "Texture" then
      if TexturePath(region):find("common-input-border", 1, true) then
        region:SetAlpha(0)
      end
    end
  end
end

-- ElvUI's S:HandleEditBox puts the opaque backdrop at the SAME frame level as the edit
-- box (Skins.lua:251). A child frame on the same level as its parent can be drawn on top
-- of it, so the backdrop covers the edit box text. This is made worse when the edit box
-- sits in a pooled AceGUI row that gets re-parented (SetParent recalculates levels).
-- Keep the backdrop exactly one level below the edit box, and the edit box at least two
-- levels above its parent so the backdrop never ties with the parent's own backdrop.
local function FixEditBoxLevel(eb)
  local backdrop = eb and eb.backdrop
  if type(backdrop) ~= "table" or not backdrop.SetFrameLevel then return end
  local parent = eb:GetParent()
  local parentLevel = parent and parent.GetFrameLevel and parent:GetFrameLevel() or 0
  if eb:GetFrameLevel() < parentLevel + 2 then
    eb:SetFrameLevel(parentLevel + 2)
  end
  local want = math.max(0, eb:GetFrameLevel() - 1)
  if backdrop:GetFrameLevel() ~= want then
    backdrop:SetFrameLevel(want)
  end
end

local function SkinEditBoxInternal(eb)
  if not eb or not DetectEngine() then return false end
  if editBoxes[eb] then
    FixEditBoxLevel(eb)
    return true
  end

  local handled
  if engine == "elvui" then
    HideInputBoxTextures(eb)
    -- Don't use S:HandleEditBox: it draws the backdrop on a separate child frame, which ends
    -- up above the edit box (and its text) in pooled list rows. A backdrop set on the edit box
    -- itself is always drawn under the box's own text, whatever the frame levels are.
    if eb.backdrop and eb.backdrop.Hide then eb.backdrop:Hide() end
    if eb.SetTemplate then
      handled = Try(eb.SetTemplate, eb, "Default")
    end
    if not handled and eb.SetBackdrop then
      eb:SetBackdrop({
        bgFile = Media("blankTex", WHITE_TEXTURE), edgeFile = Media("blankTex", WHITE_TEXTURE),
        tile = false, tileSize = 0, edgeSize = PixelSize(),
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
      })
      local bc = Media("backdropcolor")
      if type(bc) == "table" and bc[1] then
        eb:SetBackdropColor(bc[1], bc[2], bc[3], 1)
      else
        eb:SetBackdropColor(0.1, 0.1, 0.1, 1)
      end
      eb:SetBackdropBorderColor(BorderColor())
      handled = true
    end
  else
    handled = Try(AS.SkinEditBox, AS, eb)
    HideInputBoxTextures(eb)
  end

  editBoxes[eb] = true
  skinned[eb] = true
  return handled
end

local function DropdownWidth(widget)
  if widget.raukinDropdownWidth then return widget.raukinDropdownWidth end
  local obj = widget.obj
  if type(obj) == "table" and obj.raukinDropdownWidth then return obj.raukinDropdownWidth end
  return nil
end

local function SkinWidget(widget)
  if widget.raukinNoSkin then return end
  if skinned[widget] then
    if editBoxes[widget] then FixEditBoxLevel(widget) end
    return
  end
  local kind = widget.GetObjectType and widget:GetObjectType()
  local name = widget.GetName and widget:GetName()
  local handled = false

  if kind == "Button" then
    local normal = TexturePath(widget.GetNormalTexture and widget:GetNormalTexture())
    if normal:find("ui-panel-minimizebutton", 1, true) then
      if engine == "elvui" then handled = Try(S.HandleCloseButton, S, widget)
      else handled = Try(AS.SkinCloseButton, AS, widget) end
    elseif normal:find("ui-panel-button", 1, true) or normal:find("ui-dialogbox-button", 1, true) then
      if engine == "elvui" then handled = Try(S.HandleButton, S, widget, true)
      else handled = Try(AS.SkinButton, AS, widget, true) end
    end

  elseif kind == "CheckButton" then
    local normal = TexturePath(widget.GetNormalTexture and widget:GetNormalTexture())
    if normal:find("ui-checkbox", 1, true) then
      if engine == "elvui" then handled = Try(S.HandleCheckBox, S, widget)
      else handled = Try(AS.SkinCheckBox, AS, widget) end
    end

  elseif kind == "EditBox" then
    if HasRegionTexture(widget, "common-input-border") then
      return SkinEditBoxInternal(widget)
    end

  elseif kind == "Slider" then
    -- scroll bars of UIPanelScrollFrameTemplate (they need a name for their arrow buttons)
    local thumb = TexturePath(widget.GetThumbTexture and widget:GetThumbTexture())
    if name and thumb:find("ui-scrollbar-knob", 1, true) then
      -- ElvUI/AddOnSkins look the arrow buttons up by global name (name.."ScrollUpButton").
      -- Only let them do that when those buttons really belong to THIS scroll bar; if another
      -- addon created a frame with the same name, they would grab and move the wrong arrows.
      local up, down = _G[name .. "ScrollUpButton"], _G[name .. "ScrollDownButton"]
      local own = up and down and up.GetParent and up:GetParent() == widget and down:GetParent() == widget
      if own then
        if engine == "elvui" then handled = Try(S.HandleScrollBar, S, widget)
        else handled = Try(AS.SkinScrollBar, AS, widget) end
      else
        -- keep our own arrows glued to our own scroll bar
        for i = 1, select("#", widget:GetChildren()) do
          local child = select(i, widget:GetChildren())
          if child and child.GetObjectType and child:GetObjectType() == "Button" then
            local tex = TexturePath(child.GetNormalTexture and child:GetNormalTexture())
            if tex:find("scrollup", 1, true) then
              child:ClearAllPoints(); child:SetPoint("BOTTOM", widget, "TOP", 0, 0)
            elseif tex:find("scrolldown", 1, true) then
              child:ClearAllPoints(); child:SetPoint("TOP", widget, "BOTTOM", 0, 0)
            end
          end
        end
      end
    end

  elseif kind == "Frame" then
    -- UIDropDownMenuTemplate
    if name and _G[name .. "Button"] and _G[name .. "Middle"] then
      local width = DropdownWidth(widget)
      if engine == "elvui" then handled = Try(S.HandleDropDownBox, S, widget, width)
      else handled = Try(AS.SkinDropDownBox, AS, widget, width) end
    end
  end

  skinned[widget] = true
  return handled
end

-- Walks all children of a frame and skins what it recognises (safe to call often)
function Skin:Children(frame, depth)
  if not frame or not DetectEngine() then return end
  depth = depth or 0
  if depth > 8 then return end
  for i = 1, select("#", frame:GetChildren()) do
    local child = select(i, frame:GetChildren())
    if child and not child.raukinNoSkin then
      SkinWidget(child)
      self:Children(child, depth + 1)
    end
  end
end

-- Any edit box, including hand-made ones (textures already hidden by the caller)
function Skin:EditBox(eb)
  if not eb then return false end
  return SkinEditBoxInternal(eb)
end

-- A panel (no opacity slider), e.g. the trade helper
function Skin:Panel(frame)
  if not frame or not DetectEngine() then return end
  if not skinned[frame] then
    skinned[frame] = true
    if engine == "elvui" then
      Try(frame.StripTextures, frame)
      Try(frame.SetTemplate, frame, "Transparent", true)   -- true = Secondary (gloss) texture
    else
      Try(AS.SkinFrame, AS, frame)
    end
  end
  self:Children(frame)
end

-- Status bar: ElvUI Primary texture, registered so it follows /ec media changes
function Skin:StatusBar(bar)
  if not bar or not bar.SetStatusBarTexture then return end
  if DetectEngine() ~= "elvui" then return end
  local tex = Media("normTex")
  if tex then bar:SetStatusBarTexture(tex) end
  if not statusBars[bar] then
    statusBars[bar] = true
    if type(E.RegisterStatusBar) == "function" then
      Try(E.RegisterStatusBar, E, bar)
    end
  end
end

-- List row: flat backdrop (ElvUI Secondary texture) + pixel border in ElvUI's border colour.
-- The backdrop colour the row already had is kept, and later SetBackdropColor calls
-- (status tints) are never touched, not even on media updates.
local function ApplyRowBackdrop(frame)
  local r, g, b, a
  if frame.GetBackdropColor then
    local ok, cr, cg, cb, ca = pcall(frame.GetBackdropColor, frame)
    if ok and cr then r, g, b, a = cr, cg, cb, ca end
  end

  local px = PixelSize()
  local isElv = DetectEngine() == "elvui"
  frame:SetBackdrop({
    bgFile = isElv and Media("glossTex", FLAT_TEXTURE) or FLAT_TEXTURE,
    edgeFile = isElv and Media("blankTex", WHITE_TEXTURE) or WHITE_TEXTURE,
    tile = false, tileSize = 0, edgeSize = px,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })

  if r then
    frame:SetBackdropColor(r, g, b, a)
  else
    frame:SetBackdropColor(0, 0, 0, 0.3)
  end
  if isElv then
    frame:SetBackdropBorderColor(BorderColor())
  else
    frame:SetBackdropBorderColor(0, 0, 0, 1)
  end
end

function Skin:Row(frame)
  if not frame or not frame.SetBackdrop then return end
  ApplyRowBackdrop(frame)
  rows[frame] = true
end

-- ElvUI font on a font string (falls back to keeping the current font)
function Skin:FontString(fs, size, outline)
  if not fs or DetectEngine() ~= "elvui" then return end
  if fs.FontTemplate then
    Try(fs.FontTemplate, fs, nil, size, outline)
  elseif E.media and E.media.normFont then
    fs:SetFont(E.media.normFont, size or 12, outline)
  end
end

-- ---------------------------------------------------------------------------
-- Opacity
-- ---------------------------------------------------------------------------

function Skin:GetOpacity()
  local value = tonumber(RaukinGDKP:GetPref("windowOpacity", DEFAULT_OPACITY)) or DEFAULT_OPACITY
  return math.max(MIN_OPACITY, math.min(1, value))
end

local function ApplyOpacity(frame, color)
  if not color then return end
  local alpha = Skin:GetOpacity()
  local target = (type(frame.backdrop) == "table" and frame.backdrop) or frame
  if target.SetBackdropColor then
    target:SetBackdropColor(color[1], color[2], color[3], alpha)
  end
end

function Skin:SetOpacity(value)
  value = math.max(MIN_OPACITY, math.min(1, tonumber(value) or DEFAULT_OPACITY))
  RaukinGDKP:SetPref("windowOpacity", value)
  for frame, color in pairs(windows) do ApplyOpacity(frame, color) end
  for _, slider in ipairs(sliders) do
    if math.abs(slider:GetValue() - value) > 0.001 then
      slider.syncing = true
      slider:SetValue(value)
      slider.syncing = nil
    end
  end
end

-- ---------------------------------------------------------------------------
-- ElvUI media updates (/ec -> General -> Media)
-- ---------------------------------------------------------------------------
-- E:UpdateFrameTemplates re-runs SetTemplate on every frame in E.frames (our windows and
-- panels too), which resets their backdrop alpha; E:UpdateBackdropColors does the same.
-- Re-apply the opacity afterwards, and refresh our rows (they are not in E.frames, so
-- their tints survive) and edit box levels.

local function RefreshWindowsAfterElvUI()
  local fade = E and E.media and E.media.backdropfadecolor
  for frame, color in pairs(windows) do
    local target = (type(frame.backdrop) == "table" and frame.backdrop) or frame
    if type(fade) == "table" and fade[1] and target.template == "Transparent" then
      color[1], color[2], color[3] = fade[1], fade[2], fade[3]
    end
    ApplyOpacity(frame, color)
  end
end

local function RefreshRows()
  for frame in pairs(rows) do ApplyRowBackdrop(frame) end
  for eb in pairs(editBoxes) do FixEditBoxLevel(eb) end
end

local function RefreshRowBorders()
  local r, g, b = BorderColor()
  for frame in pairs(rows) do frame:SetBackdropBorderColor(r, g, b) end
end

local hooksInstalled
InstallElvUIHooks = function()
  if hooksInstalled or not E then return end
  hooksInstalled = true
  if type(E.UpdateFrameTemplates) == "function" then
    hooksecurefunc(E, "UpdateFrameTemplates", function()
      RefreshWindowsAfterElvUI()
      RefreshRows()
    end)
  end
  if type(E.UpdateBackdropColors) == "function" then
    hooksecurefunc(E, "UpdateBackdropColors", RefreshWindowsAfterElvUI)
  end
  if type(E.UpdateBorderColors) == "function" then
    hooksecurefunc(E, "UpdateBorderColors", RefreshRowBorders)
  end
end

local function CreateOpacitySlider(frame, point)
  local slider = CreateFrame("Slider", nil, frame)
  slider.raukinNoSkin = (DetectEngine() ~= "elvui")   -- ElvUI gets its own slider look below
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(64, 14)
  slider:SetHitRectInsets(0, 0, -6, -6)
  slider:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
  })
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetMinMaxValues(MIN_OPACITY, 1)
  slider:SetValueStep(0.05)
  slider:SetValue(Skin:GetOpacity())
  slider:SetPoint(point[1], frame, point[1], point[2], point[3])
  slider:SetFrameLevel(frame:GetFrameLevel() + 10)

  slider:SetScript("OnValueChanged", function(self, value)
    if self.syncing then return end
    Skin:SetOpacity(value)
    if GameTooltip:GetOwner() == self then
      GameTooltip:SetText(string.format("Window opacity: %d%%", math.floor(value * 100 + 0.5)))
    end
  end)
  slider:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(string.format("Window opacity: %d%%", math.floor(self:GetValue() * 100 + 0.5)))
    GameTooltip:AddLine("Drag left: more see-through. Drag right: solid.", 1, 1, 1, true)
    GameTooltip:AddLine("Applies to all RaukinGDKP windows.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
  slider:EnableMouseWheel(true)
  slider:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(self:GetValue() + delta * 0.05)
  end)

  if DetectEngine() == "elvui" then
    Try(S.HandleSliderFrame, S, slider)
  end
  skinned[slider] = true
  sliders[#sliders + 1] = slider
  return slider
end

-- ---------------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------------

-- Same background as the bidding window (GUI.lua). The Blizzard dialog background the
-- host windows used is see-through by itself, so with the same opacity they looked lighter.
local STANDARD_BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 8, right = 8, top = 8, bottom = 8 },
}

-- opts.slider = false: no opacity slider
-- opts.sliderPoint = { "TOPLEFT", x, y } where the slider goes (default top left)
-- opts.strip = true: also remove the frame's own textures with ElvUI (AceGUI title bars)
-- opts.keepBackdrop = true: without a skin engine, keep the frame's own backdrop
-- The X of a window: always on top of everything else in the window, and closes the
-- window directly (HideParentPanel goes through Blizzard's panel manager, which does not
-- always cooperate, e.g. in combat). Runs before skinning, while the Blizzard texture is there.
local function FixCloseButtons(frame)
  for i = 1, select("#", frame:GetChildren()) do
    local child = select(i, frame:GetChildren())
    if child and not child.raukinCloseFixed and child.GetObjectType and child:GetObjectType() == "Button" then
      local normal = TexturePath(child.GetNormalTexture and child:GetNormalTexture())
      if normal:find("ui-panel-minimizebutton", 1, true) then
        child.raukinCloseFixed = true
        child:SetFrameLevel(frame:GetFrameLevel() + 20)
        child:SetScript("OnClick", function() frame:Hide() end)
      end
    end
  end
end

function Skin:Window(frame, opts)
  if not frame then return end
  opts = opts or {}

  if not windows[frame] then
    FixCloseButtons(frame)
    if not DetectEngine() and opts.keepBackdrop ~= true and frame.SetBackdrop then
      -- no ElvUI/AddOnSkins: same dark background for every window (black, opacity from the slider)
      frame:SetBackdrop(STANDARD_BACKDROP)
      frame:SetBackdropColor(0, 0, 0, 1)
    end
    if DetectEngine() then
      if engine == "elvui" then
        if opts.strip then Try(frame.StripTextures, frame) end
        -- "Transparent" colours + glossTex = true: backdrop uses ElvUI's Secondary texture
        -- (Toolkit.lua SetTemplate: bgFile = glossTex and E.media.glossTex or E.media.blankTex)
        Try(frame.SetTemplate, frame, "Transparent", true)
      else
        Try(AS.SkinFrame, AS, frame)
      end
    end

    local target = (type(frame.backdrop) == "table" and frame.backdrop) or frame
    local r, g, b = 0, 0, 0
    if target.GetBackdropColor then
      local cr, cg, cb = target:GetBackdropColor()
      if cr then r, g, b = cr, cg, cb end
    end
    windows[frame] = { r, g, b }

    if opts.slider ~= false then
      frame.raukinOpacitySlider = CreateOpacitySlider(frame, opts.sliderPoint or { "TOPLEFT", 16, -12 })
    end

    -- re-skin children whenever the window opens (rows are created later)
    frame:HookScript("OnShow", function(self)
      ApplyOpacity(self, windows[self])
      Skin:Children(self)
    end)
  end

  ApplyOpacity(frame, windows[frame])
  self:Children(frame)
end

-- ---------------------------------------------------------------------------
-- Slash helpers (/rgdkp skin, /rgdkp opacity 0-100)
-- ---------------------------------------------------------------------------

function Skin:ToggleSkin()
  local disabled = not RaukinGDKP:GetPref("skinDisabled", false)
  RaukinGDKP:SetPref("skinDisabled", disabled)
  RaukinGDKP:Info(disabled and "ElvUI/AddOnSkins look turned OFF - type /reload." or "ElvUI/AddOnSkins look turned ON - type /reload.")
end

function Skin:SetSkinEnabled(enabled)
  RaukinGDKP:SetPref("skinDisabled", not enabled)
end

function Skin:IsSkinEnabled()
  return not RaukinGDKP:GetPref("skinDisabled", false)
end
