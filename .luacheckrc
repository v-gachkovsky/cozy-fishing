-- luacheck for the addon: `luacheck .` from the repo root. The game runs Lua 5.1; everything else it has is
-- listed below, so a misspelled name shows up as an unknown global.
std = "lua51"
-- Translated texts are long lines, and frame methods often don't use their self.
max_line_length = false
self = false
ignore = { "432/self" } -- a script's self inside a method
exclude_files = { ".git/", "tests/" }

-- Globals the addon sets.
globals = {
    "CozyFishingDB", "CozyFishingCharDB",
    "SLASH_COZYFISHING1", "SLASH_COZYFISHING2", "SlashCmdList",
    "BINDING_HEADER_COZYFISHING", "CozyFishing_Swap",
    "UISpecialFrames",
}

-- The game's API and frames the addon reads.
read_globals = {
    -- Lua extras of the game
    "date", "time", "wipe", "tinsert", "strsplit", "issecretvalue",
    -- Namespaces
    "C_AddOns", "C_Container", "C_CVar", "C_Item", "C_Spell", "C_SpellBook", "C_Timer", "Settings", "SettingsPanel",
    -- Functions
    "ClearOverrideBindings", "EquipItemByName", "GetContainerItemID", "GetContainerNumSlots",
    "GetCurrentBindingSet", "GetItemInfo", "SaveBindings", "SetBinding", "CollapseSkillHeader", "ExpandSkillHeader", "GetProfessions",
    "GetProfessionInfo", "SkillFrame", "CreateFontFamily", "CreateFrame", "GetAddOnMetadata", "GetBindingAction",
    "GetBindingKey", "GetBindingText", "GetCursorPosition", "GetCVar", "GetInventoryItemID", "GetItemCount",
    "GetItemInfoInstant", "GetItemSubClassInfo", "GetLootSlotInfo", "GetLootSlotLink", "GetNumLootItems",
    "GetNumSkillLines", "GetRealZoneText", "GetSkillLineInfo", "GetSpellInfo", "GetTime", "GetWeaponEnchantInfo",
    "GetZoneText", "HideUIPanel", "InCombatLockdown", "InterfaceOptions_AddCategory",
    "InterfaceOptionsFrame_OpenToCategory", "IsAltKeyDown", "IsControlKeyDown", "IsFishingLoot", "IsMacClient",
    "IsMetaKeyDown", "IsMouseButtonDown", "IsPlayerSpell", "IsShiftKeyDown", "IsSpellKnown",
    "KeyBindingFrame_LoadUI", "MouseIsOver", "RegisterStateDriver", "ResetCursor", "SetCursor", "SetCVar",
    "SetOverrideBinding", "SetOverrideBindingClick", "ShowUIPanel", "UIDropDownMenu_AddButton",
    "UIDropDownMenu_CreateInfo", "UIDropDownMenu_Initialize", "UIDropDownMenu_SetText", "UIDropDownMenu_SetWidth",
    "UnitChannelInfo", "UnitExists", "UnitGUID", "UnitName", "GameTooltip_Hide",
    -- Frames, mixins and constants
    "BackdropTemplateMixin", "DEFAULT_CHAT_FRAME", "GameTooltip", "INVSLOT_MAINHAND", "INVSLOT_OFFHAND", "NUM_BAG_SLOTS", "KeyBindingFrame", "Minimap",
    "CANCEL", "NO", "STANDARD_TEXT_FONT", "UIParent", "UNKNOWN", "YES",
}
