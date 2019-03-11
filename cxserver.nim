import asyncdispatch, asyncnet,threadpool,db_sqlite
import cxprotocol
import nimcx

# cxchat - A very private chat application for the linux terminal
#          run the cxserver on your small left over pc 
#          share the cxclient and keyfile with a few friends,family or run it on a couple of your own systems
#          
# Setup :  
#          1) For the server presented here you need a github account and ngrok (https://ngrok.com/) 
#          2) On github create a new empty repo and name it : cryxtemp 
#          3) In your home dir 2 hidden folders will be created
#               .cxchat
#               .cxchatconf       
#          4) Create a file named niip.wsx to be used for encryption/decryption , fill it with    
#             any number of random chars and save it into the .cxchat folder 
#          5) Copy the provided cxchat.db or create one as below and save it into the .cxchat folder
#          6) Change into your .cxchatconf folder and git clone your cryxtemp repo here which you created in step 2 above.
#          7) Share the niip.wsx and compiled cxclient executable with anyone you allow to connect.
#          8) Start up cxserver:
#             a) open a terminal run : ngrok tcp 10001   
#             b) open a terminal run : cxserver port_number_given_in_ngrok_terminal
#          9) Start up cxclient
#             open a terminal run : client myname    (anything longer than 6 chars will be cut to size) 
#             wait for anyone else to connect or repeat this step with a different username and talk to
#             yourself or send messages to your other computers.
#             
# Note : This system was tested and worked with client connections from 4 continents.   
#        The cxchat.db is used to keep state and replay the last 50 messages so a new connected client knows whats going on.
#        Username is stored in plaintext, usermessages are relayed and stored encrypted using xxtea-nim encryption scheme
#        Other encryption schemes may be added in the future. 
#        
# Compile : nim  --threads:on -d:ssl -d:release -f c cxserver.nim     
#
# Application : cxserver.nim     
# Backend     : sqlite  
# Last        : 2019-03-11
#
# Required    : ngrok 
#               nimble install nimcx 
#
# Usage example
# 
# 1) terminal 1   : ngrok tcp 10001                # if you change the port also change port here below 
# 2) terminal 2   : cxserver port_as_given_by_ngrok
# 3) terminal 3   : cxclient tokyo                 # any name is fine as long as it is max 6 chars long
# 4) browser      : http://127.0.0.1:4040/status   # to see the ngrok status
# 
# 
# there is a empty cxchat.db provided
# or create one like so
# sqlite3 cxchat.db
# 
# The sqlite schema used to create the cxchat.db:
# 
# let dbsqlitedb = "cxchat.db" 
# if not fileExists(dbsqlitedb):
#    let db = open(dbsqlitedb, "", "", "")  # user, password, database name can be empty
#    db.exec(sql("""CREATE TABLE cryxdata (
#                  id INTEGER PRIMARY KEY,
#                  svdate DATE DEFAULT (datetime('now','localtime')),
#                  client varchar(10),
#                  msg dblob()) """))
#                  
#    db.exec(sql"COMMIT")
#    db.close()

let serverversion = "3.5 sqlite"

var hlf = """
  ___ _  _  __   ___  ___ _  _  ___  ___ 
 |     \/  [__  |___ |__/ |  | |___ |__/ 
 |___ _/\_ ___] |___ |  \  \/  |___ |  \ 
                                        
"""
type Tcondata = (int,string)

proc cxwrap(aline:string,wrappos:int = 70,xpos:int=1)  # forward decl

var cxchatdb = gethomedir() & "/.cxchat/cxchat.db"  # or put it where ever you want
var condata:Tcondata
var sessioncon = newSeq[Tcondata]()
let histreplaycount = "15"

# this set up assumes that path2 is a gitified directory from which you can
# make git push requests to a github repo of the same name which you need to set up yourself
# the github repo will be used to store the file crydata1.txt which contains the connection port
# required to have the cxclient connect to your server
# github was selected because it is available from most countries, while dropbox may not work.
# Other possibilities would be updateable pastebin location , your cloud location or a payed ngrok account etc
# 
# future expansion might include a self talking bot 
# so that humans do not have to waste time doing pesty chats.
# or server push messages on certain cues received from a client
# 
# 
# 
var path1 = gethomedir() & ".cxchatconf"         # this dir will hold the the gitified cryxtemp dir
if dirExists(path1) == false:  newdir(path1)
var path2 = path1 & "/cryxtemp"                  # this is the cloned dir
var path3 = path2 & "/crydata1.txt"              # this is where the temporary connection port is stored

let port = 10001  # change to whatever you want or is available 
let servername = "Cxserver"
var serverTimer  = newCxtimer("cxServerTimer")
var lastsu = epochTime()
var acounter = newCxCounter()

type
  Client = ref object
    socket: AsyncSocket
    netAddr: string
    id: int
    connected: bool

  Server = ref object
    socket: AsyncSocket
    clients: seq[Client]
    
var lastmsg = "" 
var activeids = ""  # experimental to show active connection id in a server push msg
    

proc newServer(): Server =
  ## Constructor for creating a new ``Server``.
  Server(socket: newAsyncSocket(), clients: @[])

proc `$`(client: Client): string =
  ## Converts a ``Client``'s information into a string.
  "Client " & $client.id & " (" & client.netAddr & ")"

proc getClientIds(server: Server):seq[string] =
     # returns all connected/active clientids in a seq              
     var resultx = newSeq[string]()
     for c in server.clients:
          # Only add connected clients
          if c.connected:
               resultx.add($c.id)
     result = resultx   
     
             
proc disconnectMsg(aclient:string,aservername:string=servername):string =
    result = strip(aclient.split("(")[0]) & spaces(1) & truetomato & " Disconnected ! "
    
proc noNews(aservername:string=servername,acounterval:int):string = 
    # maybe we can splice in some news like exchange rate or top new from the guardian or something
    result = "Currently no news from " & aservername & " No.: " & $acounterval   
    
proc connectMsg(aclient:string,aservername:string=servername,cusr:string = ""):string =
    let clid = aclient.split("(")[0]
    result = clid & "  " & cusr & yellowgreen & " Connected ! " 
       
    
proc infoMsg(aclient:string,aservername:string=servername,clientcount:int,clientId:string,activeIds:string):string =    
    # used to send auto message to clients via sendHello upon new client connection
    # for debug we can view the connection id of the client
    # this info is not of much use to the user tough
    #if clientcount == 1 :
    #      result = cxpad(spaces(1) & $clientcount & " user online. Your Id: " & clientId,55)   
    #else:
    #      result = cxpad(spaces(1) & $clientcount & " users online. Clients " & activeids & " Chat away.",55)  
    #      #result = cxpad(spaces(1) & $clientcount & " user. " & $aclient.split("(")[0] & "You are alone. Press <enter> " ,55)   
    # therefore we only show following
    if clientcount == 1 :
          result = cxpad(spaces(1) & $clientcount & " user. You are alone. Press <enter> " ,55)        
    else:
          result = cxpad(spaces(1) & $clientcount & " users online. Chat away.",55)  
          
          
proc histDataMsg(aclient:string,aservername:string=servername,amsg:string):string =        
     # displaying historical data to new connection
     result = amsg

proc getPortServerside():string = paramStr(1)
 
proc cxwrap(aline:string,wrappos:int = 70,xpos:int=1) =
     for wline in wrapWords(aline.strip(),72).splitLines():
             printLn(wline.strip(),termwhite,xpos=28)
        
proc writeport(afile:string,ngrokport:string) =
    # we assume a public repository on github and free ngrok account (dynamic forwarding port)
    # if you want to use another location accessible by server and client to sync the ngrok port number
    # then changes need to be made accordingly , dropbox did not work from all locations
    # a pastebin may or may not work for you.
    # if you have a paid ngrok account with a fixed port this setup may not be required 
    # and can be hard coded
    var f = system.open(afile,fmWrite)
    f.writeLine(ngrokport)
    f.close
    discard chdir(path2)

    decho(2) 

#     # experimental git stash if testing server on several system and the same git repo
#     # git does it's thing but sometimes it fails , you always can delete the dir and git clone your repo again 
#     # best is to restart ngrok , cxserver  and then see if everything connects with the cxclient.
#     #           
#     var z0 = execCmdEx("git stash  ") # we try to stash anything before pulling
#     printBiCol("git stash   ",xpos = 1)
#     cxwrap($z0[0])
#     printBiCol("git stash   ",colLeft=salmon,xpos = 1)
#     cxwrap($z0[1])
#     echo()
    
    var z = execCmdEx("git pull  ")   # we do a pull command first to 
                                      # check if there where any changes in case the server
                                      # was used on another system
                                      # maybe needs to be done 2 times or need to use git stash 
                                      # if there is some issue
    
    # note to printlnBiCol statements below the first prints output
    # the 2nd any error returned from execCmdEx tuple
    printBiCol("git pull     ",xpos = 1)
    cxwrap($z[0])
    printBiCol("git pull     ",colLeft=salmon,xpos = 1)
    cxwrap($z[1])
    echo()
    z = execCmdEx("git add .")
    printBiCol("git import add .    ",xpos = 1)
    cxwrap($z[0])
    printBiCol("git add .    ",colLeft=salmon,xpos = 1)
    cxwrap($z[1])
    echo()
    z = execCmdEx(""" git commit -m"$1" """ % $now())
    printBiCol("git commit -m",xpos = 1)
    cxwrap($z[0])
    printBiCol("git commit -m",colLeft = salmon,xpos = 1)
    cxwrap($z[1])
    echo()
    z = execCmdEx("git push")
    printBiCol("git push     ",xpos = 1)
    cxwrap($z[0])
    printBiCol("git push     ",colLeft = salmon,xpos = 1)
    cxwrap($z[1])
    echo()
    
proc getClientCount(server: Server):int = 
     # returns count of connected clients
     result = 0
     for c in server.clients:
          # Don't count disconnected.
          if c.connected:
              result = result + 1
              
   
proc sendHello(server: Server, client: Client) {.async.} =   
     let line = ""   # maybe for future use
     let nobody = "  Nobody online. "
     let clientcount = getClientCount(server)
     let tempclient = $client
                 
     # write some info on the server terminal if there is something new to report        
     if (clientcount == 0) and (lastmsg != nobody):         
        printLnStatusMsg(cxpad(line & cxnow & nobody,55)) 
        lastmsg = nobody 
        
     # send message to connected clients unless last message was the same as new message   
     elif (clientcount > 0) and (lastmsg != "  Users online : " & $clientcount):
        printLnStatusMsg(cxpad(line & cxnow & "  Users online : " & $clientcount,55))
        lastmsg = "  Users online : " & $clientcount
        activeids = ""
        let gci = getClientIds(server)
        for x in 0..<gci.len:
            activeids = activeids & " " & $gci[x]     
        for c in server.clients:
          # Don't send it to the client that sent this or to a client that is disconnected.
          if c.connected :
               # putting 3 lines below here allows us to pass correct client id around
               # question is if this is efficient for many clients as we respawn the serverflowvar often
               # client id's are not reused in a session and basically reflect the connection/reconnection count on the server
               var clientId = $c.id
               var serverFlowVar = spawn infoMsg(tempclient,clientcount=clientcount,clientId=clientId,activeids=activeids)
               let bmsg = createMessage(chatname, ^serverFlowVar)
               await c.socket.send(bmsg)  
               
     else:
        discard 
               
     return     

     
proc sendNews(server: Server, client: Client) {.async.} =
        acounter.add                 
        var serverFlowVar = spawn noNews(servername,acounterval = acounter.value)
        let bmsg = createMessage(chatname, ^serverFlowVar)
        var nc = 1   # a counter to limit the message sending   --> this now works
        for c in server.clients:
          # Don't send it to the client that sent this or to a client that is disconnected.
          if c.connected and nc <= getClientCount(server):
               await c.socket.send(bmsg)  
               inc nc
          else:
               discard  
        return     

     
proc sleepAlways(server: Server, client: Client)  {.async.} = 
    ## sendHello every so often currently abt 2 sec
    while true:
        await sleepAsync(2000)          # wait 2 secs so everything settles down a bit
        await sendHello(server,client)  # now send the message
        
        
proc sleepKadang(server: Server, client: Client) {.async.} =    
    while true: 
      await sleepAsync(60000)          # wait 6 minute     
    if sessioncon.len > 0:    
       await sendNews(server,client)    # send stuff if there is someone to send to
     
proc sleepServerUptime(server: Server) {.async.} =    
    # experimental to show serveruptime on server terminal in regular intervals using async
    while true: 
       if (epochTime() - lastsu) > 60.0:
          printLnBiCol("cxServer Uptime : " & $initduration(seconds = int(lapTimer(serverTimer))),colLeft = skyBlue,xpos = 1)
          lastsu = epochTime() 
       await sleepAsync(50000)          # wait 5 minutes or apparently whatever the scheduler likes  
       
proc processMessages(server: Server, client: Client) {.async.} =
  ## Loops while ``client`` is connected to this server, and checks
  ## whether a message has been received from ``client``.
  var tempclient = "" 
  var s = epochTime()
  while true:
    # Pause execution of this procedure until a line of data is received from ``client``.
    var line = await client.socket.recvLine() # The ``recvLine`` procedure returns ``""`` (i.e. a string of length 0) when ``client`` has disconnected.
    if line.len == 0:
       # before closing we remove client.id from sessioncon
       let curclid = client.id
       var curclusr = "" 
       var removeid = -1
       for x in 0..<sessioncon.len:
           if sessioncon[x][0] == curclid:
                curclusr = sessioncon[x][1]
                removeid = x
                break
       # removing in the loop fails so we try here
       if removeid >= 0:
           try:    
              sessioncon.delete(removeid)
           except RangeError:         
              printLnInfoMsg("Attention",cxpad("RangeError SE100 thrown at " & cxnow,51),truetomato)
              printLnInfoMsg("Sessioncon",$sessioncon,truetomato)
              #sessioncon = @[]
          
       if curclusr.len > 1:   
           printLnInfoMsg("Disconnected",cxpad("Client : " & $curclid & cxlpad(curclusr,7) & " at " & cxnow,51),truetomato)
           tempclient = "Client " & $curclid & cxlpad(curclusr,7)
       else:
           # should not happen but still does ??? 
           printLnInfoMsg("Disconnected",cxpad("Client : " & $curclid & " at " & cxnow,51),truetomato) 
           tempclient = "Client " & $curclid & " no recent activity "
           
       client.connected = false
       # When a socket disconnects it must be closed.
       client.socket.close()
       await sleepAsync(200)  # let things settle down
       # dissconnect message block sends the information message of a disconnect to all other live clients
       var serverFlowVar = spawn disconnectMsg(tempclient)
       var bmsg = createMessage(chatname, ^serverFlowVar)
       tempclient = ""
       for c in server.clients:
              # Don't send it to the client that sent this or to a client that is disconnected.
                  if c.id != client.id and c.connected:
                     await c.socket.send(bmsg)
       return 
       # end of disconnect message block  
      
    else:    
       # Display the encrypted message that was sent by the client .
       echo()
       printlnBiCol($client & " sent: " & line,xpos = 1)
       # we keep state now 
              
       let msgparsed = parseMessage(line)
       let auser = msgparsed.username
       let amsg =  msgparsed.message
       
       var scaddflag = true      
       condata = (client.id,auser)
       # we only add to sessioncon if not added prev.
       for sccon in 0 ..< sessioncon.len:
           if sessioncon[sccon] == condata:
               scaddflag = false
       if scaddflag == true:
          sessioncon.add(condata)      # adding condata here means now we can check sessioncon to see who is online
       printLnBicol("Sessioncon Last : " & auser & spaces(6) & $client.id,xpos = 1)
       # for debug
       #printLnBicol("Sessioncon : " & $sessioncon,colLeft=cyan,xpos=1)
       printLnBicol("Sessioncon Live : Recently active out of " & $getClientCount(server) & " connected users",colLeft=cyan,xpos = 1)
       try:
         for sc in 0 ..< sessioncon.len:
            printLnBiCol("ID " & $sessioncon[sc][0] & " : " & sessioncon[sc][1],xpos=3)
            
       except:
            printLnBicol("Sessioncon : " & $sessioncon,colLeft=red,xpos=1)
            discard
       printLnBiCol("cxServer Uptime : " & $initduration(seconds = int(lapTimer(serverTimer))),colLeft = pink,xpos = 1)
                    
       if amsg.strip() <> "":     
          let db = open(cxchatdb, "", "", "")  
          db.exec(sql"INSERT INTO CRYXDATA (CLIENT, MSG) VALUES (?,?)" , auser ,amsg)
          db.close()   
  
       # Send the message to other connected clients.
       for c in server.clients:
          # Don't send it to the client that sent this or to a client that is disconnected.
          if c.id != client.id and c.connected:
              await c.socket.send(line & "\c\l")        
       
            
proc loop(server: Server, port = port) {.async.} =
  ## Loops forever and checks for new connections.

  # Bind the port number specified by ``port``.
  server.socket.bindAddr(port.Port)
  # Ready the server socket for new connections.
  server.socket.listen()
  printLnStatusMsg(cxpad("Listening Port : " & $port,55))
  printLnStatusMsg(cxpad("Started at     : " & cxnow,55),colLeft=lime)
  printLnStatusMsg(cxpad("Ready. Awaiting connections ...",55),colLeft=lime)
  echo()
  var tempclient = "" 
  
  while true:
    # Pause execution of this procedure until a new connection is accepted.
    let (netAddr, clientSocket) = await server.socket.acceptAddr()
    printLnInfoMsg("Connection  ",cxpad(netAddr & " at " & cxnow,51),yellowgreen)
    
    # we remember the id count
    var oldclientscount = server.clients.len
       
    # Create a new instance of Client.
    let client = Client(
      socket: clientSocket,
      netAddr: netAddr,
      id: server.clients.len,
      connected: true
    )
    # Add this new instance to the server's list of clients.
    server.clients.add(client)
    # now we want to send the last 50 records to the new client only
    let db = open(cxchatdb, "", "", "")
    for qres in db.fastRows(sql"SELECT b.client,b.msg,b.svdate FROM (SELECT r.id,r.svdate,r.client,r.msg FROM cryxdata r ORDER BY r.id DESC LIMIT ?) b ORDER BY b.id ASC" , histreplaycount) :
        #decho(2)
        #echo qres # for query debug use only
        # get the blankvalue so empty messages will not be forwarded to other clients
        let blankvalue = decryptFromBase64(qres[1],key).strip()   
        if blankvalue <> "" :
                var tempclientnew = $client
                #needs to be done for sqllite result here    
                #also need to unpack the cursor to get the data for the histDataMsg
                var v0 = qres[0]
                var v1 = qres[1]
                var v2 = qres[2]
                var histclient = v0 & "[H]"
                var histamsg = v1  
                var histdate = v2
                var histdata = " "
                #echo histdate," ",histclient , decryptFromBase64(histamsg,key).strip()    # for debug use only
                if histamsg.len > 0:
                   histdata = histdate & " --> " & decryptFromBase64(histamsg,key).strip(false,true)  
                else:
                   histdata = histdate & " --> nil"             
                histamsg = encryptToBase64(histdata,key) 
                var serverFlowVar3 = spawn histDataMsg(tempclientnew,amsg=histamsg)    # <----
                var histmsg = createMessageHist(histclient, ^serverFlowVar3)
                for c in server.clients:
                    # Only send to new client and not the currently connected ones.
                    if c.id == client.id and c.connected:
                          await c.socket.send(histmsg)
    db.close()
    
    # here we try to inform the others in case there was a new connection 
    if oldclientscount < server.clients.len:   # if true then someone must have connected to the server
        
         var cusr = ""
         for x in 0 ..< sessioncon.len:
            if sessioncon[x][0] == client.id:
                cusr = sessioncon[x][1] # hopefully we get the name
        
         var serverFlowVar2 = spawn connectMsg($client,cusr=cusr)
         var cmsg = createMessage(chatname, ^serverFlowVar2)
                         
         for c in server.clients:
         # Don't send it to the client that sent this or to a client that is disconnected.
             if c.id != client.id and c.connected:
               await c.socket.send(cmsg)
    
    # send a message to all clients giving connection status
    asyncCheck sleepAlways(server,client)  
    asyncCheck sleepKadang(server,client)  # tested works almost ok 
    # Run the ``processMessages`` procedure asynchronously in the background,
    # this procedure will continuously check for new messages from the client.
    asyncCheck processMessages(server, client)
    #await sendHello(server,client)   # sends a message to all clients , how to do it like every 3 mins ? 
    asyncCheck sleepServerUptime(server)         # write local
    
when isMainModule:
  serverTimer.startTimer  
  cleanScreen()
  decho(2)
  println2(hlf,deepskyblue,styled={stylebright})

  # we only store last 500 records , on server startup this maintenance delete query will be run
  
  let keeplast500 = sql"""DELETE FROM cryxdata
  WHERE id <= (
    SELECT id
    FROM (
      SELECT id
      FROM cryxdata    
	  ORDER BY id DESC
      LIMIT 1 OFFSET 500 
    ) foo
  )
  """   
  
  let db = open(cxchatdb, "", "", "")
  db.exec(keeplast500)
  db.close() 
  
  # Initialise a new server.
  hdx(printLnInfoMsg("CXCHAT" ,"  System Server        Version: " & serverversion & " - qqTop 2019  "))
  var server = newServer()
  var ngrokport = ""
  
  try:
     ngrokport = getPortServerside()
  except :
     printLnErrorMsg("  The ngrok port not specified. cxserver ngrokport       ") 
     printLnErrorMsg("  Try to run : ngrok tcp $1 in a new terminal first ! " % $port)
     printLnFailMsg("  cxserver could not be initialized.                     ")
     doFinish()
     
  printLnStatusMsg(cxpad("cxServer initialised!  ",55))   
  printLnStatusMsg(cxpad("Connection via : 0.tcp.ap.ngrok.io:" & ngrokport,55))
  printLnStatusMsg(cxpad("Processing port for cxclient ... ",55))
  try:
    writeport(path3,ngrokport)
  except:
    printLnErrorMsg("  Try to run : ngrok tcp $1 in a new terminal first ! " % $port)
    doFinish()
     
  # Execute the ``loop`` procedure. The ``waitFor`` procedure will run the
  # asyncdispatch event loop until the ``loop`` procedure finishes executing.
  waitFor loop(server)

# end of cxserver 
