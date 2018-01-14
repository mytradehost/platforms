{File: _ContinuousAdoptRealWorldPositionV5.el}

{  _ContinuousAdoptRealWorldPositionV5   
  
   Last updated: 7/11/2014 Afternoon  
     
   *** Reqires V9.1 Update 13 or later. ***  
     
   *** Same as the strategy_ContinuousAdoptRealWorldPositionV5, except it is an   
   Indicator so that it can run intrabar on Advanced Bar type charts ( Range, Momemtum, etc. )  
   while strategies can only run on bar Closes.  
        
     
USE: Insert on any chart along with any strategies where you want the strategies   
to continuously adopt the real-world position (If you are entering manual orders   
to change the position while the strategies are running).  This Then allows one to    
continuously interact with a strategy using manual orders and the strategy will    
always stay in sync with the manual position.   
   
You MUST ENABLE ADOPT THE REAL-WORLD POSITION on the Automation Tab of the   
Strategy Properties Window for all strategies inserted on the chart.  
You must also enable full automation for all strategies.  
   
This can be used to test strategies in the Simulation Mode.   
   
   
APPROACH:  Forces all strategies inserted on the same chart to continuously    
Adopt the real-world position (If Adopt the real-world position is enabled   
on the Automation Tab of the Strategy Properties Window) by checking If    
there is a position mismatch between the strategy market position and the   
actual position returned by the Position Provider Object and using the   
I_Market and I_CurrentShares Reserved Words.  If the two are out   
of sync for more than the specified PosMisMatchTimeOutMS parameter, this   
indicator issues a .Refresh Command Line Macro to force the chart to refresh,  
which causes all strategies on the chart to restart and to adopt the correct  
real-world position.  Assuming that Adopt the real-world position is enabled   
on the Automation Tab this will cause the strategy to re-adopt the correct   
real-world position.   
   
**** DO NOT SET TOO SMALL A PosMisMatchTimeOutMS Input or your strategy  
can enter a loop where it rapidly issues additional and incorrect orders. ****  
  
The PosMisMatchTimeOutMS parameter specifies the number of milliseconds allowed for  
the market position and the actual position to remain out of sync, before the  
recalc exception is thrown to restart all strategies.  A value of 15000 means  
to wait 15,000 milliseconds, or 15 seconds before correcting an out of sync  
market position.  It is recommended that you allow one(15) seconds  
for the out of sync condition to naturally self-correct, unless you are planning  
to frequently enter manual orders, or that your strategy must very quickly  
respond to changes in the market position (running on ticks).  **** If you specify  
too short a time period, this can result in your strategy issuing additional  
and incorrect orders. ****  This happens because the strategy thinks there is  
a position mismatch when there is no mismatch, and issues additional orders to  
correct the mismatch.  
  
*** Enable update intra-bar.  
                        
}   
  
using elsystem ;    
using elsystem.collections ;  
using strategy ;   
using tsdata.common ;    
using tsdata.marketdata ;    
using tsdata.trading ;     
  
     
Inputs:     
	AccountID(""),				//  If AccountID is not entered, it uses the default provided by GetAccountID.     
	  
	PosMisMatchTimeOutMS(                  15000),	//  Milliseconds since strategy vs actual position mismatch discovered   
	                                //  to allow market position to remain out of sync with actual position.    
	                                //  Per the above documentation, do NOT set this to a very small value.  
	                                  
	CancelAllOrders( False),	    //  If True, Then when a position mismatch is detected, all open orders for  
	                                //  this chart's symbol are first cancelled using a RunCommand before a  
	                                //  recalc exception is thrown to cause all strategies to re-adopt the correct  
	                                //  real-world position.    
	 
	____Note__________ ("negative value = off"),                                  
	EntryLimitToMkt( -2000),        //  Milliseconds after Limit price touched when order is converted to a Market order  
	                                //    A value of zero(0) creates a Market-if-touched type order  
	                                //    A negative value turns this off.  
	                                  
	ExitLimitToMkt(-2000),         //  Works same as the EntryLimitToMkt Input above  
	  
	PrintDebug(False) ;	        //  If True, prints out debug data to the Print Log    
	   
	  
Variables:     
	Intrabarpersist RefreshTime( 0 ),	        //  Declare as IntrabarPersist to carry values to next price tick    
	Intrabarpersist ActualMP( 0 ),   
	  
	IntrabarPersist Double LastTick( 0 ),  
	IntrabarPersist Double OldLastTick( 0 ),  
	  
	IntrabarPersist Double EntryLmtTrgrPrice( 0 ),	  
	IntrabarPersist Double OldEntryLmtTrgrPrice( 0 ),	  
	  
	IntrabarPersist Double ExitLmtTrgrPrice( 0 ),	  
	IntrabarPersist Double OldExitLmtTrgrPrice( 0 ),		  
  
	  
	IntrabarPersist RealTimeTicks( False ),  
	  
	Double OrderPrice( 0 ),  
	  
	MyAccountID( "" ),  
	OrdState( "" ),  
	  
	OrdersProvider MyOP( NULL ),  
	Order MyEntryLimitOrder( NULL ),  
	Order MyExitLimitOrder( NULL ),	  
	ReplaceTicket CnvtLimitToMktTicket( NULL ),		  
	PositionsProvider PositionInfo( NULL ),   
	Vector LimitOrders( NULL ),  
	  
	Timer EntryLmtPrcTouchTmr( NULL ),  
	Timer ExitLmtPrcTouchTmr( NULL ),	  
	Timer MisMatchTimer( NULL ) ;	   
	  
  
  
// Method called on OrdUpdated event.    
Method void OrdUpdated( elsystem.Object sender, OrderUpdatedEventArgs args )   
  
	Variables:  
		Int OrdCount,  
		Int Cnt,  
		Int EntryOrExit,  
		Double OrdLimitPrice,  
		String OrdState,  
		  
		Order MyOrder ;  
  
Begin    
  
	//  If we have real-time ticks arriving and the touch limit price timer is not running  
	If RealTimeTicks and ( EntryLmtPrcTouchTmr.Enable = False or ExitLmtPrcTouchTmr.Enable = False ) Then Begin  
	  
		If MyOP <> NULL Then  
			OrdCount = MyOP.Count   
		else  
			OrdCount = 0 ;  
				  
		If PrintDebug Then  
			Print( "OrderProvider Order Count=", OrdCount:0:0 ) ;  
		  
		  
		//  For each new limit order determine if its price should reset the limit trigger price  
		For Cnt = 0 to OrdCount - 1 Begin  
			  
			MyOrder = MyOP[Cnt] ;  
							  
			EntryOrExit = EntryOrExitOrder( MyOrder ) ;  
  
			If EntryOrExit > 0 and EntryLmtPrcTouchTmr.Enable = False and MyOrder.Type = OrderType.limit and   
			   ( MyEntryLimitOrder = NULL or ( MyOrder.OrderID <> MyEntryLimitOrder.OrderID ) ) Then Begin  
	  
	   			OrdLimitPrice = MyOrder.LimitPrice ;   
	   			  
	   			//  If we have valid real-time ticks arriving, the order price is not equal to the  
	   			//  the most recent limit trigger price, and the order price is closer to the last price tick  
	   			//  than the most recent limit trigger price, then ...  
	   			//  Note the EntryLmtTrgrPrice can be zero(0), as this is also the code by which we initially set it.  
	   			If OrdLimitPrice <> EntryLmtTrgrPrice and AbsValue( OrdLimitPrice - LastTick ) < AbsValue( EntryLmtTrgrPrice - LastTick ) Then Begin	   				  
	   				  
	   		    	OldEntryLmtTrgrPrice = EntryLmtTrgrPrice ;  
	   		   		EntryLmtTrgrPrice    = OrdLimitPrice ;  
	   		   		MyEntryLimitOrder    = MyOrder ;  
	   		   			  
					CheckForLimitPriceTouch() ;		   		   		  
						  
					If PrintDebug Then   
						Print( "ENTRY LimitTriggerPrice set to ", EntryLmtTrgrPrice:0:2 ) ;  
						  
				End ;  		   	  
	   					  
			End  
			Else If EntryOrExit < 0 and ExitLmtPrcTouchTmr.Enable = False and MyOrder.Type = OrderType.limit and   
			   ( MyExitLimitOrder = NULL or ( MyOrder.OrderID <> MyExitLimitOrder.OrderID ) ) Then Begin  
	  
	   			OrdLimitPrice = MyOrder.LimitPrice ;   
	   			  
	   			//  If we have valid real-time ticks arriving, the order price is not equal to the  
	   			//  the most recent limit trigger price, and the order price is closer to the last price tick  
	   			//  than the most recent limit trigger price, then ...  
	   			//  Note the ExitLmtTrgrPrice can be zero(0), as this is also the code by which we initially set it.  
	   			If OrdLimitPrice <> ExitLmtTrgrPrice and AbsValue( OrdLimitPrice - LastTick ) < AbsValue( ExitLmtTrgrPrice - LastTick ) Then Begin	   				  
	   				  
	   		    	OldExitLmtTrgrPrice = ExitLmtTrgrPrice ;  
	   		   		ExitLmtTrgrPrice    = OrdLimitPrice ;  
	   		   		MyExitLimitOrder    = MyOrder ;  
	   		   			  
					CheckForLimitPriceTouch() ;		   		   		  
						  
					If PrintDebug Then   
						Print( "EXIT LimitTriggerPrice set to ", ExitLmtTrgrPrice:0:2 ) ;  
						  
				End ;  		   	  
	   					  
			End ;  
			  
			  
		End ;    
	  
	End ;  
	  
End ;  
  
  
//  Return 1 for an entry order ( increase position ) and -1 for an exit order ( reduce position )   
Method Int EntryOrExitOrder( Order MyOrder ) Begin  
  
	If ( ActualMP >= 0 and ( MyOrder.Action = OrderAction.buy       or MyOrder.Action = OrderAction.buytocover ) ) OR   
	   ( ActualMP <= 0 and ( MyOrder.Action = OrderAction.sellshort or MyOrder.Action = OrderAction.sell ) ) Then  
	     
		Return 1  
		  
	Else  
	  
		Return -1 ;  
		  
End ;  
  
  
Method void CheckForLimitPriceTouch() Begin  
  
	If EntryLmtTrgrPrice > 0 and EntryLmtPrcTouchTmr.Enable = False Then Begin  
	  
		//  Test if the limit price has been touched or crossed by the last tick price  
		If Sign( OldLastTick - EntryLmtTrgrPrice ) <> Sign( LastTick - EntryLmtTrgrPrice ) Then Begin  
		  
			EntryLmtPrcTouchTmr.Enable = True ;  			//  Start timer  
			  
			If PrintDebug Then  
				Print( "Starting ENTRY Limit Price Touch Timeout at Time = ", DateTimeToString(ComputerDateTime) ) ;  
			  
		End ;  
						  
	End ;  
  
	If ExitLmtTrgrPrice > 0 and ExitLmtPrcTouchTmr.Enable = False Then Begin  
	  
		//  Test if the limit price has been touched or crossed by the last tick price  
		If Sign( OldLastTick - ExitLmtTrgrPrice ) <> Sign( LastTick - ExitLmtTrgrPrice ) Then Begin  
		  
			ExitLmtPrcTouchTmr.Enable = True ;  			//  Start timer  
			  
			If PrintDebug Then  
				Print( "Starting EXIT Limit Price Touch Timeout at Time = ", DateTimeToString(ComputerDateTime) ) ;  
			  
		End ;  
						  
	End ;  
  
End ;  
  
  
  
// Method called on the timeout of a the most recent ENTRY order limit price touch  
Method void EntryLimitPriceTouchTimeOut( elsystem.Object sender, elsystem.TimerElapsedEventArgs args )   
	  
	Variables:  
		Int OrdCount,  
		Int Cnt,  
		String OrdState,  
		Order MyOrder ;  
  
Begin  
	  
	//  Sweep through all orders and force any open limit order whose price is equal to the limit trigger  
	//  price to immediately fill so that we can handle multiple limit orders which may have the same limit price.    
	//  All limit orders which match the limit trigger price are forced to immediately fill by issuing a replace   
	//  ticket to convert them to market orders.   Note that the only orders the OrdersProvider receives are in the  
	//  received or partially filled state.  
	If MyOP <> NULL Then  
		OrdCount = MyOP.Count   
	Else  
		OrdCount = 0 ;  
	  
	For Cnt = 0 to OrdCount - 1 Begin  
	  
		MyOrder = MyOP[Cnt] ;  
		  
		If  MyOrder.Type = OrderType.Limit and   
		  ( MyOrder.Action = OrderAction.buy or MyOrder.Action = OrderAction.sellshort ) and  
		    MyOrder.LimitPrice = EntryLmtTrgrPrice Then Begin  
						  
			If PrintDebug Then  
				Print( NewLine, "*** Issuing Market Order to immediately fill ENTRY Limit order at Time = ", DateTimeToString(ComputerDateTime), NewLine ) ;  
				  
			MyOrder.Replace( CnvtLimitToMktTicket ) ;  //  Change to market order to immediately fill				  
				  
		End ;  
  
	End ;  
	  
	//  Clear the limit order and the limit trigger price for the next limit order  
	MyEntryLimitOrder = NULL ;  
	EntryLmtTrgrPrice = 0 ;  
		  
End ;  
  
  
// Method called on the timeout of a the most recent EXIT order limit price touch  
Method void ExitLimitPriceTouchTimeOut( elsystem.Object sender, elsystem.TimerElapsedEventArgs args )   
	  
	Variables:  
		Int OrdCount,  
		Int Cnt,  
		String OrdState,  
		Order MyOrder ;  
  
Begin  
	  
	//  Sweep through all orders and force any open limit order whose price is equal to the limit trigger  
	//  price to immediately fill so that we can handle multiple limit orders which may have the same limit price.    
	//  All limit orders which match the limit trigger price are forced to immediately fill by issuing a replace   
	//  ticket to convert them to market orders.   Note that the only orders the OrdersProvider receives are in the  
	//  received or partially filled state.  
	If MyOP <> NULL Then  
		OrdCount = MyOP.Count   
	Else  
		OrdCount = 0 ;  
	  
	For Cnt = 0 to OrdCount - 1 Begin  
	  
		MyOrder = MyOP[Cnt] ;  
		  
		If  MyOrder.Type = OrderType.Limit and   
		  ( MyOrder.Action = OrderAction.sell or MyOrder.Action = OrderAction.buytocover ) and  
		    MyOrder.LimitPrice = ExitLmtTrgrPrice Then Begin  
						  
			If PrintDebug Then  
				Print( NewLine, "*** Issuing Market Order to immediately fill EXIT Limit order at Time = ", DateTimeToString(ComputerDateTime), NewLine ) ;  
				  
			MyOrder.Replace( CnvtLimitToMktTicket ) ;  //  Change to market order to immediately fill				  
				  
		End ;  
  
	End ;  
	  
	//  Clear the limit order and the limit trigger price for the next limit order  
	MyExitLimitOrder = NULL ;  
	ExitLmtTrgrPrice = 0 ;  
		  
End ;  
  
  
//  This Method is called whenever there is an actual position change.  It is also called  
//  on each price tick whenever there is an open position ( long or short ).	     
Method void PositionUpdate( Object PosProvide, PositionUpdatedEventArgs  PosUpdateArgs )  Begin     
   
	If RealTimeTicks = False and LastBarOnChartEx and GetAppInfo( aiRealTimeCalc ) = 1 Then  
		RealTimeTicks = True ;  
   
	//  Real-time ticks are arriving: Only process position change events on real-time ticks,   
	//  not historical bars. Only run If all the strategies on the chart are being automated.  
	If RealTimeTicks Then Begin   
	   
		//  Get the actual position using the Position Provider   
		If PositionInfo.Count >= 1 Then    
			ActualMP = PositionInfo[0].Quantity    
		Else   
			ActualMP = 0 ;  //  Reset to zero for the next entry  
			   
		//  If the strategy market position and current shares match the actual position   
		//  Then DISABLE the timer, Else start the Timer to allow some time for the  
		//  position mismatch to correct.  If the Timer Then times out a recalc    
		//  exception will be thrown to cause all strategies inserted on the same chart   
		//  to recalculate ( same as turning the strategy off and Then back on).  This   
		//  will cause the strategies to the correctly Adopt the current real-world position   
		//  (assuming this is enabled on the Automation Tab of the Strategy Properties Window).   
		If I_MarketPosition * I_CurrentShares = ActualMP Then   
			MisMatchTimer.Enable = False     
			   
		//  We have found a strategy versus actual position mismatch.  So If the MisMatch Timer   
		//  is Null (meaning we have no timer running), Then setup the timer to expire in    
		//  PosMisMatchTimeOutMS milliseconds.  If the Timer is not null, Then do nothing, as it   
		//  will expire shortly (from the last time a position mismatch was discovered).   
		Else If MisMatchTimer.Enable = False Then Begin   
			   
			If PrintDebug Then    
				Print(" Date=", Date:0:0, "  Time=", Time:4:0, "  Position MISMATCH detected where Actual Pos = ",   
				      ActualMP:0:0, "  Strategy Pos = ", I_Marketposition * I_CurrentShares:0:0, " detected at Date-Time=",   
				      DateTimeToString( ComputerDateTime ) ) ;   
				   
			MisMatchTimer.Enable = True ;   
				   
		End ;   
					   
	End ;  
			   
End ;   
   
  
  
// Method called on PosMisMatchTimeOut event.   
Method void PosMisMatchTimeOut( elsystem.Object sender, elsystem.TimerElapsedEventArgs args ) Begin   
	   
	If PrintDebug Then   
		print( NewLine, " RESTART strategy to ADOPT CORRECT REAL WORLD POSITION at time=", Time:4:0, " at Date-Time=",   
		       DateTimeToString( ComputerDateTime ), Newline ) ;   
	   
	//  FIRST: Cancel all open orders for this symbol/account before throwing the recalc exception  
	If CancelAllOrders Then  
		OrderTicket.CancelAllOrders( Symbol, MyAccountID, True ) ;  
	  
	//  SECOND: Force chart to refresh so that strategy can adopt the correct position  
	Value1 = RunCommand( ".Refresh" ) ;  
	   
end;   
  
   
//  At strategy startup do the following initialization events one time, such   
//  as creating and defining the Timer and Positions Provider Objects to provide actual   
//  position information.   
Once Begin     
			  
	//  Define the account.  If there is user input it overrides the default Account ID.  
	//  This account ID is used by the PositionsProvider and in the RunCommand.  
	If AccountID = "" Then   
		MyAccountID = GetAccountID()    
	Else   
		MyAccountID = AccountID ;   
		  
	  
	//  Create the Position Mismatch Timer Object  
	MisMatchTimer           = new Timer;		   
	MisMatchTimer.Interval  = PosMisMatchTimeOutMS ;   
	MisMatchTimer.AutoReset = False ;   
	MisMatchTimer.Enable    = False ;   
	MisMatchTimer.elapsed  += PosMisMatchTimeOut;		   
	  
	  
	//  Create the Entry Limit order touch price timer  
	EntryLmtPrcTouchTmr           = new Timer;		   
	EntryLmtPrcTouchTmr.Interval  = EntryLimitToMkt ;   
	EntryLmtPrcTouchTmr.AutoReset = False ;   
	EntryLmtPrcTouchTmr.Enable    = False ;   
	EntryLmtPrcTouchTmr.elapsed  += EntryLimitPriceTouchTimeOut;		   
  
  
	//  Create the Exit Limit order touch price timer  
	ExitLmtPrcTouchTmr           = new Timer;		   
	ExitLmtPrcTouchTmr.Interval  = ExitLimitToMkt ;   
	ExitLmtPrcTouchTmr.AutoReset = False ;   
	ExitLmtPrcTouchTmr.Enable    = False ;   
	ExitLmtPrcTouchTmr.elapsed  += ExitLimitPriceTouchTimeOut;		   
  
	  
	//  Create the Orders Provider  
	MyOP           = new OrdersProvider;    
	MyOP.Accounts += MyAccountID;    
	MyOP.Symbols  += Symbol;    
	MyOP.States   += "received,partiallyfilled" ;  
	MyOP.Realtime  = True;    
	MyOP.updated  += OrdUpdated; 		   
	MyOP.Load      = True;    
  
	  
	//  Create the Position Provider object PositionsInfo	   
	PositionInfo           = new PositionsProvider ;     
	PositionInfo.Accounts += MyAccountID ;  
	PositionInfo.Symbols  += Symbol ;         //  set the symbol  
	PositionInfo.Realtime  = True ;  	      //  set the position provider to run on real-time ticks   
	PositionInfo.Load      = True ;  		  //  load (activate) the positions provider with current positions info   
	PositionInfo.Updated  += PositionUpdate ; //  If any position changes occur, startup the PositionUpdate Method		  
   
   
 	//  Create the Replace Ticket to convert open limit orders to market orders to force an immediate fill  
	CnvtLimitToMktTicket      = new ReplaceTicket ;  
	CnvtLimitToMktTicket.Type = OrderType.market ;  
	  
	If GetAppInfo( aiMacroConf ) = 1 or GetAppInfo( aiMacroEnabled ) = 0 Then  
		RaiseRunTimeError( "Enable RunCommand Macros with Confirmation OFF on General Tab of Format Indicator Window" ) ;  
	  
	If OrderTicketBase.OrderPlacementEnabled = False Then  
		RaiseRunTimeError( "Enable Order Objects on General Tab of Format Indicator Window" ) ;  
		  
	If PrintDebug Then   
		print( Newline, " *** CONTINUOUS ADOPT THE REAL-WORLD POSITION V5 STARTING ***", NewLine ) ;   
	   
End ;     
  
  
//  MAIN code  
  
  
//  Design check for RealTimeTicks to only call GetAppInfo once as this is computationally expensive  
If LastBarOnChartEx and RealTimeTicks = False and GetAppInfo( aiRealTimeCalc ) = 1 Then Begin  
	RealTimeTicks = True ;  
	If PrintDebug Then  
		Print( "Real Time Ticks arriving" ) ;  
End ;  
	  
//  Get the most recent real-time tick price and check for a limit price touch  
If RealTimeTicks Then Begin  
	OldLastTick = LastTick ;  
	LastTick    = Close ;  
	CheckForLimitPriceTouch() ;	  
End ;  
