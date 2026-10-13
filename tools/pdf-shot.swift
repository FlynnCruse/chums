// pdf-shot: a PDF's pages as one picture, top to bottom, with a thin black gap between them. The hub uses it to show
// PDFs on the watch, which has no PDF viewer of its own. PDFKit draws each page as Preview does, with its rotation,
// annotations and form fields.
//   pdf-shot <in.pdf> <out.png>
// Pages are drawn 1200 px wide; when they don't all fit in 10 M pixels at that width, narrower (down to 900 px) so
// more of them do; past that, the pages that don't fit are left out. Prints "<w>x<h> <pages shown> <pages>". Exits 1
// on a failure (a file that isn't a PDF, one locked with a password).
import AppKit
import PDFKit

let args = CommandLine.arguments
func fail(_ why: String) -> Never { FileHandle.standardError.write("pdf-shot: \(why)\n".data(using: .utf8)!); exit(1) }
guard args.count >= 3 else { fail("usage: pdf-shot <in.pdf> <out.png>") }
guard let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else { fail("not a PDF that can be opened") }
if doc.isLocked && !doc.unlock(withPassword: "") { fail("the PDF is locked with a password") }
let count = doc.pageCount
guard count > 0 else { fail("the PDF has no pages") }

let maxWidth = 1200.0, minWidth = 900.0, maxPixels = 10_000_000.0, gap = 16.0
// each page as it's shown (its rotation applied), in points
let sizes: [CGSize] = (0..<count).map { i in
    let page = doc.page(at: i)!, b = page.bounds(for: .cropBox)
    return page.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
}
let ratios = sizes.map { Double($0.height / max($0.width, 1)) }
// the widest width from 900 to 1200 px at which every page fits: W × (W × Σ ratios + gap × (pages − 1)) ≤ maxPixels
let a = ratios.reduce(0, +), b = gap * Double(count - 1)
let W = min(maxWidth, max(minWidth, ((-b + (b * b + 4 * a * maxPixels).squareRoot()) / (2 * a)).rounded(.down)))
// the pages that fit at that width (at least the first, cut at the bottom if it alone is too tall)
var heights: [Int] = [], total = 0
for r in ratios {
    let h = max(1, Int((W * r).rounded())), next = total + (heights.isEmpty ? 0 : Int(gap)) + h
    if !heights.isEmpty && Double(next) * W > maxPixels { break }
    heights.append(h); total = next
}
let width = Int(W), height = min(total, Int(maxPixels / W))

guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fail("no memory for a \(width)x\(height) picture") }
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
ctx.interpolationQuality = .high
var top = 0
for (i, h) in heights.enumerated() {
    let page = doc.page(at: i)!
    let y = height - top - h                                     // Core Graphics counts from the bottom
    let slot = CGRect(x: 0, y: y, width: width, height: h)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(slot)
    ctx.saveGState()
    ctx.clip(to: slot)
    ctx.translateBy(x: 0, y: CGFloat(y))
    ctx.scaleBy(x: CGFloat(W) / sizes[i].width, y: CGFloat(h) / sizes[i].height)
    page.draw(with: .cropBox, to: ctx)                           // in the box's space, its rotation applied
    ctx.restoreGState()
    top += h + Int(gap)
}
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, "public.png" as CFString, 1, nil)
else { fail("can't write \(args[2])") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fail("can't write \(args[2])") }
print("\(width)x\(height) \(heights.count) \(count)")
