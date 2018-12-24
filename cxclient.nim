import asyncdispatch, asyncnet
import cxprotocol,threadpool
import nimcx
import std/wordwrap
#import "/data5/NimStuff/NimCxDevel/cx.nim"
const clientversion = "3.1" 


#  Application : cxclient.nim
#  Latest      : 2018-12-24
#  Usage       : cxclient wuff 
#  
#  the server prog writes the ngrok port to a github repo and the client reads it from there
#  client restarts itself if a disconnect occurs , just press enter to get a new prompt
#

       
var clientstart = epochTime() 
var shwemojis = 0
        
proc clientGetPort(url:string = "https://raw.githubusercontent.com/qqtop/cryxtemp/master/crydata1.txt"):string = 
     # read content of our file on github
     result = ""
     sleepy(3)  # sleep 3 helps to have everything settled down 
     let client = newHttpClient()
     result = strip(client.getContent(url),true,true)    
     
     
# proc clientGetPort386(url:string = "https://raw.githubusercontent.com/qqtop/cryxtemp386/master/crydata1.txt"):string = 
#      # read content of our file on github
#      result = ""
#      sleepy(3)  # sleep 3 helps to have everything settled down 
#      let client = newHttpClient()
#      result = strip(client.getContent(url),true,true)        
#      
                         
proc showEmojis() = 
     # using ejm3 from cxconsts.nim
     echo()
     printLnInfoMsg(gold & cxpad("Emojis" & ivory,19),"Copy emoji you want to use and paste it into your text line." & spaces(5),colLeft=pastelblue,xpos = 1)                 
     var ejm:string = ""
     for x in 0..21: ejm = ejm & ejm3[x] & " "
     printLnInfoMsg(gold & cxpad("Emojis" & ivory,19),strip(ejm),colLeft=pastelblue,xpos = 1) 
     ejm = ""
     for x in 22..43: ejm = ejm & ejm3[x] & " "
     printLnInfoMsg(gold & cxpad("Emojis" & ivory,19),strip(ejm),colLeft=pastelblue,xpos = 1)
     let ejml = ejm.len
     ejm = ""
     for x in 44..ejm3.len: ejm = ejm & ejm3[x] & " "
     ejm = ejm & hand & " " & errorsymbol & "  "
     printLnInfoMsg(gold & cxpad("Emojis" & ivory,19),cxpad(ejm,ejml - 7),colLeft=pastelblue,xpos = 1)
     echo()        
     
               
proc doPrompt(username:string) =
     # a swith to showemojis only once before the second prompt
     if shwemojis < 2: 
       if shwemojis == 1: showEmojis()
     inc shwemojis
     printInfoMsg(yellowgreen & cxpad(username & "[C]" & lightslategray & spaces(1) & cxDateTime() & pastelblue,20),"",colLeft=pastelblue,colRight=black,xpos = 1)
     curBk()  
     print cleareol 
     
                         
proc connect(socket: AsyncSocket, serverAddr: string, serverport:int,username:string) {.async.} =
  ## Connects the specified AsyncSocket to the specified address.
  ## Then receives messages from the server continuously.
  #echo("Connecting to ", serverAddr)
  printLnInfoMsg("Connecting to", cxpad(serverAddr & " Port: " & $serverport.Port,60) ,zippi)
  printLnInfoMsg(spaces(5),cxpad(" Press enter now or if there is no prompt. ",68),yellowgreen)
  # Pause the execution of this procedure until the socket connects to the specified server.
  # or give error msg if server offline
  var contrials = 0
  var sockok=false
  while sockok == false and contrials < 10:
      try:  
          await socket.connect(serverAddr,serverport.Port)
          sockok=true
      except Exception:
          inc contrials
          printLnErrorMsg("Server can not be reached. Maybe offline. Try again later.    ")
          printLnInfoMsg(spaces(6),"Alternatively try if the secondary server is online.     ")
          printLnInfoMsg(spaces(6),"Try this :  client turtle  or client turtle 386         ")
          let  e = getCurrentException()
          let  msg = getCurrentExceptionMsg()
          echo()
          printLnErrorMsg("System exception data : " & repr(e).strip() & " with message " & msg.strip())
          # we also try to break out from here , hopefully we will retry lets see
          printLnInfoMsg(spaces(6),"Break out , trying to reconnect attempt : " & $contrials & spaces(8))
          sockok=false
          await sleepAsync(5000)         
      
      if sockok == false and contrials == 9:
        printLnInfoMsg(spaces(6),"Auto reconnect attempts failed , please restart manually to see if server can be reached")
        doFinish()   
      
  # all ok lets go
  let wmsg0 = cxpad("Welcome user " & gold & "  " & username & "  " & termwhite & " --> You are now connected to Cryxserver !   ",84)
  printLnOkMsg(wmsg0)
  let wmsg1 = cxpad("via " & pastelpink & rightarrow & termwhite & spaces(1) & $serveraddr & ":" & $serverport & "  since " & ($now()).replace("T"," "),94)
  printLnOkMsg(cxpad(wmsg1,(wmsg0.len)))
  echo()
  printLnInfoMsg("Notes",cxpad(" Username is truncated if longer than 6 chars",68),yellowgreen)
  printLnInfoMsg(spaces(5),cxpad(" [H] indicates historical data. Up to 100 recent messages are shown",68),yellowgreen)
  printLnInfoMsg(spaces(5),cxpad(" The client will timeout and disconnect within 5-10 minutes",68),yellowgreen)
  printLnInfoMsg(spaces(5),cxpad(" Keep calm ! Do not panic ! It will AutoRestart ! ",68),lavender)
  echo()
  printLnInfoMsg(spaces(5),cxpad(" Have Fun !",68),pink)
  showEmojis()
  decho(3)
  while true:
    # Pause the execution of this procedure until a new message is received from the server.
    try:
      
      let line = await socket.recvLine()
      # Parse the received message using ``parseMessage`` defined in the protocol module.
      let parsed = parseMessage(line)  
      let crynow = cxDateTime()
      # Display the message to the user.
      var pm = decryptFromBase64(parsed.message,key)
      if pm == "" or pm.len == 0:
           # this error triggers
           var onlinetime = epochTime() - clientstart
           #printLnInfoMsg(red & cxpad("Error" & lightslategray & spaces(1) & crynow & ivory,20), "A disconnect occured. " & username & " , please reconnect again !" ,colLeft=pastelblue,xpos = 1)
           echo()
           printLnInfoMsg(red & cxpad(spaces(5) & lightslategray & spaces(1) & crynow & ivory,20), "Online for " & $onlinetime & " secs" ,colLeft=pastelblue,xpos = 1)
           printLnInfoMsg(pink & cxpad(spaces(5) & lightslategray & spaces(1) & crynow & ivory,20), "Client is restarting ... ",colLeft=pastelblue,xpos = 1)
           #doFinish()
           # restart works now
           close(socket) # close anything hanging around
           var socket = newAsyncSocket()
           # wait a bit tohave things settle down
           await sleepAsync(10)
           # Execute the ``connect`` procedurhttps://www.youtube.com/watch?v=PCTOxiZ-lBUe in the background asynchronously.
           asyncCheck connect(socket, serverAddr,serverport,username)
           
           break  # leave this loop
           
      if pm <> "" and pm.len > 0:
          pm = pm.strip()
          if pm.contains("disconnected from Cxserver"):  
             # echo()
             printLnInfoMsg(cxpad(parsed.username & "[S]" & lightslategray & spaces(1) & crynow,20), pm,colLeft=truetomato,colRight=pastelpink,xpos = 1)
          elif pm.contains("connected to Cxserver"):
             printLnInfoMsg(cxpad(parsed.username & "[S]" & spaces(1) & crynow,25), pm & spaces(1),colLeft=turquoise,colRight=pastelgreen,xpos = 1)
          else:
             if parsed.username.contains("CRYX") :
                printLnInfoMsg(cxpad(parsed.username & "[S]" & lightslategray & spaces(1) & crynow & pastelgreen,20), pm ,colLeft=orchid,colRight=pastelgreen,xpos = 1)
             else:
                if (decryptFromBase64(parsed.message,key)).strip() == "" :   # do not show any blank lines from incoming messages to keepy display tidy
                   discard
                else:
                   if parsed.username.contains("[H]"):
                       # display historical msgs 
                       let apm = pm.split("-->")[0].strip()
                       let apm2 = pm.split("-->")[1].strip()
                       if parsed.username.startswith(username):
                             printLnInfoMsg(yellowgreen & cxpad(parsed.username & lightslategray & spaces(1) & apm & ivory,20),apm2,colLeft=pastelblue,xpos = 1)
                       else:
                             printLnInfoMsg(lightsalmon & cxpad(parsed.username & lightslategray & spaces(1) & apm & ivory,20),apm2,colLeft=pastelblue,xpos = 1)
                   else:  
                       # display msgs  from other clients
                       # experimental longline handling
                       if strip(pm).len > tw - 34: 
                         # we got a long line 
                         var wpm = wrapWords(strip(pm),(tw - 35))
                         var swpm = wpm.splitLines()
                         for xwpm in 0 ..< swpm.len:
                            if xwpm == 0:
                               printLnInfoMsg(lightsalmon & cxpad(parsed.username & "[C]" & lightslategray & spaces(1) & crynow & ivory,21),swpm[xwpm],colLeft=pastelblue,xpos = 1)
                            else:
                               printLnInfoMsg(lightsalmon & cxpad(parsed.username & "[C]" &  ivory,21),swpm[xwpm],colLeft=pastelblue,xpos = 1)   
                       else:   
                         printLnInfoMsg(lightsalmon & cxpad(parsed.username & "[C]" & lightslategray & spaces(1) & crynow & ivory,21),strip(pm),colLeft=pastelblue,xpos = 1)
    except:
        # we should not get here anyway
        printLnInfoMsg(red & cxpad("Error " & lightslategray & spaces(1) & cxDateTime() & ivory,20), "A network disconnect event occured. Please restart ",colLeft=pastelblue,xpos = 1)
        discard
       
 
when isMainModule: 
    getcxTrueColorSet()
    cleanscreen()
    decho(2)
    cxprintLn(" Cxchat       " & cxpad("cxClient SateSticks V" & clientversion & spaces(23) & "qqTop 2018",63),colgold,slateblue,xpos=1)
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
#     if paramcount() > 1 and paramstr(2) == "386":
#        serverport = parseInt(clientGetPort386())
#     else:   
    serverport = parseInt(clientGetPort())
    # Initialise a new asynchronous socket.
    # print(yellowgreen & username & dodgerblue & rightarrow & termwhite & spaces(1),xpos=2)
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
          asyncDispatch.poll(50)   # poll()    now using 50 for faster response 
         
    asyncCheck connect(socket, serverAddr,serverport,username)
    runForever()
     
# end of client.nim
