//
//  UIChatBubbleSoundCell.m
//  linphone
//
//  Created by David Idmansour on 02/07/2018.
//

#import "UIChatBubbleSoundCell.h"
#import "LinphoneManager.h"
#import "PhoneMainView.h"

#import <AssetsLibrary/ALAsset.h>
#import <AssetsLibrary/ALAssetRepresentation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVKit/AVKit.h>

@implementation UIChatBubbleSoundCell {
    ChatConversationTableView *chatTableView;
}

#pragma mark - Lifecycle Functions

- (id)initWithIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier]) != nil) {
        NSArray *arrayOfViews =
        [[NSBundle mainBundle] loadNibNamed:NSStringFromClass(self.class) owner:self options:nil];
        // resize cell to match .nib size. It is needed when resized the cell to
        // correctly adapt its height too
        UIView *sub = nil;
        for (int i = 0; i < arrayOfViews.count; i++) {
            if ([arrayOfViews[i] isKindOfClass:UIView.class]) {
                sub = arrayOfViews[i];
                break;
            }
        }
        [self addSubview:sub];
        chatTableView = VIEW(ChatConversationView).tableController;
        _player = linphone_core_create_local_player(LC, NULL, NULL, NULL);
        _cbs = linphone_player_get_callbacks(_player);
        linphone_player_cbs_set_eof_reached(_cbs, on_eof_reached);
        linphone_player_set_user_data(_player, (__bridge void*)self);
        _fileName = [LinphoneManager bundleFile:@"hold.mkv"];
        NSLog(@"Opening sound file %@", _fileName);
        linphone_player_open(_player, _fileName.UTF8String);
        _duration = linphone_player_get_duration(_player);
        _durationString = [UIChatBubbleSoundCell timeToString:_duration];
        [self updateTimeLabel:0];
        _timeProgressBar.progress = 0;
        NSLog(@"Duration : %@", _durationString);
        _shouldClosePlayer = NO;
        _eofReached = NO;
    }
    return self;
}

#pragma mark - Updating

- (void)goToBeginning {
    linphone_player_pause(_player);
    linphone_player_seek(_player, 0);
    _eofReached = NO;
}

- (void)updateTimeLabel:(int)currentTime {
    _timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [UIChatBubbleSoundCell timeToString:currentTime], _durationString];
}

- (void)update:(LinphonePlayer *)pl {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (linphone_player_get_state(pl) == LinphonePlayerPlaying) {
            int start = linphone_player_get_current_position(pl);
            while (start + 1000 < _duration && start + 1000 > linphone_player_get_current_position(pl)) {
                [NSThread sleepForTimeInterval:0.01];
                if (linphone_player_get_state(pl) == LinphonePlayerPaused)
                    break;
            }
            start = linphone_player_get_current_position(pl);
            dispatch_async(dispatch_get_main_queue(), ^{
                _timeProgressBar.progress = (float)start / (float)_duration;
                [self updateTimeLabel:start];
            });
            if (_shouldClosePlayer)
                break;
        }
        if (_shouldClosePlayer) {
            linphone_player_close(_player);
            linphone_player_unref(_player);
            dispatch_async(dispatch_get_main_queue(), ^{
            [self updateTimeLabel:0];
            _timeProgressBar.progress = 0;
            });
            _player = NULL;
            _cbs = NULL;
        }
    });
}

#pragma mark - Callbacks

void on_eof_reached(LinphonePlayer *pl) {
    NSLog(@"End of file reached");
    UIChatBubbleSoundCell *cell = (__bridge UIChatBubbleSoundCell *)linphone_player_get_user_data(pl);
    cell.eofReached = YES;
}

#pragma mark - Utils

+ (NSString *)timeToString:(int)time {
    time /= 1000;
    int hours = time / 3600;
    time %= 3600;
    int minutes = time / 60;
    int seconds = time % 60;
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.maximumIntegerDigits = 2;
    formatter.minimumIntegerDigits = 2;
    NSString *ret = [NSString stringWithFormat:@"%@:%@",
                     [formatter stringFromNumber:[NSNumber numberWithInt:minutes]],
                     [formatter stringFromNumber:[NSNumber numberWithInt:seconds]]];
    ret = (hours == 0)?ret:[[NSString stringWithFormat:@"%d:", hours] stringByAppendingString:ret];
    return ret;
}

#pragma mark - Event handlers

- (IBAction)onPlay:(id)sender {
    if (!_player) {
        _player = linphone_core_create_local_player(LC, NULL, NULL, NULL);
        _cbs = linphone_player_get_callbacks(_player);
        linphone_player_cbs_set_eof_reached(_cbs, on_eof_reached);
        linphone_player_set_user_data(_player, (__bridge void*)self);
        NSLog(@"Opening sound file %@", _fileName);
        linphone_player_open(_player, _fileName.UTF8String);
        [self updateTimeLabel:0];
        _timeProgressBar.progress = 0;
        NSLog(@"Duration : %@", _durationString);
        _shouldClosePlayer = NO;
        _eofReached = NO;
    }
    if (_eofReached && _player && linphone_player_get_state(_player) != LinphonePlayerClosed) {
        linphone_player_seek(_player, 0);
        _eofReached = NO;
    }
    if (_player) {
        LinphonePlayerState state = linphone_player_get_state(_player);
        switch(state) {
            case LinphonePlayerPlaying:
                NSLog(@"Pausing");
                linphone_player_pause(_player);
                break;
            case LinphonePlayerClosed:
                NSLog(@"Opening file");
                linphone_player_open(_player, _fileName.UTF8String);
            case LinphonePlayerPaused:
                NSLog(@"Playing");
                linphone_player_start(_player);
                break;
        }
        [self update:_player];
    } else {
        NSLog(@"Error");
    }
}

- (IBAction)onStop:(id)sender {
    if (_player) {
        NSLog(@"Stopping");
        [self goToBeginning];
        dispatch_async(dispatch_get_main_queue(), ^{
           _timeProgressBar.progress = 0;
            [self updateTimeLabel:0];
        });
        //[self update:_player];
    } else {
        NSLog(@"Error");
    }
}

- (IBAction)onTapBar:(UITapGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded)
        return;
    CGPoint loc = [sender locationInView:_playerView];
    CGPoint timeLoc = _timeProgressBar.frame.origin;
    CGSize timeSize = _timeProgressBar.frame.size;
    if (loc.x >= timeLoc.x && loc.x <= timeLoc.x + timeSize.width && loc.y >= timeLoc.y - 10 && loc.y <= timeLoc.y + timeSize.height + 10) {
        float progress = (loc.x - timeLoc.x) / timeSize.width;
        _timeProgressBar.progress = progress;
        linphone_player_seek(_player, (int)(progress * _duration));
    }
}

#pragma mark - Overriden methods

- (void)setEvent:(LinphoneEventLog *)event {
    if (!event || !(linphone_event_log_get_type(event) == LinphoneEventLogTypeConferenceChatMessage))
        return;
    
    super.event = event;
    [self setChatMessage:linphone_event_log_get_chat_message(event)];
}

- (void)setChatMessage:(LinphoneChatMessage *)message {
    if (message) {
        //tmp so that there is enough place for the player for testing purpose
        linphone_chat_message_set_text(message, "jriezgj grezgjior jgrkezjg iroez gjrkej iorejg iore jgioreja gioreja oig");
    }
    [super setChatMessage:message];
}

@end