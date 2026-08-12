import Foundation

public enum PCM16WAVEncoder {
  public static let requiredSampleRate = 16_000
  public static let headerSize = 44
  public static let maxUploadBytes = 25_000_000
  public static let maximumSampleCount =
    (maxUploadBytes - headerSize) / MemoryLayout<Int16>.size

  public static func encodedByteCount(sampleCount: Int) throws -> Int {
    guard sampleCount >= 0, sampleCount <= maximumSampleCount else {
      throw MicAIError.audioUploadTooLarge
    }
    return headerSize + sampleCount * MemoryLayout<Int16>.size
  }

  public static func encode(
    samples: [Float],
    sampleRate: Int = requiredSampleRate
  ) throws -> Data {
    guard sampleRate == requiredSampleRate else {
      throw MicAIError.audioUnavailable
    }
    let encodedByteCount = try encodedByteCount(sampleCount: samples.count)
    let payloadSize = samples.count * MemoryLayout<Int16>.size
    var data = Data()
    data.reserveCapacity(encodedByteCount)
    data.append(contentsOf: "RIFF".utf8)
    append(UInt32(36 + payloadSize), to: &data)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    append(UInt32(16), to: &data)
    append(UInt16(1), to: &data)
    append(UInt16(1), to: &data)
    append(UInt32(sampleRate), to: &data)
    append(UInt32(sampleRate * MemoryLayout<Int16>.size), to: &data)
    append(UInt16(MemoryLayout<Int16>.size), to: &data)
    append(UInt16(16), to: &data)
    data.append(contentsOf: "data".utf8)
    append(UInt32(payloadSize), to: &data)

    for sample in samples {
      let normalized = sample.isFinite ? sample : 0
      let value: Int16
      if normalized <= -1 {
        value = .min
      } else if normalized >= 1 {
        value = .max
      } else {
        value = Int16((normalized * Float(Int16.max)).rounded())
      }
      append(value, to: &data)
    }
    return data
  }

  private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { bytes in
      data.append(contentsOf: bytes)
    }
  }
}
