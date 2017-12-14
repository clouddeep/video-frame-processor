//
//  VideoConverter.swift
//  AVMedia Frame Picker
//
//  Created by Tuan Shou Cheng on 2017/12/9.
//  Copyright © 2017年 Tuan Shou Cheng. All rights reserved.
//

import UIKit
import AVKit
import Photos

class VideoConverter: NSObject {
    
    typealias CompletionBlock = (_ completion: Bool, _ newAsset: AVAsset?, _ error: Error?) -> Void
    var completionBlock: CompletionBlock
    
    typealias FrameProcessBlock = (_ sampleBuffer: CMSampleBuffer) -> Void
    var frameProcess: FrameProcessBlock?
    
    var outputURL: URL? = URL(fileURLWithPath: NSTemporaryDirectory() + "out.mov")
    var asset: AVAsset?
    var photoAsset: PHAsset?
    
    enum ProcessState {
        case idle
        case processing
        case cancelled
        case finished
    }
    var processState: ProcessState = .idle
    
    enum Result {
        case success
        case cancellation
        case failure(Error)
    }
    
    var executing: Bool {
        return result == nil
    }
    
    var finished: Bool {
        return result != nil
    }
    
    var result: Result? {
        willSet {
            willChangeValue(forKey: "isExecuting")
            willChangeValue(forKey: "isFinished")
        }
        didSet {
            didChangeValue(forKey: "isExecuting")
            didChangeValue(forKey: "isFinished")
        }
    }
    
    private var sampleTransferError: Error?//ErrorType?
    
    
    
    private typealias ReaderOutputAndWriterInput = (
        readerOutput: AVAssetReaderOutput,
        writerInput: AVAssetWriterInput
    )
    
    init(asset: PHAsset, completion: @escaping CompletionBlock) {
        self.photoAsset = asset
        self.completionBlock = completion

        super.init()
    }
    
    func startLoadAsset() {
        PHImageManager.default().requestAVAsset(
            forVideo: photoAsset!,
            options: nil) { [weak self] (asset, audioMix, info) in
                
                self?.asset = asset
                
                if let vAsset = asset {
                    vAsset.loadValuesAsynchronously(forKeys: ["tracks"], completionHandler: {
                        
                        let assetReader: AVAssetReader
                        let assetWriter: AVAssetWriter
                        let videoReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput]
                        let passthroughReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput]
                        
                        do {
                            // Check the completion of loading
                            var trackLoadingError: NSError?
                            guard vAsset.statusOfValue(forKey: "tracks", error: &trackLoadingError) == .loaded else {
                                throw trackLoadingError!
                            }
                            
                            // Get tracks
                            let tracks = vAsset.tracks
                            
                            // Create reader/writer objects.
                            assetReader = try AVAssetReader(asset: vAsset)
                            assetWriter = try AVAssetWriter(outputURL: (self?.outputURL)!, fileType: .mov)
                            
                            // Make reader output from tracks
                            let (videoReaderOutputs, passthroughReaderOutputs) = (self?.makeReaderOutputsForTracks(
                                tracks: tracks,
                                availableMediaTypes: assetWriter.availableMediaTypes))!
                            
                            // Make corresponded writer inputs
                            videoReaderOutputsAndWriterInputs = (try self?.makeVideoWriterInputsForVideoReaderOutputs(
                                videoReaderOutputs: videoReaderOutputs))!
                            
                            passthroughReaderOutputsAndWriterInputs = (try self?.makePassthroughWriterInputsForPassthroughReaderOutputs(
                                passthroughReaderOutputs: passthroughReaderOutputs))!
                            
                            // Hook everything up.
                            
                            for (readerOutput, writerInput) in videoReaderOutputsAndWriterInputs {
                                assetReader.add(readerOutput)
                                assetWriter.add(writerInput)
                            }
                            
                            for (readerOutput, writerInput) in passthroughReaderOutputsAndWriterInputs {
                                assetReader.add(readerOutput)
                                assetWriter.add(writerInput)
                            }
                            
                            /*
                             Remove file if necessary. AVAssetWriter will not overwrite
                             an existing file.
                             */
                            
                            self?.removeFileIfNecessary()
                            
                            
                            // Start reading/writing.
                            
                            guard assetReader.startReading() else {
                                // `error` is non-nil when startReading returns false.
                                throw assetReader.error!
                            }
                            
                            guard assetWriter.startWriting() else {
                                // `error` is non-nil when startWriting returns false.
                                throw assetWriter.error!
                            }
                            
                            assetWriter.startSession(atSourceTime: kCMTimeZero)
                            
                        } catch {
                            self?.finish(.failure(error))
                            print(error)
                            return
                        }
                        
                        let writingGroup = DispatchGroup()
                        
                        // Transfer data from input file to output file.
                        self?.transferVideoTracks(
                            videoReaderOutputsAndWriterInputs: videoReaderOutputsAndWriterInputs,
                            group: writingGroup)
                        
                        self?.transferPassthroughTracks(
                            passthroughReaderOutputsAndWriterInputs: passthroughReaderOutputsAndWriterInputs,
                            group: writingGroup)
                        
                        // Handle completion.
                        let queue = DispatchQueue.global(qos: .default)
                        
                        let item = DispatchWorkItem(block: {
                            // `readingAndWritingDidFinish()` is guaranteed to call `finish()` exactly once.
                            self?.readingAndWritingDidFinish(
                                assetReader: assetReader,
                                assetWriter: assetWriter)
                        })
                        writingGroup.notify(queue: queue, work: item)
                    })
                }
        }
    }
    /*
     func generateImage() {
     PHImageManager.default().requestAVAsset(forVideo: videoAsset, options: nil) { [weak self] (avAsset, audioMix, info) in
     if let asset = avAsset {
     let item = AVPlayerItem(asset: asset)
     let player = AVPlayer(playerItem: item)
     
     self?.playerViewController.player = player
     
     let imageGenerator = AVAssetImageGenerator(asset: asset)
     imageGenerator.appliesPreferredTrackTransform = true
     
     do {
     var time = asset.duration
     time.value = min(time.value, 2)
     let imageRef = try imageGenerator.copyCGImage(at: time, actualTime: nil)
     let image = UIImage(cgImage: imageRef)
     
     } catch {
     print("Image generation failed with error")
     }
     }
     }
     }*/
}

extension VideoConverter {
    
    private func makeReaderOutputsForTracks(
        tracks: [AVAssetTrack],
        availableMediaTypes: [AVMediaType])
        -> (
        videoReaderOutputs: [AVAssetReaderTrackOutput],
        passthroughReaderOutputs: [AVAssetReaderTrackOutput]
        )
    {
        // Decompress source video to 32ARGB.
        let videoDecompressionSettings: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value: kCVPixelFormatType_32ARGB),
            String(kCVPixelBufferIOSurfacePropertiesKey): [:]
        ]
        
        // Partition tracks into "video" and "passthrough" buckets, create reader outputs.
        
        var videoReaderOutputs       = [AVAssetReaderTrackOutput]()
        var passthroughReaderOutputs = [AVAssetReaderTrackOutput]()
        
        for track in tracks {
            guard availableMediaTypes.contains(track.mediaType) else { continue }
            
            switch track.mediaType {
            case .video:
                let videoReaderOutput = AVAssetReaderTrackOutput(
                    track: track,
                    outputSettings: videoDecompressionSettings)
                videoReaderOutputs += [videoReaderOutput]
                
            default:
                // `nil` output settings means "passthrough."
                // Note: To read the media data from a specific asset track in the format in which it was stored, pass nil to the outputSettings parameter.
                let passthroughReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                passthroughReaderOutputs += [passthroughReaderOutput]
            }
        }
        
        return (videoReaderOutputs, passthroughReaderOutputs)
    }
    
    private func makeVideoWriterInputsForVideoReaderOutputs(videoReaderOutputs: [AVAssetReaderTrackOutput]) throws -> [ReaderOutputAndWriterInput] {
        // Compress modified source frames to H.264.
        let videoCompressionSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264
        ]
        
        /*
         In order to find the source format we need to create a temporary asset
         reader, plus a temporary track output for each "real" track output.
         We will only read as many samples (typically just one) as necessary
         to discover the format of the buffers that will be read from each "real"
         track output.
         */
        
        let tempAssetReader = try AVAssetReader(asset: asset!)
        
        let videoReaderOutputsAndTempVideoReaderOutputs: [(videoReaderOutput: AVAssetReaderTrackOutput, tempVideoReaderOutput: AVAssetReaderTrackOutput)] = videoReaderOutputs.map {
            videoReaderOutput in
            
            let tempVideoReaderOutput = AVAssetReaderTrackOutput(
                track: videoReaderOutput.track,
                outputSettings: videoReaderOutput.outputSettings)
            
            tempAssetReader.add(tempVideoReaderOutput)
            
            return (videoReaderOutput, tempVideoReaderOutput)
        }
        
        // Start reading.
        
        guard tempAssetReader.startReading() else {
            // 'error' will be non-nil if startReading fails.
            throw tempAssetReader.error!
        }
        
        /*
         Create video asset writer inputs, using the source format hints read
         from the "temporary" reader outputs.
         */
        
        var videoReaderOutputsAndWriterInputs =
            [ReaderOutputAndWriterInput]()
        
        for (videoReaderOutput, tempVideoReaderOutput) in videoReaderOutputsAndTempVideoReaderOutputs
        {
            // Fetch format of source sample buffers.
            
            var videoFormatHint: CMFormatDescription?
            
            while videoFormatHint == nil
            {
                guard let sampleBuffer = tempVideoReaderOutput.copyNextSampleBuffer() else {
                    // We ran out of sample buffers before we found one with a format description
                    throw CyanifyError.NoMediaData
                }
                
                videoFormatHint = CMSampleBufferGetFormatDescription(sampleBuffer)
            }
            
            // Create asset writer input.
            
            let videoWriterInput = AVAssetWriterInput(
                mediaType:        AVMediaType.video,
                outputSettings:   videoCompressionSettings,
                sourceFormatHint: videoFormatHint)
            
            videoReaderOutputsAndWriterInputs.append(
                (readerOutput: videoReaderOutput,
                 writerInput:  videoWriterInput)
            )
        }
        
        // Shut down processing pipelines, since only a subset of the samples were read.
        tempAssetReader.cancelReading()
        
        return videoReaderOutputsAndWriterInputs
    }
    
    private func makePassthroughWriterInputsForPassthroughReaderOutputs(passthroughReaderOutputs: [AVAssetReaderTrackOutput]) throws -> [ReaderOutputAndWriterInput] {
        /*
         Create passthrough writer inputs, using the source track's format
         descriptions as the format hint for each writer input.
         */
        
        var passthroughReaderOutputsAndWriterInputs = [ReaderOutputAndWriterInput]()
        
        for passthroughReaderOutput in passthroughReaderOutputs {
            /*
             For passthrough, we can simply ask the track for its format
             description and use that as the writer input's format hint.
             */
            let trackFormatDescriptions = passthroughReaderOutput.track.formatDescriptions as! [CMFormatDescription]
            
            guard let passthroughFormatHint = trackFormatDescriptions.first else {
                throw CyanifyError.NoMediaData
            }
            
            // Create asset writer input with nil (passthrough) output settings
            let passthroughWriterInput = AVAssetWriterInput(
                mediaType: AVMediaType(passthroughReaderOutput.mediaType),
                outputSettings: nil,
                sourceFormatHint: passthroughFormatHint)
            
            passthroughReaderOutputsAndWriterInputs.append(
                (readerOutput: passthroughReaderOutput,
                 writerInput: passthroughWriterInput)
            )
        }
        
        return passthroughReaderOutputsAndWriterInputs
    }
    
    private func transferVideoTracks(
        videoReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput],
        group: DispatchGroup)
    {
        for (videoReaderOutput, videoWriterInput) in videoReaderOutputsAndWriterInputs
        {
            let perTrackDispatchQueue = DispatchQueue(label: "Track data transfer queue: \(videoReaderOutput) -> \(videoWriterInput).")
            //            let perTrackDispatchQueue = dispatch_queue_create("Track data transfer queue: \(videoReaderOutput) -> \(videoWriterInput).", nil)
            
            // A block for changing color values of each video frame.
            let videoProcessor: (CMSampleBuffer) throws -> Void = { sampleBuffer in
                
                if let sampleProcess = self.frameProcess {
                    sampleProcess(sampleBuffer)
                }
                
            }
            group.enter()
            
            transferSamplesAsynchronouslyFromReaderOutput(
                readerOutput:          videoReaderOutput,
                toWriterInput:         videoWriterInput,
                onQueue:               perTrackDispatchQueue,
                sampleBufferProcessor: videoProcessor
            ) { group.leave() }
        }
    }
    
    private func transferPassthroughTracks(
        passthroughReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput],
        group: DispatchGroup)
    {
        for (passthroughReaderOutput, passthroughWriterInput) in passthroughReaderOutputsAndWriterInputs {
            let perTrackDispatchQueue = DispatchQueue(label: "Track data transfer queue: \(passthroughReaderOutput) -> \(passthroughWriterInput).")
            //            let perTrackDispatchQueue = dispatch_queue_create("Track data transfer queue: \(passthroughReaderOutput) -> \(passthroughWriterInput).", nil)
            
            group.enter()
            
            transferSamplesAsynchronouslyFromReaderOutput(
                readerOutput: passthroughReaderOutput,
                toWriterInput: passthroughWriterInput,
                onQueue: perTrackDispatchQueue
            ) { group.leave() }
        }
    }
    
    private func transferSamplesAsynchronouslyFromReaderOutput(
        readerOutput: AVAssetReaderOutput,
        toWriterInput writerInput: AVAssetWriterInput,
        onQueue queue: DispatchQueue,
        sampleBufferProcessor: ((_ sampleBuffer: CMSampleBuffer) throws -> Void)? = nil, completionHandler: @escaping () -> Void) {
        
        // Provide the asset writer input with a block to invoke whenever it wants to request more samples
        
        writerInput.requestMediaDataWhenReady(on: queue) {
            var isDone = false
            
            /*
             Loop, transferring one sample per iteration, until the asset writer
             input has enough samples. At that point, exit the callback block
             and the asset writer input will invoke the block again when it
             needs more samples.
             */
            while writerInput.isReadyForMoreMediaData {
                guard self.processState != .cancelled else {
                    isDone = true
                    break
                }
                
                // Grab next sample from the asset reader output.
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                    /*
                     At this point, the asset reader output has no more samples
                     to vend.
                     */
                    isDone = true
                    break
                }
                
                // Process the sample, if requested.
                do {
                    try sampleBufferProcessor?(sampleBuffer)
                }
                catch {
                    // This error will be picked back up in `readingAndWritingDidFinish()`.
                    //                    FrameProcessError.sampleTransferError = error
                    self.sampleTransferError = error
                    isDone = true
                }
                
                // Append the sample to the asset writer input.
                guard writerInput.append(sampleBuffer) else {
                    /*
                     The sample buffer could not be appended. Error information
                     will be fetched from the asset writer in
                     `readingAndWritingDidFinish()`.
                     */
                    isDone = true
                    break
                }
            }
            
            if isDone {
                /*
                 Calling `markAsFinished()` on the asset writer input will both:
                 1. Unblock any other inputs that need more samples.
                 2. Cancel further invocations of this "request media data"
                 callback block.
                 */
                writerInput.markAsFinished()
                
                // Tell the caller that we are done transferring samples.
                completionHandler()
            }
        }
    }
    
    private func readingAndWritingDidFinish(assetReader: AVAssetReader, assetWriter: AVAssetWriter) {
        if self.processState == .cancelled {
            assetReader.cancelReading()
            assetWriter.cancelWriting()
        }
        
        // Deal with any error that occurred during processing of the video.
        guard sampleTransferError == nil else {
            assetReader.cancelReading()
            assetWriter.cancelWriting()
            //            finish(.Failure(sampleTransferError!))
            return
        }
        
        // Evaluate result of reading samples.
        
        guard assetReader.status == .completed else {
            let result: Result
            
            switch assetReader.status {
            case .cancelled:
                assetWriter.cancelWriting()
                result = .cancellation
                
            case .failed:
                // `error` property is non-nil in the `.Failed` status.
                result = .failure(assetReader.error!)
                
            default:
                fatalError("Unexpected terminal asset reader status: \(assetReader.status).")
            }
            
            finish(result)
            
            return
        }
        
        // Finish writing, (asynchronously) evaluate result of writing samples.
        
        assetWriter.finishWriting {
            let result: Result
            
            switch assetWriter.status {
            case .completed:
                result = .success
                
            case .cancelled:
                result = .cancellation
                
            case .failed:
                // `error` property is non-nil in the `.Failed` status.
                result = .failure(assetWriter.error!)
                
            default:
                fatalError("Unexpected terminal asset writer status: \(assetWriter.status).")
            }
            
            self.finish(result)
        }
    }
    
    func finish(_ result: Result) {
        self.result = result
        
        switch result {
        case .success:
            if let url = self.outputURL {
                let asset = AVAsset(url: url)
                completionBlock(true, asset, nil)
            } else {
                completionBlock(false, nil, nil)
            }
            
        default:
            completionBlock(false, nil, nil)
        }
    }
    
    func removeFileIfNecessary() {
        let fileManager = FileManager.default
        if let outputPath = self.outputURL?.path, fileManager.fileExists(atPath: outputPath) {
            do {
                try fileManager.removeItem(atPath: outputPath)
            } catch let error {
                print("delete file fails \(error)")
            }
        }
    }
}
