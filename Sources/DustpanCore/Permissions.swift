import Foundation

public enum Permissions {
    /// True when Dustpan has Full Disk Access. The TCC database is readable only with FDA,
    /// and trying to open it never shows a prompt.
    public static var hasFullDiskAccess: Bool {
        let tcc = URL.home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = try? FileHandle(forReadingFrom: tcc) else { return false }
        try? handle.close()
        return true
    }

    /// Opens System Settings › Privacy & Security › Full Disk Access.
    public static let fullDiskAccessSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
