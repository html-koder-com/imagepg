import AppKit

@main
struct UpdateCheck {
    static func main() {
        _ = NSApplication.shared
        precondition(UpdateChecker.isNewer("v0.2.0", than: "0.1.0"))
        precondition(UpdateChecker.isNewer("1.0", than: "0.9.9"))
        precondition(UpdateChecker.isNewer("0.10.0", than: "0.9.0"), "numeric, not lexical")
        precondition(UpdateChecker.isNewer("0.1.1", than: "0.1"))
        precondition(!UpdateChecker.isNewer("v0.1.0", than: "0.1.0"))
        precondition(!UpdateChecker.isNewer("0.1", than: "0.1.0"))
        precondition(!UpdateChecker.isNewer("0.0.9", than: "0.1.0"))
        precondition(!UpdateChecker.isNewer("", than: "0.1.0"))
        precondition(UpdateChecker.components("v1.2.3-beta") == [1, 2, 3])

        let json = #"{"tag_name":"v0.2.0","name":"ImagePG 0.2.0","html_url":"https://github.com/html-koder-com/imagepg/releases/tag/v0.2.0","draft":false,"prerelease":false}"#
        guard let release = UpdateChecker.parse(Data(json.utf8)) else { fatalError("parse release") }
        precondition(release.version == "0.2.0" && release.name == "ImagePG 0.2.0")
        precondition(release.url.absoluteString.hasSuffix("/releases/tag/v0.2.0"))
        let unnamed = #"{"tag_name":"0.3.0","name":"","html_url":"https://example.com/r"}"#
        precondition(UpdateChecker.parse(Data(unnamed.utf8))?.name == "ImagePG 0.3.0")
        let draft = #"{"tag_name":"v9.0.0","html_url":"https://example.com/r","draft":true}"#
        precondition(UpdateChecker.parse(Data(draft.utf8)) == nil, "drafts are ignored")
        precondition(UpdateChecker.parse(Data("not json".utf8)) == nil)
        print("OK: version comparison, release parsing")
    }
}
