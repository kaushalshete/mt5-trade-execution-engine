   #include <Trade/Trade.mqh>
   CTrade trade;
   
   #property strict
   #property version "1.05"
   
   // ===== OBJECT NAMES =====
   string BUY_BTN        = "BUY_BTN";
   string SELL_BTN       = "SELL_BTN";
   string CLOSE_BTN      = "CLOSE_BTN";
   string TRAIL_BTN      = "TRAIL_BTN";
   
   string RISK_BOX       = "RISK_BOX";
   string SL_BOX         = "SL_BOX";
   string TRAIL_BOX      = "TRAIL_BOX";
   string CLOSE_PCT_BOX  = "CLOSE_PCT_BOX";
   
   // ===== GLOBALS =====
   bool TrailingActive = false;
   
   //+------------------------------------------------------------------+
   //| Expert initialization                                            |
   //+------------------------------------------------------------------+
   int OnInit()
   {
      int xLeft = 20;
      int yBase = 75;
   
      // BUY / SELL (120 width each)
      CreateButton(BUY_BTN,  "BUY",  clrGreen, xLeft,        yBase, 120);
      CreateButton(SELL_BTN, "SELL", clrRed,   xLeft + 130,  yBase, 120);
   
      // SL
      CreateLabel("SL_LBL", "SL (POINTS)", xLeft, yBase + 45);
      CreateEditBox(SL_BOX, "150", xLeft, yBase + 80);   // more spacing
   
      // RISK
      CreateLabel("RISK_LBL", "RISK ($)", xLeft, yBase + 120);
      CreateEditBox(RISK_BOX, "10", xLeft, yBase + 155); // more spacing
   
      // PARTIAL CLOSE (250 width)
      CreateButton(CLOSE_BTN, "PARTIAL CLOSE", clrOrange, xLeft, yBase + 195, 250);
      CreateEditBox(CLOSE_PCT_BOX, "50", xLeft, yBase + 235);
   
      // TRAILING SL (250 width)
      CreateButton(TRAIL_BTN, "TRAILING SL", clrDodgerBlue, xLeft, yBase + 275, 250);
      CreateEditBox(TRAIL_BOX, "50", xLeft, yBase + 315);
   
      return INIT_SUCCEEDED;
   }
   
   
   //+------------------------------------------------------------------+
   void OnDeinit(const int reason)
   {
      ObjectDelete(0, BUY_BTN);
      ObjectDelete(0, SELL_BTN);
      ObjectDelete(0, CLOSE_BTN);
      ObjectDelete(0, TRAIL_BTN);
      ObjectDelete(0, RISK_BOX);
      ObjectDelete(0, SL_BOX);
      ObjectDelete(0, TRAIL_BOX);
      ObjectDelete(0, CLOSE_PCT_BOX);
   }
   
   //+------------------------------------------------------------------+
   void OnTick()
   {
      if(TrailingActive)
         ApplyTrailingStop();
   }
   
   //+------------------------------------------------------------------+
   void OnChartEvent(const int id,
                     const long &lparam,
                     const double &dparam,
                     const string &sparam)
   {
      if(id != CHARTEVENT_OBJECT_CLICK) return;
   
      if(sparam == BUY_BTN)
         ExecuteTrade(ORDER_TYPE_BUY);
   
      if(sparam == SELL_BTN)
         ExecuteTrade(ORDER_TYPE_SELL);
   
      if(sparam == CLOSE_BTN)
      {
         double pct = StringToDouble(ObjectGetString(0, CLOSE_PCT_BOX, OBJPROP_TEXT));
         if(pct > 0 && pct <= 100)
            ClosePartial(pct / 100.0);
      }
   
      if(sparam == TRAIL_BTN)
      {
         TrailingActive = true;
         Print("Trailing Stop Activated");
      }
   }
   
   //+------------------------------------------------------------------+
   void ExecuteTrade(ENUM_ORDER_TYPE type)
   {
      double riskUSD = StringToDouble(ObjectGetString(0, RISK_BOX, OBJPROP_TEXT));
      int    slPts   = (int)StringToInteger(ObjectGetString(0, SL_BOX, OBJPROP_TEXT));
   
      if(riskUSD <= 0 || slPts <= 0) return;
   
      double lot = CalculateLot(riskUSD, slPts);
      if(lot <= 0) return;
   
      double price = (type == ORDER_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
      double sl = (type == ORDER_TYPE_BUY)
                  ? price - slPts * _Point
                  : price + slPts * _Point;
   
      trade.SetDeviationInPoints(20);
   
      if(type == ORDER_TYPE_BUY)
         trade.Buy(lot, _Symbol, price, sl, 0);
      else
         trade.Sell(lot, _Symbol, price, sl, 0);
   }
   
   //+------------------------------------------------------------------+
   double CalculateLot(double riskUSD, int slPts)
   {
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick_value <= 0 || tick_size <= 0) return 0;
   
      double loss_per_lot = (slPts * _Point / tick_size) * tick_value;
      double lot = riskUSD / loss_per_lot;
   
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
      lot = MathFloor(lot / step) * step;
      return MathMax(minLot, MathMin(lot, maxLot));
   }
   
   //+------------------------------------------------------------------+
   void ClosePartial(double fraction)
   {
      if(!PositionSelect(_Symbol)) return;
   
      ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      double volume = PositionGetDouble(POSITION_VOLUME);
   
      double closeVol = volume * fraction;
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
      closeVol = MathFloor(closeVol / step) * step;
      if(closeVol < minLot) return;
   
      trade.PositionClosePartial(ticket, closeVol);
   }
   
   //+------------------------------------------------------------------+
   void ApplyTrailingStop()
   {
      if(!PositionSelect(_Symbol)) return;
   
      int trailPts = (int)StringToInteger(ObjectGetString(0, TRAIL_BOX, OBJPROP_TEXT));
      if(trailPts <= 0) return;
   
      long type = PositionGetInteger(POSITION_TYPE);
      double price = (type == POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                     : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
      double sl = PositionGetDouble(POSITION_SL);
      double newSL;
   
      if(type == POSITION_TYPE_BUY)
      {
         newSL = price - trailPts * _Point;
         if(newSL > sl)
            trade.PositionModify(_Symbol, newSL, 0);
      }
      else
      {
         newSL = price + trailPts * _Point;
         if(sl == 0 || newSL < sl)
            trade.PositionModify(_Symbol, newSL, 0);
      }
   }
   
   //+------------------------------------------------------------------+
   // UI HELPERS
   //+------------------------------------------------------------------+
   void CreateButton(string name, string text, color clr, int x, int y, int width)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, width); // 🔹 variable width
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 45);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
   
   void CreateEditBox(string name, string text, int x, int y)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 250); // 🔹 wider boxes
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 26);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
   
   
   void CreateLabel(string name, string text, int x, int y)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
