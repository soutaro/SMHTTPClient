#import <Foundation/Foundation.h>
#include <sys/socket.h>

extern NSString * const SMHTTPClientErrorDomain;

typedef enum : NSUInteger {
    SMHTTPRequestStatusInit,
    SMHTTPRequestStatusConnecting,
    SMHTTPRequestStatusConnected,
    SMHTTPRequestStatusRequestSent,
    SMHTTPRequestStatusSuccess,
    SMHTTPRequestStatusError,
    SMHTTPRequestStatusAborted
} SMHTTPRequestStatus;

@interface SMHTTPRequest : NSObject

@property (nonatomic, readonly) SMHTTPRequestStatus status;

@property (nonatomic, readonly) struct sockaddr address;
@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSString *method;
@property (nonatomic, readonly) NSData *requestBody;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *requestHeader;

@property (nonatomic, readonly) NSUInteger responseStatusCode;
@property (nonatomic, readonly) NSData *responseBody;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *responseHeader;

@property (readonly) NSError *error;

- (instancetype)initWithHost:(struct sockaddr)address path:(NSString *)path method:(NSString *)method body:(NSData *)body header:(NSDictionary<NSString *, NSString *> *)header;

- (void)run;

- (void)abort:(NSError *)error;

+ (BOOL)resolveHostname:(NSString *)hostname port:(NSUInteger)port callback:(void (^)(struct sockaddr[]))callback;

@end
