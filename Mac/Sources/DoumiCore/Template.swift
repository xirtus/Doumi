public import Foundation

public struct TemplateContext {
    public let url: URL
    private let cachedAttrs: [FileAttributeKey: Any]?

    public var filename: String { url.lastPathComponent }
    public var stem: String { url.deletingPathExtension().lastPathComponent }
    public var ext: String { url.pathExtension }

    public var modDate: Date { cachedAttrs?[.modificationDate] as? Date ?? Date() }
    public var creDate: Date { cachedAttrs?[.creationDate] as? Date ?? Date() }
    public var fileSize: Int { cachedAttrs?[.size] as? Int ?? 0 }

    public init(url: URL) {
        self.url = url
        self.cachedAttrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    }
}

public func expandTemplate(_ template: String, context: TemplateContext) -> String {
    let cal = Calendar.current
    let mod = context.modDate
    let cre = context.creDate

    let posixDate = DateFormatter()
    posixDate.locale = Locale(identifier: "en_US_POSIX")
    posixDate.dateFormat = "yyyy-MM-dd"

    let posixTime = DateFormatter()
    posixTime.locale = Locale(identifier: "en_US_POSIX")
    posixTime.dateFormat = "HH-mm-ss"

    let p2: (Int) -> String = { String(format: "%02d", $0) }
    let p4: (Int) -> String = { String(format: "%04d", $0) }

    return [
        ("{filename}", context.filename), ("{name}", context.stem), ("{stem}", context.stem),
        ("{ext}", context.ext), ("{size}", String(context.fileSize)),
        ("{year}",   p4(cal.component(.year,   from: mod))),
        ("{month}",  p2(cal.component(.month,  from: mod))),
        ("{day}",    p2(cal.component(.day,    from: mod))),
        ("{hour}",   p2(cal.component(.hour,   from: mod))),
        ("{minute}", p2(cal.component(.minute, from: mod))),
        ("{date}", posixDate.string(from: mod)),
        ("{time}", posixTime.string(from: mod)),
        ("{created_year}",  p4(cal.component(.year,  from: cre))),
        ("{created_month}", p2(cal.component(.month, from: cre))),
        ("{created_day}",   p2(cal.component(.day,   from: cre))),
        ("{created_date}",  posixDate.string(from: cre)),
    ].reduce(template) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
}

public func expandPath(_ path: String, context: TemplateContext) -> String {
    (expandTemplate(path, context: context) as NSString).expandingTildeInPath
}
