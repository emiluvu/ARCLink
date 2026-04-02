//
//  BluetoothManager.swift
//  BLE Demo
//
//  Created by Evan Overman on 3/3/26.
//

import Foundation
import CoreBluetooth
import OSLog

/**
 * Manager for bluetooth operation with the specific device we're concerned with. It fascilitates
 * interaction with a singular service and characteristic, and will automatically connect to a
 * device with the correct UUIDs.
 */
@Observable
final class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let UUID_SERVICE = CBUUID(string: "0000BEEF-0000-1000-8000-00805F9B34FB")
    static let UUID_CHARACTERISTIC = CBUUID(string: "0000FEED-0000-1000-8000-00805F9B34FB")
    
    private let logger = Logger()
    private var centralManager: CBCentralManager!
    private var device: CBPeripheral?
    
    private var deviceService: CBService? = nil
    private var deviceCharacteristic: CBCharacteristic? = nil
    
    /**
     * The raw data as was last read from the connected bluetooth device.
     */
    private(set) var deviceRawData: Data? = nil
    
    /**
     * The same data as ``deviceRawData`` but decoded as a ``String`` via UTF-8.
     */
    public var deviceDataString: String? {
        get {
            deviceRawData.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    /**
     * Creates a new ``BluetoothManager`` which will, on Bluetooth power on, scan for and connect to
     * a device advertising a service with UUID ``UUID_SERVICE`` with a characteristic with UUID
     * ``UUID_CHARACTERISTIC``.
     *
     * # Example
     *
     * Simple, complete example using SwiftUI.
     *
     * ```swift
     * import SwiftUI
     *
     * struct ContentView: View {
     *     private var bluetooth = BluetoothManager()
     *
     *     @State private var writeText = "Look mom, no hands!"
     *
     *     var body: some View {
     *         VStack(spacing: 32) {
     *             if !bluetooth.isConnected() {
     *                 Text("Waiting...")
     *             } else {
     *                 Text("Connected!")
     *                 Text(bluetooth.deviceDataString ?? "No data :(")
     *
     *                 // Get some data from the user to send.
     *                 TextField("Data to write", text: $writeText)
     *                     .border(.secondary)
     *                     .padding(.horizontal, 64)
     *
     *                 Button("Write to device!") {
     *                     // We already checked if we were connected and the text we
     *                     // have should be valid UTF-8.
     *                     try! bluetooth.writeString(writeText)
     *                 }
     *
     *                 Button("Read from device!") {
     *                     // Already check if we were connected.
     *                     try! bluetooth.read()
     *                 }
     *             }
     *
     *
     *         }
     *         .padding()
     *     }
     * }
     *
     * #Preview {
     *     ContentView()
     * }
     * ```
     */
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    /**
     * True when a device is connected and ready to be written to or read from. This means that the
     * device has produced the characteristics needed for both actions.
     */
    public func isConnected() -> Bool {
        device != nil && deviceService != nil && deviceCharacteristic != nil
    }
    
    /**
     * Write the given ``String`` to the current bluetooth device.
     *
     * This function throws ``BluetoothError.noDevice`` when no device is connected, and
     * ``BluetoothError.noCharacteristic`` when a device is connected by lacks the characteristic to
     * write to. In some cases ``BluetoothError.invalidArgument`` can be thrown if the given
     * ``String`` cannot be converted to UTF-8 bytes correctly, though this is unlikely.
     *
     * # Example
     *
     * ```swift
     * let btManager = BluetoothManager()
     *
     * do {
     *     btManager.write("Hello World!")
     * } catch BluetoothError.noDevice {
     *     print("Tried to write but had no device!")
     * } catch BluetoothError.noCharacteristic {
     *     print("Tried to write, but device lacked characteristic!")
     * } catch {
     *     print("Unknown error")
     * }
     * ```
     */
    public func writeString(_ text: String) throws(BluetoothError) {
        guard var data = text.data(using: .utf8) else { throw BluetoothError.invalidArgument }
        try write(&data)
    }
    
    /**
     * Write the given raw ``Data`` to the current bluetooth device.
     *
     * This function throws ``BluetoothError.noDevice`` when no device is connected, and
     * ``BluetoothError.noCharacteristic`` when a device is connected by lacks the characteristic to
     * write to.
     */

    public func write(_ data: inout Data) throws(BluetoothError) {
        guard let dev = device else { throw BluetoothError.noDevice }
        guard let characteristic = deviceCharacteristic else { throw BluetoothError.noCharacteristic }
        
        let chunkSize = 500
        
        while !data.isEmpty {
            let end = min(chunkSize, data.count)
            
            print("intended len: \(end)")
            
            var subdata = Data(count: 1)
            subdata[0] = 0
            subdata.append(data.subdata(in: 0..<end))
            
            print("subdata length: \(subdata.count)")
            
            dev.writeValue(subdata, for: characteristic, type: .withResponse)
            data.removeSubrange(0..<end)
        }
        
        var data = Data(count: 1)
        data[0] = 1

        dev.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    /**
     * Request to read from the current bluetooth device. If the device does not exist then this
     * function throws ``BluetoothError.noDevice``. If the device exists but the necessary
     * characteristic has not been discovered, this function throws
     * ``BluetoothError.noCharacteristic``.
     *
     * When a read succeeds, the ``BluetoothManager.deviceValue`` property is updated
     * with the newly read value.
     *
     * # Example
     *
     * ```swift
     * let btManager = BluetoothManager()
     *
     * do {
     *     btManager.read()
     * } catch BluetoothError.noDevice {
     *     print("Tried to read but had no device!")
     * } catch BluetoothError.noCharacteristic {
     *     print("Tried to read, but device lacked characteristic!")
     * } catch {
     *     print("Unknown error")
     * }
     *
     * // Assuming all went well, we can unwrap a `deviceValue` now! It may be
     * // worth being carefull though, there's no guarantee that `deviceValue`
     * // is not `nil`
     * let value = btManager.deviceValue!
     * ```
     */
    public func read() throws(BluetoothError) {
        guard let dev = device else { throw BluetoothError.noDevice }
        guard let characteristic = deviceCharacteristic else { throw BluetoothError.noCharacteristic }
        dev.readValue(for: characteristic)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            logger.error("Tried to scan for peripherals but Bluetooth is unavailable!")
            return
        }
        
        centralManager.scanForPeripherals(withServices: [BluetoothManager.UUID_SERVICE])
        logger.info("Scanning for Bluetooth peripherals ...")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        device = peripheral
        peripheral.delegate = self
        centralManager?.stopScan()
        centralManager?.connect(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BluetoothManager.UUID_SERVICE])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard let service = deviceService else { return }
        guard invalidatedServices.contains(service) else { return }
        
        logger.info("Device disconnected!")
        
        if let dev = device {
            centralManager.cancelPeripheralConnection(dev)
        }
        
        device = nil
        deviceService = nil
        deviceCharacteristic = nil
        
        centralManager.scanForPeripherals(withServices: [BluetoothManager.UUID_SERVICE])
        logger.info("Scanning for Bluetooth peripherals ...")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        deviceRawData = characteristic.value
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first else {
            logger.error("Services discovered event occured but discovered no services!")
            return
        }
        
        logger.info("Found service! Discovering characteristics ...")
        
        self.deviceService = service
        peripheral.discoverCharacteristics([BluetoothManager.UUID_CHARACTERISTIC], for: service)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard let characteristic = service.characteristics?.first else {
            logger.error("Characteristics discovered event occured but discovered no characteristics!")
            return
        }
        
        logger.info("Found characteristic!")
        self.deviceCharacteristic = characteristic
    }
}

/**
 * Errors which can occur during bluetooth operations.
 */
public enum BluetoothError: Error {
    /**
     * No device was ready for the operation performed.
     */
    case noDevice
    
    /**
     * There may have been a device but it lacked a service to use in the bluetooth operation.
     */
    case noService
    
    /**
     * There may have been both a device and usable service, but that service lacked a necessary
     * characteristic for the operation.
     */
    case noCharacteristic
    
    /**
     * An invalid argument was provided to the operation.
     */
    case invalidArgument
}
