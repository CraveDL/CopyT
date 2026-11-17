// 端到端测试用的剪贴板工具：模拟用户在各种应用中复制内容
// 用法: pbtool text <s> | textfile <path> | rtf <s> | html <html> <plain> | png <file> | files <path>... |
//       concealed <s> | blank | read
import AppKit

let pb = NSPasteboard.general
var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { FileHandle.standardError.write("missing command\n".data(using: .utf8)!); exit(2) }
let cmd = args.removeFirst()

switch cmd {
case "text":
    pb.clearContents()
    pb.setString(args[0], forType: .string)
case "textfile": // 大文本：命令行参数有长度上限，改从文件读取
    pb.clearContents()
    pb.setString(try! String(contentsOfFile: args[0], encoding: .utf8), forType: .string)
case "rtf":
    let attr = NSAttributedString(string: args[0], attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
    let rtf = try! attr.data(from: NSRange(location: 0, length: attr.length),
                             documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    pb.clearContents()
    pb.setData(rtf, forType: .rtf)
    pb.setString(args[0], forType: .string)
case "html":
    pb.clearContents()
    pb.setString(args[0], forType: .html)
    pb.setString(args[1], forType: .string)
case "png":
    let data = try! Data(contentsOf: URL(fileURLWithPath: args[0]))
    pb.clearContents()
    pb.setData(data, forType: .png)
case "makepng":
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: 40, height: 30).fill()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[0]))
case "files":
    pb.clearContents()
    pb.writeObjects(args.map { URL(fileURLWithPath: $0) as NSURL })
case "concealed":
    pb.clearContents()
    pb.setString(args[0], forType: .string)
    pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
case "blank":
    pb.clearContents()
    pb.setString("   \n  ", forType: .string)
case "read":
    print(pb.string(forType: .string) ?? "")
default:
    FileHandle.standardError.write("unknown command \(cmd)\n".data(using: .utf8)!)
    exit(2)
}
