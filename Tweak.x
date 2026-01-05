#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// ---------------------------------------------------------
// 1. 宣告與欺騙編譯器 (Fix Forward Declaration Error)
// ---------------------------------------------------------

// 告訴編譯器：Azar 的介面是 UIViewController
@interface AzarMain_MirrorViewController : UIViewController
@end

// 🔥 關鍵修正：告訴編譯器這些廣告元件是 UIView
// 這樣編譯器就會允許使用 setHidden, removeFromSuperview 等方法
@interface GADBannerView : UIView
@end

@interface FBAdView : UIView
@end

// 插頁廣告通常是 NSObject
@interface GADInterstitial : NSObject
@end

// ---------------------------------------------------------
// 2. 全域變數
// ---------------------------------------------------------
static BOOL useRearCamera = NO; 
static AVCaptureSession *currentSession = nil;

// ---------------------------------------------------------
// 3. 通用去廣告模組 (AdBlock)
// ---------------------------------------------------------

// 攔截 Google AdMob (橫幅)
%hook GADBannerView
- (void)didMoveToWindow {
    %orig;
    if (self.superview) {
        [self setHidden:YES];
        [self setAlpha:0];
        [self removeFromSuperview];
    }
}
- (CGSize)intrinsicContentSize {
    return CGSizeZero;
}
%end

// 攔截 Google 插頁廣告
%hook GADInterstitial
- (void)presentFromRootViewController:(id)vc {
    return; // 直接攔截，不讓它彈出來
}
%end

// 攔截 Facebook 廣告
%hook FBAdView
- (void)didMoveToWindow {
    %orig;
    [self setHidden:YES];
    [self removeFromSuperview];
}
- (CGSize)intrinsicContentSize {
    return CGSizeZero;
}
%end

// ---------------------------------------------------------
// 4. 核心邏輯：相機攔截
// ---------------------------------------------------------
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

// ---------------------------------------------------------
// 5. UI 邏輯：懸浮按鈕
// ---------------------------------------------------------
%hook AzarMain_MirrorViewController

-(void)viewDidLoad {
    %orig;

    UIViewController *controller = (UIViewController *)self;
    
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat btnSize = 50.0;
    CGFloat margin = 15.0;
    CGFloat topOffset = 150.0; 
    
    UIButton *magicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    magicBtn.frame = CGRectMake(screenWidth - btnSize - margin, topOffset, btnSize, btnSize);
    
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

// --- 初始化 ---
%ctor {
    %init(AzarMain_MirrorViewController = objc_getClass("AzarMain.MirrorViewController"));
}
