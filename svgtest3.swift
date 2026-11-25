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
typealias ReleaseFn = @convention(c) (Doc) -> Void

let create = sym(fw, "CGSVGDocumentCreateFromData", CreateFn.self)
let canvasSize = sym(fw, "CGSVGDocumentGetCanvasSize", SizeFn.self)
let release = sym(fw, "CGSVGDocumentRelease", ReleaseFn.self)

print("LOAD bytes=\(data.count)")

guard let doc = create(data as CFData, nil) else {
    print("DOC_CREATE_FAILED")
    exit(3)
}
let size = canvasSize(doc)
print("CANVAS \(Int(size.width))x\(Int(size.height))")

// Replicates SDWebImageSVGCoder's private UIImage initializer:
//   _imageWithCGSVGDocument:
let sel = NSSelectorFromString("_imageWithCGSVGDocument:")
guard let method = class_getClassMethod(UIImage.self, sel) else {
    print("NO_PRIVATE_SELECTOR")
    exit(4)
}
typealias ImageWithDocFn = @convention(c) (AnyObject, Selector, Doc) -> Unmanaged<AnyObject>?
let imp = method_getImplementation(method)
let imageWithDoc = unsafeBitCast(imp, to: ImageWithDocFn.self)
guard let imgAny = imageWithDoc(UIImage.self as AnyObject, sel, doc)?.takeUnretainedValue() as? UIImage else {
    print("VECTOR_IMAGE_FAILED")
    exit(5)
}
let vector = imgAny
print("VECTOR_IMAGE size=\(vector.size.width)x\(vector.size.height) scale=\(vector.scale)")

// Replicates SDImageSVGCoder createVectorSVGWithData: 1x1 snapshot, then real draws.
func snapshot(_ w: CGFloat, _ h: CGFloat, _ scale: CGFloat, label: String) {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = scale
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
    let out = renderer.image { _ in
        vector.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    print("DRAW \(label) ok=\(out.size.width)x\(out.size.height)")
}

let sem = DispatchSemaphore(value: 0)
DispatchQueue.global(qos: .default).async {
    autoreleasepool {
        snapshot(1, 1, 1, label: "1x1@1")
        snapshot(32, 32, 3, label: "32@3")
        snapshot(512, 512, 1, label: "512@1")
        snapshot(365, 451, 2, label: "canvas@2")
        for _ in 0..<5 {
            snapshot(1, 1, 1, label: "1x1@1")
            snapshot(32, 32, 3, label: "32@3")
        }
        release(doc)
        print("ALL_OK")
        sem.signal()
    }
}
sem.wait()
