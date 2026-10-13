import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
// make a HEIC image sequence from PNG frames, then time decoding each frame
let args = CommandLine.arguments, dir = args[1], clip = args[2], out = args[3], q = Double(args[4])!
var urls: [URL] = []; var i = 0
while FileManager.default.fileExists(atPath: "\(dir)/\(clip)_\(String(format: "%03d", i)).png") { urls.append(URL(fileURLWithPath: "\(dir)/\(clip)_\(String(format: "%03d", i)).png")); i += 1 }
let type = (args.count > 5 ? args[5] : "public.heics") as CFString
guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, type, urls.count, nil) else { print("no dest for", type); exit(1) }
for u in urls {
    let src = CGImageSourceCreateWithURL(u as CFURL, nil)!, im = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    CGImageDestinationAddImage(dest, im, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
}
print("finalize", CGImageDestinationFinalize(dest))
let size = (try! FileManager.default.attributesOfItem(atPath: out)[.size] as! Int)
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: out) as CFURL, nil)!
let n = CGImageSourceGetCount(src), t0 = Date()
for k in 0..<n { let im = CGImageSourceCreateImageAtIndex(src, k, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)!; _ = im.width }
print("\(urls.count) frames -> \(size / 1024) KB (\(size / urls.count / 1024) KB/frame), \(n) decodable, \(String(format: "%.1f", Date().timeIntervalSince(t0) / Double(n) * 1000)) ms/frame on this Mac")
