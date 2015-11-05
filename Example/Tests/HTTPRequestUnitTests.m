//
//  SMHTTPClientTests.m
//  SMHTTPClientTests
//
//  Created by Soutaro Matsumoto on 11/03/2015.
//  Copyright (c) 2015 Soutaro Matsumoto. All rights reserved.
//

// https://github.com/Specta/Specta

#import <Specta/Specta.h>

#import "SMHTTPRequest.h"

@interface SMHTTPRequest ()

- (void)setStatus:(SMHTTPRequestStatus)status;

- (void)receive;

- (NSData *)requestData;

@property (nonatomic) NSMutableData *readBuffer;
@property (nonatomic) NSUInteger readOffset;;

@end

SpecBegin(SMHTTPRequestUnitSpecs)

describe(@"receive", ^{
    NSString *responseString = [@[@"HTTP/1.1 200 OK",
                               @"Content-Type: application/json",
                               @"Content-Length: 10",
                               @"",
                               @"1234567890",
                               @"    padding    "
                               ] componentsJoinedByString:@"\r\n"];

    NSString *chunkedResponseString = [@[@"HTTP/1.1 200 OK",
                                         @"Content-Type: application/json",
                                         @"Content-Encoding: chunked",
                                         @"",
                                         @"A;ext",
                                         @"1234567890",
                                         @"3",
                                         @"abc",
                                         @"0",
                                         @""
                                  ] componentsJoinedByString:@"\r\n"];

    it(@"sets status line", ^{
        SMHTTPRequest *request = [[SMHTTPRequest alloc] init];
        request.status = SMHTTPRequestStatusRequestSent;
        request.readBuffer = [responseString dataUsingEncoding:NSUTF8StringEncoding].mutableCopy;
        
        [request receive];
        
        expect(request.responseStatusCode).to.equal(200);
    });
    
    it(@"sets response header", ^{
        SMHTTPRequest *request = [[SMHTTPRequest alloc] init];
        request.status = SMHTTPRequestStatusRequestSent;
        request.readBuffer = [responseString dataUsingEncoding:NSUTF8StringEncoding].mutableCopy;
        
        [request receive];
        
        expect(request.responseHeader[@"Content-Type"]).to.equal(@"application/json");
        expect(request.responseHeader[@"Content-Length"]).to.equal(@"10");
    });
    
    it(@"sets response body", ^{
        SMHTTPRequest *request = [[SMHTTPRequest alloc] init];
        request.status = SMHTTPRequestStatusRequestSent;
        request.readBuffer = [responseString dataUsingEncoding:NSUTF8StringEncoding].mutableCopy;
        
        [request receive];
        
        NSString *expectedBody = @"1234567890";
        NSString *responseBody = [[NSString alloc] initWithData:request.responseBody encoding:NSUTF8StringEncoding];
        expect(responseBody).to.equal(expectedBody);
    });
    
    it(@"sets chunked response body", ^{
        SMHTTPRequest *request = [[SMHTTPRequest alloc] init];
        request.status = SMHTTPRequestStatusRequestSent;
        request.readBuffer = [chunkedResponseString dataUsingEncoding:NSUTF8StringEncoding].mutableCopy;
        
        [request receive];
        
        NSString *expectedBody = @"1234567890abc";
        NSString *responseBody = [[NSString alloc] initWithData:request.responseBody encoding:NSUTF8StringEncoding];
        expect(responseBody).to.equal(expectedBody);
    });
});

    
describe(@"requestData", ^{
    it(@"returns HTTP/1.1 request", ^{
        NSString *expectedRequest = [@[@"POST / HTTP/1.1",
                                       @"Connection: Close",
                                       @"Content-Type: application/json",
                                       @"",
                                       @"[1,2,3]"
                                       ] componentsJoinedByString:@"\r\n"];
        
        struct sockaddr address;
        NSString *requestBody = @"[1,2,3]";
        SMHTTPRequest *request = [[SMHTTPRequest alloc] initWithHost:address
                                                                path:@"/"
                                                              method:@"POST"
                                                                body:[requestBody dataUsingEncoding:NSUTF8StringEncoding]
                                                              header:@{
                                                                       @"Content-Type": @"application/json",
                                                                       @"Connection": @"Close"
                                                                       }
                                  ];
        
        NSString *requestString = [[NSString alloc] initWithData:[request requestData] encoding:NSUTF8StringEncoding];
        
        expect(requestString).to.equal(expectedRequest);
    });
});

SpecEnd

