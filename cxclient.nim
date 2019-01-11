import asyncdispatch, asyncnet
import cxprotocol,threadpool
import nimcx
import std/wordwrap

const clientversion = "3.5" 
#  Application : cxclient.nim
#  Latest      : 2019-01-11
#  Usage       : cxclient wuff   # you could use an emoji 😇 as user name too
#  
#  the cxserver prog writes the ngrok port to a github repo and the client reads it from there
#  client restarts itself if a disconnect occurs , just press enter to get a new prompt
#  if the client connection fails or flickers errormessages then the server is down.
#  Longline handling is at least attempted and copy/paste code snippets are 
#  transferred with correct indentation.
#  
#  Find the contrialsmax var below to set the restart attempts. Default is 100 which should last abt 8 hours.
#  
#  Compile  : nim  --threads:on -d:ssl -d:release -f c cxclient.nim
     
var clientstart = epochTime() 
var shwemojis = 0
var contrials = 0
var sessionhead = 0

var hlf = """
   ___ _  _  ___ _  _  __  ___ 
  |     \/  |    |__| |__|  |  
  |___ _/\_ |___ |  | |  |  |  
                                                                  
"""

        
proc clientGetPort(url:string = crydatapath):string = 
     # read content of our file on github to get the ngrok port number
     # crydatapath is defined in cxprotocol.nim
     result = ""
     sleepy(3)  # sleep 3 helps to have everything settled down 
     let client = newHttpClient()
     var xresult = ""
     try:
        xresult = strip(client.getContent(url),true,true) 
     except HttpRequestError :
        printLnErrorMsg("Client connect error. E404 crydatapath not reachable")
        printLnErrorMsg("Possible causes: Internet down. Crydatapath in cxprotocol.nim not set or incorrect")
        doFinish()
     result = xresult   
     
                         
proc showEmojis() = 
     # using ejm3 from cxconsts.nim
     #echo()
     printLnInfoMsg(gold & cxpad("Emojis" & ivory,19),"Copy emoji you want to use and paste it into your text line.   " & spaces(5),colLeft=pastelblue,xpos = 1)                 
     var ejm:string = ""
     for x in 0..22: ejm = ejm & ejm3[x] & " "
     printLnInfoMsg(gold & cxpad("Emojis" & ivory,19),strip(ejm),colLeft=pastelblue,xpos = 1) 
     ejm = ""
     for x in 23..45: ejm = ejm & ejm3[x] & " "
     printLnInfoMsg(gold & cxpad("Emojis" & ivory,19),strip(ejm),colLeft=pastelblue,xpos = 1)
     let ejml = ejm.len
     ejm = ""
     for x in 46..<ejm3.len: ejm = ejm & ejm3[x] & " "
     ejm = ejm & hand & " " & errorsymbol & "  "
     printLnInfoMsg(gold & cxpad("Emojis" & ivory,19),cxpad(ejm,ejml - 9),colLeft=pastelblue,xpos = 1)
            
     
               
proc doPrompt(username:string) =
     # a switch to showemojis only once before the second prompt
     if shwemojis < 3: 
         if shwemojis == 2: showEmojis()
     inc shwemojis
     printInfoMsg(yellowgreen & cxpad(username & "[C]" & lightslategray & spaces(1) & cxDateTime() & pastelblue,20),"",colLeft=pastelblue,colRight=black,xpos = 1)
     curBk()  
     print(cleareol)
     
                         
proc connect(socket: AsyncSocket, serverAddr: string, serverport:int,username:string) {.async.} =
  ## Connects the specified AsyncSocket to the specified address.
  ## Then receives messages from the server continuously.
  #echo("Connecting to ", serverAddr)
  
  let contrialsmax = 100  # change this to control reconnection or auto restart attempts
  var sockok = false
  inc contrials
  var cspace = 61
  if contrials > 1: cspace = 40
        
  printLnInfoMsg("Connecting to", cxpad(serverAddr & " Port: " & $serverport.Port,cspace) ,zippi)
  printLnInfoMsg("Attempt      ", cxpad($contrials & " of " & $contrialsmax,cspace) ,zippi)
  printLnInfoMsg("Connect      ", cxpad("Press <enter> now or if no prompt. ",cspace),zippi)

  # Pause the execution of this procedure until the socket connects to the specified server.
  # or give error msg if server offline
  
  while sockok == false and contrials < contrialsmax:
      try:  
          await socket.connect(serverAddr,serverport.Port)
          sockok = true
          await sleepAsync(1000) # triggers
          
      except Exception:
          printLnErrorMsg("Cxserver can not be reached. Maybe offline. Try again later.    ")
          printLnInfoMsg(spaces(6),"Try this : client turtle                                  ")
          echo()
          # for debug
          #let  e = getCurrentException()
          #let  msg = getCurrentExceptionMsg()
          #printLnErrorMsg("System exception data : " & repr(e).strip() & " with message " & msg.strip())
          
          # we also try to break out from here to run up to contrialsmax retrials
          inc contrials
          printLnInfoMsg(spaces(6),"Automatic reconnect attempt : " & $contrials & " of " & $contrialsmax)
          sockok=false
          await sleepAsync(10000)         

      if sockok == false and contrials == contrialsmax :
          printLnInfoMsg(spaces(6),"All auto reconnect attempts exhausted. Restart cxclient manually .")
          doFinish()  
         
  if sockok == true:  
      # all ok lets go
      if sessionhead == 0:
          let wmsg0 = cxpad(" Welcome user " & gold & "  " & username & "  " & termwhite & " --> You are now connected to Cxserver !     ",87)
          printLnInfoMsg("Ok   ",wmsg0)
          let wmsg1 = " via " & rightarrow & termwhite & spaces(1) & $serveraddr & ":" & $serverport & "  since " & ($now()).replace("T"," ")
          printLnInfoMsg("Ok   ",cxpad(wmsg1,76))
          #echo()
          printLnInfoMsg("Notes",cxpad(" Username is truncated if longer than 6 chars",69),yellowgreen)
          printLnInfoMsg(spaces(5),cxpad(" [H] indicates historical data. Up to 15 recent messages are shown",69),yellowgreen)
          printLnInfoMsg(spaces(5),cxpad(" This cxclient may timeout and disconnect every 5-10 minutes",69),yellowgreen)
          printLnInfoMsg(spaces(5),cxpad(" Keep calm ! Do not panic ! It will try to restart " & $contrialsmax & " times ! ",69),lightpink)
          #echo()
          printLnInfoMsg(spaces(5),cxpad(" Have Fun !",69),lightpink)
          showEmojis()
          decho(3)
          sessionhead = 1
      while true:
        # Pause the execution of this procedure until a new message is received from the server.
        try:
          
              let line = await socket.recvLine()
              # Parse the received message using ``parseMessage`` defined in the cxprotocol.nim
              let parsed = parseMessage(line)  
              let crynow = cxDateTime() 
              # Display the message to the user.
              var pm = decryptFromBase64(parsed.message,key)
              if pm == "" or pm.len == 0:
                   var onlinetime = initduration(seconds = int(epochtime()) - int(clientstart))
                   echo()
                   printLnFailMsg("Disconnection . ")
                   var onl = "Online for " & $onlinetime 
                   printLnInfoMsg(crynow,onl,colLeft=pastelblue,xpos = 1)
                   printLnInfoMsg(crynow,cxpad("Client attempts to restart now ... ",onl.len),colLeft=pastelblue,xpos = 1)
                   # restart works now
                   close(socket) # close anything hanging around
                   var socket = newAsyncSocket()
                   # wait a bit to have things settle down
                   await sleepAsync(1000)
                   # Execute the ``connect`` procedure in the background asynchronously.
                   asyncCheck connect(socket, serverAddr,serverport,username)
                   break  # leave this loop
                   
              if pm <> "" and pm.len > 0:
                  
                  pm = pm.strip(false,true)
                  if pm.contains("disconnected from Cxserver"):  
                     printLnInfoMsg(cxpad(parsed.username & "[S]" & lightslategray & spaces(1) & crynow & pastelwhite,20), pm,colLeft=truetomato,colRight=pastelpink,xpos = 1)
                  elif pm.contains("connected to Cxserver"):
                     printLnInfoMsg(cxpad(parsed.username & "[S]" & lightslategray & spaces(1) & crynow & pastelBlue,25), pm,colLeft=turquoise,colRight=pastelgreen,xpos = 1)
                  else:
                     if parsed.username.contains(chatname) :
                        printLnInfoMsg(cxpad(parsed.username & "[S]" & lightslategray & spaces(1) & crynow & pastelBlue,20), pm ,colLeft=orchid,colRight=pastelgreen,xpos = 1)
                     else:
                        if (decryptFromBase64(parsed.message,key)).strip() == "" :   # do not show any blank lines from incoming messages to keepy display tidy
                           discard
                        else:
                           if parsed.username.contains("[H]"):
                               # display historical msgs 
                               let apm = pm.split("-->")[0].strip()
                               let apm2 = pm.split("-->")[1].strip(false,true)
                               if parsed.username.startswith(username):
                                     printLnInfoMsg(yellowgreen & cxpad(parsed.username & lightslategray & spaces(1) & apm & ivory,20),apm2,colLeft=pastelblue,xpos = 1)
                               else:
                                     printLnInfoMsg(lightsalmon & cxpad(parsed.username & lightslategray & spaces(1) & apm & ivory,20),apm2,colLeft=pastelblue,xpos = 1)
                           else:  
                               # now display msgs from other clients
                               # experimental longline handling, tw = terminalwidth
                               
                               if strip(pm,false,true).len > tw - 34: 
                                 # we got a long line 
                                 var wpm = wrapWords(strip(pm,false,true),(tw - 35))
                                 var swpm = wpm.splitLines()
                                 for xwpm in 0 ..< swpm.len:
                                    if xwpm == 0:
                                       printLnInfoMsg(lightsalmon & cxpad(parsed.username & "[C]" & lightslategray & spaces(1) & crynow & ivory,21),swpm[xwpm],colLeft=pastelblue,xpos = 1)
                                    else:
                                       printLnInfoMsg(lightsalmon & cxpad(parsed.username & "[C]" & ivory,21),swpm[xwpm],colLeft=pastelblue,xpos = 1)   
                               else:   
                                  printLnInfoMsg(lightsalmon & cxpad(parsed.username & "[C]" & lightslategray & spaces(1) & crynow & ivory,21),strip(pm,false,true),colLeft=pastelblue,xpos = 1)
                                  
                         
        except:
            discard
  else:        
            # if we get here the internet is down or the server is not running or we have naturally reached the contrialsmax value
            # after which a manual restart of the client is required.
            decho(2)
            printLnInfoMsg(red & cxpad("Error " & lightslategray & spaces(1) & cxDateTime() & ivory,20), "A network disconnect event occured.             ",colLeft=pastelblue,xpos = 1)
            printLnInfoMsg(red & cxpad("Error " & lightslategray & spaces(1) & cxDateTime() & ivory,20), $contrials & " connections attemped.             ",colLeft=pastelblue,xpos = 1)
            printLnInfoMsg(red & cxpad("Error " & lightslategray & spaces(1) & cxDateTime() & ivory,20), "The cxserver maybe down or cannot be reached.   ",colLeft=pastelblue,xpos = 1)
            printLnInfoMsg(red & cxpad("Error " & lightslategray & spaces(1) & cxDateTime() & ivory,20), "Restart the client manually now or retry later. ",colLeft=pastelblue,xpos = 1)
            doFinish()       
 
when isMainModule: 
    
    cleanscreen()
    println2(hlf,truetomato,styled={stylebright})
    cxprintLn(" Cxchat       " & cxpad("cxClient SateSticks V" & clientversion & spaces(23) & "qqTop 2019",64),colgold,slateblue,xpos=1)
    # Ensure that a username was specified.
    if paramCount() < 1:
        # Terminate the client early with an error message if there was no username specified.
        printLnInfoMsg("Usage        ","e.g.: client turtle ",xpos = 1)
        doFinish()
    
    let serverAddr = "0.tcp.ap.ngrok.io"   # <---- 
    # Retrieve the first command line argument.
    # we want the username to be max 6 chars for nicer alignment
    var username:string = paramStr(1)   
    if username.len > 6:
       username = substr($username,0,5)
    elif username.len < 6:
       username = cxpad($username,6)

    clientstart = epochTime()
    var serverport = 0
    # reads the ngrok port from the github which was written there by the server .. 
    serverport = parseInt(clientGetPort())
    # Initialise a new asynchronous socket.
    var socket = newAsyncSocket()
    # Execute the ``connect`` procedure in the background asynchronously.
    asyncCheck connect(socket, serverAddr,serverport,username)
    # Execute the ``readInput`` procedure in the background in a new thread.
    # The Hello message will only be shown once per logon
    var messageFlowVar = spawn "Hello. I am online now !" & stdin.readLine()   # encryption done in protocol
    
    while true:
          # Check if the ``readInput`` procedure returned a new line of input.
          if messageFlowVar.isReady():
             doPrompt(username)
             curBk(2)           
             # If a new line of input was returned, we can safely retrieve it without blocking.
             # The ``createMessage`` is then used to create a message based on the
             # line of input. The message is then sent in the background asynchronously.
             asyncCheck socket.send(createMessage(username, ^messageFlowVar))
             # Execute the ``readInput`` procedure again, in the background in a new thread.
             messageFlowVar = spawn stdin.readLine() 
                                    
          # Execute the asyncdispatch event loop, to continue the execution of asynchronous procedures.
          asyncDispatch.poll(50) 
         
    asyncCheck connect(socket, serverAddr,serverport,username)
    runForever()
     
# end of cxclient.nim
