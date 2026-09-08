// Checks system-default semantics and stable microphone identity resolution without opening an audio stream.

import AVFoundation
import Foundation

@main
struct InputDeviceCheck {
  static func main() throws {
    let systemDefault = try AudioInputDevice.resolve("")
    precondition(systemDefault == nil)
    let devices = try AudioInputDevice.available()
    precondition(Set(devices.map(\.id)).count == devices.count)
    precondition(devices.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty && $0.deviceID != 0 })
    precondition(devices.allSatisfy { AVCaptureDevice(uniqueID: $0.id) != nil })
    if let device = devices.first {
      let resolved = try AudioInputDevice.resolve(device.id)
      precondition(resolved == device.deviceID)
    }
    do {
      _ = try AudioInputDevice.resolve("Vhrase-missing-device-check")
      preconditionFailure("A missing microphone must not silently resolve to another device.")
    } catch {
      precondition(error.localizedDescription.contains("disconnected"))
    }
    print("input device enumeration and resolution passed (\(devices.count) inputs)")
  }
}
