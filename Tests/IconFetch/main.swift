import Foundation
import CoreGraphics
import ImageIO

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

func png(width: Int, height: Int) -> Data {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return out as Data
}

func size(of data: Data) -> (Int, Int)? {
    guard let s = CGImageSourceCreateWithData(data as CFData, nil),
          let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { return nil }
    return (i.width, i.height)
}

// 058d: the result fits inside 64 x 64, wide or tall.
let wide = IconRules.fittedSize(width: 256, height: 64, maxSide: 64)
check("a wide icon fits inside 64 x 64", wide.width == 64 && wide.height == 16)
let tall = IconRules.fittedSize(width: 50, height: 200, maxSide: 64)
check("a tall icon fits inside 64 x 64", tall.width == 16 && tall.height == 64)
let big = IconRules.fittedSize(width: 400, height: 400, maxSide: 64)
check("a big square icon becomes 64 x 64", big.width == 64 && big.height == 64)
let small = IconRules.fittedSize(width: 32, height: 20, maxSide: 64)
check("a small icon is not scaled up", small.width == 32 && small.height == 20)
let sliver = IconRules.fittedSize(width: 1000, height: 3, maxSide: 64)
check("a thin icon keeps at least one pixel", sliver.width == 64 && sliver.height >= 1)

let wideOut = IconRules.resizedPNG(png(width: 300, height: 100), maxSide: 64).flatMap(size(of:))
check("resizing a wide image really gives 64 x 21", wideOut?.0 == 64 && wideOut?.1 == 21)
let sameOut = IconRules.resizedPNG(png(width: 64, height: 64), maxSide: 64).flatMap(size(of:))
check("a 64 x 64 image stays 64 x 64", sameOut?.0 == 64 && sameOut?.1 == 64)
check("data that is not an image gives nil", IconRules.resizedPNG(Data("nope".utf8), maxSide: 64) == nil)

// Off the main thread, many at once.
var allOK = true
let lock = NSLock()
let source = png(width: 500, height: 200)
DispatchQueue.concurrentPerform(iterations: 40) { _ in
    let s = IconRules.resizedPNG(source, maxSide: 64).flatMap(size(of:))
    if !(s?.0 == 64 && s?.1 == 26) { lock.lock(); allOK = false; lock.unlock() }
}
check("40 resizes in parallel all fit", allOK)

// e998: a failed avatar is remembered and not asked for again right away.
let t0 = Date(timeIntervalSince1970: 1_000_000)
check("never failed: try", IconRules.shouldRetry(failedAt: nil, now: t0))
check("failed an hour ago: leave it", !IconRules.shouldRetry(failedAt: t0, now: t0.addingTimeInterval(3600)))
check("failed over a day ago: try again", IconRules.shouldRetry(failedAt: t0, now: t0.addingTimeInterval(IconRules.retryAfter + 1)))

let suite = "reshelf-icon-test-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let log = IconFailureLog(defaults: defaults, key: "failures")
check("a fresh log tries", log.shouldTry(owner: "Octocat", now: t0))
log.recordFailure(owner: "Octocat", now: t0)
check("after a failure it is skipped", !log.shouldTry(owner: "Octocat", now: t0.addingTimeInterval(60)))
check("owner case does not matter", !log.shouldTry(owner: "octocat", now: t0.addingTimeInterval(60)))
check("other owners are not affected", log.shouldTry(owner: "someone-else", now: t0.addingTimeInterval(60)))
let relaunched = IconFailureLog(defaults: defaults, key: "failures")
check("the memory survives a relaunch", !relaunched.shouldTry(owner: "octocat", now: t0.addingTimeInterval(60)))
check("it expires after a day", relaunched.shouldTry(owner: "octocat", now: t0.addingTimeInterval(IconRules.retryAfter + 1)))
log.clear(owner: "Octocat")
check("a success clears it", log.shouldTry(owner: "octocat", now: t0.addingTimeInterval(60)))
defaults.removePersistentDomain(forName: suite)

if failures > 0 { print("\(failures) failed"); exit(1) }
print("IconFetch: all passed")
