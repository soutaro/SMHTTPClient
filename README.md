# SMHTTPClient

[![CI Status](http://img.shields.io/travis/soutaro/SMHTTPClient.svg?style=flat)](https://travis-ci.org/soutaro/SMHTTPClient)
[![Version](https://img.shields.io/cocoapods/v/SMHTTPClient.svg?style=flat)](http://cocoapods.org/pods/SMHTTPClient)
[![License](https://img.shields.io/cocoapods/l/SMHTTPClient.svg?style=flat)](http://cocoapods.org/pods/SMHTTPClient)
[![Platform](https://img.shields.io/cocoapods/p/SMHTTPClient.svg?style=flat)](http://cocoapods.org/pods/SMHTTPClient)

SMHTTPClient is a HTTP/1.1 client based on socket API.
Since it does not depend on NSURLSession, application transport security does not prohibit sending plain-text requests with this library.

## Usage

```swift
let resolver = NameResolver(hostname: "your-server.local", port: 80)
resolver.run()
let addr = resolver.results.first!

let request = HttpRequest(address: addr, path: "/", method: .GET, header: [("Host": "your-server.local")])
request.run()

switch request.status {
  case .Completed(let code, let header, let data):
    // Success
  case .Error(let error):
    // An error occured
  case .Aborted:
    // Aborted
  default:
    // ...
}
```

It provides a blocking API.
When you want to cancel a running request, you should call `request.abort()` from another thread.

```swift
let request = HttpRequest(...)
let queue = dispatch_queue_create("abort.queue", nil)

// Timeout after 5 seconds
let delay = 5 * Double(NSEC_PER_SEC)
dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(delay)), queue, {
    request.abort();
})

request.run()

// request.status will be .Aborted
```

## Installation

SMHTTPClient is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod "SMHTTPClient"
```

## Author

Soutaro Matsumoto, matsumoto@soutaro.com

## License

SMHTTPClient is available under the MIT license. See the LICENSE file for more info.
