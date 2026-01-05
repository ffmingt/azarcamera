#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// ---------------------------------------------------------
// 1. 宣告與全域變數
// ---------------------------------------------------------

@interface AzarMain_MirrorViewController : UIViewController
@end

// 宣告廣告類別 (避免編譯報錯)
@interface UIView (AdBlock)
@end

// 全域開關
static BOOL useRearCamera = NO; 
static AVCaptureSession *currentSession = nil;

// ==========================================
// 🔥 新增：通用去廣告模組 (AdBlock)
// ==========================================

// 1. 攔截 Google AdMob (橫幅廣告)
%hook GADBannerView
- (void)didMoveToWindow {
    %orig;
    if (self.superview) {
        [self setHidden:YES];       // 隱藏
        [self setAlpha:0];          // 透明
        [self removeFromSuperview]; // 移除
        NSLog(@"[AzarHack] 已移除一個 Google 廣告");
    }
}
// 讓廣告的高度變為 0 (避免留白)
- (CGSize)intrinsicContentSize {
    return CGSizeZero;
}
%end

// 2. 攔截 Google 插頁廣告 (全螢幕彈窗)
%hook GADInterstitial
- (void)presentFromRootViewController:(id)vc {
    // 直接無視，不讓它彈出來
    NSLog(@"[AzarHack] 已攔截一個 Google 彈窗廣告");
    return;
}
%end

// 3. 攔截 Facebook 廣告 (FBAdView)
%hook FBAdView
- (void)didMoveToWindow {
    %orig;
    [self setHidden:YES];
    [self removeFromSuperview];
    NSLog(@"[AzarHack] 已移除一個 Facebook 廣告");
}
- (CGSize)intrinsicContentSize {
    return CGSizeZero;
}
%end

// ==========================================
// 📷 核心邏輯：相機攔截 (保持不變)
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
// 🎨 UI 邏輯：懸浮按鈕 (保持不變)
// ==========================================
%hook AzarMain_MirrorViewController

-(void)viewDidLoad {
    %orig;

    UIViewController *controller = (UIViewController *)self;
    
    // 位置設定
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat btnSize = 50.0;
    CGFloat margin = 15.0;
    CGFloat topOffset = 150.0; 
    
    // 建立按鈕
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

%ctor {
    %init(AzarMain_MirrorViewController = objc_getClass("AzarMain.MirrorViewController"));
    // 初始化廣告相關的 Hook (這裡使用 %init 自動處理，如果類別存在就會 Hook，不存在就跳過，不會閃退)
    %init;
}
