import Foundation
import Darwin

public enum FileTree {
    public enum EntryType: Sendable {
        case directory
        case mountPoint
        case file
        case symlink
        case other
    }

    public struct Entry: Sendable {
        public let name: String
        public let type: EntryType
        public let allocated: Int64
        public let links: UInt32
        public let modified: Date?
    }

    public static func list(_ directory: String, fileNames: Bool = true) -> [Entry]? {
        let descriptor = open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME)
        request.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
        request.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

        let capacity = 128 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        defer { buffer.deallocate() }

        var entries: [Entry] = []
        while true {
            let count = getattrlistbulk(descriptor, &request, buffer, capacity, 0)
            if count <= 0 { break }
            var record = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(record.loadUnaligned(as: UInt32.self))
                var field = record + 4
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size

                let nameField = field
                let nameReference = field.loadUnaligned(as: attrreference_t.self)
                field += MemoryLayout<attrreference_t>.size

                var objectType = fsobj_type_t(VNON.rawValue)
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    objectType = field.loadUnaligned(as: fsobj_type_t.self)
                    field += MemoryLayout<fsobj_type_t>.size
                }
                var modified: Date?
                if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                    modified = date(field.loadUnaligned(as: timespec.self))
                    field += MemoryLayout<timespec>.size
                }
                var mountPoint = false
                if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 {
                    mountPoint = field.loadUnaligned(as: UInt32.self) & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0
                    field += 4
                }
                var links: UInt32 = 1
                if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
                    links = field.loadUnaligned(as: UInt32.self)
                    field += 4
                }
                var allocated: Int64 = 0
                if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    allocated = field.loadUnaligned(as: off_t.self)
                    field += MemoryLayout<off_t>.size
                }

                let type: EntryType
                switch objectType {
                case fsobj_type_t(VDIR.rawValue): type = mountPoint ? .mountPoint : .directory
                case fsobj_type_t(VREG.rawValue): type = .file
                case fsobj_type_t(VLNK.rawValue): type = .symlink
                default: type = .other
                }

                let name: String
                if type == .directory || fileNames {
                    let namePointer = (nameField + Int(nameReference.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                    name = String(cString: namePointer)
                } else {
                    name = ""
                }
                entries.append(Entry(name: name, type: type, allocated: allocated, links: links, modified: modified))
                record += length
            }
        }
        return entries
    }

    public static func traverse<Work: Sendable>(
        _ roots: [Work],
        workers: Int = max(2, ProcessInfo.processInfo.activeProcessorCount),
        _ visit: @escaping @Sendable (Work) -> [Work]?
    ) {
        let queue = WorkQueue(roots)
        DispatchQueue.concurrentPerform(iterations: workers) { _ in
            while let work = queue.next() {
                if let children = visit(work) {
                    queue.finish(adding: children)
                } else {
                    queue.stop()
                }
            }
        }
    }

    public static func allocatedSize(of path: String) -> Int64 {
        allocatedSizes(of: [path])[0]
    }

    public static func allocatedSizes(of paths: [String]) -> [Int64] {
        let totals = Totals(count: paths.count)
        traverse(paths.indices.map { DirectoryWork(path: paths[$0], tag: $0, level: 0) }) { work in
            guard let entries = list(work.path, fileNames: false) else { return [] }
            var sum: Int64 = 0
            var children: [DirectoryWork] = []
            for entry in entries {
                switch entry.type {
                case .file:
                    if entry.links <= 1 { sum += entry.allocated }
                case .directory:
                    children.append(DirectoryWork(path: work.path + "/" + entry.name, tag: work.tag, level: work.level + 1))
                case .mountPoint, .symlink, .other:
                    break
                }
            }
            totals.add(sum, to: work.tag)
            return children
        }
        return totals.values
    }

    public static func isRealDirectory(_ path: String) -> Bool {
        var info = Darwin.stat()
        guard lstat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR
    }

    public static func modificationDate(_ path: String) -> Date? {
        var info = Darwin.stat()
        guard lstat(path, &info) == 0 else { return nil }
        return date(info.st_mtimespec)
    }

    static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}

public struct DirectoryWork: Sendable {
    public let path: String
    public let tag: Int
    public let level: Int

    public init(path: String, tag: Int = 0, level: Int = 0) {
        self.path = path
        self.tag = tag
        self.level = level
    }
}

final class WorkQueue<Work>: @unchecked Sendable {
    private let condition = NSCondition()
    private var pending: [Work]
    private var active = 0
    private var stopped = false

    init(_ roots: [Work]) {
        pending = roots
    }

    func next() -> Work? {
        condition.lock()
        defer { condition.unlock() }
        while pending.isEmpty && active > 0 && !stopped {
            condition.wait()
        }
        guard !stopped, let work = pending.popLast() else {
            condition.broadcast()
            return nil
        }
        active += 1
        return work
    }

    func finish(adding children: [Work]) {
        condition.lock()
        pending.append(contentsOf: children)
        active -= 1
        condition.broadcast()
        condition.unlock()
    }

    func stop() {
        condition.lock()
        stopped = true
        active -= 1
        condition.broadcast()
        condition.unlock()
    }
}

final class Totals: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int64]

    init(count: Int) {
        storage = [Int64](repeating: 0, count: count)
    }

    func add(_ value: Int64, to index: Int) {
        lock.lock()
        storage[index] += value
        lock.unlock()
    }

    var values: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
