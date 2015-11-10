import Foundation

public enum NameResolverState: Equatable {
    case Initialized;
    case Running;
    case Resolved;
    case Error(NSError);
    case Aborted;
}

public func ==(a: NameResolverState, b: NameResolverState) -> Bool {
    switch (a, b) {
    case (.Initialized, .Initialized): return true;
    case (.Running, .Running): return true;
    case (.Resolved, .Resolved): return true;
    case (.Error(let e), .Error(let f)) where e == f: return true;
    case (.Aborted, .Aborted): return true;
    default: return false;
    }
}

public class NameResolver {
    private var _results: [sockaddr];
    private var _status: NameResolverState;
    private let _mutex: dispatch_queue_t;
    private let _semaphore: dispatch_semaphore_t;
    
    let hostname: String;
    let port: UInt;
    
    public init(hostname: String, port: UInt) {
        self._results = [];
        self._status = .Initialized;
        
        self.hostname = hostname;
        self.port = port;
        
        self._mutex = dispatch_queue_create("com.soutaro.SMHTTPClient.NameResolver.mutex", nil);
        self._semaphore = dispatch_semaphore_create(0);
    }
    
    public func run() {
        dispatch_sync(self._mutex) {
            self._status = .Running;
        }
        
        let resolveQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        
        dispatch_async(resolveQueue) {
            let result = UnsafeMutablePointer<UnsafeMutablePointer<addrinfo>>.alloc(1)
            
            var hints: addrinfo = addrinfo(ai_flags: 0, ai_family: PF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: UnsafeMutablePointer<Int8>(), ai_addr: UnsafeMutablePointer<sockaddr>(), ai_next: UnsafeMutablePointer<addrinfo>());
            let ret = withUnsafePointer(&hints) { hintsPtr in
                self.hostname.withCString() { namePtr in
                    String(self.port).withCString() { portPtr in
                        getaddrinfo(namePtr, portPtr, hintsPtr, result)
                    }
                }
            }
            
            dispatch_sync(self._mutex) {
                if self._status == .Aborted {
                    return;
                }
                
                if ret == 0 {
                    // success
                    var addrs: [sockaddr] = []
                    
                    var a: UnsafeMutablePointer<addrinfo> = result.memory
                    while a != UnsafeMutablePointer<addrinfo>() {
                        addrs.append(a.memory.ai_addr.memory)
                        a = a.memory.ai_next
                    }
                    
                    self._results = addrs
                    self._status = .Resolved;
                } else {
                    // error
                    let message = String.fromCString(gai_strerror(ret))
                    let nserror = NSError(
                        domain: SMHTTPClientErrorDomain,
                        code: SMHTTPClientErrorCode.NameResolutionFailure.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: message!]
                    );
                    self._status = .Error(nserror);
                }
                
                dispatch_semaphore_signal(self._semaphore);
            }
        }
        
        dispatch_semaphore_wait(self._semaphore, DISPATCH_TIME_FOREVER);
    }
    
    public func abort() {
        dispatch_sync(self._mutex) {
            if self._status == .Running || self._status == .Initialized {
                self._status = .Aborted;
                self._results.removeAll();
                dispatch_semaphore_signal(self._semaphore);
            }
        }
    }
    
    public var results: [sockaddr] {
        get {
            return self._results;
        }
    }
    
    public var IPv4Results: [sockaddr] {
        get {
            return self._results.filter { Int32($0.sa_family) == PF_INET }
        }
    }
    
    public var IPv6Results: [sockaddr] {
        get {
            return self._results.filter { Int32($0.sa_family) == PF_INET6 }
        }
    }
    
    public var status: NameResolverState {
        get {
            return self._status;
        }
    }
}