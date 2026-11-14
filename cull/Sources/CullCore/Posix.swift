import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum FileKind: Sendable { case file, directory, symlink, other }

struct FileStat: Sendable {
    let kind: FileKind
    let device: UInt64
    let inode: UInt64
    let linkCount: UInt64
    let size: Int64
    /// Bytes actually allocated on disk (what deleting it can give back).
    let allocated: Int64
    let modified: Date
    /// Birth time. Only known on Darwin.
    let created: Date?
    let ownerID: UInt32
    /// Permission bits (the low twelve bits of the mode).
    let permissions: UInt32
}

struct FileIdentity: Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
}

/// The few POSIX calls the engine needs. Nothing in here ever follows a symlink.
enum Posix {
    private static let typeMask: UInt32 = 0o170000
    private static let typeDirectory: UInt32 = 0o040000
    private static let typeRegular: UInt32 = 0o100000
    private static let typeSymlink: UInt32 = 0o120000

    private static func date(_ spec: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(spec.tv_sec) + TimeInterval(spec.tv_nsec) / 1_000_000_000)
    }

    private static func convert(_ st: stat) -> FileStat {
        let kind: FileKind
        switch UInt32(st.st_mode) & typeMask {
        case typeDirectory: kind = .directory
        case typeRegular: kind = .file
        case typeSymlink: kind = .symlink
        default: kind = .other
        }
        #if canImport(Darwin)
        let modified = date(st.st_mtimespec)
        let created: Date? = date(st.st_birthtimespec)
        #else
        let modified = date(st.st_mtim)
        let created: Date? = nil
        #endif
        return FileStat(
            kind: kind,
            device: UInt64(truncatingIfNeeded: st.st_dev),
            inode: UInt64(truncatingIfNeeded: st.st_ino),
            linkCount: UInt64(truncatingIfNeeded: st.st_nlink),
            size: Int64(st.st_size),
            allocated: Int64(st.st_blocks) * 512,
            modified: modified,
            created: created,
            ownerID: UInt32(st.st_uid),
            permissions: UInt32(st.st_mode) & 0o7777
        )
    }

    /// `lstat`: describes the path itself, never what a symlink points at.
    static func info(at path: String) -> FileStat? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return convert(st)
    }

    static func info(named name: UnsafePointer<CChar>, in directoryFD: Int32) -> FileStat? {
        var st = stat()
        guard fstatat(directoryFD, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { return nil }
        return convert(st)
    }

    /// Calls `body` for every entry of `path` except "." and "..".
    /// Returns false when the directory cannot be opened.
    @discardableResult
    static func forEachEntry(
        in path: String,
        _ body: (_ name: UnsafePointer<CChar>, _ directoryFD: Int32) -> Void
    ) -> Bool {
        guard let dir = opendir(path) else { return false }
        defer { closedir(dir) }
        let fd = dirfd(dir)
        while let entry = readdir(dir) {
            let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
            withUnsafePointer(to: &entry.pointee.d_name) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: capacity) { name in
                    let dot = CChar(46)
                    if name[0] == dot, name[1] == 0 { return }
                    if name[0] == dot, name[1] == dot, name[2] == 0 { return }
                    body(name, fd)
                }
            }
        }
        return true
    }

    /// Entry names of a directory, sorted. `nil` when it cannot be read.
    static func entries(of path: String) -> [String]? {
        var names: [String] = []
        let opened = forEachEntry(in: path) { name, _ in
            names.append(String(cString: name))
        }
        return opened ? names.sorted() : nil
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func join(_ parent: String, _ name: String) -> String {
        parent.hasSuffix("/") ? parent + name : parent + "/" + name
    }

    static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        if slash == path.startIndex { return "/" }
        return String(path[..<slash])
    }

    static func lastComponent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// Gives the owner write and search permission on every directory in a tree,
    /// so read-only trees (Go module caches and the like) can be removed.
    static func makeTreeWritable(_ path: String) {
        guard let root = info(at: path), root.kind == .directory else { return }
        var stack = [path]
        while let dir = stack.popLast() {
            // Add what the owner needs to delete inside it; leave every other bit as it was.
            if let current = info(at: dir), current.permissions & 0o700 != 0o700 {
                _ = chmod(dir, mode_t(current.permissions | 0o700))
            }
            var subdirectories: [String] = []
            forEachEntry(in: dir) { name, fd in
                guard let st = info(named: name, in: fd), st.kind == .directory, st.device == root.device else { return }
                subdirectories.append(join(dir, String(cString: name)))
            }
            stack.append(contentsOf: subdirectories)
        }
    }

    /// True when another volume is mounted at `path` or anywhere inside it. Removing such a
    /// tree would reach into that volume, which is never what was asked for.
    static func crossesVolume(_ path: String) -> Bool {
        guard let root = info(at: path), root.kind == .directory else { return false }
        if let parent = info(at: parent(of: path)), parent.device != root.device { return true }
        var stack = [path]
        while let dir = stack.popLast() {
            var found = false
            var subdirectories: [String] = []
            forEachEntry(in: dir) { name, fd in
                guard !found, let st = info(named: name, in: fd), st.kind == .directory else { return }
                if st.device != root.device {
                    found = true
                } else {
                    subdirectories.append(join(dir, String(cString: name)))
                }
            }
            if found { return true }
            stack.append(contentsOf: subdirectories)
        }
        return false
    }

    static var isRoot: Bool { geteuid() == 0 }

    static var effectiveUserID: UInt32 { UInt32(geteuid()) }
}

/// What a tree weighs on disk.
public struct Measurement: Sendable, Equatable {
    public var bytes: Int64 = 0
    public var entries: Int = 0
    /// Most recent modification time of anything in the tree.
    public var newest: Date?
    /// Some directory could not be read, or the walk was cancelled; `bytes` is a lower bound.
    public var incomplete: Bool = false
    /// Another volume is mounted somewhere inside. Cull never offers such a tree.
    public var crossesVolume: Bool = false

    public init() {}

    mutating func merge(_ other: Measurement) {
        bytes += other.bytes
        entries += other.entries
        if let theirs = other.newest, newest.map({ theirs > $0 }) ?? true { newest = theirs }
        incomplete = incomplete || other.incomplete
        crossesVolume = crossesVolume || other.crossesVolume
    }
}

enum DirectorySizer {
    /// Walks `path` without following symlinks or crossing onto other volumes.
    /// Hard-linked files are counted once.
    static func measure(_ path: String, isCancelled: () -> Bool = { false }) -> Measurement {
        var result = Measurement()
        guard let root = Posix.info(at: path) else { return result }
        var seenLinks = Set<FileIdentity>()

        func account(_ st: FileStat) {
            result.entries += 1
            if st.kind != .symlink, result.newest.map({ st.modified > $0 }) ?? true {
                result.newest = st.modified
            }
            // Folders themselves weigh nothing on APFS and a block or two elsewhere. Leaving
            // them out keeps "empty" meaning zero everywhere.
            guard st.kind != .directory else { return }
            if st.linkCount > 1 {
                let identity = FileIdentity(device: st.device, inode: st.inode)
                guard seenLinks.insert(identity).inserted else { return }
            }
            result.bytes += st.allocated
        }

        account(root)
        guard root.kind == .directory else { return result }
        // A folder that is itself another volume's mount point counts as crossing, too.
        if let parent = Posix.info(at: Posix.parent(of: path)), parent.device != root.device {
            result.crossesVolume = true
        }

        var stack = [path]
        while let dir = stack.popLast() {
            if isCancelled() {
                result.incomplete = true
                break
            }
            var subdirectories: [String] = []
            let opened = Posix.forEachEntry(in: dir) { name, fd in
                guard let st = Posix.info(named: name, in: fd) else { return }
                account(st)
                guard st.kind == .directory else { return }
                if st.device == root.device {
                    subdirectories.append(Posix.join(dir, String(cString: name)))
                } else {
                    result.crossesVolume = true
                }
            }
            if !opened { result.incomplete = true }
            stack.append(contentsOf: subdirectories)
        }
        return result
    }
}
