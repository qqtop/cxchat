import asyncdispatch, asyncnet,threadpool,db_sqlite
import nimcx,cxprotocol


# Application : cxserver.nim 
# Backend     : sqlite  
# Client      : cxclient.nim
# Last        : 2018-12-24
#
# Other reuirements : ngrok
# 
# 1) terminal 1   : ngrok TCP 7679
# 2) terminal 2   : cxserver
# 3) terminal 3   : cxclient wuff    # any name is fine
# 4) browser      : http://127.0.0.1:4040/status
# 
# 
# some notes :
#   FlowVar[T] is for spawned procedure in a thread and Future[T] is for async procedures  
#   future now in the sugar.nim module
#   'await' in an async procedure accepts futures

# cxserver now keeps state in a sqlite.db with required name : cxchat.db
# last 50 recs will be replayed to a newly connected user only
# username is stored in plaintext, usermessages are encrypted using 

# below the schema use"/crydata1.txt"d
# let dbsqlitedb = "/data5/dbmaster/cryxchatsqlite.db" 
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


let serverversion = "2.0 sqlite"
var cxchatdb = "cxchat.db"
var path1 = getAppdir()
var path2 = path1 & "/cxdata1.txt"
echo path2
let port = 7679
let servername = "Cryxserver"   # note: client expects this , change this name will need changes in client
var lastaction = epochTime()
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
var activeids = ""  # experimental to show ids in a server push msg
    

proc newServer(): Server =
  ## Constructor for creating a new ``Server``.
  Server(socket: newAsyncSocket(), clients: @[])

proc `$`(client: Client): string =
  ## Converts a ``Client``'s information into a string.
  "Client-Id : " & $client.id & " (" & client.netAddr & ")"

proc getClientIds(server: Server):seq[string] =
     # returns all connected/active clientids in a seq              
     var resultx = newSeq[string]()
     for c in server.clients:
          # Only add connected clients
          if c.connected:
               resultx.add($c.id)
     result = resultx   
     
             
proc disconnectMsg(aclient:string,aservername:string=servername):string =
    result = aclient.split("(")[0] & " disconnected from " & aservername  
    
proc noNews(aservername:string=servername,acounterval:int):string = 
        # maybe we can splice in some news like exchange rate or top new from the guardian or something
        result = "Currently no news from " & aservername & " No.: " & $acounterval   
    
proc connectMsg(aclient:string,aservername:string=servername):string =
    result = aclient.split("(")[0] & " connected to " & aservername
    
proc infoMsg(aclient:string,aservername:string=servername,clientcount:int,clientId:string,activeIds:string):string =    
    # used to send auto message to clients via sendHello
    if clientcount == 1 :
          result = cxpad("{Message} " & $clientcount & " user online. Your Client-Id: " & clientId,55)   
    else:
          result = cxpad("{Message} " & $clientcount & " users online. Active Ids: " & activeids & " Chat away.",55)  

proc histDataMsg(aclient:string,aservername:string=servername,amsg:string):string =        
     # displaying historical data to new connection
     result = amsg
          
proc getPortServerside(url:string = "http://127.0.0.1:4040/status"):string =
  # gets the port from where ngrok runs to be written to gist or a file
  result = ""
  let client = newHttpClient()
  let zcontent = client.getContent(url)
  for line in zcontent.splitLines():
     if line.contains("0.tcp.ap.ngrok.io:"):
        var l2 = line.split("o:")[1]
        var l3 = l2.split("""\",""")
        result = l3[0]
 
proc cxwrap(aline:string,wrappos:int = 70,xpos:int=1) =
     for wline in wrapWords(aline.strip(),72).splitLines():
             printLn(wline.strip(),termwhite,xpos=28)
        
proc writeport(afile:string) =
    var f = system.open(afile,fmWrite)
    f.writeLine(getPortServerside())
    f.close
    discard chdir(path1)

    decho(2) 
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
    printBiCol("git add .    ",xpos = 1)
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
     let line = "{Message} at "
     let nobody = "  Nobody online. "
     let clientcount = getClientCount(server)
     let tempclient = $client
                 
     # write some info on the server terminal if there is something new to report        
     if (clientcount == 0) and (lastmsg != nobody):         
        printLnStatusMsg(line & cxnow & nobody) 
        lastmsg = nobody 
        
     # send message to connected clients unless last message was the same as new message   
     elif (clientcount > 0) and (lastmsg != "  Users online : " & $clientcount):
        printLnStatusMsg(line & cxnow & "  Users online : " & $clientcount)
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
               # client id's are not reused in a session 
               var clientId = $c.id
               var serverFlowVar = spawn infoMsg(tempclient,clientcount=clientcount,clientId=clientId,activeids=activeids)
               let bmsg = createMessage("CRYX  ", ^serverFlowVar)
               await c.socket.send(bmsg)  
               
     else:
        discard 
               
     return     

     
proc  sendNews(server: Server, client: Client) {.async.} =
        let tempserver = "CRYX" 
        acounter.add                 
        var serverFlowVar = spawn noNews(tempserver,acounterval = acounter.value)
        let bmsg = createMessage("CRYX  ", ^serverFlowVar)
        var nc = 1   # a counter to limt the message sending   --> this now works
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
        
        
proc sleepKadang(server: Server, client: Client)  {.async.} =    
    while true: 
      await sleepAsync(50000)          # wait 50 secs       
      await sendNews(server,client)    # send stuff if there is someone to send to
     
     
proc processMessages(server: Server, client: Client) {.async.} =
  ## Loops while ``client`` is connected to this server, and checks
  ## whether a message has been received from ``client``.
  var tempclient = "" 
  var s = epochTime()
  while true:
    # Pause execution of this procedure until a line of data is received from ``client``.
    var line = await client.socket.recvLine() # The ``recvLine`` procedure returns ``""`` (i.e. a string of length 0) when ``client`` has disconnected.
    if line.len == 0:
       printLnInfoMsg("Disconnected   ", $client & " at " & cxnow,truetomato)
       tempclient = $client
       client.connected = false
       # When a socket disconnects it must be closed.
       client.socket.close()
       # dissconnect message block sends the information message of a disconnect to all other live clients
       var serverFlowVar = spawn disconnectMsg(tempclient)
       var bmsg = createMessage("CRYX  ", ^serverFlowVar)
       tempclient = ""
       for c in server.clients:
          # Don't send it to the client that sent this or to a client that is disconnected.
              if c.id != client.id and c.connected:
                 await c.socket.send(bmsg)
       return 
       # end of disconnect message block  
        
    else:    
       # Display the message that was sent by the client undecoded.
       printlnBiCol($client & " sent: " & line,xpos = 1)
       # we keep state now , there is an issue with long lines which are not saved into the database 
       # for some reasons , maybe has todo with the end of line chars ... hmmmm
       
       let msgparsed = parseMessage(line)
       let auser = msgparsed.username
       let amsg =  msgparsed.message
       #if amsg.strip() <> "2neSRotwBwc=":  # avoid blanks
       if amsg.strip() <> "":     
          #let cryxinsert = "INSERT INTO CRYXDATA (CLIENT, MSG) VALUES ('$1','$2')" % [auser ,amsg]
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
    # Pause execution of this procedure until a new connecti"Item#" & $ion is accepted.
    let (netAddr, clientSocket) = await server.socket.acceptAddr()
    printLnInfoMsg("Connection from",netAddr & " at " & cxnow,yellowgreen)
    
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
    # WIP
    let db = open(cxchatdb, "", "", "")
    
    #let cryxselect = sql"SELECT b.client,b.msg,b.svdate FROM (SELECT first 50 r.id,r.svdate,r.client,r.msg FROM cryxdata r ORDER BY r.id DESC) b ORDER BY b.id ASC"
    for qres in db.fastRows(sql"SELECT b.client,b.msg,b.svdate FROM (SELECT r.id,r.svdate,r.client,r.msg FROM cryxdata r ORDER BY r.id DESC) b ORDER BY b.id ASC LIMIT 50"):
        decho(2)
        echo qres
        if qres[1] <> "2neSRotwBwc=":
                       
                var tempclientnew = $client
                #needs to be done for sqllite result here    
                #also need to unpack the cursor to get the data for the histDataMsg
                var v0 = qres[0]
                var v1 = qres[1]
                var v2 = qres[2]
                var histclient = v0 & "[H]"
                var histamsg = v1  # maybe the longline issue (not decypting is here) not sure yet
                var histdate = v2
                var histdata = " "
                # have a problem here somewhere
                echo histdate," ",histclient , decryptFromBase64(histamsg,key).strip()
                
                if histamsg.len > 0:
                   histdata = histdate & " --> " & decryptFromBase64(histamsg,key).strip()  
                else:
                   histdata = histdate & " --> nil"             
                histamsg = encryptToBase64(histdata,key) 
                var serverFlowVar3 = spawn histDataMsg(tempclientnew,amsg=histamsg)    # <----
                var histmsg = createMessageHist(histclient, ^serverFlowVar3)
                for c in server.clients:
                    # Only send to new client and not the currentlyt connected ones.
                    if c.id == client.id and c.connected:
                          await c.socket.send(histmsg)
    db.close()
    
    # here we try to inform the others in case there was a new connection 
    if oldclientscount < server.clients.len:   # if true then someone must have connected to the server
         var serverFlowVar2 = spawn connectMsg($client)
         var cmsg = createMessage("CRYX  ", ^serverFlowVar2)
         
         for c in server.clients:
         # Don't send it to the client that sent this or to a client that is disconnected.
             if c.id != client.id and c.connected:
               await c.socket.send(cmsg)
    
    # send a message to all clients giving connection status
    asyncCheck sleepAlways(server,client)  
    #asyncCheck sleepKadang(server,client)  # tested works almost ok 
    # Run the ``processMessages`` procedure asynchronously in the background,
    # this procedure will continuously check for new messages from the client.
    asyncCheck processMessages(server, client)
    #await sendHello(server,client)   # sends a message to all clients , how to do it like every 3 mins ? callback future wtf ..
    
# Check whether this module has been imported as a dependency to another
# module, or whether this module is the main module.


when isMainModule:
  # Initialise a new server.
  hdx(printLnInfoMsg("Cxserver      " ,"cxChat System Server    Version: " & serverversion & " - qqTop 2018  "))
  var server = newServer()
  printLnStatusMsg(cxpad("Server initialised!  ",55))
  printLnStatusMsg(cxpad("Processing ports ... ",55))
  try:
    writeport(path2)
  except:
    printLnErrorMsg("Try to run : ngrok tcp $1 in a new terminal first !   " % $port)
    doFinish()
     
  # Execute the ``loop`` procedure. The ``waitFor`` procedure will run the
  # asyncdispatch event loop until the ``loop`` procedure finishes executing.
  waitFor loop(server)

# end of server fro cryxchat  
