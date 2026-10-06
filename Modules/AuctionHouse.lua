-- One click authorizes exactly one item/quantity up to the displayed estimate.
-- The quote event may confirm that authorization, never start another purchase.
local _, ns = ...
-- Startup-only local timer view; restored to the untouched global API on stop.
local C_Timer = C_Timer
if ns.StartupTimerScope then ns.StartupTimerScope("Auction", C_Timer, function(api) C_Timer = api end) end
local T = ns.L
local A=ns.AuctionHouse
local ID="auctionhouse"
local events=CreateFrame("Frame")
local open,started,invoking=false,false,0
local phase,message="idle",T["打开拍卖行后可搜索与补货"]
local revision,deadline=0,0
local current,queue,index=nil,{},0
local statuses,mailCounts,purchased={}, {}, {}
local purchaseBaselines={}
local mailKnown,mailOpen=false,false
local uncertain=false
local pendingAttempt,lastCompleted,quickRequest
local spent=0
local queryTimes={}
local quoteTaint=false
local refresh=function()if A.RefreshUI then A.RefreshUI()end end
-- Native AH item-data events arrive in bursts. Only the affected views need a
-- repaint, once per batch; purchase/quote state transitions remain immediate.
local itemRefreshQueued=false
local function refreshItemData()
    if itemRefreshQueued then return end
    itemRefreshQueued=true
    C_Timer.After(.05,function()
        itemRefreshQueued=false
        if started then refresh()end
    end)
end
local nextItem,queryCurrent,readResults,purchasedSuccessfully
local function reservations()
    local pc=ns.GetPCDB();pc.auctionhouseReservations=pc.auctionhouseReservations or {}
    return pc.auctionhouseReservations
end
local function reservePending()
    local pc=ns.GetPCDB();local pending=pc.auctionhousePending
    if pending and A.ItemID(pending.itemID) and A.Integer(pending.quantity,1,A.MAX_QUANTITY)then
        reservations()[pending.itemID]=pending
    end
    pc.auctionhousePending=nil
end
local function markUncertain()
    uncertain=true;mailKnown=false
    -- Only our own submitted order may be uncertain; unrelated UI calls are not orders.
end
local function clearPending()
    uncertain=false;pendingAttempt=nil;ns.GetPCDB().auctionhousePending=nil
end
local function read(fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c,d=pcall(fn,...);if ok then return a,b,c,d end
end
local function now()return GetTime()end
local function api()return C_AuctionHouse or {}end
local function enter(value,text,seconds)
    phase=value;message=text or message;revision=revision+1
    local token=revision;deadline=seconds and now()+seconds or 0
    if seconds and C_Timer then C_Timer.After(seconds,function()
        if token~=revision or not open then return end
        if phase=="confirming" then markUncertain() end
        A.Stop(phase=="quote" and T["报价已过期，请重新查询"] or T["请求超时，已停止；未自动重试购买"])
    end)end
    refresh()
end
local function call(name,...)
    local f=api()[name];if type(f)~="function"then return false end
    invoking=invoking+1;local ok,result=pcall(f,...);invoking=invoking-1
    return ok,result
end
local function cancelQuote()
    if current and current.quoteOwned and phase~="confirming"then
        call("CancelCommoditiesPurchase");current.quoteOwned=false
    end
end
function A.IsOpen()return open and ns.IsModuleEnabled(ID)end
function A.IsPurchasing()return pendingAttempt~=nil end
function A.IsBusy()return phase~="idle" and phase~="done"end
function A.MailKnown()return mailKnown end
function A.HasReservation(id)return reservations()[id]~=nil end
function A.ResetReservation(id)
    if pendingAttempt or InCombatLockdown()then return end
    reservations()[id]=nil
    A.Stop(T["已清除这项旧订单标记；请确认邮件已到账，再重新查询"])
end
function A.Spent()return spent end
function A.StatusFor(id)return statuses[id]end
function A.Stop(reason)
    if phase=="confirming"then markUncertain() end
    cancelQuote();current=nil;quickRequest=nil;queue={};index=0
    enter("idle",reason or T["已停止"])
end
local requested={}
local pendingItemCount=0
local itemViews={}
local itemEventsActive=false
local function syncItemEvents()
    -- Global item notifications include every other addon/native cache load.
    -- Listen only for our pending requests or a visible consumer (which also
    -- needs to recover metadata that previously failed to load).
    local needed=started and (open or pendingItemCount>0 or next(itemViews)~=nil)
    if needed==itemEventsActive then return end
    itemEventsActive=needed
    if needed then
        events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        events:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
end
function A.WatchItemDataView(frame)
    local function changed(self)
        itemViews[self]=self:IsVisible() or nil
        syncItemEvents()
    end
    frame:HookScript("OnShow",changed)
    frame:HookScript("OnHide",function(self)itemViews[self]=nil;syncItemEvents()end)
    changed(frame)
end
local function finishItemRequest(id,value)
    if requested[id]==true then pendingItemCount=pendingItemCount-1 end
    requested[id]=value
    syncItemEvents()
end
function A.ItemName(id)
    if not id then return nil end
    local name=read(C_Item and C_Item.GetItemInfo or GetItemInfo,id)
    if type(name)=="string" then
        if requested[id]~=nil then finishItemRequest(id,nil)end
        return name
    end
    if started and requested[id]==nil then
        local request=C_Item and C_Item.RequestLoadItemDataByID
        if type(request)=="function"then
            requested[id]=true;pendingItemCount=pendingItemCount+1
            syncItemEvents() -- subscribe before a possibly immediate completion
            local ok=pcall(request,id)
            if not ok and requested[id]==true then finishItemRequest(id,false)end
        else requested[id]=false end
    end
    return T["物品 #"]..id
end
function A.ItemIcon(id)
    return (id and read(C_Item and C_Item.GetItemIconByID or GetItemIcon,id)) or (A.iconFallbacks and A.iconFallbacks[id]) or 134400
end
function A.Inventory(id,target,includeBank)
    local owned=A.Integer(read(C_Item and C_Item.GetItemCount or GetItemCount,id,includeBank==true,false,includeBank==true,includeBank==true),0,A.MAX_QUANTITY*100)
    local mail=(mailCounts[id] or 0)+(purchased[id] or 0)
    local pending=ns.GetPCDB().auctionhousePending
    if pending and pending.itemID==id then mail=mail+(pending.quantity or 0)end
    local reserved=reservations()[id]
    if reserved then mail=mail+reserved.quantity end
    return owned,mail,A.Need(target,owned,mail),mailKnown
end
local function scanMail()
    if not mailOpen then return end
    local visible,total=read(GetInboxNumItems)
    if not A.Integer(visible,0,10000) or not A.Integer(total,0,10000)then mailKnown=false;return end
    local counts={};local valid=true
    for i=1,visible do
        for slot=1,(ATTACHMENTS_MAX_RECEIVE or 16)do
            local name,id,texture,count=read(GetInboxItem,i,slot)
            if not id and (name or read(GetInboxItemLink,i,slot))then valid=false end
            if id then
                id=A.ItemID(id);count=A.Integer(count,0,A.MAX_QUANTITY*100)
                if not id or not count then valid=false else counts[id]=(counts[id] or 0)+count end
            end
        end
    end
    if valid and visible==total then
        -- A complete list can still precede delivery. Retire confirmed pending
        -- quantities only as an increase in observed holdings is seen.
        for id,quantity in pairs(purchased)do
            local bag=A.Integer(read(C_Item and C_Item.GetItemCount or GetItemCount,id,false),0,A.MAX_QUANTITY*100)
            if bag then
                local holding=bag+(counts[id] or 0)
                local increase=math.max(0,holding-(purchaseBaselines[id] or holding))
                purchased[id]=math.max(0,quantity-increase);purchaseBaselines[id]=holding
            end
        end
        mailCounts=counts;mailKnown=true
        -- On reload an unresolved order reserves its quantity, not the whole UI.
        -- Remove that reservation only when its expected holdings are observed.
        for id,pending in pairs(reservations())do
            local bag=A.Integer(read(C_Item and C_Item.GetItemCount or GetItemCount,id,false),0,A.MAX_QUANTITY*100)
            if bag and pending.baseline and bag+(counts[id] or 0)>=pending.baseline+pending.quantity then reservations()[id]=nil end
        end
    else
        -- An incomplete mailbox cannot safely replace confirmed in-flight stock.
        mailKnown=false
    end
    refresh()
end
local function available()
    return A.IsOpen() and not InCombatLockdown() and A.DB().restock
end
local function supported()
    return type(api().SendSearchQuery)=="function" and type(api().GetCommoditySearchResultInfo)=="function"
        and type(api().StartCommoditiesPurchase)=="function" and type(api().ConfirmCommoditiesPurchase)=="function"
end
local function ready()
    return read(api().IsThrottledMessageSystemReady)==true
end
local function skip(reason)
    if current then statuses[current.id]=reason end
    current=nil
    -- Yield once; no recursive walking of a user-supplied list.
    enter("advance",reason)
    local token=revision
    C_Timer.After(0,function()if token==revision and available()then nextItem()end end)
end
local function budgetOK(total)
    local money=A.Integer(read(GetMoney),0)
    if not money then return false,T["金币数量未知"]end
    if total>money then return false,T["金币不足"]end
    local budget=A.Integer(A.DB().sessionBudget,0) or 0
    local pending=ns.GetPCDB().auctionhousePending
    local reserved=pending and pending.total or 0
    for _,order in pairs(reservations())do reserved=reserved+(order.total or 0)end
    if budget>0 and spent+reserved+total>budget then return false,T["超出本次预算"]end
    return true
end
queryCurrent=function()
    if not current or not available()then return end
    if not ready()then enter("throttle",T["等待拍卖行查询限流…"],15);return end
    local cutoff=now()-60
    while queryTimes[1] and queryTimes[1]<=cutoff do table.remove(queryTimes,1)end
    if #queryTimes>=90 then return A.Stop(T["查询过于频繁，请一分钟后再试"])end
    local key=read(api().MakeItemKey,current.id) or {itemID=current.id,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
    current.key=key;current.accepted=nil
    local info=read(api().GetItemKeyInfo,key)
    -- Cold item-key metadata need not be available before a read-only query.
    if type(info)=="table" and info.isCommodity==false then return skip(T["非商品物品暂不支持"])end
    if not info then A.ItemName(current.id)end
    queryTimes[#queryTimes+1]=now()
    enter("search",T["查询 "]..A.ItemName(current.id).."…",15)
    local order=Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
    if not order then return A.Stop(T["当前客户端缺少拍卖排序接口"])end
    if not call("SendSearchQuery",key,{{sortOrder=order,reverseSort=false}},true)then A.Stop(T["查询被客户端拒绝，请稍后重试"])end
end
nextItem=function()
    if not available()then return A.Stop(T["补货已停止"])end
    index=index+1;local row=queue[index]
    if not row then current=nil;enter("done",T["清单处理完成 · 本次已确认支出 "]..A.Money(spent));return end
    local owned,mail,need=A.Inventory(row.itemID,row.target,row.includeBank)
    current={id=row.itemID,quantity=need,cap=row.maxPrice,target=row.target,includeBank=row.includeBank}
    if need==nil then return skip(T["库存未知"])end
    if reservations()[current.id]then return skip(T["上笔订单在途，暂不重复下单"])end
    if need==0 then return skip(T["已备齐"])end
    if not A.Integer(row.maxPrice,0)then return skip(T["限价无效"])end
    statuses[current.id]=T["查询中"];queryCurrent()
end
local function start()
    if not available()then return end
    if not supported()then return enter("idle",T["当前客户端不支持所需拍卖行接口"])end
    if pendingAttempt then return end
    quoteTaint=false
    queue={};statuses={};index=0
    local seen={}
    local plan=A.ActivePlan()
    if plan.blocked then return enter("idle",plan.blocked)end
    for _,row in ipairs(plan.items)do
        local id=A.ItemID(row.itemID)
        if row.enabled and id and not seen[id] and A.Integer(row.target,1,A.MAX_QUANTITY)then
            queue[#queue+1]={itemID=id,target=row.target,maxPrice=row.maxPrice or 0,includeBank=row.includeBank};seen[id]=true
        end
    end
    nextItem()
end
readResults=function(id)
    if not current or id~=current.id or (phase~="search" and phase~="more" and phase~="metadata")then return end
    local a=api()
    local metadata=read(a.GetItemKeyInfo,current.key)
    if type(metadata)~="table" or metadata.isCommodity==nil then
        enter("metadata",T["等待物品类型信息，尚未允许购买…"],15);return
    end
    if metadata.isCommodity~=true then return skip(T["非商品物品暂不支持"])end
    local count=A.Integer(read(a.GetNumCommoditySearchResults,id),0,100000)
    if not count then return skip(T["报价未知"])end
    local tiers={}
    for i=1,count do
        local info=read(a.GetCommoditySearchResultInfo,id,i)
        if type(info)~="table" or A.ItemID(info.itemID)~=id then return skip(T["报价物品不匹配"])end
        local n=A.Integer(info.quantity,0,A.MAX_QUANTITY*100)
        local own=A.Integer(info.numOwnerItems,0,A.MAX_QUANTITY*100)
        if not n or not own then return skip(T["在售数量未知"])end
        tiers[#tiers+1]={unitPrice=info.unitPrice,quantity=math.max(0,n-own)}
    end
    local _,_,need=A.Inventory(current.id,current.target,current.includeBank)
    if not need then return skip(T["库存未知"])end
    if need==0 then return skip(T["已备齐"])end
    current.quantity=need
    local plan,why=A.PricePlan(tiers,need,current.cap)
    if not plan and why==T["在售数量不足"] and read(a.HasFullCommoditySearchResults,id)~=true then
        if ready()then
            enter("more",T["正在补全价格档位…"],15)
            local ok,full=call("RequestMoreCommoditySearchResults",id)
            if not ok then A.Stop(T["无法补全报价，已停止"])
            elseif full==true and phase=="more" and read(a.HasFullCommoditySearchResults,id)==true then
                local token=revision
                C_Timer.After(0,function()if token==revision and available()then readResults(id)end end)
            end
        else enter("moreThrottle",T["等待补全报价…"],15)end
        return
    end
    if not plan then return skip(why)end
    local ok,reason=budgetOK(plan.total);if not ok then return skip(reason)end
    current.estimate=plan.total;current.highest=plan.highest
    statuses[current.id]=T["待购买"]
    enter("ready",A.ItemName(id).." ×"..need..T[" · 预估 "]..A.Money(plan.total))
end
local function quote()
    if not current or not available()then return end
    if quoteTaint then return A.Stop(T["报价归属不明，请关闭并重新打开拍卖行"])end
    local _,_,need=A.Inventory(current.id,current.target,current.includeBank)
    if need~=current.quantity then
        cancelQuote();statuses[current.id]=T["库存变化，重新查询"];queryCurrent();return
    end
    if not ready()then return A.Stop(T["拍卖行正忙，请重新开始"])end
    current.accepted=current.estimate
    current.quoteOwned=true
    enter("quoting",T["正在获取有效购买报价…"],10)
    if not call("StartCommoditiesPurchase",current.id,current.quantity)then A.Stop(T["客户端拒绝报价请求，请重新点击开始"])end
end
local function confirmAuthorized()
    if not current or not current.accepted or not current.quoteOwned or not available()then return end
    local duration=A.Number(read(api().GetQuoteDurationRemaining))
    if not duration or duration<=0 or now()>=deadline then return A.Stop(T["报价过期，请重新查询"])end
    local _,_,need=A.Inventory(current.id,current.target,current.includeBank)
    if need~=current.quantity then cancelQuote();return queryCurrent()end
    local ok,reason=budgetOK(current.total);if not ok then return A.Stop(reason)end
    local owned=A.Inventory(current.id,current.target)
    current.baseline=(owned or 0)+(mailCounts[current.id] or 0)
    ns.GetPCDB().auctionhousePending={itemID=current.id,quantity=current.quantity,total=current.total,baseline=current.baseline}
    pendingAttempt=current;current.accepted=nil
    statuses[current.id]=T["购买中"]
    enter("confirming",T["正在购买 "]..A.ItemName(current.id).." ×"..current.quantity.." · "..A.Money(current.total),15)
    if not call("ConfirmCommoditiesPurchase",current.id,current.quantity)then
        A.Stop(T["客户端未接受购买确认，已停止；不会自动重试"])
    end
end
-- Start always stays on the actual click. The quote callback consumes its one-shot authorization.
function A.Action()
    if not available() or pendingAttempt then return end
    if phase=="idle" or phase=="done"then start()
    elseif phase=="ready"then quote()end
end
function A.ActionState()
    if not ns.IsModuleEnabled(ID)then return T["模块已停用"],false,T["请在功能页启用拍卖行助手"]end
    if not open then return T["请先打开拍卖行"],false,T["布局预览 · 尚未连接拍卖行，不会发起购买"]end
    if InCombatLockdown()then return T["战斗中暂停"],false,T["脱战后重新开始"]end
    if not A.DB().restock then return T["补货已关闭"],false,T["快捷搜索可独立使用"]end
    if pendingAttempt then return T["正在购买…"],false,uncertain and T["上笔订单结果尚未返回，等待服务器；不会重复下单"] or message end
    if phase=="ready"then return T["购买 ×"]..current.quantity.." · "..A.Money(current.estimate),true,message end
    if phase=="idle" or phase=="done"then
        local plan=A.ActivePlan()
        if plan.blocked then return T["暂无可补货材料"],false,plan.blocked end
        return T["开始补货"],true,message
    end
    return T["请稍候…"],false,message
end
local function searchEntry(entry,fromRestock)
    if not A.IsOpen() or (not fromRestock and not A.DB().quickSearch) or InCombatLockdown()then return end
    if A.IsPurchasing()then return end
    A.Stop(T["已切换至快捷搜索"])
    local name=entry.query
    if entry.itemID then
        name=read(C_Item and C_Item.GetItemInfo or GetItemInfo,entry.itemID)
        if not name then
            A.ItemName(entry.itemID);quickRequest={entry=entry,fromRestock=fromRestock}
            enter("idle",T["正在加载物品，加载完成后自动搜索…"])
            local token=revision
            C_Timer.After(8,function()if revision==token and quickRequest then quickRequest=nil;enter("idle",T["物品加载超时，请稍后重试"])end end)
            return
        end
    end
    local bar=AuctionHouseFrame and AuctionHouseFrame.SearchBar
    if type(name)~="string" or not bar or not bar.SetSearchText or not bar.StartSearch then return enter("idle",T["请打开原生拍卖行浏览页后再搜索"])end
    if fromRestock then
        -- A prior equipment category/level filter must not hide this material.
        -- Open Buy before filling text: SearchBar OnShow clears the search box.
        local frame=AuctionHouseFrame
        local categories=frame.GetCategoriesList and frame:GetCategoriesList()
        if categories and categories.SetSelectedCategory then categories:SetSelectedCategory(nil)end
        if bar.FilterButton and bar.FilterButton.Reset then bar.FilterButton:Reset()end
        if frame.SetDisplayMode and AuctionHouseFrameDisplayMode then frame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)end
    end
    bar:SetSearchText(name);bar:StartSearch()
    enter("idle",T["已搜索："]..name..T["；同名物品请核对品质"])
end
function A.QuickSearch(entry)return searchEntry(entry,false)end
function A.SearchRestockItem(entry)return searchEntry(entry,true)end
local function priceUpdated(unitPrice,totalPrice)
    if (phase~="quoting" and phase~="quote") or not current or not current.quoteOwned then return end
    unitPrice=A.Integer(unitPrice,1);totalPrice=A.Integer(totalPrice,1)
    if not unitPrice or not totalPrice then return A.Stop(T["报价无效，未购买"])end
    -- Check the returned unit/total values and previewed amount. The API does
    -- not document updatedUnitPrice as the maximum constituent tier price.
    if (current.cap>0 and (unitPrice>current.cap or totalPrice>current.quantity*current.cap)) or totalPrice>(current.accepted or current.estimate) then
        local id=current.id;cancelQuote();statuses[id]=T["报价上涨，已跳过"];return skip(T["报价上涨，已跳过"])
    end
    local ok,reason=budgetOK(totalPrice);if not ok then return A.Stop(reason)end
    current.total=totalPrice;statuses[current.id]=T["正在购买"]
    local duration=A.Number(read(api().GetQuoteDurationRemaining))
    if not duration or duration<=0 then return A.Stop(T["无法确认报价有效期，未购买"])end
    enter("quote",A.ItemName(current.id).." ×"..current.quantity..T[" · 报价 "]..A.Money(totalPrice),duration)
    confirmAuthorized()
end
purchasedSuccessfully=function()
    local attempt=pendingAttempt
    if not attempt or quoteTaint then return end
    local continuing=phase=="confirming" and current==attempt
    if not purchased[attempt.id] or purchased[attempt.id]==0 then purchaseBaselines[attempt.id]=attempt.baseline end
    purchased[attempt.id]=(purchased[attempt.id] or 0)+attempt.quantity
    spent=spent+attempt.total;statuses[attempt.id]=T["已购 "]..attempt.quantity
    ns.Print(T["拍卖补货："]..A.ItemName(attempt.id).." ×"..attempt.quantity.."，"..A.Money(attempt.total))
    lastCompleted={id=attempt.id,quantity=attempt.quantity}
    attempt.quoteOwned=false;current=nil;clearPending()
    if continuing then
        enter("advance",T["购买成功，查询下一项…"])
        local token=revision;C_Timer.After(0,function()if revision==token and available()then nextItem()end end)
    else enter("idle",T["上笔购买已成功，可继续补货"])end
end
function A.HandleEvent(event,...)
    if event=="AUCTION_HOUSE_SHOW"then
        if open then if A.SyncPanel then A.SyncPanel()end;return end
        open=true;syncItemEvents();spent=0;quoteTaint=false;A.Stop(T["选择快捷搜索，或开始按清单补货"]);if A.SyncPanel then A.SyncPanel()end
    elseif event=="AUCTION_HOUSE_DISABLED"then open=false;syncItemEvents();A.Stop(T["拍卖行暂不可用"]);if A.SyncPanel then A.SyncPanel()end
    elseif event=="AUCTION_HOUSE_CLOSED"then open=false;syncItemEvents();A.Stop(T["拍卖行已关闭"]);if A.SyncPanel then A.SyncPanel()end
    elseif event=="PLAYER_REGEN_DISABLED"then A.Stop(T["进入战斗，补货已停止"])
    elseif event=="PLAYER_LEAVING_WORLD"then open=false;syncItemEvents();A.Stop(T["离开当前区域，已停止"])
    elseif event=="MAIL_SHOW"then mailOpen=true;scanMail()
    elseif event=="MAIL_CLOSED"then mailOpen=false
    elseif event=="MAIL_INBOX_UPDATE"then scanMail()
    elseif event=="COMMODITY_SEARCH_RESULTS_UPDATED" or event=="COMMODITY_SEARCH_RESULTS_ADDED"then readResults(...)
    elseif event=="ITEM_SEARCH_RESULTS_UPDATED"then
        local key=...;if current and type(key)=="table" and key.itemID==current.id and phase=="search"then skip(T["非商品物品暂不支持"])end
    elseif event=="AUCTION_HOUSE_THROTTLED_SYSTEM_READY"then
        if phase=="throttle"then queryCurrent()
        elseif phase=="moreThrottle"then phase="more";readResults(current.id)end
    elseif event=="COMMODITY_PRICE_UPDATED"then priceUpdated(...)
    elseif event=="COMMODITY_PRICE_UNAVAILABLE"then if phase=="quoting" or phase=="quote"then A.Stop(T["当前报价不可用，请重新查询"])end
    elseif event=="COMMODITY_PURCHASE_SUCCEEDED"then
        if pendingAttempt then purchasedSuccessfully()end
    elseif event=="COMMODITY_PURCHASED"then
        -- SUCCEEDED is authoritative, as in Blizzard's UI. PURCHASED is optional
        -- identity corroboration, never a second prerequisite or another credit.
        if pendingAttempt then
            local id,quantity=...
            if A.ItemID(id)==pendingAttempt.id and A.Integer(quantity,1,A.MAX_QUANTITY)==pendingAttempt.quantity then
                pendingAttempt.identitySeen=true
            elseif not lastCompleted or lastCompleted.id~=id or lastCompleted.quantity~=quantity then
                pendingAttempt.quoteOwned=false;quoteTaint=true
                A.Stop(T["收到其他订单回执，本单暂记在途，未自动继续"])
                reservePending();pendingAttempt=nil;uncertain=false;refresh()
            end
        end
    elseif event=="COMMODITY_PURCHASE_FAILED"then
        if pendingAttempt then
            pendingAttempt.quoteOwned=false;clearPending();current=nil
            enter("idle",T["购买未成功，可重新查询"])
        end
    elseif event=="TRACKED_RECIPE_UPDATE" or event=="TRADE_SKILL_LIST_UPDATE" then
        A.Recipes.Invalidate()
        if A.purchaseSource=="recipes" and A.IsBusy()then A.Stop(T["追踪配方已更新；当前订单结束后请重新查询"])else refresh()end
    elseif event=="BAG_UPDATE_DELAYED"then
        if A.RefreshInventory then A.RefreshInventory()end
    elseif event=="ITEM_KEY_ITEM_INFO_RECEIVED" or event=="ITEM_DATA_LOAD_RESULT" or event=="GET_ITEM_INFO_RECEIVED"then
        local itemID,success=...
        itemID=A.ItemID(type(itemID)=="table" and itemID.itemID or itemID)
        if not itemID then return end
        local itemData=event~="ITEM_KEY_ITEM_INFO_RECEIVED"
        local dirty=false
        -- Observe only data requested by this helper, not every item loaded by
        -- Blizzard's browse results (or another addon). Failures must not loop.
        if itemData and requested[itemID]~=nil then
            if success==false then finishItemRequest(itemID,false)
            else finishItemRequest(itemID,nil);dirty=true end
        end
        if itemData and success~=false and A.Recipes.InvalidateItem(itemID)then dirty=true end
        if success~=false then
            if quickRequest and quickRequest.entry.itemID==itemID then
                -- An unrelated or still-incomplete event must not restart the
                -- search timeout or allocate another stale timer callback.
                local name=read(C_Item and C_Item.GetItemInfo or GetItemInfo,itemID)
                if type(name)=="string"then
                    local request=quickRequest;quickRequest=nil;searchEntry(request.entry,request.fromRestock)
                end
            elseif phase=="metadata" and current and current.id==itemID then
                local metadata=read(api().GetItemKeyInfo,current.key)
                if type(metadata)=="table" and metadata.isCommodity~=nil then readResults(itemID)end
            end
        end
        if dirty then refreshItemData()end
    elseif event=="PLAYER_REGEN_ENABLED"then refresh()end
end
local hooksInstalled=false
local function hookAuctions()
    if hooksInstalled or not hooksecurefunc or not C_AuctionHouse then return end
    hooksInstalled=true
    -- Quotes are a shared client resource. Other UIs must never overwrite ours
    -- unnoticed. Post-hooks observe only; they do not replace Blizzard functions.
    for _,name in ipairs({"StartCommoditiesPurchase","ConfirmCommoditiesPurchase","CancelCommoditiesPurchase","SendSearchQuery","SendBrowseQuery","PlaceBid"})do
        if type(api()[name])=="function"then
            hooksecurefunc(api(),name,function()
                if invoking>0 or not started then return end
                if name=="ConfirmCommoditiesPurchase" or name=="PlaceBid"then mailKnown=false end
                if not A.IsBusy() and not pendingAttempt then refresh();return end
                quoteTaint=true
                if current then current.quoteOwned=false end
                A.Stop(T["已切换其他拍卖操作；需要时可重新开始补货"])
                -- Keep only a per-item reservation if our submitted order lost
                -- ownership. Never turn someone else's trade into an unlock gate.
                reservePending();pendingAttempt=nil;uncertain=false;refresh()
            end)
        end
    end
end
local function enable()
    if started then return end
    started=true;A.Recipes.Invalidate()
    -- Migrate the prototype's false lock caused by unrelated/native purchases.
    local pending=ns.GetPCDB().auctionhousePending
    if pending and pending.external then clearPending()
    elseif pending and not pendingAttempt then reservePending()end
    for _,event in ipairs({"AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_DISABLED","AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
        "COMMODITY_SEARCH_RESULTS_UPDATED","COMMODITY_SEARCH_RESULTS_ADDED","ITEM_SEARCH_RESULTS_UPDATED","ITEM_KEY_ITEM_INFO_RECEIVED","COMMODITY_PRICE_UPDATED","COMMODITY_PRICE_UNAVAILABLE",
        "COMMODITY_PURCHASE_SUCCEEDED","COMMODITY_PURCHASE_FAILED","COMMODITY_PURCHASED","MAIL_SHOW","MAIL_CLOSED","MAIL_INBOX_UPDATE",
        "TRACKED_RECIPE_UPDATE","TRADE_SKILL_LIST_UPDATE","BAG_UPDATE_DELAYED","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_LEAVING_WORLD","ADDON_LOADED"})do events:RegisterEvent(event)end
    syncItemEvents();hookAuctions()
    if AuctionHouseFrame and AuctionHouseFrame:IsShown()then A.HandleEvent("AUCTION_HOUSE_SHOW")end
end
local function disable()
    A.Stop(T["拍卖行助手已停用"]);started=false;open=false;events:UnregisterAllEvents()
    itemEventsActive=false
    -- Completion while disabled must not strand a request across re-enable.
    for id,pending in pairs(requested)do if pending==true then requested[id]=nil end end
    pendingItemCount=0
    -- Events can finish while unsubscribed: release the runtime wait, retaining
    -- only this item's reservation instead of blocking all future purchases.
    reservePending();pendingAttempt=nil;uncertain=false
    -- Mail may change while disabled. Never reuse a stale known inventory.
    mailKnown=false;mailOpen=false;mailCounts={}
    -- Keep confirmed in-flight stock when toggled off and back on.
    if A.panel then A.panel:Hide()end
end
events:SetScript("OnEvent",function(_,event,...)
    if event=="ADDON_LOADED"then hookAuctions()else A.HandleEvent(event,...)end
end)
ns.RegisterModule({id=ID,name=T["拍卖行助手"],desc=T["常用物品快捷搜索，清单与追踪配方材料补货。"],defaults=A.defaults,
    BuildOptions=function(...)return A.BuildOptions(...)end,OnEnable=enable,OnDisable=disable,
    OnToggle=function(_,on)if on then enable()end end})
SLASH_BAIMIAOAH1="/bmah"
SlashCmdList.BAIMIAOAH=function()if A.ShowPanel then A.ShowPanel(true)end end

if ns.PerfWatchFrame then ns.PerfWatchFrame("Auction", events, "OnEvent") end

if ns.StartupCheckpoint then ns.StartupCheckpoint("AuctionHouse.lua") end
