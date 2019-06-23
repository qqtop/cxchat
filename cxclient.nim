import asyncdispatch, asyncnet
import cxprotocol,threadpool
import nimcx
import std/wordwrap

const clientversion = "4.2" 
#  Application : cxclient.nim
#  Latest      : 2019-06-23
#  Usage       : cxclient eagle1   # you could use an emoji 😇 as user name too
#  
#  the cxserver prog writes the dynamic ngrok port encrypted to a github repo and the client reads it from there
#  client restarts itself if a disconnect occurs , just press enter to get a new prompt
#  if the client connection fails or flickers errormessages then the server is down.
#  Longline handling is at least attempted and copy/paste code snippets are 
#  transferred with correct indentation.
#  
#  Find the contrialsmax var below to set the restart attempts.
#  Default is 10000 which should last abt 30 days.
#  
#  Compile  : nim --threads:on -d:ssl -d:release -f c cxclient.nim
     
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
        # the port returned in xresult is now encrypted ,we need to decrypt here
        result = decryptFromBase64(xresult,key)       
         
     except HttpRequestError :
        printLnErrorMsg("Client connect error. E404 crydatapath not reachable")
        printLnErrorMsg("Possible causes: Internet down. Crydatapath in cxprotocol.nim not set or incorrect")
        doFinish()
     
                         
proc showEmojis() = 
     # using ejm3 from cxconsts.nim
     var smiki = newcolor(200,255,60)
     cxprintLn(1,ivory,"[",smiki,"Emoji   ",ivory,"]" , yellow,yalebluebg," ","Copy emoji you want to use and paste it into your text line." & spaces(8))                 
     var ejm:string = ""
     for x in 0..22: ejm = ejm & ejm3[x] & " "
     cxprintLn(1,ivory,"[",smiki,"Emoji   ",ivory,"]" , yellow,yalebluebg," ",strip(ejm)) 
     ejm = ""
     for x in 23..45: ejm = ejm & ejm3[x] & " "
     cxprintLn(1,ivory,"[",smiki,"Emoji   ",ivory,"]" , yellow,yalebluebg," ",strip(ejm))
     let ejml = ejm.len
     ejm = ""
     for x in 46..<ejm3.len: ejm = ejm & ejm3[x] & " "
     ejm = ejm & "  " & leftarrow & "  " & rightarrow & "  " & uparrow & "  " & downarrow & spaces(5)
     cxprintLn(1,ivory,"[",smiki,"Emoji   ",ivory,"]" , yellow,yalebluebg," ",cxpad(ejm,ejml - 8))
               
               
proc doPrompt(username:string) =
     # a switch to showemojis only once before the first prompt
     if shwemojis < 2: 
         if shwemojis == 1: 
             showEmojis()
             echo()
         inc shwemojis
     
     printInfoMsg(cxpad(lightslategray & cxDateTime() & pastelBlue & "]" & bblack & spaces(1) & yellowgreen & username & "[C]",20),"",colLeft=yellowgreen,colRight=black,xpos = 1)
     curFw()  
     print(cleareol)
     
                         
proc connect(socket: AsyncSocket, serverAddr: string, serverport:int,username:string) {.async.} =
  ## Connects the specified AsyncSocket to the specified address.
  ## Then receives messages from the server continuously.
  # for debug 
  #echo("Connecting to ", serverAddr)
  
  let contrialsmax = 10000  # change this to control reconnection or auto restart attempts
  var sockok = false
  inc contrials
  var cspace = 61
  if contrials > 1: cspace = 40
        
  printLnInfoMsg("Connecting to", cxpad(serverAddr & " Port: " & $serverport.Port,cspace),yellow)
  printLnInfoMsg("Attempt      ", cxpad($contrials & " of " & $contrialsmax,cspace),pastelblue)
  printLnInfoMsg("Connect      ", cxpad("Press <enter> now or if no prompt. ",cspace),pastelblue)
 
  # Pause the execution of this procedure until the socket connects to the specified server.
  # or give error msg if server offline
  
  while sockok == false and contrials < contrialsmax:
      try:  
          await socket.connect(serverAddr,serverport.Port)
          sockok = true
          await sleepAsync(1000) # triggers
          
      except Exception:
          printLnErrorMsg("Cxserver can not be reached. Maybe offline. Try again later.    ")
          printLnInfoMsg(spaces(6),"Try this : cxclient eagle1                                ")
          echo()
          # for debug
          #let  e = getCurrentException()
          #let  msg = getCurrentExceptionMsg()
          #printLnErrorMsg("System exception data : " & repr(e).strip() & " with message " & msg.strip())
          
          # we also try to break out from here to run up to contrialsmax retrials
          inc contrials
          printLnInfoMsg(spaces(6),"Automatic reconnect attempt : " & $contrials & " of " & $contrialsmax)
          sockok=false
          await sleepAsync(10000)   # spacing the retrials      

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
          printLnInfoMsg("😅😅 ",cxpad(" This cxclient may timeout and disconnect every 5-10 minutes",69),yellowgreen)
          printLnInfoMsg(spaces(5),cxpad(" Keep calm ! Do not panic ! It will try to restart " & $contrialsmax & " times ! ",69),lightpink)
          printLnInfoMsg("😀😀 ",cxpad(" Have Fun !",69),lightpink)
          decho(3)
          sessionhead = 1
      while true:
        try:
              # Pause the execution of this procedure until a new message is received from the server.
              let line = await socket.recvLine()
              # Parse the received message using ``parseMessage`` defined in the cxprotocol.nim
              let parsed = parseMessage(line)  
              let crynow = cxDateTime() & "]" 
              # Display the message to the user.
              var pm = decryptFromBase64(parsed.message,key)
              if pm == "" or pm.len == 0:
                   var onlinetime = initduration(seconds = int(epochtime()) - int(clientstart))
                   echo()
                   let onl = "Online for " & $onlinetime 
                   printLnInfoMsg(crynow,cxpad("Disconnection . ",onl.len),colLeft=truetomato,xpos = 1)
                   printLnInfoMsg(crynow,onl,colLeft=pastelblue,xpos = 1)
                   printLnInfoMsg(crynow,cxpad("Client attempts to restart now ... ",onl.len),colLeft=pastelblue,xpos = 1)
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
                     printLnInfoMsg(cxpad(lightslategray & crynow & spaces(1) & parsed.username & "[S]",20),pastelwhite & pm,colLeft=truetomato,colRight=pastelpink,xpos = 1)
                     
                  elif pm.contains("connected to Cxserver"):
                     printLnInfoMsg(cxpad(lightslategray & crynow & spaces(1) & parsed.username & "[S]",25),pastelBlue & pm,colLeft=turquoise,colRight=pastelgreen,xpos = 1)
                  else:
                     if parsed.username.contains(chatname) :
                        printLnInfoMsg(cxpad(lightslategray & crynow & spaces(1) & parsed.username & "[S]",20),pastelBlue & pm ,colLeft=orchid,colRight=pastelgreen,xpos = 1)
                     else:
                        if (decryptFromBase64(parsed.message,key)).strip() == "" :   # do not show any blank lines from incoming messages to keepy display tidy
                           discard
                        else:
                           let cclcolor = whiteSmoke  
                           if parsed.username.contains("[H]"):
                               # display historical msgs 
                               let apm = pm.split("-->")[0].strip()
                               let apm2 = pm.split("-->")[1].strip(false,true)
                               
                               if parsed.username.startswith(username):
                                     if strip(pm,false,true).len < tw - 35: 
                                        printLnInfoMsg(cxpad(lightslategray & apm & "]" & yellowgreen & spaces(1) & parsed.username,32),pastelwhite & apm2,colLeft=pastelblue,xpos = 1)
                                     else: 
                                        # we got a long line 
                                         var wpm1 = wrapWords(strip(apm2,false,true),(tw - 37))
                                         var swpm1 = wpm1.splitLines()
                                         for xwpm1 in 0 .. swpm1.len - 1:
                                             if xwpm1 == 0:
                                                  printLnInfoMsg(cxpad(lightslategray & apm & "]" & yellowgreen & spaces(1) & parsed.username ,32),pastelwhite & spaces(2) & swpm1[xwpm1],colLeft=pastelblue,xpos = 1)
                                             else:
                                                  printLnInfoMsg(cxpad(yellowgreen & parsed.username,12),cclcolor & spaces(2) & swpm1[xwpm1],colLeft=pastelblue,xpos = 22)                                   
                                      
                                      
                               else:
                                     if strip(pm,false,true).len < tw - 35: 
                                         printLnInfoMsg(cxpad(lightslategray & apm & "]" & lightsalmon & spaces(1) & parsed.username,32),pastelwhite & apm2,colLeft=pastelblue,xpos = 1)
                                     else: 
                                         # we got a long line 
                                         var wpm2 = wrapWords(strip(apm2,false,true),(tw - 37))
                                         var swpm2 = wpm2.splitLines()
                                         for xwpm2 in 0 .. swpm2.len - 1:
                                             if xwpm2 == 0:
                                                  printLnInfoMsg(cxpad(lightslategray & apm & "]" & lightsalmon & spaces(1) & parsed.username ,32),pastelwhite & spaces(2) & swpm2[xwpm2],colLeft=pastelblue,xpos = 1)
                                             else:
                                                  printLnInfoMsg(cxpad(lightsalmon & parsed.username,12),cclcolor & spaces(2) & swpm2[xwpm2],colLeft=pastelblue,xpos = 22)                                   

                                     
                           else:  
                               # display current msgs from other clients
                               # longline handling, tw = terminalwidth
                               
                               if strip(pm,false,true).len > tw - 35: 
                                 # we got a long line 
                                 var wpm = wrapWords(strip(pm,false,true),(tw - 35))
                                 var swpm = wpm.splitLines()
                                 for xwpm in 0 .. swpm.len - 1:
                                    if xwpm == 0:
                                       printLnInfoMsg(cxpad(lightslategray & crynow & bblack & spaces(1) & lightsalmon & parsed.username & "[C]",32), spaces(2) & cclcolor & swpm[xwpm],colLeft=lightsalmon,colRight = bblack,xpos = 1)
                                    else:
                                       printLnInfoMsg(cxpad(lightsalmon & parsed.username & "[C]",12), spaces(2) & cclcolor & swpm[xwpm],colLeft=pastelblue,xpos = 22)                                   
                               else:  
                                    printLnInfoMsg(cxpad(lightslategray & crynow & bblack & spaces(1) & lightsalmon & parsed.username & "[C]",32), spaces(1) & cclcolor & strip(pm,false,true),colLeft=lightsalmon,colRight = bblack,xpos = 1)
                                   
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
    println(hlf,truetomato,styled={stylebright})
    printLn(" Cxchat       " & cxpad("cxClient SateSticks V" & clientversion & spaces(23) & "qqTop 2019",64),gold,truebluebg,xpos=1,styled={})
    # Ensure that a username was specified.
    if paramCount() < 1:
        # Terminate the client early with an error message if there was no username specified.
        printLnInfoMsg("Usage        ","e.g.: cxclient eagle1 ",xpos = 1)
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
    # reads the ngrok port from the github which was written there by the cxserver .. 
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
          asyncDispatch.poll(30) 
          
    asyncCheck connect(socket,serverAddr,serverport,username)
    runForever()
     
# end of cxclient.nim
