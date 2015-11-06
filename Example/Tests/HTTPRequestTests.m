//
//  HTTPRequestTests.m
//  SMHTTPClient
//
//  Created by 松本 宗太郎 on 2015/11/06.
//  Copyright © 2015年 Soutaro Matsumoto. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Specta/Specta.h>
#import <GCDWebServer/GCDWebServer.h>
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerRequest.h"
#import "GCDWebServerDataRequest.h"

#import "SMHTTPRequest.h"

SpecBegin(SMHTTPRequestSpecs)

describe(@"+", ^{
    __block GCDWebServer* webServer;
    __block struct sockaddr localhost;
    
    beforeAll(^{
        [SMHTTPRequest resolveHostname:@"localhost" port:8080 callback:^(struct sockaddr *addr) {
            localhost = *addr;
        }];
    });
    
    beforeEach(^{
        webServer = [[GCDWebServer alloc] init];
    });
    
    after(^{
        if (webServer.isRunning) {
            [webServer stop];
        }
    });
    
    describe(@"methods", ^{
        before(^{
            [webServer addDefaultHandlerForMethod:@"GET"
                                     requestClass:[GCDWebServerRequest class]
                                     processBlock:^ GCDWebServerResponse* (GCDWebServerRequest *request) {
                                         if ([request.path isEqualToString:@"/test"]) {
                                             return [GCDWebServerDataResponse responseWithHTML:@"GET content"];
                                         } else {
                                             return nil;
                                         }
                                     }];
            
            [webServer addDefaultHandlerForMethod:@"POST"
                                     requestClass:[GCDWebServerRequest class]
                                     processBlock:^ GCDWebServerResponse* (GCDWebServerRequest *request) {
                                         if ([request.path isEqualToString:@"/test"]) {
                                             return [GCDWebServerDataResponse responseWithHTML:@"POST content"];
                                         } else {
                                             return nil;
                                         }
                                     }];
            
            [webServer addDefaultHandlerForMethod:@"PUT"
                                     requestClass:[GCDWebServerRequest class]
                                     processBlock:^ GCDWebServerResponse* (GCDWebServerRequest *request) {
                                         if ([request.path isEqualToString:@"/test"]) {
                                             return [GCDWebServerDataResponse responseWithHTML:@"PUT content"];
                                         } else {
                                             return nil;
                                         }
                                     }];

            [webServer addDefaultHandlerForMethod:@"DELETE"
                                     requestClass:[GCDWebServerRequest class]
                                     processBlock:^ GCDWebServerResponse* (GCDWebServerRequest *request) {
                                         if ([request.path isEqualToString:@"/test"]) {
                                             return [GCDWebServerDataResponse responseWithHTML:@"DELETE content"];
                                         } else {
                                             return nil;
                                         }
                                     }];

            [webServer startWithPort:8080 bonjourName:nil];
        });
        
        it(@"sends GET request", ^{
            SMHTTPRequest *request = [[SMHTTPRequest alloc] initWithHost:localhost path:@"/test" method:@"GET" body:nil header:nil];
            
            [request run];
            
            expect(request.status).to.equal(SMHTTPRequestStatusSuccess);
            expect(request.responseStatusCode).to.equal(200);
            expect([[NSString alloc] initWithData:request.responseBody encoding:NSUTF8StringEncoding]).to.equal(@"GET content");
        });
        
        it(@"sends POST request", ^{
            SMHTTPRequest *request = [[SMHTTPRequest alloc] initWithHost:localhost path:@"/test" method:@"POST" body:nil header:nil];
            
            [request run];
            
            expect(request.status).to.equal(SMHTTPRequestStatusSuccess);
            expect(request.responseStatusCode).to.equal(200);
            expect([[NSString alloc] initWithData:request.responseBody encoding:NSUTF8StringEncoding]).to.equal(@"POST content");
        });
        
        it(@"sends PUT request", ^{
            SMHTTPRequest *request = [[SMHTTPRequest alloc] initWithHost:localhost path:@"/test" method:@"PUT" body:nil header:nil];
            
            [request run];
            
            expect(request.status).to.equal(SMHTTPRequestStatusSuccess);
            expect(request.responseStatusCode).to.equal(200);
            expect([[NSString alloc] initWithData:request.responseBody encoding:NSUTF8StringEncoding]).to.equal(@"PUT content");
        });

        it(@"sends DELETE request", ^{
            SMHTTPRequest *request = [[SMHTTPRequest alloc] initWithHost:localhost path:@"/test" method:@"DELETE" body:nil header:nil];
            
            [request run];
            
            expect(request.status).to.equal(SMHTTPRequestStatusSuccess);
            expect(request.responseStatusCode).to.equal(200);
            expect([[NSString alloc] initWithData:request.responseBody encoding:NSUTF8StringEncoding]).to.equal(@"DELETE content");
        });
    });
    
    describe(@"message body", ^{
        beforeEach(^{
            [webServer addDefaultHandlerForMethod:@"POST"
                                     requestClass:[GCDWebServerDataRequest class]
                                     processBlock:^ GCDWebServerResponse* (GCDWebServerRequest *request) {
                                         if ([request.path isEqualToString:@"/test"]) {
                                             // Echo posted JSON
                                             GCDWebServerDataRequest *dataRequest = (GCDWebServerDataRequest *)request;
                                             return [GCDWebServerDataResponse responseWithJSONObject:dataRequest.jsonObject];
                                         } else {
                                             return nil;
                                         }
                                     }];
            
            [webServer startWithPort:8080 bonjourName:nil];
        });
        
        it(@"sends message body", ^{
            id jsonObject = @[@1, @2, @3];
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject options:0 error:nil];
            SMHTTPRequest *request = [[SMHTTPRequest alloc] initWithHost:localhost
                                                                    path:@"/test"
                                                                  method:@"POST"
                                                                    body:jsonData
                                                                  header:@{
                                                                           @"Content-Type": @"application/json",
                                                                           @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)jsonData.length]
                                                                           }];
            
            [request run];
            
            expect(request.status).to.equal(SMHTTPRequestStatusSuccess);
            expect(request.responseStatusCode).to.equal(200);
            expect([NSJSONSerialization JSONObjectWithData:request.responseBody options:0 error:nil]).to.equal(jsonObject);
        });
    });
    
    describe(@"response header", ^{
        beforeEach(^{
            [webServer addDefaultHandlerForMethod:@"GET"
                                     requestClass:[GCDWebServerRequest class]
                                     processBlock:^ GCDWebServerResponse* (GCDWebServerRequest *request) {
                                         if ([request.path isEqualToString:@"/test"]) {
                                             // Returns request headers as JSON
                                             return [GCDWebServerDataResponse responseWithJSONObject:request.headers];
                                         } else {
                                             return nil;
                                         }
                                     }];
            
            [webServer startWithPort:8080 bonjourName:nil];
        });
        
        it(@"sends request header", ^{
            SMHTTPRequest *request = [[SMHTTPRequest alloc] initWithHost:localhost
                                                                    path:@"/test"
                                                                  method:@"GET"
                                                                    body:nil
                                                                  header:@{ @"X-Test-Header": @"Hello World" }];
            
            [request run];
            
            expect(request.status).to.equal(SMHTTPRequestStatusSuccess);
            expect(request.responseStatusCode).to.equal(200);
            
            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:request.responseBody options:0 error:nil];
            expect(responseDictionary[@"X-Test-Header"]).to.equal(@"Hello World");
        });
    });
    
    describe(@"error message", ^{
        it(@"sets error status and error property", ^{
            SMHTTPRequest *request = [[SMHTTPRequest alloc] initWithHost:localhost
                                                                    path:@"/test"
                                                                  method:@"GET"
                                                                    body:nil
                                                                  header:@{ @"X-Test-Header": @"Hello World" }];
            
            [request run];
            
            expect(request.status).to.equal(SMHTTPRequestStatusError);
            expect(request.error).notTo.beNil();
        });
    });
    
    describe(@"abort", ^{
        beforeEach(^{
            [webServer addDefaultHandlerForMethod:@"GET"
                                     requestClass:[GCDWebServerRequest class]
                                     processBlock:^ GCDWebServerResponse* (GCDWebServerRequest *request) {
                                         [NSThread sleepForTimeInterval:10];
                                         return [GCDWebServerDataResponse responseWithJSONObject:@[]];
                                     }];
            
            [webServer startWithPort:8080 bonjourName:nil];
        });
        
        it(@"exits from wait data", ^{
            SMHTTPRequest *request = [[SMHTTPRequest alloc] initWithHost:localhost
                                                                    path:@"/test"
                                                                  method:@"GET"
                                                                    body:nil
                                                                  header:nil];
            
            dispatch_queue_t queue = dispatch_queue_create("com.soutaro.test", NULL);
            
            dispatch_async(queue, ^{
                [request run];
            });
            
            [NSThread sleepForTimeInterval:0.1];
            
            expect(request.status).to.equal(SMHTTPRequestStatusRequestSent);
            
            [request abort:nil];

            expect(request.status).to.equal(SMHTTPRequestStatusAborted);
        });
    });
});

SpecEnd