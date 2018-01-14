{File: _ContinuousAdoptRealWorldPositionMK.el}

 
{      
Strategy:        _ContinuousAdoptRealWorldPositionMK:    
  
Updated:         12/7/13  
 
Description:     This is a re-write of ContinuousAdoptRealWorldPositionV2 with the following changes: 
     
    1) If the AcountID is eliminated as an input parameter.  GetAccountID is used internally to obtain the account ID.  
        
    2) A minimum number of seconds of mismatch is required (recommend 2 seconds) before debug statements log the mismatch, 
       since almost all new positions result in a mismatch for a fraction of a second, and these do not need to be logged.        
        
    3) The number of seconds of position mismatch that will trigger a strategy restart is specified in seconds rather than 
       milliseconds, using input parameter MaxMisMatchSeconds.  Fractions of a second are allowed, such as MaxMisMatchSeconds = 7.5 
                       
    4) Code cleanup / streamlining.  
     
Purpose (reproduced from ContinuousAdoptRealWorldPositionV2) 
 
Insert on any chart along with any strategies where you want the strategies   
to continuously adopt the real-world position (if you are entering manual orders   
to change the position while the strategies are running).  This then allows one to    
continuously interact with a strategy using manual orders and the strategy will    
always stay in sync with the manual position.   
   
You MUST - 
1. Enable "Adopt the real-world position", Properties of All strategies, Automation Tab. 
2. Enable full automation, no NO confirmation. 
3. Enable macros with NO confirmation. 
   
This can be used to test strategies in the Simulation Mode.   
   
   
If there is a position mismatch between the strategy market position and the   
actual position returned by the Position Provider Object for more than  
PosMisMatchTimeOutMS milliseconds, then strategy generates a RecalcException,  
which causes all strategies on the chart to restart.   
 
When strategies restart, they will adopt the real-world position. 
   
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
 	____Note_1______________ ("Enable Adopt the real-world position"), 
	____Note_2______________ ("Enable full automation, no NO confirmation"), 
	____Note_2______________ ("Enable macros with NO confirmation"),    
    MaxMisMatchSeconds(15),               { maximum seconds RT position and strategy position can be out of sync before } 
                                          { strategy is forced to adopt real time position,  Recommended value = 15 }     
    LogMisMatchSeconds(2),                                                                                                                              
    CancelAllOrders(true),                { if true, cancell all open orders before restarting strategy }                                      
    Debug(true) ;                         { print debugging information }   
       
      
Variables:     
    CancelAllOrdersStr( "" ),             { Holds cancel all orders instruction, as text string }       
    Intrabarpersist RefreshTime(0),       { Declare as IntrabarPersist to carry values to next price tick } 
    Intrabarpersist ActualMP(0),   
    Intrabarpersist LastBar(false),     
    Intrabarpersist MisMatch(false),  
    string AccountID(GetAccountID()),  
      
    StrategyHost MyStratHost( NULL  ),              
    PositionsProvider PositionInfo( NULL ),   
    StopWatch MisMatchStopWatch( NULL ), 
    Timer MisMatchTimer ( Null );       
      
 
Method override void InitializeComponent() 
    begin 
 
        MyStratHost         = new StrategyHost;  
        MyStratHost.Connect = true;  
         
        if Debug then  
            Print( " Strat Adopt Real-World Pos=", MyStratHost.Automation.AdoptRealWorldPosition.ToString(),   
               " and Automated Trading with Confirmation=", MyStratHost.Automation.Mode.ToString() ) ;  
      
        { failure conditions: } 
        { 1. Strategy Formatting - Automation - Adopt Real World Position NOT Enabled } 
        { 2. Strategy Properties for All - Automate execution with confirmation OFF NOT enabled }  
        { 3. Strategy Macros NOT enabled }    
         
        Condition1 = MyStratHost.Automation.AdoptRealWorldPosition = False; 
        Condition2 = MyStratHost.Automation.Mode <> AutomationMode.FullNoConfirm; 
        Condition3 = GetAppInfo( aiMacroEnabled ) <> 1; 
        Condition4 = GetAppInfo(aiMacroConf) = 1; 
         
        if Condition1 or Condition2 then  
             RaiseRunTimeError( "Enable Full Automation & Adopt Real-World Position on Automation Tab" ) ;           
          
        { Strategy Host Object no longer needed.  Keeping it can cause downstream issues } 
            MyStratHost = Null ;  
      
        If Condition3 then RaiseRunTimeError( "Strategy Properties for All - General - Enable RunCommand and order placement objects" ) ;  
        If Condition4 then RaiseRunTimeError( "Strategy Properties for ALL = General = Macro confirmation should be OFF"); 
                      
        { Create the Command Line Macro string to cancel all open orders for this symbol } 
            CancelAllOrdersStr = ".CAOSA" + " " + Symbol + "," + AccountID ;  
           
        MisMatchStopWatch      = new elsystem.StopWatch;  
 
        MisMatchTimer           = new elsystem.Timer;                    
        MisMatchTimer.Interval  = MaxMisMatchSeconds * 1000 ;   
        MisMatchTimer.AutoReset = false ;   
        MisMatchTimer.Enable    = false ;   
        MisMatchTimer.elapsed  += PosMisMatchTimeOut;                
 
        PositionInfo            = new PositionsProvider ;           
        PositionInfo.Accounts  += AccountID ;  
        PositionInfo.Symbols   += Symbol ;          
        PositionInfo.Realtime   = true ;                        //  set the position provider to run on real-time ticks   
        PositionInfo.Load       = true ;                        //  load (activate) the positions provider with current positions info   
        PositionInfo.Updated   += PositionUpdate ;              //  if any position changes occur, startup the PositionUpdate Method          
       
        if Debug then   
            print( _Bar, "  START CONTINUOUS ADOPT THE REAL-WORLD POSITION" );   
 
    end; 
                   
     
Method void PositionUpdate( Object PosProvide, PositionUpdatedEventArgs  PosUpdateArgs )   
{ Called whenever there is an actual position change, AND on each price tick whenever there is an open position ( long or short ) }     
{ AND, whenever the inside bid/ask price or the inside bid/ask size changes } 
    Begin     
   
        { PositionUpdate will trigger on the second historical bar loaded into the chart } 
        { Therefore, PrositionUpdate will trigger only occur on real-time ticks, and not other historical bars } 
        { Any PositionUpdate triggers AFTER LastBarOnChart is reached must therefore be a result of real time data activity } 
        { It is therefore not necessary to test for the presence of RealTimeData, as is done in ContinuousAdoptRealWorldPositionV2 } 
        { Doing so, also delays the processing of this code in some synthetic bars, such as Kase bars, since RealTimeData can not be } 
        { detected in these bars until the close of the bar FOLLOWING the LastBarOnChart.  If there is not much price movement, this }  
        { delay in the recognition of RealTimeData may be unacceptably long } 
         
        if LastBar then begin        
             
            if PositionInfo.Count > 0 then    
                ActualMP = PositionInfo[0].Quantity    
            else   
                ActualMP = 0 ;   
             
            MisMatch = MarketPosition * CurrentShares <> ActualMP; 
             
            Switch MisMatch begin 
                 
                Case true: 
                 
                    If MisMatchTimer.Enable = false then begin                     
                        MisMatchTimer.Enable = True ; 
                        MisMatchStopWatch.Start();   
                    end; 
                     
                    if Debug and MisMatchStopWatch.Elapsedmilliseconds > LogMisMatchSeconds * 1000 then     
                        Print(" Date=", Date:0:0, "  Time=", Time:4:0, "  Position MISMATCH detected where Actual Pos = ", ActualMP:0:0, 
                            "  Strategy Pos = ", Marketposition * CurrentShares:0:0, "  @  ", _ComputerDateTimeToString) ;              
             
                Case false:                                     
                       
                    If MisMatchTimer.Enable = True then begin 
                        MisMatchTimer.Enable = False;  
                        MisMatchStopWatch.Reset();   
                        if Debug then    
                            Print(" Date=", Date:0:0, "  Time=", Time:4:0, "  Position MISMATCH resolved where Actual Pos = ",   
                                  ActualMP:0:0, "  Strategy Pos = ", Marketposition * CurrentShares:0:0, "  @  ",    
                                  _ComputerDateTimeToString) ;  
                    end; 
                     
            end;  
                   
        end;  
                   
    end;   
     
 
Method void PosMisMatchTimeOut( elsystem.Object sender, elsystem.TimerElapsedEventArgs args )  
    begin   
       
        if Debug then   
            print(_Bar, "  RESTART strategy to ADOPT CORRECT REAL WORLD POSITION at time=", Time:4:0, "  @  ",   
                   _ComputerDateTimeToString, Newline ) ;   
           
        { Cancel all open orders for this symbol/account before throwing the recalc exception } 
            if CancelAllOrders then value1 = RunCommand( CancelAllOrdersStr ) ;  
          
        { Throw recalculation event to force all strategies to restart and adopt the current real-world position }   
            Throw RecalculateException.Create(" Restart strategy to enter trade") ;   
       
    end;   
 
    
  
//  MAIN code  
  
    Once (_LastBarOnChart) begin 
        LastBar = true; 
        value1 = RunCommand( CancelAllOrdersStr ) ;  
    end; 
             
     
     
