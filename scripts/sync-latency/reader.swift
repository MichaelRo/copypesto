// SPDX-License-Identifier: MIT
// Mac B: watches the folder with FSEvents and with a 5 second poll, and logs when each file was first seen by each
// method, whether it was a dataless placeholder (iCloud "Optimize Mac Storage"), and how long reading its first bytes
// took (pread on a dataless file waits for the download). One JSON line per sighting and one per probe.
//
//   swiftc -swift-version 5 -O scripts/sync-latency/reader.swift -o /tmp/sync-latency-reader
//   /tmp/sync-latency-reader --folder <the iCloud Drive folder> --offset $(scripts/sync-latency/clock-offset.sh) \
//       --log reader.log --duration 3900 [--hydrate download]
//
// --hydrate download asks for the download with startDownloadingUbiquitousItem first (the app's plan for a dataless
// file); the default reads at once with pread.
import CoreServices
import Foundation

struct Options {
    var folder = ""
    var log = "reader.log"
    var offset = 0.0
    var duration = 3900.0
    var poll = 5.0
    var hydrateByDownload = false
}

func parse() -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while let flag = args.first {
        args.removeFirst()
        switch flag {
        case "--folder": options.folder = args.removeFirst()
        case "--log": options.log = args.removeFirst()
        case "--offset": options.offset = Double(args.removeFirst()) ?? 0
        case "--duration": options.duration = Double(args.removeFirst()) ?? 3900
        case "--poll": options.poll = Double(args.removeFirst()) ?? 5
        case "--hydrate": options.hydrateByDownload = args.removeFirst() == "download"
        default:
            FileHandle.standardError.write(Data("unknown option \(flag)\n".utf8))
            exit(2)
        }
    }
    guard !options.folder.isEmpty else {
        FileHandle.standardError.write(Data("--folder is required\n".utf8))
        exit(2)
    }
    return options
}

let options = parse()
let queue = DispatchQueue(label: "latency")
var seen: Set<String> = []
let logHandle: FileHandle = {
    FileManager.default.createFile(atPath: options.log, contents: nil)
    return FileHandle(forWritingAtPath: options.log)!
}()

func now() -> Double { Date().timeIntervalSince1970 + options.offset }

func write(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    logHandle.write(data + Data("\n".utf8))
}

func isDataless(_ path: String) -> Bool {
    var info = stat()
    guard stat(path, &info) == 0 else { return false }
    return info.st_flags & UInt32(SF_DATALESS) != 0
}

func probe(_ path: String, name: String) {
    let dataless = isDataless(path)
    let started = now()
    if dataless, options.hydrateByDownload {
        try? FileManager.default.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path))
        while isDataless(path), now() - started < 120 { usleep(100_000) }
    }
    let fd = open(path, O_RDONLY)
    var header = [UInt8](repeating: 0, count: 24)
    var count = -1
    if fd >= 0 {
        count = pread(fd, &header, header.count, 0)
        close(fd)
    }
    let done = now()
    write(["file": name, "event": "probe", "dataless": dataless, "bytesRead": count, "readMs": (done - started) * 1000,
           "at": done, "headerOk": count == 24 && header.starts(with: Array("PSTOLAT1".utf8))])
}

func sighting(_ name: String, via: String) {
    queue.async {
        guard name.hasSuffix(".lat") else { return }
        let path = options.folder + "/" + name
        write(["file": name, "event": "seen", "via": via, "at": now()])
        if seen.insert(name).inserted { probe(path, name: name) }
    }
}

let callback: FSEventStreamCallback = { _, _, count, paths, _, _ in
    let list = unsafeBitCast(paths, to: NSArray.self)
    for index in 0..<count {
        if let path = list[index] as? String { sighting((path as NSString).lastPathComponent, via: "fsevent") }
    }
}

try? FileManager.default.createDirectory(atPath: options.folder, withIntermediateDirectories: true)
var context = FSEventStreamContext()
let stream = FSEventStreamCreate(
    nil, callback, &context, [options.folder] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1,
    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
)!
FSEventStreamSetDispatchQueue(stream, queue)
FSEventStreamStart(stream)

let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now(), repeating: options.poll)
timer.setEventHandler {
    for name in (try? FileManager.default.contentsOfDirectory(atPath: options.folder)) ?? [] where name.hasSuffix(".lat") {
        write(["file": name, "event": "seen", "via": "poll", "at": now()])
        if seen.insert(name).inserted { probe(options.folder + "/" + name, name: name) }
    }
}
timer.resume()

DispatchQueue.main.asyncAfter(deadline: .now() + options.duration) {
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    try? logHandle.close()
    exit(0)
}
dispatchMain()
