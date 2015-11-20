import Foundation

public enum HttpMethod {
    case GET;
    case HEAD;
    case POST(NSData);
    case PUT(NSData);
    case PATCH(NSData);
    case DELETE;
}

public enum HttpRequestStatus: Equatable {
    case Initialized;
    case Connecting;
    case Connected;
    case RequestSent;
    case Completed(Int, [(String, String)], NSData);
    case Error(NSError);
    case Aborted;
}

internal func ==(a: [(String, String)], b: [(String, String)]) -> Bool {
    if a.count != b.count {
        return false
    }
    
    return zip(a, b).reduce(true, combine: { (pred, z) in
        let ((x1, y1), (x2, y2)) = z
        return pred && x1 == x2 && y1 == y2
    })
}

public func ==(a: HttpRequestStatus, b: HttpRequestStatus) -> Bool {
    switch (a, b) {
    case (.Initialized, .Initialized): return true
    case (.Connecting, .Connecting): return true
    case (.Connected, .Connected): return true
    case (.RequestSent, .RequestSent): return true
    case (.Completed(let c1, let h1, let d1), .Completed(let c2, let h2, let d2)) where c1 == c2 && h1 == h2 && d1 == d2: return true
    case (.Error(let e1), .Error(let e2)) where e1 == e2: return true
    case (.Aborted, .Aborted): return true
    default: return false
    }
}

private enum HttpRequestError: ErrorType {
    case Error(NSError)
    case Aborted
    case MulformedResponse(String)
}

public class HttpRequest {
    public let address: sockaddr
    public let path: String
    public let method: HttpMethod
    public let requestHeader: [(String, String)]
    
    private var _socket: Int32
    private var _status: HttpRequestStatus
    
    private let _queue: dispatch_queue_t
    private let _semaphore: dispatch_semaphore_t
    
    public init(address: sockaddr, path: String, method: HttpMethod, header: [(String, String)]) {
        self.address = address
        self.path = path
        self.method = method
        self.requestHeader = header
        self._status = .Initialized
        
        self._queue = dispatch_queue_create("com.soutaro.SMHTTPClient.HttpRequest.queue", nil)
        self._semaphore = dispatch_semaphore_create(0)
        
        self._socket = 0
    }
    
    deinit {
        if self._socket != 0 {
            Darwin.close(self._socket)
        }
    }
    
    public var status: HttpRequestStatus {
        get {
            var status: HttpRequestStatus = .Initialized
            dispatch_sync(self._queue) {
                status = self._status
            }
            return status
        }
    }
    
    public func run() {
        self.setStatus(.Connecting);
        
        let q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        dispatch_async(q) {
            do {
                defer {
                    if self._socket != 0 {
                        shutdown(self._socket, SHUT_RDWR)
                    }
                }
                
                try self.connect()
                try self.send()
                try self.receive()
            } catch HttpRequestError.Error(let error) {
                self.setErrorStatus(error)
            } catch HttpRequestError.MulformedResponse(let message) {
                self.setErrorStatus(NSError(domain: SMHTTPClientErrorDomain, code: SMHTTPClientErrorCode.MulformedHTTPResponse.rawValue, userInfo: [NSLocalizedDescriptionKey: message]))
            } catch HttpRequestError.Aborted {
                // Nothing to do
            } catch _ {
                // Nothing to do
            }
            
            dispatch_semaphore_signal(self._semaphore);
        }
        
        dispatch_semaphore_wait(self._semaphore, DISPATCH_TIME_FOREVER);
    }
    
    public func abort() {
        dispatch_sync(self._queue) {
            switch self._status {
            case .Aborted, .Error(_), .Completed(_):
                 break
            default:
                self._status = .Aborted
                if self._socket != 0 {
                    shutdown(self._socket, SHUT_RDWR)
                }
            }
        }
        
        dispatch_semaphore_signal(self._semaphore)
    }
    
    private func connect() throws {
        let sock = socket(Int32(self.address.sa_family), SOCK_STREAM, 0)
        try self.abortIfAborted()
        
        var one: Int32 = 1;
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, UInt32(sizeof(Int32)))
        
        if sock != -1 {
            self._socket = sock
        } else {
            throw HttpRequestError.Error(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
        }
        
        var address = self.address
        let ret = withUnsafePointer(&address) { ptr in
            Darwin.connect(self._socket, ptr, UInt32(ptr.memory.sa_len))
        }
        
        try self.abortIfAborted()
        
        if ret == 0 {
            self.setStatus(.Connected)
        } else {
            throw HttpRequestError.Error(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
        }
    }
    
    private func send() throws {
        let data = NSMutableData()
        
        let requestLine: String
        
        switch self.method {
        case .GET:
            requestLine = "GET \(self.path) HTTP/1.1\r\n"
        case .DELETE:
            requestLine = "DELETE \(self.path) HTTP/1.1\r\n"
        case .POST(_):
            requestLine = "POST \(self.path) HTTP/1.1\r\n"
        case .PUT(_):
            requestLine = "PUT \(self.path) HTTP/1.1\r\n"
        case .PATCH(_):
            requestLine = "PATCH \(self.path) HTTP/1.1\r\n"
        case .HEAD:
            requestLine = "HEAD \(self.path) HTTP/1.1\r\n"
        }
        
        data.appendData(requestLine.dataUsingEncoding(NSUTF8StringEncoding)!)
        
        for (name, value) in self.requestHeader {
            let headerLine = "\(name): \(value)\r\n"
            data.appendData(headerLine.dataUsingEncoding(NSUTF8StringEncoding)!)
        }
        
        data.appendData("\r\n".dataUsingEncoding(NSUTF8StringEncoding)!)
        
        switch self.method {
        case .PATCH(let body):
            data.appendData(body)
        case .PUT(let body):
            data.appendData(body)
        case .POST(let body):
            data.appendData(body)
        default: break
        }
        
        var offset = 0
        while offset < data.length {
            var size = 4096
            if offset + size > data.length {
                size = data.length - offset
            }
            let buf = UnsafeMutablePointer<Void>.alloc(size)
            data.getBytes(buf, range: NSMakeRange(offset, size))
            let ret = Darwin.send(self._socket, buf, size, 0)
            
            if ret >= 0 {
                offset = offset + ret
            } else {
                throw HttpRequestError.Error(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
            }
            
            try self.abortIfAborted()
        }
        
        self.setStatus(.RequestSent)
    }
    
    private func receive() throws {
        let buffer = Buffer() { (buf: UnsafeMutablePointer<UInt8>, size: Int) throws -> Int in
            let read = recv(self._socket, buf, size, 0)
            try self.abortIfAborted()
            if read == 0 {
                throw HttpRequestError.MulformedResponse("recv returned 0 bytes read, through not aborted yet...")
            }
            if read < 0 {
                throw HttpRequestError.Error(NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil))
            }
            return read
        }
        
        let status = try self.readStatusLine(buffer)
        let header = try self.readResponseHeader(buffer)
        let body = self.hasBody(status) ? try self.readBody(header, buffer: buffer) : NSData()
        
        self.setStatus(.Completed(status, header, body))
    }
    
    private func readStatusLine(buffer: Buffer) throws -> Int {
        let line = try buffer.readLine()
        
        if !line.hasPrefix("HTTP/1.1 ") {
            throw HttpRequestError.MulformedResponse("The response does not look like a HTTP/1.1 response")
        }
        
        let code = (line as NSString).substringWithRange(NSRange(location: 9, length: 3))
        return Int(code)!
    }
    
    private func readResponseHeader(buffer: Buffer) throws -> [(String, String)] {
        var header: [(String, String)] = []
        
        while true {
            let line = try buffer.readLine()
            if line == "" {
                return header
            }
            
            if let position = line.characters.indexOf(":") {
                let name = line.substringToIndex(position)
                let value = line.substringFromIndex(position.advancedBy(1))
                let pair = (
                    name,
                    value.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: " "))
                )
                header.append(pair)
            } else {
                throw HttpRequestError.MulformedResponse("Header line looks mulformed... (\(line))")
            }

        }
    }
    
    private func readBody(header: [(String, String)], buffer: Buffer) throws -> NSData {
        let transferEncoding = self.findHeaderValue(header, name: "Transfer-Encoding", defaultEncoding: "identity")
        
        if transferEncoding.componentsSeparatedByString(" ").contains("chunked") {
            let result = NSMutableData()
            while true {
                let chunk = try readNextChunk(buffer)
                if chunk.length > 0 {
                    result.appendData(chunk)
                } else {
                    return result
                }
            }
        } else {
            let contentLength = Int(self.findHeaderValue(header, name: "Content-Length", defaultEncoding: "0"))!
            return try buffer.readData(contentLength)
        }
    }
    
    private func hasBody(statusCode: Int) -> Bool {
        if 100..<200 ~= statusCode {
            // Informational
            return false
        }
        
        if statusCode == 204 {
            // No content
            return false
        }
        
        if statusCode == 304 {
            // Not modified
            return false
        }
        
        switch self.method {
        case .HEAD: return false
        default: return true
        }
    }
    
    private func readNextChunk(buffer: Buffer) throws -> NSData {
        let line = try buffer.readLine()
        let scanner = NSScanner(string: line)
        var size: UInt32 = 0
        scanner.scanHexInt(&size)
        let data = try buffer.readData(Int(size))
        try buffer.readLine()
        return data;
    }
    
    private func findHeaderValue(header: [(String, String)], name: String, defaultEncoding: String) -> String {
        for (k, v) in header {
            if k.uppercaseString == name.uppercaseString {
                return v
            }
        }
        
        return defaultEncoding
    }
    
    private func abortIfAborted() throws {
        var aborted = false
        
        dispatch_sync(self._queue) {
            aborted = self._status == .Aborted
        }
        
        if aborted {
            throw HttpRequestError.Aborted
        }
    }
    
    private func setErrorStatus(error: NSError) {
        switch self._status {
        case .Aborted, .Error(_): return
        default: break
        }
        
        dispatch_sync(self._queue) {
            switch self._status {
            case .Aborted, .Error(_):
                return
            default:
                self._status = .Error(error)
            }
        }
    }
    
    private func setStatus(status: HttpRequestStatus) {
        dispatch_sync(self._queue) {
            switch self._status {
            case .Aborted, .Error(_):
                return
            default:
                self._status = status
            }
        }
    }
}