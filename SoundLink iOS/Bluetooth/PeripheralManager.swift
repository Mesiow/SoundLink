//
//  PeripheralManager.swift
//  SoundLink iOS
//
//  The iPhone side: acts as a BLE *peripheral*.
//  Publishes the SoundLink service, advertises it, receives command writes,
//  and sends acks back to the Mac through notifications.
//

import CoreBluetooth
import Observation

@Observable
final class PeripheralManager: NSObject {
    // MARK: - State shown in the UI

    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var isAdvertising = false
    /// True once the Mac subscribes to the ack characteristic.
    private(set) var isCentralSubscribed = false

    let log = EventLog()

    // MARK: - Core Bluetooth

    @ObservationIgnored private var peripheralManager: CBPeripheralManager!
    @ObservationIgnored private var commandCharacteristic: CBMutableCharacteristic?
    @ObservationIgnored private var ackCharacteristic: CBMutableCharacteristic?
    @ObservationIgnored private var pendingAcks: [Data] = []

    /// Called when a valid command arrives. The app wires this up to the audio player.
    @ObservationIgnored var onCommand: ((CommandPacket) -> AckStatus)?

    override init() {
        super.init()
        //Create the CBPeripheralManager with self as delegate.
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
    }

    // MARK: - Public API

    func startAdvertising() {
        // Advertise the service UUID and local name.
        
        //1. Only advertise when bluetooth is on
        guard peripheralManager.state == .poweredOn else {
            log.log("Cannot advertise, Bluetooth is \(peripheralManager.state.displayName)", kind: .error)
            return
        }
        
        //2. Only start advertising if it isnt already
        guard !peripheralManager.isAdvertising else { return }
        
        //3. Create the advertisement packet
        let advertisementData : [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [SoundLinkUUIDs.service],
            CBAdvertisementDataLocalNameKey: SoundLinkUUIDs.advertisedName
        ]
        
        //4. request the system to start, the response comes back in the delegate callback
        peripheralManager.startAdvertising(advertisementData)
        log.log("Requested Advertising...")
    }

    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
        log.log("Stopped Advertising")
    }

    // MARK: - Private helpers

    /// Builds the service + characteristics and adds them to the peripheral manager.
    /// Only call this once the state is .poweredOn.
    private func setupService() {
        //Create CBMutableCharacteristics (write / notify) and a CBMutableService.
        
        //1. Command characterisitic: the MAC writes commands here
        let command = CBMutableCharacteristic(
            type: SoundLinkUUIDs.commandCharacteristic,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        
        //2. Ack characteristic: the iPhone NOTIFIES the Mac through this
        let ack = CBMutableCharacteristic(
            type: SoundLinkUUIDs.ackCharacteristic,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        
        //3. Group them into the service
        let service = CBMutableService(type: SoundLinkUUIDs.service, primary: true)
        service.characteristics = [command, ack]
        
        //4. Keep references to both characteristics
        commandCharacteristic = command
        ackCharacteristic = ack
        
        //5. Add service, the result arrives in peripheralManager(_:didAdd:error)
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
        log.log("Adding SoundLink service...")
    }

    /// Sends an ack to the subscribed Mac via updateValue(_:for:onSubscribedCentrals:).
    private func sendAck(_ ack: AckPacket) {
        // Handle the case where updateValue returns false (queue is full).
        guard isCentralSubscribed else {
            log.log("Ack #\(ack.sequence) dropped, no subscriber", kind: .error)
            return
        }
        
    }
    
    //Send queued acks in order until the queue is empty or iOS says it's full
    private func flushPendingAcks(){
        guard let ackCharacteristic else {
            return
        }
        
        while let data = pendingAcks.first {
            let sent = peripheralManager.updateValue(data, for: ackCharacteristic, onSubscribedCentrals: nil)
            guard sent else {
                log.log("Transmit queue full, will retry", kind: .info)
                return //wait for peripheralManagerIsReady
            }
            pendingAcks.removeFirst()
            log.log("Ack sent (\(data.count) bytes", kind: .sent)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension PeripheralManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        // Track state. When .poweredOn, set up the service.
        bluetoothState = peripheral.state
        log.log("Bluetooth state: \(peripheral.state.displayName)")
        if bluetoothState == .poweredOn {
            setupService()
        }else {
            //Off/reset
            isAdvertising = false
            isCentralSubscribed = false
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        // Start advertising once the service is added.
        if let error {
            log.log("Failed to add service: \(error.localizedDescription)", kind: .error)
            return
        }
        log.log("Service added")
        startAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            log.log("Advertising Failed: \(error.localizedDescription)", kind: .error)
            isAdvertising = false
            return
        }
        isAdvertising = true
        log.log("Advertising \(SoundLinkUUIDs.advertisedName)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        // The Mac is now listening for acks.
        isCentralSubscribed = true
        log.log("Mac subscribed (max update \(central.maximumUpdateValueLength) bytes)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        // Usually means the Mac disconnected.
        isCentralSubscribed = false
        pendingAcks.removeAll()
        log.log("Mac unsubscribed")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Decode each request's value into a CommandPacket, run onCommand,
        // respond to the request, then send an ack.
        guard let first = requests.first else { return }
        
        //1. validate all requests first, if any are bad, reject all
        for request in requests {
            guard request.characteristic.uuid == SoundLinkUUIDs.commandCharacteristic else {
                peripheral.respond(to: first, withResult: .writeNotPermitted)
                return
            }
            guard request.offset == 0 else {
                peripheral.respond(to: first, withResult: .invalidOffset)
                return
            }
        }
        
        //2. Complete the Mac's write. Exactly once, using the first request
        peripheral.respond(to: first, withResult: .success)
        
        //3. Handle each command and acknowledge it.
        for request in requests {
            let data = request.value ?? Data()
            log.log("Received \(data.count) bytes: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))", kind: .received)
            
            guard let packet = CommandPacket.decode(data) else {
                //Still acknowledge, so the Mac isn't left waiting on this sequence
                let bytes = [UInt8](data)
                let sequence = bytes.count >= 2 ? UInt16(bytes[0]) | (UInt16(bytes[1]) << 8) : 0
                let status: AckStatus = bytes.count >= 3 ? .unknownCommand : .malformedPacket
                log.log("Bad packet #\(sequence): \(status)", kind: .error)
                
                sendAck(AckPacket(sequence: sequence, status: status))
                continue
            }
            
            log.log("Command #\(packet.sequence): \(packet.command)", kind: .received)
            let status = onCommand?(packet) ?? .ok
            sendAck(AckPacket(sequence: packet.sequence, status: status))
      }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Retry any acks that failed to send earlier.
        flushPendingAcks()
    }
}
