#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// 宣告 MirrorViewController (UI)
@interface AzarMain_MirrorViewController : UIViewController
@end

// 全域開關
static BOOL useRearCamera = NO; 

// ==========================================
// 🔥 核心邏輯：攔截 AVCaptureDeviceInput
// ==========================================
%hook AVCaptureDeviceInput

+ (instancetype)deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    
    // 如果開關開啟，且 App 試圖使用「前置鏡頭」
    if (useRearCamera && device.position == AVCaptureDevicePositionFront) {
        
        AVCaptureDevice *backCamera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera 
                                                                         mediaType:AVMediaTypeVideo 
                                                                          position:AVCaptureDevicePositionBack];
        
        if (backCamera) {
            return %orig(backCamera, outError);
        }
    }
    return %orig;
}

- (AVCaptureDevice *)device {
    AVCaptureDevice *realDevice = %orig;
    // 騙 App 說這是前置鏡頭 (雖然實際上我們可能換成了後置)
    return realDevice;
}

%end


// ==========================================
// 🎨 UI 邏輯：懸浮按鈕 (可拖動版)
// ==========================================
%hook AzarMain_MirrorViewController

-(void)viewDidLoad {
    %orig;

    // 1. 建立按鈕
    UIButton *magicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    magicBtn.frame = CGRectMake(100, 150, 60, 40); // 初始位置
    magicBtn.backgroundColor = [UIColor redColor];
    [magicBtn setTitle:@"前" forState:UIControlStateNormal];
    magicBtn.layer.cornerRadius = 20;
    magicBtn.layer.borderWidth = 2;
    magicBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    
    // 2. 設定點擊事件 (切換鏡頭)
    [magicBtn addTarget:self action:@selector(toggleCameraMode:) forControlEvents:UIControlEventTouchUpInside];

    // 3. 🔥 新增拖曳手勢 (讓按鈕可以移動)
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [magicBtn addGestureRecognizer:panGesture];

    // 4. 加到畫面上
    UIViewController *controller = (UIViewController *)self;
    [controller.view addSubview:magicBtn];
}

// 處理拖曳手勢的方法
%new
-(void)handlePan:(UIPanGestureRecognizer *)sender {
    UIViewController *controller = (UIViewController *)self;
    UIView *button = sender.view;
    
    // 獲取手指移動的距離
    CGPoint translation = [sender translationInView:controller.view];
    
    // 更新按鈕的中心點位置
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    
    // 重置移動距離 (避免累加)
    [sender setTranslation:CGPointZero inView:controller.view];
}

// 切換模式的方法
%new
-(void)toggleCameraMode:(UIButton *)sender {
    useRearCamera = !useRearCamera;

    if (useRearCamera) {
        sender.backgroundColor = [UIColor greenColor];
        [sender setTitle:@"後" forState:UIControlStateNormal];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已開啟後置模式" 
                                                                       message:@"請滑動切換濾鏡，或重新進入視訊，以刷新攝像頭。" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        
        UIViewController *controller = (UIViewController *)self;
        [controller presentViewController:alert animated:YES completion:nil];
        
    } else {
        sender.backgroundColor = [UIColor redColor];
        [sender setTitle:@"前" forState:UIControlStateNormal];
    }
}

%end

%ctor {
    %init(AzarMain_MirrorViewController = objc_getClass("AzarMain.MirrorViewController"));
}
