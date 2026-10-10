import Foundation
import Vapor
import NIOCore
import NIOHTTP2
import NIOSSL
import Crypto

let digest = SHA256.hash(data: Data("dependency check".utf8))
precondition(Array(digest).count == 32)
var buffer = ByteBufferAllocator().buffer(capacity: 32)
buffer.writeString("dependency check")
precondition(buffer.getString(at: 0, length: buffer.readableBytes) == "dependency check")
let context = try NIOSSLContext(configuration: TLSConfiguration.makeClientConfiguration())
print("Swift dependency graph compiled and initialized successfully")
