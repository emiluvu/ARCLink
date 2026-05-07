//
//  ARCLinkApp.swift
//  ARCLink
//
//  Created by Emilia Vu on 3/9/26.
//

import SwiftUI

@main
struct ARCLinkApp: App {
    @State private var bluetoothManager = BluetoothManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bluetoothManager)
        }
    }
}
