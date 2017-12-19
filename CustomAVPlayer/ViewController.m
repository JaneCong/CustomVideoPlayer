//
//  ViewController.m
//  CustomAVPlayer
//
//  Created by L了个G on 2017/12/18.
//  Copyright © 2017年 L了个G. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "LGVideoRenderView.h"

static void *AVPlayerItemStatusContext = &AVPlayerItemStatusContext;

@interface ViewController ()<AVPlayerItemOutputPullDelegate>

@property (nonatomic) AVPlayer *player;

@property (nonatomic) dispatch_queue_t videoOutPutQueue;

@property (nonatomic) CADisplayLink *displayLink;

@property (nonatomic) AVPlayerItemVideoOutput *videoOutput;

@property (nonatomic) LGVideoRenderView *renderView;

@property (nonatomic) BOOL isYUVRend;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self addChooseButton];
}

-(void)addChooseButton{
    UIButton *btn1 = [UIButton buttonWithType:UIButtonTypeCustom];
    btn1.frame     = CGRectMake(40, 200, 100, 40);
    [btn1 setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [btn1 setTitle:@"yuv mode" forState:UIControlStateNormal];
    [btn1 addTarget:self action:@selector(startPlay:) forControlEvents:UIControlEventTouchUpInside];
    btn1.tag = 1;
    [self.view addSubview:btn1];
    
    UIButton *btn2 = [UIButton buttonWithType:UIButtonTypeCustom];
    btn2.frame     = CGRectMake(200, 200, 100, 40);
    [btn2 setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [btn2 setTitle:@"rgb mode" forState:UIControlStateNormal];
    [btn2 addTarget:self action:@selector(startPlay:) forControlEvents:UIControlEventTouchUpInside];
    btn2.tag = 2;
    [self.view addSubview:btn2];
}

-(void)startPlay:(UIButton *)btn{
    self.isYUVRend = btn.tag == 1 ? YES : NO ;
    [self configPlayer];
    [self configTimer];
    if ([self.player currentItem] == nil) {
        [self.renderView setUpGLParams];
    }
    
    [[self.player currentItem] removeOutput:self.videoOutput];
    
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[[NSBundle mainBundle] URLForResource:@"1" withExtension:@"mp4"]];
    AVAsset *asset = [item asset];
    
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        if ([asset statusOfValueForKey:@"tracks" error:nil] == AVKeyValueStatusLoaded) {
            NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
            if ([tracks count] > 0) {
                AVAssetTrack *videoTrack = [tracks firstObject];
                
                [videoTrack loadValuesAsynchronouslyForKeys:@[@"preferredTransform"] completionHandler:^{
                    if ([videoTrack statusOfValueForKey:@"preferredTransform" error:nil] == AVKeyValueStatusLoaded) {
                        CGAffineTransform perferredTransform = [videoTrack preferredTransform];
                        self.renderView.preferredRotation = -1 * atan2(perferredTransform.b, perferredTransform.a);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [item addOutput:self.videoOutput];
                            [self.player replaceCurrentItemWithPlayerItem:item];
                            [self.videoOutput requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03];
                            [self.player play];
                        });
                    }
                }];
            }
        }
    }];
}


- (void)configPlayer{
    self.player = [AVPlayer new];
    
    NSDictionary *pixBuffAttributes =  self.isYUVRend ? @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)}: @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    self.videoOutput  = [[AVPlayerItemVideoOutput alloc] initWithOutputSettings:pixBuffAttributes];
    _videoOutPutQueue = dispatch_queue_create("videoOutputQueue",DISPATCH_QUEUE_SERIAL);
    [self.videoOutput setDelegate:self queue:_videoOutPutQueue];
    
    [self addObserver:self forKeyPath:@"player.currentItem.status" options:NSKeyValueObservingOptionNew context:AVPlayerItemStatusContext];
    
    self.renderView = [LGVideoRenderView new];
    self.renderView.frame = self.view.bounds;
    [self.view addSubview:self.renderView];
}

- (void)configTimer{
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
    [[self displayLink] addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [[self displayLink] setPaused:YES];
}

- (void)displayLinkCallback:(CADisplayLink *)sender
{

    CMTime outputItemTime = kCMTimeInvalid;
    
    CFTimeInterval nextVSync = ([sender timestamp] + [sender duration]);
    
    outputItemTime = [[self videoOutput] itemTimeForHostTime:nextVSync];
    
    if ([[self videoOutput] hasNewPixelBufferForItemTime:outputItemTime]) {
        CVPixelBufferRef pixelBuffer = NULL;
        pixelBuffer = [[self videoOutput] copyPixelBufferForItemTime:outputItemTime itemTimeForDisplay:NULL];
        
        if (self.isYUVRend) {
            [self.renderView rendYUVPixbuffer:pixelBuffer];
        }else
        {
           [self.renderView rendRGBPixbuffer:pixelBuffer];
        }

        
        if (pixelBuffer != NULL) {
            CFRelease(pixelBuffer);
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == AVPlayerItemStatusContext) {
        AVPlayerStatus status = [change[NSKeyValueChangeNewKey] integerValue];
        switch (status) {
            case AVPlayerItemStatusUnknown:
                break;
            case AVPlayerItemStatusReadyToPlay:
                self.renderView.presentationRect = [[_player currentItem] presentationSize];
                break;
            case AVPlayerItemStatusFailed:
                
                break;
        }
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


#pragma mark - AVPlayerItemOutputPullDelegate

- (void)outputMediaDataWillChange:(AVPlayerItemOutput *)sender
{
    // Restart display link.
    [[self displayLink] setPaused:NO];
}


@end
