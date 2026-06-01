import Foundation
import zlib

enum RunbookZipArchiveWriter {
    struct Entry {
        var path: String
        var data: Data
    }

    enum ZipError: LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case let .writeFailed(message):
                return message
            }
        }
    }

    static func write(entries: [Entry], to url: URL) throws {
        var archive = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let filenameData = Data(entry.path.utf8)
            let crc = crc32Checksum(entry.data)
            let size = UInt32(entry.data.count)

            var localHeader = Data()
            localHeader.appendUInt32(0x0403_4b50)
            localHeader.appendUInt16(20)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(dosTime())
            localHeader.appendUInt16(dosDate())
            localHeader.appendUInt32(crc)
            localHeader.appendUInt32(size)
            localHeader.appendUInt32(size)
            localHeader.appendUInt16(UInt16(filenameData.count))
            localHeader.appendUInt16(0)

            archive.append(localHeader)
            archive.append(filenameData)
            archive.append(entry.data)

            var centralEntry = Data()
            centralEntry.appendUInt32(0x0201_4b50)
            centralEntry.appendUInt16(20)
            centralEntry.appendUInt16(20)
            centralEntry.appendUInt16(0)
            centralEntry.appendUInt16(0)
            centralEntry.appendUInt16(dosTime())
            centralEntry.appendUInt16(dosDate())
            centralEntry.appendUInt32(crc)
            centralEntry.appendUInt32(size)
            centralEntry.appendUInt32(size)
            centralEntry.appendUInt16(UInt16(filenameData.count))
            centralEntry.appendUInt16(0)
            centralEntry.appendUInt16(0)
            centralEntry.appendUInt16(0)
            centralEntry.appendUInt16(0)
            centralEntry.appendUInt32(0)
            centralEntry.appendUInt32(offset)
            centralDirectory.append(centralEntry)
            centralDirectory.append(filenameData)

            offset += UInt32(localHeader.count + filenameData.count + entry.data.count)
        }

        archive.append(centralDirectory)

        var endRecord = Data()
        endRecord.appendUInt32(0x0605_4b50)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(UInt16(entries.count))
        endRecord.appendUInt16(UInt16(entries.count))
        endRecord.appendUInt32(UInt32(centralDirectory.count))
        endRecord.appendUInt32(offset)
        endRecord.appendUInt16(0)
        archive.append(endRecord)

        do {
            try archive.write(to: url, options: .atomic)
        } catch {
            throw ZipError.writeFailed("Could not write ZIP archive: \(error.localizedDescription)")
        }
    }

    private static func crc32Checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            return UInt32(zlib.crc32(0, base, uInt(buffer.count)))
        }
    }

    private static func dosDate() -> UInt16 {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let year = max(0, (components.year ?? 1980) - 1980)
        let month = components.month ?? 1
        let day = components.day ?? 1
        return UInt16((year << 9) | (month << 5) | day)
    }

    private static func dosTime() -> UInt16 {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: Date())
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = (components.second ?? 0) / 2
        return UInt16((hour << 11) | (minute << 5) | second)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
