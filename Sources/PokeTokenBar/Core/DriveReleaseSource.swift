import Foundation

/// Public HTML metadata only. No API credentials, cookies or ZIP download are required.
enum DriveReleaseSource {
    static let shareURL=URL(string:"https://drive.google.com/file/d/1NYVOMV8fMqf-UGM-dIfKZ3wKV4PtITrN/view")!
    static func version(filename:String)->String? {
        let pattern="^PokeTokenBar-([0-9]{1,9}\\.[0-9]{1,9}\\.[0-9]{1,9})(?:-(?:[0-9]{6,8}(?:\\([1-9][0-9]{0,5}\\))?|arm64(?:-[A-Za-z0-9_-]{1,100})?))?\\.zip$"
        guard let re=try? NSRegularExpression(pattern:pattern),let match=re.firstMatch(in:filename,range:NSRange(filename.startIndex...,in:filename)),
              let range=Range(match.range(at:1),in:filename) else{return nil}
        return UpdateChecker.normalizedReleaseVersion(String(filename[range]))
    }
    static func release(html:String)->UpdateChecker.LatestRelease? {
        guard let re=try? NSRegularExpression(pattern:"<title[^>]*>([^<]{1,256})</title>",options:.caseInsensitive),
              let match=re.firstMatch(in:html,range:NSRange(html.startIndex...,in:html)),let range=Range(match.range(at:1),in:html) else{return nil}
        var title=String(html[range]).trimmingCharacters(in:.whitespacesAndNewlines)
        for (from,to) in [("&#40;","("),("&#41;",")"),("&#x28;","("),("&#x29;",")")]{title=title.replacingOccurrences(of:from,with:to)}
        guard title.hasSuffix(" - Google Drive"),let version=version(filename:String(title.dropLast(" - Google Drive".count))) else{return nil}
        return .init(tag:version,url:shareURL.absoluteString)
    }
    static func fetch() async ->UpdateChecker.LatestRelease? {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=15;configuration.timeoutIntervalForResource=20
        let session=URLSession(configuration:configuration);defer{session.invalidateAndCancel()}
        do {
            let (bytes,response)=try await session.bytes(for:URLRequest(url:shareURL,cachePolicy:.reloadIgnoringLocalCacheData))
            guard let http=response as? HTTPURLResponse,http.statusCode==200,http.url?.host=="drive.google.com",
                  http.mimeType=="text/html",http.expectedContentLength<=1_048_576 else{return nil}
            var data=Data()
            for try await byte in bytes {
                guard data.count<1_048_576,!Task.isCancelled else{return nil}
                data.append(byte)
            }
            guard let html=String(data:data,encoding:.utf8) else{return nil}
            return release(html:html)
        }catch{return nil}
    }
}
