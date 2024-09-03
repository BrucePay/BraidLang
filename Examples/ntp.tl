;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Simple example of .NET socket programming with Braid: an NTP client
; (Adapted from an MSDN C# sample).
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(let ntpServer "time.windows.com")

; Utility to switch the endianness of a word
(defn SwapEndianness [word]
    (bor
        (band word 0xff       | shiftl 24)
        (band word 0xff00     | shiftl 8)
        (band word 0xff0000   | shiftr 8)
        (band word 0xff000000 | shiftr 24)
    )
)

; NTP message size - 16 bytes of the digest (RFC 2030)
(const ntpData (new ^byte[] 48))

; Setting the Leap Indicator, Version Number and Mode values
; LI = 0 (no warning), VN = 3 (IPv4 only), Mode = 3 (Client Mode)
(!! ntpData 0 (^byte? 0b0_011_011))

; get the IP address of the NTP server
(let addresses (.System.Net.Dns/GetHostEntry ntpServer | .AddressList))

; The UDP port number assigned to NTP is 123
(let ipEndPoint (new ^System.Net.IPEndPoint (addresses[0]) 123))

; create the socket object; NTP uses UDP
(let socket
    (new ^System.Net.Sockets.Socket
        .System.Net.Sockets.AddressFamily/InterNetwork
        .System.Net.Sockets.SocketType/Dgram
        .System.Net.Sockets.ProtocolType/Udp
    )
)

(.Connect socket ipEndPoint)

; Stops code hang if NTP is blocked
(.ReceiveTimeout socket 3000)

(.Send    socket ntpData)
(.Receive socket ntpData)
(.Close   socket)

; Offset to get to the "Transmit Timestamp" field (time at which the reply 
; departed the server for the client, in 64-bit timestamp format."
(let ^byte? serverReplyTime 40)

; Get the seconds part
(let intPart   (.BitConverter/ToUInt32 ntpData serverReplyTime))

; Get the seconds fraction
(let fractPart (.BitConverter/ToUInt32 ntpData (+ serverReplyTime 4)))

; Convert From big-endian to little-endian
(let intPart   (SwapEndianness intPart))
(let fractPart (SwapEndianness fractPart))

; convert to milliseconds using the "=" infix macro.
(let milliseconds (= intpart*1000 + fractPart*1000 / 0x1_0000_0000))

; Compute the UTC time then add the milliseconds.
(let networkDateTime (new ^DateTime 1900 1 1 0 0 0 .DateTimeKind/Utc
    | .AddMilliseconds milliseconds))

; Finally convert it to local time and return it.
(.ToLocalTime networkDateTime)

