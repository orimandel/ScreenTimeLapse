import AVFoundation
import ScreenCaptureKit
import UserNotifications

/// Represents an object interactable with a ``RecorderViewModel``
protocol Recordable : CustomStringConvertible {
    var metaData: OutputInfo {get set}
    var state: RecordingState {get set}
    var enabled: Bool {get set}
    
    var writer: AVAssetWriter? {get set}
    var input: AVAssetWriterInput? {get set}
    
    var timeMultiple: Double {get set}
    var offset: CMTime {get set}
    var frameCount: Int {get set}
    
    var lastAppenedFrame: CMTime {get set}
    var tmpFrameBuffer: CMSampleBuffer? {get set}
    var frameRate: CMTimeScale {get}
    
    // MARK: -Intents
    mutating func startRecording()
    mutating func stopRecording()
    mutating func resumeRecording()
    mutating func pauseRecording()
    mutating func saveRecording()
    
    func getFilename() -> String
}

extension Recordable{    
    var frameRate: CMTimeScale {
        guard let writer = writer else {return .zero}
        return CMTimeScale(30.0)
    }
    
    /// Starts recording if ``enabled``
    mutating func startRecording() {
        guard self.enabled else { return }
        guard self.state != .recording else { return }
        
        logger.log("This should not run")
        
        self.state = .recording
    }
    
    /// Stops recording if ``enabled``
    mutating func stopRecording() {
        guard self.enabled else { return }
        
        self.state = .stopped
        saveRecording()
    }
    
    mutating func resumeRecording(){
        self.state = .recording
    }
    
    mutating func pauseRecording() {
        self.state = .paused
    }
    
    mutating func saveRecording() {
        logger.log("Saving recorder")
    }
    
    func getFileDestination(path: String) -> URL {
        var url = URL(filePath: path, directoryHint: .notDirectory, relativeTo: .temporaryDirectory)
       
        if let location = UserDefaults.standard.url(forKey: "saveLocation"),
           FileManager.default.fileExists(atPath: location.path),
           FileManager.default.isWritableFile(atPath: location.path)
        {
            url = URL(filePath: path, directoryHint: .notDirectory, relativeTo: location)
        } else {
            logger.error("No camera save location present")
        }
        
         do { // delete old video
            try FileManager.default.removeItem(at: url)
        } catch { print("Failed to delete file \(error.localizedDescription)")}

        return url
    }
    
    /// Sends a notification using `UserNotifications` framework
    /// Exists on `Recordable` because this can be modifyied is an **iOS** application is in the future
    func sendNotification(title: String, body: String, url: URL?){
        guard UserDefaults.standard.bool(forKey: "showNotifications") else {return}
        
        let center = UNUserNotificationCenter.current()
    
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        
        if let url = url {
            content.userInfo = ["fileURL": url.absoluteString]
        }
        
        content.sound = .default // .defaultCritical
       
        let request = UNNotificationRequest(identifier: "recordingStatusNotifications", content: content, trigger: nil)
        
        center.add(request) { error in
            if let error = error {
                logger.log("Failed to send notification with error \(error)")
            }
        }
    }
    
    /// Appends a buffer depending on a couple of factors
    /// The `tmpFrameBuffer` is used to keep track of deletable buffers
    /// Saves **30%** of space at only **2x** speed. Austensibly much higher for higher time multiples
    func appendBuffer(buffer: CMSampleBuffer) -> (CMSampleBuffer, CMTime){
        guard let input = input else { return (buffer, lastAppenedFrame) }
        
        
        print(writer?.overallDurationHint)
        
        // Determines if we should append
        let currentPTS = buffer.presentationTimeStamp
        
        let differenceTime =  CMTimeMultiplyByFloat64(CMTime(seconds: 1.0 / 30, preferredTimescale: 30), multiplier: timeMultiple)
        
        guard currentPTS > lastAppenedFrame + differenceTime else {
            // okay to replace the tmp buffer
            return (buffer, lastAppenedFrame)
        }
                
        guard let newBuffer = try? tmpFrameBuffer?.offsettingTiming(by: offset, multiplier: 1.0 / timeMultiple) else {
            return (buffer, lastAppenedFrame)
        }
        
        guard input.append(newBuffer) else {
            logger.error("failed to append data")
            return (buffer, lastAppenedFrame)
        }
        
        if let tmpFrameBuffer = tmpFrameBuffer{
            return (buffer, tmpFrameBuffer.presentationTimeStamp)
        } else {
            // Initial condition
            return (buffer, buffer.presentationTimeStamp)
        }

    }
    
    /// Returns a `String` representation of the current date, used by both `Camera` and `Screen`
    ///  The intention is for this to be utiized
    var dateExtension : String {
        let currentDate = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let formattedDate = formatter.string(from: currentDate)
        
        return formattedDate
    }
    
    
    /// Returns a valid file extension for recording formats
    var fileExtension : String {
        var fileType : AVFileType = baseConfig.validFormats.first!
        if let fileTypeValue = UserDefaults.standard.object(forKey: "format"),
           let preferenceType = fileTypeValue as? AVFileType{
            fileType = preferenceType
        }
        
        return baseConfig.convertFormatToString(fileType)
    }
    
    /// Returns the length of the recording
    var time : CMTime {
        guard let tmpFrameBuffer = tmpFrameBuffer else { return CMTime.zero }
        
        return CMTimeMultiplyByFloat64((tmpFrameBuffer.presentationTimeStamp - offset), multiplier: 1 / timeMultiple)        
    }
}

extension CMSampleBuffer {
    /// Allows timing offsets
    func offsettingTiming(by offset: CMTime, multiplier: Float64) throws -> CMSampleBuffer {
        let newSampleTimingInfos: [CMSampleTimingInfo]
        
        do {
            newSampleTimingInfos = try sampleTimingInfos().map {
                var newSampleTiming = $0
                newSampleTiming.presentationTimeStamp = offset + CMTimeMultiplyByFloat64($0.presentationTimeStamp - offset, multiplier: multiplier)
                return newSampleTiming
            }
        } catch {
            newSampleTimingInfos = []
        }
        let newSampleBuffer = try CMSampleBuffer(copying: self, withNewTiming: newSampleTimingInfos)
        return newSampleBuffer
    }
}

extension URL {
    /// Returns whether or not the url is in the `URL.temporaryDirectory`
    func isInTemporaryFolder() -> Bool {
        return self.absoluteString.starts(with: URL.temporaryDirectory.absoluteString)
    }
}
