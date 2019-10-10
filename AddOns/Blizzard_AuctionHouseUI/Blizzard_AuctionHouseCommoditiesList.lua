
local COMMODITIES_LIST_SCROLL_OFFSET_REFRESH_THRESHOLD = 30;


AuctionHouseCommoditiesListMixin = CreateFromMixins(AuctionHouseItemListMixin, AuctionHouseSystemMixin);

local AUCTION_HOUSE_COMMODITIES_LIST_EVENTS = {
	"COMMODITY_SEARCH_RESULTS_UPDATED",
	"COMMODITY_SEARCH_RESULTS_ADDED",
};

function AuctionHouseCommoditiesListMixin:OnLoad()
	AuctionHouseItemListMixin.OnLoad(self);
	
	local function CommoditiesListGetTotalQuantity()
		return self.itemID and C_AuctionHouse.GetCommoditySearchResultsQuantity(self.itemID) or 0;
	end

	local function CommoditiesListRefreshResults()
		if self.itemID then
			C_AuctionHouse.RefreshCommoditySearchResults(self.itemID);
		end
	end

	self:SetRefreshFrameFunctions(CommoditiesListGetTotalQuantity, CommoditiesListRefreshResults);
end

function AuctionHouseCommoditiesListMixin:OnShow()
	self:UpdateDataProvider();

	AuctionHouseItemListMixin.OnShow(self);

	FrameUtil.RegisterFrameForEvents(self, AUCTION_HOUSE_COMMODITIES_LIST_EVENTS);
end

function AuctionHouseCommoditiesListMixin:OnHide()
	FrameUtil.UnregisterFrameForEvents(self, AUCTION_HOUSE_COMMODITIES_LIST_EVENTS);
end

function AuctionHouseCommoditiesListMixin:OnEvent(event, ...)
	if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		self:Reset();
	elseif event == "COMMODITY_SEARCH_RESULTS_ADDED" then
		self:DirtyScrollFrame();
	end
end

function AuctionHouseCommoditiesListMixin:SetItemID(itemID)
	self.itemID = itemID;
	self:UpdateDataProvider();
	self:DirtyScrollFrame();
end

function AuctionHouseCommoditiesListMixin:UpdateDataProvider()
	local itemID = self.itemID;

	local function CommoditiesListSearchStarted()
		return itemID ~= nil;
	end

	local function CommoditiesListGetEntry(index)
		return C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index);
	end

	local function CommoditiesListGetNumEntries()
		return C_AuctionHouse.GetNumCommoditySearchResults(itemID);
	end

	local function CommoditiesListHasFullResults()
		return C_AuctionHouse.HasFullCommoditySearchResults(itemID);
	end

	self:SetDataProvider(CommoditiesListSearchStarted, CommoditiesListGetEntry, CommoditiesListGetNumEntries, CommoditiesListHasFullResults);
end

function AuctionHouseCommoditiesListMixin:RefreshScrollFrame()
	AuctionHouseItemListMixin.RefreshScrollFrame(self);

	if not self.isInitialized then
		return;
	end

	if not self.itemID or C_AuctionHouse.HasFullCommoditySearchResults(self.itemID) then
		return;
	end

	local numEntries = C_AuctionHouse.GetNumCommoditySearchResults(self.itemID);
	if numEntries > 0 then
		local buttons = HybridScrollFrame_GetButtons(self.ScrollFrame);
		local buttonCount = #buttons;
		local offset = self:GetScrollOffset();
		local lastDisplayedEntry = offset + buttonCount;
		if numEntries - lastDisplayedEntry < COMMODITIES_LIST_SCROLL_OFFSET_REFRESH_THRESHOLD then
			C_AuctionHouse.RequestMoreCommoditySearchResults(self.itemID);
		end
	end
end


AuctionHouseCommoditiesBuyListMixin = CreateFromMixins(AuctionHouseCommoditiesListMixin);

function AuctionHouseCommoditiesBuyListMixin:OnLoad()
	AuctionHouseCommoditiesListMixin.OnLoad(self);

	self:SetSelectionCallback(function(auctionData)
		self:OnAuctionSelected(auctionData);
	end);

	self:SetTableBuilderLayout(AuctionHouseTableBuilder.GetCommoditiesBuyListLayout(self));

	local function QuantitySelectionChangedCallback(event, quantity)
		self:SetQuantitySelected(quantity);
	end

	self.quantitySelectionChangedCallback = QuantitySelectionChangedCallback;

	self.quantitySelected = 1;

	self.ScrollFrame:SetPoint("TOPLEFT", self.HeaderContainer, "TOPLEFT", 0, -6);
end

function AuctionHouseCommoditiesBuyListMixin:OnEnterListLine(line, rowData)
	if rowData.containsOwnerItem then
		GameTooltip:SetOwner(line, "ANCHOR_RIGHT");
		GameTooltip_SetTitle(GameTooltip, AUCTION_HOUSE_OWNED_COMMODITIES_LINE_TOOLTIP_TITLE);
		GameTooltip_AddNormalLine(GameTooltip, AUCTION_HOUSE_OWNED_COMMODITIES_LINE_TOOLTIP_TEXT);
		GameTooltip:Show();
	end
end

function AuctionHouseCommoditiesBuyListMixin:OnLeaveListLine(line, rowData)
	GameTooltip:Hide();
end

function AuctionHouseCommoditiesBuyListMixin:UpdateDynamicCallbacks()
	-- These callbacks are based on quantity selected and need to be reset when the quantity selection changes.

	-- Also note that because commodities are selected and highlighted in order, the later results depend
	-- on the earlier ones, so these callbacks also need to be reset when the scroll frame is refreshed.

	self:UpdateListHighlightCallback();
	self:UpdateGetEntryInfoCallback();
end

function AuctionHouseCommoditiesBuyListMixin:GetQuantityToHighlight()
	local quantityScrolled = AuctionHouseUtil.AggregateSearchResults(self.itemID, self:GetScrollOffset());
	return math.max(self.quantitySelected - quantityScrolled, 0);
end

function AuctionHouseCommoditiesBuyListMixin:UpdateListHighlightCallback()
	local quantityToHighlight = self:GetQuantityToHighlight();
	if quantityToHighlight == 0 then
		self:SetHighlightCallback(nil);
	else
		self:SetHighlightCallback(function(currentRowData, selectedRowData)
			local shouldHighlight = quantityToHighlight > 0 and (currentRowData.quantity > currentRowData.numOwnerItems);
			local highlightAlpha = (currentRowData.containsOwnerItem or (quantityToHighlight < currentRowData.quantity)) and 0.5 or 1.0;
			quantityToHighlight = math.max(quantityToHighlight - (currentRowData.quantity - currentRowData.numOwnerItems), 0);
			return shouldHighlight, highlightAlpha;
		end);
	end
end

function AuctionHouseCommoditiesBuyListMixin:UpdateGetEntryInfoCallback()
	local quantityToHighlight = self:GetQuantityToHighlight();
	self.getEntryInfoCallback = function(index)
		local searchResult = C_AuctionHouse.GetCommoditySearchResultInfo(self.itemID, index);
		if not searchResult then
			return searchResult;
		end

		searchResult.maximumToHighlight = quantityToHighlight;
		quantityToHighlight = math.max(quantityToHighlight - searchResult.quantity, 0);
		return searchResult;
	end
end

function AuctionHouseCommoditiesBuyListMixin:SetQuantitySelected(quantity)
	self.quantitySelected = quantity;
	self:UpdateDynamicCallbacks();
	self:DirtyScrollFrame();
end

function AuctionHouseCommoditiesBuyListMixin:OnShow()
	AuctionHouseCommoditiesListMixin.OnShow(self);

	self:GetAuctionHouseFrame():RegisterCallback(AuctionHouseFrameMixin.Event.CommoditiesQuantitySelectionChanged, self.quantitySelectionChangedCallback);
end

function AuctionHouseCommoditiesBuyListMixin:OnHide()
	AuctionHouseCommoditiesListMixin.OnHide(self);

	self:GetAuctionHouseFrame():UnregisterCallback(AuctionHouseFrameMixin.Event.CommoditiesQuantitySelectionChanged, self.quantitySelectionChangedCallback);
end

function AuctionHouseCommoditiesBuyListMixin:SetItemID(itemID)
	AuctionHouseCommoditiesListMixin.SetItemID(self, itemID);

	self:SetQuantitySelected(1);
end

function AuctionHouseCommoditiesBuyListMixin:UpdateDataProvider() -- Overrides AuctionHouseCommoditiesListMixin
	local itemID = self.itemID;

	local function CommoditiesBuyListSearchStarted()
		return itemID ~= nil;
	end

	local function CommoditiesBuyListGetEntry(index)
		return self.getEntryInfoCallback(index);
	end

	local function CommoditiesBuyListGetNumEntries()
		return C_AuctionHouse.GetNumCommoditySearchResults(itemID);
	end

	local function CommoditiesBuyListHasFullResults()
		return C_AuctionHouse.HasFullCommoditySearchResults(itemID);
	end

	self:SetDataProvider(CommoditiesBuyListSearchStarted, CommoditiesBuyListGetEntry, CommoditiesBuyListGetNumEntries, CommoditiesBuyListHasFullResults);
end

function AuctionHouseCommoditiesBuyListMixin:GetAuctionHouseFrame() -- Overrides AuctionHouseCommoditiesListMixin
	return self:GetParent():GetAuctionHouseFrame();
end

function AuctionHouseCommoditiesBuyListMixin:RefreshScrollFrame()
	AuctionHouseCommoditiesListMixin.RefreshScrollFrame(self);

	self:UpdateDynamicCallbacks();
end


AuctionHouseCommoditiesSellListMixin = CreateFromMixins(AuctionHouseCommoditiesListMixin);

function AuctionHouseCommoditiesSellListMixin:OnLoad()
	AuctionHouseCommoditiesListMixin.OnLoad(self);

	self:SetTableBuilderLayout(AuctionHouseTableBuilder.GetCommoditiesSellListLayout(self, self));

	self:SetHighlightCallback(function(currentRowData, selectedRowData)
		return selectedRowData and currentRowData.unitPrice == selectedRowData.unitPrice;
	end);
end
