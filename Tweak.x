#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <ReplayKit/ReplayKit.h>

// ---------------------------------------------------------
// 1. 宣告與欺騙編譯器
// ---------------------------------------------------------
@interface AzarMain_MirrorViewController : UIViewController
// 宣告我們將透過 %new 新增的方法，避免編譯錯誤
- (void)toggleCameraMode:(UIButton *)sender;
- (void)handlePan:(UIPanGestureRecognizer *)sender;
- (void)forceBringToFront;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)showSettings;
- (void)updateCameraSettings;
- (void)fixMirroring;
- (void)checkLayer:(CALayer *)layer;
// Recording methods
- (void)toggleRecording:(UIButton *)sender;
- (void)previewControllerDidFinish:(RPPreviewViewController *)previewController;
- (void)updateRecordButtonPosition;
@end

@interface GADBannerView : UIView
@end
@interface FBAdView : UIView
@end
@interface GADInterstitial : NSObject
@end

// ---------------------------------------------------------
// 2. 全域變數
// ---------------------------------------------------------
static BOOL useRearCamera = NO; 
static AVCaptureSession *currentSession = nil;
static UIButton *globalMagicBtn = nil;
static UIButton *recordBtn = nil;
static BOOL isRecording = NO;

static float beautyExposure = 2.0; // 預設美顏曝光值
static BOOL enableLowLight = YES; // 預設開啟低光增強
static BOOL forceMirror = NO; // 預設關閉強制鏡像 (避免上下顛倒)
static BOOL enableAudioFix = YES; // 預設開啟音訊錄製修復
static BOOL enableLayerFlip = NO; // 強制圖層翻轉





// ---------------------------------------------------------
// 3. UI 層去廣告
// ---------------------------------------------------------
%hook GADBannerView
- (void)didMoveToWindow {
    %orig;
    if (self.superview) { [self setHidden:YES]; [self removeFromSuperview]; }
}
- (CGSize)intrinsicContentSize { return CGSizeZero; }
%end

%hook GADInterstitial
- (void)presentFromRootViewController:(id)vc { return; }
%end

%hook FBAdView
- (void)didMoveToWindow {
    %orig;
    [self setHidden:YES]; [self removeFromSuperview];
}
- (CGSize)intrinsicContentSize { return CGSizeZero; }
%end

// ---------------------------------------------------------
// 4. 網路層去廣告
// ---------------------------------------------------------
%hook NSMutableURLRequest
- (void)setURL:(NSURL *)url {
    NSString *urlStr = [url absoluteString];
    NSArray *blockKeywords = @[
        @"googleads", @"doubleclick", @"admob",
        @"facebook.com/ad", @"audience_network",
        @"applovin", @"unity3d.com/ads"
    ];
    BOOL isAd = NO;
    for (NSString *keyword in blockKeywords) {
        if ([urlStr rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            isAd = YES; break;
        }
    }
    if (isAd) {
        %orig([NSURL URLWithString:@"http://127.0.0.1"]);
    } else {
        %orig(url);
    }
}
%end

// ---------------------------------------------------------
// 5. 核心邏輯：相機攔截
// ---------------------------------------------------------
%hook AVCaptureSession
- (void)startRunning { currentSession = self; %orig; }
- (void)addInput:(AVCaptureInput *)input { currentSession = self; %orig; }
%end

%hook AVCaptureDeviceInput
+ (instancetype)deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    if (useRearCamera && device.position == AVCaptureDevicePositionFront) {
        AVCaptureDevice *backCamera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera 
                                                                         mediaType:AVMediaTypeVideo 
                                                                          position:AVCaptureDevicePositionBack];
        if (backCamera) return %orig(backCamera, outError);
    }
    return %orig;
}
%end

%hook AVCaptureConnection
- (void)setVideoMirrored:(BOOL)mirrored {
    if (useRearCamera && [self isVideoMirroringSupported]) {
        %orig(forceMirror);
    } else {
        %orig(mirrored);
    }
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)setConnection:(AVCaptureConnection *)connection {
    %orig(connection);
    if (useRearCamera && connection.isVideoMirroringSupported) {
        connection.videoMirrored = forceMirror;
    }
}
%end

%hook AVAudioSession
- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    if (enableAudioFix && [category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        NSUInteger opts = AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionAllowAirPlay;
        return [self setCategory:category withOptions:opts error:outError];
    }
    return %orig;
}

- (BOOL)setCategory:(NSString *)category withOptions:(NSUInteger)options error:(NSError **)outError {
    if (enableAudioFix && [category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        options |= AVAudioSessionCategoryOptionDefaultToSpeaker;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
        options |= AVAudioSessionCategoryOptionAllowBluetooth;
        options |= AVAudioSessionCategoryOptionAllowAirPlay;
        options &= ~AVAudioSessionCategoryOptionDuckOthers;
    }
    return %orig(category, options, outError);
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(NSUInteger)options error:(NSError **)outError {
    if (enableAudioFix && [category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        options |= AVAudioSessionCategoryOptionDefaultToSpeaker;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
        options |= AVAudioSessionCategoryOptionAllowBluetooth;
        options |= AVAudioSessionCategoryOptionAllowAirPlay;
        options &= ~AVAudioSessionCategoryOptionDuckOthers;
        
        mode = AVAudioSessionModeVideoRecording;
    }
    return %orig(category, mode, options, outError);
}

- (BOOL)setMode:(NSString *)mode error:(NSError **)outError {
    if (enableAudioFix) {
         mode = AVAudioSessionModeVideoRecording;
    }
    return %orig(mode, outError);
}
%end

// ---------------------------------------------------------
// 6. UI 邏輯：懸浮按鈕 (寄生置頂版 + 美顏補光)
// ---------------------------------------------------------
%hook AzarMain_MirrorViewController

-(void)viewDidAppear:(BOOL)animated {
    %orig;
    if (globalMagicBtn) return;

    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat btnSize = 50.0;
    CGFloat margin = 15.0;
    CGFloat topOffset = 150.0; 

    globalMagicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    globalMagicBtn.frame = CGRectMake(screenWidth - btnSize - margin, topOffset, btnSize, btnSize);
    
    globalMagicBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.7]; 
    globalMagicBtn.layer.cornerRadius = btnSize / 2.0;
    globalMagicBtn.layer.borderWidth = 1.5;
    globalMagicBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    globalMagicBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    globalMagicBtn.layer.shadowOffset = CGSizeMake(0, 3);
    globalMagicBtn.layer.shadowOpacity = 0.4;
    globalMagicBtn.layer.shadowRadius = 4.0;
    globalMagicBtn.layer.masksToBounds = NO;
    globalMagicBtn.layer.zPosition = 99999.0;
    
    [globalMagicBtn setTitle:@"🤳" forState:UIControlStateNormal];
    globalMagicBtn.titleLabel.font = [UIFont systemFontOfSize:24];
    
    [globalMagicBtn addTarget:self action:@selector(toggleCameraMode:) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [globalMagicBtn addGestureRecognizer:panGesture];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [globalMagicBtn addGestureRecognizer:longPress];


    UIWindow *keyWindow = nil;
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        if (win.isKeyWindow) { keyWindow = win; break; }
    }
    if (!keyWindow) keyWindow = [[UIApplication sharedApplication].windows lastObject];
    [keyWindow addSubview:globalMagicBtn];

    if (!recordBtn) {
        CGFloat rSize = 40.0;
        recordBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        recordBtn.frame = CGRectMake(globalMagicBtn.frame.origin.x + (btnSize - rSize)/2, 
                                     globalMagicBtn.frame.origin.y + btnSize + 10, 
                                     rSize, rSize);
        
        recordBtn.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8];
        recordBtn.layer.cornerRadius = rSize / 2.0;
        recordBtn.layer.borderWidth = 1.5;
        recordBtn.layer.borderColor = [UIColor whiteColor].CGColor;
        recordBtn.layer.zPosition = 99998.0;
        
        [recordBtn setTitle:@"⏺" forState:UIControlStateNormal];
        recordBtn.titleLabel.font = [UIFont systemFontOfSize:20];
        
        [recordBtn addTarget:self action:@selector(toggleRecording:) forControlEvents:UIControlEventTouchUpInside];
        
        [keyWindow addSubview:recordBtn];
    }

    [NSTimer scheduledTimerWithTimeInterval:1.0 
                                     target:self 
                                   selector:@selector(forceBringToFront) 
                                   userInfo:nil 
                                    repeats:YES];
}

%new
-(void)forceBringToFront {
    if (!globalMagicBtn) return;
    UIView *superView = globalMagicBtn.superview;
    if (!superView) {
        UIWindow *keyWindow = nil;
        for (UIWindow *win in [UIApplication sharedApplication].windows) {
            if (win.isKeyWindow) { keyWindow = win; break; }
        }
        if (!keyWindow) keyWindow = [[UIApplication sharedApplication].windows lastObject];
        [keyWindow addSubview:globalMagicBtn];
        superView = keyWindow;
    }
    [superView bringSubviewToFront:globalMagicBtn];
    globalMagicBtn.layer.zPosition = 99999.0;
    
    if (recordBtn) {
        if (!recordBtn.superview) {
            [superView addSubview:recordBtn];
        }
        [superView bringSubviewToFront:recordBtn];
        recordBtn.layer.zPosition = 99998.0;
    }
}

%new
-(void)handlePan:(UIPanGestureRecognizer *)sender {
    UIView *button = sender.view;
    CGPoint translation = [sender translationInView:button.superview];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [sender setTranslation:CGPointZero inView:button.superview];
    
    if (recordBtn) {
        CGFloat btnSize = 50.0;
        CGFloat rSize = 40.0;
        recordBtn.frame = CGRectMake(button.frame.origin.x + (btnSize - rSize)/2, 
                                     button.frame.origin.y + btnSize + 10, 
                                     rSize, rSize);
    }
}

%new
-(void)toggleCameraMode:(UIButton *)sender {
    useRearCamera = !useRearCamera;

    if (useRearCamera) {
        [UIView animateWithDuration:0.2 animations:^{
            sender.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.8];
            sender.transform = CGAffineTransformMakeScale(1.1, 1.1);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.1 animations:^{
                sender.transform = CGAffineTransformIdentity;
            }];
        }];
        [sender setTitle:@"📸" forState:UIControlStateNormal];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            sender.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.7];
            sender.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.1 animations:^{
                sender.transform = CGAffineTransformIdentity;
            }];
        }];
        [sender setTitle:@"🤳" forState:UIControlStateNormal];
    }

    if (currentSession) {
        @try {
            [currentSession beginConfiguration];
            
            // 移除舊輸入
            for (AVCaptureInput *input in currentSession.inputs) {
                if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                    AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                    if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
                        [currentSession removeInput:input];
                    }
                }
            }
            
            // 準備新輸入
            AVCaptureDevicePosition targetPos = useRearCamera ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
            AVCaptureDevice *newDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera 
                                                                            mediaType:AVMediaTypeVideo 
                                                                             position:targetPos];
            
            // 🔥🔥 美顏/補光核心：調整曝光補償 (Exposure Target Bias) 🔥🔥
            if (newDevice) {
                NSError *lockError = nil;
                // 必須先鎖定設備才能修改參數
                if ([newDevice lockForConfiguration:&lockError]) {
                    
                    // 這裡的數值範圍通常是 -8.0 到 8.0
                    // 0 是正常，+1 是稍亮
                    // +2.0 是明顯增亮 (類似打光效果)
                    float brightnessValue = beautyExposure; 
                    
                    [newDevice setExposureTargetBias:brightnessValue completionHandler:nil];
                    
                    // 如果有低光增強模式，根據設定開啟或關閉
                    if (newDevice.isLowLightBoostSupported) {
                        newDevice.automaticallyEnablesLowLightBoostWhenAvailable = enableLowLight;
                    }

                    [newDevice unlockForConfiguration];
                    NSLog(@"[AzarHack] 已開啟美顏補光模式：+2.0 EV");
                }
            }

            if (newDevice) {
                NSError *err = nil;
                AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:&err];
                if (newInput && [currentSession canAddInput:newInput]) {
                    [currentSession addInput:newInput];
                }
            }
            [currentSession commitConfiguration];
            
            [self fixMirroring];
            
        } @catch (NSException *exception) {}
    }
}

%new
-(void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self showSettings];
    }
}

%new
-(void)showSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"美顏設定" 
                                                                   message:@"調整參數" 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSString *expTitle = [NSString stringWithFormat:@"曝光補償 (目前: %.1f)", beautyExposure];
    [alert addAction:[UIAlertAction actionWithTitle:expTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        
        UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"設定曝光補償" 
                                                                            message:@"範圍: -8.0 ~ +8.0\n(0=正常, +2=美白)" 
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        
        [inputAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.text = [NSString stringWithFormat:@"%.1f", beautyExposure];
            textField.keyboardType = UIKeyboardTypeDecimalPad;
        }];
        
        [inputAlert addAction:[UIAlertAction actionWithTitle:@"確定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            UITextField *tf = inputAlert.textFields.firstObject;
            float val = [tf.text floatValue];
            if (val > 8.0) val = 8.0;
            if (val < -8.0) val = -8.0;
            beautyExposure = val;
            [self updateCameraSettings];
            [self showSettings]; 
        }]];
        
        [inputAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            [self showSettings];
        }]];
        
        [self presentViewController:inputAlert animated:YES completion:nil];
    }]];
    
    NSString *lowLightTitle = enableLowLight ? @"低光增強: ✅ 開啟" : @"低光增強: ❌ 關閉";
    [alert addAction:[UIAlertAction actionWithTitle:lowLightTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        enableLowLight = !enableLowLight;
        [self updateCameraSettings];
        [self showSettings];
    }]];

    NSString *mirrorTitle = forceMirror ? @"鏡像翻轉: ✅ 開啟" : @"鏡像翻轉: ❌ 關閉";
    [alert addAction:[UIAlertAction actionWithTitle:mirrorTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        forceMirror = !forceMirror;
        [self fixMirroring];
        [self showSettings];
    }]];
    
    NSString *audioTitle = enableAudioFix ? @"音訊錄製優化: ✅ 開啟" : @"音訊錄製優化: ❌ 關閉";
    [alert addAction:[UIAlertAction actionWithTitle:audioTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        enableAudioFix = !enableAudioFix;
        [self showSettings];
    }]];
    
    NSString *layerFlipTitle = enableLayerFlip ? @"圖層翻轉: ✅ 開啟" : @"圖層翻轉: ❌ 關閉";
    [alert addAction:[UIAlertAction actionWithTitle:layerFlipTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        enableLayerFlip = !enableLayerFlip;
        [self fixMirroring];
        [self showSettings];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"關閉" style:UIAlertActionStyleCancel handler:nil]];
    
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = globalMagicBtn;
        alert.popoverPresentationController.sourceRect = globalMagicBtn.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

%new
-(void)updateCameraSettings {
    if (!currentSession) return;
    
    for (AVCaptureInput *input in currentSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *devInput = (AVCaptureDeviceInput *)input;
            AVCaptureDevice *device = devInput.device;
            
            if ([device hasMediaType:AVMediaTypeVideo]) {
                NSError *error = nil;
                if ([device lockForConfiguration:&error]) {
                    [device setExposureTargetBias:beautyExposure completionHandler:nil];
                    if (device.isLowLightBoostSupported) {
                        device.automaticallyEnablesLowLightBoostWhenAvailable = enableLowLight;
                    }
                    [device unlockForConfiguration];
                }
            }
        }
    }
}

%new
-(void)fixMirroring {
    if (!useRearCamera) return;
    
    if (currentSession) {
        for (AVCaptureOutput *output in currentSession.outputs) {
            for (AVCaptureConnection *connection in output.connections) {
                if (connection.isVideoMirroringSupported) {
                    connection.videoMirrored = forceMirror;
                }
            }
        }
    }
    
    // Fix Preview Layer
    [self checkLayer:((UIViewController *)self).view.layer];
}

%new
-(void)checkLayer:(CALayer *)layer {
    BOOL isVideoLayer = [layer isKindOfClass:[AVCaptureVideoPreviewLayer class]];
    if (!isVideoLayer && NSClassFromString(@"AVSampleBufferDisplayLayer")) {
        isVideoLayer = [layer isKindOfClass:NSClassFromString(@"AVSampleBufferDisplayLayer")];
    }
    if (!isVideoLayer && NSClassFromString(@"CAEAGLLayer")) {
        isVideoLayer = [layer isKindOfClass:NSClassFromString(@"CAEAGLLayer")];
    }
    if (!isVideoLayer && NSClassFromString(@"CAMetalLayer")) {
        isVideoLayer = [layer isKindOfClass:NSClassFromString(@"CAMetalLayer")];
    }

    if (isVideoLayer) {
        if ([layer isKindOfClass:[AVCaptureVideoPreviewLayer class]]) {
            AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)layer;
            if (previewLayer.connection.isVideoMirroringSupported) {
                previewLayer.connection.videoMirrored = forceMirror;
            }
        }
        
        if (enableLayerFlip) {
            layer.transform = CATransform3DMakeScale(-1.0, 1.0, 1.0);
        } else {
            layer.transform = CATransform3DIdentity;
        }
    }
    
    if (layer.sublayers) {
        for (CALayer *sub in layer.sublayers) {
            [self checkLayer:sub];
        }
    }
}

%new
-(void)toggleRecording:(UIButton *)sender {
    if (isRecording) {
        [[RPScreenRecorder sharedRecorder] stopRecordingWithHandler:^(RPPreviewViewController *previewViewController, NSError *error) {
            isRecording = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                // Reset button state
                if (recordBtn) {
                    [recordBtn setTitle:@"⏺" forState:UIControlStateNormal];
                    recordBtn.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.8];
                }
                
                if (error) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"錄影停止失敗" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                    [(UIViewController *)self presentViewController:alert animated:YES completion:nil];
                }
                
                if (previewViewController) {
                    previewViewController.previewControllerDelegate = (id<RPPreviewViewControllerDelegate>)self;
                    if (previewViewController.popoverPresentationController) {
                        previewViewController.popoverPresentationController.sourceView = recordBtn ? recordBtn : sender;
                        previewViewController.popoverPresentationController.sourceRect = recordBtn ? recordBtn.bounds : sender.bounds;
                    }
                    [(UIViewController *)self presentViewController:previewViewController animated:YES completion:nil];
                }
            });
        }];
    } else {
        if ([[RPScreenRecorder sharedRecorder] isAvailable]) {
            [[RPScreenRecorder sharedRecorder] setMicrophoneEnabled:YES];
            
            [[RPScreenRecorder sharedRecorder] startRecordingWithHandler:^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!error) {
                        isRecording = YES;
                        if (recordBtn) {
                            [recordBtn setTitle:@"⏹" forState:UIControlStateNormal];
                            recordBtn.backgroundColor = [UIColor grayColor];
                        }
                    } else {
                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"無法開始錄影" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                        [(UIViewController *)self presentViewController:alert animated:YES completion:nil];
                    }
                });
            }];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"錯誤" message:@"螢幕錄製不可用" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [(UIViewController *)self presentViewController:alert animated:YES completion:nil];
        }
    }
}

%new
-(void)previewControllerDidFinish:(RPPreviewViewController *)previewController {
    [previewController dismissViewControllerAnimated:YES completion:nil];
}

%end

%ctor {
    %init(AzarMain_MirrorViewController = objc_getClass("AzarMain.MirrorViewController"));
}
