import Foundation

internal class Buffer {
    private var data: NSMutableData
    private var offset: Int
    private let filler: (UnsafeMutablePointer<UInt8>, Int) throws -> Int
    
    init(filler: (UnsafeMutablePointer<UInt8>, Int) throws -> Int) {
        self.data = NSMutableData()
        self.offset = 0
        self.filler = filler
    }
    
    func fillBuffer(expectedSize: Int) throws {
        let buf = UnsafeMutablePointer<UInt8>.alloc(expectedSize)
        let actualSize = try self.filler(buf, expectedSize)
        self.data = NSMutableData(bytes: buf, length: actualSize)
        self.offset = 0
    }
    
    private func readCharacter() throws -> Character {
        if self.offset == self.data.length {
            try self.fillBuffer(4096)
        }
        
        var c = [UInt8](count: 1, repeatedValue: 0)
        self.data.getBytes(&c, range: NSMakeRange(self.offset, 1))
        self.offset += 1
        
        return Character(UnicodeScalar(c[0]))
    }
    
    func readLine() throws -> String {
        var line = ""
        var lastChar: Character = "\0"
        while true {
            let char = try self.readCharacter()
            if lastChar == "\r" && char == "\n" {
                return line
            }
            
            if char != "\r" && char != "\n" {
                line.append(char)
            }
            
            lastChar = char
        }
    }
    
    func readData(expectedSize: Int) throws -> NSData {
        let data = NSMutableData()
        
        var readSize = 0
        
        while readSize < expectedSize {
            if self.offset == self.data.length {
                try self.fillBuffer(4096)
            }
            
            var size = expectedSize - readSize
            if size > self.data.length - self.offset {
                size = self.data.length - self.offset
            }
            
            let buf = UnsafeMutablePointer<UInt8>.alloc(size)
            self.data.getBytes(buf, range: NSMakeRange(self.offset, size))
            
            data.appendBytes(buf, length: size)
            readSize += size
            self.offset += size
        }
        
        return data
    }
}