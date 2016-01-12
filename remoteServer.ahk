;AHK Remote Server v1.2
setmousedelay -1
setbatchlines -1 

#SingleInstance Force
#NoEnv
SendMode Input
NetworkAddress = 0.0.0.0 ;Listen address, 0.0.0.0 = any
NetworkPort    = 8257    ;Listen port
ignoreMe       :=false			
debugOn        :=false              ;enables debug messages on the screen

MaxDataLength  = 4096    ;Longest message that can be recieved.

Menu TRAY, Tip, AHK Remote Server`n%A_IPAddress1%
Menu TRAY, Icon, SHELL32.DLL, 125
Menu TRAY, NoStandard
If A_IsCompiled ;The self-reading trick won't work for compiled scripts.
   CommandList = Quit Volume_Up Volume_Down Mute ;sample hard-coded list
Else
{
   LabelStart := False
   Loop Read, %A_ScriptFullPath%
   {
      If (NOT LabelStart)
      {
         If InStr(A_LoopReadLine, "===" . "Begin Custom Labels" . "===")
            LabelStart := True
         Else
            Continue
      }
      If RegExMatch(A_LoopReadLine, "^[^\s;]\S*(?=:\s*$)", LabelName)
         CommandList .= " " . LabelName
   }
   CommandList := SubStr(CommandList, 2)
   Menu TRAY, Add, &Edit, TrayEdit
   Menu TRAY, Add, &Copy Command List, TrayCopy
   Menu TRAY, Add
}
Menu TRAY, Add, No Connection, TrayDisconnect
Menu TRAY, Disable, No Connection
Menu TRAY, Add, &Reload, TrayReload
Menu TRAY, Add, E&xit, TrayExit
RunningCommands := " "

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
;FD_READ + FD_CLOSE + FD_ACCEPT = 41
If DllCall("Ws2_32\WSAAsyncSelect", "UInt", MainSocket, "UInt", MainWindow, "UInt", 5555, "Int", 41)
;v v v v v v v v v v v v v v v v v v v
{
    MsgBox % "WSAAsyncSelect() indicated Winsock error " . DllCall("Ws2_32\WSAGetLastError")
    ExitApp
}

OnMessage(5555, "ReceiveData", 999) ;Allow 99 (i.e. lots of) threads.

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

   If DllCall("Ws2_32\bind", "UInt", Socket, "UInt", &SocketAddress, "Int", 16)
   {
      MsgBox % "Bind() indicated Winsock error " . DllCall("Ws2_32\WSAGetLastError")
      return -1
   }
   If DllCall("Ws2_32\listen", "UInt", Socket, "UInt", "SOMAXCONN")
   {
      MsgBox % "Listen() indicated Winsock error " . DllCall("Ws2_32\WSAGetLastError")
      return -1
   }
    
   Return Socket
}

ReceiveData(wParam, lParam)
{
   Global MaxDataLength, OutgoingSocket, CommandList, RunningCommands, ClientResponse, ignoreMe, shiftedDown,ctrledDown,altedDown,debugOn
   Event := lParam & 0xFFFF

   If (Event = 8) ;FD_ACCEPT = 8
   {
      If (OutgoingSocket > 0)
         NormalClose() ;Close OutgoingSocket
      OutgoingSocket := DllCall("Ws2_32\accept", "UInt", wParam, "UInt", &SocketAddress, "Int", 0)
      If (OutgoingSocket < 0)
         MsgBox % "Accept() indicated Winsock error " . DllCall("Ws2_32\WSAGetLastError")
      Else
      {
         SendData(OutgoingSocket, "ARCOMLIST:" . CommandList)
         Menu TRAY, Rename, No Connection, &Disconnect
         Menu TRAY, Enable, &Disconnect
         Menu TRAY, Tip, AHK Remote Server`nConnected!
      }
      Return 1
   }

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

   ;æäãáâàç
           ;        token,   command
   commands:= Object( "¢", "ARCOMMAND:"
                    , "¤", "A_LB_DOWN:"
                    , "¥", "A_LB_DOUP:"
                    , "¦", "A_RB_DOWN:"
                    , "§", "A_RB_DOUP:"
                    , "©", "A_MB_DOUP:"
                    , "ª", "A_MB_DOWN:"
                    , "®", "A_WL_DOWN:"
                    , "µ", "A_WL_DOUP:"
                    , "¶", "AKEYINPUT:"
                    , "¬", "ARMOUSEXY:"
                    , "à", "A_SH_DOWN:"
                    , "á", "A_SH_DOUP:"
                    , "â", "A_CO_DOWN:"
                    , "ã", "A_CO_DOUP:"
                    , "ä", "A_AL_DOWN:"
                    , "æ", "A_AL_DOUP:"
                    , "ç", "A_PINGTST:")
   ;  è é ê  some spare tokens for new commands
   
   ; Tokenize the commandList (in order to use the single char parsing loop we must do it this way.
   ;really this seems redundant as hell and seems like overhead, 
   ;Im more inclined to use super global constants, 
   ;we could just define all these tokens as constants and pass
   ;them around that way.
   ;also I needed to parse like this to stop being flooded by multiple commands per packet
   
   ReceivedDataX := ReceivedData
   for token,command in commands 
   {
      StringReplace, ReceivedDataX, ReceivedDataX, %command%, %token%, All
   }
      
   position:=
   lastCommand:=""
   Loop, parse, ReceivedDataX, ¢¤¥¦§©ª®µ¶¬æäãáâàç
   {
         token        := SubStr(ReceivedDataX, Position, 1)      ; Retrieve the token found          
         Command      := commands[token]                         ; convert to a command         
         ReceivedData := A_LoopField                            
         Position += StrLen(A_LoopField) + 1                     ; +1 for the token, go to next cmd

      If (Command = "ARCOMMAND:")
      {
         If InStr(" " . CommandList . " ", " " . ReceivedData . " ")
         {
            If NOT InStr(" " . RunningCommands . " ", " " . ReceivedData . " ")
            {
               RunningCommands .= ReceivedData . " "
               If IsLabel(ReceivedData) ;Should be redundant, but just in case.
                  GoSub %ReceivedData%
               StringReplace, RunningCommands, RunningCommands, %A_Space%%ReceivedData%%A_Space%, %A_Space%
            }
         }
         
      } else If (Command = "A_PINGTST:") {
         A_PINGACK("pong") 
      
      } else If (Command = "ARESPONSE:") {
         ClientResponse := ReceivedData
         
    
      } else if (Command = "ARMOUSEXY:") {   
           mouseX := SubStr(ReceivedData, 1, instr(ReceivedData,"/")-1)		
           mouseY := SubStr(ReceivedData, instr(ReceivedData,"/")+1)
           if(lastXY != "" . mouseX . mouseY ) {			
               lastXY := "" . mouseX . mouseY
               
               coordmode Mouse,Screen
               mouseMove , mouseX,mouseY,0
          
               
           }
       }else if (Command = "AKEYINPUT:") {   
            key := ReceivedData
               modState:=""
               if(shiftedDown){
                  send {shift down}
                  modState:=modState . "S"                  
               }else{
                  send {shift up}
                  modState:=modState . "s"
               }
               if(ctrledDown){
                  send {ctrl down}
                  modState:=modState . "C"
               }else{
                  send {ctrl up}
                  modState:=modState . "c"
               }
               if(altedDown){
                  send {alt down}
                  modState:=modState . "A"
               }else{
                  send {alt up}
                  modState:=modState . "a"
               }
               toolTip %modState%(%key%)
               if(instr(key,"ctrl")){   ; for debugging...
                  msgbox %key%
               }
            if(strlen(key)>1){               
               send {%key%}               
            }else{
               send %key%
            }
       }else if (Command = "A_LB_DOWN:") {
            send {lbutton down}
       }else if (Command = "A_LB_DOUP:") {
            send {lbutton up}
       }else if (Command = "A_RB_DOWN:") {
            send {rbutton down}
       }else if (Command = "A_RB_DOUP:") {
            send {rbutton up}
       }else if (Command = "A_MB_DOWN:") {
            send {mbutton down}
       }else if (Command = "A_MB_DOUP:") {
            send {mbutton up}
       }else if (Command = "A_WL_DOUP:") {
            send {wheelup}
       }else if (Command = "A_WL_DOWN:") {
            send {wheeldown}
       }else if (Command = "A_SH_DOWN:") {
            send {shift down}
            shiftedDown:=true
       }else if (Command = "A_SH_DOUP:") {
            send {shift up}
            shiftedDown:=false
       }else if (Command = "A_CO_DOWN:") {
            send {CTRL DOWN}
            ctrledDown:=true
       }else if (Command = "A_CO_DOUP:") {
            send {CTRL UP}
            ctrledDown:=false
       }else if (Command = "A_AL_DOWN:") {
            send {alt down}
            altedDown:=true
       }else if (Command = "A_AL_DOUP:") {
            send {alt up}
            altedDown:=false
       }
             
       
       
   } ;end loop    
   Return 1
}
+f12::
 reload
return
 
NormalClose()
{
   Global OutgoingSocket, ClientResponse := "DISCONNECT"
   Result := DllCall("Ws2_32\closesocket", "UInt", OutgoingSocket)
   If (Result != 0)
   {
      MsgBox % "CloseSocket() indicated Winsock error " . DllCall("Ws2_32\WSAGetLastError")
      ExitApp
   }
   OutgoingSocket =
   Menu TRAY, Tip, AHK Remote Server`n%A_IPAddress1%
   Menu TRAY, Rename, &Disconnect, No Connection
   Menu TRAY, Disable, No Connection
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

TrayCopy:
ClipBoard := CommandList
Return

TrayDisconnect:
NormalClose()
Return

; ---------------------------------------------------------------------------
; Here are some functions you can use to communicate with the client script.

A_PINGACK(msg="pong") 
{
   Global OutgoingSocket
   SendData(OutgoingSocket, "A_PINGACK:" . msg )
   toolTip Sent Ping Ack
}                            

ARMessage(Text) ;Standard message box.
{
   Global OutgoingSocket
   SendData(OutgoingSocket, "ARMESSAGE:" . Text)
   return true
}


ARShowText(Text) ;Shows text in a copyable box, for longer test.
{
   Global OutgoingSocket
   SendData(OutgoingSocket, "ARSHOWTXT:" . Text)
}

ARYesNo(Text) ;Returns 1 (true) for yes.
{
   Global OutgoingSocket, ClientResponse =
   SendData(OutgoingSocket, "ARYESORNO:" . Text)
   Loop
   {
      Sleep 50
      If (ClientResponse == "DISCONNECT")
         Exit
      Else If (ClientResponse != "")
         Return (ClientResponse == "YES")
   }
}

ARInput(Text) ;Returns CANCEL if response is blank or dialog is canceled.
{
   Global OutgoingSocket, ClientResponse =
   SendData(OutgoingSocket, "ARGETINFO:" . Text)
   Loop
   {
      Sleep 50
      If (ClientResponse == "DISCONNECT")
         Exit
      Else If (ClientResponse != "")
         Return ClientResponse
   }
}

ARPassword(Pass) ;Asks for a password .
{                ;Returns 1 (true) for success. If ErrorLevel is 1, it was canceled.
   Global OutgoingSocket, ClientResponse =
   Loop 10
   {
      Random Rand, 1, 255
      Challenge .= Chr(Rand)
   }
   SendData(OutgoingSocket, "ARPASWORD:" . Challenge)
   Loop
   {
      Sleep 50
      If (ClientResponse == "DISCONNECT")
         Exit
      Else If (ClientResponse != "")
      {
         If (ClientResponse = "CANCEL")
         {
            ErrorLevel := 1
            Return 0
         }
         ErrorLevel := 0
         Return (ClientResponse = RC4txt2hex("OPENSESAME", Pass . Challenge))
      }
   }
}

ARMenu(Items) ;Items format: Item1|Item2|Item3, || makes a separator.
{             ;Returns item postion (counting separators) or 0 if canceled. 
   Global OutgoingSocket, ClientResponse =
   SendData(OutgoingSocket, "ARPOPMENU:" . Items)
   Loop
   {
      Sleep 50
      If (ClientResponse == "DISCONNECT")
         Exit
      Else If (ClientResponse != "")
         Return ClientResponse
   }
}

; ==========Begin Custom Labels========== (Do not delete this line.)
; Put a comment after a label to prevent it from being a command.

Close_Server:
If ARYesNo("Are you sure?")
   ExitApp
Return

Restart_Server:
Reload
Return

Sound:
SoundGet VolLevel
SoundGet IsMute,, MUTE
SoundInfo := "Vol:" . Round(VolLevel) . "%   Mute:" . IsMute
Result := ARMenu("Volume Up|Volume Down||Mute|Un-Mute||" . SoundInfo)
If (Result = 1)
   SoundSet +10
Else If (Result = 2)
   SoundSet -10
Else If (Result = 4)
   SoundSet 1,, MUTE
Else If (Result = 5)
   SoundSet 0,, MUTE
Return

View_Server_Code:
If A_IsCompiled ;The self-reading trick won't work for compiled scripts.
   ARMessage("Sorry, you can't. It's compiled. ")
Else
{
   FileRead Code, %A_ScriptFullPath%
   Code := RegExReplace(Code, "`as).*\R(?=.*?===" . "Begin Custom Labels" . "===)")
   Code := RegExReplace(Code, "i)(ARPassword)\(.*?\)", "$1(""*******"")")
   ARShowText(Code)
   VarSetCapacity(Code, 0)
}
Return

Ultra_Basic_Chat:
Result := ARInput("Send message:")
Loop
{
   If (Result == "CANCEL")
      Break
   InputBox Result, AHK Remote Server, %Result%,,, 130
   If ErrorLevel
      Break
   Result := ARInput(Result)
}
Return

Shutdown_Computer: ;Change the password below, than remove this comment to enable.
If ARPassword("swordfish")
{
   MsgBox 49, AHK Remote Server, AHK Remote Client requested shutdown. Permit?, 30
   IfMsgBox OK
      Shutdown 12
   Else
      ARMessage("Shutdown aborted by remote user.")
}
Else
   ARMessage("Permission Denied.")
Return

Remote_Control:
If ARYesNo("Activate Remote Control?") 
{
   ARMessage("< - - Mouse off Screen to Activate Remote Control")
}
Return

Ping:
If A_PINGACK()
{
   ;If ARYesNo("Activate Remote Control?")
   ;   ARMessage("<--- Mouse off Screen to Activate Remote Control")
   ;ARMessage("sent Ping Ack")   
}
Return
