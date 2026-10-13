// ql-shot: Quick Look's picture of a file, as Finder draws it (a document's first page, a presentation's first slide,
// a spreadsheet's first sheet, a 3D model), on white, up to 1600 px on its long side. The hub uses it for the files it
// has no renderer of its own for (Word, Excel, PowerPoint, Pages, Keynote, Numbers, RTF, EPUB, USDZ…).
//   ql-shot <file> <out.png> [size 1600]
// Prints "<w>x<h>". Exits 1 when Quick Look has no picture of the file (only its icon), at once; 2 after 20 s.
// (Not qlmanage -t: it waits forever on a file it has no picture of, and draws RTF in dark mode, black on dark grey.)
import AppKit
import QuickLookThumbnailing

let args = CommandLine.arguments
func fail(_ why: String, _ code: Int32 = 1) -> Never { FileHandle.standardError.write("ql-shot: \(why)\n".data(using: .utf8)!); exit(code) }
guard args.count >= 3 else { fail("usage: ql-shot <file> <out.png> [size]") }
let file = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let side = args.count > 3 ? Double(args[3]) ?? 1600 : 1600

let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: side, height: side), scale: 1, representationTypes: .thumbnail)
QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
    guard let picture = rep?.cgImage else { fail("Quick Look has no picture of \(file.lastPathComponent)") }
    // on white: a page or a model drawn on a clear background would turn black as a JPEG
    let w = picture.width, h = picture.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fail("no memory for a \(w)x\(h) picture") }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(picture, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let flat = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)
    else { fail("can't write \(out.path)") }
    CGImageDestinationAddImage(dest, flat, nil)
    guard CGImageDestinationFinalize(dest) else { fail("can't write \(out.path)") }
    print("\(w)x\(h)")
    exit(0)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fail("timed out", 2) }
RunLoop.main.run()
