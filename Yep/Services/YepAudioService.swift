//
//  YepAudioService.swift
//  Yep
//
//  Created by kevinzhow on 15/3/31.
//  Copyright (c) 2015年 Catch Inc. All rights reserved.
//

import UIKit
import AVFoundation
import AudioToolbox
import Proposer

class YepAudioService: NSObject {
    
    static let sharedManager = YepAudioService()
    
    var shouldIgnoreStart = false
    
    let queue = dispatch_queue_create("YepAudioService", DISPATCH_QUEUE_SERIAL)

    var audioFileURL: NSURL?
    
    var audioRecorder: AVAudioRecorder?
    
    var audioPlayer: AVAudioPlayer?

    func prepareAudioRecorderWithFileURL(fileURL: NSURL, audioRecorderDelegate: AVAudioRecorderDelegate) {

        audioFileURL = fileURL

        let settings: [String: AnyObject] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVEncoderAudioQualityKey : AVAudioQuality.Max.rawValue,
            AVEncoderBitRateKey : 64000,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey : 44100.0
        ]
        
        do {
            let audioRecorder = try AVAudioRecorder(URL: fileURL, settings: settings)
            audioRecorder.delegate = audioRecorderDelegate
            audioRecorder.meteringEnabled = true
            audioRecorder.prepareToRecord() // creates/overwrites the file at soundFileURL

            self.audioRecorder = audioRecorder

        } catch let error {
            self.audioRecorder = nil
            println("create AVAudioRecorder error: \(error)")
        }
    }

    var recordTimeoutAction: (() -> Void)?

    var checkRecordTimeoutTimer: NSTimer?

    func startCheckRecordTimeoutTimer() {

        let timer = NSTimer.scheduledTimerWithTimeInterval(1.0, target: self, selector: "checkRecordTimeout:", userInfo: nil, repeats: true)

        checkRecordTimeoutTimer = timer

        timer.fire()
    }

    func checkRecordTimeout(timer: NSTimer) {
        
        if audioRecorder?.currentTime > YepConfig.AudioRecord.longestDuration {

            endRecord()

            recordTimeoutAction?()
            recordTimeoutAction = nil
        }
    }

    func beginRecordWithFileURL(fileURL: NSURL, audioRecorderDelegate: AVAudioRecorderDelegate) {

        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryRecord)
        } catch let error {
            println("beginRecordWithFileURL setCategory failed: \(error)")
        }

        //dispatch_async(queue) {
        do {
            //AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord, withOptions: AVAudioSessionCategoryOptions.DefaultToSpeaker,error: nil)
            //AVAudioSession.sharedInstance().setActive(true, error: nil)

            proposeToAccess(.Microphone, agreed: {
                
                self.prepareAudioRecorderWithFileURL(fileURL, audioRecorderDelegate: audioRecorderDelegate)
                
                if let audioRecorder = self.audioRecorder {
                    
                    if (audioRecorder.recording){
                        audioRecorder.stop()
                        
                    } else {
                        if !self.shouldIgnoreStart {
                            audioRecorder.record()
                            println("audio record did begin")
                        }
                    }
                }
                
            }, rejected: {
                if let
                    appDelegate = UIApplication.sharedApplication().delegate as? AppDelegate,
                    viewController = appDelegate.window?.rootViewController {
                        viewController.alertCanNotAccessMicrophone()
                }
            })
        }
    }
    
    func endRecord() {
        
        if let audioRecorder = self.audioRecorder {
            if audioRecorder.recording {
                audioRecorder.stop()
            }
        }

        dispatch_async(queue) {
            //AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord, withOptions: AVAudioSessionCategoryOptions.DefaultToSpeaker,error: nil)
            let _ = try? AVAudioSession.sharedInstance().setActive(false, withOptions: AVAudioSessionSetActiveOptions.NotifyOthersOnDeactivation)
        }

        self.checkRecordTimeoutTimer?.invalidate()
        self.checkRecordTimeoutTimer = nil
    }

    // MARK: Audio Player

    var playingMessage: Message?
    var playingFeedAudio: FeedAudio?

    var playbackTimer: NSTimer? {
        didSet {
            if let oldPlaybackTimer = oldValue {
                oldPlaybackTimer.invalidate()
            }
        }
    }

    func playAudioWithMessage(message: Message, beginFromTime time: NSTimeInterval, delegate: AVAudioPlayerDelegate, success: () -> Void) {

        if AVAudioSession.sharedInstance().category == AVAudioSessionCategoryRecord {
            do {
                try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            } catch let error {
                println("playAudioWithMessage setCategory failed: \(error)")
            }
        }

        let fileName = message.localAttachmentName

        if !fileName.isEmpty {
            
            if let fileURL = NSFileManager.yepMessageAudioURLWithName(fileName) {

                do {
                    let audioPlayer = try AVAudioPlayer(contentsOfURL: fileURL)
                    self.audioPlayer = audioPlayer
                    audioPlayer.delegate = delegate
                    audioPlayer.prepareToPlay()

                    audioPlayer.currentTime = time

                    if audioPlayer.play() {
                        println("do play audio")

                        playingMessage = message

                        UIDevice.currentDevice().proximityMonitoringEnabled = true

                        if !message.mediaPlayed {
                            if let realm = message.realm {
                                let _ = try? realm.write {
                                    message.mediaPlayed = true
                                }
                            }
                        }

                        success()
                    }

                } catch let error {
                    println("play audio error: \(error)")
                }
            }

        } else {
            println("please wait for download") // TODO: Download audio message, check first
        }
    }

    func playAudioWithFeedAudio(feedAudio: FeedAudio, beginFromTime time: NSTimeInterval, delegate: AVAudioPlayerDelegate, success: () -> Void) {

        if AVAudioSession.sharedInstance().category == AVAudioSessionCategoryRecord {
            do {
                try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            } catch let error {
                println("playAudioWithMessage setCategory failed: \(error)")
            }
        }

        let fileName = feedAudio.fileName

        if !fileName.isEmpty {

            if let fileURL = NSFileManager.yepMessageAudioURLWithName(fileName) {

                do {
                    let audioPlayer = try AVAudioPlayer(contentsOfURL: fileURL)
                    self.audioPlayer = audioPlayer
                    audioPlayer.delegate = delegate
                    audioPlayer.prepareToPlay()

                    audioPlayer.currentTime = time

                    if audioPlayer.play() {
                        println("do play audio")

                        playingFeedAudio = feedAudio

                        success()
                    }

                } catch let error {
                    println("play audio error: \(error)")
                }
            }
            
        } else {
            println("please wait for download") // TODO: Download feed audio, check first
        }
    }

    func resetToDefault() {
        // playback 会导致从音乐 App 进来的时候停止音乐，所以需要重置回去
        
        dispatch_async(queue) {
            let _ = try? AVAudioSession.sharedInstance().setActive(false, withOptions: AVAudioSessionSetActiveOptions.NotifyOthersOnDeactivation)
        }
    }

    // MARK: Proximity

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    override init() {
        super.init()

        NSNotificationCenter.defaultCenter().addObserver(self, selector: "proximityStateChanged", name: UIDeviceProximityStateDidChangeNotification, object: UIDevice.currentDevice())
    }

    func proximityStateChanged() {

        if UIDevice.currentDevice().proximityState {
            do {
                try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord)
            } catch let error {
                println("proximityStateChanged setCategory failed: \(error)")
            }

        } else {
            do {
                try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            } catch let error {
                println("proximityStateChanged setCategory failed: \(error)")
            }
        }
    }
}

