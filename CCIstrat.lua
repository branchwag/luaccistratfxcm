-- ***REQUIRED FUNCTION***
-- The Init function is the first thing thats ran as soon as a strategy is selected...
-- This allows you to select the parameters for your strategy...
-- i.e. lotsize, stop/limit levels, indicator settings, anything you want the ability to change
function Init()
    strategy:name("The Magic Sauce"); -- Name of the strategy
    strategy:description("This strategy places trades based off of CCI Crossovers. Triggers BUY if CCI crosses up over the -100 line and triggers SELL if CCI crosses down over the +100 line."); -- Description of the strategy: This strategy places trades based off of CCI Crossovers. Triggers BUY if CCI crosses up over the -100 line and triggers SELL if CCI crosses down over the +100 line. (May add in a moving average - default 200 period, but let's try this first)
	
	--Time Frame parameter
    strategy.parameters:addString("TF", "Time Frame", "Time frame ('m1', 'm5', etc.) the strategy will be fun on.", "H1");
		strategy.parameters:setFlag("TF", core.FLAG_BARPERIODS); -- core.FLAG_BARPERIODS will create a convenient drop down list of all available time frames for this parameter
	
	-- CCI parameters
	strategy.parameters:addGroup("CCI Settings");
	strategy.parameters:addInteger("CCI_Periods", "CCI", "Specify the period used for the CCI calculation", 14);

	-- Money Management parameters
	strategy.parameters:addGroup("Money Management");
	strategy.parameters:addInteger("LotSize", "LotSize", "Set the trade size; an input of 1 refers to the minimum contract size available on the account", 200);
    strategy.parameters:addDouble("StopLoss", "StopLoss", "Set the distance, in pips, from entry price to place a stoploss on trades", 15);
    strategy.parameters:addDouble("Limit", "Limit", "Set the distance, in pips, from entry price to place a limit(ie. Limit) on trades", 30);

	-- Magic Number and Account parameters
	strategy.parameters:addGroup("Misc");	
    strategy.parameters:addString("MagicNumber", "MagicNumber", "This will allow the strategy to more easily see what trades belong to it.", "1992");
	strategy.parameters:addString("Account", "Account to trade on", "", "");
		strategy.parameters:setFlag("Account", core.FLAG_ACCOUNT); -- core.FLAG_ACCOUNT will create a convenient drop down list of all available accounts

end




-- ***REQUIRED AREA***
-- list of global variables to be referenced in any function
local CCI_Periods;
local LotSize;
local StopLoss;
local Limit;
local MagicNumber;
local Account;
-- global variables I added
local AllowTrade;
local ShowAlert;
local Email;
local SendEmail;
-- [Question! How do I make this have popups and send emails? Know how to put the parameters in, but not sure how to code the Update function with it.]

local Source = nil; -- will be the source stream

local BaseSize, Offer, CanClose; -- will store account information
local iCCI; -- will be indicator data streams

local first; -- will be the index of the oldest period we can use





-- ***REQUIRED FUNCTION***
-- The Prepare function is run one time when the strategy is turned on.
-- This is where we store our parameter settings as variables.
-- We create our Strategy's chart "Legend"
-- We store our account's settings (FIFO/Non-FIFO, Base trade size)
-- We define what our price source(s) will be.
-- We create any indicator streams we will need to reference.
function Prepare(nameOnly)
	-- stores the parameters we selected using simpler variable names
    CCI_Periods = instance.parameters.CCI_Periods;
    LotSize = instance.parameters.LotSize;
    StopLoss = instance.parameters.StopLoss;
    Limit = instance.parameters.Limit;
	MagicNumber = instance.parameters.MagicNumber;
	Account = instance.parameters.Account;

	-- creates the "Legend" displayed in the top left corner of the chart
    local name = profile:id() .. "(" .. instance.bid:instrument() .. ", " .. tostring(instance.parameters.TF) .. ", " .. tostring(CCI_Periods) .. ", " .. tostring(LotSize) .. ", " .. tostring(StopLoss) .. ", " .. tostring(Limit) .. ", " .. tostring(MagicNumber) .. ")";
    instance:name(name);
    if nameOnly then
        return ;
    end
	
	ShowAlert = instance.parameters.ShowAlert;

    local PlaySound = instance.parameters.PlaySound;
    if PlaySound then
        SoundFile = instance.parameters.SoundFile;
        RecurrentSound = instance.parameters.RecurrentSound;
    else
        SoundFile = nil;
        RecurrentSound = false;
    end
    assert(not(PlaySound) or (PlaySound and SoundFile ~= ""), ("SoundFileError"));
    
    SendEmail = instance.parameters.SendEmail;
    if SendEmail then
        Email = instance.parameters.Email;
    else
        Email = nil;
    end
    assert(not(SendEmail) or (SendEmail and Email ~= ""), ("EmailAddressError"));
	
    -- stores the account's settings
    BaseSize = core.host:execute("getTradingProperty", "baseUnitSize", instance.bid:instrument(), Account); -- base trade size
    Offer = core.host:findTable("offers"):find("Instrument", instance.bid:instrument()).OfferID; -- the instrument the strategy is applied to in this instance
    CanClose = core.host:execute("getTradingProperty", "canCreateMarketClose", instance.bid:instrument(), Account); -- whether account is FIFO or Non-FIFO

	-- creates our price source based on the TF (time frame) we selected in parameters.
    Source = ExtSubscribe(1, nil, instance.parameters.TF, true, "bar");
	
	-- creates our indicator streams based on the parameters we selected
	iCCI = core.indicators:create("CCI", Source, CCI_Periods);
	
	-- stores the oldest index, or in other words, the first bar we can work with
	first = math.max(iCCI.DATA:first());
	
end





-- ***REQUIRED FUNCTION***
-- The ExtUpdate function is run everytime our price source updates based on time frame we picked...
-- 		...(m5 = runs every 5 minute close, H1 = runs every hourly close, etc)
-- We need to update our indicators' values
-- We need to make sure our indicators' have data available before we reference them
-- We need to add our 'decision making' logic
-- This is the brain of the strategy that causes things to happen
function ExtUpdate(id, source, period)
	-- Updates CCI indicator
    iCCI:update(core.UpdateLast);
	
	-- simplifies variable names for indicators
	CCI = iCCI.DATA;
	
	-- if the period is before the first bar we can work with, return (do nothing)
	if (period < first+1) then
		return; -- stop and do nothing this bar
	end

	-- check to make sure indicators have data for the latest closed bar
	if not CCI:hasData(period) then
		core.host:trace("We are missing data for some reason. No action taken this bar");
		return;
	end
	
	
	------------------------
	--  MY TRADING LOGIC  --                        
	------------------------

	-- only check logic if there are no open strategy trades
	if not haveTrades() then
	
	
		-- BUY Logic
		-- ENGLISH: if CCI crosses over -100, then Buy.
		if core.crossesOver(iCCI.DATA, -100, period) then
			enter("B"); -- place a buy trade
		end
		
		-- SELL Logic
		-- ENGLISH: if CCI crosses under 100, then Sell.
		if core.crossesUnder(iCCI.DATA, 100, period) then
			enter("S"); -- place a sell trade
		end
		
		
	end
	
end







-- This is a custom function that will enter a market order with a stop/limit (if specified)
-- This will only run when it is called (typically called from your strategy's trading logic)
-- calling enter("B") will execute a market order to buy with a stop/limit (if specified)
-- calling enter("S") will execute a market order to sell with a stop/limit (if specified)
function enter(BuySell)
	local valuemap, success, msg;

    valuemap = core.valuemap();

    valuemap.OrderType = "OM";
    valuemap.OfferID = Offer;
    valuemap.AcctID = Account;
    valuemap.Quantity = LotSize * BaseSize;
    valuemap.BuySell = BuySell;
    valuemap.GTC = "GTC";
    valuemap.CustomID = "FXCM_Contest";

	-- set limit order if its greater than 0
    if Limit > 0 then
        valuemap.PegTypeLimit = "O";
        if BuySell == "B" then
           valuemap.PegPriceOffsetPipsLimit = Limit;
        else
           valuemap.PegPriceOffsetPipsLimit = -Limit;
        end
    end

	-- set stoploss order if its greater than 0
    if StopLoss > 0 then
        valuemap.PegTypeStop = "O";
        if BuySell == "B" then
           valuemap.PegPriceOffsetPipsStop = -StopLoss;
        else
           valuemap.PegPriceOffsetPipsStop = StopLoss;
        end
    end

	-- sets correct stop/limit based on FIFO vs Non-FIFO accounts
    if (not CanClose) and (StopLoss > 0 or Limit > 0) then
        valuemap.EntryLimitStop = 'Y'
    end
    
    success, msg = terminal:execute(100, valuemap);

    if not(success) then
        terminal:alertMessage(instance.bid:instrument(), instance.bid[instance.bid:size() - 1], "alert_OpenOrderFailed: " .. msg, instance.bid:date(instance.bid:size() - 1));
        return false;
    end

    return true;
end







-- This is a custom function that will tell us if there is a strategy trade already open or not
-- This will only run when it is called (typically called from your strategy's trading logic)
-- calling haveTrades("B") will return 'true' if there is a strategy Buy position currently open
-- calling haveTrades("S") will return 'true' if there is a strategy Sell position currently open
-- calling haveTrades() will return 'true' if there is any strategy  position currently open (buy or sell)
function haveTrades(BuySell)
    local enum, row;
    local found = false;
    enum = core.host:findTable("trades"):enumerator();
    row = enum:next();
    while (not found) and (row ~= nil) do
        if row.AccountID == Account and
           row.OfferID == Offer and
           (row.BS == BuySell or BuySell == nil) and
           row.QTXT == "FXCM_Contest" then
           found = true;
        end
        row = enum:next();
    end

    return found;
end





-- *** REQUIRED FILE ***
-- This allows you to more easily code strategies in Marketscope the way this strategy is coded
dofile(core.app_path() .. "\\strategies\\standard\\include\\helper.lua");








