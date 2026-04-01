//+------------------------------------------------------------------+
//|                        kalifx_Trade Manager.mq5                  |
//|                                                                  |
//|                        https://kalifxlab.com                     |
//+------------------------------------------------------------------+
#property copyright "COPYRIGHT 2025, KALIFX TRADE MANAGER"
#property link      "www.kalilfxlab.com"
#property version   "1.70"
#property description "Kalifx Trade Manager"
#property description "Smart order management panel,"
#property description "trailing, Breakeven & Partial close,"
#property description "Precision trades. Consistent profits."

#include <Trade/Trade.mqh>

CTrade trade;

// --- BE & Trailing Inputs
input string sepBE            = "=== BreakEven Settings ==="; //===
input bool   EnableBE         = true;     // Enable BE?
input double BE_TP_Percent    = 60.0;     // BE % of Take Profit
input int    BE_OffsetPoints  = 20;       // BE offset in points
input int    StartBE_ButtonOffsetPoints = 10; // Start BE button offset in points

// ==============================================
// 🔷 TRAILING STOP – POINT BASED
// ==============================================
input string sepTS1                = "=== Trailing Stop (Points-Based) ==="; //===
input bool   EnableTrailingPoints  = false;   // Enable point-based trailing?
input int    TS_StartPoints        = 300;     // Trailing start in points
input int    TS_StepPoints         = 50;      // Trailing step in points
input int    TS_StopPoints         = 150;     // Distance of SL from price (points)

// ==============================================
// 🔶 TRAILING STOP – PERCENT OF TP BASED
// ==============================================
input string sepTS2                = "=== Trailing Stop (% of TP Based) ==="; //===
input bool   EnableTrailingPercent = false;   // Enable trailing based on % of TP?
input double TS_StartTPPercent     = 60.0;    // Trailing start % of TP
input int    TS_StepPoints2        = 20;      // Step for moving SL (points)
input double TS_ProfitLockPercent  = 50.0;    // % of profit to lock in

// --- Auto SL/TP Inputs
input string sepAutoSLTP      = "=== Auto SL/TP Settings ==="; //===
input bool   UseAutoSLTP      = false;     // Automatically set SL/TP if missing?
input int    AutoStopLoss     = 300;       // Default SL in points
input int    AutoTakeProfit   = 600;       // Default TP in points

// ==============================================
// 🔹 PARTIAL CLOSE SETTINGS
// ==============================================
input string sepPartial              = "=== Partial Close Settings ==="; //===
input bool   EnablePartialClose      = false;   // Enable Partial Close?
input double PartialClosePercent     = 50.0;    // % of lots to close
input double PartialCloseTriggerTP   = 70.0;    // % of TP distance to trigger close

// --- Equity Protection Inputs
input string sepEquityProtect        = "=== Equity Protection ==="; //===
input bool   EnableEquityProtection  = false;   // Enable equity protection?
input double MaxDrawdownPercent      = 20.0;    // Max total drawdown (%)
input bool   EnableFloatingLossProtection = false; // Enable floating loss protection?
input double MaxFloatingLossAmount   = 100.0;   // Max floating loss in account currency
input double MaxFloatingLossPercent  = 10.0;    // Max floating loss (% of balance)
input bool   HaltTradingOnProtection = true;    // Stop new panel trades after protection trigger?
input bool   AutoResumeNextDay       = false;   // Auto resume panel trading on next day?

// --- Order Panel Inputs
input string sepPanel          = "=== Order Panel Settings ==="; //===
input bool   EnablePanel       = true;     // Show trading panel?
input bool   EnableActionPanel = true;     // Show management panel below main panel?
input bool   StartWithRiskMode = true;     // Start mode as Risk % (true) / Lot (false)
input double DefaultRiskPct    = 1.0;      // Default Risk % value
input double DefaultFixedLot   = 0.10;     // Default fixed lot value
input int    PanelX            = 10;       // Panel X offset
input int    PanelY            = 30;       // Panel Y offset
input int    UiRefreshMs       = 30;       // UI refresh timer in milliseconds
input bool   ShowEntryLineLabels = true;   // Show SL/TP tag boxes on chart?

// --- General Inputs
input int    MagicNumber       = 0;        // Magic number (0 = manage manual trades)
input int    SlippagePoints    = 20;       // Deviation in points for panel market orders

// --- Globals
double g_MaxBalance = 0.0;
bool   g_ProtectionTriggered = false;
bool   g_TradingHalted = false;
int    g_HaltDayOfYear = -1;

bool   g_UseRiskMode = true;
bool   g_UsePendingMode = false; // false=market, true=pending
double g_RiskPercent = 1.0;
double g_FixedLot    = 0.10;
bool   g_BeRuntimeEnabled = true;
bool   g_TrailingRuntimeEnabled = false;
bool   g_ForceBEStart = false;
bool   g_ForceTSStart = false;
bool   g_TSPercentStartOverridden = false;
bool   g_UseStartBEButtonOffset = false;

int    g_PendingDirection = 0; // 1=buy, -1=sell, 0=none

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

void CloseAllTrades(bool filterByMagic = true);
void CloseTradesByType(long positionType, bool filterByMagic = true);
void ManageOpenPositions();
void CreatePanelButton(const string name,
                       const string text,
                       const int x,
                       const int y,
                       const int w,
                       const int h,
                       color bgColor,
                       color textColor,
                       const int fontSize);

int GetDayOfYear(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.day_of_year;
}

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- EA settings
   g_MaxBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_UseRiskMode = StartWithRiskMode;
   g_RiskPercent = MathMax(0.01, DefaultRiskPct);
   g_FixedLot    = MathMax(0.01, DefaultFixedLot);
   g_BeRuntimeEnabled = EnableBE;
   g_TrailingRuntimeEnabled = (EnableTrailingPoints || EnableTrailingPercent);
   g_TSPercentStartOverridden = false;

   trade.SetExpertMagicNumber((uint)MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   if(EnablePanel)
      CreatePanel();

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   int timerMs = (UiRefreshMs < 16) ? 16 : UiRefreshMs;
   EventSetMillisecondTimer(timerMs);

   //--- Chart appearance
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY, false);

   ChartSetInteger(0, CHART_COLOR_BACKGROUND, 0x2A170F);   // background
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, 0x54422F);   // axes, text

   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, 0x53C800);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, 0x53C800);

   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, 0x4417FF);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, 0x4417FF);

   ChartSetInteger(0, CHART_SHOW_VOLUMES, false);

   // Activate chart shift on init
   ChartSetInteger(0, CHART_SHIFT, true);  // turn on chart shift

   PrintFormat("✅ EA Initialized | Peak Balance: %.2f", g_MaxBalance);
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeletePanel();
   DeleteEntryLines();
   ObjectDelete(0, BTN_SEND);
   ObjectDelete(0, BTN_CANCEL);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Check equity protection                                           |
//+------------------------------------------------------------------+
void CheckEquityProtection()
{
   if(g_TradingHalted && AutoResumeNextDay)
   {
      int today = GetDayOfYear(TimeCurrent());
      if(g_HaltDayOfYear >= 0 && today != g_HaltDayOfYear)
      {
         g_TradingHalted = false;
         g_HaltDayOfYear = -1;
         Print("✅ Trading auto-resumed for new day after protection halt.");
      }
   }

   if(!EnableEquityProtection && !EnableFloatingLossProtection)
      return;

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double floatingPnl = AccountInfoDouble(ACCOUNT_PROFIT);
   double floatingLoss = (floatingPnl < 0.0) ? -floatingPnl : 0.0;

   if(currentEquity > g_MaxBalance)
      g_MaxBalance = currentEquity;

   double drawdown = (g_MaxBalance > 0.0) ? 100.0 * (g_MaxBalance - currentEquity) / g_MaxBalance : 0.0;
   double floatingLossPct = (balance > 0.0) ? (100.0 * floatingLoss / balance) : 0.0;
   bool ddHit = EnableEquityProtection && (drawdown >= MaxDrawdownPercent);
   bool flAmtHit = EnableFloatingLossProtection && (MaxFloatingLossAmount > 0.0) && (floatingLoss >= MaxFloatingLossAmount);
   bool flPctHit = EnableFloatingLossProtection && (MaxFloatingLossPercent > 0.0) && (floatingLossPct >= MaxFloatingLossPercent);

   if((ddHit || flAmtHit || flPctHit) && !g_ProtectionTriggered)
   {
      g_ProtectionTriggered = true;
      string reason = "Unknown";
      if(ddHit)
         reason = StringFormat("Drawdown %.2f%% >= %.2f%%", drawdown, MaxDrawdownPercent);
      else if(flAmtHit)
         reason = StringFormat("Floating Loss %.2f >= %.2f", floatingLoss, MaxFloatingLossAmount);
      else if(flPctHit)
         reason = StringFormat("Floating Loss %.2f%% >= %.2f%%", floatingLossPct, MaxFloatingLossPercent);

      PrintFormat("🚨 Protection Triggered (%s) — closing all positions", reason);

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;

         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);

         if(trade.PositionClose(symbol))
            PrintFormat("✅ Closed position %I64u (%s %.2f lots)", ticket, symbol, volume);
         else
            PrintFormat("⚠️ Failed to close position %I64u (%s). Error=%d", ticket, symbol, GetLastError());

         Sleep(200);
      }

      Print("🛑 Protection executed.");
      g_MaxBalance = AccountInfoDouble(ACCOUNT_EQUITY);
      if(HaltTradingOnProtection)
      {
         g_TradingHalted = true;
         g_HaltDayOfYear = GetDayOfYear(TimeCurrent());
         Print("⛔ New panel trades halted by protection.");
      }

      g_ProtectionTriggered = false;
      PrintFormat("🔄 New peak equity set: %.2f.", g_MaxBalance);
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckEquityProtection();
   ManageOpenPositions();
}

//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   string sym = _Symbol;
   double point = _Point;
   int digits = (int)_Digits;

   double minStop = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;

   double Bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double Ask = SymbolInfoDouble(sym, SYMBOL_ASK);

   int total = PositionsTotal();
   bool hasManagedPosition = false;
   for(int idx = total - 1; idx >= 0; idx--)
   {
      ulong ticket = PositionGetTicket(idx);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      if(pos_symbol != sym)
         continue;

      long pos_magic = PositionGetInteger(POSITION_MAGIC);
      if(MagicNumber != 0 && (int)pos_magic != MagicNumber)
         continue;

      hasManagedPosition = true;

      long   pos_type   = PositionGetInteger(POSITION_TYPE);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl         = PositionGetDouble(POSITION_SL);
      double tp         = PositionGetDouble(POSITION_TP);
      double volume     = PositionGetDouble(POSITION_VOLUME);

      if(UseAutoSLTP && (sl <= 0.0 || tp <= 0.0))
      {
         double newSL = sl;
         double newTP = tp;

         if(pos_type == POSITION_TYPE_BUY)
         {
            if(sl <= 0.0)
               newSL = NormalizeDouble(openPrice - AutoStopLoss * point, digits);
            if(tp <= 0.0)
               newTP = NormalizeDouble(openPrice + AutoTakeProfit * point, digits);
         }
         else if(pos_type == POSITION_TYPE_SELL)
         {
            if(sl <= 0.0)
               newSL = NormalizeDouble(openPrice + AutoStopLoss * point, digits);
            if(tp <= 0.0)
               newTP = NormalizeDouble(openPrice - AutoTakeProfit * point, digits);
         }

         if(pos_type == POSITION_TYPE_BUY)
         {
            if(newSL > 0.0 && (openPrice - newSL) < minStop)
            {
               PrintFormat("❌ SL too close for BUY (ticket=%I64u)", ticket);
               newSL = 0.0;
            }
            if(newTP > 0.0 && (newTP - openPrice) < minStop)
            {
               PrintFormat("❌ TP too close for BUY (ticket=%I64u)", ticket);
               newTP = 0.0;
            }
         }
         else if(pos_type == POSITION_TYPE_SELL)
         {
            if(newSL > 0.0 && (newSL - openPrice) < minStop)
            {
               PrintFormat("❌ SL too close for SELL (ticket=%I64u)", ticket);
               newSL = 0.0;
            }
            if(newTP > 0.0 && (openPrice - newTP) < minStop)
            {
               PrintFormat("❌ TP too close for SELL (ticket=%I64u)", ticket);
               newTP = 0.0;
            }
         }

         if(newSL > 0.0 || newTP > 0.0)
         {
            bool ok = ModifyPositionSLTP(ticket, newSL, newTP);
            if(ok)
               PrintFormat("✅ Auto SL/TP set: ticket=%I64u SL=%.%df TP=%.%df", ticket, digits, newSL, digits, newTP);
            else
               PrintFormat("⚠️ Auto SL/TP failed for ticket=%I64u", ticket);
         }

         PositionSelectByTicket(ticket);
         sl = PositionGetDouble(POSITION_SL);
         tp = PositionGetDouble(POSITION_TP);
      }

      bool tpMissing = (tp <= 0.0);
      if(tpMissing)
         continue;

      double distanceToTP = MathAbs(tp - openPrice);
      double profitDistance = 0.0;
      if(pos_type == POSITION_TYPE_BUY)
         profitDistance = Bid - openPrice;
      else
         profitDistance = openPrice - Ask;

      if(EnablePartialClose)
      {
         double pcTrigger = distanceToTP * PartialCloseTriggerTP / 100.0;
         if(profitDistance >= pcTrigger)
         {
            static double lastPartialTicketLot = 0;
            if(volume != lastPartialTicketLot)
            {
               double closeLots = volume * (PartialClosePercent / 100.0);
               closeLots = NormalizeDouble(closeLots, 2);
               if(closeLots >= SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN))
               {
                  bool ok = trade.PositionClosePartial(ticket, closeLots);
                  if(ok)
                  {
                     PrintFormat("🟢 Partial close executed: ticket=%I64u closed %.2f lots (%.1f%%)", ticket, closeLots, PartialClosePercent);
                     lastPartialTicketLot = volume - closeLots;
                  }
                  else
                  {
                     PrintFormat("⚠️ Partial close failed for ticket=%I64u", ticket);
                  }
               }
            }
         }
      }

      if(g_BeRuntimeEnabled && (EnableBE || g_ForceBEStart))
      {
         double beTrigger = distanceToTP * BE_TP_Percent / 100.0;
         if(g_ForceBEStart || profitDistance >= beTrigger)
         {
            double newSL;
            int beOffset = g_UseStartBEButtonOffset ? StartBE_ButtonOffsetPoints : BE_OffsetPoints;
            if(pos_type == POSITION_TYPE_BUY)
               newSL = NormalizeDouble(openPrice + (beOffset * point), digits);
            else
               newSL = NormalizeDouble(openPrice - (beOffset * point), digits);

            bool shouldModify = false;
            if(pos_type == POSITION_TYPE_BUY)
            {
               if((sl <= 0.0 || newSL > sl) && newSL < Bid)
                  shouldModify = true;
            }
            else
            {
               if((sl <= 0.0 || newSL < sl) && newSL > Ask)
                  shouldModify = true;
            }

            if(shouldModify)
            {
               bool ok = ModifyPositionSLTP(ticket, newSL, tp);
               if(ok)
                  PrintFormat("✅ BE move: ticket=%I64u newSL=%.%df", ticket, digits, newSL);
               else
                  PrintFormat("⚠️ BE modify failed for ticket=%I64u", ticket);
            }
         }
      }

      if(g_TrailingRuntimeEnabled && EnableTrailingPoints)
      {
         double startDistance = TS_StartPoints * point;

         if(profitDistance >= startDistance)
         {
            if(pos_type == POSITION_TYPE_BUY)
            {
               double newSL = NormalizeDouble(Bid - TS_StopPoints * point, digits);

               if(sl < newSL - TS_StepPoints * point && newSL < Bid)
               {
                  bool ok = ModifyPositionSLTP(ticket, newSL, tp);
                  if(ok)
                     PrintFormat("🔵 TS Points BUY: ticket=%I64u SL=%.%df", ticket, digits, newSL);
               }
            }
            else
            {
               double newSL = NormalizeDouble(Ask + TS_StopPoints * point, digits);

               if((sl <= 0.0 || sl > newSL + TS_StepPoints * point) && newSL > Ask)
               {
                  bool ok = ModifyPositionSLTP(ticket, newSL, tp);
                  if(ok)
                     PrintFormat("🔵 TS Points SELL: ticket=%I64u SL=%.%df", ticket, digits, newSL);
               }
            }
         }
      }

      if(g_TrailingRuntimeEnabled && (EnableTrailingPercent || g_TSPercentStartOverridden || g_ForceTSStart))
      {
         double tsTrigger = distanceToTP * TS_StartTPPercent / 100.0;

         if(g_TSPercentStartOverridden || g_ForceTSStart || profitDistance >= tsTrigger)
         {
            if(pos_type == POSITION_TYPE_BUY)
            {
               double targetSL = openPrice + (profitDistance * TS_ProfitLockPercent / 100.0);
               targetSL = NormalizeDouble(targetSL, digits);

               if(sl < targetSL - TS_StepPoints2 * point && targetSL < Bid)
               {
                  bool ok = ModifyPositionSLTP(ticket, targetSL, tp);
                  if(ok)
                     PrintFormat("🔴 TS %% BUY: ticket=%I64u SL=%.%df", ticket, digits, targetSL);
               }
            }
            else
            {
               double targetSL = openPrice - (profitDistance * TS_ProfitLockPercent / 100.0);
               targetSL = NormalizeDouble(targetSL, digits);

               if((sl <= 0.0 || sl > targetSL + TS_StepPoints2 * point) && targetSL > Ask)
               {
                  bool ok = ModifyPositionSLTP(ticket, targetSL, tp);
                  if(ok)
                     PrintFormat("🔴 TS %% SELL: ticket=%I64u SL=%.%df", ticket, digits, targetSL);
               }
            }
         }
      }
   }

   g_ForceBEStart = false;
   g_ForceTSStart = false;
   g_UseStartBEButtonOffset = false;
   if(!hasManagedPosition)
      g_TSPercentStartOverridden = false; // reset Start TS override after trade cycle ends
}

//+------------------------------------------------------------------+
void ProcessPanelButtonStates()
{
   if(ObjectFind(0, BTN_MODE) >= 0 && ObjectGetInteger(0, BTN_MODE, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_MODE, OBJPROP_STATE, false);
      g_UseRiskMode = !g_UseRiskMode;
      UpdatePanelState();
      return;
   }

   if(ObjectFind(0, BTN_BUY) >= 0 && ObjectGetInteger(0, BTN_BUY, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_BUY, OBJPROP_STATE, false);
      HandleEntryClick(1);
      return;
   }

   if(ObjectFind(0, BTN_SELL) >= 0 && ObjectGetInteger(0, BTN_SELL, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_SELL, OBJPROP_STATE, false);
      HandleEntryClick(-1);
      return;
   }

   if(ObjectFind(0, BTN_SEND) >= 0 && ObjectGetInteger(0, BTN_SEND, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_SEND, OBJPROP_STATE, false);
      if(g_PendingDirection != 0 && EntryLinesExist())
      {
         g_PendingDirection = 0;
         DeleteEntryLines();
      }
      else
      {
         g_UsePendingMode = !g_UsePendingMode;
         if(g_PendingDirection != 0)
            CreateOrResetEntryLines(g_PendingDirection);
      }
      UpdatePanelState();
      return;
   }

   if(ObjectFind(0, BTN_CANCEL) >= 0 && ObjectGetInteger(0, BTN_CANCEL, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_CANCEL, OBJPROP_STATE, false);
      if(g_PendingDirection != 0 && EntryLinesExist() && OpenPanelTrade(g_PendingDirection))
      {
         g_PendingDirection = 0;
         DeleteEntryLines();
      }
      UpdatePanelState();
      return;
   }

   if(EnableActionPanel && ObjectFind(0, BTN_CLOSE_ALL) >= 0 && ObjectGetInteger(0, BTN_CLOSE_ALL, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_STATE, false);
      CloseAllTrades();
      return;
   }

   if(EnableActionPanel && ObjectFind(0, BTN_CLOSE_BUY) >= 0 && ObjectGetInteger(0, BTN_CLOSE_BUY, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_CLOSE_BUY, OBJPROP_STATE, false);
      CloseTradesByType(POSITION_TYPE_BUY);
      return;
   }

   if(EnableActionPanel && ObjectFind(0, BTN_CLOSE_SELL) >= 0 && ObjectGetInteger(0, BTN_CLOSE_SELL, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_CLOSE_SELL, OBJPROP_STATE, false);
      CloseTradesByType(POSITION_TYPE_SELL);
      return;
   }

   if(EnableActionPanel && ObjectFind(0, BTN_START_TS) >= 0 && ObjectGetInteger(0, BTN_START_TS, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_START_TS, OBJPROP_STATE, false);
      g_TrailingRuntimeEnabled = true;   // keep TS runtime enabled
      g_TSPercentStartOverridden = true; // override % trailing start threshold after click
      g_ForceTSStart = true;           // force immediate TS start once
      ManageOpenPositions();           // apply immediately on click
      UpdatePanelState();
      return;
   }

   if(EnableActionPanel && ObjectFind(0, BTN_START_BE) >= 0 && ObjectGetInteger(0, BTN_START_BE, OBJPROP_STATE))
   {
      ObjectSetInteger(0, BTN_START_BE, OBJPROP_STATE, false);
      g_BeRuntimeEnabled = true;  // ensure BE logic remains enabled
      g_UseStartBEButtonOffset = true;
      g_ForceBEStart = true;      // force immediate BE+offset application
      ManageOpenPositions();      // apply immediately on click
      UpdatePanelState();
      return;
   }
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(!EnablePanel)
      return;

   ProcessPanelButtonStates();

   if(EntryLinesExist())
      UpdateEntryLineLabels();
   else
   {
      ObjectDelete(0, LABEL_SL);
      ObjectDelete(0, LABEL_TP);
      ObjectDelete(0, LABEL_ENTRY);
      ObjectDelete(0, LINE_SL);
      ObjectDelete(0, LINE_TP);
      ObjectDelete(0, LINE_ENTRY);


      if(g_PendingDirection != 0)
      {
         g_PendingDirection = 0;
         UpdatePanelState();
      }
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(!EnablePanel)
      return;

   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == EDIT_SIZE)
   {
      double value = StringToDouble(ObjectGetString(0, EDIT_SIZE, OBJPROP_TEXT));
      if(g_UseRiskMode)
         g_RiskPercent = MathMax(0.01, value);
      else
         g_FixedLot = MathMax(0.01, value);
      UpdatePanelState();
      UpdateEntryLineLabels();
      return;
   }

   if(id == CHARTEVENT_OBJECT_DRAG && (sparam == LINE_SL || sparam == LINE_TP || sparam == LINE_ENTRY))
   {
      UpdateEntryLineLabels();
      return;
   }

   if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(EntryLinesExist())
         UpdateEntryLineLabels();
      return;
   }
}

//+------------------------------------------------------------------+
void HandleEntryClick(int direction)
{
   if(g_PendingDirection == direction && EntryLinesExist())
   {
      if(OpenPanelTrade(direction))
      {
         g_PendingDirection = 0;
         DeleteEntryLines();
         UpdatePanelState();
      }
      return;
   }

   g_PendingDirection = direction;
   CreateOrResetEntryLines(direction);
   UpdatePanelState();
}

//+------------------------------------------------------------------+
bool OpenPanelTrade(int direction)
{
   if(g_TradingHalted)
   {
      Print("⛔ Trading is halted by equity/floating-loss protection.");
      return false;
   }

   double sl = ObjectGetDouble(0, LINE_SL, OBJPROP_PRICE);
   double tp = ObjectGetDouble(0, LINE_TP, OBJPROP_PRICE);
   double marketPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryPrice = marketPrice;
   if(g_UsePendingMode && ObjectFind(0, LINE_ENTRY) >= 0)
      entryPrice = ObjectGetDouble(0, LINE_ENTRY, OBJPROP_PRICE);

   if(sl <= 0.0 || tp <= 0.0)
   {
      Print("⚠️ SL/TP lines are missing or invalid.");
      return false;
   }

   if(direction == 1)
   {
      if(!(sl < entryPrice && tp > entryPrice))
      {
         Print("⚠️ BUY requires SL below price and TP above price.");
         return false;
      }
   }
   else
   {
      if(!(sl > entryPrice && tp < entryPrice))
      {
         Print("⚠️ SELL requires SL above price and TP below price.");
         return false;
      }
   }

   double lots = CalculateOrderLots(entryPrice, sl);
   if(lots <= 0.0)
   {
      Print("❌ Could not calculate a valid lot size.");
      return false;
   }

   bool ok = false;
   if(g_UsePendingMode)
   {
      if(direction == 1)
      {
         if(entryPrice >= SymbolInfoDouble(_Symbol, SYMBOL_ASK))
            ok = trade.BuyStop(lots, entryPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Panel BuyStop");
         else
            ok = trade.BuyLimit(lots, entryPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Panel BuyLimit");
      }
      else
      {
         if(entryPrice <= SymbolInfoDouble(_Symbol, SYMBOL_BID))
            ok = trade.SellStop(lots, entryPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Panel SellStop");
         else
            ok = trade.SellLimit(lots, entryPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Panel SellLimit");
      }
   }
   else if(direction == 1)
      ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, "Panel Buy");
   else
      ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, "Panel Sell");

   if(!ok)
   {
      PrintFormat("❌ Order failed. retcode=%d comment=%s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
   }

   PrintFormat("✅ Panel order placed: %s %.2f lots | Entry=%.5f SL=%.5f TP=%.5f",
               (direction == 1 ? "BUY" : "SELL"), lots, entryPrice, sl, tp);
   return true;
}

//+------------------------------------------------------------------+
double CalculateOrderLots(double entryPrice, double slPrice)
{
   if(!g_UseRiskMode)
      return NormalizeVolume(g_FixedLot);

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (g_RiskPercent / 100.0);
   if(riskMoney <= 0.0)
      return 0.0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double stopDist  = MathAbs(entryPrice - slPrice);

   if(tickValue <= 0.0 || tickSize <= 0.0 || stopDist <= 0.0)
      return 0.0;

   double riskPerLot = (stopDist / tickSize) * tickValue;
   if(riskPerLot <= 0.0)
      return 0.0;

   double lots = riskMoney / riskPerLot;
   return NormalizeVolume(lots);
}

//+------------------------------------------------------------------+
double NormalizeVolume(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stepLot <= 0.0)
      stepLot = 0.01;

   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots / stepLot) * stepLot;
   lots = NormalizeDouble(lots, 2);

   if(lots < minLot)
      lots = minLot;

   return lots;
}

//+------------------------------------------------------------------+
void CreateOrResetEntryLines(int direction)
{
   DeleteEntryLines();

   double price = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double slPrice = price;
   double tpPrice = price;

   if(direction == 1)
   {
      slPrice -= AutoStopLoss * _Point;
      tpPrice += AutoTakeProfit * _Point;
   }
   else
   {
      slPrice += AutoStopLoss * _Point;
      tpPrice -= AutoTakeProfit * _Point;
   }

   slPrice = NormalizeDouble(slPrice, _Digits);
   tpPrice = NormalizeDouble(tpPrice, _Digits);

   ObjectCreate(0, LINE_SL, OBJ_HLINE, 0, 0, slPrice);
   ObjectSetInteger(0, LINE_SL, OBJPROP_COLOR, clrTomato);
   ObjectSetInteger(0, LINE_SL, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, LINE_SL, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, LINE_SL, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, LINE_SL, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, LINE_SL, OBJPROP_BACK, true);   // <-- send to back
   ObjectSetInteger(0, LINE_SL, OBJPROP_ZORDER, 1);


   ObjectCreate(0, LINE_TP, OBJ_HLINE, 0, 0, tpPrice);
   ObjectSetInteger(0, LINE_TP, OBJPROP_COLOR, clrMediumSeaGreen);
   ObjectSetInteger(0, LINE_TP, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, LINE_TP, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, LINE_TP, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, LINE_TP, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, LINE_TP, OBJPROP_BACK, true);   // <-- send to back
   ObjectSetInteger(0, LINE_TP, OBJPROP_ZORDER, 1);

   if(g_UsePendingMode)
   {
      ObjectCreate(0, LINE_ENTRY, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_COLOR, C'119,136,153');
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_STYLE, STYLE_DASHDOTDOT);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_SELECTED, true);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_BACK, true);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_ZORDER, 1);
   }
   else
   {
      ObjectDelete(0, LINE_ENTRY);
      ObjectDelete(0, LABEL_ENTRY);
   }

   UpdateEntryLineLabels();
}

//+------------------------------------------------------------------+
void DeleteEntryLines()
{
   ObjectDelete(0, LINE_SL);
   ObjectDelete(0, LINE_TP);
   ObjectDelete(0, LINE_ENTRY);
   ObjectDelete(0, LABEL_SL);
   ObjectDelete(0, LABEL_TP);
   ObjectDelete(0, LABEL_ENTRY);
}

//+------------------------------------------------------------------+
bool EntryLinesExist()
{
   bool sltp = (ObjectFind(0, LINE_SL) >= 0 && ObjectFind(0, LINE_TP) >= 0);
   if(!sltp)
      return false;
   if(g_UsePendingMode)
      return (ObjectFind(0, LINE_ENTRY) >= 0);
   return true;
}


//+------------------------------------------------------------------+
double CalcLineMoney(double entryPrice, double linePrice, double lots)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0.0 || tickSize <= 0.0 || lots <= 0.0)
      return 0.0;

   double priceDistance = MathAbs(linePrice - entryPrice);
   return (priceDistance / tickSize) * tickValue * lots;
}

//+------------------------------------------------------------------+
void EnsureLineLabel(const string name, color textColor)
{
   if(ObjectFind(0, name) >= 0)
      return;

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
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 999);
   ObjectSetString(0, name, OBJPROP_TEXT, "...");
}

//+------------------------------------------------------------------+
void UpdateEntryLineLabels()
{
   if(!ShowEntryLineLabels)
   {
      ObjectDelete(0, LABEL_SL);
      ObjectDelete(0, LABEL_TP);
      ObjectDelete(0, LABEL_ENTRY);
      return;
   }

   if(!EntryLinesExist())
      return;

   EnsureLineLabel(LABEL_SL, clrTomato);
   EnsureLineLabel(LABEL_TP, clrMediumSeaGreen);
   if(g_UsePendingMode)
      EnsureLineLabel(LABEL_ENTRY, C'119,136,153'); // LightSlateGray
   else
      ObjectDelete(0, LABEL_ENTRY);

   double sl = ObjectGetDouble(0, LINE_SL, OBJPROP_PRICE);
   double tp = ObjectGetDouble(0, LINE_TP, OBJPROP_PRICE);
   double entry = (g_PendingDirection == -1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(g_UsePendingMode && ObjectFind(0, LINE_ENTRY) >= 0)
      entry = ObjectGetDouble(0, LINE_ENTRY, OBJPROP_PRICE);

   double lots = g_UseRiskMode ? CalculateOrderLots(entry, sl) : NormalizeVolume(g_FixedLot);
   if(lots <= 0.0)
      lots = NormalizeVolume(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   double slMoney = CalcLineMoney(entry, sl, lots);
   double tpMoney = CalcLineMoney(entry, tp, lots);

   datetime t = TimeCurrent();
   int periodSec = PeriodSeconds(_Period);
   if(periodSec <= 0)
      periodSec = 60;
   t += (datetime)(periodSec * 2);

   int xSL = 0, ySL = 0, xTP = 0, yTP = 0, xEN = 0, yEN = 0;
   bool slXY = ChartTimePriceToXY(0, 0, t, sl, xSL, ySL);
   bool tpXY = ChartTimePriceToXY(0, 0, t, tp, xTP, yTP);
   bool enXY = true;
   if(g_UsePendingMode)
      enXY = ChartTimePriceToXY(0, 0, t, entry, xEN, yEN);

   if(!slXY)
   {
      xSL = PanelX + 8;
      ySL = PanelY + 86;
   }

   if(!tpXY)
   {
      xTP = PanelX + 8;
      yTP = PanelY + 112;
   }
   if(g_UsePendingMode && !enXY)
   {
      xEN = PanelX + 8;
      yEN = PanelY + 99;
   }

   string accountCcy = AccountInfoString(ACCOUNT_CURRENCY);
   string slTxt = StringFormat("SL: %s | -%.2f %s", DoubleToString(sl, _Digits), slMoney, accountCcy);
   string tpTxt = StringFormat("TP: %s | +%.2f %s", DoubleToString(tp, _Digits), tpMoney, accountCcy);
   double rr = (MathAbs(entry - sl) > 0.0) ? (MathAbs(tp - entry) / MathAbs(entry - sl)) : 0.0;
   string enTxt = StringFormat("ENTRY: %s | RR: 1:%.1f", DoubleToString(entry, _Digits), rr);

   int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int labelWidth = 200;
   int rightSafePadding = 20; // keep away from right price scale markers
   int minX = 10;
   int maxX = chartWidth - rightSafePadding - labelWidth;
   if(maxX < minX)
      maxX = minX;

   int xSLSafe = xSL + 8;
   int xTPSafe = xTP + 8;
   if(xSLSafe > maxX) xSLSafe = maxX;
   if(xTPSafe > maxX) xTPSafe = maxX;
   if(xSLSafe < minX) xSLSafe = minX;
   if(xTPSafe < minX) xTPSafe = minX;

   ObjectSetInteger(0, LABEL_SL, OBJPROP_XDISTANCE, xSLSafe);
   ObjectSetInteger(0, LABEL_SL, OBJPROP_YDISTANCE, ySL - 10);
   ObjectSetInteger(0, LABEL_TP, OBJPROP_XDISTANCE, xTPSafe);
   ObjectSetInteger(0, LABEL_TP, OBJPROP_YDISTANCE, yTP - 10);
   if(g_UsePendingMode && ObjectFind(0, LABEL_ENTRY) >= 0)
   {
      int xENSafe = xEN + 8;
      if(xENSafe > maxX) xENSafe = maxX;
      if(xENSafe < minX) xENSafe = minX;
      ObjectSetInteger(0, LABEL_ENTRY, OBJPROP_XDISTANCE, xENSafe);
      ObjectSetInteger(0, LABEL_ENTRY, OBJPROP_YDISTANCE, yEN - 10);
      ObjectSetString(0, LABEL_ENTRY, OBJPROP_TEXT, enTxt);
   }

   ObjectSetString(0, LABEL_SL, OBJPROP_TEXT, slTxt);
   ObjectSetString(0, LABEL_TP, OBJPROP_TEXT, tpTxt);
}

//+------------------------------------------------------------------+
void CreatePanelButton(const string name,
                       const string text,
                       const int x,
                       const int y,
                       const int w,
                       const int h,
                       color bgColor,
                       color textColor,
                       const int fontSize)
{
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
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1000);
}

//+------------------------------------------------------------------+
void CreatePanel()
{
   //--- delete existing objects
   ObjectDelete(0, PANEL_BG);
   ObjectDelete(0, BTN_BUY);
   ObjectDelete(0, BTN_SELL);
   ObjectDelete(0, BTN_MODE);
   ObjectDelete(0, EDIT_SIZE);
   ObjectDelete(0, BTN_SEND);
   ObjectDelete(0, BTN_CANCEL);
   ObjectDelete(0, PANEL2_BG);
   ObjectDelete(0, BTN_CLOSE_ALL);
   ObjectDelete(0, BTN_CLOSE_BUY);
   ObjectDelete(0, BTN_CLOSE_SELL);
   ObjectDelete(0, BTN_START_TS);
   ObjectDelete(0, BTN_START_BE);

   //--- panel background (slightly smaller for reduced padding)
   ObjectCreate(0, PANEL_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YDISTANCE, PanelY);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_XSIZE, 250);  // reduced from 250
   ObjectSetInteger(0, PANEL_BG, OBJPROP_YSIZE, 102);   // extra row for pending/cancel
   ObjectSetInteger(0, PANEL_BG, OBJPROP_BGCOLOR, 0x2A170F); // dark brown
   ObjectSetInteger(0, PANEL_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_COLOR, 0x54422F);    // border slightly lighter
   ObjectSetInteger(0, PANEL_BG, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, PANEL_BG, OBJPROP_ZORDER, 900);

   //--- BUY button (slightly closer to panel edge)
   ObjectCreate(0, BTN_BUY, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_XDISTANCE, PanelX + 6);   // from 8
   ObjectSetInteger(0, BTN_BUY, OBJPROP_YDISTANCE, PanelY + 8);   // from 10
   ObjectSetInteger(0, BTN_BUY, OBJPROP_XSIZE, 88);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_YSIZE, 58);
   ObjectSetString(0, BTN_BUY, OBJPROP_TEXT, "BUY");
   ObjectSetInteger(0, BTN_BUY, OBJPROP_BGCOLOR, 0x53C800); // bright green
   ObjectSetInteger(0, BTN_BUY, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_BORDER_COLOR, 0x3FA600);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_FONTSIZE, 16);
   ObjectSetInteger(0, BTN_BUY, OBJPROP_STATE, false);
   ObjectSetInteger(0, BTN_BUY,   OBJPROP_ZORDER, 1000);

   //--- SELL button
   ObjectCreate(0, BTN_SELL, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_XDISTANCE, PanelX + 155); // from 155
   ObjectSetInteger(0, BTN_SELL, OBJPROP_YDISTANCE, PanelY + 8);   // from 10
   ObjectSetInteger(0, BTN_SELL, OBJPROP_XSIZE, 88);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_YSIZE, 58);
   ObjectSetString(0, BTN_SELL, OBJPROP_TEXT, "SELL");
   ObjectSetInteger(0, BTN_SELL, OBJPROP_BGCOLOR, 0x4417FF); // purple
   ObjectSetInteger(0, BTN_SELL, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_BORDER_COLOR, 0x2C0F99);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_FONTSIZE, 16);
   ObjectSetInteger(0, BTN_SELL, OBJPROP_STATE, false);
   ObjectSetInteger(0, BTN_SELL,  OBJPROP_ZORDER, 1000);

   //--- MODE button
   ObjectCreate(0, BTN_MODE, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_XDISTANCE, PanelX + 100);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_YDISTANCE, PanelY + 8);   // from 10
   ObjectSetInteger(0, BTN_MODE, OBJPROP_XSIZE, 50);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_YSIZE, 25);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_BGCOLOR, 0x54422F);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_BORDER_COLOR, C'71,85,105');
   ObjectSetInteger(0, BTN_MODE, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, BTN_MODE, OBJPROP_STATE, false);
   ObjectSetInteger(0, BTN_MODE,  OBJPROP_ZORDER, 1000);

   //--- Lot size edit box
   ObjectCreate(0, EDIT_SIZE, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_XDISTANCE, PanelX + 100);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_YDISTANCE, PanelY + 38);  // from 40
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_XSIZE, 50);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_YSIZE, 28);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_BGCOLOR, C'30,41,59');
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_BORDER_COLOR, C'71,85,105');
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_ALIGN, ALIGN_CENTER);
   ObjectSetInteger(0, EDIT_SIZE, OBJPROP_ZORDER, 1000);

   //--- Pending/Market toggle button
   ObjectCreate(0, BTN_SEND, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_XDISTANCE, PanelX + 6);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_YDISTANCE, PanelY + 70);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_XSIZE, 116);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_YSIZE, 24);
   ObjectSetString(0, BTN_SEND, OBJPROP_TEXT, "Pending");
   ObjectSetInteger(0, BTN_SEND, OBJPROP_BGCOLOR, 0x1E90FF);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_BORDER_COLOR, 0x4417FF);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, BTN_SEND, OBJPROP_STATE, false);
   ObjectSetInteger(0, BTN_SEND,  OBJPROP_ZORDER, 1000);

   //--- Send button
   ObjectCreate(0, BTN_CANCEL, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_XDISTANCE, PanelX + 127);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_YDISTANCE, PanelY + 70);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_XSIZE, 116);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_YSIZE, 24);
   ObjectSetString(0, BTN_CANCEL, OBJPROP_TEXT, "Send");
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_BGCOLOR, 0x54422F);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_BORDER_COLOR, C'71,85,105');
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, BTN_CANCEL, OBJPROP_STATE, false);
   ObjectSetInteger(0, BTN_CANCEL,OBJPROP_ZORDER, 1000);

   if(EnableActionPanel)
   {
      int panel2Y = PanelY + 108;

      ObjectCreate(0, PANEL2_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_XDISTANCE, PanelX);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_YDISTANCE, panel2Y);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_XSIZE, 250);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_YSIZE, 110);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_BGCOLOR, 0x2A170F);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_COLOR, 0x54422F);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, PANEL2_BG, OBJPROP_ZORDER, 900);

      CreatePanelButton(BTN_CLOSE_ALL, "Close All", PanelX + 6, panel2Y + 8, 237, 28, 0x54422F, clrWhite, 11);
      CreatePanelButton(BTN_CLOSE_BUY, "Close Buy", PanelX + 6, panel2Y + 42, 116, 28, 0x54422F, clrWhite, 11);
      CreatePanelButton(BTN_CLOSE_SELL, "Close Sell", PanelX + 127, panel2Y + 42, 116, 28, 0x54422F, clrWhite, 11);
      CreatePanelButton(BTN_START_TS, "Start TS", PanelX + 6, panel2Y + 74, 116, 28, 0x1E90FF, clrWhite, 10);
      CreatePanelButton(BTN_START_BE, "Set BE", PanelX + 127, panel2Y + 74, 116, 28, 0xFF901E, clrWhite, 10);
   }

   //--- update panel state
   UpdatePanelState();
}
//+------------------------------------------------------------------+
void UpdatePanelState()
{
   if(!EnablePanel)
      return;

   string modeLabel = g_UseRiskMode ? "Risk %" : "Lot";
   double value = g_UseRiskMode ? g_RiskPercent : g_FixedLot;

   ObjectSetString(0, BTN_MODE, OBJPROP_TEXT, modeLabel);
   ObjectSetString(0, EDIT_SIZE, OBJPROP_TEXT, DoubleToString(value, 2));

   string buyText = (g_PendingDirection == 1) ? "BUY ✔" : "BUY";
   string sellText = (g_PendingDirection == -1) ? "SELL ✔" : "SELL";
   bool isCancelMode = (g_PendingDirection != 0 && EntryLinesExist());
   string modeTradeText = isCancelMode
      ? "Cancel"
      : (g_UsePendingMode ? "Pending" : "Market");
   string actionText = "Send";

   ObjectSetString(0, BTN_BUY, OBJPROP_TEXT, buyText);
   ObjectSetString(0, BTN_SELL, OBJPROP_TEXT, sellText);
   if(ObjectFind(0, BTN_SEND) >= 0)
   {
      ObjectSetString(0, BTN_SEND, OBJPROP_TEXT, modeTradeText);
      color modeBtnColor;
      color modeBtnBorder;

      // --- CANCEL mode (highest priority)
      if(isCancelMode)
      {
         modeBtnColor  = 0x54422F;
         modeBtnBorder = C'71,85,105';
      }
      // --- PENDING mode
      else if(g_UsePendingMode)
      {
         modeBtnColor  = 0x1E90FF;
         modeBtnBorder = 0x1E90FF;
      }
      // --- MARKET mode
      else
      {
         modeBtnColor  = 0x6B8E23;
         modeBtnBorder = 0x6B8E23;
      }
      ObjectSetInteger(0, BTN_SEND, OBJPROP_BGCOLOR, modeBtnColor);
      ObjectSetInteger(0, BTN_SEND, OBJPROP_BORDER_COLOR, modeBtnBorder);
   }
   if(ObjectFind(0, BTN_CANCEL) >= 0)
      ObjectSetString(0, BTN_CANCEL, OBJPROP_TEXT, actionText);

   if(EnableActionPanel && ObjectFind(0, BTN_START_TS) >= 0)
      ObjectSetString(0, BTN_START_TS, OBJPROP_TEXT, "Start TS");

   if(EnableActionPanel && ObjectFind(0, BTN_START_BE) >= 0)
      ObjectSetString(0, BTN_START_BE, OBJPROP_TEXT, "Set BE");

   if(EntryLinesExist())
      UpdateEntryLineLabels();

   ChartRedraw();
}

//+------------------------------------------------------------------+
void DeletePanel()
{
   ObjectDelete(0, PANEL_BG);
   ObjectDelete(0, BTN_BUY);
   ObjectDelete(0, BTN_SELL);
   ObjectDelete(0, BTN_MODE);
   ObjectDelete(0, EDIT_SIZE);
   ObjectDelete(0, BTN_SEND);
   ObjectDelete(0, BTN_CANCEL);
   ObjectDelete(0, PANEL2_BG);
   ObjectDelete(0, BTN_CLOSE_ALL);
   ObjectDelete(0, BTN_CLOSE_BUY);
   ObjectDelete(0, BTN_CLOSE_SELL);
   ObjectDelete(0, BTN_START_TS);
   ObjectDelete(0, BTN_START_BE);
}

//+------------------------------------------------------------------+
//| Modify position SL/TP via TRADE_ACTION_SLTP                      |
//+------------------------------------------------------------------+
bool ModifyPositionSLTP(ulong position_ticket, double sl_new, double tp_new)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_SLTP;
   request.position = position_ticket;
   request.symbol = _Symbol;
   request.magic = 0;
   request.sl = (sl_new > 0.0) ? sl_new : 0.0;
   request.tp = (tp_new > 0.0) ? tp_new : 0.0;
   request.type_filling = ORDER_FILLING_FOK;

   if(!OrderSend(request, result))
   {
      PrintFormat("OrderSend (SLTP) failed for ticket=%I64u. retcode=%d result_comment=%s",
                  position_ticket, result.retcode, result.comment);
      return false;
   }

   if(result.retcode == TRADE_RETCODE_DONE)
      return true;

   PrintFormat("ModifyPositionSLTP failed for ticket=%I64u retcode=%d comment=%s",
               position_ticket, result.retcode, result.comment);
   return false;
}

//+------------------------------------------------------------------+
void CloseAllTrades(bool filterByMagic)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      long pos_magic = (long)PositionGetInteger(POSITION_MAGIC);

      if(filterByMagic && MagicNumber != 0 && pos_magic != MagicNumber)
         continue;

      bool closed = trade.PositionClose(symbol);
      if(closed)
         PrintFormat("✅ Closed position %I64u on %s (%.2f lots)", ticket, symbol, volume);
      else
         PrintFormat("⚠️ Failed to close position %I64u (%s). Error=%d", ticket, symbol, GetLastError());

      Sleep(200);
   }
}

//+------------------------------------------------------------------+
void CloseTradesByType(long positionType, bool filterByMagic)
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;

      if((long)PositionGetInteger(POSITION_TYPE) != positionType)
         continue;

      long pos_magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(filterByMagic && MagicNumber != 0 && pos_magic != MagicNumber)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      bool closed = trade.PositionClose(symbol);

      if(closed)
         PrintFormat("✅ Closed %s position %I64u on %s (%.2f lots)",
                     positionType == POSITION_TYPE_BUY ? "BUY" : "SELL", ticket, symbol, volume);
      else
         PrintFormat("⚠️ Failed to close %s position %I64u (%s). Error=%d",
                     positionType == POSITION_TYPE_BUY ? "BUY" : "SELL", ticket, symbol, GetLastError());

      Sleep(200);
   }
}