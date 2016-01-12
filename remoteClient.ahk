;AHK Remote Client v1.2
; this is the client, 
;To use, Set the IP and port of the server below
   NetworkAddress       = 192.168.1.15 ;127.0.0.1 ;127.0.0.1 means local machine (so does blank).
   NetworkPort          = 8257
   SCREENMAX            :=1281         ;the screen width of the server machine
   
   activateAltScreen    :=false         ;flags
   remoteControlOn      :=false

   setmousedelay -1
   setbatchlines -1 
#maxhotkeysperinterval 3000
#SingleInstance Force
#NoEnv

SendMode Input

PromptForAddy  = 1         ;Allows the user to supply another address if desired.
TestTimout     = 1000      ;ms, Blank means don't pre-test the address.
MaxDataLength  = 4096      ;Longest message that can be recieved.
MaxGuiRows     = 10
ButtonSize     = 128       ;Blank means auto.

Menu TRAY, Tip, AHK Remote
Menu TRAY, Icon, SHELL32.DLL, 121
Menu TRAY, NoStandard
If (NOT A_IsCompiled) 
{
   Menu TRAY, Add, &Edit, TrayEdit
   Menu TRAY, Add
}
Menu TRAY, Add, &Reload, TrayReload
Menu TRAY, Add, E&xit, TrayExit

If PromptForAddy
{
   Gui Add, Text, w64 Right, Address:
   Gui Add, Edit, w100 yp-4 x+8 vNetworkAddress, %NetworkAddress%
   Gui Add, Text, xm w64 Right, Port:
   Gui Add, Edit, w100 yp-4 x+8 vNetworkPort, %NetworkPort%
   Gui Add, Button, gGetStarted Default, Connect
   Gui Show,, Enter Address
   Return
}
GetStarted:
Gui Submit

if (NetworkAddress = "")
   NetworkAddress := "127.0.0.1"
If (NOT TestTimout)
   TestTimout := 0
NeedIP := !RegExMatch(NetworkAddress, "^(\d+\.){3}\d+$")

If (TestTimout OR NeedIP)
{
   ;Use Ping to check if the address is reachable, we can also get the IP address this way.
   RunWait %ComSpec% /C Ping -n 1 -w %TestTimout% %NetworkAddress% > getpingtestip.txt,, Hide
   If (ErrorLevel AND TestTimout)
   {
      MsgBox %NetworkAddress% cannot be reached.
      FileDelete getpingtestip.txt
      ExitApp
   }
   If NeedIP
   {
      Loop, Read, getpingtestip.txt
      {
         If RegExMatch(A_LoopReadLine, "(?<=\[)(\d+\.){3}\d+(?=\])", NetworkAddress)
           Break
      }
   }
   FileDelete getpingtestip.txt
}

Menu PopUp, Add, Dummy, HandleMenu ;So the menu exists.

If (ButtonSize != "")
   ButtonSize := "w" . ButtonSize

;v v v v v v v v v v v v v v v v v v v
OnExit DoExit

MainSocket := PrepareSocket(NetworkAddress, NetworkPort)
If (MainSocket = -1)
   ExitApp ;failed

DetectHiddenWindows On
Process Exist
MainWindow := WinExist("ahk_class AutoHotkey ahk_pid " . ErrorLevel)
DetectHiddenWindows Off

;^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^
;FD_READ + FD_CLOSE + FD_WRITE = 35
If DllCall("Ws2_32\WSAAsyncSelect", "UInt", MainSocket, "UInt", MainWindow, "UInt", 5555, "Int", 35)
;v v v v v v v v v v v v v v v v v v v
{
    MsgBox % "WSAAsyncSelect() indicated Winsock error " . DllCall("Ws2_32\WSAGetLastError")
    ExitApp
}

OnMessage(5555, "ReceiveData", 99) ;Allow 99 (i.e. lots of) threads.

Return

PrepareSocket(IPAddress, Port)
{
   VarSetCapacity(wsaData, 32)
   Result := DllCall("Ws2_32\WSAStartup", "UShort", 0x0002, "UInt", &wsaData)
   If ErrorLevel
   {
      MsgBox WSAStartup() could not be called due to error %ErrorLevel%. Winsock 2.0 or higher is required.
      return -1
   }
   If Result  ; Non-zero, which means it failed (most Winsock functions return 0 upon success).
   {
      MsgBox % "WSAStartup() indicated Winsock error " . DllCall("Ws2_32\WSAGetLastError")
      return -1
   }

   ;AF_INET = 2   SOCK_STREAM = 1   IPPROTO_TCP = 6
   Socket := DllCall("Ws2_32\socket", "Int", 2, "Int", 1, "Int", 6)
   If (Socket = -1)
   {
      MsgBox % "Socket() indicated Winsock error " . DllCall("Ws2_32\WSAGetLastError")
      return -1
   }

   VarSetCapacity(SocketAddress, 16)
   InsertInteger(2, SocketAddress, 0, 2) ; AF_INET = 2
   InsertInteger(DllCall("Ws2_32\htons", "UShort", Port), SocketAddress, 2, 2)   ; sin_port
   InsertInteger(DllCall("Ws2_32\inet_addr", "Str", IPAddress), SocketAddress, 4, 4)   ; sin_addr.s_addr
;^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^

   If DllCall("Ws2_32\connect", "UInt", Socket, "UInt", &SocketAddress, "Int", 16)
   {
      Result := DllCall("Ws2_32\WSAGetLastError")
      If (Result = 10061)
         MsgBox Connection Refused. That probably means the server script is not running.
      Else
         MsgBox % "Connect() indicated Winsock error " . Result
      return -1
   }
    
   Return Socket
}

ReceiveData(wParam, lParam)
{
   Global MaxGuiRows, ButtonSize, MaxDataLength, MainSocket, MenuChoice

;v v v v v v v v v v v v v v v v v v v
   VarSetCapacity(ReceivedData, MaxDataLength, 0)
   ReceivedDataLength := DllCall("Ws2_32\recv", "UInt", wParam, "Str", ReceivedData, "Int", MaxDataLength, "Int", 0)
   If (ReceivedDataLength = 0)  ; The connection was gracefully closed
      Return NormalClose()
   if ReceivedDataLength = -1
   {
      WinsockError := DllCall("Ws2_32\WSAGetLastError")
      If (WinsockError = 10035)  ; No more data to be read
         Return 1
      If WinsockError = 10054 ; Connection closed
         Return NormalClose()
      MsgBox % "Recv() indicated Winsock error " . WinsockError
      ExitApp
   }

   Command := SubStr(ReceivedData, 1, 10)
   ReceivedData := SubStr(ReceivedData, 11)
;^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^

   If (Command = "ARCOMLIST:")
   {
      Gui Destroy
      Loop Parse, ReceivedData, %A_Space%
      {
         StringReplace ButtonName, A_Loopfield, _, %A_Space%, All
         If (Mod(A_Index, MaxGuiRows) = 0)
            Options .= "ym "
         Gui Add, Button, %ButtonSize% gHandleButton %Options%, %ButtonName%
         Options =
      }
      Gui Show,, AHK Remote
   }
   Else If (Command = "ARSHOWTXT:")
   {
      Gui 2:Destroy
      Gui 2:Add, Edit, Multi w500, %ReceivedData%
      Gui 2:+ToolWindow +Owner1
      Gui 2:Show,, AHK Remote
   }
   Else If (Command = "ARMESSAGE:")
   {
      Gui +OwnDialogs
      MsgBox,, AHK Remote, %ReceivedData%
   }
   Else If (Command = "ARYESORNO:")
   {
      Gui +OwnDialogs
      MsgBox 36, AHK Remote, %ReceivedData%
      
      IfMsgBox Yes 
      {
         SendData(MainSocket, "ARESPONSE:YES")
         if(instr(ReceivedData,"Activate")){
            gosub activateRemoteControl
         }
      }Else{
         SendData(MainSocket, "ARESPONSE:NO")
      }
   }
   Else If (Command = "ARGETINFO:")
   {
      Gui +OwnDialogs
      InputBox Result, AHK Remote, %ReceivedData%,,, 130
      If (ErrorLevel OR Result = "")
         SendData(MainSocket, "ARESPONSE:CANCEL")
      Else
         SendData(MainSocket, "ARESPONSE:" . Result)
   }
   Else If (Command = "ARPASWORD:")
   {
      Gui +OwnDialogs
      InputBox Result, AHK Remote, Password required., Hide,, 110
      If ErrorLevel
         SendData(MainSocket, "ARESPONSE:CANCEL")
      Else
         SendData(MainSocket, "ARESPONSE:" . RC4txt2hex("OPENSESAME", Result . ReceivedData))
   }
   Else If (Command = "ARPOPMENU:")
   {
      Menu PopUp, DeleteAll
      Loop Parse, ReceivedData, |
         Menu PopUp, Add, %A_LoopField%, HandleMenu
      MenuChoice := 0
      Menu PopUp, Show
      SendData(MainSocket, "ARESPONSE:" . MenuChoice)
   }
   Else If (Command = "A_PINGACK:")
   {
      gosub pingAck
   }

   Return 1
}

NormalClose()
{
   ExitApp
   Return 1
}

;v v v v v v v v v v v v v v v v v v v
SendData(Socket, Data)
{
   SendRet := DllCall("Ws2_32\send", "UInt", Socket, "Str", Data, "Int", StrLen(Data), "Int", 0)
   If (SendRet = -1)
      MsgBox % "Send() indicated Winsock error " . DllCall("Ws2_32\WSAGetLastError")
   Return SendRet
}

;By Laszlo, used by the password function.
RC4txt2hex(Data,Pass) { 
   Format := A_FormatInteger 
   SetFormat Integer, Hex 
   b := 0, j := 0 
   VarSetCapacity(Result,StrLen(Data)*4) 
   Loop 256 { 
      a := A_Index - 1 
      Key%a% := Asc(SubStr(Pass, Mod(a,StrLen(Pass))+1, 1)) 
      sBox%a% := a 
   } 
   Loop 256 { 
      a := A_Index - 1 
      b := b + sBox%a% + Key%a%  & 255 
      T := sBox%a% 
      sBox%a% := sBox%b% 
      sBox%b% := T 
   } 
   Loop Parse, Data 
   { 
      i := A_Index & 255 
      j := sBox%i% + j  & 255 
      k := sBox%i% + sBox%j%  & 255 
      Result .= Asc(A_LoopField)^sBox%k% 
   } 
   Result := RegExReplace(Result, "0x(.)(?=0x|$)", "0$1") 
   StringReplace Result, Result, 0x,,All 
   SetFormat Integer, %Format% 
   Return Result 
}

InsertInteger(pInteger, ByRef pDest, pOffset = 0, pSize = 4)
{
   Loop %pSize%  ; Copy each byte in the integer into the structure as raw binary data.
      DllCall("RtlFillMemory", "UInt", &pDest + pOffset + A_Index-1, "UInt", 1, "UChar", pInteger >> 8*(A_Index-1) & 0xFF)
}

GuiClose:
ExitApp

DoExit:
TrayExit:
DllCall("Ws2_32\WSACleanup")
ExitApp

TrayEdit:
Edit
Return

TrayReload:
Reload
Return

;^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^

HandleButton:
StringReplace CommandName, A_GuiControl, %A_Space%, _, All
SendData(MainSocket, "ARCOMMAND:" . CommandName)
Return

HandleMenu:
MenuChoice := A_ThisMenuItemPos
Return

shift::
   if(remoteControlOn){
      
                           ;123456789                            
      SendData(MainSocket, "A_SH_DOWN:Shift Down")
    }
    shiftDown:=true
   send {shift down}
return
shift up::
   
   shiftDown:=false
   if(remoteControlOn){
      
                           ;123456789                            
      SendData(MainSocket, "A_SH_DOUP:Shift uP")
    }
   send {shift up}
return
ctrl::
   ctrlDown:=true
   if(remoteControlOn){
      
                           ;123456789                            
      SendData(MainSocket, "A_CO_DOWN:CTRL down")
      return
   }
   send {ctrl down}
return
ctrl up::
   ctrlDown:=false
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_CO_DOUP:CtRl Up")
      return
   }
   send {ctrl up}
return
~RALT::
~LALT::
   altDown:=true
   SLEEP 100          ;DEBOUNCE THE KEY.. ? 
   ;having troubles with PHP storm triggering millions of ALTs when I press it.. must be a storm bug
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_AL_DOWN:ALT Down")
      return
   }
   ;send {ctrl down}
return
RALT UP::
LALT UP::
   altDown:=false
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_AL_DOUP:ALT UP")
      return
   }
   send {alt up}
return

~LWIN::
~RWIN::
   winDown:=true   
return
~LWIN up::
~RWIN up::
   winDown:=false   
return



lbutton::   
   if(remoteControlOn){
                           ;123456789                                  
      SendData(MainSocket, "A_LB_DOWN:LButton Down")
      return
   }
   
   send {lbutton down}
   
return
~lbutton up::
   pingTime := stopwatch()
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_LB_DOUP:LButton Up")
      return
   }   
return
rbutton::
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_RB_DOWN:RButton Down")
      return
   }
   
   send {rbutton down}
return
~rbutton up::
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_RB_DOUP:RButton Up")
      return
   }      
 
return
mbutton::
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_MB_DOWN:MButton Down")
      return
   }
   send {mbutton down}
return
~mbutton up::
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_MB_DOUP:MButton Up")
      return
   }    
return

wheelup::
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_WL_DOUP:Wheel Up")
      return
   }
   
   send {%A_ThisHotkey%}
return
wheeldown::
   if(remoteControlOn){
                           ;123456789                            
      SendData(MainSocket, "A_WL_DOWN:Wheel Down")
      return
   }
   
   send {%A_ThisHotkey%}
return


scanTheKeys:
      setTimer, scanTheKeys,off
        
        input:=""
         Loop  {
            Input, thisKey, B L1 C M, {AppsKey}{F1}{F2}{F3}{F4}{F5}{F6}{F7}{F8}{F9}{F10}{F11}{F12}{Left}{Right}{Up}{Down}{Home}{End}{PgUp}{PgDn}{Del}{Ins}{BS}{Capslock}{Numlock}{PrintScreen}{Pause}{ESC}{backspace}{space},~ 
            
            EL := ErrorLevel 
            if EL = EndKey:f6
               break
            if(instr(EL,"Match:")){
               break
            }
            if(remoteControlOn=false){
               break
            }
            if(instr(EL,"EndKey:")){
               thisKey:=substr(EL,8)
               if(thisKey=="F6" || thisKey=="f6"){   ;/just in case
                  break
               }
            }
            if(thisKey!=lastKey){
               lastKey:=thisKey
               if (thiskey==" "){
                  thisKey:="space"
               }               
               SendData(MainSocket, "AKEYINPUT:" . thisKey )
            }
            ;input.=thisKey
            ;ToolTip, % input       
         }       
         remoteControlOn  :=false
         activateAltScreen:=false
         return
         
deactivateRemoteControl:        
		remoteControlOn:=false
  		setTimer, doRemoteControl, off        
    return    


activateRemoteControl:   	
		setTimer, doRemoteControl,20    ; for 50 updates per second
        return
doRemoteControl:
   if(1){
      scanTime := stopwatch()                         ;50% duty cycle
      loop 
      {    
         if(stopwatch(scanTime,false)>15){            ; at 20ms updates, scans for 15ms for 75% DtyCycl
            break 
         }
         lastKey:=""       ; a debounce..
         updateMouse:=false
         coordmode Mouse,Screen
         MouseGetPos, mouseXpos ,mouseYpos , id, Control
         
           if(lastMouseX != mouseXpos){
           
               if(mouseXpos==0 && activateAltScreen==false){               
                  activateAltScreen    :=true       ;//this looks redundant..              
                  remoteControlOn      := true
                  mouseMove , SCREENMAX ,mouseYpos,0
                  setTimer scanTheKeys,10         ;activate scan the keys in another thread. so we can exit okay.
               }
               if(mouseXpos>SCREENMAX && activateAltScreen==true ){
                  activateAltScreen := false                
                  remoteControlOn := false
                  mouseMove , 1,mouseYpos,0
                  
               }
               
               if(remoteControlOn){
                  toolTip <-- %mouseXPos% / %mouseYpos%
               }
               
               
               
               lastMouseX := mouseXpos
               updateMouse:=true
           }
           if(lastMouseY != mouseYpos){
               lastMouseY := mouseYpos
               updateMouse:=true
           }
         if(updateMouse && remoteControlOn){
           SendData(MainSocket, "ARMOUSEXY:" . mouseXpos . "/" . mouseYpos)		 
         }
         if(!remoteControlOn){
            break
         }      
      }
   }
return

+f12::
 reload
return	

^f12::
   pingTime := stopwatch()
   SendData(MainSocket, "A_PINGTST:ping" )
return

pingAck:
   pingTime := stopwatch(pingTime,false)
   msgBox Ping took %pingTime% milliseconds.   
return
   


; returns elapsed time in ms 
; Can keep track of multiple events in the same or different threads 
; stopwatch 
; built by RHCP
; from SKANS QPX & Delay
; https://autohotkey.com/board/topic/48063-qpx-delay-based-on-queryperformancecounter/

stopwatch(itemId := 0, removeUsedItem := True)
{
	static F := DllCall("QueryPerformanceFrequency", "Int64P", F) * F , aTicks := [], runID := 0

	if (itemId = 0) ; so if user accidentally passes an empty ID variable function returns -1
	{
		DllCall("QueryPerformanceCounter", "Int64P", S), aTicks[++runID] := S
		return runID
	}
	else 
	{
		if aTicks.hasKey(itemId)
		{
			DllCall("QueryPerformanceCounter", "Int64P", End)
			return (End - aTicks[itemId]) / F * 1000, removeUsedItem ? aTicks.remove(itemId, "") : ""
		}
		else return -1
	}
}

