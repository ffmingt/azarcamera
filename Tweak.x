#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// ---------------------------------------------------------
// 1. 宣告與欺騙編譯器
// ---------------------------------------------------------
@interface AzarMain_MirrorViewController : UIViewController
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
// 我們的上帝視窗
static UIWindow *floatingWindow = nil;

// ---------------------------------------------------------
// 3. UI 層去廣告
// ---------------------------------------------------------
%hook GADBannerView
- (void)didMoveToWindow {
    %orig;
    if (self.superview) {
        [self setHidden:YES];
        [self removeFromSuperview];
    }
}
- (CGSize)intrinsicContentSize { return CGSizeZero; }
%end

%hook GADInterstitial
- (void)presentFromRootViewController:(id)vc { return; }
%end

%hook FBAdView
- (void)didMoveToWindow {
    %orig;
    [self setHidden:YES];
    [self removeFromSuperview];
}
- (CGSize)intrinsicContentSize { return CGSizeZero; }
%end

// ---------------------------------------------------------
// 4. 🔥 網路層去廣告
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
// 6. UI 邏輯：懸浮按鈕 (永久駐留版)
// ---------------------------------------------------------
%hook AzarMain_MirrorViewController

// 只在第一次進入時建立視窗，之後就不會消失了
-(void)viewDidAppear:(BOOL)animated {
    %orig;

    // 如果視窗已經存在，什麼都不做 (保持它原本的位置和狀態)
    if (floatingWindow) {
        return;
    }

    // --- 以下為第一次初始化 ---
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat btnSize = 50.0;
    CGFloat margin = 15.0;
    CGFloat topOffset = 150.0; 

    // 建立上帝視窗
    floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(screenWidth - btnSize - margin, topOffset, btnSize, btnSize)];
    floatingWindow.windowLevel = UIWindowLevelAlert + 2000; // 無敵置頂
    floatingWindow.backgroundColor = [UIColor clearColor];
    floatingWindow.hidden = NO; // 永遠顯示
    
    // 建立按鈕
    UIButton *magicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    magicBtn.frame = CGRectMake(0, 0, btnSize, btnSize);
    
    // 美化
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

    [floatingWindow addSubview:magicBtn];
}

// 🔥 修改點：刪除了 viewWillDisappear 方法
// 這樣即使你離開了視訊頁面，按鈕依然會留在螢幕上

%new
-(void)handlePan:(UIPanGestureRecognizer *)sender {
    UIWindow *win = floatingWindow;
    CGPoint translation = [sender translationInView:win];
    win.center = CGPointMake(win.center.x + translation.x, win.center.y + translation.y);
    [sender setTranslation:CGPointZero inView:win];
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

    // 執行熱切換 (如果當下相機有在運作)
    if (currentSession) {
        // 防止崩潰檢查：確保 session 正在運行且沒有被銷毀
        @try {
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
        } @catch (NSException *exception) {
            // 如果在非相機頁面切換，可能會捕捉到異常，這裡忽略它
        }
    }
}

%end

// --- 初始化 ---
%ctor {
    %init(AzarMain_MirrorViewController = objc_getClass("AzarMain.MirrorViewController"));
}
