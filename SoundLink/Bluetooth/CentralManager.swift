//
//  CentralManager.swift
//  SoundLink (macOS)
//
//  The Mac side: acts as a BLE *central*.
//  Scans for the iPhone's SoundLink service, connects, discovers the
//  characteristics, writes commands, and listens for ack notifications.
//

import CoreBluetooth
import Observation

/// A peripheral found while scanning, for the UI list.
struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
}

enum ConnectionState {
    case idle
    case scanning
    case connecting
    case discovering   // connected, finding service/characteristics
    case ready         // characteristics found, notifications on
    case disconnected
}

@Observable
final class CentralManager: NSObject {
    // MARK: - State shown in the UI

    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var connectionState: ConnectionState = .idle
    private(set) var discoveredDevices: [DiscoveredDevice] = []
    /// Most recent command → ack round-trip time, in milliseconds.
    private(set) var lastRoundTripMs: Double?

    let log = EventLog()

    // MARK: - Core Bluetooth

    @ObservationIgnored private var centralManager: CBCentralManager!
    /// Keep a strong reference, or Core Bluetooth cancels the connection.
    @ObservationIgnored private var connectedPeripheral: CBPeripheral?
    @ObservationIgnored private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var commandCharacteristic: CBCharacteristic?
    @ObservationIgnored private var ackCharacteristic: CBCharacteristic?
    /// Note packets waiting for room in the write-without-response buffer.
      @ObservationIgnored private var pendingPackets: [CommandPacket] = []

    @ObservationIgnored private var roundTrip = RoundTripTracker()
    @ObservationIgnored private var nextSequence: UInt16 = 0

    override init() {
        super.init()
        // TODO: Create the CBCentralManager with self as delegate.
        centralManager = CBCentralManager(delegate: self, queue: nil, options: nil)
    }

    // MARK: - Public API

    func startScanning() {
        // TODO: Scan only for the SoundLink service UUID.
        
        //1. Check if bluetooth is on
        guard centralManager.state == .poweredOn else {
            log.log("Can't scan: Bluetooth is not on", kind: .error)
            return
        }
        
        //Remove any previous devices
        discoveredDevices.removeAll()
        discoveredPeripherals.removeAll()
        
        //Only look for iphones running soundlink
        centralManager.scanForPeripherals(withServices: [SoundLinkUUIDs.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        connectionState = .scanning
        log.log("Scanning for SoundLink Devices...")
    }

    func stopScanning() {
        guard centralManager.isScanning else { return }
        
        centralManager.stopScan()
        
        //Only set to idle if we were just scanning
        if connectionState == .scanning {
            connectionState = .idle
        }
        log.log("Stopped scanning")
    }

    func connect(to deviceID: UUID) {
        //Look up the CBPeripheral and connect.
        
        //1. find the peripheral we saved in didDiscover
        guard let peripheral = discoveredPeripherals[deviceID] else {
            log.log("Can't connect: device not found", kind: .error)
            return
        }
        
        //2. stop scanning, it uses power and slows down connectivity
        stopScanning()
        
        //3. keep a strong ref
        connectedPeripheral = peripheral
        
        //4. ask corebluetooth to connect
        centralManager.connect(peripheral, options: nil)
        
        connectionState = .connecting
        log.log("Connecting to \(peripheral.name ?? "device")...")
    }

    func disconnect() {
        // cancelPeripheralConnection
        guard let connectedPeripheral else { return }
        
        log.log("Disconnecting…")
        centralManager.cancelPeripheralConnection(connectedPeripheral)
        // Cleanup happens in didDisconnectPeripheral, not here
        
    }

    /// Encodes and writes a command to the iPhone (with response).
    func send(_ command: SoundLinkCommand, payload: Data = Data()) {
        // Build a CommandPacket, record the send time, write it.
        guard connectionState == .ready,
              let connectedPeripheral,
              let commandCharacteristic else {
            log.log("Can't send \(command): not connected", kind: .error)
            return
        }
        
        let packet = makePacket(command, payload: payload)
        
        roundTrip.markSent(sequence: packet.sequence)
        connectedPeripheral.writeValue(packet.encode(), for: commandCharacteristic, type:
                .withResponse)
        log.log("Sent \(command) #\(packet.sequence)", kind: .sent)
    }

    // MARK: - Piano

    /// Called by the piano when a key goes down.
    func noteOn(_ note: UInt8, velocity: UInt8) {
        // Build a .noteOn CommandPacket with a NoteEvent payload,
        // then send it with writeFast(_:).
        let event = NoteEvent(note: note, velocity: velocity)
        writeFast(makePacket(.noteOn, payload: event.encode()))
    }

    /// Called by the piano when a key comes up.
    func noteOff(_ note: UInt8) {
        let event = NoteEvent(note: note, velocity: 0)
        writeFast(makePacket(.noteOff, payload: event.encode()))
    }

    /// Stop everything on the iPhone (e.g. a "Panic" button, or before disconnecting).
    func allNotesOff() {
        // Same queue as notes, so it can't arrive before a pending noteOn
        writeFast(makePacket(.allNotesOff))
    }

    // MARK: - Private helpers

    /// Writes a packet with .withoutResponse for low latency (used for notes).
    /// Check peripheral.canSendWriteWithoutResponse first. If it's false, queue the
    /// packet and send it from peripheralIsReady(toSendWriteWithoutResponse:).
    private func writeFast(_ packet: CommandPacket) {
        guard connectionState == .ready else { return }
        
        // Add to the back of the line, then send as much as we can.
        // Always going through the queue keeps notes in order.
        pendingPackets.append(packet)
        flushPendingPackets()
    }
    
    /// Sends queued packets until the buffer is full or the queue is empty.
    private func flushPendingPackets() {
        guard let connectedPeripheral, let commandCharacteristic else { return }
        
        while connectedPeripheral.canSendWriteWithoutResponse, !pendingPackets.isEmpty {
            let packet = pendingPackets.removeFirst()
            roundTrip.markSent(sequence: packet.sequence)
            connectedPeripheral.writeValue(packet.encode(), for: commandCharacteristic,
                                           type: .withoutResponse)
        }
    }


    /// Clears characteristics/peripheral state after a disconnect.
    private func resetConnection() {
        connectedPeripheral = nil
        commandCharacteristic = nil
        ackCharacteristic = nil
        
        roundTrip.reset()
        lastRoundTripMs = nil
        nextSequence = 0
        pendingPackets.removeAll()
    }

    /// Optionally reconnect automatically after an unexpected disconnect.
    private func attemptReconnect(to peripheral: CBPeripheral) {
        guard centralManager.state == .poweredOn else { return }
        
        log.log("Trying to reconnect to \(peripheral.name ?? "device")…")
        connectedPeripheral = peripheral          // strong ref again
        connectionState = .connecting
        centralManager.connect(peripheral, options: nil)
    }
    
    /// Builds a packet with the next sequence number.
    private func makePacket(_ command: SoundLinkCommand, payload: Data = Data()) ->
    CommandPacket {
        let packet = CommandPacket(sequence: nextSequence, command: command, payload:
                                    payload)
        nextSequence &+= 1   // &+= wraps 65535 → 0 instead of crashing
        return packet
    }

}

// MARK: - CBCentralManagerDelegate

extension CentralManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // TODO: Track state. Only scan when .poweredOn.
        bluetoothState = central.state
        log.log("Bluetooth state: \(central.state.displayName)")
        
        if central.state != .poweredOn {
            connectionState = .idle
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        //Save the peripheral and add/update it in discoveredDevices.
        
        //1. Keep a strong ref
        discoveredPeripherals[peripheral.identifier] = peripheral
        
        //2. Grab the advertised name
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Unknown Device"
        
        let device = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        
        //3. update it if we have seen the device before, otherwise add it
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }){
            discoveredDevices[index] = device
        }else{
            discoveredDevices.append(device)
            log.log("Found \(name) (RSSI \(RSSI.intValue))")
        }
        
    }

    //Core Bluetooth calls this when the connection succeeds
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        //Set delegate, discover the SoundLink service.
        
        log.log("Connected to \(peripheral.name ?? "device")")
        
        //1. we want the peripherals' callbacks
        peripheral.delegate = self
        
        //2. find our soundlink service on the iPhone
        connectionState = .discovering
        peripheral.discoverServices([SoundLinkUUIDs.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.log("Failed to connect: \(error?.localizedDescription ?? "unknown error")",
         kind: .error)

        connectedPeripheral = nil
        connectionState = .disconnected
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Log it, reset, and decide whether to reconnect.
        if let error {
            // Something went wrong: out of range, iPhone app closed, etc.
            log.log("Disconnected unexpectedly: \(error.localizedDescription)", kind:
                    .error)
        } else {
            // We called cancelPeripheralConnection ourselves
            log.log("Disconnected")
        }
        
        resetConnection()
        connectionState = .disconnected
        
        if error != nil {
            attemptReconnect(to: peripheral)
        }
    }
}

// MARK: - CBPeripheralDelegate

extension CentralManager: CBPeripheralDelegate {
    //Runs after the discoverServices call in didConnect
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        //Discover the command + ack characteristics.
        
        // 1. Bail out if something went wrong
        if let error {
            log.log("Service discovery failed: \(error.localizedDescription)", kind: .error)
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        //2. find our soundlink service
        guard let service = peripheral.services?.first(where: { $0.uuid == SoundLinkUUIDs.service}) else {
            log.log("SoundLink service not found on device", kind: .error)
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        log.log("Found SoundLink service")
        
        //3. ask for just the two characteristics
        peripheral.discoverCharacteristics([SoundLinkUUIDs.commandCharacteristic, SoundLinkUUIDs.ackCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Store the characteristics, enable notifications on the ack characteristic.
        
        // 1. Bail out if something went wrong
        if let error {
            log.log("Characteristic discovery failed: \(error.localizedDescription)", kind:
                    .error)
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        //2. save the characteristics we carea bout
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case SoundLinkUUIDs.commandCharacteristic:
                commandCharacteristic = characteristic
                log.log("Found command characteristic")
            case SoundLinkUUIDs.ackCharacteristic:
                ackCharacteristic = characteristic
                log.log("Found ack characteristic")
            default:
                break
            }
        }
        
        // 3. We need both, or there's no point staying connected
        guard commandCharacteristic != nil, let ackCharacteristic else {
            log.log("Missing a SoundLink characteristic", kind: .error)
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        // 4. Subscribe to acks (iPhone → Mac)
        peripheral.setNotifyValue(true, for: ackCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        //Notifications on → connection is ready.
        
        //only worry about our ack characterisitics
        guard characteristic.uuid == SoundLinkUUIDs.ackCharacteristic else { return }
        
        if let error {
            log.log("Couldn't subscribe to acks: \(error.localizedDescription)", kind:
                    .error)
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        if characteristic.isNotifying {
            connectionState = .ready
            log.log("Ready: subscribed to acks")
        } else {
            log.log("Ack notifications turned off")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // The write reached the iPhone (or failed).
        if let error {
            log.log("Write failed: \(error.localizedDescription)", kind: .error)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        //Decode an AckPacket and compute round-trip time.
        
        guard characteristic.uuid == SoundLinkUUIDs.ackCharacteristic else { return }

              if let error {
                  log.log("Ack error: \(error.localizedDescription)", kind: .error)
                  return
              }

              // 1. Turn the bytes into an AckPacket
              guard let data = characteristic.value, let ack = AckPacket.decode(data) else {
                  log.log("Received a malformed ack", kind: .error)
                  return
              }

              // 2. Stop the stopwatch for this sequence number
              if let ms = roundTrip.markAcked(sequence: ack.sequence) {
                  lastRoundTripMs = ms
                  log.log("Ack #\(ack.sequence) \(ack.status) in \(String(format: "%.1f", ms))", kind: .received)
              } else {
                  log.log("Ack #\(ack.sequence) \(ack.status) (no matching send)", kind:
          .received)
              }

    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        // The write-without-response queue has room again. Send any queued note packets.
        // Buffer has room again, so send what's waiting
        flushPendingPackets()
    }
}
