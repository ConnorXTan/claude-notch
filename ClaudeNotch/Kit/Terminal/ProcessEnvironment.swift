import Foundation
import Darwin

/// The environment another process of this user started with, read the way
/// `ps eww` does. Used to learn the cmux terminal of a session whose file
/// was written before the hook recorded it.
public enum ProcessEnvironment {
    /// The process's environment, or nil when it is gone or not readable.
    public static func variables(of pid: pid_t) -> [String: String]? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parse(Array(buffer.prefix(size)))
    }

    /// `KERN_PROCARGS2` is argc, the executable path, NUL padding, argc
    /// NUL-terminated arguments, then the environment as NUL-terminated
    /// `KEY=value` strings up to an empty one.
    static func parse(_ bytes: [UInt8]) -> [String: String]? {
        guard bytes.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var i = MemoryLayout<Int32>.size

        func skipString() {
            while i < bytes.count, bytes[i] != 0 { i += 1 }
        }

        skipString()
        while i < bytes.count, bytes[i] == 0 { i += 1 }
        for _ in 0..<max(0, Int(argc)) {
            skipString()
            i += 1
        }

        var environment: [String: String] = [:]
        while i < bytes.count, bytes[i] != 0 {
            let start = i
            skipString()
            let entry = String(decoding: bytes[start..<i], as: UTF8.self)
            if let eq = entry.firstIndex(of: "=") {
                environment[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
            }
            i += 1
        }
        return environment
    }
}
