#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface AZCameraOverlayViewController : UIViewController
@property (nonatomic, strong) UIButton *magicButton;
- (void)toggleCameraMode:(UIButton *)sender;
- (void)handlePan:(UIPanGestureRecognizer *)sender;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)showSettings;
- (void)updateCameraSettings;
- (void)applySettingsToDevice:(AVCaptureDevice *)device;
- (void)updateCameraButton;
- (void)syncCameraButtonWithSession;
- (void)cameraSessionDidChange:(NSNotification *)notification;
- (void)configureButtonInteractions;
- (void)fixMirroring;
- (void)updatePreviewLayersInLayer:(CALayer *)layer;
- (void)bringButtonToFront;
@end

// 透明 overlay window 只攔截按鈕本身，其餘觸控會穿透到 Azar。
@interface AZPassthroughWindow : UIWindow
@end

@implementation AZPassthroughWindow
- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (![hitView isKindOfClass:[UIControl class]]) {
        UIView *view = hitView;
        while (view && view != self.rootViewController.view) {
            if ([view isKindOfClass:[UIControl class]]) return view;
            view = view.superview;
        }
    }
    UIView *rootView = self.rootViewController.view;
    return (hitView == rootView || hitView == self) ? nil : hitView;
}
@end

static BOOL useRearCamera = NO;
static AVCaptureSession *currentSession = nil;
static UIWindow *globalOverlayWindow = nil;
static AZCameraOverlayViewController *globalOverlayController = nil;
static UIButton *globalMagicBtn = nil;

static float beautyExposure = 1.0;
static BOOL enableLowLight = YES;
static BOOL forceMirror = NO;

static NSString * const AZCameraSessionDidChangeNotification = @"AZCameraSessionDidChangeNotification";

static void AZInstallOverlayForWindowScene(UIWindowScene *windowScene);

// 由通用 UIKit 入口呼叫，不再依賴 Azar 某個版本的 controller 名稱。
%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    if (self == globalOverlayWindow) return;

    UIWindowScene *windowScene = self.windowScene;
    if (windowScene) {
        NSLog(@"[AzarMagicButton] UIWindow ready: %@", NSStringFromClass(self.class));
        AZInstallOverlayForWindowScene(windowScene);
    }
}
%end

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
    currentSession = self;
    if (![input isKindOfClass:[AVCaptureDeviceInput class]]) return;
    if (![((AVCaptureDeviceInput *)input).device hasMediaType:AVMediaTypeVideo]) return;

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
    if (!connection.isVideoMirroringSupported || self.session != currentSession) return;

    if (useRearCamera) {
        connection.automaticallyAdjustsVideoMirroring = NO;
        connection.videoMirrored = forceMirror;
    } else {
        connection.automaticallyAdjustsVideoMirroring = YES;
    }
}
%end

// 有些 Swift/UIKit 畫面不會觸發特定的 makeKeyAndVisible 路徑，
// 因此把所有非 overlay controller 的 viewDidAppear 當作安全 fallback。
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([self isKindOfClass:[AZCameraOverlayViewController class]]) return;

    UIWindowScene *windowScene = ((UIViewController *)self).view.window.windowScene;
    if (windowScene) AZInstallOverlayForWindowScene(windowScene);
}
%end

@implementation AZCameraOverlayViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.opaque = NO;

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AZCameraSessionDidChangeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cameraSessionDidChange:)
                                                 name:AZCameraSessionDidChangeNotification
                                               object:nil];

    CGFloat buttonSize = 54.0;
    CGFloat margin = 16.0;
    CGFloat topOffset = 100.0;

    self.magicButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.magicButton.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - buttonSize - margin,
                                       topOffset,
                                       buttonSize,
                                       buttonSize);
    self.magicButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                        UIViewAutoresizingFlexibleBottomMargin;
    self.magicButton.backgroundColor = [UIColor colorWithRed:0.05 green:0.55 blue:0.85 alpha:0.9];
    self.magicButton.layer.cornerRadius = buttonSize / 2.0;
    self.magicButton.layer.borderWidth = 2.0;
    self.magicButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.magicButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.magicButton.layer.shadowOffset = CGSizeMake(0, 3);
    self.magicButton.layer.shadowOpacity = 0.5;
    self.magicButton.layer.shadowRadius = 5.0;
    self.magicButton.layer.zPosition = 100000.0;
    self.magicButton.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    self.magicButton.accessibilityLabel = @"切換相機";
    [self.magicButton setTitle:@"↻" forState:UIControlStateNormal];
    [self.magicButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];

    [self configureButtonInteractions];
    [self.view addSubview:self.magicButton];
    globalMagicBtn = self.magicButton;

    [self syncCameraButtonWithSession];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self bringButtonToFront];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)cameraSessionDidChange:(NSNotification *)notification {
    if (notification.object == currentSession) [self syncCameraButtonWithSession];
}

- (void)bringButtonToFront {
    if (!self.magicButton) return;
    [self.view bringSubviewToFront:self.magicButton];
    self.magicButton.layer.zPosition = 100000.0;
    self.magicButton.hidden = NO;
}

- (void)configureButtonInteractions {
    [self.magicButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [self.magicButton addTarget:self
                          action:@selector(toggleCameraMode:)
                forControlEvents:UIControlEventTouchUpInside];

    for (UIGestureRecognizer *recognizer in [self.magicButton.gestureRecognizers copy]) {
        [self.magicButton removeGestureRecognizer:recognizer];
    }

    UIPanGestureRecognizer *panGesture =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.magicButton addGestureRecognizer:panGesture];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self.magicButton addGestureRecognizer:longPress];
}

- (void)handlePan:(UIPanGestureRecognizer *)sender {
    UIButton *button = (UIButton *)sender.view;
    UIView *container = button.superview;
    CGPoint translation = [sender translationInView:container];
    CGPoint center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    CGFloat halfWidth = CGRectGetWidth(button.bounds) / 2.0;
    CGFloat halfHeight = CGRectGetHeight(button.bounds) / 2.0;
    center.x = MIN(MAX(center.x, halfWidth + 8.0), CGRectGetWidth(container.bounds) - halfWidth - 8.0);
    center.y = MIN(MAX(center.y, halfHeight + 8.0), CGRectGetHeight(container.bounds) - halfHeight - 8.0);
    button.center = center;
    [sender setTranslation:CGPointZero inView:container];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan && !self.presentedViewController) {
        [self showSettings];
    }
}

- (void)toggleCameraMode:(UIButton *)sender {
    if (!currentSession) {
        NSLog(@"[AzarMagicButton] 尚未偵測到 AVCaptureSession");
        return;
    }

    AVCaptureDevicePosition currentPosition =
        useRearCamera ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    for (AVCaptureInput *input in currentSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
            if ([device hasMediaType:AVMediaTypeVideo]) {
                currentPosition = device.position;
                break;
            }
        }
    }

    AVCaptureDevicePosition targetPosition =
        currentPosition == AVCaptureDevicePositionBack
            ? AVCaptureDevicePositionFront
            : AVCaptureDevicePositionBack;
    AVCaptureDevice *newDevice =
        [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                           mediaType:AVMediaTypeVideo
                                            position:targetPosition];
    if (!newDevice) return;

    NSError *inputError = nil;
    AVCaptureDeviceInput *newInput =
        [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:&inputError];
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
            if ([currentSession.inputs containsObject:newInput]) {
                [currentSession removeInput:newInput];
            }
            if (oldVideoInput && [currentSession canAddInput:oldVideoInput]) {
                [currentSession addInput:oldVideoInput];
            }
            [currentSession commitConfiguration];
        } @catch (__unused NSException *rollbackException) {
        }
        NSLog(@"[AzarMagicButton] 切換相機失敗：%@", exception);
        return;
    }

    useRearCamera = targetPosition == AVCaptureDevicePositionBack;
    [self applySettingsToDevice:newDevice];
    [self updateCameraButton];
    [self fixMirroring];
}

- (void)showSettings {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"相機設定"
                                           message:@"曝光、低光與鏡像設定"
                                    preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *exposureTitle =
        [NSString stringWithFormat:@"曝光補償（目前 %.1f）", beautyExposure];
    [alert addAction:
        [UIAlertAction actionWithTitle:exposureTitle
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
        UIAlertController *inputAlert =
            [UIAlertController alertControllerWithTitle:@"設定曝光補償"
                                                message:@"範圍 -8.0 ~ +8.0"
                                         preferredStyle:UIAlertControllerStyleAlert];
        [inputAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = [NSString stringWithFormat:@"%.1f", beautyExposure];
            textField.keyboardType = UIKeyboardTypeDecimalPad;
        }];
        [inputAlert addAction:
            [UIAlertAction actionWithTitle:@"確定"
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *confirmation) {
            UITextField *textField = inputAlert.textFields.firstObject;
            beautyExposure = MIN(MAX([textField.text floatValue], -8.0), 8.0);
            [self updateCameraSettings];
        }]];
        [inputAlert addAction:
            [UIAlertAction actionWithTitle:@"取消"
                                     style:UIAlertActionStyleCancel
                                   handler:nil]];
        [self presentViewController:inputAlert animated:YES completion:nil];
    }]];

    NSString *lowLightTitle =
        enableLowLight ? @"低光增強：開啟" : @"低光增強：關閉";
    [alert addAction:
        [UIAlertAction actionWithTitle:lowLightTitle
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
        enableLowLight = !enableLowLight;
        [self updateCameraSettings];
    }]];

    NSString *mirrorTitle =
        forceMirror ? @"後鏡頭鏡像：開啟" : @"後鏡頭鏡像：關閉";
    [alert addAction:
        [UIAlertAction actionWithTitle:mirrorTitle
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
        forceMirror = !forceMirror;
        [self fixMirroring];
    }]];

    [alert addAction:
        [UIAlertAction actionWithTitle:@"關閉"
                                 style:UIAlertActionStyleCancel
                               handler:nil]];

    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.magicButton;
        alert.popoverPresentationController.sourceRect = self.magicButton.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateCameraSettings {
    if (!currentSession) return;
    for (AVCaptureInput *input in currentSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
            if ([device hasMediaType:AVMediaTypeVideo]) {
                [self applySettingsToDevice:device];
            }
        }
    }
}

- (void)applySettingsToDevice:(AVCaptureDevice *)device {
    if (!device || ![device hasMediaType:AVMediaTypeVideo]) return;

    NSError *error = nil;
    if (![device lockForConfiguration:&error]) {
        NSLog(@"[AzarMagicButton] 無法套用相機設定：%@", error);
        return;
    }

    @try {
        float exposure =
            MIN(MAX(beautyExposure, device.minExposureTargetBias), device.maxExposureTargetBias);
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

- (void)fixMirroring {
    if (!currentSession || !globalOverlayWindow) return;

    for (UIWindow *window in globalOverlayWindow.windowScene.windows) {
        if (window != globalOverlayWindow) {
            [self updatePreviewLayersInLayer:window.layer];
        }
    }
}

- (void)updatePreviewLayersInLayer:(CALayer *)layer {
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

- (void)updateCameraButton {
    if (!self.magicButton) return;
    self.magicButton.backgroundColor = useRearCamera
        ? [UIColor colorWithRed:0.05 green:0.65 blue:0.35 alpha:0.9]
        : [UIColor colorWithRed:0.05 green:0.55 blue:0.85 alpha:0.9];
    [self.magicButton setTitle:@"↻" forState:UIControlStateNormal];
}

- (void)syncCameraButtonWithSession {
    if (!currentSession || !self.magicButton) return;
    for (AVCaptureInput *input in currentSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
            if ([device hasMediaType:AVMediaTypeVideo]) {
                useRearCamera = device.position == AVCaptureDevicePositionBack;
                [self updateCameraButton];
                [self applySettingsToDevice:device];
                [self fixMirroring];
                return;
            }
        }
    }
}

@end

static void AZInstallOverlayForWindowScene(UIWindowScene *windowScene) {
    if (!windowScene) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (globalOverlayWindow && globalOverlayWindow.windowScene == windowScene) {
            globalOverlayWindow.hidden = NO;
            [globalOverlayController bringButtonToFront];
            return;
        }

        AZCameraOverlayViewController *controller = [[AZCameraOverlayViewController alloc] init];
        AZPassthroughWindow *overlayWindow =
            [[AZPassthroughWindow alloc] initWithWindowScene:windowScene];
        overlayWindow.frame = windowScene.coordinateSpace.bounds;
        overlayWindow.backgroundColor = [UIColor clearColor];
        overlayWindow.opaque = NO;
        overlayWindow.windowLevel = UIWindowLevelAlert + 1.0;
        overlayWindow.rootViewController = controller;
        overlayWindow.hidden = NO;

        globalOverlayController = controller;
        globalOverlayWindow = overlayWindow;
        NSLog(@"[AzarMagicButton] overlay window installed");
    });
}
