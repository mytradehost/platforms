{File: _ContinuousAdoptRealWorldPositionV0.el}

{  _ContinuousAdoptRealWorldPositionV0  
  
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
  
The PosMisMatchTimeOutMS parameter specifies the number of milliseconds allowed for  
the market position and the actual position to remain out of sync, before the  
recalc exception is thrown to restart all strategies.  A value of 1000 means  
to wait 1,000 milliseconds, or one second before correcting an out of sync  
market position.  It is recommended that you allow one(1) or several seconds  
for the out of sync condition to naturally self-correct, unless you are planning  
to frequently enter manual orders, or that your strategy must very quickly  
respond to changes in the market position (running on ticks).  
                       
}  
  
  DefineDLLFunc:  "GetMachineTime.dll", Float,"MachineTimeMillD";      
//DefineDLLFunc:  "20060224145637GetMachineTime.dll", Float,"MachineTimeMillD";  
  
using elsystem ;    
using tsdata.common ;   
using tsdata.trading ;    
    
inputs:    
  AccountID(  "");                //  If AccountID is not entered, it uses the default provided by GetAccountID.  Sometimes this has problems.  
Input:_____Timer____ ("Set Timer in Code"); 
variable:  PosMisMatchTimeOutMS(  600000); {10 min}  //  Milliseconds since strategy vs actual position mismatch discovered to allow market position to remain out of sync with actual position  
input:  PrintDebug(  false);            //  If true, the prints out data to the print log   
      
        
variables:    
  Intrabarpersist RefreshTime( 0 ),    //  Declare as IntrabarPersist to carry values over to the next price tick within a bar  
  Intrabarpersist TickTime   ( 0 ),  
  Intrabarpersist ActualMP   ( 0 ),  
      
  PositionsProvider PositionInfo( NULL ),  
  Timer MisMatchTimer           ( NULL );      
 
  
//  This method is called whenever there is an actual position change.        
method void PositionUpdate( Object PosProvide, PositionUpdatedEventArgs  PosUpdateArgs )   
 begin    
  
  //  Only process position change events on real-time ticks, not historical bars  
  if GetAppInfo( aiRealTimeCalc ) = 1  
    then begin  
      
   //  Get the actual position using the Position Provider  
     if PositionInfo.Count >= 1  
       then  ActualMP = PositionInfo[0].Quantity   
       else  ActualMP = 0 ;  
              
  // If the strategy market position and current shares match the actual position  
  //  then CANCEL the timer (by setting it to NULL) which will cause a Recalc  
  //  exception to be thrown to cause all strategies inserted on the same chart  
  //  to recalculate ( same as turning the strategy off and then back on).  This  
  //  will cause the strategies to Adopt the current real-world position (assuming  
  //  this is enabled on the Automation Tab of the Strategy Properties Window).  
     if MarketPosition * CurrentShares = ActualMP  
       then  MisMatchTimer = NULL   
              
   //  We have found a strategy versus actual position mismatch.  So if the MisMatch Timer  
   //  is Null (meaning we have no timer running), then setup the timer to expire in   
   //  PosMisMatchTimeOutMS milliseconds.  If the Timer is not null, then do nothing, as it  
   //  will expire shortly (from the last time a position mismatch was discovered).  
      else  
     if MisMatchTimer = NULL  
       then begin  
              
        TickTime = MachineTimeMillD ;  
                      
        if PrintDebug  then 
           print( " Date=", Date:0:0, "  Time=", Time:4:0,  
           "  Position MISMATCH detected where Actual Pos = ", ActualMP:0:0,   
           "  Strategy Pos = ", Marketposition * CurrentShares:0:0, 
           "  detected at MillDTime=", _MachineTimeMillDStr( TickTime )   ) ;  
                  
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
     print( NewLine,  
        " RESTART strategy to ADOPT CORRECT REAL WORLD POSITION at time=",Time:4:0,  
        " at MillDTime=", _MachineTimeMillDStr( MachineTimeMillD ),  
            Newline ) ;  
      
  //  Throw (execute) a recalculation event to force all strategies to toggle off and then back on,   
  //  and restart and rerun, so they can adopt the current real-world position      
    Throw RecalculateException.Create(" Restart strategy to enter trade") ;  
      
end;  
  
  
//  At strategy startup do the following initialization events one time, such  
//  as creating and defining the Positions Provider object to provide actual  
//  position information.  
Once  
  begin    
      
  //  Create the Position Provider object PositionsInfo      
   PositionInfo = new PositionsProvider ;    
      
  //  Define properties for the PositionsInfo object to tell it  
  //  what accounts and symbols to provide positions info on.  
   If AccountID = ""  
     then  PositionInfo.Accounts += GetAccountID()   
     else  PositionInfo.Accounts += AccountID ;  
              
   PositionInfo.Symbols += Symbol ;    
   PositionInfo.Realtime = true ;            //  set the position provider to run on real-time ticks  
   PositionInfo.Load     = true ;            //  load (activate) the positions provider with current positions info  
   PositionInfo.Updated += PositionUpdate ;  //  if any position changes occur, startup the PositionUpdate method  
      
   if PrintDebug then  
      print( Newline, " *** CONTINUOUS ADOPT THE REAL-WORLD POSITION STARTING ***",  
             NewLine ) ;  
      
end ;    
