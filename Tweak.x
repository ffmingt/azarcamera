#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// ---------------------------------------------------------
// 1. 宣告与全域变数
// ---------------------------------------------------------

@interface AzarMain_MirrorViewController : UIViewController
@end

// 宣告广告类别 (避免编译报错)
@interface UIView (AdBlock)
@end

// 全域开关
static BOOL useRearCamera = NO; 
static AVCaptureSession *currentSession = nil;

// ==========================================
// 🔥 新增：通用去广告模组 (AdBlock)
// ==========================================

// 1. 拦截 Google AdMob (横幅广告)
%hook GADBannerView
- (void)didMoveToWindow {
    %orig;
    if (self.superview) {
        [self setHidden:YES];       // 隐藏
        [self setAlpha:0];          // 透明
        [self removeFromSuperview]; // 移除
        NSLog(@"[AzarHack] 已移除一个 Google 广告");
    }
}
// 让广告的高度变为 0 (避免留白)
- (CGSize)intrinsicContentSize {
    return CGSizeZero;
}
%end

// 2. 拦截 Google 插页广告 (全萤幕弹窗)
%hook GADInterstitial
- (void)presentFromRootViewController:(id)vc {
    // 直接无视，不让它弹出来
    NSLog(@"[AzarHack] 已拦截一个 Google 弹窗广告");
    return;
}
%end

// 3. 拦截 Facebook 广告 (FBAdView)
%hook FBAdView
- (void)didMoveToWindow {
    %orig;
    [self setHidden:YES];
    [self removeFromSuperview];
    NSLog(@"[AzarHack] 已移除一个 Facebook 广告");
}
- (CGSize)intrinsicContentSize {
    return CGSizeZero;
}
%end

// ==========================================
// 📷 核心逻辑：相机拦截 (保持不变)
// ==========================================
%hook AVCaptureSession
- (void)startRunning {
    currentSession = self;
    %orig;
}
- (void)addInput:(AVCaptureInput *)input {
    currentSession = self;
    %orig;
}
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

// ==========================================
// 🎨 UI 逻辑：悬浮按钮 (保持不变)
// ==========================================
%hook AzarMain_MirrorViewController

-(void)viewDidLoad {
    %orig;

    UIViewController *controller = (UIViewController *)self;
    
    // 位置设定
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat btnSize = 50.0;
    CGFloat margin = 15.0;
    CGFloat topOffset = 150.0; 
    
    // 建立按钮
    UIButton *magicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    magicBtn.frame = CGRectMake(screenWidth - btnSize - margin, topOffset, btnSize, btnSize);
    
    // UI 美化
    magicBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.7]; 
    magicBtn.layer.cornerRadius = btnSize / 2.0;
    magicBtn.layer.borderWidth = 1.5;
    magicBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    magicBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    magicBtn.layer.shadowOffset = CGSizeMake(0, 3);
    magicBtn.layer.shadowOpacity = 0.4;
    magicBtn.layer.shadowRadius = 4.0;
    magicBtn.layer.masksToBounds = NO;
    
    [magicBtn setTitle:@"🤳" forState:UIControlStateNormal];
    magicBtn.titleLabel.font = [UIFont systemFontOfSize:24];
    
    [magicBtn addTarget:self action:@selector(toggleCameraMode:) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [magicBtn addGestureRecognizer:panGesture];

    [controller.view addSubview:magicBtn];
}

%new
-(void)handlePan:(UIPanGestureRecognizer *)sender {
    UIViewController *controller = (UIViewController *)self;
    UIView *button = sender.view;
    CGPoint translation = [sender translationInView:controller.view];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [sender setTranslation:CGPointZero inView:controller.view];
}

%new
-(void)toggleCameraMode:(UIButton *)sender {
    useRearCamera = !useRearCamera;

    if (useRearCamera) {
        [UIView animateWithDuration:0.2 animations:^{
            sender.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.8];
            sender.layer.borderColor = [UIColor whiteColor].CGColor;
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
            sender.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
            sender.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.1 animations:^{
                sender.transform = CGAffineTransformIdentity;
            }];
        }];
        [sender setTitle:@"🤳" forState:UIControlStateNormal];
    }

    if (currentSession) {
        [currentSession beginConfiguration];
        for (AVCaptureInput *input in currentSession.inputs) {
            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
                    [currentSession removeInput:input];
                }
            }
        }
        
        AVCaptureDevicePosition targetPos = useRearCamera ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
        AVCaptureDevice *newDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera 
                                                                        mediaType:AVMediaTypeVideo 
                                                                         position:targetPos];
        if (newDevice) {
            NSError *err = nil;
            AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:&err];
            if (newInput && [currentSession canAddInput:newInput]) {
                [currentSession addInput:newInput];
            }
        }
        [currentSession commitConfiguration];
    }
}

%end

// --- 初始化区域 ---
%ctor {
    // 修正点：只保留這一行。它會同時初始化所有 Hook，並處理 Swift 類別映射。
    %init(AzarMain_MirrorViewController = objc_getClass("AzarMain.MirrorViewController"));
}
