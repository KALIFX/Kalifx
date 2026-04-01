#property strict
#property copyright "COPYRIGHT 2025, KALIFX TRADE MANAGER"
#property link      "www.kalilfxlab.com"
#property version   "1.70"
#property description "Kalifx Trade Manager"
#property description "Smart order management panel,"
#property description "trailing, Breakeven & Partial close,"
#property description "Precision trades. Consistent profits."

input string sepBE            = "=== BreakEven Settings ===";
input bool   EnableBE         = true;
input double BE_TP_Percent    = 60.0;
input int    BE_OffsetPoints  = 20;
input int    StartBE_ButtonOffsetPoints = 10;

input string sepTS1                = "=== Trailing Stop (Points-Based) ===";
input bool   EnableTrailingPoints  = false;
input int    TS_StartPoints        = 300;
input int    TS_StepPoints         = 50;
input int    TS_StopPoints         = 150;

input string sepTS2                = "=== Trailing Stop (% of TP Based) ===";
input bool   EnableTrailingPercent = false;
input double TS_StartTPPercent     = 60.0;
input int    TS_StepPoints2        = 20;
input double TS_ProfitLockPercent  = 50.0;

input string sepAutoSLTP      = "=== Auto SL/TP Settings ===";
input bool   UseAutoSLTP      = false;
input int    AutoStopLoss     = 300;
input int    AutoTakeProfit   = 600;

input string sepPartial              = "=== Partial Close Settings ===";
input bool   EnablePartialClose      = false;
input double PartialClosePercent     = 50.0;
input double PartialCloseTriggerTP   = 70.0;

input string sepEquityProtect        = "=== Equity Protection ===";
input bool   EnableEquityProtection  = false;
input double MaxDrawdownPercent      = 20.0;
input bool   EnableFloatingLossProtection = false;
input double MaxFloatingLossAmount   = 100.0;
input double MaxFloatingLossPercent  = 10.0;
input bool   HaltTradingOnProtection = true;
input bool   AutoResumeNextDay       = false;

input string sepPanel          = "=== Order Panel Settings ===";
input bool   EnablePanel       = true;
input bool   EnableActionPanel = true;
input bool   StartWithRiskMode = true;
input double DefaultRiskPct    = 1.0;
input double DefaultFixedLot   = 0.10;
input int    PanelX            = 10;
input int    PanelY            = 30;
input int    UiRefreshMs       = 30;
input bool   ShowEntryLineLabels = true;

input int    MagicNumber       = 0;
input int    SlippagePoints    = 20;

double g_MaxBalance = 0.0;
bool   g_ProtectionTriggered = false;
bool   g_TradingHalted = false;
int    g_HaltDayOfYear = -1;

bool   g_UseRiskMode = true;
bool   g_UsePendingMode = false;
double g_RiskPercent = 1.0;
double g_FixedLot    = 0.10;
bool   g_BeRuntimeEnabled = true;
bool   g_TrailingRuntimeEnabled = false;
bool   g_ForceBEStart = false;
bool   g_ForceTSStart = false;
bool   g_TSPercentStartOverridden = false;
bool   g_UseStartBEButtonOffset = false;

int    g_PendingDirection = 0;
double g_LastPartialTicketLot = -1.0;
int    g_LastPartialTicket = -1;

string PANEL_BG      = "KFX_PANEL_BG";
string BTN_BUY       = "KFX_BTN_BUY";
string BTN_SELL      = "KFX_BTN_SELL";
string BTN_MODE      = "KFX_BTN_MODE";
string EDIT_SIZE     = "KFX_EDIT_SIZE";
string BTN_SEND      = "KFX_BTN_SEND";
string BTN_CANCEL    = "KFX_BTN_CANCEL";
string PANEL2_BG     = "KFX_PANEL2_BG";
string BTN_CLOSE_ALL = "KFX_BTN_CLOSE_ALL";
string BTN_CLOSE_BUY = "KFX_BTN_CLOSE_BUY";
string BTN_CLOSE_SELL= "KFX_BTN_CLOSE_SELL";
string BTN_START_TS  = "KFX_BTN_START_TS";
string BTN_START_BE  = "KFX_BTN_START_BE";
string LINE_SL       = "KFX_LINE_SL";
string LINE_TP       = "KFX_LINE_TP";
string LINE_ENTRY    = "KFX_LINE_ENTRY";
string LABEL_SL      = "KFX_LABEL_SL";
string LABEL_TP      = "KFX_LABEL_TP";
string LABEL_ENTRY   = "KFX_LABEL_ENTRY";

int GetDayOfYear(datetime t){ return TimeDayOfYear(t); }

int OnInit(){
   g_MaxBalance = AccountBalance();
   g_UseRiskMode = StartWithRiskMode;
   g_RiskPercent = MathMax(0.01, DefaultRiskPct);
   g_FixedLot    = MathMax(0.01, DefaultFixedLot);
   g_BeRuntimeEnabled = EnableBE;
   g_TrailingRuntimeEnabled = (EnableTrailingPoints || EnableTrailingPercent);

   if(EnablePanel) CreatePanel();

   int timerSec = MathMax(1, (UiRefreshMs + 999) / 1000);
   EventSetTimer(timerSec);

   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, 0x2A170F);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, 0x54422F);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, 0x53C800);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, 0x53C800);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, 0x4417FF);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, 0x4417FF);
   ChartSetInteger(0, CHART_SHOW_VOLUMES, false);
   ChartSetInteger(0, CHART_SHIFT, true);

   Print("✅ EA Initialized | Peak Balance: ", DoubleToString(g_MaxBalance,2));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
   EventKillTimer();
   DeletePanel();
   DeleteEntryLines();
   ObjectDelete(0, BTN_SEND);
   ObjectDelete(0, BTN_CANCEL);
   ChartRedraw();
}

bool IsManagedOrder(){
   if(OrderSymbol()!=Symbol()) return false;
   if(OrderType()>OP_SELL) return false;
   if(MagicNumber!=0 && OrderMagicNumber()!=MagicNumber) return false;
   return true;
}

void CheckEquityProtection(){
   if(g_TradingHalted && AutoResumeNextDay){
      int today = GetDayOfYear(TimeCurrent());
      if(g_HaltDayOfYear >= 0 && today != g_HaltDayOfYear){
         g_TradingHalted = false;
         g_HaltDayOfYear = -1;
      }
   }
   if(!EnableEquityProtection && !EnableFloatingLossProtection) return;

   double currentEquity = AccountEquity();
   double balance = AccountBalance();
   double floatingPnl = AccountProfit();
   double floatingLoss = (floatingPnl < 0.0) ? -floatingPnl : 0.0;

   if(currentEquity > g_MaxBalance) g_MaxBalance = currentEquity;

   double drawdown = (g_MaxBalance > 0.0) ? 100.0 * (g_MaxBalance - currentEquity) / g_MaxBalance : 0.0;
   double floatingLossPct = (balance > 0.0) ? (100.0 * floatingLoss / balance) : 0.0;
   bool ddHit = EnableEquityProtection && (drawdown >= MaxDrawdownPercent);
   bool flAmtHit = EnableFloatingLossProtection && (MaxFloatingLossAmount > 0.0) && (floatingLoss >= MaxFloatingLossAmount);
   bool flPctHit = EnableFloatingLossProtection && (MaxFloatingLossPercent > 0.0) && (floatingLossPct >= MaxFloatingLossPercent);

   if((ddHit || flAmtHit || flPctHit) && !g_ProtectionTriggered){
      g_ProtectionTriggered = true;
      CloseAllTrades(true);
      g_MaxBalance = AccountEquity();
      if(HaltTradingOnProtection){
         g_TradingHalted = true;
         g_HaltDayOfYear = GetDayOfYear(TimeCurrent());
      }
      g_ProtectionTriggered = false;
   }
}

void OnTick(){
   CheckEquityProtection();
   ManageOpenPositions();
}

void ManageOpenPositions(){
   RefreshRates();
   string sym = Symbol();
   double point = Point;
   int digits = Digits;
   double minStop = MarketInfo(sym, MODE_STOPLEVEL) * point;
   double bid = Bid;
   double ask = Ask;
   bool hasManagedPosition = false;

   for(int i=OrdersTotal()-1; i>=0; i--){
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsManagedOrder()) continue;
      hasManagedPosition = true;

      int ticket = OrderTicket();
      int type = OrderType();
      double openPrice = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      double volume = OrderLots();

      if(UseAutoSLTP && (sl <= 0.0 || tp <= 0.0)){
         double newSL = sl, newTP = tp;
         if(type==OP_BUY){
            if(sl <= 0.0) newSL = NormalizeDouble(openPrice - AutoStopLoss*point, digits);
            if(tp <= 0.0) newTP = NormalizeDouble(openPrice + AutoTakeProfit*point, digits);
         } else if(type==OP_SELL){
            if(sl <= 0.0) newSL = NormalizeDouble(openPrice + AutoStopLoss*point, digits);
            if(tp <= 0.0) newTP = NormalizeDouble(openPrice - AutoTakeProfit*point, digits);
         }
         if(type==OP_BUY){
            if(newSL>0.0 && (openPrice-newSL)<minStop) newSL=0.0;
            if(newTP>0.0 && (newTP-openPrice)<minStop) newTP=0.0;
         } else {
            if(newSL>0.0 && (newSL-openPrice)<minStop) newSL=0.0;
            if(newTP>0.0 && (openPrice-newTP)<minStop) newTP=0.0;
         }
         if(newSL>0.0 || newTP>0.0) ModifyPositionSLTP(ticket,newSL,newTP);

         OrderSelect(ticket, SELECT_BY_TICKET);
         sl = OrderStopLoss(); tp = OrderTakeProfit();
      }

      if(tp<=0.0) continue;

      double distanceToTP = MathAbs(tp-openPrice);
      double profitDistance = (type==OP_BUY) ? (bid-openPrice) : (openPrice-ask);

      if(EnablePartialClose){
         double pcTrigger = distanceToTP * PartialCloseTriggerTP / 100.0;
         if(profitDistance >= pcTrigger){
            if(!(ticket==g_LastPartialTicket && MathAbs(volume-g_LastPartialTicketLot)<0.0000001)){
               double closeLots = NormalizeDouble(volume * (PartialClosePercent/100.0),2);
               if(closeLots >= MarketInfo(sym, MODE_MINLOT)){
                  double closePrice = (type==OP_BUY)?bid:ask;
                  if(OrderClose(ticket, closeLots, closePrice, SlippagePoints, clrNONE)){
                     g_LastPartialTicket = ticket;
                     g_LastPartialTicketLot = volume-closeLots;
                  }
               }
            }
         }
      }

      if(g_BeRuntimeEnabled && (EnableBE || g_ForceBEStart)){
         double beTrigger = distanceToTP * BE_TP_Percent / 100.0;
         if(g_ForceBEStart || profitDistance >= beTrigger){
            int beOffset = g_UseStartBEButtonOffset ? StartBE_ButtonOffsetPoints : BE_OffsetPoints;
            double newSL = (type==OP_BUY) ? NormalizeDouble(openPrice+beOffset*point,digits)
                                          : NormalizeDouble(openPrice-beOffset*point,digits);
            bool shouldModify = false;
            if(type==OP_BUY){ if((sl<=0.0 || newSL>sl) && newSL<bid) shouldModify = true; }
            else           { if((sl<=0.0 || newSL<sl) && newSL>ask) shouldModify = true; }
            if(shouldModify) ModifyPositionSLTP(ticket,newSL,tp);
         }
      }

      if(g_TrailingRuntimeEnabled && EnableTrailingPoints){
         double startDistance = TS_StartPoints*point;
         if(profitDistance >= startDistance){
            if(type==OP_BUY){
               double newSL = NormalizeDouble(bid - TS_StopPoints*point, digits);
               if(sl < newSL - TS_StepPoints*point && newSL < bid) ModifyPositionSLTP(ticket,newSL,tp);
            } else {
               double newSL = NormalizeDouble(ask + TS_StopPoints*point, digits);
               if((sl<=0.0 || sl > newSL + TS_StepPoints*point) && newSL > ask) ModifyPositionSLTP(ticket,newSL,tp);
            }
         }
      }

      if(g_TrailingRuntimeEnabled && (EnableTrailingPercent || g_TSPercentStartOverridden || g_ForceTSStart)){
         double tsTrigger = distanceToTP * TS_StartTPPercent / 100.0;
         if(g_TSPercentStartOverridden || g_ForceTSStart || profitDistance >= tsTrigger){
            if(type==OP_BUY){
               double targetSL = NormalizeDouble(openPrice + (profitDistance*TS_ProfitLockPercent/100.0), digits);
               if(sl < targetSL - TS_StepPoints2*point && targetSL < bid) ModifyPositionSLTP(ticket,targetSL,tp);
            } else {
               double targetSL = NormalizeDouble(openPrice - (profitDistance*TS_ProfitLockPercent/100.0), digits);
               if((sl<=0.0 || sl > targetSL + TS_StepPoints2*point) && targetSL > ask) ModifyPositionSLTP(ticket,targetSL,tp);
            }
         }
      }
   }

   g_ForceBEStart = false;
   g_ForceTSStart = false;
   g_UseStartBEButtonOffset = false;
   if(!hasManagedPosition) g_TSPercentStartOverridden = false;
}

void ProcessPanelButtonStates(){
   if(ObjectFind(0, BTN_MODE) >= 0 && ObjectGetInteger(0, BTN_MODE, OBJPROP_STATE)){ ObjectSetInteger(0, BTN_MODE, OBJPROP_STATE, false); g_UseRiskMode=!g_UseRiskMode; UpdatePanelState(); return; }
   if(ObjectFind(0, BTN_BUY) >= 0 && ObjectGetInteger(0, BTN_BUY, OBJPROP_STATE)){ ObjectSetInteger(0, BTN_BUY, OBJPROP_STATE, false); HandleEntryClick(1); return; }
   if(ObjectFind(0, BTN_SELL) >= 0 && ObjectGetInteger(0, BTN_SELL, OBJPROP_STATE)){ ObjectSetInteger(0, BTN_SELL, OBJPROP_STATE, false); HandleEntryClick(-1); return; }

   if(ObjectFind(0, BTN_SEND) >= 0 && ObjectGetInteger(0, BTN_SEND, OBJPROP_STATE)){
      ObjectSetInteger(0, BTN_SEND, OBJPROP_STATE, false);
      if(g_PendingDirection != 0 && EntryLinesExist()){ g_PendingDirection=0; DeleteEntryLines(); }
      else { g_UsePendingMode=!g_UsePendingMode; if(g_PendingDirection!=0) CreateOrResetEntryLines(g_PendingDirection); }
      UpdatePanelState(); return;
   }

   if(ObjectFind(0, BTN_CANCEL) >= 0 && ObjectGetInteger(0, BTN_CANCEL, OBJPROP_STATE)){
      ObjectSetInteger(0, BTN_CANCEL, OBJPROP_STATE, false);
      if(g_PendingDirection!=0 && EntryLinesExist() && OpenPanelTrade(g_PendingDirection)){ g_PendingDirection=0; DeleteEntryLines(); }
      UpdatePanelState(); return;
   }

   if(EnableActionPanel && ObjectFind(0, BTN_CLOSE_ALL) >= 0 && ObjectGetInteger(0, BTN_CLOSE_ALL, OBJPROP_STATE)){ ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_STATE, false); CloseAllTrades(true); return; }
   if(EnableActionPanel && ObjectFind(0, BTN_CLOSE_BUY) >= 0 && ObjectGetInteger(0, BTN_CLOSE_BUY, OBJPROP_STATE)){ ObjectSetInteger(0, BTN_CLOSE_BUY, OBJPROP_STATE, false); CloseTradesByType(OP_BUY,true); return; }
   if(EnableActionPanel && ObjectFind(0, BTN_CLOSE_SELL) >= 0 && ObjectGetInteger(0, BTN_CLOSE_SELL, OBJPROP_STATE)){ ObjectSetInteger(0, BTN_CLOSE_SELL, OBJPROP_STATE, false); CloseTradesByType(OP_SELL,true); return; }

   if(EnableActionPanel && ObjectFind(0, BTN_START_TS) >= 0 && ObjectGetInteger(0, BTN_START_TS, OBJPROP_STATE)){
      ObjectSetInteger(0, BTN_START_TS, OBJPROP_STATE, false); g_TrailingRuntimeEnabled=true; g_TSPercentStartOverridden=true; g_ForceTSStart=true; ManageOpenPositions(); UpdatePanelState(); return;
   }
   if(EnableActionPanel && ObjectFind(0, BTN_START_BE) >= 0 && ObjectGetInteger(0, BTN_START_BE, OBJPROP_STATE)){
      ObjectSetInteger(0, BTN_START_BE, OBJPROP_STATE, false); g_BeRuntimeEnabled=true; g_UseStartBEButtonOffset=true; g_ForceBEStart=true; ManageOpenPositions(); UpdatePanelState(); return;
   }
}

void OnTimer(){
   if(!EnablePanel) return;
   ProcessPanelButtonStates();
   if(EntryLinesExist()) UpdateEntryLineLabels();
   else {
      ObjectDelete(0, LABEL_SL); ObjectDelete(0, LABEL_TP); ObjectDelete(0, LABEL_ENTRY);
      ObjectDelete(0, LINE_SL); ObjectDelete(0, LINE_TP); ObjectDelete(0, LINE_ENTRY);
      if(g_PendingDirection != 0){ g_PendingDirection = 0; UpdatePanelState(); }
   }
   ChartRedraw();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam){
   if(!EnablePanel) return;
   if(id==CHARTEVENT_OBJECT_ENDEDIT && sparam==EDIT_SIZE){
      double value = StrToDouble(ObjectGetString(0, EDIT_SIZE, OBJPROP_TEXT));
      if(g_UseRiskMode) g_RiskPercent = MathMax(0.01, value); else g_FixedLot = MathMax(0.01, value);
      UpdatePanelState(); UpdateEntryLineLabels(); return;
   }
   if(id==CHARTEVENT_OBJECT_DRAG && (sparam==LINE_SL || sparam==LINE_TP || sparam==LINE_ENTRY)){ UpdateEntryLineLabels(); return; }
   if(id==CHARTEVENT_CHART_CHANGE){ if(EntryLinesExist()) UpdateEntryLineLabels(); return; }
}

void HandleEntryClick(int direction){
   if(g_PendingDirection==direction && EntryLinesExist()){
      if(OpenPanelTrade(direction)){ g_PendingDirection=0; DeleteEntryLines(); UpdatePanelState(); }
      return;
   }
   g_PendingDirection = direction;
   CreateOrResetEntryLines(direction);
   UpdatePanelState();
}

bool OpenPanelTrade(int direction){
   if(g_TradingHalted) return false;

   RefreshRates();
   double sl = ObjectGetDouble(0, LINE_SL, OBJPROP_PRICE);
   double tp = ObjectGetDouble(0, LINE_TP, OBJPROP_PRICE);
   double marketPrice = (direction==1)?Ask:Bid;
   double entryPrice = marketPrice;
   if(g_UsePendingMode && ObjectFind(0, LINE_ENTRY)>=0) entryPrice = ObjectGetDouble(0, LINE_ENTRY, OBJPROP_PRICE);

   if(sl<=0.0 || tp<=0.0) return false;
   if(direction==1){ if(!(sl<entryPrice && tp>entryPrice)) return false; }
   else            { if(!(sl>entryPrice && tp<entryPrice)) return false; }

   double lots = CalculateOrderLots(entryPrice, sl);
   if(lots<=0.0) return false;

   int cmd = -1;
   if(g_UsePendingMode){
      if(direction==1) cmd = (entryPrice>=Ask) ? OP_BUYSTOP : OP_BUYLIMIT;
      else             cmd = (entryPrice<=Bid) ? OP_SELLSTOP : OP_SELLLIMIT;
   } else cmd = (direction==1) ? OP_BUY : OP_SELL;

   double price = (cmd==OP_BUY)?Ask:((cmd==OP_SELL)?Bid:entryPrice);
   int ticket = OrderSend(Symbol(), cmd, lots, price, SlippagePoints, sl, tp, "Panel", MagicNumber, 0, clrNONE);
   return (ticket>0);
}

double CalculateOrderLots(double entryPrice, double slPrice){
   if(!g_UseRiskMode) return NormalizeVolume(g_FixedLot);

   double riskMoney = AccountBalance() * (g_RiskPercent/100.0);
   if(riskMoney<=0.0) return 0.0;

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double stopDist  = MathAbs(entryPrice-slPrice);
   if(tickValue<=0.0 || tickSize<=0.0 || stopDist<=0.0) return 0.0;

   double riskPerLot = (stopDist/tickSize)*tickValue;
   if(riskPerLot<=0.0) return 0.0;

   return NormalizeVolume(riskMoney/riskPerLot);
}

double NormalizeVolume(double lots){
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double stepLot = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(stepLot<=0.0) stepLot=0.01;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots/stepLot)*stepLot;
   lots = NormalizeDouble(lots,2);
   if(lots<minLot) lots=minLot;
   return lots;
}

void CreateOrResetEntryLines(int direction){
   DeleteEntryLines();
   RefreshRates();
   double price = (direction==1) ? Ask : Bid;
   double slPrice = price;
   double tpPrice = price;

   if(direction==1){ slPrice -= AutoStopLoss*Point; tpPrice += AutoTakeProfit*Point; }
   else            { slPrice += AutoStopLoss*Point; tpPrice -= AutoTakeProfit*Point; }

   slPrice = NormalizeDouble(slPrice, Digits);
   tpPrice = NormalizeDouble(tpPrice, Digits);

   ObjectCreate(0, LINE_SL, OBJ_HLINE, 0, 0, slPrice);
   ObjectSetInteger(0, LINE_SL, OBJPROP_COLOR, clrTomato);
   ObjectSetInteger(0, LINE_SL, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, LINE_SL, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, LINE_SL, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, LINE_SL, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, LINE_SL, OBJPROP_BACK, true);

   ObjectCreate(0, LINE_TP, OBJ_HLINE, 0, 0, tpPrice);
   ObjectSetInteger(0, LINE_TP, OBJPROP_COLOR, clrMediumSeaGreen);
   ObjectSetInteger(0, LINE_TP, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, LINE_TP, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, LINE_TP, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, LINE_TP, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, LINE_TP, OBJPROP_BACK, true);

   if(g_UsePendingMode){
      ObjectCreate(0, LINE_ENTRY, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_COLOR, C'119,136,153');
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_STYLE, STYLE_DASHDOTDOT);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_SELECTED, true);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_BACK, true);
   }else{
      ObjectDelete(0, LINE_ENTRY);
      ObjectDelete(0, LABEL_ENTRY);
   }

   UpdateEntryLineLabels();
}

void DeleteEntryLines(){
   ObjectDelete(0, LINE_SL); ObjectDelete(0, LINE_TP); ObjectDelete(0, LINE_ENTRY);
   ObjectDelete(0, LABEL_SL); ObjectDelete(0, LABEL_TP); ObjectDelete(0, LABEL_ENTRY);
}

bool EntryLinesExist(){
   bool sltp = (ObjectFind(0, LINE_SL)>=0 && ObjectFind(0, LINE_TP)>=0);
   if(!sltp) return false;
   if(g_UsePendingMode) return (ObjectFind(0, LINE_ENTRY)>=0);
   return true;
}

double CalcLineMoney(double entryPrice, double linePrice, double lots){
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickValue<=0.0 || tickSize<=0.0 || lots<=0.0) return 0.0;
   double priceDistance = MathAbs(linePrice-entryPrice);
   return (priceDistance/tickSize) * tickValue * lots;
}

void EnsureLineLabel(const string name, color textColor){
   if(ObjectFind(0, name)>=0) return;
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 180);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 22);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TEXT, "...");
}

void UpdateEntryLineLabels(){
   if(!ShowEntryLineLabels){ ObjectDelete(0,LABEL_SL); ObjectDelete(0,LABEL_TP); ObjectDelete(0,LABEL_ENTRY); return; }
   if(!EntryLinesExist()) return;

   EnsureLineLabel(LABEL_SL, clrTomato);
   EnsureLineLabel(LABEL_TP, clrMediumSeaGreen);
   if(g_UsePendingMode) EnsureLineLabel(LABEL_ENTRY, C'119,136,153'); else ObjectDelete(0, LABEL_ENTRY);

   double sl = ObjectGetDouble(0, LINE_SL, OBJPROP_PRICE);
   double tp = ObjectGetDouble(0, LINE_TP, OBJPROP_PRICE);
   RefreshRates();
   double entry = (g_PendingDirection==-1)?Bid:Ask;
   if(g_UsePendingMode && ObjectFind(0,LINE_ENTRY)>=0) entry = ObjectGetDouble(0, LINE_ENTRY, OBJPROP_PRICE);

   double lots = g_UseRiskMode ? CalculateOrderLots(entry,sl) : NormalizeVolume(g_FixedLot);
   if(lots<=0.0) lots = NormalizeVolume(MarketInfo(Symbol(), MODE_MINLOT));

   double slMoney = CalcLineMoney(entry, sl, lots);
   double tpMoney = CalcLineMoney(entry, tp, lots);

   datetime t = TimeCurrent();
   int periodSec = (Period()>0)?(Period()*60):60;
   t += periodSec*2;

   int xSL=0,ySL=0,xTP=0,yTP=0,xEN=0,yEN=0;
   bool slXY = ChartTimePriceToXY(0,0,t,sl,xSL,ySL);
   bool tpXY = ChartTimePriceToXY(0,0,t,tp,xTP,yTP);
   bool enXY = true;
   if(g_UsePendingMode) enXY = ChartTimePriceToXY(0,0,t,entry,xEN,yEN);

   if(!slXY){ xSL=PanelX+8; ySL=PanelY+86; }
   if(!tpXY){ xTP=PanelX+8; yTP=PanelY+112; }
   if(g_UsePendingMode && !enXY){ xEN=PanelX+8; yEN=PanelY+99; }

   string accountCcy = AccountCurrency();
   string slTxt = StringFormat("SL: %s | -%.2f %s", DoubleToString(sl,Digits), slMoney, accountCcy);
   string tpTxt = StringFormat("TP: %s | +%.2f %s", DoubleToString(tp,Digits), tpMoney, accountCcy);
   double rr = (MathAbs(entry-sl)>0.0) ? (MathAbs(tp-entry)/MathAbs(entry-sl)) : 0.0;
   string enTxt = StringFormat("ENTRY: %s | RR: 1:%.1f", DoubleToString(entry,Digits), rr);

   ObjectSetInteger(0, LABEL_SL, OBJPROP_XDISTANCE, xSL+8);
   ObjectSetInteger(0, LABEL_SL, OBJPROP_YDISTANCE, ySL-10);
   ObjectSetInteger(0, LABEL_TP, OBJPROP_XDISTANCE, xTP+8);
   ObjectSetInteger(0, LABEL_TP, OBJPROP_YDISTANCE, yTP-10);
   if(g_UsePendingMode && ObjectFind(0, LABEL_ENTRY)>=0){
      ObjectSetInteger(0, LABEL_ENTRY, OBJPROP_XDISTANCE, xEN+8);
      ObjectSetInteger(0, LABEL_ENTRY, OBJPROP_YDISTANCE, yEN-10);
      ObjectSetString(0, LABEL_ENTRY, OBJPROP_TEXT, enTxt);
   }
   ObjectSetString(0, LABEL_SL, OBJPROP_TEXT, slTxt);
   ObjectSetString(0, LABEL_TP, OBJPROP_TEXT, tpTxt);
}

void CreatePanelButton(const string name,const string text,const int x,const int y,const int w,const int h,color bgColor,color textColor,const int fontSize){
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'71,85,105');
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}

void CreatePanel(){
   DeletePanel();
   ObjectCreate(0, PANEL_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YDISTANCE, PanelY);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XSIZE, 250);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YSIZE, 102);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_BGCOLOR, 0x2A170F);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_COLOR, 0x54422F);

   ObjectCreate(0, BTN_BUY, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_XDISTANCE, PanelX+6);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_YDISTANCE, PanelY+8);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_XSIZE, 88);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_YSIZE, 58);
   ObjectSetString(0, BTN_BUY, OBJPROP_TEXT, "BUY");
   ObjectSetInteger(0, BTN_BUY, OBJPROP_BGCOLOR, 0x53C800);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_COLOR, clrWhite);

   ObjectCreate(0, BTN_SELL, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_XDISTANCE, PanelX+155);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_YDISTANCE, PanelY+8);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_XSIZE, 88);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_YSIZE, 58);
   ObjectSetString(0, BTN_SELL, OBJPROP_TEXT, "SELL");
   ObjectSetInteger(0, BTN_SELL, OBJPROP_BGCOLOR, 0x4417FF);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_COLOR, clrWhite);

   ObjectCreate(0, BTN_MODE, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_XDISTANCE, PanelX+100);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_YDISTANCE, PanelY+8);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_XSIZE, 50);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_YSIZE, 25);

   ObjectCreate(0, EDIT_SIZE, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_XDISTANCE, PanelX+100);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_YDISTANCE, PanelY+38);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_XSIZE, 50);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_YSIZE, 28);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_COLOR, clrWhite);

   ObjectCreate(0, BTN_SEND, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_XDISTANCE, PanelX+6);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_YDISTANCE, PanelY+70);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_XSIZE, 116);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_YSIZE, 24);

   ObjectCreate(0, BTN_CANCEL, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_XDISTANCE, PanelX+127);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_YDISTANCE, PanelY+70);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_XSIZE, 116);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_YSIZE, 24);

   if(EnableActionPanel){
      int panel2Y = PanelY+108;
      ObjectCreate(0, PANEL2_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_XDISTANCE, PanelX);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_YDISTANCE, panel2Y);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_XSIZE, 250);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_YSIZE, 110);
      CreatePanelButton(BTN_CLOSE_ALL, "Close All", PanelX+6, panel2Y+8, 237, 28, 0x54422F, clrWhite, 11);
      CreatePanelButton(BTN_CLOSE_BUY, "Close Buy", PanelX+6, panel2Y+42, 116, 28, 0x54422F, clrWhite, 11);
      CreatePanelButton(BTN_CLOSE_SELL, "Close Sell", PanelX+127, panel2Y+42, 116, 28, 0x54422F, clrWhite, 11);
      CreatePanelButton(BTN_START_TS, "Start TS", PanelX+6, panel2Y+74, 116, 28, 0x1E90FF, clrWhite, 10);
      CreatePanelButton(BTN_START_BE, "Set BE", PanelX+127, panel2Y+74, 116, 28, 0xFF901E, clrWhite, 10);
   }
   UpdatePanelState();
}

void UpdatePanelState(){
   if(!EnablePanel) return;
   string modeLabel = g_UseRiskMode ? "Risk %" : "Lot";
   double value = g_UseRiskMode ? g_RiskPercent : g_FixedLot;
   ObjectSetString(0, BTN_MODE, OBJPROP_TEXT, modeLabel);
   ObjectSetString(0, EDIT_SIZE, OBJPROP_TEXT, DoubleToString(value,2));

   string buyText = (g_PendingDirection==1)?"BUY ✔":"BUY";
   string sellText = (g_PendingDirection==-1)?"SELL ✔":"SELL";
   bool isCancelMode = (g_PendingDirection!=0 && EntryLinesExist());
   string modeTradeText = isCancelMode ? "Cancel" : (g_UsePendingMode ? "Pending" : "Market");

   ObjectSetString(0, BTN_BUY, OBJPROP_TEXT, buyText);
   ObjectSetString(0, BTN_SELL, OBJPROP_TEXT, sellText);
   if(ObjectFind(0, BTN_SEND)>=0) ObjectSetString(0, BTN_SEND, OBJPROP_TEXT, modeTradeText);
   if(ObjectFind(0, BTN_CANCEL)>=0) ObjectSetString(0, BTN_CANCEL, OBJPROP_TEXT, "Send");
   if(EntryLinesExist()) UpdateEntryLineLabels();
   ChartRedraw();
}

void DeletePanel(){
   ObjectDelete(0, PANEL_BG); ObjectDelete(0, BTN_BUY); ObjectDelete(0, BTN_SELL);
   ObjectDelete(0, BTN_MODE); ObjectDelete(0, EDIT_SIZE); ObjectDelete(0, BTN_SEND); ObjectDelete(0, BTN_CANCEL);
   ObjectDelete(0, PANEL2_BG); ObjectDelete(0, BTN_CLOSE_ALL); ObjectDelete(0, BTN_CLOSE_BUY); ObjectDelete(0, BTN_CLOSE_SELL);
   ObjectDelete(0, BTN_START_TS); ObjectDelete(0, BTN_START_BE);
}

bool ModifyPositionSLTP(int ticket, double sl_new, double tp_new){
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;
   double sl = (sl_new>0.0)?sl_new:OrderStopLoss();
   double tp = (tp_new>0.0)?tp_new:OrderTakeProfit();
   return OrderModify(ticket, OrderOpenPrice(), sl, tp, 0, clrNONE);
}

void CloseAllTrades(bool filterByMagic){
   RefreshRates();
   for(int i=OrdersTotal()-1; i>=0; i--){
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderType()>OP_SELL) continue;
      if(filterByMagic && MagicNumber!=0 && OrderMagicNumber()!=MagicNumber) continue;
      double closePrice = (OrderType()==OP_BUY)?Bid:Ask;
      OrderClose(OrderTicket(), OrderLots(), closePrice, SlippagePoints, clrNONE);
      Sleep(200);
   }
}

void CloseTradesByType(int positionType, bool filterByMagic){
   RefreshRates();
   for(int i=OrdersTotal()-1; i>=0; i--){
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderType()!=positionType) continue;
      if(filterByMagic && MagicNumber!=0 && OrderMagicNumber()!=MagicNumber) continue;
      double closePrice = (OrderType()==OP_BUY)?Bid:Ask;
      OrderClose(OrderTicket(), OrderLots(), closePrice, SlippagePoints, clrNONE);
      Sleep(200);
   }
}
