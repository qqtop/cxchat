import asyncdispatch,asyncnet,threadpool,asyncfile,sigfault
import nimcx
import cxprotocol

# cxcalm
#
# Heartbeat for cxchat optional since cxclient.nim now has a heartbeat build in  
#
# we connect into the current chat and send pings every soften to keep the sockets alive
# status : ok
#
#
# 2019/09/24

# Compile with
#nim -d:threadsafe --threads:on -d:ssl -d:release -d:danger -f cpp cxCalm 



proc clientGetPort(url:string = crydatapath):string   # forward

let serverAddr = "0.tcp.ap.ngrok.io"
let username = "cxCalm"
# get the serverport  
let serverport = parseInt(clientGetPort())
#let sleeptime = 180_000   # 3 mins seems ok 5 minutes times out somewhen
#let sleeptime = 90_000    # 1.5 mins
let sleeptime = 10_000     # 10 secs
var recvcount = 0
var calmTimer  = newCxtimer("calmTimer")

calmTimer.startTimer


proc clientGetPort(url:string = crydatapath):string = 
     # read content of our file on github to get the ngrok port number
     # crydatapath is defined in cxprotocol.nim
     printLnStatusMsg("cxCalm starting up, please wait... ")
     printLnStatusMsg("Fetching server port ... ")
     result = ""
     sleepy(3)  # sleep 3 helps to have everything settled down 
     let client = newHttpClient()
     var xresult = ""
     try:
        xresult = strip(client.getContent(url),true,true)
        # the port returned in xresult is encrypted ,we need to decrypt here
        result = decryptFromBase64(xresult,key)
        curup(1)
        print clearline
        curup(1)
        print clearline    
         
     except HttpRequestError :
        printLnErrorMsg("Client connect error. E404 crydatapath not reachable                ")
        printLnErrorMsg("Cause 1 : Internet down                                            ")
        printLnErrorMsg("Cause 2 : Crydatapath in cxprotocol.nim not set or incorrect       ")
        printLnErrorMsg("Cause 3 : not compiled with -d:ssl flag                            ")
        doFinish()



proc connect(socket: AsyncSocket, serverAddr: string, serverport:int,username:string) {.async.} =
     var socketok = false
     while socketok == false:
        try:
            printlnStatusMsg(cxnow() & " Connecting now.... ")
            await sleepAsync(1000) 
            await socket.connect(serverAddr,serverport.Port)
            socketok = true
            curup(1)
        except Exception:
             socketok = false
             currentLine()
             printLnErrorMsg(getCurrentExceptionMsg() & spaces(30))
             printLnErrorMsg("Cxserver can not be reached.                    ")
             printLnErrorMsg("Maybe cxserver is down or ngrok socket is closed")
             printLnErrorMsg("Try again later                                 ")
             printLnErrorMsg(cxdatetime())
             socket.close()
             doFinish()

     if socketok == true:
        return
     

proc checkserverAlive(socket:AsyncSocket,username:string){.async.} =
         
          while true:
              
              let line = await socket.recvLine()  # this is an asyncsocket so recvline has no timeout
              # Parse the received message using ``parseMessage`` defined in the cxprotocol.nim
              let parsed = parseMessage(line)  
              let crynow = cxDateTime() & "]"
              let errm  = cxpad(cxDateTime() & " Server maybe off line or disconnected. Try restart cxCalm",tw - 3)
              let okmsg = " ok " 
              # Display okmsg in console if parsed contained anything
              var pm = decryptFromBase64(parsed.message,key)
              if pm == "" or pm.len == 0:   # usually means socket down,disconnected or server down etc hence exit
                  printLnErrorMsg(errm)
                  cxBell();cxBell();cxBell()                                   
                  doFinish()
              else: # received something from server so we show okmsg
                  inc recvcount
                  cxSound()
                  cxprintLn(52,pastelblue,fmtx(["", ">10","",""],"Recv.: ",$recvcount,spaces(2),cxDatetime() & " " & okmsg))
                  printLnBiCol("Up   : " & $initduration(seconds = int(lapTimer(calmTimer))),colLeft = pastelblue,xpos = 1)
       
              curup(2)
                  
proc afterConnect(socket:AsyncSocket,username:string) {.async.} =
  var c = 0
  var sockok = true
  if isClosed(socket) == false:
    while sockok == true:
        inc c 
        let botnews = "ping sent" # msg shown in console
        let calm = spaces(2)  # just send an empty line which is being eaten by the server, but keeps all going
        let messageFlowVar = spawn calm & "\c\l"
        # cxCalm only writes to console
        cxprintLn(1,goldenrod,fmtx(["", ">10","",""],"Sent : ",$c,spaces(2),cxDatetime() & " " & botnews & spaces(3)),termwhite)
        printLnBiCol("Up   : " & $initduration(seconds = int(lapTimer(calmTimer))),colLeft = goldenrod,xpos = 1)
        curup(2)
        if messageFlowVar.isReady():
              await socket.send(createMessage(username, ^messageFlowVar))
              cxSound("/usr/share/sounds/purple/send.wav")
              await sleepAsync(sleeptime)
        asyncCheck checkserverAlive(socket,username)
        
   
              
proc mastercon(serverAddr: string,username: string) {.async.} =
    cleanscreen()
    printLn("Cxchat      " & cxpad("cxCalm SateSticks V-008" & spaces(23) & "qqTop 2019" & spaces(15) & "HeartBeat " & heart,tw - 15),gold,xpos=1,styled={styleBright})
    printLnBiCol("Since: " & cxDateTime(),xpos=1)
    # get the serverport  
    let serverport = parseInt(clientGetPort())
    # Initialise a new asynchronous socket.
    let socket = newAsyncSocket()
    # Execute the ``connect`` procedure in the background asynchronously.
    await connect(socket,serverAddr,serverport,username)

    # only send once
    let messageFlowVar = spawn "Hello. " & username & " online now !" & "\c\l"   # encryption done in protocol
    while true:
             await afterConnect(socket,username)
             asyncDispatch.poll(30)
              
    #if isClosed(socket) == true:  
    #    printlnStatusMsg(cxnow() & " Socket found closed awaiting connect ")    
    await connect(socket,serverAddr,serverport,username)  # do we need this line

when isMainModule :
   
   #while true:  # with this while we never trigger exception below SO FAR
     try: 
         waitFor mastercon(serverAddr,username)
     except Exception:
          let  e = getCurrentException()
          let  msg = getCurrentExceptionMsg()
          printLnInfoMsg("System exception data : " & repr(e).strip() & "\n with message " & msg.strip())   
          
     runforever()
