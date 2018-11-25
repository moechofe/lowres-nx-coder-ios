//
//  ToolsMenuConfiguration.swift
//  LowRes NX Coder
//
//  Created by Timo Kloss on 13/3/18.
//  Copyright © 2018 Inutilis Software. All rights reserved.
//

import UIKit

class ToolsMenuConfiguration: NSObject {
    
    private let defaultPrograms = [
        "Char Designer 1.2.nx",
        "BG Designer 1.2.nx",
        "Sound Composer 0.3.nx"
    ]
    
    private(set) var programUrls: [URL]!
    
    private var userPrograms: [String] {
        get {
            return UserDefaults.standard.array(forKey: "ToolsMenuConfiguration") as? [String] ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "ToolsMenuConfiguration")
        }
    }
    
    override init() {
        super.init()
        programUrls = defaultProgramUrls()
        
        let documentsUrl = ProjectManager.shared.currentDocumentsUrl
        for program in userPrograms {
            programUrls.append(documentsUrl.appendingPathComponent(program))
        }
    }
    
    func addProgram(url: URL) {
        if !programUrls.contains(url) {
            let program = url.lastPathComponent
            userPrograms.append(program)
            programUrls.append(url)
        }
    }
    
    func reset() {
        userPrograms = []
        programUrls = defaultProgramUrls()
    }
    
    var canReset: Bool {
        return !userPrograms.isEmpty
    }
    
    private func defaultProgramUrls() -> [URL] {
        var urls = [URL]()
        let documentsUrl = ProjectManager.shared.currentDocumentsUrl
        for program in defaultPrograms {
            urls.append(documentsUrl.appendingPathComponent(program))
        }
        return urls
    }
    
}
