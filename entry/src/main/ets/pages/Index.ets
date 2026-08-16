import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';

// 固定连接本机后端（出于安全考虑，不支持远程地址配置）
const BACKEND_URL: string = 'http://127.0.0.1:8080/';
const PROBE_INTERVAL_MS: number = 2000;
const FAIL_LIMIT: number = 5;

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  @State uiState: string = 'connecting'; // connecting | error | hidden
  @State errorText: string = '';
  private timerId: number = -1;
  private failCount: number = 0;

  aboutToAppear(): void {
    this.timerId = setInterval(() => {
      this.probe();
    }, PROBE_INTERVAL_MS);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
    }
  }

  private probe(): void {
    const req: http.HttpRequest = http.createHttp();
    req.request(BACKEND_URL, {
      method: http.RequestMethod.GET,
      connectTimeout: 2000,
      readTimeout: 3000,
      expectDataType: http.HttpDataType.STRING
    }).then((resp: http.HttpResponse) => {
      const code: number = resp.responseCode;
      if (code >= 200 && code < 500) {
        this.backendUp();
      } else {
        this.backendDown('HTTP ' + code);
      }
    }).catch(() => {
      this.backendDown('连接失败');
    }).finally(() => {
      req.destroy();
    });
  }

  private backendUp(): void {
    this.failCount = 0;
    let current: string = '';
    try {
      current = this.controller.getUrl();
    } catch (e) {
      // controller 未就绪
    }
    // 页面地址与后端地址不一致，或之前处于错误态 → 重新加载
    if (current !== BACKEND_URL || this.uiState === 'error') {
      this.uiState = 'connecting';
      this.reloadPage();
    }
  }

  private backendDown(reason: string): void {
    this.failCount++;
    if (this.failCount >= FAIL_LIMIT && this.uiState !== 'error') {
      this.uiState = 'error';
      this.errorText = '无法连接 DSH 后端（' + reason + '）\n请确认 dsh web 已在本机启动';
    }
  }

  private reloadPage(): void {
    try {
      this.controller.loadUrl(BACKEND_URL);
    } catch (e) {
      // controller 未就绪时忽略，Web 组件加载时会自动请求
    }
  }

  private openInBrowser(url: string): void {
    try {
      this.context.openLink(url);
    } catch (e) {
      // openLink 失败时兜底：不拦截，让 WebView 内部导航
    }
  }

  build() {
    Stack() {
      Web({ src: BACKEND_URL, controller: this.controller })
        .width('100%')
        .height('100%')
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .onPageEnd(() => {
          this.uiState = 'hidden';
        })
        .onLoadIntercept((event) => {
          const url: string = event.data.getRequestUrl();
          // 仅拦截主框架的外站 http/https 链接，站内导航放行
          if (event.data.isMainFrame() && url.indexOf('://') >= 0 && !url.startsWith(BACKEND_URL)) {
            this.openInBrowser(url);
            return true;
          }
          return false;
        })

      if (this.uiState === 'connecting') {
        Column({ space: 16 }) {
          LoadingProgress()
            .width(64)
            .height(64)
            .color('#0A59F7')
          Text('正在连接 DSH 服务…')
            .fontSize(16)
            .fontColor('#666666')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F5F6F8')
      } else if (this.uiState === 'error') {
        Column({ space: 16 }) {
          Text('⚠')
            .fontSize(56)
          Text(this.errorText)
            .fontSize(15)
            .fontColor('#333333')
            .textAlign(TextAlign.Center)
          Button('重试')
            .fontSize(16)
            .onClick(() => {
              this.uiState = 'connecting';
              this.failCount = 0;
              this.reloadPage();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#F5F6F8')
      }
    }
    .width('100%')
    .height('100%')
  }
}
