import Foundation
import Quick
import Nimble
import GCDWebServer

func requestSuccessfullyCompleted(request: HttpRequest) -> Bool {
    switch request.status {
    case .Completed(_): return true
    default: return false
    }
}

func requestHasError(request: HttpRequest) -> Bool {
    switch request.status {
    case .Error(_): return true
    default: return false
    }
}

func requestIsAborted(request: HttpRequest) -> Bool {
    return request.status == .Aborted
}

func valueOfHeader(header: [(String, String)], name: String) -> String? {
    let entry = header.filter() { (e: (String, String)) -> Bool in
        let (key, _) = e
        return key.uppercaseString == name.uppercaseString
    }.first
    
    if let (_, v) = entry {
        return v
    } else {
        return nil
    }
}

class HttpRequestTests: QuickSpec {
    override func spec() {
        var address: sockaddr?
        var server: GCDWebServer?
        
        beforeEach {
            let resolver = NameResolver(hostname: "localhost", port: 8080)
            resolver.run()
            address = resolver.IPv4Results.first
            
            server = GCDWebServer()
        }
        
        afterEach {
            address = nil
            
            if server!.running {
                server!.stop()
            }
        }
        
        describe("HttpRequest#connect") {
            describe("establishing connection") {
                it("connects to server") {
                    server!.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                        GCDWebServerResponse(statusCode: 200)
                    })
                    server!.startWithPort(8080, bonjourName: nil)
                    
                    let request = HttpRequest(address: address!, path: "/", method: .GET, header: [])
                    request.run()
                    
                    expect(requestHasError(request)).to(equal(false))
                    expect(requestIsAborted(request)).to(equal(false))
                }
                
                it("sets error if connection failed") {
                    let request = HttpRequest(address: address!, path: "/", method: .GET, header: [])
                    request.run()
                    
                    expect(request.status).to(equal(HttpRequestStatus.Error(NSError(domain: NSPOSIXErrorDomain, code: 61, userInfo: [:]))))
                }
            }
            
            describe("Sending request") {
                it("sends path") {
                    var requestedPath: String = ""
                    server!.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                        requestedPath = request.path
                        return GCDWebServerResponse(statusCode: 200)
                    })
                    server!.startWithPort(8080, bonjourName: nil)
                    
                    let request = HttpRequest(address: address!, path: "/test123", method: .GET, header: [("Connection", "close")])
                    request.run()
                    
                    expect(requestSuccessfullyCompleted(request)).to(beTrue())
                    expect(requestedPath).to(equal("/test123"))
                }
                
                it("sends header") {
                    var requestHeader: [NSObject: AnyObject] = [:]
                    server!.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                        requestHeader = request.headers
                        return GCDWebServerResponse(statusCode: 200)
                    })
                    server!.startWithPort(8080, bonjourName: nil)
                    
                    let request = HttpRequest(address: address!, path: "/test123", method: .GET, header: [("Connection", "close"), ("Host", "localhost")])
                    request.run()
                    
                    expect(requestSuccessfullyCompleted(request)).to(beTrue())
                    expect(requestHeader["Host"] as? String).to(equal("localhost"))
                    expect(requestHeader["Connection"] as? String).to(equal("close"))
                }
                
                it("sends body") {
                    var requestJson: AnyObject = []
                    server!.addDefaultHandlerForMethod("POST", requestClass: GCDWebServerDataRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                        let dataRequest: GCDWebServerDataRequest = request as! GCDWebServerDataRequest
                        requestJson = dataRequest.jsonObject
                        return GCDWebServerResponse(statusCode: 200)
                    })
                    server!.startWithPort(8080, bonjourName: nil)
                    
                    let jsonData = try! NSJSONSerialization.dataWithJSONObject([1,2,3], options: NSJSONWritingOptions.PrettyPrinted)
                    let request = HttpRequest(address: address!, path: "/test123", method: .POST(jsonData), header: [("Connection", "close"), ("Content-Type", "application/json"), ("Content-Length", String(jsonData.length))])
                    request.run()
                    
                    expect(requestSuccessfullyCompleted(request)).to(beTrue())
                    expect(requestJson as? [Int]).to(equal([1,2,3]))
                }
            }
            
            describe("receiving response") {
                it("receives status code") {
                    server!.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                        return GCDWebServerResponse(statusCode: 404)
                    })
                    server!.startWithPort(8080, bonjourName: nil)
                    
                    let request = HttpRequest(address: address!, path: "/test123", method: .GET, header: [("Connection", "close"), ("Host", "localhost")])
                    request.run()
                    
                    expect(requestSuccessfullyCompleted(request)).to(beTrue())
                    
                    switch request.status {
                    case .Completed(let status, _, _):
                        expect(status).to(equal(404))
                    default:
                        expect(true).to(beFalse())
                    }
                }
                
                it("receives response header") {
                    server!.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                        return GCDWebServerResponse(statusCode: 200)
                    })
                    server!.startWithPort(8080, bonjourName: nil)
                    
                    let request = HttpRequest(address: address!, path: "/test123", method: .GET, header: [("Connection", "close"), ("Host", "localhost")])
                    request.run()
                    
                    expect(requestSuccessfullyCompleted(request)).to(beTrue())
                    
                    switch request.status {
                    case .Completed(_, let h, _):
                        expect(h.count).to(beGreaterThan(0))
                        expect(valueOfHeader(h, name: "Server")!).to(equal("GCDWebServer"))
                    default:
                        expect(true).to(beFalse())
                    }
                }
                
                it("receives identity body") {
                    server!.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                        let response = GCDWebServerDataResponse(text: "Hello World")
                        return response
                    })
                    server!.startWithPort(8080, bonjourName: nil)
                    
                    let request = HttpRequest(address: address!, path: "/test123", method: .GET, header: [("Connection", "close"), ("Host", "localhost")])
                    request.run()
                    
                    expect(requestSuccessfullyCompleted(request)).to(beTrue())
                    
                    switch request.status {
                    case .Completed(_, _, let body):
                        let string = String(data: body, encoding: NSUTF8StringEncoding)
                        expect(string).to(equal("Hello World"))
                    default:
                        expect(true).to(beFalse())
                    }
                }

                it("receives chunked body") {
                    let resolver = NameResolver(hostname: "qiita.com", port: 80)
                    resolver.run()
                    let address = resolver.IPv4Results.first!
                    
                    let request = HttpRequest(address: address, path: "/ryotapoi/items/e674615a613061c08cae", method: .GET, header: [("Connection", "close"), ("Host", "qiita.com")])
                    request.run()
                    
                    expect(requestSuccessfullyCompleted(request)).to(beTrue())
                    
                    switch request.status {
                    case .Completed(_, _, let body):
                        expect(body.length).to(beGreaterThan(0))
                    default:
                        expect(true).to(beFalse())
                    }
                }

                it("receives empty body if the response does not have body") {
                    server!.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                        GCDWebServerDataResponse(text: "Hello World")
                    })
                    server!.startWithPort(8080, bonjourName: nil)
                    
                    let request = HttpRequest(address: address!, path: "/test123", method: .HEAD, header: [("Connection", "close"), ("Host", "localhost")])
                    request.run()
                    
                    expect(requestSuccessfullyCompleted(request)).to(beTrue())
                    
                    switch request.status {
                    case .Completed(let code, _, let body):
                        expect(code).to(equal(200))
                        expect(body.length).to(equal(0))
                    default:
                        expect(true).to(beFalse())
                    }
                }
            }
        }
        
        describe("HttpRequest#abort") {
            it("stops running request") {
                server!.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                    NSThread.sleepForTimeInterval(5)
                    return GCDWebServerDataResponse(text: "Hello World")
                })
                server!.startWithPort(8080, bonjourName: nil)
                
                let request = HttpRequest(address: address!, path: "/test123", method: .HEAD, header: [("Connection", "close"), ("Host", "localhost")])
                
                let queue = dispatch_queue_create("com.soutaro.SMHttpRequestTests.test", nil)
                
                let delay = 0.5 * Double(NSEC_PER_SEC)
                let time  = dispatch_time(DISPATCH_TIME_NOW, Int64(delay))
                dispatch_after(time, queue, {
                    expect(request.status).to(equal(HttpRequestStatus.RequestSent));
                    request.abort();
                })
                
                let start = NSDate()
                
                request.run()
                
                expect(requestIsAborted(request)).to(beTrue())
                expect(NSDate().timeIntervalSinceDate(start)).to(beLessThan(1))
            }
            
            it("does not update status if completed") {
                server!.addDefaultHandlerForMethod("GET", requestClass: GCDWebServerRequest.self, processBlock: { (request: GCDWebServerRequest!) -> GCDWebServerResponse! in
                    return GCDWebServerDataResponse(text: "Hello World")
                })
                server!.startWithPort(8080, bonjourName: nil)
                
                let request = HttpRequest(address: address!, path: "/test123", method: .HEAD, header: [("Connection", "close"), ("Host", "localhost")])
                request.run()
                
                expect(requestSuccessfullyCompleted(request)).to(beTrue())

                request.abort()
                
                expect(requestIsAborted(request)).notTo(beTrue())
            }
        }
    }
}