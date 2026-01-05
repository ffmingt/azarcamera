#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// ---------------------------------------------------------
// 1. 宣告與全域變數
// ---------------------------------------------------------

@interface AzarMain_MirrorViewController : UIViewController
@end

// 全域開關
static BOOL useRearCamera = NO; 
// 抓取目前正在運作的相機 Session
static AVCaptureSession *currentSession = nil;

// ---------------------------------------------------------
// 2. 綁架相機 Session (為了熱切換)
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

// ---------------------------------------------------------
// 3. 攔截輸入 (底層替換)
// ---------------------------------------------------------
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
// 4. UI 美化與熱切換邏輯
// ---------------------------------------------------------
%hook AzarMain_MirrorViewController

-(void)viewDidLoad {
    %orig;

    UIViewController *controller = (UIViewController *)self;
    
    // --- 計算位置 (右上角，向下偏移) ---
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat btnSize = 50.0; // 按鈕大小 (圓形)
    CGFloat margin = 15.0;  // 距離右邊邊緣的距離
    CGFloat topOffset = 60.0; // 向下偏移 (避開狀態列)
    
    // 建立按鈕
    UIButton *magicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    magicBtn.frame = CGRectMake(screenWidth - btnSize - margin, topOffset, btnSize, btnSize);
    
    // --- 🎨 UI 美化 ---
    // 1. 半透明深色背景
    magicBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.7]; 
    
    // 2. 圓形與邊框
    magicBtn.layer.cornerRadius = btnSize / 2.0;
    magicBtn.layer.borderWidth = 1.5;
    magicBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    
    // 3. 陰影效果 (增加立體感)
    magicBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    magicBtn.layer.shadowOffset = CGSizeMake(0, 3);
    magicBtn.layer.shadowOpacity = 0.4;
    magicBtn.layer.shadowRadius = 4.0;
    magicBtn.layer.masksToBounds = NO; // 必須為 NO 才能顯示陰影
    
    // 4. 初始圖示 (前置模式：🤳)
    [magicBtn setTitle:@"🤳" forState:UIControlStateNormal];
    magicBtn.titleLabel.font = [UIFont systemFontOfSize:24]; // Emoji 大小
    
    // --- 事件綁定 ---
    [magicBtn addTarget:self action:@selector(toggleCameraMode:) forControlEvents:UIControlEventTouchUpInside];

    // 拖曳手勢
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [magicBtn addGestureRecognizer:panGesture];

    [controller.view addSubview:magicBtn];
}

// 處理拖曳 (保持懸浮手感)
%new
-(void)handlePan:(UIPanGestureRecognizer *)sender {
    UIViewController *controller = (UIViewController *)self;
    UIView *button = sender.view;
    CGPoint translation = [sender translationInView:controller.view];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [sender setTranslation:CGPointZero inView:controller.view];
}

// 處理點擊 (熱切換 + UI 變化)
%new
-(void)toggleCameraMode:(UIButton *)sender {
    useRearCamera = !useRearCamera;

    // --- 更新 UI 狀態 ---
    if (useRearCamera) {
        // 開啟後置：變綠色，圖示變相機
        [UIView animateWithDuration:0.2 animations:^{
            sender.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.8]; // 漂亮的綠色
            sender.layer.borderColor = [UIColor whiteColor].CGColor;
            sender.transform = CGAffineTransformMakeScale(1.1, 1.1); // 按下時稍微變大
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.1 animations:^{
                sender.transform = CGAffineTransformIdentity; // 恢復大小
            }];
        }];
        [sender setTitle:@"📸" forState:UIControlStateNormal];
        
    } else {
        // 切回前置：變回半透明黑，圖示變自拍
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

    // --- 執行熱切換手術 ---
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
}
