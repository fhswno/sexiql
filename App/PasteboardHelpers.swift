import AppKit

extension Notification.Name {
    static let sexiqlCopySelectedRows = Notification.Name("sexiqlCopySelectedRows")
}

func copyToPasteboard(_ string: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(string, forType: .string)
}
