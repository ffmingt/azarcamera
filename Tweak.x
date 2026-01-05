#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// ---------------------------------------------------------
// 1. 宣告與全域變數
// ---------------------------------------------------------

// 讓編譯器認識這個類別
@interface AzarMain_MirrorViewController : UIViewController
@end

// 全域變數：紀錄目前是否要強制使用後置鏡頭
static BOOL useRearCamera = NO; 

// 全域變數：抓取目前正在運作的相機 Session (靈魂核心)
static AVCaptureSession *currentSession = nil;

// ---------------------------------------------------------
// 2. 綁架相機 Session (為了之後能熱切換)
// ---------------------------------------------------------
%hook AVCaptureSession

// 當 App 啟動相機時，我們趕快把 Session 記下來
- (void)startRunning {
    currentSession = self; // 抓到了！
    %orig;
}

// 為了保險，添加輸入時也更新一下
- (void)addInput:(AVCaptureInput *)input {
    currentSession = self;
    %orig;
}

%end

// ---------------------------------------------------------
// 3. 攔截輸入 (防止 App 自己切回去)
// ---------------------------------------------------------
%hook AVCaptureDeviceInput

+ (instancetype)deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    // 雙重保險：如果開關是開的，不管 App 要什麼，都給它後置
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
// 4. UI 與熱切換邏輯 (懸浮按鈕)
// ---------------------------------------------------------
%hook AzarMain_MirrorViewController

-(void)viewDidLoad {
    %orig;

    // --- 建立按鈕 ---
    UIButton *magicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    magicBtn.frame = CGRectMake(100, 150, 60, 40);
    magicBtn.backgroundColor = [UIColor redColor];
    [magicBtn setTitle:@"前" forState:UIControlStateNormal];
    magicBtn.layer.cornerRadius = 20;
    magicBtn.layer.borderWidth = 2;
    magicBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    
    // 點擊事件
    [magicBtn addTarget:self action:@selector(toggleCameraMode:) forControlEvents:UIControlEventTouchUpInside];

    // 拖曳手勢
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [magicBtn addGestureRecognizer:panGesture];

    UIViewController *controller = (UIViewController *)self;
    [controller.view addSubview:magicBtn];
}

// 處理拖曳
%new
-(void)handlePan:(UIPanGestureRecognizer *)sender {
    UIViewController *controller = (UIViewController *)self;
    UIView *button = sender.view;
    CGPoint translation = [sender translationInView:controller.view];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [sender setTranslation:CGPointZero inView:controller.view];
}

// 處理點擊 (重點在這裡：熱切換！)
%new
-(void)toggleCameraMode:(UIButton *)sender {
    useRearCamera = !useRearCamera;

    // 更新按鈕外觀
    if (useRearCamera) {
        sender.backgroundColor = [UIColor greenColor];
        [sender setTitle:@"後" forState:UIControlStateNormal];
    } else {
        sender.backgroundColor = [UIColor redColor];
        [sender setTitle:@"前" forState:UIControlStateNormal];
    }

    // --- 🔥 核彈級操作：強制熱切換 Session ---
    if (currentSession) {
        [currentSession beginConfiguration]; // 暫停引擎

        // 1. 移除舊的鏡頭輸入
        for (AVCaptureInput *input in currentSession.inputs) {
            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                // 只要是視訊輸入，通通拔掉
                AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
                    [currentSession removeInput:input];
                }
            }
        }

        // 2. 準備新的鏡頭 (根據開關狀態)
        AVCaptureDevicePosition targetPos = useRearCamera ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
        AVCaptureDevice *newDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera 
                                                                        mediaType:AVMediaTypeVideo 
                                                                         position:targetPos];

        // 3. 插上新鏡頭
        if (newDevice) {
            NSError *err = nil;
            AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:newDevice error:&err];
            if (newInput && [currentSession canAddInput:newInput]) {
                [currentSession addInput:newInput];
            }
        }

        [currentSession commitConfiguration]; // 重啟引擎 (畫面會在這裡切換)
    }
}

%end

%ctor {
    %init(AzarMain_MirrorViewController = objc_getClass("AzarMain.MirrorViewController"));
}
