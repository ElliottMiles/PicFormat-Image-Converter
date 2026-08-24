//
//  Good_Image_ConverterApp.swift
//  Good_Image_Converter
//
//  Created by Agent Sandbox on 8/16/26.
//

import SwiftUI

@main
struct Good_Image_ConverterApp: App {
    init() {
        FileExportService.cleanUpTemporaryDirectoryOnLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
