import Foundation
import Quick
import Nimble

func in_addr_from_sockaddr<T>(address: sockaddr, closure: (UnsafePointer<Void>) -> T) -> T {
    var a = address
    var result: T? = nil
    
    if Int32(a.sa_family) == PF_INET {
        withUnsafePointer(&a) { sockaddr_ptr in
            let sockaddr_in_ptr = unsafeBitCast(sockaddr_ptr, UnsafePointer<sockaddr_in>.self)
            var in_addr = sockaddr_in_ptr.memory.sin_addr
            withUnsafePointer(&in_addr) {
                result = closure(unsafeBitCast($0, UnsafePointer<Void>.self))
            }
        }
    }
    
    if Int32(a.sa_family) == PF_INET6 {
        withUnsafePointer(&a) { sockaddr_ptr in
            let sockaddr_in6_ptr = unsafeBitCast(sockaddr_ptr, UnsafePointer<sockaddr_in6>.self)
            var in_addr = sockaddr_in6_ptr.memory.sin6_addr
            withUnsafePointer(&in_addr) {
                result = closure(unsafeBitCast($0, UnsafePointer<Void>.self))
            }
        }
    }
    
    return result!
}

func numericAddress(address: sockaddr) -> String {
    return in_addr_from_sockaddr(address) { (in_addr: UnsafePointer<Void>) -> String in
        let buf = UnsafeMutablePointer<Int8>.alloc(256)
        inet_ntop(Int32(address.sa_family), in_addr, buf, 256)
        return String.fromCString(unsafeBitCast(buf, UnsafeMutablePointer<CChar>.self))!
    }
}

class NameResolverTests: QuickSpec {
    override func spec() {
        describe("NameResolver#run") {
            it("resolves hostname to sockaddrs") {
                let resolver = NameResolver(hostname: "google.com", port: 80);
                resolver.run();
                print(resolver.status)
                expect(resolver.status).to(equal(NameResolverState.Resolved));
                expect(resolver.results.count).to(beGreaterThan(0));
                expect(resolver.IPv4Results.count + resolver.IPv6Results.count).to(equal(resolver.results.count))
            }

            it("resolves numeric name to sockaddrs") {
                let resolver = NameResolver(hostname: "8.8.8.8", port: 80);
                resolver.run();
                expect(resolver.status).to(equal(NameResolverState.Resolved));
                expect(resolver.results.count).to(equal(1));
                expect(numericAddress(resolver.results.first!)).to(equal("8.8.8.8"))
            }
            
            it("resolves to empty") {
                let resolver = NameResolver(hostname: "no-such-host.soutaro.com", port: 80);
                resolver.run();
                
                let expectedError = NSError(
                    domain: SMHTTPClientErrorDomain,
                    code: SMHTTPClientErrorCode.NameResolutionFailure.rawValue,
                    userInfo: ["NSLocalizedDescription": "nodename nor servname provided, or not known"])
                expect(resolver.status).to(equal(NameResolverState.Error(expectedError)));
                expect(resolver.results.count).to(equal(0));
            }
            
            it("can be aborted during resolve") {
                let resolver = NameResolver(hostname: "no-such-host.local", port: 80);
                
                let queue = dispatch_queue_create("name-resolver-test.test", nil);
                
                let delay = 0.5 * Double(NSEC_PER_SEC)
                let time  = dispatch_time(DISPATCH_TIME_NOW, Int64(delay))
                dispatch_after(time, queue, {
                    expect(resolver.status).to(equal(NameResolverState.Running));
                    resolver.abort();
                })
                
                let startTime = NSDate()
                
                resolver.run();
                
                let endTime = NSDate()
                
                expect(resolver.status).to(equal(NameResolverState.Aborted));
                expect(resolver.results.count).to(equal(0));
                expect(endTime.timeIntervalSinceDate(startTime)).to(beLessThan(1));
            }
        }
    }
}