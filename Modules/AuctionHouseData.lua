-- Pure validation and price planning. No API calls or purchase side effects.
local _, ns = ...
local T = ns.L
local A = { MAX_ROWS=100, MAX_PLANS=12, MAX_QUANTITY=100000, MAX_MONEY=99999999999 }
ns.AuctionHouse = A
A.defaults = { showPanel=true, quickSearch=true, restock=true, selectedPlan=1, sessionBudget=0,
    favorites={}, plans={}, recipeQuality=5, recipeCrafts=1,
}
-- Keep mutable arrays out of recursive defaults: deleted entries must stay deleted.
-- Item IDs verified against the installed 12.x reference data; names/icons come
-- from the client. Presets are a catalog, not rows forcibly merged into favorites.
A.catalog={}
local function preset(group,ids)
    for _,id in ipairs(ids)do A.catalog[#A.catalog+1]={itemID=id,group=group,preset=true}end
end
preset("合剂",{241326,241324,241320,241322})
preset("药水",{271884,241298,241300,241308,241292,241288,241296,241286,241302})
preset("食物",{255845,242273,255847,255848})
preset("武器油",{243734,243736,237369,237371})
preset("宝石",{240905,240909,240907,240889,240893,240891,240913,240915,240917,240898,240899,240901,240982})
preset("附魔",{244005,243949,243979,243990,244020,243962,243953,243982,244009,243977,244641,240155,240133,
    243984,244010,244012,243954,243970,243972,244001,244030,244029,243987,244015,244017,243959,243957})
preset("公函",{245782,245784,245786,245788,245790,245792,245815,245817,245819,245821,245823,245825,245827})
preset("常用",{272195,269586,248137,132514,219905,259085})
preset("特殊",{188152,204370,124640,225592,191350})
A.categoryOrder={"全部","收藏","合剂","药水","食物","武器油","宝石","附魔","公函","常用","特殊"}
-- Category IDs are persisted in old favorites. Translate at presentation only;
-- never run arbitrary user group names, searches or plan names through L.
local categoryIDs={}
for _,id in ipairs(A.categoryOrder)do categoryIDs[id]=true end
function A.CategoryName(id)
    return categoryIDs[id] and T[id] or id
end
function A.CategoryID(value)
    if categoryIDs[value] then return value end
    for _,id in ipairs(A.categoryOrder)do if T[id]==value then return id end end
    return value
end
-- Concise effects verified against localized item tooltips (no fixed stat amounts).
-- Lookup by ID so favorites retain details without migrating saved variables.
local attributes={
    [241326]="爆",[241324]="急",[241320]="全",[241322]="精",
    [271884]="瞬回治疗",[241298]="持续治疗",[241300]="回蓝",[241308]="主属性",
    [241292]="主属性·风险",[241288]="最高副属性",[241296]="伤害",[241286]="护盾",[241302]="隐形",
    [240905]="爆·急",[240909]="爆·全",[240907]="爆·精",[240889]="急·爆",[240893]="急·全",[240891]="急·精",
    [240913]="全·爆",[240915]="全·急",[240917]="全·精",[240898]="精·爆",[240899]="精·急",[240901]="精·全",[240982]="主属性",
    [244005]="头·闪避",[243949]="头·吸血",[243979]="头·移速",[243990]="肩·闪避",[244020]="肩·吸血",[243962]="肩·移速",
    [243953]="鞋·闪避/耐",[243982]="鞋·吸血/耐",[244009]="鞋·移速/耐",[243977]="胸·主属性",
    [244641]="腿·力敏/耐",[240155]="腿·智/法力",[240133]="腿·智/耐",
    [243984]="戒·爆",[244010]="戒·急",[244012]="戒·全",[243954]="戒·精",
    [243970]="武器·爆",[243972]="武器·急",[244001]="武器·全",[244030]="武器·精",[244029]="武器·主属",
    [243987]="戒·爆",[244015]="戒·急",[244017]="戒·全",[243959]="戒·精",[243957]="戒·爆效",
    [245782]="急·全",[245784]="急·精",[245786]="爆·急",[245788]="全·精",[245790]="爆·精",[245792]="爆·全",
    [245815]="奇思",[245817]="充裕",[245819]="产能",[245821]="制作速度",[245823]="精细",[245825]="感知",[245827]="熟练",
}
function A.Attributes(entry)return entry.itemID and attributes[entry.itemID] or nil end
function A.SearchKey(entry)return entry.itemID and ("id:"..entry.itemID) or ("q:"..(entry.query or ""))end
function A.SearchEntries(group)
    local result,seen={},{}
    local function add(entry)
        local key=A.SearchKey(entry)
        if not seen[key]then result[#result+1]=entry;seen[key]=true end
    end
    if group=="收藏"then return A.DB().favorites end
    for _,entry in ipairs(A.catalog)do if group=="全部" or group==entry.group then add(entry)end end
    for _,entry in ipairs(A.DB().favorites)do if group=="全部" or group==entry.group then add(entry)end end
    return result
end
function A.Categories()
    local out,seen={},{}
    for _,group in ipairs(A.categoryOrder)do out[#out+1]=group;seen[group]=true end
    for _,entry in ipairs(A.DB().favorites)do
        local group=entry.group or "常用"
        if not seen[group]then out[#out+1]=group;seen[group]=true end
    end
    return out
end
function A.Number(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value)~="number" or value~=value or value==math.huge or value==-math.huge then return nil end
    return value
end
function A.Integer(value,minimum,maximum)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value)~="number" and type(value)~="string" then return nil end
    local n=A.Number(tonumber(value))
    if not n or n~=math.floor(n) or n<(minimum or 0) or n>(maximum or A.MAX_MONEY) then return nil end
    return n
end
function A.Clean(value,limit)
    if type(value)~="string" then return "" end
    value=value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("[|%c]",""):match("^%s*(.-)%s*$")
    local out,size={},0
    for character in value:gmatch("[%z\1-\127\194-\244][\128-\191]*")do
        if size+#character>(limit or 80)then break end
        out[#out+1]=character;size=size+#character
    end
    return table.concat(out)
end
function A.ItemID(value)
    if type(value)=="number" then return A.Integer(value,1,2147483647) end
    if type(value)~="string" then return nil end
    local id=value:match("|Hitem:(%d+):") or value:match("^item:(%d+)") or value:match("^%s*(%d+)%s*$")
    return A.Integer(id,1,2147483647)
end
-- Gold input is decimal, not a Lua expression; round to copper, reject negatives/NaN.
function A.Gold(value)
    if type(value)~="string" or not value:match("^%d+%.?%d?%d?%d?%d?$") then return nil end
    local n=A.Number(tonumber(value))
    if not n or n<0 or n*10000>A.MAX_MONEY then return nil end
    return math.floor(n*10000+0.5)
end
function A.Money(copper)
    if not A.Number(copper) then return T["未知"] end
    return string.format(copper%100==0 and T["%.2f金"] or T["%.4f金"],copper/10000)
end
function A.Need(target,owned,pending)
    target=A.Integer(target,1,A.MAX_QUANTITY)
    owned=A.Integer(owned,0,A.MAX_QUANTITY*100)
    pending=A.Integer(pending,0,A.MAX_QUANTITY*100)
    if not target or not owned or not pending then return nil end
    return math.max(0,target-owned-pending)
end
-- Evaluate every required price tier, never use the cheapest/average price as a cap.
-- Do not silently buy a partial quantity: the user reviews one complete quote.
function A.PricePlan(tiers,quantity,cap)
    if not A.Integer(quantity,1,A.MAX_QUANTITY) or not A.Integer(cap,0) then return nil,T["限价无效"] end
    local remaining,total,highest=quantity,0,0
    local sorted={}
    for _,tier in ipairs(tiers) do
        local price=A.Integer(tier.unitPrice,1)
        local count=A.Integer(tier.quantity,0,A.MAX_QUANTITY*100)
        if not price or not count then return nil,T["报价数据未知"] end
        sorted[#sorted+1]={unitPrice=price,quantity=count}
    end
    table.sort(sorted,function(a,b)return a.unitPrice<b.unitPrice end)
    for _,tier in ipairs(sorted) do
        if remaining==0 then break end
        if tier.quantity>0 then
            if cap>0 and tier.unitPrice>cap then return nil,T["超出单价上限"] end
            local take=math.min(remaining,tier.quantity)
            total=total+take*tier.unitPrice;highest=tier.unitPrice;remaining=remaining-take
            if total>A.MAX_MONEY then return nil,T["总价超出安全范围"] end
        end
    end
    if remaining>0 then return nil,T["在售数量不足"] end
    return {quantity=quantity,total=total,highest=highest}
end
function A.DB()
    local d=ns.GetDB("auctionhouse",A.defaults)
    if type(d.plans)~="table" or #d.plans==0 then d.plans={{name=T["日常补货"],items={}}} end
    if type(d.favorites)~="table" then d.favorites={} end
    -- Existing favorites, including the first prototype's eight entries, survive.
    d.favoritesSeeded=true
    d.selectedPlan=math.min(#d.plans,A.Integer(d.selectedPlan,1,A.MAX_PLANS) or 1)
    return d
end
function A.Plan() return A.DB().plans[A.DB().selectedPlan] end
