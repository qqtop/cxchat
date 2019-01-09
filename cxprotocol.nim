# cxprotocol.nim
# part of cxchat
# 
# Last : 2019-01-09
# 
# the keyfile used for encryption/decryption is called niip.wsx and currently must be in
# <homedir>/.cxchat . This directory is automatically created the keyfile must be provided
# by the cxserver admin to the cxclient user. It is a plaintext file with any number of random chars.
# 

import base64
import nimcx


# change this accordingly to reach your github repo
let githubrepo = ""   # <---- name of your github account here
let crydatapath* = "https://raw.githubusercontent.com/" & githubrepo & "/cryxtemp/master/crydata1.txt"

if githubrepo == "":
   printLnErrorMsg("You need to set correct githubrepo in cxprotocol.nim first then recompile cxserver and cxclient")
   doFinish() 

let chatname* = "CXCHAT"  # used as identifier in server push messages
 
# encryption/decryption code based on xxtea-nim 
let niipwsxdir = getHomeDir() & ".cxchat/"
let niipwsx =  niipwsxdir & "niip.wsx"  # path to keyfile, content can be anything , keyfile must be available to server and clients
if dirExists(niipwsxdir) == false:  newdir(niipwsxdir)
if fileExists(niipwsx) == false:            
    # exit if file not found                
    echo()  
    let tmsg = "Installation path error . Protocol Error No. E101 keyfile does not exist.    "
    printLnErrorMsg(tmsg)
    printLnErrorMsg("contact cxserver admin for the keyfile or copy it into directory shown below.")
    printLnErrorMsg(cxpad("Put your keyfile niip.wsx into " & niipwsxdir,tmsg.len))
    printLnErrorMsg(cxpad("Currently cannot continue. Bye Bye",tmsg.len))
    doFinish()   
    
# read in the keydata
var f = system.open(niipwsx,fmread)
let key* = f.readAll()
f.close()

# start crypto stuff

const DELTA = 0x9e3779b9'u32

proc mx(sum: uint32, y: uint32, z: uint32, p: int, e: int, k: openArray[uint32]): uint32 =
    result = (z shr 5 xor y shl 2) + (y shr 3 xor z shl 4) xor (sum xor y) + (k[p and 3 xor e] xor z)

proc encrypt(v: var seq[uint32], k: seq[uint32]): seq[uint32] =
    if v.len < 2: return v
    var n = v.len - 1
    var z = v[n]
    var sum = 0'u32
    var y: uint32
    var q = 6 + 52 div v.len
    var e: int
    while 0 < q:
        dec(q)
        sum = sum + DELTA
        e = (sum shr 2 and 3).int
        for p in countup(0, n - 1):
            y = v[p + 1]
            v[p] = v[p] + mx(sum, y, z, p, e, k)
            z = v[p]
        y = v[0]
        v[n] = v[n] + mx(sum, y, z, n, e, k)
        z = v[n]
    return v

proc decrypt(v: var seq[uint32], k: seq[uint32]): seq[uint32] =
    if v.len < 2: return v
    var n = v.len - 1
    var z: uint32
    var y = v[0]
    var sum = uint32(6 + 52 div v.len) * DELTA;
    var e: int
    while sum != 0:
        e = (sum shr 2 and 3).int
        for p in countdown(n, 1):
            z = v[p - 1]
            v[p] = v[p] - mx(sum, y, z, p, e, k)
            y = v[p]
        z = v[n]
        v[0] = v[0] - mx(sum, y, z, 0, e, k)
        y = v[0]
        sum = sum - DELTA
    return v

proc fixkey(key: string): string =
    if key.len == 16: return key
    if key.len > 16: return key[0..16]
    result = newString(16)
    result[0 .. key.len - 1] = key

proc toUint32Seq(data: string, includeLength: bool): seq[uint32] =
    var len = data.len
    var n = len shr 2
    if (len and 3) != 0: inc(n)
    if includeLength:
        newSeq(result, n + 1)
        result[n] = uint32(len)
    else:
        newSeq(result, n)
    for i, value in data:
        result[i shr 2] = result[i shr 2] or uint32(ord(value) shl ((i and 3) shl 3))

proc toString(data: seq[uint32], includeLength: bool): string =
    var n = data.len shl 2
    if includeLength:
        var m = int(data[^1])
        n -= 4
        if (m < n - 3) or (m > n): return ""
        n = m
    result = newString(n)
    for i in countup(0, n - 1):
        result[i] = chr(int((data[i shr 2] shr uint32((i and 3) shl 3)) and 0xff))

proc encrypt*(data, key: string): string =
    ## encrypt data with key.
    ## return binary string encrypted data or nil on failure.
    if data.len == 0:
        return ""
    else:
         var v = toUint32Seq(data, true)
         var k = toUint32Seq(fixkey(key), false)
         return toString(encrypt(v, k), false)

proc decrypt*(data, key: string): string =
    ## decrypt binary string encrypted data with key.
    ## return decrypted string or nil on failure
    if data.len == 0:
        return ""
      
    else:  
        var v = toUint32Seq(data, false)
        var k = toUint32Seq(fixkey(key), false)
        return toString(decrypt(v, k), true)

proc encryptToBase64*(data, key: string): string =
    ## encrypt data with key.
    ## return base64 string encrypted data or nil on failure.
    return base64.encode(encrypt(data, key))

proc decryptFromBase64*(data, key: string): string =
    ## decrypt base64 string encrypted data with key.
    ## return decrypted string or nil on failure
    return decrypt(base64.decode(data), key)
      
# end crypto stuff


type
  Message* = object
    username*: string
    message*: string

  MessageParsingError* = object of Exception

proc parseMessage*(data: string): Message {.raises: [MessageParsingError, KeyError].} =
  
  var dataJson: JsonNode
  if data.len == 0 :
    result.message = ""
  else:
     try:
       dataJson = parseJson(data)
     except JsonParsingError:
       printLnErrorMsg("This client has disconnected now ! Please try to restart client again.")
       decho(2)
       raise newException(MessageParsingError, "Invalid JSON: " & "\n" & "  " & getCurrentExceptionMsg())
     except:
       raise newException(MessageParsingError, "Unknown error: " & "\n" & "  " & getCurrentExceptionMsg())

     if not dataJson.hasKey("username"):
       raise newException(MessageParsingError, "Username field missing")

     result.username = dataJson["username"].getStr()
     if result.username.len == 0:
       raise newException(MessageParsingError, "Username field is empty")

     if not dataJson.hasKey("message"):
       raise newException(MessageParsingError, "Message field missing")
     result.message = dataJson["message"].getStr()
     
     if result.message.len == 0:
        result.message = "" 
       

proc createMessage*(username, message: string): string =
    result = $(%{
      "username": %username,
      "message": %encryptToBase64(" " & message,key)
    }) & "\c\l" 
 

proc createMessageHist*(username, message: string): string =
    # used for sending historical messages which are encrypted in the database so no need encryptToBase64
    result = $(%{
      "username": %username,
      "message": %message
    }) & "\c\l"   
    

# end of cxprotocol.nim

