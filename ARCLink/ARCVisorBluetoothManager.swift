//
//  ARCVisorBluetoothManager.swift
//  ARCLink
//

import Foundation
import Observation

#if !targetEnvironment(simulator)
import CoreBluetooth
import OSLog
#endif

@Observable
#if !targetEnvironment(simulator)
final class ARCVisorBluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
#else
final class ARCVisorBluetoothManager {
#endif
    struct CapabilityStatus: Equatable {
        var liveSectionSyncEnabled = false
        var taskOverlaysAvailable = false
    }

    enum ConnectionState: Equatable {
        case idle
        case bluetoothUnavailable
        case scanning
        case connecting
        case discovering
        case connected
        case failed(String)
    }

    private(set) var connectionState: ConnectionState = .idle
    private(set) var latestPayload: String?
    private(set) var capabilityStatus = CapabilityStatus()

    var isConnected: Bool {
        #if targetEnvironment(simulator)
        connectionState == .connected
        #else
        connectionState == .connected && peripheral != nil && service != nil && characteristic != nil
        #endif
    }

    var liveSectionSyncEnabled: Bool {
        capabilityStatus.liveSectionSyncEnabled
    }

    var taskOverlaysAvailable: Bool {
        capabilityStatus.taskOverlaysAvailable
    }

    var statusText: String {
        switch connectionState {
        case .idle:
            return "Ready to connect"
        case .bluetoothUnavailable:
            return "Bluetooth unavailable"
        case .scanning:
            return "Scanning for ARCVisor"
        case .connecting:
            return "Connecting to ARCVisor"
        case .discovering:
            return "Configuring ARCVisor"
        case .connected:
            return "ARCVisor connected"
        case .failed(let message):
            return message
        }
    }

    #if targetEnvironment(simulator)
    func connect() {
        connectionState = .discovering
        latestPayload = nil
        capabilityStatus = CapabilityStatus()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            connectionState = .connected
            latestPayload = "Simulator preview: ARCVisor paired successfully."
            capabilityStatus = CapabilityStatus(liveSectionSyncEnabled: true, taskOverlaysAvailable: true)
        }
    }
    #else
    static let serviceUUID = CBUUID(string: "0000BEEF-0000-1000-8000-00805F9B34FB")
    static let characteristicUUID = CBUUID(string: "0000FEED-0000-1000-8000-00805F9B34FB")

    private let logger = Logger(subsystem: "ARCLink", category: "ARCVisorBluetooth")
    private var centralManager: CBCentralManager?
    private var shouldConnectWhenPoweredOn = false
    private var peripheral: CBPeripheral?
    private var service: CBService?
    private var characteristic: CBCharacteristic?

    func connect() {
        shouldConnectWhenPoweredOn = true
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
            connectionState = .scanning
            return
        }

        guard let centralManager else { return }
        guard centralManager.state == .poweredOn else {
            connectionState = .bluetoothUnavailable
            return
        }

        startScanning()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            guard shouldConnectWhenPoweredOn else {
                connectionState = .idle
                return
            }
            startScanning()
        case .poweredOff, .resetting, .unauthorized, .unsupported, .unknown:
            cleanupConnection()
            connectionState = .bluetoothUnavailable
        @unknown default:
            cleanupConnection()
            connectionState = .bluetoothUnavailable
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        logger.info("Discovered ARCVisor peripheral")
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Connected to ARCVisor peripheral")
        connectionState = .discovering
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("Failed to connect to ARCVisor peripheral: \(error?.localizedDescription ?? "unknown error")")
        cleanupConnection()
        connectionState = .failed("Unable to connect to ARCVisor")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("ARCVisor disconnected")
        cleanupConnection()

        if shouldConnectWhenPoweredOn, central.state == .poweredOn {
            startScanning()
        } else {
            connectionState = .idle
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            logger.error("ARCVisor service discovery failed: \(error?.localizedDescription ?? "unknown error")")
            connectionState = .failed("ARCVisor service unavailable")
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            connectionState = .failed("ARCVisor service unavailable")
            return
        }

        self.service = service
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            logger.error("ARCVisor characteristic discovery failed: \(error?.localizedDescription ?? "unknown error")")
            connectionState = .failed("ARCVisor characteristic unavailable")
            return
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
            connectionState = .failed("ARCVisor characteristic unavailable")
            return
        }

        self.characteristic = characteristic
        connectionState = .connected
        capabilityStatus = CapabilityStatus(liveSectionSyncEnabled: true, taskOverlaysAvailable: true)
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            logger.error("ARCVisor read failed: \(error?.localizedDescription ?? "unknown error")")
            return
        }

        latestPayload = characteristic.value.flatMap { String(data: $0, encoding: .utf8) }
        updateCapabilities(from: latestPayload)
    }

    private func startScanning() {
        guard let centralManager, centralManager.state == .poweredOn else {
            connectionState = .bluetoothUnavailable
            return
        }

        cleanupConnection()
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: [Self.serviceUUID])
        logger.info("Scanning for ARCVisor")
    }

    private func cleanupConnection() {
        latestPayload = nil
        capabilityStatus = CapabilityStatus()
        service = nil
        characteristic = nil
        peripheral = nil
    }

    private func updateCapabilities(from payload: String?) {
        guard let payload, let data = payload.data(using: .utf8) else { return }

        struct PayloadCapabilities: Decodable {
            let liveSectionSyncEnabled: Bool?
            let taskOverlaysAvailable: Bool?
            let liveSectionSync: Bool?
            let taskOverlays: Bool?
        }

        guard let decoded = try? JSONDecoder().decode(PayloadCapabilities.self, from: data) else { return }

        capabilityStatus = CapabilityStatus(
            liveSectionSyncEnabled: decoded.liveSectionSyncEnabled ?? decoded.liveSectionSync ?? capabilityStatus.liveSectionSyncEnabled,
            taskOverlaysAvailable: decoded.taskOverlaysAvailable ?? decoded.taskOverlays ?? capabilityStatus.taskOverlaysAvailable
        )
    }
    #endif
}
