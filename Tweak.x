#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

// --------------------------------------------------------
// 方法宣告
// ---------------------------------------------------------
@interface AzarMain_MirrorViewController : UIViewController
// 宣告我們將透過 %new 新增的方法，避免編譯錯誤
- (void)toggleCameraMode:(UIButton *)sender;
- (void)handlePan:(UIPanGestureRecognizer *)sender;
- (void)forceBringToFront;
- (void)configureButtonInteractions;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)showSettings;
- (void)updateCameraSettings;
- (void)applySettingsToDevice:(AVCaptureDevice *)device;
- (void)updateCameraButton:(UIButton *)button;
- (void)syncCameraButtonWithSession;
- (void)cameraSessionDidChange:(NSNotification *)notification;
- (void)fixMirroring;
@end

// 獨立透明視窗：讓按鈕不受 app 內其他 view/window 的排序影響，
// 並讓按鈕以外的觸控穿透到原本的介面。
@interface AZPassthroughWindow : UIWindow
@end

@implementation AZPassthroughWindow
- (BOOL)canBecomeKeyWindow { return NO; }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    UIView *rootView = self.rootViewController.view;
    return (hitView == rootView || hitView == self) ? nil : hitView;
}
@end

// ---------------------------------------------------------
// 2. 全域變數
// ---------------------------------------------------------
static BOOL useRearCamera = NO; 
static AVCaptureSession *currentSession = nil;
static UIButton *globalMagicBtn = nil;
static UIWindow *globalOverlayWindow = nil;
static NSString * const AZCameraSessionDidChangeNotification = @"AZCameraSessionDidChangeNotification";


static float beautyExposure = 1.0; // 預設美顏曝光值
static BOOL enableLowLight = YES; // 預設開啟低光增強
static BOOL forceMirror = NO; // 預設關閉強制鏡像 (避免上下顛倒)





// ---------------------------------------------------------
// 相機攔截
// ---------------------------------------------------------
%hook AVCaptureSession
- (void)startRunning {
    %orig;
    if (!self.isRunning) return;
    BOOL hasVideoInput = NO;
    for (AVCaptureInput *input in self.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]] &&
            [((AVCaptureDeviceInput *)input).device hasMediaType:AVMediaTypeVideo]) {
            hasVideoInput = YES;
            break;
        }
    }
    if (!hasVideoInput) return;
    currentSession = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AZCameraSessionDidChangeNotification object:self];
    });
}
- (void)addInput:(AVCaptureInput *)input {
    %orig;
    if (![input isKindOfClass:[AVCaptureDeviceInput class]]) return;
    AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
    if (![device hasMediaType:AVMediaTypeVideo]) return;
    currentSession = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:AZCameraSessionDidChangeNotification object:self];
    });
}
- (void)stopRunning {
    %orig;
    if (currentSession == self) currentSession = nil;
}
%end

%hook AVCaptureVideoPreviewLayer
- (void)setConnection:(AVCaptureConnection *)connection {
    %orig(connection);
    if (currentSession && self.session == currentSession && connection.isVideoMirroringSupported) {
        if (useRearCamera) {
            connection.automaticallyAdjustsVideoMirroring = NO;
            connection.videoMirrored = forceMirror;
        } else {
            connection.automaticallyAdjustsVideoMirroring = YES;
        }
    }
}
%end

// ---------------------------------------------------------
// UI 邏輯：懸浮按鈕與相機設定
// ---------------------------------------------------------
%hook AzarMain_MirrorViewController

-(void)viewDidAppear:(BOOL)animated {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AZCameraSessionDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(cameraSessionDidChange:)
                                                   name:AZCameraSessionDidChangeNotification
                                                 object:nil];
    if (globalMagicBtn) {
        [self configureButtonInteractions];
        [self syncCameraButtonWithSession];
        [self forceBringToFront];
        return;
    }

    CGFloat btnSize = 50.0;
    CGFloat margin = 15.0;
    CGFloat topOffset = 150.0; 

    UIWindowScene *windowScene = self.view.window.windowScene;
    if (windowScene) {
        globalOverlayWindow = [[AZPassthroughWindow alloc] initWithWindowScene:windowScene];
    } else {
        globalOverlayWindow = [[AZPassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }
    globalOverlayWindow.backgroundColor = [UIColor clearColor];
    globalOverlayWindow.opaque = NO;
    globalOverlayWindow.rootViewController = [UIViewController new];
    globalOverlayWindow.rootViewController.view.backgroundColor = [UIColor clearColor];
    globalOverlayWindow.rootViewController.view.opaque = NO;
    // 獨立視窗放在 alert 層以上，確保按鈕不被 app 內其他視圖蓋住。
    globalOverlayWindow.windowLevel = UIWindowLevelAlert + 1.0;
    globalOverlayWindow.hidden = NO;

    globalMagicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    globalMagicBtn.frame = CGRectMake(CGRectGetWidth(globalOverlayWindow.bounds) - btnSize - margin,
                                      topOffset, btnSize, btnSize);
    globalMagicBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    
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
    
    [globalOverlayWindow.rootViewController.view addSubview:globalMagicBtn];
    [self configureButtonInteractions];
    [self syncCameraButtonWithSession];
    [self forceBringToFront];
}

-(void)viewDidDisappear:(BOOL)animated {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AZCameraSessionDidChangeNotification object:nil];
    if (!self.presentedViewController) globalOverlayWindow.hidden = YES;
}

%new
-(void)cameraSessionDidChange:(NSNotification *)notification {
    if (notification.object == currentSession) [self syncCameraButtonWithSession];
}

%new
-(void)forceBringToFront {
    if (!globalMagicBtn || !globalOverlayWindow) return;

    UIView *rootView = globalOverlayWindow.rootViewController.view;
    if (globalMagicBtn.superview != rootView) [rootView addSubview:globalMagicBtn];
    [rootView bringSubviewToFront:globalMagicBtn];
    globalMagicBtn.layer.zPosition = 99999.0;

    globalOverlayWindow.windowLevel = UIWindowLevelAlert + 1.0;
    globalOverlayWindow.hidden = NO;
}

%new
-(void)configureButtonInteractions {
    if (!globalMagicBtn) return;

    [globalMagicBtn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [globalMagicBtn addTarget:self action:@selector(toggleCameraMode:) forControlEvents:UIControlEventTouchUpInside];

    for (UIGestureRecognizer *recognizer in [globalMagicBtn.gestureRecognizers copy]) {
        [globalMagicBtn removeGestureRecognizer:recognizer];
    }

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [globalMagicBtn addGestureRecognizer:panGesture];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [globalMagicBtn addGestureRecognizer:longPress];
}

%new
-(void)handlePan:(UIPanGestureRecognizer *)sender {
    UIView *button = sender.view;
    UIView *container = button.superview;
    CGPoint translation = [sender translationInView:container];
    CGPoint center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    CGFloat halfWidth = CGRectGetWidth(button.bounds) / 2.0;
    CGFloat halfHeight = CGRectGetHeight(button.bounds) / 2.0;
    center.x = MIN(MAX(center.x, halfWidth + 8.0), CGRectGetWidth(container.bounds) - halfWidth - 8.0);
    center.y = MIN(MAX(center.y, halfHeight + 8.0), CGRectGetHeight(container.bounds) - halfHeight - 8.0);
    button.center = center;
    [sender setTranslation:CGPointZero inView:button.superview];
}

%new
-(void)toggleCameraMode:(UIButton *)sender {
    if (!currentSession) return;

    AVCaptureDevicePosition currentPosition = useRearCamera ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    for (AVCaptureInput *input in currentSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
            if ([device hasMediaType:AVMediaTypeVideo]) {
                currentPosition = device.position;
                break;
            }
        }
    }
    AVCaptureDevicePosition targetPosition = currentPosition == AVCaptureDevicePositionBack
        ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    AVCaptureDevice *newDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                    mediaType:AVMediaTypeVideo
                                                                     position:targetPosition];
    if (!newDevice) return;

    NSError *inputError = nil;
    AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:&inputError];
    if (!newInput) {
        NSLog(@"[AzarMagicButton] 無法建立相機輸入：%@", inputError);
        return;
    }

    AVCaptureDeviceInput *oldVideoInput = nil;
    for (AVCaptureInput *input in currentSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
            if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
                oldVideoInput = deviceInput;
                break;
            }
        }
    }

    @try {
        [currentSession beginConfiguration];
        if (oldVideoInput) [currentSession removeInput:oldVideoInput];

        if (![currentSession canAddInput:newInput]) {
            if (oldVideoInput && [currentSession canAddInput:oldVideoInput]) {
                [currentSession addInput:oldVideoInput];
            }
            [currentSession commitConfiguration];
            return;
        }

        [currentSession addInput:newInput];
        [currentSession commitConfiguration];
    } @catch (NSException *exception) {
        @try {
            if ([currentSession.inputs containsObject:newInput]) [currentSession removeInput:newInput];
            if (oldVideoInput && ![currentSession.inputs containsObject:oldVideoInput] && [currentSession canAddInput:oldVideoInput]) {
                [currentSession addInput:oldVideoInput];
            }
            [currentSession commitConfiguration];
        } @catch (__unused NSException *commitException) {}
        NSLog(@"[AzarMagicButton] 切換相機失敗：%@", exception);
        return;
    }

    useRearCamera = (targetPosition == AVCaptureDevicePositionBack);
    [self applySettingsToDevice:newDevice];
    [self updateCameraButton:sender];
    [self fixMirroring];
}

%new
-(void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self showSettings];
    }
}

%new
-(void)showSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"相機設定" 
                                                                   message:@"曝光、低光與鏡像設定" 
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

    NSString *mirrorTitle = forceMirror ? @"後鏡頭鏡像: ✅ 開啟" : @"後鏡頭鏡像: ❌ 關閉";
    [alert addAction:[UIAlertAction actionWithTitle:mirrorTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        forceMirror = !forceMirror;
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
                [self applySettingsToDevice:device];
            }
        }
    }
}

%new
-(void)applySettingsToDevice:(AVCaptureDevice *)device {
    if (!device || ![device hasMediaType:AVMediaTypeVideo]) return;

    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        NSLog(@"[AzarMagicButton] 無法套用相機設定：%@", error);
        return;
    }

    @try {
        float exposure = MIN(MAX(beautyExposure, device.minExposureTargetBias), device.maxExposureTargetBias);
        [device setExposureTargetBias:exposure completionHandler:nil];
        if (device.isLowLightBoostSupported) {
            device.automaticallyEnablesLowLightBoostWhenAvailable = enableLowLight;
        }
    } @catch (NSException *exception) {
        NSLog(@"[AzarMagicButton] 套用相機設定失敗：%@", exception);
    } @finally {
        [device unlockForConfiguration];
    }
}

%new
-(void)fixMirroring {
    [self updatePreviewLayersInLayer:self.view.layer];
}

%new
-(void)updatePreviewLayersInLayer:(CALayer *)layer {
    if ([layer isKindOfClass:[AVCaptureVideoPreviewLayer class]]) {
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)layer;
        if (previewLayer.session == currentSession) {
            AVCaptureConnection *connection = previewLayer.connection;
            if (connection.isVideoMirroringSupported) {
                if (useRearCamera) {
                    connection.automaticallyAdjustsVideoMirroring = NO;
                    connection.videoMirrored = forceMirror;
                } else {
                    connection.automaticallyAdjustsVideoMirroring = YES;
                }
            }
        }
    }

    for (CALayer *subLayer in layer.sublayers) {
        [self updatePreviewLayersInLayer:subLayer];
    }
}

%new
-(void)updateCameraButton:(UIButton *)button {
    if (!button) return;
    [button setTitle:(useRearCamera ? @"📸" : @"🤳") forState:UIControlStateNormal];
    button.backgroundColor = useRearCamera
        ? [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.8]
        : [UIColor colorWithWhite:0.1 alpha:0.7];
}

%new
-(void)syncCameraButtonWithSession {
    if (!currentSession || !globalMagicBtn) return;

    for (AVCaptureInput *input in currentSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
            if ([device hasMediaType:AVMediaTypeVideo]) {
                useRearCamera = device.position == AVCaptureDevicePositionBack;
                [self updateCameraButton:globalMagicBtn];
                [self applySettingsToDevice:device];
                [self fixMirroring];
                return;
            }
        }
    }
}

%end

%ctor {
    %init(AzarMain_MirrorViewController = objc_getClass("AzarMain.MirrorViewController"));
}
