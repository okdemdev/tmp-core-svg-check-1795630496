import Foundation
import UIKit
import CoreGraphics
import Darwin

typealias Doc = OpaquePointer

func sym<T>(_ handle: UnsafeMutableRawPointer, _ name: String, _ type: T.Type) -> T {
    guard let p = dlsym(handle, name) else {
        FileHandle.standardError.write("missing symbol \(name)\n".data(using: .utf8)!)
        exit(2)
    }
    return unsafeBitCast(p, to: T.self)
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
    FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
    exit(2)
}

guard let fw = dlopen("/System/Library/PrivateFrameworks/CoreSVG.framework/CoreSVG", RTLD_NOW) else {
    FileHandle.standardError.write("cannot dlopen CoreSVG: \(String(cString: dlerror()))\n".data(using: .utf8)!)
    exit(2)
}

typealias CreateFn = @convention(c) (CFData, CFDictionary?) -> Doc?
typealias SizeFn = @convention(c) (Doc) -> CGSize
typealias DrawFn = @convention(c) (CGContext, Doc) -> Void
typealias ReleaseFn = @convention(c) (Doc) -> Void

let create = sym(fw, "CGSVGDocumentCreateFromData", CreateFn.self)
let canvasSize = sym(fw, "CGSVGDocumentGetCanvasSize", SizeFn.self)
let drawDoc = sym(fw, "CGContextDrawSVGDocument", DrawFn.self)
let release = sym(fw, "CGSVGDocumentRelease", ReleaseFn.self)

guard let doc = create(data as CFData, nil) else {
    print("DOC_CREATE_FAILED")
    exit(3)
}
let size = canvasSize(doc)
print("canvas=\(Int(size.width))x\(Int(size.height)) bytes=\(data.count)")

func rawRender(_ w: Int, _ h: Int) -> Bool {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return false
    }
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    drawDoc(ctx, doc)
    return true
}

/// Mirrors SDWebImageSVGCoder's `createVectorSVGWithData:` path: a UIGraphicsImageRenderer
/// test draw (1x1) followed by real sizes, executed on a background queue.
func uiRender(_ w: CGFloat, _ h: CGFloat, scale: CGFloat) {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = scale
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
    _ = renderer.image { ctx in
        drawDoc(ctx.cgContext, doc)
    }
}

let sem = DispatchSemaphore(value: 0)
DispatchQueue.global(qos: .default).async {
    autoreleasepool {
        print("raw1x1=\(rawRender(1, 1))")
        print("raw32=\(rawRender(32, 32))")
        for _ in 0..<10 {
            uiRender(1, 1, scale: 1)
            uiRender(32, 32, scale: 3)
            uiRender(512, 512, scale: 1)
        }
        release(doc)
        print("DONE")
        sem.signal()
    }
}
sem.wait()
