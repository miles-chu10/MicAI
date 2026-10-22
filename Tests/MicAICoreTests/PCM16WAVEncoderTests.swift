import Foundation
import MicAICore
import Testing

@Suite
struct PCM16WAVEncoderTests {
  @Test
  func writesMonoPCM16HeaderAndClipsSamples() throws {
    let data = try PCM16WAVEncoder.encode(
      samples: [-2, -1, -0.5, 0, 0.5, 1, 2, .nan]
    )

    #expect(String(decoding: data[0..<4], as: UTF8.self) == "RIFF")
    #expect(readUInt32(data, offset: 4) == UInt32(data.count - 8))
    #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
    #expect(readUInt16(data, offset: 20) == 1)
    #expect(readUInt16(data, offset: 22) == 1)
    #expect(readUInt32(data, offset: 24) == 16_000)
    #expect(readUInt32(data, offset: 28) == 32_000)
    #expect(readUInt16(data, offset: 34) == 16)
    #expect(String(decoding: data[36..<40], as: UTF8.self) == "data")
    #expect(readUInt32(data, offset: 40) == 16)
    #expect(
      (0..<8).map { readInt16(data, offset: 44 + $0 * 2) }
        == [.min, .min, -16_384, 0, 16_384, .max, .max, 0]
    )
  }

  @Test
  func rejectsUnsupportedSampleRate() {
    #expect(throws: MicAIError.audioUnavailable) {
      try PCM16WAVEncoder.encode(samples: [0], sampleRate: 44_100)
    }
  }

  @Test
  func enforcesSafeTwentyFiveMegabyteUploadLimitWithoutAllocatingAudio() throws {
    #expect(
      try PCM16WAVEncoder.encodedByteCount(
        sampleCount: PCM16WAVEncoder.maximumSampleCount
      ) <= PCM16WAVEncoder.maxUploadBytes
    )
    #expect(throws: MicAIError.audioUploadTooLarge) {
      try PCM16WAVEncoder.encodedByteCount(
        sampleCount: PCM16WAVEncoder.maximumSampleCount + 1
      )
    }
  }

  private func readUInt16(_ data: Data, offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
  }

  private func readUInt32(_ data: Data, offset: Int) -> UInt32 {
    UInt32(data[offset])
      | UInt32(data[offset + 1]) << 8
      | UInt32(data[offset + 2]) << 16
      | UInt32(data[offset + 3]) << 24
  }

  private func readInt16(_ data: Data, offset: Int) -> Int16 {
    Int16(bitPattern: readUInt16(data, offset: offset))
  }
}
