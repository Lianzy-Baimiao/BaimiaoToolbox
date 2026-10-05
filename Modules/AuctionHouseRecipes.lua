-- Read-only tracked-recipe adapter. Never alters profession selections or crafts.
local _,ns=...
local T = ns.L
local A=ns.AuctionHouse
local R={};A.Recipes=R
local cached,selection
local function read(fn,...)
    if type(fn)~="function"then return nil end
    local ok,value=pcall(fn,...);if ok then return value end
end
function R.Invalidate()cached=nil end
function R.Quality()return A.Integer(A.DB().recipeQuality,1,5) or 5 end
function R.Crafts()return A.Integer(A.DB().recipeCrafts,1,1000) or 1 end
function R.Configure(quality,crafts,key)
    if A.IsPurchasing() or InCombatLockdown()then return false end
    if quality~=nil then
        quality=A.Integer(quality,1,5);if not quality then return false end
        A.DB().recipeQuality=quality
    end
    if crafts~=nil then
        crafts=A.Integer(crafts,1,1000);if not crafts then return false end
        A.DB().recipeCrafts=crafts
    end
    if key~=nil then selection=key~="all" and key or nil end
    R.Invalidate();A.Stop(T["配方条件已更新，点击开始补货查询材料价格"])
    return true
end
-- 12.x uses a separate two-tier atlas family. A reagent tier is not a
-- five-star equipment rank; retain the client's icon instead of inventing stars.
local function reagentQuality(id)
    local api=C_TradeSkillUI
    if not api then return nil end
    local info=read(api.GetItemReagentQualityInfo,id)
    local rank=type(info)=="table" and A.Integer(info.quality,1,5)
    return rank or A.Integer(read(api.GetItemReagentQualityByItemInfo,id),1,5)
end
function R.QualityLabel(entry)
    if not entry.quality then return "" end
    local info=C_TradeSkillUI and read(C_TradeSkillUI.GetItemReagentQualityInfo,entry.itemID)
    local atlas=type(info)=="table" and info.icon
    local icon=type(atlas)=="string" and atlas:match("^[%w_%-]+$") and ("|A:"..atlas..":14:14|a ") or ""
    return " · "..icon..(entry.highestQuality and T["最高"] or (entry.quality..T["阶"]))
end
-- Quality comes from reagent metadata, NEVER item rarity or the array position.
local function choose(slot,quality)
    local reagents=slot.reagents
    if type(reagents)~="table" or #reagents==0 then return nil,T["材料信息未就绪"],true end
    if #reagents==1 then
        local id=A.ItemID(reagents[1].itemID)
        if not id then return nil,T["货币材料需自行准备"] end
        return reagents[1],nil,false,reagentQuality(id)
    end
    local byQuality,maxQuality={},0
    for _,reagent in ipairs(reagents)do
        local id=A.ItemID(reagent.itemID)
        if not id then return nil,T["材料选项需自行确认"] end
        local rank=reagentQuality(id)
        if not rank then
            -- Only unknown item data is loadable. Known unranked alternatives
            -- are choices (not quality variants); do not silently pick one.
            local name=read(C_Item and C_Item.GetItemInfo or GetItemInfo,id)
            if not name then A.ItemName(id);return nil,T["正在加载材料品质"],true end
            return nil,T["存在非品质材料选项，需自行确认"]
        end
        if byQuality[rank] and byQuality[rank].itemID~=id then return nil,T["同品质有多个选项，需自行确认"] end
        byQuality[rank]=reagent;maxQuality=math.max(maxQuality,rank)
    end
    local wanted=math.min(quality,maxQuality)
    if not byQuality[wanted]then return nil,T["没有所选品质，需自行确认"] end
    return byQuality[wanted],nil,false,wanted,wanted==maxQuality
end
local function boundOnPickup(id)
    local fn=C_Item and C_Item.GetItemInfo or GetItemInfo
    if type(fn)~="function"then return false end
    local info={pcall(fn,id)}
    -- GetItemInfo's 14th return is bindType; quality/rarity is not binding.
    return info[1] and info[15]==1
end
function R.Plan()
    if cached then return cached end
    local plan={name=T["追踪配方"],items={},recipes={},warnings={},recipeCount=0}
    cached=plan
    local api=C_TradeSkillUI
    if not api or type(api.GetRecipesTracked)~="function" or type(api.GetRecipeSchematic)~="function"then
        plan.blocked=T["当前客户端的配方追踪接口不可用"];return plan
    end
    local function warn(text)plan.warnings[#plan.warnings+1]=text end
    local seen={}
    for _,recraft in ipairs({false,true})do
        local ids=read(api.GetRecipesTracked,recraft)
        if type(ids)~="table"then plan.blocked=T["配方数据未就绪，请打开一次专业面板"];ids={}end
        for _,id in ipairs(ids)do
            id=A.ItemID(id)
            local key=id and ((recraft and "r:" or "c:")..id)
            if key and not seen[key]then
                seen[key]=true
                local schematic=read(api.GetRecipeSchematic,id,recraft)
                local name=schematic and schematic.name or (T["配方 #"]..id)
                plan.recipes[#plan.recipes+1]={key=key,id=id,recraft=recraft,schematic=schematic,name=(recraft and T["再造 · "] or "")..name}
            end
        end
    end
    if selection and not seen[selection]then selection=nil end
    plan.selection=selection or "all";plan.selectionName=T["全部追踪配方（"]..#plan.recipes.."）"
    local merged={};local quality,crafts=R.Quality(),R.Crafts()
    for _,recipe in ipairs(plan.recipes)do
        if not selection or recipe.key==selection then
            if selection then plan.selectionName=recipe.name end
            plan.recipeCount=plan.recipeCount+1
            local schematic=recipe.schematic
            if type(schematic)~="table" or type(schematic.reagentSlotSchematics)~="table"then
                plan.blocked=T["配方信息未就绪，请打开一次专业面板"]
            else
                for _,slot in ipairs(schematic.reagentSlotSchematics)do
                    local basic=Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
                    if not basic then plan.blocked=T["客户端材料类型信息不可用"];break end
                    if slot.required and slot.reagentType==basic then
                        local reagent,why,pending,rank,highest=choose(slot,quality)
                        if reagent and boundOnPickup(reagent.itemID)then
                            warn(recipe.name.."："..A.ItemName(reagent.itemID)..T["是绑定材料，不从拍卖行采购"])
                        elseif reagent then
                            local id=reagent.itemID
                            local quantity=slot.quantityRequired
                            for _,variable in ipairs(slot.variableQuantities or {})do
                                if variable.reagent and variable.reagent.itemID==id then quantity=variable.quantity;break end
                            end
                            quantity=A.Integer(quantity,1,A.MAX_QUANTITY)
                            if not quantity or quantity*crafts>A.MAX_QUANTITY then
                                plan.blocked=T["材料数量超出支持范围，请减少制作份数"]
                            else
                                local row=merged[id]
                                if not row then
                                    row={itemID=id,target=0,maxPrice=0,enabled=true,quality=rank,highestQuality=highest,includeBank=true}
                                    merged[id]=row;plan.items[#plan.items+1]=row
                                end
                                row.target=row.target+quantity*crafts
                                if row.target>A.MAX_QUANTITY or #plan.items>A.MAX_ROWS then plan.blocked=T["合并后的材料数量超出上限"] end
                            end
                        else
                            warn(recipe.name.."："..why)
                            if pending then plan.blocked=why..T["，加载完成后可补货"] end
                        end
                    elseif slot.required then
                        warn(recipe.name.."："..((slot.slotInfo and slot.slotInfo.slotText) or T["特殊必需材料"])..T["需自行准备"])
                    end
                end
            end
        end
    end
    if #plan.recipes==0 and not plan.blocked then plan.blocked=T["先在专业面板勾选「追踪配方」，这里会自动显示材料"] end
    if #plan.items==0 and not plan.blocked then plan.blocked=T["没有可补货的基础材料，请检查配方材料要求"] end
    return plan
end
function A.ActivePlan()
    if A.purchaseSource=="recipes"then return R.Plan()end
    return A.Plan()
end
function A.SetPurchaseSource(source)
    if A.IsPurchasing()then return false end
    source=source=="recipes" and "recipes" or "manual"
    if A.purchaseSource~=source then A.Stop(T["点击开始补货查询材料价格"]);A.purchaseSource=source end
    return true
end
