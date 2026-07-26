import AVFoundation
import Combine

class CaptureManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let processingQueue = DispatchQueue(label: "capture.processing")
    private let sessionQueue = DispatchQueue(label: "capture.session")
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var isSessionRunning = false

    @Published var latestFrame: CMSampleBuffer?
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var availableMicrophones: [AVCaptureDevice] = []
    @Published var isRunning = false

    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    weak var recordingAudioWriterInput: AVAssetWriterInput?
    var recordingStartHostTime: CMTime?

    override init() {
        super.init()
        refreshDeviceList()
    }

    func refreshDeviceList() {
        let cameraTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .external,
        ]
        #if os(macOS)
        let micTypes: [AVCaptureDevice.DeviceType] = [
            .builtInMicrophone,
            .external,
        ]
        #else
        let micTypes: [AVCaptureDevice.DeviceType] = [
            .builtInMicrophone,
        ]
        #endif
        availableCameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: cameraTypes, mediaType: .video, position: .unspecified
        ).devices
        availableMicrophones = AVCaptureDevice.DiscoverySession(
            deviceTypes: micTypes, mediaType: .audio, position: .unspecified
        ).devices
    }

    func start(camera: AVCaptureDevice?, microphone: AVCaptureDevice?) {
        guard !isSessionRunning else { return }

        let cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if !cameraGranted || !micGranted {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .medium

            for i in self.session.inputs { self.session.removeInput(i) }
            for o in self.session.outputs { self.session.removeOutput(o) }

            if let cam = camera, let input = try? AVCaptureDeviceInput(device: cam) {
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoInput = input
                }
            }
            if let mic = microphone, let input = try? AVCaptureDeviceInput(device: mic) {
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.audioInput = input
                }
            }

            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            if self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
            }

            self.session.commitConfiguration()

            self.videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
            self.audioOutput.setSampleBufferDelegate(self, queue: self.processingQueue)

            self.session.startRunning()
            self.isSessionRunning = true
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.stopRunning()
            self.isSessionRunning = false
            DispatchQueue.main.async {
                self.isRunning = false
                self.latestFrame = nil
            }
        }
        videoInput = nil
        audioInput = nil
    }

    func updateVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        videoOutput.connection(with: .video)?.videoOrientation = orientation
    }
}

extension CaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                          AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === videoOutput {
            latestFrame = sampleBuffer
        } else if output === audioOutput {
            guard let writerInput = recordingAudioWriterInput,
                  writerInput.isReadyForMoreMediaData,
                  let startTime = recordingStartHostTime else { return }
            let rawPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let adjustedPTS = CMTimeSubtract(rawPTS, startTime)
            guard CMTimeCompare(adjustedPTS, .zero) >= 0 else { return }
            var adjusted: CMSampleBuffer?
            let timing = CMSampleTimingInfo(
                duration: CMSampleBufferGetDuration(sampleBuffer),
                presentationTimeStamp: adjustedPTS,
                decodeTimeStamp: .invalid
            )
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: 1,
                sampleTimingArray: [timing],
                sampleBufferOut: &adjusted
            )
            if let buf = adjusted { writerInput.append(buf) }
        }
    }
}
