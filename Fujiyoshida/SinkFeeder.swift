import CoreMedia
import CoreMediaIO

final class SinkFeeder {
    private var deviceID: CMIOObjectID = 0
    private var streamID: CMIOStreamID = 0
    private var queue: CMSimpleQueue?

    var isConnected: Bool { queue != nil }

    func connect() -> Bool {
        if queue != nil { return true }
        guard let device = Self.findDevice(uid: FujiyoshidaConfig.deviceUID),
              let stream = Self.sinkStream(of: device) else { return false }

        var unmanagedQueue: Unmanaged<CMSimpleQueue>?
        let status = CMIOStreamCopyBufferQueue(stream, { _, _, _ in }, nil, &unmanagedQueue)
        guard status == noErr, let bufferQueue = unmanagedQueue?.takeRetainedValue() else { return false }
        guard CMIODeviceStartStream(device, stream) == noErr else { return false }

        deviceID = device
        streamID = stream
        queue = bufferQueue
        return true
    }

    func disconnect() {
        guard queue != nil else { return }
        CMIODeviceStopStream(deviceID, streamID)
        queue = nil
    }

    func isViewerActive() -> Bool {
        guard queue != nil else { return false }
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(FujiyoshidaConfig.viewerPropertySelector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        guard CMIOObjectHasProperty(deviceID, &address) else { return true }
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(deviceID, &address, 0, nil, size, &used, &value) == noErr,
              let text = value?.takeRetainedValue() else { return true }
        return (text as String) == "1"
    }

    func send(_ pixelBuffer: CVPixelBuffer) {
        guard let queue, CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return }

        var format: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
        guard let format else { return }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: FujiyoshidaConfig.frameRate),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return }
        CMSimpleQueueEnqueue(queue, element: Unmanaged.passRetained(sampleBuffer).toOpaque())
    }

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private static func objectIDs(of object: CMIOObjectID, selector: Int) -> [CMIOObjectID] {
        var address = address(selector)
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, dataSize, &used, &ids) == noErr else { return [] }
        return ids
    }

    private static func findDevice(uid: String) -> CMIOObjectID? {
        objectIDs(of: CMIOObjectID(kCMIOObjectSystemObject), selector: kCMIOHardwarePropertyDevices).first { device in
            var address = address(kCMIODevicePropertyDeviceUID)
            var value: Unmanaged<CFString>?
            var used: UInt32 = 0
            let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &value) == noErr,
                  let deviceUID = value?.takeRetainedValue() else { return false }
            return (deviceUID as String) == uid
        }
    }

    private static func sinkStream(of device: CMIOObjectID) -> CMIOStreamID? {
        let streams = objectIDs(of: device, selector: kCMIODevicePropertyStreams)
        let sink = streams.first { stream in
            var address = address(kCMIOStreamPropertyDirection)
            var direction: UInt32 = 1
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(stream, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &direction)
            return status == noErr && direction == 0
        }
        return sink ?? (streams.count > 1 ? streams.last : nil)
    }
}
