import AppKit

func copyToPasteboard(_ string: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(string, forType: .string)
}
