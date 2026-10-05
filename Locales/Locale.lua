-- Locales load before Core.lua. English is the complete fallback catalog;
-- the selected locale overlays it. No SavedVariables or global UI hooks needed.
local _, ns = ...
local client = GetLocale()
ns.locale = (client == "zhCN" or client == "zhTW" or client == "koKR") and client or "enUS"
ns.L = setmetatable({}, { __index = function(_, key) return key end })
function ns.GetLocaleTable(locale)
    if locale == "enUS" or locale == ns.locale then return ns.L end
end
