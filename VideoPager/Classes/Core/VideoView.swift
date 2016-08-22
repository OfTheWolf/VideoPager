//
//  VideoView.swift
//  PlayerPagingCollectionView
//
//  Created by Takuya Okamoto on 2016/08/14.
//  Copyright © 2016 Takuya Okamoto. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import RxSwift

protocol VideoViewDelegate: class {
    func videoView(currentTimeDidChange time: NSTimeInterval)
    func videoView(playbackDidEnd player: Player)
    func videoView(playbackDidFailed player: Player)
    func videoView(bufferingProgressDidChange bufferProgress: Float)// TODO: call
    func videoView(shouldTogglePlayerButtonIconIsPause isPauseIcon: Bool)
    func videoViewDidStartPlayback()
}

/// just play the video.
class VideoView: UIView {
    
    static let sharedPlayer = Player()

    public weak var delegate: VideoViewDelegate!
    public var currentTime: NSTimeInterval { return self.player?.currentTime ?? 0 }
    public var duration: NSTimeInterval { return self.player?.maximumDuration ?? 0 }
    public dynamic var shouldShowIndicator = false// please observe
    private weak var player: Player?
    private var disposeBag = DisposeBag()
    private var pausedByUser = false
    private var isStartedPlayback = false {
        didSet {
            if !oldValue && isStartedPlayback {
                delegate.videoViewDidStartPlayback()
            }
        }
    }
    
    init() {
        super.init(frame: CGRect.zero)
        initialize()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initialize() {
        self.setupObservingCallingAndHeadPhone()
    }
    
    func play(url: NSURL) {
        shouldShowIndicator = true
        isStartedPlayback = false
        // get singletone
        player = self.dynamicType.sharedPlayer
        player!.delegate = self
        // add to this
        player!.view.frame = self.bounds
        self.addSubview(player!.view)
        // play
        player!.setUrl(url)
        player!.playFromBeginning()
    }
    
    func playFromCurrentTime() {
        pausedByUser = false
        player?.playFromCurrentTime()
    }

    func pause() {
        pausedByUser = true
        player?.pause()
    }
    
    func seek(value: Double) {
        let isUnspecifiedDuration = duration >= CMTimeGetSeconds(kCMTimeIndefinite)
        guard !isUnspecifiedDuration else {
            return
        }
        shouldShowIndicator = true
        player?.seekToTime(CMTime(seconds: self.duration * value, preferredTimescale: 1))
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        player?.view.frame = self.bounds
    }
}


extension VideoView: PlayerDelegate {
    
    func playerReady(player: Player) {
    }
    
    func playerPlaybackStateDidChange(player: Player) {
        guard let state = player.playbackState else { return }
        switch state {
        case .Paused:
            break
        case .Playing:
            if let bufferingState = player.bufferingState where bufferingState == .Ready {
                shouldShowIndicator = false
                if !isStartedPlayback {
                    isStartedPlayback = true
                }
            }
        case .Stopped:
            break
        case .Failed:
            shouldShowIndicator = false
            delegate.videoView(playbackDidFailed: player)
        }
    }
    
    func playerBufferingStateDidChange(player: Player) {
        guard let state = player.bufferingState else { return }
        switch state {
        case .Unknown:
            shouldShowIndicator = true
        case .Delayed:
            shouldShowIndicator = true
        case .Ready:
            if !pausedByUser {
                player.playFromCurrentTime()
            }
            shouldShowIndicator = false
            if !isStartedPlayback {
                isStartedPlayback = true
            }
        }
    }
    
    func playerCurrentTimeDidChange(player: Player) {
        delegate.videoView(currentTimeDidChange: player.currentTime)
    }
    
    func playerPlaybackWillStartFromBeginning(player: Player) {
    }
    
    func playerPlaybackDidEnd(player: Player) {
        delegate.videoView(playbackDidEnd: player)
    }
    
    func playerWillComeThroughLoop(player: Player) {
    }
}

// MARK: observe calling and head-phone event
extension VideoView {
    
    func setupObservingCallingAndHeadPhone() {
        
        // When interrupted by calling
        NSNotificationCenter.defaultCenter().rx_notification(AVAudioSessionInterruptionNotification)
            .subscribeOn(MainScheduler.instance)
            .subscribeNext { [weak self] (notification: NSNotification) in
                guard let wself = self else { return }
                let keyNumber = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as! NSNumber
                let type = AVAudioSessionInterruptionType(rawValue: keyNumber.unsignedLongValue)
                if let type = type {
                    if type == .Began {
                        wself.pause()
                        wself.delegate.videoView(shouldTogglePlayerButtonIconIsPause: false)
                    }
                    if type == .Ended {
                        wself.playFromCurrentTime()
                        wself.delegate.videoView(shouldTogglePlayerButtonIconIsPause: true)
                    }
                }
            }
            .addDisposableTo(self.disposeBag)
        
        // When the head-phone is pluged in or out
        NSNotificationCenter.defaultCenter().rx_notification(AVAudioSessionRouteChangeNotification)
            .subscribeOn(MainScheduler.instance)
            .subscribeNext { [weak self] (notification: NSNotification) in
                guard let wself = self else { return }
                let keyNumber = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as! NSNumber
                let type = AVAudioSessionRouteChangeReason(rawValue: keyNumber.unsignedLongValue)
                if let type = type {
                    if case .OldDeviceUnavailable = type {
                        wself.pause()
                        wself.delegate.videoView(shouldTogglePlayerButtonIconIsPause: false)
                    }
                }
            }
            .addDisposableTo(self.disposeBag)
    }
}