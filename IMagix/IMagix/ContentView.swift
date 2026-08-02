//
//  ContentView.swift
//  IMagix
//
//  Created by Elliot Williams on 2025-07-04.
//

import SwiftUI
import MultipeerConnectivity
import CoreMotion
import CoreBluetooth
import Combine
import AVFoundation

// MARK: - Bluetooth Controller
class BluetoothController: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager?
    private var hidService: CBMutableService?
    private var reportCharacteristic: CBMutableCharacteristic?
    private let serialQueue = DispatchQueue(label: "BluetoothController.serialQueue")
    private var isInitializing = false
    
    @Published var isBluetoothEnabled = false
    @Published var isAdvertising = false
    @Published var isConnected = false
    @Published var initializationComplete = false
    @Published var errorMessage: String?
    
    // Debug function to check state
    func debugBluetoothState() {
        print("=== Bluetooth Debug Info ===")
        print("Running on: \(isRunningOnSimulator() ? "Simulator" : "Device")")
        print("Peripheral Manager: \(peripheralManager != nil ? "✓" : "✗")")
        print("Bluetooth Enabled: \(isBluetoothEnabled)")
        print("Initialization Complete: \(initializationComplete)")
        print("Is Advertising: \(isAdvertising)")
        print("Is Connected: \(isConnected)")
        if let pm = peripheralManager {
            print("Peripheral Manager State: \(pm.state.rawValue) (\(stateDescription(pm.state)))")
        }
        print("=========================")
    }
    
    private func isRunningOnSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported"
        case .unauthorized: return "Unauthorized"
        case .poweredOff: return "Powered Off"
        case .poweredOn: return "Powered On"
        @unknown default: return "Unknown State"
        }
    }
    
    // HID UUIDs
    private let hidServiceUUID = CBUUID(string: "1812")
    private let reportMapUUID = CBUUID(string: "2A4B")
    private let reportUUID = CBUUID(string: "2A4D")
    private let protocolModeUUID = CBUUID(string: "2A4E")
    private let hidInfoUUID = CBUUID(string: "2A4A")
    private let hidControlPointUUID = CBUUID(string: "2A4C")
    
    // HID Report Map for a mouse with scroll wheel
    private let hidReportMap: [UInt8] = [
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x02,        // Usage (Mouse)
        0xA1, 0x01,        // Collection (Application)
        0x09, 0x01,        //   Usage (Pointer)
        0xA1, 0x00,        //   Collection (Physical)
        // Buttons
        0x05, 0x09,        //     Usage Page (Button)
        0x19, 0x01,        //     Usage Minimum (1)
        0x29, 0x02,        //     Usage Maximum (2)
        0x15, 0x00,        //     Logical Minimum (0)
        0x25, 0x01,        //     Logical Maximum (1)
        0x95, 0x02,        //     Report Count (2)
        0x75, 0x01,        //     Report Size (1)
        0x81, 0x02,        //     Input (Data, Var, Abs)
        // Padding
        0x95, 0x01,        //     Report Count (1)
        0x75, 0x06,        //     Report Size (6)
        0x81, 0x01,        //     Input (Const, Array, Abs)
        // Movement
        0x05, 0x01,        //     Usage Page (Generic Desktop)
        0x09, 0x30,        //     Usage (X)
        0x09, 0x31,        //     Usage (Y)
        0x15, 0x81,        //     Logical Minimum (-127)
        0x25, 0x7F,        //     Logical Maximum (127)
        0x75, 0x08,        //     Report Size (8)
        0x95, 0x02,        //     Report Count (2)
        0x81, 0x06,        //     Input (Data, Var, Rel)
        // Scroll Wheel
        0x09, 0x38,        //     Usage (Wheel)
        0x15, 0x81,        //     Logical Minimum (-127)
        0x25, 0x7F,        //     Logical Maximum (127)
        0x75, 0x08,        //     Report Size (8)
        0x95, 0x01,        //     Report Count (1)
        0x81, 0x06,        //     Input (Data, Var, Rel)
        0xC0,              //   End Collection
        0xC0               // End Collection
    ]
    
    override init() {
        print("🔄 BluetoothController: Starting initialization...")
        super.init()
        print("✅ BluetoothController: Super.init() completed")
        
        // Don't initialize Bluetooth automatically - make it manual
        // This prevents crashes on startup
        DispatchQueue.main.async {
            self.initializationComplete = true
            print("✅ BluetoothController: Marked as initialized (without starting Bluetooth)")
        }
    }
    
    // Manual initialization method
    func initializeBluetooth() {
        print("🔄 BluetoothController: Manual Bluetooth initialization requested")
        setupPeripheralManager()
    }
    
    private func setupPeripheralManager() {
        print("🔄 BluetoothController: setupPeripheralManager() called")
        
        guard !isInitializing else { 
            print("⚠️ BluetoothController: Already initializing, skipping...")
            return 
        }
        
        print("🔄 BluetoothController: Setting isInitializing = true")
        isInitializing = true
        
        DispatchQueue.main.async {
            print("🔄 BluetoothController: Clearing error message")
            self.errorMessage = nil
        }
        
        // Check if we're running on simulator
        let isSimulator = self.isRunningOnSimulator()
        print("📱 BluetoothController: Running on \(isSimulator ? "Simulator" : "Physical Device")")
        
        // Initialize on main queue to avoid potential delegate issues
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { 
                print("❌ BluetoothController: Self is nil in setupPeripheralManager async block")
                return 
            }
            
            print("🔄 BluetoothController: About to create CBPeripheralManager")
            
            do {
                // On simulator, we might want to handle this differently
                if isSimulator {
                    print("⚠️ BluetoothController: Creating peripheral manager on simulator - this may cause issues")
                }
                
                self.peripheralManager = CBPeripheralManager(
                    delegate: self, 
                    queue: self.serialQueue, 
                    options: [
                        CBPeripheralManagerOptionShowPowerAlertKey: false, // Changed to false to avoid potential issues
                        CBPeripheralManagerOptionRestoreIdentifierKey: "IMagixPeripheralManager"
                    ]
                )
                print("✅ BluetoothController: Peripheral manager created successfully")
                
                // Add a timeout to handle cases where delegate methods might not be called
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if !self.initializationComplete {
                        print("⚠️ BluetoothController: Initialization timeout - forcing completion")
                        self.initializationComplete = true
                        self.errorMessage = "Bluetooth initialization timed out"
                    }
                }
                
            } catch {
                print("❌ CRITICAL ERROR: Failed to initialize peripheral manager: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("❌ Error domain: \(nsError.domain)")
                    print("❌ Error code: \(nsError.code)")
                    print("❌ Error userInfo: \(nsError.userInfo)")
                }
                
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to initialize Bluetooth: \(error.localizedDescription)"
                    self.initializationComplete = true
                }
            }
        }
    }
    
    func startAdvertising() {
        print("🚀 Starting advertising process...")
        
        // First check if we can proceed
        guard initializationComplete else {
            print("❌ Cannot start advertising: Bluetooth not initialized")
            DispatchQueue.main.async {
                self.errorMessage = "Bluetooth not initialized yet. Please wait."
            }
            return
        }
        
        serialQueue.async { [weak self] in
            guard let self = self else { 
                print("❌ Self is nil in startAdvertising")
                return 
            }
            
            // Check if running on simulator
            if self.isRunningOnSimulator() {
                print("⚠️ WARNING: Running on iOS Simulator. Bluetooth LE peripheral mode may not work properly.")
                print("⚠️ Please test on a physical iOS device for full Bluetooth functionality.")
            }
            
            // Safety check: ensure peripheral manager is not nil and initialized
            guard let peripheralManager = self.peripheralManager else {
                print("❌ ERROR: Peripheral manager is nil")
                DispatchQueue.main.async {
                    self.errorMessage = "Bluetooth peripheral manager not available"
                }
                return
            }
            
            print("🔍 Checking Bluetooth state: \(peripheralManager.state.rawValue) (\(self.stateDescription(peripheralManager.state)))")
            
            guard peripheralManager.state == .poweredOn else {
                let stateDesc = self.stateDescription(peripheralManager.state)
                print("❌ ERROR: Bluetooth not ready: \(peripheralManager.state.rawValue) (\(stateDesc))")
                
                var userMessage = "Bluetooth not ready: \(stateDesc)"
                
                // Provide specific guidance based on the state
                switch peripheralManager.state {
                case .unauthorized:
                    print("💡 SOLUTION: Check Bluetooth permissions in iOS Settings > Privacy & Security > Bluetooth")
                    userMessage = "Bluetooth access not authorized. Check Settings > Privacy > Bluetooth"
                case .unsupported:
                    print("💡 SOLUTION: This device does not support Bluetooth LE")
                    userMessage = "This device does not support Bluetooth LE"
                case .poweredOff:
                    print("💡 SOLUTION: Turn on Bluetooth in Control Center or Settings")
                    userMessage = "Please turn on Bluetooth"
                case .resetting:
                    print("💡 INFO: Bluetooth is resetting, please wait...")
                    userMessage = "Bluetooth is resetting, please wait..."
                case .unknown:
                    print("💡 INFO: Bluetooth state is unknown, initialization may be in progress")
                    userMessage = "Bluetooth state unknown, please wait..."
                default:
                    break
                }
                
                DispatchQueue.main.async {
                    self.errorMessage = userMessage
                }
                return
            }
            
            // Clear any previous error
            DispatchQueue.main.async {
                self.errorMessage = nil
            }
            
            print("✅ Bluetooth is ready, proceeding with advertising setup...")
            self.performStartAdvertising()
        }
    }
    
    private func performStartAdvertising() {
        print("🔧 Setting up HID service and characteristics...")
        
        // Reset existing service if needed
        performStopAdvertising()
        
        // Create HID Service
        do {
            hidService = CBMutableService(type: hidServiceUUID, primary: true)
            print("✅ HID service created successfully")
        } catch {
            print("❌ ERROR: Failed to create HID service: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to create HID service: \(error.localizedDescription)"
            }
            return
        }
        
        // Create characteristics with error handling
        do {
            // Create Report Map Characteristic
            let reportMapData = Data(hidReportMap)
            let reportMapCharacteristic = CBMutableCharacteristic(
                type: reportMapUUID,
                properties: [.read],
                value: reportMapData,
                permissions: [.readable]
            )
            print("✅ Report map characteristic created")
            
            // Create Protocol Mode Characteristic
            let protocolModeData = Data([0x01]) // Report Protocol Mode
            let protocolModeCharacteristic = CBMutableCharacteristic(
                type: protocolModeUUID,
                properties: [.read, .writeWithoutResponse],
                value: protocolModeData,
                permissions: [.readable, .writeable]
            )
            print("✅ Protocol mode characteristic created")
            
            // Create HID Information Characteristic
            let hidInfoData = Data([0x00, 0x01, 0x00, 0x00]) // Version 1.0, country code 0
            let infoCharacteristic = CBMutableCharacteristic(
                type: hidInfoUUID,
                properties: [.read],
                value: hidInfoData,
                permissions: [.readable]
            )
            print("✅ HID info characteristic created")
            
            // Create Control Point Characteristic
            let controlPointCharacteristic = CBMutableCharacteristic(
                type: hidControlPointUUID,
                properties: [.writeWithoutResponse],
                value: nil,
                permissions: [.writeable]
            )
            print("✅ Control point characteristic created")
            
            // Create HID Report Characteristic
            reportCharacteristic = CBMutableCharacteristic(
                type: reportUUID,
                properties: [.read, .notify],
                value: nil,
                permissions: [.readable]
            )
            print("✅ Report characteristic created")
            
            // Safely add characteristics to service
            guard let reportChar = reportCharacteristic,
                  let service = hidService else {
                print("❌ ERROR: Failed to get required characteristics or service")
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to create required Bluetooth characteristics"
                }
                return
            }
            
            service.characteristics = [
                reportMapCharacteristic,
                reportChar,
                protocolModeCharacteristic,
                infoCharacteristic,
                controlPointCharacteristic
            ]
            print("✅ All characteristics added to service")
            
            // Add service to peripheral manager
            guard let peripheralManager = peripheralManager else {
                print("❌ ERROR: Peripheral manager is nil when adding service")
                DispatchQueue.main.async {
                    self.errorMessage = "Peripheral manager not available"
                }
                return
            }
            
            print("🔄 Adding service to peripheral manager...")
            peripheralManager.add(service)
            
            // Start advertising (this will be confirmed in the delegate method)
            let advertisementData: [String: Any] = [
                CBAdvertisementDataServiceUUIDsKey: [hidServiceUUID],
                CBAdvertisementDataLocalNameKey: "iPhone Mouse"
            ]
            
            print("📡 Starting Bluetooth LE advertising...")
            peripheralManager.startAdvertising(advertisementData)
            
            DispatchQueue.main.async {
                self.isAdvertising = true
            }
            
        } catch {
            print("❌ CRITICAL ERROR: Exception during characteristic creation: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to setup Bluetooth characteristics: \(error.localizedDescription)"
            }
        }
    }
    
    func stopAdvertising() {
        serialQueue.async { [weak self] in
            self?.performStopAdvertising()
        }
    }
    
    private func performStopAdvertising() {
        // Safety check: ensure peripheral manager is not nil
        guard let peripheralManager = peripheralManager else {
            print("Peripheral manager is nil in stopAdvertising")
            return
        }
        
        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
        }
        
        // Remove existing services
        if let service = hidService {
            peripheralManager.remove(service)
        }
        
        hidService = nil
        reportCharacteristic = nil
        
        DispatchQueue.main.async {
            self.isAdvertising = false
            self.isConnected = false
        }
    }
    
    func sendMouseReport(dx: Int8, dy: Int8, buttons: UInt8, wheel: Int8 = 0) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            guard let peripheralManager = self.peripheralManager else { return }
            guard self.isConnected, let characteristic = self.reportCharacteristic else { return }
            
            // Create HID report: [buttons, dx, dy, wheel]
            let report = Data([
                buttons,                // Button state
                UInt8(bitPattern: dx),  // X movement
                UInt8(bitPattern: dy),  // Y movement
                UInt8(bitPattern: wheel) // Scroll wheel
            ])
            
            peripheralManager.updateValue(
                report,
                for: characteristic,
                onSubscribedCentrals: nil
            )
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("🔄 BluetoothController: peripheralManagerDidUpdateState called")
        print("📡 Bluetooth state: \(peripheral.state.rawValue) (\(stateDescription(peripheral.state)))")
        
        DispatchQueue.main.async {
            print("🔄 BluetoothController: Updating state on main queue")
            self.isBluetoothEnabled = peripheral.state == .poweredOn
            self.initializationComplete = true
            
            print("✅ BluetoothController: isBluetoothEnabled = \(self.isBluetoothEnabled)")
            print("✅ BluetoothController: initializationComplete = \(self.initializationComplete)")
            
            // Reset advertising state if Bluetooth was turned off
            if peripheral.state != .poweredOn && self.isAdvertising {
                print("⚠️ BluetoothController: Bluetooth not powered on, resetting advertising state")
                self.isAdvertising = false
                self.isConnected = false
            }
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("Error advertising: \(error.localizedDescription)")
                self.isAdvertising = false
            } else {
                print("Started advertising as HID device")
                self.isAdvertising = true
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("Error adding service: \(error.localizedDescription)")
        } else {
            print("HID service added successfully")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("Connected to central: \(central.identifier)")
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("Disconnected from central: \(central.identifier)")
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}

// MARK: - Theme System
struct Theme: Identifiable {
    let id = UUID()
    let name: String
    let primaryColor: Color
    let secondaryColor: Color
    let buttonColor: Color
    let background: AnyView
    let isAnimated: Bool
    let buttonShape: ButtonShape
    let buttonSize: ButtonSize
    
    enum ButtonShape {
        case rectangle
        case rounded
        case circle
        case capsule
    }
    
    enum ButtonSize {
        case small
        case medium
        case large
    }
}

class ThemeManager: ObservableObject {
    @Published var currentThemeIndex: Int = 0
    @Published var themes: [Theme] = []
    
    init() {
        createThemes()
    }
    
    private func createThemes() {
        // Solid Color Themes
        themes.append(Theme(
            name: "Ocean Blue",
            primaryColor: .blue,
            secondaryColor: .white,
            buttonColor: .blue,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.3)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Midnight",
            primaryColor: .purple,
            secondaryColor: .white,
            buttonColor: .purple,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.1, green: 0, blue: 0.2), Color(red: 0.3, green: 0, blue: 0.4)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Sunset",
            primaryColor: .orange,
            secondaryColor: .white,
            buttonColor: .orange,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.orange, Color.red]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Emerald",
            primaryColor: .green,
            secondaryColor: .white,
            buttonColor: .green,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.green.opacity(0.7), Color.mint.opacity(0.4)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Crimson",
            primaryColor: .red,
            secondaryColor: .white,
            buttonColor: .red,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.red.opacity(0.8), Color.pink.opacity(0.4)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Gold Rush",
            primaryColor: .yellow,
            secondaryColor: .black,
            buttonColor: .yellow,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.yellow.opacity(0.7), Color.orange.opacity(0.4)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Neon Pink",
            primaryColor: .pink,
            secondaryColor: .white,
            buttonColor: .pink,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.pink.opacity(0.8), Color.purple.opacity(0.4)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Steel Blue",
            primaryColor: .gray,
            secondaryColor: .white,
            buttonColor: .blue,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.7), Color.blue.opacity(0.4)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        // Animated Themes
        themes.append(Theme(
            name: "Cosmic",
            primaryColor: .white,
            secondaryColor: .white,
            buttonColor: .purple,
            background: AnyView(CosmicBackground()),
            isAnimated: true,
            buttonShape: .circle,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Particles",
            primaryColor: .white,
            secondaryColor: .white,
            buttonColor: .green,
            background: AnyView(ParticleBackground()),
            isAnimated: true,
            buttonShape: .circle,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Rainbow",
            primaryColor: .white,
            secondaryColor: .black,
            buttonColor: .pink,
            background: AnyView(RainbowBackground()),
            isAnimated: true,
            buttonShape: .capsule,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Galaxy",
            primaryColor: .white,
            secondaryColor: .white,
            buttonColor: .indigo,
            background: AnyView(GalaxyBackground()),
            isAnimated: true,
            buttonShape: .rectangle,
            buttonSize: .small
        ))
        
        themes.append(Theme(
            name: "Aurora",
            primaryColor: .white,
            secondaryColor: .white,
            buttonColor: .teal,
            background: AnyView(AuroraBackground()),
            isAnimated: true,
            buttonShape: .rounded,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Lava",
            primaryColor: .orange,
            secondaryColor: .white,
            buttonColor: .red,
            background: AnyView(LavaBackground()),
            isAnimated: true,
            buttonShape: .rounded,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Cyberpunk",
            primaryColor: .blue,
            secondaryColor: .pink,
            buttonColor: .pink,
            background: AnyView(CyberpunkBackground()),
            isAnimated: true,
            buttonShape: .rectangle,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Starry Night",
            primaryColor: .blue,
            secondaryColor: .yellow,
            buttonColor: .yellow,
            background: AnyView(StarryNightBackground()),
            isAnimated: true,
            buttonShape: .circle,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Digital Rain",
            primaryColor: .green,
            secondaryColor: .black,
            buttonColor: .green,
            background: AnyView(DigitalRainBackground()),
            isAnimated: true,
            buttonShape: .rectangle,
            buttonSize: .small
        ))
        
        themes.append(Theme(
            name: "Watercolor",
            primaryColor: .white,
            secondaryColor: .black,
            buttonColor: .purple,
            background: AnyView(WatercolorBackground()),
            isAnimated: true,
            buttonShape: .capsule,
            buttonSize: .medium
        ))
        
        // MARK: - Additional Solid Color Themes
        
        themes.append(Theme(
            name: "Arctic",
            primaryColor: .cyan,
            secondaryColor: .black,
            buttonColor: .cyan,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.cyan.opacity(0.8), Color.white.opacity(0.3)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .circle,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Forest",
            primaryColor: Color(red: 0.2, green: 0.6, blue: 0.2),
            secondaryColor: .white,
            buttonColor: Color(red: 0.1, green: 0.5, blue: 0.1),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.1, green: 0.3, blue: 0.1), Color(red: 0.2, green: 0.5, blue: 0.2)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Rose Gold",
            primaryColor: Color(red: 0.9, green: 0.7, blue: 0.7),
            secondaryColor: .white,
            buttonColor: Color(red: 0.8, green: 0.5, blue: 0.5),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.9, green: 0.7, blue: 0.7), Color(red: 0.8, green: 0.6, blue: 0.5)]), startPoint: .topLeading, endPoint: .bottomTrailing)),
            isAnimated: false,
            buttonShape: .capsule,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Monochrome",
            primaryColor: .white,
            secondaryColor: .black,
            buttonColor: .gray,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.black, Color.gray]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rectangle,
            buttonSize: .small
        ))
        
        themes.append(Theme(
            name: "Lavender",
            primaryColor: Color(red: 0.7, green: 0.6, blue: 0.9),
            secondaryColor: .white,
            buttonColor: Color(red: 0.6, green: 0.5, blue: 0.8),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.7, green: 0.6, blue: 0.9), Color(red: 0.8, green: 0.7, blue: 0.95)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Coral Reef",
            primaryColor: Color(red: 1.0, green: 0.5, blue: 0.3),
            secondaryColor: .white,
            buttonColor: Color(red: 0.9, green: 0.4, blue: 0.2),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 1.0, green: 0.5, blue: 0.3), Color(red: 0.2, green: 0.7, blue: 0.9)]), startPoint: .topLeading, endPoint: .bottomTrailing)),
            isAnimated: false,
            buttonShape: .circle,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Mint Chocolate",
            primaryColor: Color(red: 0.4, green: 0.8, blue: 0.6),
            secondaryColor: Color(red: 0.2, green: 0.1, blue: 0.0),
            buttonColor: Color(red: 0.3, green: 0.7, blue: 0.5),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.4, green: 0.8, blue: 0.6), Color(red: 0.3, green: 0.2, blue: 0.1)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .capsule,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Turquoise",
            primaryColor: Color(red: 0.25, green: 0.88, blue: 0.82),
            secondaryColor: .white,
            buttonColor: Color(red: 0.2, green: 0.8, blue: 0.75),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.25, green: 0.88, blue: 0.82), Color(red: 0.1, green: 0.6, blue: 0.8)]), startPoint: .topTrailing, endPoint: .bottomLeading)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Burgundy",
            primaryColor: Color(red: 0.8, green: 0.1, blue: 0.3),
            secondaryColor: .white,
            buttonColor: Color(red: 0.7, green: 0.0, blue: 0.2),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.5, green: 0.0, blue: 0.1), Color(red: 0.8, green: 0.1, blue: 0.3)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rectangle,
            buttonSize: .small
        ))
        
        themes.append(Theme(
            name: "Electric Blue",
            primaryColor: Color(red: 0.0, green: 0.75, blue: 1.0),
            secondaryColor: .black,
            buttonColor: Color(red: 0.0, green: 0.65, blue: 0.9),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.0, green: 0.75, blue: 1.0), Color(red: 0.0, green: 0.2, blue: 0.5)]), startPoint: .topLeading, endPoint: .bottomTrailing)),
            isAnimated: false,
            buttonShape: .circle,
            buttonSize: .large
        ))
        
        // MARK: - Gradient Collection Themes
        
        themes.append(Theme(
            name: "Cotton Candy",
            primaryColor: .white,
            secondaryColor: Color(red: 0.4, green: 0.2, blue: 0.6),
            buttonColor: Color(red: 1.0, green: 0.6, blue: 0.8),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 1.0, green: 0.8, blue: 0.9), Color(red: 0.6, green: 0.8, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)),
            isAnimated: false,
            buttonShape: .capsule,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Volcano",
            primaryColor: .orange,
            secondaryColor: .white,
            buttonColor: .red,
            background: AnyView(RadialGradient(gradient: Gradient(colors: [Color.yellow, Color.orange, Color.red, Color.black]), center: .center, startRadius: 50, endRadius: 400)),
            isAnimated: false,
            buttonShape: .circle,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Deep Ocean",
            primaryColor: Color(red: 0.0, green: 0.8, blue: 1.0),
            secondaryColor: .white,
            buttonColor: Color(red: 0.0, green: 0.6, blue: 0.8),
            background: AnyView(RadialGradient(gradient: Gradient(colors: [Color(red: 0.0, green: 0.2, blue: 0.4), Color(red: 0.0, green: 0.1, blue: 0.2), Color.black]), center: .bottom, startRadius: 50, endRadius: 500)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Northern Lights",
            primaryColor: .green,
            secondaryColor: .white,
            buttonColor: Color(red: 0.2, green: 0.8, blue: 0.4),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.black, Color(red: 0.0, green: 0.3, blue: 0.2), Color(red: 0.2, green: 0.8, blue: 0.4), Color(red: 0.4, green: 0.0, blue: 0.8), Color.black]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Tropical Sunset",
            primaryColor: .orange,
            secondaryColor: .white,
            buttonColor: Color(red: 1.0, green: 0.3, blue: 0.5),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 1.0, green: 0.4, blue: 0.0), Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 0.8, green: 0.2, blue: 0.8), Color(red: 0.2, green: 0.1, blue: 0.4)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .capsule,
            buttonSize: .medium
        ))
        
        // MARK: - Dark Themes
        
        themes.append(Theme(
            name: "Dark Mode",
            primaryColor: .white,
            secondaryColor: .white,
            buttonColor: Color(red: 0.3, green: 0.3, blue: 0.3),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.1), Color(red: 0.2, green: 0.2, blue: 0.2)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Neon Dark",
            primaryColor: Color(red: 0.0, green: 1.0, blue: 0.5),
            secondaryColor: .black,
            buttonColor: Color(red: 0.0, green: 0.8, blue: 0.4),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.1), Color(red: 0.0, green: 0.2, blue: 0.1)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rectangle,
            buttonSize: .small
        ))
        
        themes.append(Theme(
            name: "Purple Haze",
            primaryColor: Color(red: 0.8, green: 0.4, blue: 1.0),
            secondaryColor: .white,
            buttonColor: Color(red: 0.6, green: 0.2, blue: 0.8),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.1, green: 0.0, blue: 0.2), Color(red: 0.3, green: 0.1, blue: 0.4), Color(red: 0.1, green: 0.0, blue: 0.1)]), startPoint: .topLeading, endPoint: .bottomTrailing)),
            isAnimated: false,
            buttonShape: .circle,
            buttonSize: .large
        ))
        
        // MARK: - Pastel Themes
        
        themes.append(Theme(
            name: "Soft Pink",
            primaryColor: Color(red: 0.9, green: 0.4, blue: 0.6),
            secondaryColor: .white,
            buttonColor: Color(red: 0.8, green: 0.3, blue: 0.5),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 1.0, green: 0.9, blue: 0.95), Color(red: 0.9, green: 0.7, blue: 0.8)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .capsule,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Baby Blue",
            primaryColor: Color(red: 0.4, green: 0.7, blue: 1.0),
            secondaryColor: .white,
            buttonColor: Color(red: 0.3, green: 0.6, blue: 0.9),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.9, green: 0.95, blue: 1.0), Color(red: 0.7, green: 0.85, blue: 1.0)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Peachy",
            primaryColor: Color(red: 1.0, green: 0.6, blue: 0.4),
            secondaryColor: .white,
            buttonColor: Color(red: 0.9, green: 0.5, blue: 0.3),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 1.0, green: 0.95, blue: 0.9), Color(red: 1.0, green: 0.8, blue: 0.6)]), startPoint: .topLeading, endPoint: .bottomTrailing)),
            isAnimated: false,
            buttonShape: .circle,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Sage Green",
            primaryColor: Color(red: 0.5, green: 0.7, blue: 0.5),
            secondaryColor: .white,
            buttonColor: Color(red: 0.4, green: 0.6, blue: 0.4),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.9, green: 0.95, blue: 0.9), Color(red: 0.7, green: 0.8, blue: 0.7)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .small
        ))
        
        // MARK: - Metallic Themes
        
        themes.append(Theme(
            name: "Gold",
            primaryColor: Color(red: 1.0, green: 0.84, blue: 0.0),
            secondaryColor: .black,
            buttonColor: Color(red: 0.9, green: 0.75, blue: 0.0),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.8, green: 0.6, blue: 0.0), Color(red: 0.6, green: 0.4, blue: 0.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)),
            isAnimated: false,
            buttonShape: .circle,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Silver",
            primaryColor: Color(red: 0.75, green: 0.75, blue: 0.75),
            secondaryColor: .black,
            buttonColor: Color(red: 0.6, green: 0.6, blue: 0.6),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.9, green: 0.9, blue: 0.9), Color(red: 0.7, green: 0.7, blue: 0.7), Color(red: 0.5, green: 0.5, blue: 0.5)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .capsule,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Copper",
            primaryColor: Color(red: 0.72, green: 0.45, blue: 0.2),
            secondaryColor: .white,
            buttonColor: Color(red: 0.6, green: 0.35, blue: 0.1),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.85, green: 0.55, blue: 0.25), Color(red: 0.65, green: 0.4, blue: 0.15), Color(red: 0.45, green: 0.25, blue: 0.05)]), startPoint: .topTrailing, endPoint: .bottomLeading)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .large
        ))
        
        // MARK: - Additional Animated Themes
        
        themes.append(Theme(
            name: "Fireflies",
            primaryColor: .yellow,
            secondaryColor: .black,
            buttonColor: Color(red: 1.0, green: 0.8, blue: 0.0),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.0), Color(red: 0.2, green: 0.2, blue: 0.0)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .circle,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Ocean Waves",
            primaryColor: .cyan,
            secondaryColor: .white,
            buttonColor: .blue,
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.0, green: 0.3, blue: 0.6), Color(red: 0.0, green: 0.5, blue: 0.8), Color(red: 0.2, green: 0.7, blue: 1.0)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .capsule,
            buttonSize: .large
        ))
        
        themes.append(Theme(
            name: "Plasma",
            primaryColor: .white,
            secondaryColor: .black,
            buttonColor: Color(red: 1.0, green: 0.0, blue: 0.5),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.8, green: 0.0, blue: 0.4), Color(red: 0.6, green: 0.0, blue: 0.8), Color(red: 0.4, green: 0.0, blue: 1.0)]), startPoint: .topLeading, endPoint: .bottomTrailing)),
            isAnimated: false,
            buttonShape: .rounded,
            buttonSize: .medium
        ))
        
        themes.append(Theme(
            name: "Neural Network",
            primaryColor: Color(red: 0.0, green: 1.0, blue: 0.8),
            secondaryColor: .white,
            buttonColor: Color(red: 0.0, green: 0.8, blue: 0.6),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color.black, Color(red: 0.0, green: 0.2, blue: 0.2), Color(red: 0.0, green: 0.4, blue: 0.4)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .rectangle,
            buttonSize: .small
        ))
        
        themes.append(Theme(
            name: "Bubble Pop",
            primaryColor: Color(red: 0.4, green: 0.8, blue: 1.0),
            secondaryColor: .white,
            buttonColor: Color(red: 0.2, green: 0.6, blue: 0.8),
            background: AnyView(LinearGradient(gradient: Gradient(colors: [Color(red: 0.6, green: 0.9, blue: 1.0), Color(red: 0.4, green: 0.8, blue: 1.0), Color(red: 0.2, green: 0.6, blue: 0.8)]), startPoint: .top, endPoint: .bottom)),
            isAnimated: false,
            buttonShape: .circle,
            buttonSize: .large
        ))
    }
    
    var currentTheme: Theme {
        themes[currentThemeIndex]
    }
}

// MARK: - Animated Backgrounds
struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGVector
    var size: CGFloat
    var color: Color
    var life: CGFloat
}

struct ParticleBackground: View {
    @State private var particles: [Particle] = []
    
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .opacity(particle.life)
                }
            }
            .onAppear {
                // Create initial particles
                for _ in 0..<50 {
                    particles.append(createParticle(in: geometry.size))
                }
            }
            .onReceive(timer) { _ in
                updateParticles(in: geometry.size)
            }
        }
    }
    
    private func createParticle(in size: CGSize) -> Particle {
        Particle(
            position: CGPoint(x: CGFloat.random(in: 0..<size.width),
            y: CGFloat.random(in: 0..<size.height)),
            velocity: CGVector(dx: CGFloat.random(in: -1...1), dy: CGFloat.random(in: -1...1)),
            size: CGFloat.random(in: 2...8),
            color: [Color.blue, Color.purple, Color.cyan, Color.mint].randomElement()!,
            life: CGFloat.random(in: 0.5...1.0)
        )
    }
    
    private func updateParticles(in size: CGSize) {
        for i in 0..<particles.count {
            particles[i].position.x += particles[i].velocity.dx * 2
            particles[i].position.y += particles[i].velocity.dy * 2
            
            // Reset particles that go off screen
            if particles[i].position.x < 0 || particles[i].position.x > size.width ||
               particles[i].position.y < 0 || particles[i].position.y > size.height {
                particles[i] = createParticle(in: size)
            }
            
            // Gradually reduce life and reset when needed
            particles[i].life -= 0.01
            if particles[i].life <= 0 {
                particles[i] = createParticle(in: size)
            }
        }
    }
}

struct CosmicBackground: View {
    var body: some View {
        TimelineView(.animation) { timelineContext in
            let now = timelineContext.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width/2, y: size.height/2)
                let maxRadius = max(size.width, size.height) * 0.6
                
                // Draw stars
                for _ in 0..<200 {
                    let angle = Double.random(in: 0..<Double.pi * 2)
                    let distance = Double.random(in: 0..<maxRadius)
                    let starSize = Double.random(in: 1...3)
                    
                    let x = center.x + CGFloat(cos(angle) * distance)
                    let y = center.y + CGFloat(sin(angle) * distance)
                    
                    let brightness = Double.random(in: 0.5...1.0)
                    let path = Path(ellipseIn: CGRect(x: x, y: y, width: starSize, height: starSize))
                    context.fill(path, with: .color(Color(white: brightness)))
                }
                
                // Draw a subtle galaxy spiral
                for i in 0..<5 {
                    let spiralRadius = maxRadius * 0.3 * Double(i + 1)
                    let spiralPath = Path { path in
                        for j in 0..<360 {
                            let angle = Double(j) * .pi / 180
                            let spiralX = center.x + CGFloat(cos(angle + now)) * spiralRadius * CGFloat(cos(angle * 5))
                            let spiralY = center.y + CGFloat(sin(angle + now)) * spiralRadius * CGFloat(sin(angle * 5))
                            
                            if j == 0 {
                                path.move(to: CGPoint(x: spiralX, y: spiralY))
                            } else {
                                path.addLine(to: CGPoint(x: spiralX, y: spiralY))
                            }
                        }
                    }
                    context.stroke(spiralPath, with: .color(Color.blue.opacity(0.1)), lineWidth: 1)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct RainbowBackground: View {
    @State private var hue: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AngularGradient(gradient: Gradient(colors: [
                    .red, .orange, .yellow, .green, .blue, .purple, .red
                ]), center: .center)
                .hueRotation(.degrees(hue))
                .onAppear {
                    withAnimation(Animation.linear(duration: 10).repeatForever(autoreverses: false)) {
                        hue = 360
                    }
                }
            }
        }
    }
}

struct GalaxyBackground: View {
    var body: some View {
        TimelineView(.animation) { timelineContext in
            let now = timelineContext.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width/2, y: size.height/2)
                let maxRadius = max(size.width, size.height) * 0.6
                
                // Draw stars
                for _ in 0..<300 {
                    let angle = Double.random(in: 0..<Double.pi * 2)
                    let distance = Double.random(in: 0..<maxRadius)
                    let starSize = Double.random(in: 1...3)
                    
                    let x = center.x + CGFloat(cos(angle) * distance)
                    let y = center.y + CGFloat(sin(angle) * distance)
                    
                    let brightness = Double.random(in: 0.5...1.0)
                    let path = Path(ellipseIn: CGRect(x: x, y: y, width: starSize, height: starSize))
                    context.fill(path, with: .color(Color(white: brightness)))
                }
                
                // Draw nebula clouds
                for i in 0..<5 {
                    let cloudRadius = maxRadius * 0.2 * Double(i + 1)
                    let cloudPath = Path { path in
                        for j in 0..<360 {
                            let angle = Double(j) * .pi / 180
                            let cloudX = center.x + CGFloat(cos(angle + now * 0.5)) * cloudRadius * CGFloat(cos(angle * 3))
                            let cloudY = center.y + CGFloat(sin(angle + now * 0.5)) * cloudRadius * CGFloat(sin(angle * 3))
                            
                            if j == 0 {
                                path.move(to: CGPoint(x: cloudX, y: cloudY))
                            } else {
                                path.addLine(to: CGPoint(x: cloudX, y: cloudY))
                            }
                        }
                        path.closeSubpath()
                    }
                    context.fill(cloudPath, with: .color(Color(hue: Double(i)/5.0, saturation: 0.8, brightness: 0.7, opacity: 0.3)))
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct AuroraBackground: View {
    @State private var gradientStart: UnitPoint = .topLeading
    @State private var gradientEnd: UnitPoint = .bottomTrailing
    
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.cyan.opacity(0.8),
                    Color.teal.opacity(0.6),
                    Color.purple.opacity(0.7),
                    Color.blue.opacity(0.5)
                ]),
                startPoint: gradientStart,
                endPoint: gradientEnd
            )
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 15).repeatForever()) {
                    gradientStart = .bottomLeading
                    gradientEnd = .topTrailing
                }
            }
            .mask(
                WaveShape(amplitude: 30, frequency: 50)
                    .opacity(0.7)
            )
        }
    }
}

struct WaveShape: Shape {
    var amplitude: CGFloat
    var frequency: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let height = rect.height
        let width = rect.width
        
        path.move(to: CGPoint(x: 0, y: height))
        
        for x in stride(from: 0, to: width, by: 1) {
            let relativeX = x / width
            let sine = sin(relativeX * frequency * .pi)
            let y = height * 0.5 + amplitude * CGFloat(sine)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        
        return path
    }
}

struct LavaBackground: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            LavaCanvasView(now: timeline.date.timeIntervalSinceReferenceDate, offset: offset)
        }
        .onAppear {
            withAnimation(Animation.linear(duration: 10).repeatForever(autoreverses: true)) {
                offset = 200
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct LavaCanvasView: View {
    var now: TimeInterval
    var offset: CGFloat

    var body: some View {
        Canvas { context, size in
            // Lava base
            var base = Path()
            base.addRect(CGRect(origin: .zero, size: size))
            context.fill(base, with: .color(Color(red: 0.3, green: 0, blue: 0)))

            // Lava bubbles
            for _ in 0..<30 {
                let bubbleSize = CGFloat.random(in: 10...50)
                let x = CGFloat.random(in: 0..<size.width)
                let y = size.height - bubbleSize/2 - CGFloat.random(in: 0..<size.height/2) + offset
                let bubble = Path(ellipseIn: CGRect(x: x, y: y, width: bubbleSize, height: bubbleSize))

                let color = Color(
                    red: Double.random(in: 0.7...1.0),
                    green: Double.random(in: 0.2...0.4),
                    blue: 0.0,
                    opacity: Double.random(in: 0.5...0.8)
                )

                context.fill(bubble, with: .color(color))
            }

            // Lava flow
            let flow = Path { path in
                path.move(to: CGPoint(x: 0, y: size.height))
                for x in stride(from: 0, to: size.width, by: 5) {
                    let y = size.height - 30 - sin(now + Double(x)/30) * 20
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
            }

            context.fill(flow, with: .linearGradient(
                Gradient(colors: [Color.orange, Color.red]),
                startPoint: CGPoint(x: 0, y: size.height - 100),
                endPoint: CGPoint(x: 0, y: size.height)
            ))
        }
    }
}

struct CyberpunkBackground: View {
    @State private var hue: Double = 0
    @State private var gridOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color(red: 0.1, green: 0, blue: 0.3)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Grid pattern
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    let spacing: CGFloat = 40
                    
                    // Vertical lines
                    for x in stride(from: gridOffset, to: width, by: spacing) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                    
                    // Horizontal lines
                    for y in stride(from: gridOffset, to: height, by: spacing) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                .blur(radius: 1)
                
                // Neon elements
                ForEach(0..<10, id: \.self) { _ in
                    let x = CGFloat.random(in: 0..<geometry.size.width)
                    let y = CGFloat.random(in: 0..<geometry.size.height)
                    let size = CGFloat.random(in: 20...100)
                    
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                gradient: Gradient(colors: [.blue, .purple, .pink, .blue]),
                                center: .center
                            ),
                            lineWidth: 2
                        )
                        .frame(width: size, height: size)
                        .position(x: x, y: y)
                        .blur(radius: 4)
                        .opacity(0.7)
                }
            }
            .hueRotation(.degrees(hue))
            .onAppear {
                withAnimation(Animation.linear(duration: 10).repeatForever(autoreverses: false)) {
                    hue = 360
                }
                withAnimation(Animation.linear(duration: 20).repeatForever(autoreverses: false)) {
                    gridOffset = -40
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct StarryNightBackground: View {
    @State private var twinkle: [Bool] = Array(repeating: false, count: 100)
    
    var body: some View {
        TimelineView(.animation) { timeline in
            
            Canvas { context, size in
                let center = CGPoint(x: size.width/2, y: size.height/2)
                let maxRadius = max(size.width, size.height) * 0.6
                
                // Draw stars
                for i in 0..<twinkle.count {
                    let angle = Double.random(in: 0..<Double.pi * 2)
                    let distance = Double.random(in: 0..<maxRadius)
                    let starSize = Double.random(in: 1...3) * (twinkle[i] ? 1.5 : 1)
                    
                    let x = center.x + CGFloat(cos(angle) * distance)
                    let y = center.y + CGFloat(sin(angle) * distance)
                    
                    let brightness = Double.random(in: 0.5...1.0)
                    let path = Path(ellipseIn: CGRect(x: x, y: y, width: starSize, height: starSize))
                    context.fill(path, with: .color(Color(white: brightness)))
                }
                
                // Draw moon
                let moonSize: CGFloat = 80
                let moonPath = Path(ellipseIn: CGRect(
                    x: size.width - moonSize - 30,
                    y: 30,
                    width: moonSize,
                    height: moonSize
                ))
                context.fill(moonPath, with: .color(Color(white: 0.9)))
            }
            .onAppear {
                // Randomly twinkle stars
                for i in 0..<twinkle.count {
                    let delay = Double.random(in: 0..<5)
                    withAnimation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(delay)
                    ) {
                        twinkle[i] = true
                    }
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

struct DigitalRainBackground: View {
    @State private var columns: [[CGFloat]] = []
    @State private var characters: [[Character]] = []
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                // Create digital rain columns
                ForEach(0..<columns.count, id: \.self) { columnIndex in
                    ForEach(0..<columns[columnIndex].count, id: \.self) { charIndex in
                        if charIndex < characters[columnIndex].count {
                            Text(String(characters[columnIndex][charIndex]))
                                .foregroundColor(charIndex == 0 ? .white : .green)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .position(
                                    x: CGFloat(columnIndex) * 20,
                                    y: columns[columnIndex][charIndex]
                                )
                        }
                    }
                }
            }
            .onAppear {
                setupRain(for: geometry.size)
            }
            .onReceive(timer) { _ in
                updateRain(for: geometry.size)
            }
        }
    }
    
    private func setupRain(for size: CGSize) {
        let columnCount = Int(size.width / 20)
        columns = Array(repeating: [], count: columnCount)
        characters = Array(repeating: [], count: columnCount)
        
        for i in 0..<columnCount {
            let charCount = Int.random(in: 5...20)
            var column: [CGFloat] = []
            var chars: [Character] = []
            
            for j in 0..<charCount {
                column.append(CGFloat.random(in: -100...0))
                chars.append(randomCharacter())
            }
            
            columns[i] = column
            characters[i] = chars
        }
    }
    
    private func updateRain(for size: CGSize) {
        for i in 0..<columns.count {
            for j in 0..<columns[i].count {
                // Move character down
                columns[i][j] += 20
                
                // Reset if off screen
                if columns[i][j] > size.height + 100 {
                    columns[i][j] = CGFloat.random(in: -100...0)
                    characters[i][j] = randomCharacter()
                }
            }
        }
    }
    
    private func randomCharacter() -> Character {
        let characters = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!@#$%^&*()_+-=[]{}|;:,.<>?/~`"
        return characters.randomElement()!
    }
}

struct WatercolorBackground: View {
    @State private var blobs: [WatercolorBlob] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                ForEach(blobs) { blob in
                    blob.path
                        .fill(blob.color)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: blob.blur)
                        .opacity(blob.opacity)
                }
            }
            .onAppear {
                createBlobs(for: geometry.size)
                animateBlobs()
            }
        }
    }
    
    private func createBlobs(for size: CGSize) {
        blobs = []
        let colors: [Color] = [
            .blue.opacity(0.3),
            .purple.opacity(0.3),
            .pink.opacity(0.3),
            .teal.opacity(0.3),
            .green.opacity(0.3)
        ]
        
        for _ in 0..<15 {
            let center = CGPoint(
                x: CGFloat.random(in: 0..<size.width),
                y: CGFloat.random(in: 0..<size.height)
            )
            let radius = CGFloat.random(in: 50...200)
            let points = Int.random(in: 5...10)
            let color = colors.randomElement()!
            let blur = CGFloat.random(in: 10...30)
            let opacity = Double.random(in: 0.3...0.7)
            
            blobs.append(WatercolorBlob(
                center: center,
                radius: radius,
                points: points,
                color: color,
                blur: blur,
                opacity: opacity
            ))
        }
    }
    
    private func animateBlobs() {
        for index in blobs.indices {
            withAnimation(
                Animation.easeInOut(duration: Double.random(in: 10...20))
                    .repeatForever()
            ) {
                blobs[index].center.x += CGFloat.random(in: -100...100)
                blobs[index].center.y += CGFloat.random(in: -100...100)
                blobs[index].radius *= CGFloat.random(in: 0.8...1.2)
            }
        }
    }
}

struct WatercolorBlob: Identifiable {
    let id = UUID()
    var center: CGPoint
    var radius: CGFloat
    var points: Int
    let color: Color
    let blur: CGFloat
    let opacity: Double
    
    var path: Path {
        var path = Path()
        let angleIncrement = CGFloat.pi * 2 / CGFloat(points)
        
        path.move(to: CGPoint(
            x: center.x + radius * cos(0),
            y: center.y + radius * sin(0)
        ))
        
        for i in 1..<points {
            let angle = angleIncrement * CGFloat(i)
            let randomRadius = radius * CGFloat.random(in: 0.8...1.2)
            path.addLine(to: CGPoint(
                x: center.x + randomRadius * cos(angle),
                y: center.y + randomRadius * sin(angle)
            ))
        }
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Main App
struct ContentView: View {
    @StateObject private var themeManager: ThemeManager = {
        print("🔄 ContentView: About to create ThemeManager")
        let manager = ThemeManager()
        print("✅ ContentView: ThemeManager created successfully")
        return manager
    }()
    
    // Make these optional/lazy to prevent crashes
    @StateObject private var motionManager = MotionManager()
    @StateObject private var bluetoothController = BluetoothController()
    @StateObject private var multipeerManager = MultipeerManager()
    @State private var showThemes = false
    @State private var showSettings = false
    @State private var leftPressed = false
    @State private var rightPressed = false
    @State private var middlePressed = false
    @State private var lastMovement = Date()
    @State private var buttonOpacity: Double = UserDefaults.standard.double(forKey: "buttonOpacity") != 0 ? UserDefaults.standard.double(forKey: "buttonOpacity") : 0.8
    @State private var buttonScale: Double = UserDefaults.standard.double(forKey: "buttonScale") != 0 ? UserDefaults.standard.double(forKey: "buttonScale") : 1.0
    @State private var buttonHeight: Double = UserDefaults.standard.double(forKey: "buttonHeight") != 0 ? UserDefaults.standard.double(forKey: "buttonHeight") : 70.0
    
    // Keep awake settings
    @State private var keepAwakeEnabled = UserDefaults.standard.bool(forKey: "keepAwakeEnabled")
    @State private var keepAwakeDuration: Double = UserDefaults.standard.double(forKey: "keepAwakeDuration") != 0 ? UserDefaults.standard.double(forKey: "keepAwakeDuration") : 30
    @State private var keepAwakeTimer: Timer?
    @State private var keepAwakeStartTime: Date?
    
    // Connection status visibility
    @State private var showConnectionStatus = true
    @State private var connectionStatusTimer: Timer?
    
    // Status bar visibility
    @State private var showStatusBar = UserDefaults.standard.object(forKey: "showStatusBar") != nil ? UserDefaults.standard.bool(forKey: "showStatusBar") : true
    
    // Computed property to determine overall connection status
    private var isConnected: Bool {
        bluetoothController.isConnected || multipeerManager.connected
    }
    
    private var connectionStatusText: String {
        if bluetoothController.isConnected && multipeerManager.connected {
            return "Connected (BT + WiFi)"
        } else if bluetoothController.isConnected {
            return "Connected (Bluetooth)"
        } else if multipeerManager.connected {
            return "Connected (WiFi)"
        } else if multipeerManager.isAdvertising || multipeerManager.isBrowsing {
            return multipeerManager.connectionStatus
        } else {
            return "Ready to connect"
        }
    }
    
    private func saveStatusBarPreference() {
        UserDefaults.standard.set(showStatusBar, forKey: "showStatusBar")
    }
    
    var body: some View {
        print("🔄 ContentView: Rendering body")
        return ZStack {
            // Background with current theme
            themeManager.currentTheme.background
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Mouse Controls Area at the top
                HStack(spacing: 40) {
                    // Left Button
                    MouseButton(
                        title: "L",
                        isPressed: $leftPressed,
                        onPress: {
                            // Send via Bluetooth if connected
                            if bluetoothController.isConnected {
                                bluetoothController.sendMouseReport(
                                    dx: 0,
                                    dy: 0,
                                    buttons: 0x01 // Left button pressed
                                )
                            }
                            // Send via MultipeerConnectivity if connected
                            if multipeerManager.connected {
                                multipeerManager.sendMouseEvent(button: "left", state: "down")
                            }
                        },
                        onRelease: {
                            // Send via Bluetooth if connected
                            if bluetoothController.isConnected {
                                bluetoothController.sendMouseReport(
                                    dx: 0,
                                    dy: 0,
                                    buttons: 0x00 // Button released
                                )
                            }
                            // Send via MultipeerConnectivity if connected
                            if multipeerManager.connected {
                                multipeerManager.sendMouseEvent(button: "left", state: "up")
                            }
                        },
                        theme: themeManager.currentTheme,
                        buttonOpacity: buttonOpacity,
                        buttonScale: buttonScale,
                        customHeight: CGFloat(buttonHeight)
                    )
                    
                    // Scroll Wheel and Middle Button
                    VStack(spacing: 15) {
                        // Scroll Wheel
                        ScrollWheelView(theme: themeManager.currentTheme) { deltaY in
                            let scrollAmount = deltaY * 5
                            
                            // Send via Bluetooth if connected
                            if bluetoothController.isConnected {
                                let btScrollAmount = Int8(min(max(-127, Int8(scrollAmount)), 127))
                                bluetoothController.sendMouseReport(
                                    dx: 0,
                                    dy: 0,
                                    buttons: 0x00,
                                    wheel: btScrollAmount
                                )
                            }
                            
                            // Send via MultipeerConnectivity if connected
                            if multipeerManager.connected {
                                multipeerManager.sendScroll(dy: scrollAmount)
                            }
                        }
                        .frame(width: 80, height: 35)
                        
                        // Middle Button
                        MouseButton(
                            title: "M",
                            isPressed: $middlePressed,
                            onPress: {
                                // Send via Bluetooth if connected
                                if bluetoothController.isConnected {
                                    bluetoothController.sendMouseReport(
                                        dx: 0,
                                        dy: 0,
                                        buttons: 0x04 // Middle button pressed
                                    )
                                }
                                // Send via MultipeerConnectivity if connected
                                if multipeerManager.connected {
                                    multipeerManager.sendMouseEvent(button: "middle", state: "down")
                                }
                            },
                            onRelease: {
                                // Send via Bluetooth if connected
                                if bluetoothController.isConnected {
                                    bluetoothController.sendMouseReport(
                                        dx: 0,
                                        dy: 0,
                                        buttons: 0x00
                                    )
                                }
                                // Send via MultipeerConnectivity if connected
                                if multipeerManager.connected {
                                    multipeerManager.sendMouseEvent(button: "middle", state: "up")
                                }
                            },
                            theme: themeManager.currentTheme,
                            buttonOpacity: buttonOpacity,
                            buttonScale: buttonScale,
                            customHeight: CGFloat(buttonHeight * 0.8) // Slightly smaller for middle button
                        )
                        .frame(width: 60, height: 40) // Smaller for middle button
                    }
                    
                    // Right Button
                    MouseButton(
                        title: "R",
                        isPressed: $rightPressed,
                        onPress: {
                            // Send via Bluetooth if connected
                            if bluetoothController.isConnected {
                                bluetoothController.sendMouseReport(
                                    dx: 0,
                                    dy: 0,
                                    buttons: 0x02 // Right button pressed
                                )
                            }
                            // Send via MultipeerConnectivity if connected
                            if multipeerManager.connected {
                                multipeerManager.sendMouseEvent(button: "right", state: "down")
                            }
                        },
                        onRelease: {
                            // Send via Bluetooth if connected
                            if bluetoothController.isConnected {
                                bluetoothController.sendMouseReport(
                                    dx: 0,
                                    dy: 0,
                                    buttons: 0x00
                                )
                            }
                            // Send via MultipeerConnectivity if connected
                            if multipeerManager.connected {
                                multipeerManager.sendMouseEvent(button: "right", state: "up")
                            }
                        },
                        theme: themeManager.currentTheme,
                        buttonOpacity: buttonOpacity,
                        buttonScale: buttonScale,
                        customHeight: CGFloat(buttonHeight)
                    )
                }
                .padding(.top, 50) // Top padding for buttons
                
                Spacer()
                
                // Bottom area with status, settings, and swipe prompt
                VStack(spacing: 10) {
                    // Main connection status (disappears after connecting)
                    if showConnectionStatus || !isConnected {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isConnected ? Color.green : Color.yellow)
                                .frame(width: 14, height: 14)
                            
                            Text(connectionStatusText)
                                .font(.callout)
                                .foregroundColor(themeManager.currentTheme.primaryColor)
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(20)
                        .transition(.opacity)
                    }
                    
                    // Secondary connection status (Bluetooth specific)
                    if !bluetoothController.isConnected && !multipeerManager.connected {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 12, height: 12)
                            
                            Text("Tap settings to connect")
                                .font(.caption)
                                .foregroundColor(themeManager.currentTheme.primaryColor.opacity(0.8))
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(15)
                    }
                    
                    // Settings Button
                    HStack(spacing: 20) {
                        // Unified Settings Button
                        Button(action: {
                            withAnimation {
                                showSettings.toggle()
                            }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(themeManager.currentTheme.primaryColor)
                                .padding(12)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        
                        // Keep Awake Toggle
                        Button(action: {
                            toggleKeepAwake()
                        }) {
                            Image(systemName: keepAwakeEnabled ? "eye.fill" : "eye.slash.fill")
                                .font(.title2)
                                .foregroundColor(keepAwakeEnabled ? Color.green : themeManager.currentTheme.primaryColor)
                                .padding(12)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                    }
                    
                    Text("Swipe up for themes")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 8)
                        .opacity(showThemes ? 0 : 1)
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal)
            
            // Theme selection panel
            ThemePanelView(themeManager: themeManager, showThemes: $showThemes)
            
            // Unified Settings Panel
            UnifiedSettingsView(
                showSettings: $showSettings,
                bluetoothController: bluetoothController,
                multipeerManager: multipeerManager,
                buttonOpacity: $buttonOpacity,
                buttonScale: $buttonScale,
                buttonHeight: $buttonHeight,
                keepAwakeEnabled: $keepAwakeEnabled,
                keepAwakeDuration: $keepAwakeDuration,
                onKeepAwakeToggle: toggleKeepAwake,
                showStatusBar: $showStatusBar,
                onToggleStatusBar: saveStatusBarPreference
            )
        }
        .onTapGesture {
            // Toggle connection status visibility when tapping background
            withAnimation {
                showConnectionStatus.toggle()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only respond to upward swipes from bottom
                    if value.startLocation.y > UIScreen.main.bounds.height - 100 {
                        withAnimation {
                            showThemes = true
                        }
                    }
                }
        )
        .onAppear {
            // Load saved theme
            themeManager.currentThemeIndex = UserDefaults.standard.integer(forKey: "selectedTheme")
            
            // Start motion updates
            motionManager.startUpdates { dx, dy in
                if isConnected && Date().timeIntervalSince(self.lastMovement) > 0.008 {
                    // Only send movement if there's significant change
                    let threshold = 0.5 // Minimum movement threshold to match Mac app filtering
                    if abs(dx) > threshold || abs(dy) > threshold {
                        self.lastMovement = Date()
                        
                        // Send via Bluetooth if connected
                        if bluetoothController.isConnected {
                            let scaledDx = Int8(min(max(dx, -127), 127))
                            let scaledDy = Int8(min(max(dy, -127), 127))
                            
                            bluetoothController.sendMouseReport(
                                dx: scaledDx,
                                dy: scaledDy,
                                buttons: 0x00
                            )
                        }
                        
                        // Send via MultipeerConnectivity if connected
                        if multipeerManager.connected {
                            multipeerManager.sendMove(dx: dx, dy: dy)
                        }
                    }
                }
            }
        }
        .onChange(of: isConnected) { connected in
            if connected {
                // Hide connection status 3 seconds after connecting
                connectionStatusTimer?.invalidate()
                connectionStatusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    withAnimation {
                        showConnectionStatus = false
                    }
                }
            } else {
                // Show connection status when disconnected
                connectionStatusTimer?.invalidate()
                withAnimation {
                    showConnectionStatus = true
                }
            }
        }
        .statusBar(hidden: !showStatusBar)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Turn off flashlight when app becomes inactive
            turnOffFlashlightOnExit()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Reapply status bar preference when app returns to foreground
            showStatusBar = UserDefaults.standard.object(forKey: "showStatusBar") != nil ? UserDefaults.standard.bool(forKey: "showStatusBar") : true
        }
    }
    
    // MARK: - Keep Awake Functionality
    private func toggleKeepAwake() {
        keepAwakeEnabled.toggle()
        UserDefaults.standard.set(keepAwakeEnabled, forKey: "keepAwakeEnabled")
        
        if keepAwakeEnabled {
            startKeepAwake()
        } else {
            stopKeepAwake()
        }
    }
    
    private func startKeepAwake() {
        UIApplication.shared.isIdleTimerDisabled = true
        keepAwakeStartTime = Date()
        UserDefaults.standard.set(keepAwakeDuration, forKey: "keepAwakeDuration")
        
        // Set up timer to automatically disable after selected duration
        keepAwakeTimer = Timer.scheduledTimer(withTimeInterval: keepAwakeDuration * 60, repeats: false) { _ in
            stopKeepAwake()
        }
        
        print("🔦 Keep awake enabled for \(keepAwakeDuration) minutes")
    }
    
    private func stopKeepAwake() {
        UIApplication.shared.isIdleTimerDisabled = false
        keepAwakeTimer?.invalidate()
        keepAwakeTimer = nil
        keepAwakeStartTime = nil
        keepAwakeEnabled = false
        
        print("😴 Keep awake disabled")
    }
    
    private func turnOffFlashlightOnExit() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch,
              device.torchMode == .on else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
            print("🔦 Flashlight turned off on app exit")
        } catch {
            print("❌ Failed to turn off flashlight on exit: \(error.localizedDescription)")
        }
    }
}

// MARK: - Scroll Wheel Component
struct ScrollWheelView: View {
    let theme: Theme
    let onScroll: (CGFloat) -> Void
    
    @State private var offset: CGFloat = 0
    @State private var lastTranslation: CGSize = .zero
    
    var body: some View {
        ZStack {
            // Wheel groove
            Capsule()
                .fill(theme.primaryColor.opacity(0.2))
                .frame(width: 80, height: 30)
            
            // Wheel ridge
            Capsule()
                .fill(theme.buttonColor.opacity(0.8))
                .frame(width: 50, height: 15)
                .offset(y: offset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let deltaY = value.translation.height - lastTranslation.height
                    lastTranslation = value.translation
                    
                    // Update scroll position with limits
                    offset = min(max(offset + deltaY, -20), 20)
                    
                    // Send scroll event
                    onScroll(deltaY)
                }
                .onEnded { _ in
                    // Smoothly return to center
                    withAnimation(.spring()) {
                        offset = 0
                    }
                    lastTranslation = .zero
                }
        )
    }
}

// MARK: - Multipeer Manager
class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "mouse-control"
    private var myPeerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    private var isSetup = false
    
    @Published var connected = false
    @Published var connectionStatus = "Searching for Mac..."
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    
    override init() {
        super.init()
        setupConnectivity()
        setupConnectionMaintenance()
    }
    
    private func setupConnectionMaintenance() {
        // Monitor app state changes to maintain connection
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        print("📱 App entering background - maintaining connection")
        // Keep advertising and browsing active
    }
    
    @objc private func appWillEnterForeground() {
        print("📱 App entering foreground - checking connection")
        // Restart services if needed
        if !isAdvertising || !isBrowsing {
            startServices()
        }
    }
    
    func setupConnectivity() {
        print("🔗 Setting up MultipeerConnectivity...")
        
        // Clean up existing connections if any
        cleanup()
        
        myPeerID = MCPeerID(displayName: UIDevice.current.name + "-Mouse")
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .optional)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                              discoveryInfo: ["type": "mouse", "version": "1.0"],
                                              serviceType: serviceType)
        advertiser.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        
        startServices()
        isSetup = true
        print("✅ MultipeerConnectivity setup complete")
        print("📱 Peer ID: \(myPeerID.displayName)")
        print("🔍 Service Type: \(serviceType)")
    }
    
    func startServices() {
        guard !isAdvertising else { 
            print("⚠️ Already advertising, skipping...")
            return 
        }
        
        do {
            advertiser.startAdvertisingPeer()
            isAdvertising = true
            print("📡 Started advertising as \(myPeerID.displayName)")
            
            DispatchQueue.main.async {
                self.connectionStatus = "Advertising as \(self.myPeerID.displayName)"
            }
        } catch {
            print("❌ Failed to start advertising: \(error)")
        }
        
        guard !isBrowsing else { 
            print("⚠️ Already browsing, skipping...")
            return 
        }
        
        do {
            browser.startBrowsingForPeers()
            isBrowsing = true
            print("🔍 Started browsing for peers")
        } catch {
            print("❌ Failed to start browsing: \(error)")
        }
    }
    
    func stopServices() {
        if isAdvertising {
            advertiser.stopAdvertisingPeer()
            isAdvertising = false
            print("🚫 Stopped advertising")
        }
        
        if isBrowsing {
            browser.stopBrowsingForPeers()
            isBrowsing = false
            print("🚫 Stopped browsing")
        }
    }
    
    func cleanup() {
        stopServices()
        session?.disconnect()
        
        DispatchQueue.main.async {
            self.connected = false
            self.connectedPeers.removeAll()
            self.connectionStatus = "Disconnected"
        }
    }
    
    func sendCommand(_ command: String) {
        guard connected, let data = command.data(using: .utf8) else { return }
        
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Send error: \(error.localizedDescription)")
        }
    }
    
    func sendMove(dx: Double, dy: Double) {
        sendCommand("move:\(dx),\(dy)")
    }
    
    func sendMouseEvent(button: String, state: String) {
        sendCommand("\(button):\(state)")
    }
    
    func sendScroll(dy: Double) {
        sendCommand("scroll:\(dy)")
    }
}

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("🔄 Peer \(peerID.displayName) state changed to: \(state.rawValue)")
        
        DispatchQueue.main.async {
            // Update connected peers list
            self.connectedPeers = session.connectedPeers
            self.connected = !session.connectedPeers.isEmpty
            
            switch state {
            case .connected:
                self.connectionStatus = "Connected to \(peerID.displayName)"
                print("✅ Successfully connected to \(peerID.displayName)")
            case .connecting:
                self.connectionStatus = "Connecting to \(peerID.displayName)..."
                print("🔄 Connecting to \(peerID.displayName)...")
            case .notConnected:
                if session.connectedPeers.isEmpty {
                    self.connectionStatus = "Searching for Mac..."
                    print("🔍 Lost connection to \(peerID.displayName), searching for peers...")
                } else {
                    self.connectionStatus = "Connected to \(session.connectedPeers.first?.displayName ?? "Unknown")" 
                }
            @unknown default:
                self.connectionStatus = "Unknown connection state"
                print("⚠️ Unknown connection state for \(peerID.displayName)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle incoming data from Mac (could be used for feedback/acknowledgments)
        if let message = String(data: data, encoding: .utf8) {
            if message == "keepalive" {
                // Respond to keep-alive from Mac
                let response = "keepalive-ack".data(using: .utf8)!
                do {
                    try session.send(response, toPeers: [peerID], with: .reliable)
                } catch {
                    print("⚠️ Failed to send keep-alive response: \(error)")
                }
            } else {
                print("💬 Received message from \(peerID.displayName): \(message)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("🌊 Received stream \(streamName) from \(peerID.displayName)")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print("📦 Started receiving resource \(resourceName) from \(peerID.displayName)")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            print("❌ Error receiving resource \(resourceName): \(error.localizedDescription)")
        } else {
            print("✅ Finished receiving resource \(resourceName) from \(peerID.displayName)")
        }
    }
}

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                   didReceiveInvitationFromPeer peerID: MCPeerID,
                   withContext context: Data?,
                   invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📫 Received invitation from \(peerID.displayName)")
        invitationHandler(true, session)
        print("✅ Accepted invitation from \(peerID.displayName)")
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Failed to start advertising: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isAdvertising = false
            self.connectionStatus = "Failed to start advertising"
        }
    }
}

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("🔍 Found peer: \(peerID.displayName)")
        if let info = info {
            print("📋 Discovery info: \(info)")
            // Check if this is a Mac companion app
            if info["type"] == "mac-receiver" {
                print("✅ Found Mac companion app!")
            }
        }
        
        // Only connect if we're not already connected to this peer
        guard !session.connectedPeers.contains(peerID) else {
            print("⚠️ Already connected to \(peerID.displayName)")
            return
        }
        
        print("📤 Inviting \(peerID.displayName) to session...")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        
        DispatchQueue.main.async {
            self.connectionStatus = "Found \(peerID.displayName), connecting..."
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("📍 Lost peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            // Only update status if we lost our current connection
            if self.connectedPeers.contains(peerID) {
                self.connectionStatus = "Connection lost. Searching..."
                // Don't immediately set connected to false - let session delegate handle it
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Failed to start browsing: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isBrowsing = false
            self.connectionStatus = "Failed to start browsing"
        }
    }
}

// MARK: - Motion Manager
class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private var lastUserAcceleration: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)
    private var smoothedAcceleration: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)
    private let smoothingFactor: Double = 0.1
    
    func startUpdates(handler: @escaping (Double, Double) -> Void) {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion not available")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { motion, error in
            guard let motion = motion else { return }
            
            // Get user acceleration (acceleration due to user movement, not gravity)
            let userAccel = motion.userAcceleration
            
            // Apply smoothing to reduce noise
            self.smoothedAcceleration.x = self.smoothingFactor * userAccel.x + (1 - self.smoothingFactor) * self.smoothedAcceleration.x
            self.smoothedAcceleration.y = self.smoothingFactor * userAccel.y + (1 - self.smoothingFactor) * self.smoothedAcceleration.y
            
            // Use smoothed acceleration for movement
            // X-axis: side-to-side movement (left/right)
            // Y-axis: up-down movement (forward/backward when phone is upright)
            let dx = self.smoothedAcceleration.x
            let dy = -self.smoothedAcceleration.y  // Negative to match typical cursor movement
            
            // Apply sensitivity scaling and threshold
            let sensitivity = 150.0
            let threshold = 0.02  // Minimum acceleration to register movement
            
            let scaledDx = abs(dx) > threshold ? dx * sensitivity : 0
            let scaledDy = abs(dy) > threshold ? dy * sensitivity : 0
            
            handler(scaledDx, scaledDy)
        }
    }
}

// MARK: - Custom UI Components
struct MouseButton: View {
    let title: String
    @Binding var isPressed: Bool
    let action: (() -> Void)?
    let onPress: (() -> Void)?
    let onRelease: (() -> Void)?
    let theme: Theme
    let buttonOpacity: Double
    let buttonScale: Double
    let customHeight: CGFloat?
    
    // Legacy initializer for backwards compatibility
    init(title: String, isPressed: Binding<Bool>, action: @escaping () -> Void, theme: Theme, buttonOpacity: Double, buttonScale: Double, customHeight: CGFloat? = nil) {
        self.title = title
        self._isPressed = isPressed
        self.action = action
        self.onPress = nil
        self.onRelease = nil
        self.theme = theme
        self.buttonOpacity = buttonOpacity
        self.buttonScale = buttonScale
        self.customHeight = customHeight
    }
    
    // New initializer with onPress/onRelease
    init(title: String, isPressed: Binding<Bool>, onPress: @escaping () -> Void, onRelease: @escaping () -> Void, theme: Theme, buttonOpacity: Double, buttonScale: Double, customHeight: CGFloat? = nil) {
        self.title = title
        self._isPressed = isPressed
        self.action = nil
        self.onPress = onPress
        self.onRelease = onRelease
        self.theme = theme
        self.buttonOpacity = buttonOpacity
        self.buttonScale = buttonScale
        self.customHeight = customHeight
    }
    
    var body: some View {
        if let action = action {
            // Legacy button behavior
            Button(action: action) {
                buttonContent
            }
        } else {
            // New press/release behavior
            buttonContent
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isPressed {
                                isPressed = true
                                onPress?()
                            }
                        }
                        .onEnded { _ in
                            isPressed = false
                            onRelease?()
                        }
                )
        }
    }
    
    private var buttonContent: some View {
        Text(title)
            .font(.system(size: buttonFontSize, weight: .bold))
            .foregroundColor(theme.secondaryColor)
            .frame(width: buttonWidth, height: buttonHeight)
            .background(
                ButtonShapeView(shape: theme.buttonShape,
                               fillColor: theme.buttonColor.opacity(buttonOpacity),
                               strokeColor: theme.primaryColor.opacity(0.5))
                    .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
            )
            .scaleEffect(isPressed ? 0.95 * buttonScale : 1.0 * buttonScale)
            .offset(y: isPressed ? 2 : 0)
    }
    
    @ViewBuilder
    private var backgroundShape: some View {
        switch theme.buttonShape {
        case .rectangle:
            Rectangle()
        case .rounded:
            RoundedRectangle(cornerRadius: 8)
        case .circle:
            Circle()
        case .capsule:
            Capsule()
        }
    }
    
    private var buttonWidth: CGFloat {
        switch theme.buttonSize {
        case .small: return 80
        case .medium: return 100
        case .large: return 120
        }
    }
    
    private var buttonHeight: CGFloat {
        // Use the customizable button height if provided, otherwise use theme defaults
        return customHeight ?? {
            switch theme.buttonSize {
            case .small: return 50
            case .medium: return 70
            case .large: return 90
            }
        }()
    }
    
    private var buttonFontSize: CGFloat {
        switch theme.buttonSize {
        case .small: return 18
        case .medium: return 20
        case .large: return 24
        }
    }
}

struct UnifiedSettingsView: View {
    @Binding var showSettings: Bool
    @ObservedObject var bluetoothController: BluetoothController
    @ObservedObject var multipeerManager: MultipeerManager
    @Binding var buttonOpacity: Double
    @Binding var buttonScale: Double
    @Binding var buttonHeight: Double
    @Binding var keepAwakeEnabled: Bool
    @Binding var keepAwakeDuration: Double
    let onKeepAwakeToggle: () -> Void
    @Binding var showStatusBar: Bool
    let onToggleStatusBar: () -> Void
    
    // Flashlight and orientation settings
    @State private var useFlashlight = false
    @State private var lockOrientation = false
    
    @State private var selectedTab = 0
    
    var body: some View {
        if showSettings {
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Settings")
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation {
                                showSettings = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    // Tab Selector
                    HStack(spacing: 0) {
                        ForEach(0..<4) { index in
                            Button(action: { selectedTab = index }) {
                                VStack(spacing: 5) {
                                    Image(systemName: tabIcons[index])
                                        .font(.system(size: 16))
                                    Text(tabTitles[index])
                                        .font(.caption)
                                }
                                .foregroundColor(selectedTab == index ? .blue : .white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedTab == index ? Color.blue.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                    
                    // Content based on selected tab
                    ScrollView {
                        VStack(spacing: 20) {
                            switch selectedTab {
                            case 0:
                                BluetoothSettingsContent(bluetoothController: bluetoothController)
                            case 1:
                                WiFiSettingsContent(multipeerManager: multipeerManager)
                            case 2:
                                ButtonSettingsContent(buttonOpacity: $buttonOpacity, buttonScale: $buttonScale, buttonHeight: $buttonHeight)
                            case 3:
                            PowerSettingsContent(
                                keepAwakeEnabled: $keepAwakeEnabled,
                                keepAwakeDuration: $keepAwakeDuration,
                                onKeepAwakeToggle: onKeepAwakeToggle,
                                showStatusBar: $showStatusBar,
                                onToggleStatusBar: onToggleStatusBar
                            )
                            default:
                                EmptyView()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .frame(maxHeight: 400)
                }
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.gray.opacity(0.8)]),
                                  startPoint: .top,
                                  endPoint: .bottom)
                )
                .clipShape(RoundedCorner(radius: 25, corners: [.topLeft, .topRight]))
                .transition(.move(edge: .bottom))
            }
        }
    }
    
    private let tabTitles = ["Bluetooth", "WiFi", "Buttons", "Power"]
    private let tabIcons = ["antenna.radiowaves.left.and.right", "wifi", "rectangle.roundedtop.fill", "battery.100"]
}
struct BluetoothSettingsContent: View {
    @ObservedObject var bluetoothController: BluetoothController
    
    var body: some View {
        VStack(spacing: 15) {
            // Show any error messages
            if let errorMessage = bluetoothController.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Bluetooth Controls
            if !bluetoothController.initializationComplete {
                Text("Initializing Bluetooth...")
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
            } else if bluetoothController.isBluetoothEnabled {
                if bluetoothController.isAdvertising {
                    Button(action: {
                        bluetoothController.stopAdvertising()
                    }) {
                        Text("Stop Advertising")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                } else {
                    Button(action: {
                        bluetoothController.debugBluetoothState()
                        bluetoothController.startAdvertising()
                    }) {
                        Text("Start Advertising")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .disabled(!bluetoothController.initializationComplete)
                }
                
                Text("Pair with your computer in Bluetooth settings")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                Text("Bluetooth is disabled")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.5))
                    .cornerRadius(8)
            }
        }
    }
}

struct WiFiSettingsContent: View {
    @ObservedObject var multipeerManager: MultipeerManager
    
    var body: some View {
        VStack(spacing: 15) {
            // Connection status
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(multipeerManager.connected ? Color.green : Color.yellow)
                        .frame(width: 14, height: 14)
                    
                    Text(multipeerManager.connectionStatus)
                        .font(.callout)
                        .foregroundColor(.white)
                }
                
                if !multipeerManager.connectedPeers.isEmpty {
                    Text("Connected to: \(multipeerManager.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(10)
            
            // Connection Controls
            Button(action: {
                multipeerManager.setupConnectivity()
            }) {
                Text("Restart Connection")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            
            HStack(spacing: 10) {
                Button(action: {
                    if multipeerManager.isAdvertising {
                        multipeerManager.stopServices()
                    } else {
                        multipeerManager.startServices()
                    }
                }) {
                    Text(multipeerManager.isAdvertising ? "Stop Advertising" : "Start Advertising")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(multipeerManager.isAdvertising ? Color.red : Color.green)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    if multipeerManager.isBrowsing {
                        multipeerManager.stopServices()
                    } else {
                        multipeerManager.startServices()
                    }
                }) {
                    Text(multipeerManager.isBrowsing ? "Stop Browsing" : "Start Browsing")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(multipeerManager.isBrowsing ? Color.red : Color.green)
                        .cornerRadius(8)
                }
            }
            
            Text("Make sure your Mac is on the same network and running the companion app")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }
}

struct ButtonSettingsContent: View {
    @Binding var buttonOpacity: Double
    @Binding var buttonScale: Double
    @Binding var buttonHeight: Double
    
    var body: some View {
        VStack(spacing: 15) {
            // Button Opacity Slider
            VStack(alignment: .leading, spacing: 5) {
                Text("Button Opacity: \(buttonOpacity, specifier: "%.1f")")
                    .foregroundColor(.white)
                Slider(value: $buttonOpacity, in: 0.1...1.0, step: 0.1)
                    .onChange(of: buttonOpacity) { _ in
                        savePreferences()
                    }
                    .accentColor(.blue)
            }
            
            // Button Scale Slider
            VStack(alignment: .leading, spacing: 5) {
                Text("Button Scale: \(buttonScale, specifier: "%.1f")")
                    .foregroundColor(.white)
                Slider(value: $buttonScale, in: 0.5...1.5, step: 0.1)
                    .onChange(of: buttonScale) { _ in
                        savePreferences()
                    }
                    .accentColor(.green)
            }
            
            // Button Height Slider
            VStack(alignment: .leading, spacing: 5) {
                Text("Button Height: \(buttonHeight, specifier: "%.0f")")
                    .foregroundColor(.white)
                Slider(value: $buttonHeight, in: 50.0...120.0, step: 5.0)
                    .onChange(of: buttonHeight) { _ in
                        savePreferences()
                    }
                    .accentColor(.orange)
            }
        }
    }
    
    private func savePreferences() {
        UserDefaults.standard.set(buttonOpacity, forKey: "buttonOpacity")
        UserDefaults.standard.set(buttonScale, forKey: "buttonScale")
        UserDefaults.standard.set(buttonHeight, forKey: "buttonHeight")
    }
}

struct PowerSettingsContent: View {
    @Binding var keepAwakeEnabled: Bool
    @Binding var keepAwakeDuration: Double
    let onKeepAwakeToggle: () -> Void
    
    @State private var useFlashlight = UserDefaults.standard.bool(forKey: "useFlashlight")
    @State private var lockOrientation = UserDefaults.standard.bool(forKey: "lockOrientation")
    @Binding var showStatusBar: Bool
    let onToggleStatusBar: () -> Void

    var body: some View {
        VStack(spacing: 15) {
            // Show/Hide Status Bar Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Status Bar")
                        .foregroundColor(.white)
                        .font(.headline)
                    Text("Toggle to show or hide the status bar")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
                
                Spacer()
                
                Toggle("", isOn: $showStatusBar)
                    .onChange(of: showStatusBar) { _ in
                        onToggleStatusBar()
                    }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(10)
            // Keep Awake Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keep Screen Awake")
                        .foregroundColor(.white)
                        .font(.headline)
                    Text("Prevents device from sleeping")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
                
                Spacer()
                
                Toggle("", isOn: $keepAwakeEnabled)
                    .onChange(of: keepAwakeEnabled) { _ in
                        onKeepAwakeToggle()
                    }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(10)
            
            // Flashlight Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use Flashlight")
                        .foregroundColor(.white)
                        .font(.headline)
                    Text("Turn on LED flashlight")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
                
                Spacer()
                
                Toggle("", isOn: $useFlashlight)
                    .onChange(of: useFlashlight) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "useFlashlight")
                        toggleFlashlight(enabled: newValue)
                    }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(10)
            
            // Orientation Lock Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lock Portrait Mode")
                        .foregroundColor(.white)
                        .font(.headline)
                    Text("Prevent landscape rotation")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
                
                Spacer()
                
                Toggle("", isOn: $lockOrientation)
                    .onChange(of: lockOrientation) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "lockOrientation")
                        setOrientationLock(enabled: newValue)
                    }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            .cornerRadius(10)
            
            // Duration Picker
            if keepAwakeEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep awake duration: \(Int(keepAwakeDuration)) minutes")
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    HStack(spacing: 15) {
                        ForEach([15.0, 30.0, 60.0, 120.0], id: \.self) { duration in
                            Button(action: {
                                keepAwakeDuration = duration
                                UserDefaults.standard.set(duration, forKey: "keepAwakeDuration")
                            }) {
                                Text("\(Int(duration))m")
                                    .foregroundColor(keepAwakeDuration == duration ? .white : .white.opacity(0.7))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(keepAwakeDuration == duration ? Color.blue : Color.gray.opacity(0.3))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(10)
            }
            
            Text("Keep awake will automatically disable after the selected duration")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Flashlight Functions
    private func toggleFlashlight(enabled: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else {
            print("⚠️ Flashlight not available on this device")
            return
        }
        
        do {
            try device.lockForConfiguration()
            if enabled {
                try device.setTorchModeOn(level: 1.0)
                print("🔦 Flashlight turned on")
            } else {
                device.torchMode = .off
                print("🔦 Flashlight turned off")
            }
            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to toggle flashlight: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Orientation Lock Functions
    private func setOrientationLock(enabled: Bool) {
        if enabled {
            // Lock to portrait
            AppDelegate.orientationLock = .portrait
            print("🔒 Locked to portrait mode")
        } else {
            // Allow all orientations
            AppDelegate.orientationLock = .all
            print("🔓 Unlocked orientation")
        }
        
        // Force current orientation if locking
        if enabled {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
    }
}

struct ConnectionSettingsView: View {
    @Binding var showConnectionSettings: Bool
    @ObservedObject var multipeerManager: MultipeerManager
    
    var body: some View {
        if showConnectionSettings {
            VStack {
                Spacer()
                
                VStack(spacing: 20) {
                    Text("WiFi Connection Settings")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    
                    // Connection status
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(multipeerManager.connected ? Color.green : Color.yellow)
                                .frame(width: 14, height: 14)
                            
                            Text(multipeerManager.connectionStatus)
                                .font(.callout)
                                .foregroundColor(.white)
                        }
                        
                        if !multipeerManager.connectedPeers.isEmpty {
                            Text("Connected to: \(multipeerManager.connectedPeers.map { $0.displayName }.joined(separator: ", "))")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(10)
                    
                    // Connection Controls
                    VStack(spacing: 15) {
                        Button(action: {
                            multipeerManager.setupConnectivity()
                        }) {
                            Text("Restart Connection")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                        HStack(spacing: 10) {
                            Button(action: {
                                if multipeerManager.isAdvertising {
                                    multipeerManager.stopServices()
                                } else {
                                    multipeerManager.startServices()
                                }
                            }) {
                                Text(multipeerManager.isAdvertising ? "Stop Advertising" : "Start Advertising")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 8)
                                    .background(multipeerManager.isAdvertising ? Color.red : Color.green)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {
                                if multipeerManager.isBrowsing {
                                    multipeerManager.stopServices()
                                } else {
                                    multipeerManager.startServices()
                                }
                            }) {
                                Text(multipeerManager.isBrowsing ? "Stop Browsing" : "Start Browsing")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 8)
                                    .background(multipeerManager.isBrowsing ? Color.red : Color.green)
                                    .cornerRadius(8)
                            }
                        }
                        
                        VStack(spacing: 8) {
                            Text("Make sure your Mac is on the same network and running the companion app")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Text("⚠️ You need to create a Mac companion app to receive connections")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                    
                    Button(action: {
                        withAnimation {
                            showConnectionSettings = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.gray.opacity(0.8)]),
                                  startPoint: .top,
                                  endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .transition(.move(edge: .bottom))
            }
        }
    }
}

struct ButtonSettingsView: View {
    @Binding var showButtonSettings: Bool
    @Binding var buttonOpacity: Double
    @Binding var buttonScale: Double
    
    var body: some View {
        if showButtonSettings {
            VStack {
                Spacer()
                
                VStack(spacing: 20) {
                    Text("Button Settings")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    
                    VStack(spacing: 15) {
                        // Button Opacity Slider
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Button Opacity: \(buttonOpacity, specifier: "%.1f")")
                                .foregroundColor(.white)
                            Slider(value: $buttonOpacity, in: 0.1...1.0, step: 0.1)
                                .accentColor(.blue)
                        }
                        .padding(.horizontal)
                        
                        // Button Scale Slider
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Button Scale: \(buttonScale, specifier: "%.1f")")
                                .foregroundColor(.white)
                            Slider(value: $buttonScale, in: 0.5...1.5, step: 0.1)
                                .accentColor(.green)
                        }
                        .padding(.horizontal)
                    }
                    
                    Button(action: {
                        withAnimation {
                            showButtonSettings = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color.black, Color.gray.opacity(0.8)]),
                                  startPoint: .top,
                                  endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .transition(.move(edge: .bottom))
            }
        }
    }
}

struct ThemePanelView: View {
    @ObservedObject var themeManager: ThemeManager
    @Binding var showThemes: Bool
    
    var body: some View {
        if showThemes {
            VStack {
                Spacer()
                
                VStack {
                    Text("Customize Your Mouse")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(themeManager.themes) { theme in
                                ThemePreview(theme: theme, isSelected: themeManager.currentTheme.id == theme.id)
                                    .onTapGesture {
                                        withAnimation {
                                            if let index = themeManager.themes.firstIndex(where: { $0.id == theme.id }) {
                                                themeManager.currentThemeIndex = index
                                                UserDefaults.standard.set(index, forKey: "selectedTheme")
                                            }
                                            showThemes = false
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 150)
                    
                    Button(action: {
                        withAnimation {
                            showThemes = false
                        }
                    }) {
                        Image(systemName: "chevron.down")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding()
                    }
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.7)]),
                                  startPoint: .top,
                                  endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .transition(.move(edge: .bottom))
            }
        }
    }
}

struct ThemePreview: View {
    let theme: Theme
    let isSelected: Bool
    
    var body: some View {
        VStack {
            theme.background
                .frame(width: 100, height: 100)
                .cornerRadius(15)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                )
                .overlay(
                    // Mouse preview with realistic layout
                    VStack(spacing: 15) {
                        HStack(spacing: 30) {
                            ButtonPreview(shape: theme.buttonShape, size: theme.buttonSize, color: theme.buttonColor)
                            ButtonPreview(shape: theme.buttonShape, size: theme.buttonSize, color: theme.buttonColor)
                        }
                        
                        // Scroll wheel
                        Capsule()
                            .fill(theme.primaryColor.opacity(0.3))
                            .frame(width: 40, height: 10)
                        
                        // Middle button
                        ButtonPreview(shape: theme.buttonShape, size: .small, color: theme.buttonColor)
                    }
                )
            
            Text(theme.name)
                .font(.caption)
                .foregroundColor(.white)
            .padding()
        }
    }
}

struct ButtonShapeView: View {
    let shape: Theme.ButtonShape
    let fillColor: Color
    let strokeColor: Color
    
    var body: some View {
        Group {
            switch shape {
            case .rectangle:
                Rectangle()
                    .fill(fillColor)
                    .overlay(Rectangle().stroke(strokeColor, lineWidth: 1))
            case .rounded:
                RoundedRectangle(cornerRadius: 8)
                    .fill(fillColor)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(strokeColor, lineWidth: 1))
            case .circle:
                Circle()
                    .fill(fillColor)
                    .overlay(Circle().stroke(strokeColor, lineWidth: 1))
            case .capsule:
                Capsule()
                    .fill(fillColor)
                    .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
            }
        }
    }
}

struct ButtonPreview: View {
    let shape: Theme.ButtonShape
    let size: Theme.ButtonSize
    let color: Color
    
    var body: some View {
        ButtonShapeView(shape: shape, fillColor: color.opacity(0.8), strokeColor: .clear)
            .frame(width: buttonWidth, height: buttonHeight)
    }
    
    private var buttonWidth: CGFloat {
        switch size {
        case .small: return 20
        case .medium: return 25
        case .large: return 30
        }
    }
    
    private var buttonHeight: CGFloat {
        switch size {
        case .small: return 10
        case .medium: return 15
        case .large: return 20
        }
    }
}

// MARK: - Helpers
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - App Delegate for Orientation Control
class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

// MARK: - App Entry
@main
struct MouseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

