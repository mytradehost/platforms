{File: _ContinuousAdoptRealWorldPositionV2.el}

{  _ContinuousAdoptRealWorldPositionV2:    
  
   Last Updated: 5/17/2012  
     
   Same as V1, but:  
     
   1) Adds check if Automation, Adopt the real-world position, and   
      RunCommand are ALL enabled, else issues an error message and aborts the  
      strategy.    
     
   2) Also, has an input to specify whether all open orders are cancelled  
      upon restart, so it can work with strategies which requires existing orders  
      be left in place.     
     
   3) If the AcountID is blank, uses GetAccountID to obtain the account ID.  
     
   4) Does not set the Timer object to NULL to shut down the timer.  Rather  
      it just disables the Timer to stop it, and re-enables it to start it.    
     
   5) Minor code cleanup / streamlining.  
     
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
actual position returned by the Position Provider Object.  if the two are out   
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
respond to changes in the market position (running on ticks).  **** if you specify  
too short a time period, this can result in your strategy issuing additional  
and incorrect orders. ****  This happens because the strategy thinks there is  
a position mismatch when there is no mismatch, and issues additional orders to  
correct the mismatch.  
                        
}   
   
using elsystem ;    
using strategy ;   
using tsdata.common ;    
using tsdata.trading ;     
  
     
inputs:     
	AccountID( "" ),				//  if AccountID is not entered, it uses the default provided by GetAccountID.     
	  
	PosMisMatchTimeOutMS( 15000 ),	//  Milliseconds since strategy vs actual position mismatch discovered   
	                                //  to allow market position to remain out of sync with actual position.    
	                                //  Per the above documentation, do NOT set this to a very small value.  
	                                  
	CancelAllOrders( false ),	    //  if true, then when a position mismatch is detected, all open orders for  
	                                //  this chart's symbol are first cancelled using a RunCommand before a  
	                                //  recalc exception is thrown to cause all strategies to re-adopt the correct  
	                                //  real-world position.    
	                                  
	PrintDebug( false ) ;	        //  if true, prints out debug data to the Print Log    
	   
	  
Variables:     
	Intrabarpersist CancelAllOrdersStr( "" ),	//  Initialized at startup.  Used to speedup code.  
	  
	Intrabarpersist RefreshTime( 0 ),	        //  Declare as IntrabarPersist to carry values to next price tick    
	Intrabarpersist ActualMP( 0 ),   
	  
	IntrabarPersist RealTimeTicks( false ),  
	  
	MyAccountID( "" ),  
	  
	StrategyHost MyStratHost( NULL  ),			  
	PositionsProvider PositionInfo( NULL ),   
	Timer MisMatchTimer( NULL ) ;	   
	  
   
//  This Method is called whenever there is an actual position change.  It is also called  
//  on each price tick whenever there is an open position ( long or short ).	     
Method void PositionUpdate( Object PosProvide, PositionUpdatedEventArgs  PosUpdateArgs )  Begin     
   
	if RealTimeTicks = false and GetAppInfo( aiRealTimeCalc ) = 1 then  
		RealTimeTicks = true   
   
	//  Real-time ticks are arriving: Only process position change events on real-time ticks,   
	//  not historical bars. Only run if all the strategies on the chart are being automated.  
	else begin   
	   
		//  Get the actual position using the Position Provider   
		if PositionInfo.Count >= 1 then    
			ActualMP = PositionInfo[0].Quantity    
		else   
			ActualMP = 0 ;   
			   
		//  if the strategy market position and current shares match the actual position   
		//  then DISABLE the timer, else start the Timer to allow some time for the  
		//  position mismatch to correct.  if the Timer then times out a recalc    
		//  exception will be thrown to cause all strategies inserted on the same chart   
		//  to recalculate ( same as turning the strategy off and then back on).  This   
		//  will cause the strategies to the correctly Adopt the current real-world position   
		//  (assuming this is enabled on the Automation Tab of the Strategy Properties Window).   
		if MarketPosition * CurrentShares = ActualMP then   
			MisMatchTimer.Enable = False     
			   
		//  We have found a strategy versus actual position mismatch.  So if the MisMatch Timer   
		//  is Null (meaning we have no timer running), then setup the timer to expire in    
		//  PosMisMatchTimeOutMS milliseconds.  if the Timer is not null, then do nothing, as it   
		//  will expire shortly (from the last time a position mismatch was discovered).   
		else if MisMatchTimer.Enable = False then begin   
			   
			if PrintDebug then    
				Print(" Date=", Date:0:0, "  Time=", Time:4:0, "  Position MISMATCH detected where Actual Pos = ",   
				      ActualMP:0:0, "  Strategy Pos = ", Marketposition * CurrentShares:0:0, " detected at Date-Time=",   
				      ComputerDateTimeToString( ComputerDateTime ) ) ;   
				   
			MisMatchTimer.Enable = True ;   
				   
		end ;   
			   
	end ;  
			   
end ;   
   
   
   
// Method called on PosMisMatchTimeOut event.   
Method void PosMisMatchTimeOut( elsystem.Object sender, elsystem.TimerElapsedEventArgs args ) begin   
	   
	if PrintDebug then   
		print( NewLine, " RESTART strategy to ADOPT CORRECT REAL WORLD POSITION at time=", Time:4:0, " at Date-Time=",   
		       ComputerDateTimeToString( ComputerDateTime ), Newline ) ;   
	   
	//  FIRST: Cancel all open orders for this symbol/account before throwing the recalc exception  
	if CancelAllOrders then  
		Value1 = RunCommand( CancelAllOrdersStr ) ;  
	  
	//  SECOND: Throw (execute) a recalculation event to force all strategies to toggle off and then back on,    
	//  and restart and rerun, so they can adopt the current real-world position	   
	Throw RecalculateException.Create(" Restart strategy to enter trade") ;   
	   
end;   
   
  
// Returns a string representation of a DateTime value, typically fetched used ComputerDateTime   
Method String ComputerDateTimeToString( Double BaseDateTime )   
  
	//  The variables are strictly internal to this Method  
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
	  
	//  if minutes are less than 10, insert a leading zero to keep 2 digit format MM  
	if Mins < 10 Then //  add leading zero  
		DateTimeStr = DateTimeStr + "0" ;    
		  
	DateTimeStr = DateTimeStr + NumToStr( Mins, 0 ) + ":" ;  
	  
	//  if seconds are less than 10, insert a leading zero to keep 2 digit format SS  
	if Secs < 10 Then //  add leading zero  
		DateTimeStr = DateTimeStr + "0" ;    
		  
	DateTimeStr = DateTimeStr + NumToStr( Secs, 0 ) ;  
	  
	Return DateTimeStr ;  
	  
End ;  
   
   
//  At strategy startup do the following initialization events one time, such   
//  as creating and defining the Timer and Positions Provider Objects to provide actual   
//  position information.   
Once begin     
		  
	//  Create the strategy host object to verify the strategy automation settings  
	MyStratHost         = new StrategyHost;  
	MyStratHost.Connect = true;  
	  
	if PrintDebug then  
		Print( " Strat Adopt Real-World Pos=", MyStratHost.Automation.AdoptRealWorldPosition.ToString(),   
		       " and Automated Trading with Confirmation=", MyStratHost.Automation.Mode.ToString() ) ;  
	  
	        
	//  Verify the strategy can adopt the real-world position and has automation fully enabled.  
	if MyStratHost.Automation.AdoptRealWorldPosition = False or   
	   MyStratHost.Automation.Mode <> AutomationMode.fullnoconfirm then  
	       
	     RaiseRunTimeError( "Enable Full Automation & Adopt Real-World Position on Automation Tab" ) ;  
	  
	  
	//  Clear the Strategy Host Object as we no longer need it, as the Strategy Host Object can  
	//  sometimes cause downstream issues.  
	MyStratHost = Null ;  
	  
	//  Verify that RunCommand is enabled for the strategy.  
	if GetAppInfo( aiMacroEnabled ) <> 1 then   
		RaiseRunTimeError( "Must enable Macros on General Tab of the Strategy Properties Window" ) ;  
		  
	//  Define the account.  if there is user input it overrides the default Account ID.  
	//  This account ID is used by the PositionsProvider and in the RunCommand.  
	if AccountID = "" Then   
		MyAccountID = GetAccountID()    
	Else   
		MyAccountID = AccountID ;   
		  
	//  Create the Command Line Macro string to cancel all open orders for this symbol  
	CancelAllOrdersStr = ".CAOSA" + " " + Symbol + "," + MyAccountID ;  
	  
	  
	//  Create the Position Mismatch Timer Object  
	MisMatchTimer = new elsystem.Timer;		   
		  
	MisMatchTimer.Interval  = PosMisMatchTimeOutMS ;   
	MisMatchTimer.AutoReset = false ;   
	MisMatchTimer.Enable    = false ;   
	MisMatchTimer.elapsed  += PosMisMatchTimeOut;		   
	  
	  
	//  Create the Position Provider object PositionsInfo	   
	PositionInfo = new PositionsProvider ;     
	   
	PositionInfo.Accounts += MyAccountID ;  
	PositionInfo.Symbols  += Symbol ;         //  set the symbol  
	PositionInfo.Realtime  = true ;  	      //  set the position provider to run on real-time ticks   
	PositionInfo.Load      = true ;  		  //  load (activate) the positions provider with current positions info   
	PositionInfo.Updated  += PositionUpdate ; //  if any position changes occur, startup the PositionUpdate Method		  
   
	if PrintDebug then   
		print( Newline, " *** CONTINUOUS ADOPT THE REAL-WORLD POSITION STARTING ***", NewLine ) ;   
	   
end ;     
  
  
//  MAIN code  
  
//  Design check for RealTimeTicks to only call GetAppInfo once as this is computationally expensive  
if LastBarOnChart and RealTimeTicks = false and GetAppInfo( aiRealTimeCalc ) = 1 then  
	RealTimeTicks = true ;  
