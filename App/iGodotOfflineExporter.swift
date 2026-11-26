import Foundation

enum ExportPlatform: String, CaseIterable {
    case iOS = "iOS (.ipa for SideStore)"
    case windows = "Windows (.exe)"
    case android = "Android (.apk)"
}

final class iGodotOfflineExporter {
    static let shared = iGodotOfflineExporter()
    
    func exportGame(project: iGodotProject, platform: ExportPlatform) -> Result<URL, Error> {
        let fm = FileManager.default
        let exportsDir = iGodotBootstrap.shared.documentsURL.appendingPathComponent("Exports", isDirectory: true)
        try? fm.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        
        let templatesDir = iGodotBootstrap.shared.templatesRootURL
        let templateName: String
        let outputExt: String
        
        switch platform {
        case .windows:
            templateName = "igodot_windows_release_x86_64.exe"
            outputExt = "exe"
        case .iOS:
            templateName = "igodot_ios_release.zip"
            outputExt = "ipa"
        case .android:
            templateName = "igodot_android_release_arm64.apk"
            outputExt = "apk"
        }
        
        let templateURL = templatesDir.appendingPathComponent(templateName)
        let outputURL = exportsDir.appendingPathComponent("\(project.name).\(outputExt)")
        
        guard fm.fileExists(atPath: templateURL.path) else {
            return .failure(NSError(
                domain: "iGodotExporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Place \(templateName) inside On My iPad / iGodot / Templates/"]
            ))
        }
        
        try? fm.removeItem(at: outputURL)
        try? fm.copyItem(at: templateURL, to: outputURL)
        return .success(outputURL)
    }
}

