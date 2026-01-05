#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// 宣告我们要 Hook 的类 (讓編譯器知道它的存在)
@interface AzarMain_MirrorViewController : UIViewController
@end

// --- 全域變數：紀錄目前是否要強制使用後置鏡頭 ---
static BOOL useRearCamera = NO; // 預設關閉 (使用正常前置)

// --- Part 1: 核心邏輯 (欺騙攝像頭) ---
%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithDeviceType:(AVCaptureDeviceType)deviceType
                                       mediaType:(AVMediaType)mediaType
                                        position:(AVCaptureDevicePosition)position {

    // 如果 App 請求的是「前置鏡頭」(Front) 且 我們的開關是「開啟」的
    if (position == AVCaptureDevicePositionFront && useRearCamera) {
        // 強行返回「後置鏡頭」(Back)
        return %orig(deviceType, mediaType, AVCaptureDevicePositionBack);
    }
    return %orig;
}

%end

// --- Part 2: UI 介面 (懸浮按鈕) ---

%hook AzarMain_MirrorViewController

-(void)viewDidLoad {
    %orig; // 執行原本的程式碼

    // 建立一個按鈕
    UIButton *magicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    magicBtn.frame = CGRectMake(100, 150, 60, 40); // 位置: x=100, y=150
    magicBtn.backgroundColor = [UIColor redColor]; // 預設紅色 (代表未開啟)
    [magicBtn setTitle:@"前" forState:UIControlStateNormal];
    magicBtn.layer.cornerRadius = 20;
    magicBtn.layer.borderWidth = 2;
    magicBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    
    // 設定點擊事件
    [magicBtn addTarget:self action:@selector(toggleCameraMode:) forControlEvents:UIControlEventTouchUpInside];

    // --- 關鍵修正：強制告訴編譯器 self 是 UIViewController ---
    // 這樣它就一定找得到 .view 屬性了
    UIViewController *controller = (UIViewController *)self;
    [controller.view addSubview:magicBtn];
}

// 新增按鈕點擊後的動作
%new
-(void)toggleCameraMode:(UIButton *)sender {
    // 1. 切換開關狀態
    useRearCamera = !useRearCamera;

    // 2. 改變按鈕外觀給提示
    if (useRearCamera) {
        sender.backgroundColor = [UIColor greenColor]; // 綠色代表開啟 (後置)
        [sender setTitle:@"後" forState:UIControlStateNormal];
        
        // 彈出提示
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已切換至後置模式" 
                                                                       message:@"請重新進入視訊聊天，或點擊兩下畫面來刷新攝像頭。" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        
        // --- 這裡也一樣，為了安全起見，強制轉型後再 Present ---
        UIViewController *controller = (UIViewController *)self;
        [controller presentViewController:alert animated:YES completion:nil];
        
    } else {
        sender.backgroundColor = [UIColor redColor]; // 紅色代表關閉 (前置)
        [sender setTitle:@"前" forState:UIControlStateNormal];
    }
}

%end

// --- 初始化 Swift 類別 ---
%ctor {
    // 因為 Azar 是 Swift 寫的，我們要告訴 Tweak 這是哪個類別
    %init(AzarMain_MirrorViewController = objc_getClass("AzarMain.MirrorViewController"));
}
