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

// ---------------------------------------------------------
// 3. UI 層去廣告 (視覺隱藏)
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
// 4. 🔥 網路層去廣告 (模擬 Hosts 阻擋)
//    這是最底層的攔截，直接讓 App 連不上廣告伺服器
// ---------------------------------------------------------
%hook NSMutableURLRequest

- (void)setURL:(NSURL *)url {
    NSString *urlStr = [url absoluteString];
    
    // 定義廣告關鍵字黑名單
    NSArray *blockKeywords = @[
        @"googleads",
        @"doubleclick",
        @"admob",
        @"facebook.com/ad",
        @"audience_network",
        @"applovin",
        @"unity3d.com/ads"
    ];
    
    BOOL isAd = NO;
    for (NSString *keyword in blockKeywords) {
        if ([urlStr rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
            isAd = YES;
            break;
        }
    }
    
    if (isAd) {
        // 如果發現是廣告，就把網址改成 127.0.0.1 (本機)，讓請求失敗
        NSLog(@"[AzarHack] 🛡️ 已攔截廣告請求: %@", urlStr);
        NSURL *blockedURL = [NSURL URLWithString:@"http://127.0.0.1"];
        %orig(blockedURL);
    } else {
        // 正常的請求，放行
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
// 6. UI 邏輯：懸浮按鈕
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
