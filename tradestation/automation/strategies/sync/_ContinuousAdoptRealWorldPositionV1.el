{File: _ContinuousAdoptRealWorldPositionV1.el}

{  _ContinuousAdoptRealWorldPositionV1:    
  
   Same as V0, except eliminates the use of the MachineTimeMillD DLL   
   ( replaces this with ComputerDateTime ) and also cancels open orders before   
   throwing the Recalc exception so that an automated strategy will continue   
   after the Recalc exception without requiring a user respond to screen prompt   
   to delete open orders.  Note that the screen prompt may appear, but does not   
   need to be responded to as the open orders are cancelled.  
   
USE: Insert on any chart along with any strategies where you want the strategies   
to continuously adopt the real-world position (if you are entering manual orders   
to change the position while the strategies are running).  This then allows one to    
continuously interact with a strategy using manual orders and the strategy will    
always stay in sync with the manual position.   
   
You MUST ENABLE ADOPT THE REAL-WORLD POSITION on the Automation Tab of the   
Strategy Properties Window.  You must also enable full automation.   
   
This can be used to test strategies in the Simulation Mode.   
   
   
APPROACH:  Forces all strategies inserted on the same chart to continuously    
Adopt the real-world position (if Adopt the real-world position is enabled   
on the Automation Tab of the Strategy Properties Window) by checking if    
there is a position mismatch between the strategy market position and the   
actual position returned by the Position Provider Object.  If the two are out   
of sync for more than the specified PosMisMatchTimeOutMS parameter, then this   
function throws a RecalcException, which causes all strategies on the chart to restart.   
Assuming that Adopt the real-world position is enabled on the Automation Tab   
this will cause the strategy to re-adopt the correct real-world position.   
   
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
                        
}   
   
using elsystem ;     
using tsdata.common ;    
using tsdata.trading ;     
     
inputs:  
	Note1_Run_Command ("Enable Run Command in the"), 
	Note2_Run_Command ("Properties Tab /General Tab"),   
	AccountID( "" ),				//  If AccountID is not entered, it uses the default provided by GetAccountID.  Sometimes this has problems.   
	PosMisMatchTimeOutMS( 15000 ),	//  Milliseconds since strategy vs actual position mismatch discovered to allow market position to remain out of sync with actual position   
	PrintDebug( false ) ;	        //  If true, the prints out data to the print log    
	   
	  
Variables:     
	MyAccountID( "" ),				//  Initialized at startup.  Used to speedup code.  
	CancelAllOrdersStr( "" ),		//  Initialized at startup.  Used to speedup code.  
	  
	Intrabarpersist RefreshTime( 0 ),	        //  Declare as IntrabarPersist to carry values over to the next price tick within a bar   
	Intrabarpersist ActualMP( 0 ),   
	  
	IntrabarPersist FirstRealTimeTick( false ),  
	  
	PositionsProvider PositionInfo( NULL ),   
	Timer MisMatchTimer( NULL ) ;	   
	  
   
//  This method is called whenever there is an actual position change.	     
method void PositionUpdate( Object PosProvide, PositionUpdatedEventArgs  PosUpdateArgs )  Begin     
   
	//  Only process position change events on real-time ticks, not historical bars.  
	//  Only run if all the strategies on the chart are being automated.  
	if GetAppInfo( aiRealTimeCalc ) = 1 and GetAppInfo( aiStrategyAuto ) = 1 then   
		begin   
	   
		//  Get the actual position using the Position Provider   
		if PositionInfo.Count >= 1 then    
			ActualMP = PositionInfo[0].Quantity    
		else   
			ActualMP = 0 ;   
			   
		//  If the strategy market position and current shares match the actual position   
		//  then CANCEL the timer (by setting it to NULL) which will cause a Recalc   
		//  exception to be thrown to cause all strategies inserted on the same chart   
		//  to recalculate ( same as turning the strategy off and then back on).  This   
		//  will cause the strategies to Adopt the current real-world position (assuming   
		//  this is enabled on the Automation Tab of the Strategy Properties Window).   
		if MarketPosition * CurrentShares = ActualMP then   
			MisMatchTimer = NULL    
			   
		//  We have found a strategy versus actual position mismatch.  So if the MisMatch Timer   
		//  is Null (meaning we have no timer running), then setup the timer to expire in    
		//  PosMisMatchTimeOutMS milliseconds.  If the Timer is not null, then do nothing, as it   
		//  will expire shortly (from the last time a position mismatch was discovered).   
		else if MisMatchTimer = NULL then   
			begin   
			   
			if PrintDebug then    
				print(" Date=", Date:0:0, "  Time=", Time:4:0, "  Position MISMATCH detected where Actual Pos = ", ActualMP:0:0,    
				  	"  Strategy Pos = ", Marketposition * CurrentShares:0:0, " detected at Date-Time=", ComputerDateTimeToString( ComputerDateTime ) ) ;   
				   
			MisMatchTimer = new elsystem.Timer;		   
			   
			MisMatchTimer.Interval  = PosMisMatchTimeOutMS ;   
			MisMatchTimer.AutoReset = false ;   
			MisMatchTimer.Enable    = true ;   
			   
			MisMatchTimer.elapsed += PosMisMatchTimeOut;		   
				   
			end ;   
			   
		end ;   
			   
end ;   
   
   
   
// Method called on PosMisMatchTimeOut event.   
method void PosMisMatchTimeOut( elsystem.Object sender, elsystem.TimerElapsedEventArgs args ) begin   
	   
	if PrintDebug then   
		print( NewLine, " RESTART strategy to ADOPT CORRECT REAL WORLD POSITION at time=", Time:4:0, " at Date-Time=",   
		       ComputerDateTimeToString( ComputerDateTime ), Newline ) ;   
	   
	//  FIRST: Cancel all open orders for this symbol/account  
	if MarketPosition * CurrentShares <> ActualMP then 
	Value1 = RunCommand( CancelAllOrdersStr ) ;  
	  
	//  SECOND: Throw (execute) a recalculation event to force all strategies to toggle off and then back on,    
	//  and restart and rerun, so they can adopt the current real-world position	   
	if MarketPosition * CurrentShares <> ActualMP then  
	Throw RecalculateException.Create(" Restart strategy to enter trade") ;   
	   
end;   
   
  
// Returns a string representation of a DateTime value, typically fetched used ComputerDateTime   
method String ComputerDateTimeToString( Double BaseDateTime )   
  
	//  The variables are strictly internal to this method  
	Variables:  
		Double Secs,  
		Double Mins,  
		Double Hours,  
		Double MyBaseDateTime,  
		  
		String HoldDate,  
		String DateTimeStr ;  
		  
Begin  
	  
	MyBaseDateTime = BaseDateTime ;  
	  
	HoldDate = ELDateToString( JulianToDate( IntPortion( MyBaseDateTime ) ) ) ;  
			  
	Secs  = FracPortion( MyBaseDateTime ) * ( 24 * 3600 ) ;  
	Hours = IntPortion( Secs / 3600 ) ;  
	Mins  = IntPortion ( ( Secs - ( Hours * 3600 ) ) / 60 ) ;  
	  
	Secs  = Secs - ( Hours * 3600 ) - ( Mins * 60 ) ;  
	  
	//  Assemble the date/time string		  
	DateTimeStr = HoldDate + " " + NumToStr( Hours, 0 ) + ":" ;  
	  
	//  If minutes are less than 10, insert a leading zero to keep 2 digit format MM  
	if Mins < 10 Then //  add leading zero  
		DateTimeStr = DateTimeStr + "0" ;    
		  
	DateTimeStr = DateTimeStr + NumToStr( Mins, 0 ) + ":" ;  
	  
	//  If seconds are less than 10, insert a leading zero to keep 2 digit format SS  
	if Secs < 10 Then //  add leading zero  
		DateTimeStr = DateTimeStr + "0" ;    
		  
	DateTimeStr = DateTimeStr + NumToStr( Secs, 0 ) ;  
	  
	Return DateTimeStr ;  
	  
End ;  
   
   
//  At strategy startup do the following initialization events one time, such   
//  as creating and defining the Positions Provider object to provide actual   
//  position information.   
Once  
	begin     
	  
	//  Define properties for the PositionsInfo object to tell it   
	//  what accounts and symbols to provide positions info on.   
	If AccountID = "" Then   
		MyAccountID = GetAccountID()    
	Else   
		MyAccountID = AccountID ;   
		  
	CancelAllOrdersStr = ".CAOSA " + Symbol + "," + MyAccountID ;  
	  
	//  Create the Position Provider object PositionsInfo	   
	PositionInfo = new PositionsProvider ;     
	   
	PositionInfo.Accounts += MyAccountID ;  
		 	   
	PositionInfo.Symbols += Symbol ;          //  set the symbol  
	PositionInfo.Realtime = true ;  	      //  set the position provider to run on real-time ticks   
	PositionInfo.Load     = true ;  		  //  load (activate) the positions provider with current positions info   
	PositionInfo.Updated += PositionUpdate ;  //  if any position changes occur, startup the PositionUpdate method   
	   
	if PrintDebug then   
		print( Newline, " *** CONTINUOUS ADOPT THE REAL-WORLD POSITION STARTING ***", NewLine ) ;   
	   
	end ;     
