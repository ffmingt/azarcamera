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

// 🔥 新增：這是我們的「上帝視窗」
static UIWindow *floatingWindow = nil;

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
// 6. UI 邏輯：上帝視窗 (UIWindow)
// ---------------------------------------------------------
%hook AzarMain_MirrorViewController

// 當進入視訊畫面時，顯示懸浮窗
-(void)viewDidAppear:(BOOL)animated {
    %orig;

    // 如果視窗已經存在，就只要顯示出來就好
    if (floatingWindow) {
        floatingWindow.hidden = NO;
        return;
    }

    // --- 計算位置 ---
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat btnSize = 50.0;
    CGFloat margin = 15.0;
    CGFloat topOffset = 150.0; 

    // --- 1. 建立獨立視窗 ---
    // 視窗的大小剛好等於按鈕的大小，這樣才不會擋到其他地方的觸控
    floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(screenWidth - btnSize - margin, topOffset, btnSize, btnSize)];
    
    // 🔥 核彈級設定：層級設為 Alert + 2000，保證無敵置頂
    floatingWindow.windowLevel = UIWindowLevelAlert + 2000;
    floatingWindow.backgroundColor = [UIColor clearColor];
    
    // 讓視窗顯示出來，但不搶走鍵盤焦點
    floatingWindow.hidden = NO;
    
    // --- 2. 建立按鈕 (加在視窗上) ---
    // 因為視窗跟按鈕一樣大，所以按鈕位置設為 (0,0)
    UIButton *magicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    magicBtn.frame = CGRectMake(0, 0, btnSize, btnSize);
    
    // UI 美化
    magicBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.7]; 
    magicBtn.layer.cornerRadius = btnSize / 2.0;
    magicBtn.layer.borderWidth = 1.5;
    magicBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    
    // 陰影
    magicBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    magicBtn.layer.shadowOffset = CGSizeMake(0, 3);
    magicBtn.layer.shadowOpacity = 0.4;
    magicBtn.layer.shadowRadius = 4.0;
    magicBtn.layer.masksToBounds = NO;
    
    [magicBtn setTitle:@"🤳" forState:UIControlStateNormal];
    magicBtn.titleLabel.font = [UIFont systemFontOfSize:24];
    
    [magicBtn addTarget:self action:@selector(toggleCameraMode:) forControlEvents:UIControlEventTouchUpInside];

    // 拖曳手勢
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [magicBtn addGestureRecognizer:panGesture];

    // 把按鈕加到這個獨立視窗裡
    [floatingWindow addSubview:magicBtn];
}

// 當離開視訊畫面時，隱藏懸浮窗 (避免在首頁也顯示)
-(void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (floatingWindow) {
        floatingWindow.hidden = YES;
    }
}

// 處理拖曳 (這次是移動整個視窗)
%new
-(void)handlePan:(UIPanGestureRecognizer *)sender {
    // 這裡我們移動的是 floatingWindow，而不是 button
    // 因為 button 是固定在 window 裡面的
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

    // 執行熱切換
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
