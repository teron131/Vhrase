// Enumerates macOS microphone devices and resolves stable saved identities without changing system-wide audio defaults.

import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Sendable {
  let id: String
  let name: String
  let deviceID: AudioDeviceID

  /// Lists physical microphone inputs, excluding output-only, virtual, and temporary aggregate devices.
  static func available() throws -> [AudioInputDevice] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    try check(
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size))
    var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard !devices.isEmpty else { return [] }
    try check(
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices))
    return try devices.compactMap { deviceID in
      var transportAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
      var transport: UInt32 = 0
      var transportSize = UInt32(MemoryLayout<UInt32>.size)
      guard
        AudioObjectGetPropertyData(deviceID, &transportAddress, 0, nil, &transportSize, &transport)
          == noErr,
        transport != kAudioDeviceTransportTypeVirtual,
        transport != kAudioDeviceTransportTypeAggregate
      else { return nil }
      var streams = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)
      var streamBytes: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(deviceID, &streams, 0, nil, &streamBytes) == noErr,
        streamBytes > 0
      else { return nil }
      return AudioInputDevice(
        id: try stringProperty(kAudioDevicePropertyDeviceUID, device: deviceID),
        name: try stringProperty(kAudioObjectPropertyName, device: deviceID), deviceID: deviceID)
    }
  }

  /// A missing explicit choice is an error rather than silently recording from another microphone.
  static func resolve(_ uid: String) throws -> AudioDeviceID? {
    guard !uid.isEmpty else { return nil }
    guard let device = try available().first(where: { $0.id == uid }) else {
      throw InputDeviceError.unavailable
    }
    return device.deviceID
  }

  private static func stringProperty(_ selector: AudioObjectPropertySelector, device: AudioDeviceID)
    throws -> String
  {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value))
    guard let value else { throw InputDeviceError.system(kAudioHardwareUnspecifiedError) }
    return value.takeRetainedValue() as String
  }

  private static func check(_ status: OSStatus) throws {
    guard status == noErr else { throw InputDeviceError.system(status) }
  }
}

private enum InputDeviceError: LocalizedError {
  case unavailable
  case system(OSStatus)

  var errorDescription: String? {
    switch self {
    case .unavailable:
      "The selected microphone is disconnected. Choose another input device or System default."
    case .system(let status): "Could not read microphone devices (macOS error \(status))."
    }
  }
}
