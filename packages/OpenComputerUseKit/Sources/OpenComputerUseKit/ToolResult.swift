import Foundation

public struct ToolResultContentItem: @unchecked Sendable {
    let dictionary: [String: Any]

    public static func text(_ text: String) -> ToolResultContentItem {
        ToolResultContentItem(
            dictionary: [
                "type": "text",
                "text": text,
            ]
        )
    }

    static func screenshotImage(_ data: Data) -> ToolResultContentItem {
        ToolResultContentItem(dictionary: [
            "type": "image", "data": data.base64EncodedString(),
            "mimeType": data.starts(with: [0xff, 0xd8, 0xff]) ? "image/jpeg" : (data.count >= 12 && String(data: data.subdata(in: 8..<12), encoding: .ascii) == "WEBP" ? "image/webp" : "image/png"),
        ])
    }

    public static func pngImage(_ data: Data) -> ToolResultContentItem {
        ToolResultContentItem(
            dictionary: [
                "type": "image",
                "data": data.base64EncodedString(),
                "mimeType": "image/png",
            ]
        )
    }
}

public struct ToolCallResult: @unchecked Sendable {
    public let content: [ToolResultContentItem]
    public let isError: Bool

    public init(content: [ToolResultContentItem], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    public var primaryText: String? {
        content.first(where: { $0.dictionary["type"] as? String == "text" })?.dictionary["text"] as? String
    }

    /// Plain-text CLI output includes observation notes but never image bytes.
    public var textContent: String {
        content.compactMap { item in
            item.dictionary["type"] as? String == "text" ? item.dictionary["text"] as? String : nil
        }.joined(separator: "\n")
    }

    public var asDictionary: [String: Any] {
        [
            "content": content.map(\.dictionary),
            "isError": isError,
        ]
    }

    public var hasScreenshotContent: Bool {
        content.contains { $0.dictionary["type"] as? String == "image" }
    }

    /// Write every image content item to `path`. The first image uses the exact
    /// path; additional images get `-1`, `-2`, ... before the extension.
    @discardableResult
    public func writeScreenshots(to path: String, startingAt startIndex: Int = 0) throws -> Int {
        let url = URL(fileURLWithPath: path)
        var written = startIndex
        for item in content {
            guard item.dictionary["type"] as? String == "image",
                  let dataString = item.dictionary["data"] as? String,
                  let data = Data(base64Encoded: dataString) else {
                continue
            }

            let target: URL
            if written == 0 {
                target = url
            } else {
                let ext = url.pathExtension
                let base = url.deletingPathExtension().lastPathComponent
                let filename = ext.isEmpty ? "\(base)-\(written)" : "\(base)-\(written).\(ext)"
                target = url.deletingLastPathComponent().appendingPathComponent(filename)
            }

            do {
                try data.write(to: target, options: .atomic)
            } catch {
                throw ComputerUseError.message("Failed to write screenshot to \(target.path): \(error.localizedDescription)")
            }
            written += 1
        }

        guard written > startIndex else {
            throw ComputerUseError.message("No screenshot content to write to \(path).")
        }
        return written - startIndex
    }

    /// Return the MCP-style dictionary with image blocks replaced by a short
    /// note. Use after `writeScreenshots(to:)` to keep base64 out of stdout.
    public func dictionaryReplacingScreenshots(with note: String) -> [String: Any] {
        var dictionary = asDictionary
        guard var items = dictionary["content"] as? [[String: Any]] else {
            return dictionary
        }
        items = items.map { item in
            item["type"] as? String == "image" ? ["type": "text", "text": note] : item
        }
        dictionary["content"] = items
        return dictionary
    }

    public static func text(_ text: String, isError: Bool = false) -> ToolCallResult {
        ToolCallResult(content: [.text(text)], isError: isError)
    }
}
