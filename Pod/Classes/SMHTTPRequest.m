#include <netinet/in.h>
#include <netdb.h>

#import "SMHTTPRequest.h"

NSString * const SMHTTPClientErrorDomain = @"SMHTTPClientErrorDomain";
NSInteger const SMHTTPClientErrorCodeInvalidResponse = 1;

@interface SMHTTPRequest ()

@property (nonatomic) SMHTTPRequestStatus status;
@property (nonatomic) int sock;
@property (nonatomic) NSUInteger readOffset;
@property (nonatomic) NSMutableData *readBuffer;

@end

@implementation SMHTTPRequest

- (instancetype)init
{
    self = [super init];
    
    self.status = SMHTTPRequestStatusInit;
    
    return self;
}

- (void)dealloc
{
    [self close];
}

- (instancetype)initWithHost:(struct sockaddr)address path:(NSString *)path method:(NSString *)method body:(NSData *)body header:(NSDictionary<NSString *,NSString *> *)header
{
    self = [self init];
    
    _address = address;
    _path = path;
    _method = method;
    _requestBody = body;
    _requestHeader = header;
    
    return self;
}

- (void)run
{
    [self connect:^{
        if ([self shouldExitFromRun]) return;
        [self send];
        if ([self shouldExitFromRun]) return;
        [self receive];
        if ([self shouldExitFromRun]) return;
    }];
}

- (void)abort:(NSError *)error
{
    _error = error;
    self.status = SMHTTPRequestStatusAborted;
    
    if (self.sock) {
        shutdown(self.sock, SHUT_RDWR);
    }
}

+ (BOOL)resolveHostname:(NSString *)hostname port:(NSUInteger)port callback:(void (^)(struct sockaddr *))callback
{
    struct addrinfo hints = {0};
    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_ADDRCONFIG;
    
    struct addrinfo *address;
    
    int error = getaddrinfo(hostname.UTF8String, [NSString stringWithFormat:@"%ld", port].UTF8String, &hints, &address);
    
    if (error) {
        NSString *erroriinfo = [NSString stringWithCString:gai_strerror(error) encoding:NSUTF8StringEncoding];
        NSLog(@"%s %d %@", __func__, error, erroriinfo);
        return NO;
    }
    
    struct addrinfo *cursor = address;
    
    while (cursor) {
        callback(cursor->ai_addr);
        cursor = cursor->ai_next;
    }
    
    freeaddrinfo(address);
    
    return YES;
}

#pragma mark -

- (BOOL)shouldExitFromRun
{
    return self.status == SMHTTPRequestStatusError || self.status == SMHTTPRequestStatusAborted;
}

- (void)errorWithPosixErrono
{
    if (self.status != SMHTTPRequestStatusAborted) {
        self.status = SMHTTPRequestStatusError;
        _error = [[NSError alloc] initWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    }
}

- (void)errorWithCode:(NSInteger)code
{
    if (self.status != SMHTTPRequestStatusAborted) {
        self.status = SMHTTPRequestStatusError;
        _error = [[NSError alloc] initWithDomain:SMHTTPClientErrorDomain code:code userInfo:nil];
    }
}

- (BOOL)checkStatus:(SMHTTPRequestStatus)expectedStatus
{
    if (self.status != expectedStatus) {
        NSLog(@"%s unexpected status: %@ (expected %@)", __func__, @(self.status), @(expectedStatus));
        return false;
    } else {
        return true;
    }
}

- (void)connect:(void(^)())k
{
    if (![self checkStatus:SMHTTPRequestStatusInit]) return;
    
    self.status = SMHTTPRequestStatusConnecting;

    struct sockaddr address = self.address;
    self.sock = socket(address.sa_family, SOCK_STREAM, 0);
    
    if (connect(self.sock, &address, address.sa_len)) {
        if (self.status == SMHTTPRequestStatusConnecting) {
            [self errorWithPosixErrono];
        }
        return;
    }
    
    if (self.status == SMHTTPRequestStatusConnecting) {
        self.status = SMHTTPRequestStatusConnected;
        k();
    }
    
    [self close];
}

- (void)send
{
    if (![self checkStatus:SMHTTPRequestStatusConnected]) return;
    
    NSUInteger bufsize = 4096;
    NSUInteger offset = 0;
    
    NSData *data = [self requestData];
    
    while (true) {
        if (offset == data.length) {
            break;
        }
        if (self.status == SMHTTPRequestStatusAborted) {
            return;
        }
        
        NSUInteger size = bufsize;
        if (offset + bufsize >= data.length) {
            size = data.length - offset;
        }
        
        NSInteger sizeSent = send(self.sock, data.bytes + offset, size, 0);
        
        if (sizeSent >= 0) {
            offset += sizeSent;
        } else {
            if (self.status == SMHTTPRequestStatusConnected) {
                [self errorWithPosixErrono];
            }
            return;
        }
    }
    
    if (self.status == SMHTTPRequestStatusConnected) {
        self.status = SMHTTPRequestStatusRequestSent;
    }
}

- (NSData *)requestData
{
    NSMutableString *header = [[NSMutableString alloc] init];
    
    [header appendString:[NSString stringWithFormat:@"%@ %@ HTTP/1.1\r\n", self.method, self.path]];
    for (NSString *name in self.requestHeader) {
        NSString *value = self.requestHeader[name];
        [header appendString:[NSString stringWithFormat:@"%@: %@\r\n", name, value]];
    }
    [header appendString:@"\r\n"];
    
    NSMutableData *data = [[header dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [data appendData:self.requestBody];
    
    return data;
}

- (void)receive
{
    if (![self checkStatus:SMHTTPRequestStatusRequestSent]) return;
    
    NSMutableDictionary<NSString *, NSString *> *header = [[NSMutableDictionary alloc] init];
    NSMutableData *body = [[NSMutableData alloc] init];
    
    NSUInteger statusCode;
    
    [self readStatusLine:&statusCode];
    if (![self checkStatus:SMHTTPRequestStatusRequestSent]) return;
    
    [self readHeaderLines:header];
    if (![self checkStatus:SMHTTPRequestStatusRequestSent]) return;
    
    if ([[self headerValue:header forKey:@"Content-Encoding"] isEqualToString:@"chunked"]) {
        [self readChunkedBody:body];
    } else {
        NSString *length = [self headerValue:header forKey:@"Content-Length"];
        [self readBody:body length:length.integerValue];
    }
    
    
    if (self.status == SMHTTPRequestStatusRequestSent) {
        _responseStatusCode = statusCode;
        _responseHeader = header;
        _responseBody = body;
        self.status = SMHTTPRequestStatusSuccess;
    }
}

- (BOOL)nextByte:(unsigned char *)dest
{
    if (!self.readBuffer) {
        // Fill buffer
        unsigned char buf[4096];
        long recv_size = recv(self.sock, buf, sizeof(buf), 0);
        if (recv_size <= 0) {
            // Maybe an error or aborted
            return NO;
        }
        
        self.readBuffer = [[NSMutableData alloc] initWithBytes:buf length:recv_size];
        self.readOffset = 0;
    }
    
    NSRange range = NSMakeRange(self.readOffset, 1);
    [self.readBuffer getBytes:dest range:range];
    self.readOffset += 1;
    
    if (self.readOffset == self.readBuffer.length) {
        self.readOffset = 0;
        self.readBuffer = nil;
    }
    
    return YES;
}

- (void)readStatusLine:(NSUInteger *)statusCode
{
    unsigned char c = '\0';
    
    char *httpHeader = "HTTP/1.1";
    
    for (int i = 0; i < strlen(httpHeader); i++) {
        if ([self nextByte:&c]) {
            if(c == httpHeader[i]) {
                // ok
            } else {
                // error
                [self errorWithCode:SMHTTPClientErrorCodeInvalidResponse];
                return;
            }
        } else {
            // aborted?
            return;
        }
    }
    
    [self nextByte:&c];
    
    unsigned char statusCodeBuffer[4] = { '\0' };
    for (int i = 0; i < 3; i++) {
        if ([self nextByte:&statusCodeBuffer[i]]) {
            // ok
        } else {
            [self errorWithCode:SMHTTPClientErrorCodeInvalidResponse];
            return;
        }
    }
    
    *statusCode = atoi((char*)statusCodeBuffer);
    
    unsigned char lastByte = '\0';
    while (true) {
        if (![self nextByte:&c]) {
            [self errorWithCode:SMHTTPClientErrorCodeInvalidResponse];
            return;
        }
        
        if (lastByte == '\r' && c == '\n') {
            return;
        }
        
        lastByte = c;
    }
}

- (void)readHeaderLines:(NSMutableDictionary<NSString *, NSString *> *)header
{
    int state = 0;
    unsigned char lastByte = '\0';
    
    NSMutableData *nameData;
    NSMutableData *valueData;
    NSCharacterSet *space = [NSCharacterSet characterSetWithCharactersInString:@" "];

    while (state != -1) {
        unsigned char byte;
        
        if (![self nextByte:&byte]) {
            [self errorWithCode:SMHTTPClientErrorCodeInvalidResponse];
            return;
        }
        
        switch (state) {
            case 0:
                // Starting Line
                if (lastByte == '\r' && byte == '\n') {
                    state = -1;
                } else if (byte != '\r') {
                    nameData = [[NSMutableData alloc] init];
                    valueData = [[NSMutableData alloc] init];
                    
                    [nameData appendBytes:&byte length:1];
                    
                    state = 1;
                }
                
                break;
            case 1:
                // Reading Name
                if (byte == ':') {
                    state = 2;
                } else {
                    [nameData appendBytes:&byte length:1];
                }
                break;
            case 2:
                // Reading Value
                if (lastByte == '\r' && byte == '\n') {
                    state = 0;
                    [valueData setLength:valueData.length - 1];
                    
                    NSString *nameString = [[NSString alloc] initWithData:nameData encoding:NSUTF8StringEncoding];
                    NSString *valueString = [[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding];
                    
                    header[nameString] = [valueString stringByTrimmingCharactersInSet:space];
                    
                    nameData = nil;
                    valueData = nil;
                } else {
                    [valueData appendBytes:&byte length:1];
                }
                break;
        }
        
        lastByte = byte;
    }
}

- (void)readBody:(NSMutableData *)body length:(NSUInteger)length
{
    for (NSUInteger i = 0; i < length; i++) {
        unsigned char c;
        if (![self nextByte:&c]) {
            [self errorWithCode:SMHTTPClientErrorCodeInvalidResponse];
            return;
        }
        
        [body appendBytes:&c length:1];
    }
}

- (void)readChunkedBody:(NSMutableData *)body
{
    int state = 0;
    unsigned char lastByte = '\0';
    
    NSMutableString *chunkSizeString = [[NSMutableString alloc] init];
    unsigned int chunkSize = 0;
    NSUInteger chunkOffset = 0;
    
    while (state != -1) {
        unsigned char byte;
        if (![self nextByte:&byte]) {
            [self errorWithCode:SMHTTPClientErrorCodeInvalidResponse];
            return;
        }
        
        switch (state) {
            case 0:
                // Reading chunk size
                if (byte == '\r' || byte == ';') {
                    NSScanner *scanner = [NSScanner scannerWithString:chunkSizeString];
                    [scanner scanHexInt:&chunkSize];
                    chunkSizeString = [[NSMutableString alloc] init];
                    state = 1;
                } else {
                    NSString *c = [[NSString alloc] initWithBytes:&byte length:1 encoding:NSUTF8StringEncoding];
                    [chunkSizeString appendString:c];
                }
                
                break;
            case 1:
                // Skipping rest of chunk line
                if (lastByte == '\r' && byte == '\n') {
                    if (chunkSize == 0) {
                        state = -1;
                    } else {
                        chunkOffset = 0;
                        state = 2;
                    }
                }
                break;
            case 2:
                // Reading chunk body
                [body appendBytes:&byte length:1];
                chunkOffset += 1;
                if (chunkOffset == chunkSize) {
                    state = 3;
                }
                break;
            case 3:
                // Skipping rest of chunk delimitting CR
                state = 4;
                break;
            case 4:
                // Skipping rest of chunk delimitting LF
                state = 0;
                break;
            default:
                break;
        }
        
        
        lastByte = byte;
    }
}

- (NSString *)headerValue:(NSDictionary *)header forKey:(NSString *)key
{
    for (NSString *name in header) {
        if ([name.uppercaseString isEqualToString:key.uppercaseString]) {
            return header[name];
        }
    }
    
    return nil;
}

- (void)close
{
    if (self.sock == 0) return;
    
    shutdown(self.sock, SHUT_RDWR);
    close(self.sock);
    self.sock = 0;
}

@end
