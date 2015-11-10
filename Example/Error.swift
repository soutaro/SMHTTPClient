import Foundation

public let SMHTTPClientErrorDomain = "SMHTTPClientErrorDomain"
public enum SMHTTPClientErrorCode: Int {
    case MulformedHTTPResponse
    case NameResolutionFailure
}
