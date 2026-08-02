//
//  BluetoothTest.swift
//  IMagix - Simple test for Bluetooth crash debugging
//

import Foundation
import CoreBluetooth

class SimpleBluetoothTest: NSObject, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager?
    
    func startTest() {
        print("🧪 Starting simple Bluetooth test...")
        
        // Very basic initialization
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("📱 Bluetooth state changed to: \(peripheral.state.rawValue)")
        
        switch peripheral.state {
        case .poweredOn:
            print("✅ Bluetooth is powered on")
        case .poweredOff:
            print("❌ Bluetooth is powered off")
        case .unauthorized:
            print("🚫 Bluetooth access not authorized")
        case .unsupported:
            print("⚠️ Bluetooth LE not supported")
        case .resetting:
            print("🔄 Bluetooth is resetting")
        case .unknown:
            print("❓ Bluetooth state unknown")
        @unknown default:
            print("🤷‍♂️ Unknown Bluetooth state")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("❌ Advertising failed: \(error.localizedDescription)")
        } else {
            print("✅ Advertising started successfully")
        }
    }
}

// Usage:
// let test = SimpleBluetoothTest()
// test.startTest()
