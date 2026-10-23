# 醒课 WakeClass

> 手机优先的大学课程表 App：**直接从教务系统导入课表**，也支持**截图 OCR 识别**。
> 自动生成可编辑的周课表，并附带**课前提醒**与**桌面小组件**。

Flutter 应用 + 纯 Dart 领域包（零 Flutter 依赖）。已在真机上跑通两类教务系统：
**金智 CAS 统一认证 + URP（eams）** 与 **强智 jsxsd**。

<p>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-%E2%89%A53.27-02569B?logo=flutter&logoColor=white">
  <img alt="Dart" src="https://img.shields.io/badge/Dart-%E2%89%A53.4-0175C2?logo=dart&logoColor=white">
  <img alt="Android" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-yellow.svg">
</p>

---

## 功能特性

### 导入（两条路线，同一套校对页）

- **教务直连**：填教务系统地址 + 学号 + 密码，自动识别系统类型
  - **适配器架构**：所有厂商统一走 `JwxtAdapter` 接口（`detect → prepare → login`），
    UI 不按厂商分支；新增一所学校 = 新增一个适配器文件
  - **正方教务（jwglxt）**：登录页 `csrftoken` + `login_getPublicKey` 的 RSA 公钥，
    密码按学校同样的 PKCS#1 v1.5 规则加密后提交 → `kbcx/xskbcx_cxXsKb.html` 的
    `kbList` JSON（节次 / 周次 / 地点 / 教师）→ 失败时回退 HTML 表格解析
  - **强智 jsxsd**：登录表单探测 → 课表页（`xskb/xskb_list.do`）→ 学期选择 → HTML 解析
  - **统一认证（CAS）+ URP**：金智 CAS 登录页探测（`execution` / 加密盐）→ 按官方 `encrypt.js`
    规则做 AES-CBC 密码加密 → 票据 302 跳转（含 `;jsessionid=` URL 重写）→ 定位 URP 课表页
  - **通用（自动识别）**：兜底适配器，自动找页面里的登录表单（学号/密码/隐藏字段/验证码图片）→
    登录后依次尝试「当前页 → 页面里的课表链接 → 常见课表路径」→ 通用表格解析
    （表头找周一..周日、行首找节次、单元格复用 OCR 的文本解析规则）
  - **支持图片验证码**：展示验证码图片、人工输入（不绕过、不破解）
  - 账号密码只在内存里用于这一次登录请求，**不写入任何存储**
- **截图 OCR 导入**：相册选图 / 拍照 → 端上识别（Google ML Kit，离线、支持中文）
  → 网格解析 → 校对页
  - 表头（星期列）+ 节次行自动推断，兼容 12 行单节次 / 6 行双节次两种课表形态
  - 合并单元格（rowspan）、一格多课、单双周（`3-15周(单)`）自动处理
- **校对页**：识别结果逐门勾选 / 编辑 / 删除，展示告警与未识别文本

### 课表

- 七天一屏、表头显示日期、**今天加深高亮**、**左右滑动切上一周 / 下一周**、
  点击周次文字回到本周、只显示当前周的课程
- **打开即停在当前周**（不再从第 1 周开始翻）
- 课程块随屏幕高度自适应、列分界线直达屏幕底部、冲突红框提示
- **点课程即可换颜色**：20 色课程色板，改完立刻生效（课表 + 桌面小组件同步）
- 顶部栏：左上角桌面小组件入口；中间周次与设置齿轮同排；右侧导入（纯图标）

### 上课时间（自定义作息）

- 设置 → 上课时间：第 1 节几点开始、每节多少分钟、课间休息多久、每天几节课，
  一键生成全天作息；也可以点某一节单独微调（应对「第 3 节 10:10」「下午 14:00」这类特殊安排）
- 课表时间轴、课程提醒、桌面小组件倒计时**全部使用这套时间**

### 外观

- **主题色**：10 种预设一键换色（影响按钮、高亮等）
- **背景颜色**：12 种浅色底（纸感米白 / 纯白 / 暖沙 / 浅灰 / 薄荷 / 天蓝 …），可单独更换

### 课程提醒

- 设置页开关 + 提前 5 / 10 / 15 / 20 / 30 分钟可选
- 本地通知（`flutter_local_notifications` + `timezone`）提醒课程名、教室、节次时间
- 使用**精确闹钟**（`SCHEDULE_EXACT_ALARM`），一次排程未来 60 天，回到前台自动补排
- 设置页可查看「已排程 N 条」、一键重新排程、发测试通知（立即 + 10 秒后各一条）

### 桌面小组件（Android）

三种尺寸：**小 4×2（同时 2 门）** / **中 4×4（3 门）** / **大 4×5（4 门）**

- 整体铺一层**自定义底色**，上半 1/5 是自定义文字（≤6 字）+ 日期/周次/周几
- 下半 4/5 是**白色圆角面板**，课程按数量**平均等分**（两门课就各占一半），四周露出底色
- 每行：左侧上课/下课时间 + 课程色条（跟随课程自定义颜色）+ 课程名 + 「节次 · 地点 · 教师」+ 倒计时
- 只显示**今天还没上完的课**：上完一门自动移除、后面的课补上来；全部上完显示「(〃'▽'〃) 今天没有课啦」
- **8 套配色**可选，App 内实时预览，支持一键添加到桌面（Android 8+ 系统弹窗）
- 每分钟自动刷新，跨天自动切到新一天课表

### 其他

- **演示导入**：内置一份模拟识别结果（14 门课），无需真机即可体验全流程
- **本地存储**：`shared_preferences` JSON；设置页支持学期信息、JSON 备份 / 恢复、清空课表
- **Web 端可跑**：`flutter build web` 直接出静态站（ML Kit 不支持 Web，自动降级为演示导入）

---

## 仓库结构

```text
.
├── app/                        # Flutter 应用（Android / Web）
│   ├── lib/
│   │   ├── pages/              # 课表主页 / 导入 / 教务直连 / 校对 / 课程编辑 / 设置 / 小组件设置
│   │   ├── widgets/            # 周课表网格
│   │   ├── services/
│   │   │   ├── jwxt/           # 教务直连：适配器 + 正方/强智/CAS/通用 + HTML 解析 + RSA
│   │   │   ├── ocr/            # ML Kit OCR 引擎（Web 端条件导出占位实现）
│   │   │   ├── import/         # 截图导入流程与统一预览模型
│   │   │   ├── notifications/  # 课前提醒调度
│   │   │   ├── storage/        # 本地 JSON 存储
│   │   │   └── widget/         # 桌面小组件桥接与配置
│   │   ├── model/              # ScheduleModel（状态 + 持久化）、ThemeModel、PeriodModel（作息）
│   │   └── theme.dart          # 暖色纸感主题
│   ├── android/                # 原生壳：3 个 AppWidgetProvider + 每分钟刷新 + pin 请求
│   ├── test/                   # widget 测试 + 解析测试 + 两套端到端集成测试 + 模拟教务系统
│   └── tool/                   # 真机/真实系统诊断脚本
├── packages/wakeclass_core/    # 纯 Dart 领域包（零 Flutter 依赖）
│   ├── lib/src/grid/           # GridParser：OCR 文本块 → 课程网格
│   ├── lib/src/parsing/        # 周次解析、单元格文本解析、节次时间、作息设置（PeriodSettings）
│   ├── lib/src/models/         # Course / Schedule / OcrTextBlock / RawCell
│   └── test/                   # 纯 Dart 单元测试（独立 Dart SDK 可跑）
└── docs/技术方案.md             # 完整技术方案（架构、解析算法、教务适配层）
```

---

## 快速开始

### 1. 环境

- Flutter ≥ 3.27（Dart ≥ 3.4），用 Flutter 自带 Dart 即可
- Android 构建：JDK 17+（CI 用 21）、Android SDK（compileSdk 36）

```bash
flutter --version
flutter doctor
```

### 2. 运行

```bash
cd app
flutter pub get
flutter run                     # Android 真机 / 模拟器
flutter run -d chrome           # Web（自动降级为演示导入）
```

### 3. 测试

```bash
# 应用：widget 测试 + 解析测试 + 端到端集成测试
cd app
flutter test

# 领域包：纯 Dart 单元测试
cd ../packages/wakeclass_core
dart pub get
dart test
```

两套端到端集成测试依赖本地模拟教务系统（未启动时相关用例会失败，可先启动再跑）：

```bash
# 在 app/ 目录下
node test/mock_jwxt.mjs        # 强智模拟  127.0.0.1:8788  账号 2026002/qzpass
node test/mock_cas_urp.cjs     # CAS+URP 模拟 127.0.0.1:8790 账号 2026003/caspass
                               #   账号 captchauser 触发验证码流程，验证码 1234
node test/mock_jwxt_universal.cjs  # 正方 + 通用 模拟 127.0.0.1:8791
                               #   正方 /jwglxt 账号 2026005/zfpass
                               #   通用 /gen/login.jsp 账号 2026004/genpass
```

### 4. 构建安装包

```bash
cd app
flutter build apk --release    # 产物：build/app/outputs/flutter-apk/app-release.apk
```

> APK 约 92 MB：包含全部 CPU 架构与 ML Kit 离线中文识别模型。
> 仓库不提交安装包，需要的版本请到 **Releases** 下载。

---

## 使用说明

### 教务直连

1. 主页点「导入」→「教务直连」
2. 系统类型默认「**自动识别**」：
   - 地址含 `jwglxt` / `xtgl` → 正方教务
   - 含 `jsxsd` → 强智教务
   - 含 `authserver` / `cas` / `eams` → 统一认证（CAS）
   - 其它 → 通用适配器（自动找登录表单与课表页）
   识别不准时可以手动选择
3. 粘贴**浏览器地址栏里登录页的完整地址**（统一认证需带 `service=` 参数）、学号、密码；
   学期可留空（正方会读页面里的当前学年学期）
4. 若登录需要验证码，页面会自动显示验证码图片，输入后提交
5. 识别结果进入校对页核对，点「追加导入」或「覆盖导入」

> 统一认证方式仅支持「账号密码 + 可选图片验证码」；微信扫码 / 短信验证码 / 滑块等
> 登录方式无法自动完成，请改用截图导入。
>
> 通用适配器是兜底：换了学校、换了系统，先试它；仍不行就用截图导入（任何系统都能截图）。

### 截图导入

1. 手机打开教务系统课表页，截一张**完整**的课表图（要包含顶部星期表头和左侧节次列）
2. 主页点「导入」→「截图导入」→「从相册选择」
3. 等待识别完成，进入校对页核对：课程名、教师、周次、地点、节次都可直接改
4. 点「追加导入」或「覆盖导入」

### 桌面小组件

1. 课表页**左上角**点小组件图标（或 设置 → 桌面小组件）
2. 选尺寸（小 4×2 / 中 4×4 / 大 4×5）、选配色、改左上角文字（≤6 字），上方实时预览
3. 点「添加到桌面」：
   - 支持的桌面会弹出系统确认框，确认即可
   - **MIUI / HyperOS 等品牌桌面会忽略该请求**（API 返回成功但不弹窗），
     面板会直接列出手动添加步骤：长按桌面空白处 → 小组件 → 搜「醒课」→ 拖到桌面

> 小组件随时间自动刷新：上完一门课就少一门，全部上完显示「今天没有课啦」。

### 课程提醒收不到 / 不准？

1. 设置 → 课程提醒：确认开关已开、通知权限已授予（Android 13+）
2. 看「精确闹钟」状态：显示**未授权**时点「去授权精确闹钟」（Android 12+ 需要单独授权，
   否则系统会把提醒延后几分钟到几小时）
3. 点「测试通知」，应立即收到一条，并再收到一条 10 秒后的定时通知
4. 小米 / 红米 / HyperOS：设置 → 应用设置 → 醒课 → **省电策略改「无限制」**，
   并允许「自启动」，否则系统可能拦截后台闹钟

---

## 技术要点

- **统一预览模型**：截图 OCR 与教务直连都产出 `ImportPreview`，共用同一个校对页与导入逻辑
- **HTML 编码自适应**：UTF-8 / GBK / 二次编码三重打分，最大概率命中中文语义
- **CAS 登录**：手工跟随 302（`followRedirects = false`）以保留 `Location` 与 `Set-Cookie`，
  登录时必须使用带新 `;jsessionid=` 的 canonical service，否则票据校验不过
- **课表解析**：URP 课表数据藏在 `new TaskActivity(...)` 的 JS 里，
  `index = 星期 * 节次数 + 节次`，周次是 53 位 bitmask；强智走 HTML 表格解析
- **教务适配器层**：`JwxtAdapter` 统一 `detect / prepare / login`，UI 不按厂商分支
  - 正方：`csrftoken` + RSA（PKCS#1 v1.5，pointycastle）加密密码 → `kbList` JSON
  - 通用：自动识别登录表单（学号/密码/hidden/验证码）→ 跟随 302 → 找「课表」链接或常见路径
    → 通用表格解析（与 OCR 共用 `parseCellText`，兼容 rowspan/colspan）
- **桌面小组件**：原生 Kotlin `AppWidgetProvider` 读 `FlutterSharedPreferences` 里的课表 JSON
  与作息 JSON，用 `RemoteViews` 渲染；`AlarmManager` 每分钟刷新一次，跨天自动切换
  - 布局只能用 RemoteViews 白名单控件（`TextView` / `ImageView` / `LinearLayout` / `FrameLayout`），
    **不能用 `android.view.View`**，否则桌面会显示「载入窗口小部件时出现问题」
  - `RemoteViews.addView` **不会保留 `layout_weight`**（实测行高退回内容高度，两门课只占上半部分），
    所以课程行是布局里**固定的 4 个分栏**（小 2 / 中 3 / 大 4），用显隐控制，而不是运行时动态添加
  - `RemoteViews` 不能改控件背景色（`setBackgroundColor` 没有 `@RemotableViewMethod`），
    课程色条用「圆角位图 + `setImageViewBitmap`」实现
- **提醒准时**：`zonedSchedule` 使用 `exactAllowWhileIdle` + 声明 `SCHEDULE_EXACT_ALARM`，
  设置页提供授权入口与测试通知；一次排程未来 60 天（上限 300 条），App 回前台时补排

---

## 已知限制

- 教务直连：内置**正方（jwglxt）**、**强智（jsxsd）**、**统一认证（CAS）+ URP**，
  其余系统由**通用适配器**兜底（表单登录 + 表格 / kbList JSON）；青果、新版 URP 移动端 API 在路线图中
- 微信扫码、短信验证码、滑块、双因子等登录方式不做绕过，请改用截图导入
- 只开放校园网 / 需要 VPN 的教务系统，手机直连会超时；请连学校 VPN 后使用
- 教务页面按 UTF-8 / GBK 自适应解析（其余编码暂不支持）
- 学校若使用 http 明文教务系统，Android 需允许明文流量（当前仅在 `AndroidManifest.xml` 中开启）；
  正式发布建议只支持 https
- 单学期单课表；多学期切换在路线图中
- OCR 准确率依赖截图质量；表格线缺失时靠坐标推断，兜底在校对页
- 端上文字识别仅 Android / iOS（ML Kit）；桌面端 / Web 自动降级为演示导入
- 桌面小组件仅 Android；部分品牌桌面（MIUI / HyperOS）不支持「一键添加」

---

## 路线图

- [x] 强智 / CAS+URP 教务直连
- [x] 截图 OCR 导入 + 校对页
- [x] 课前提醒、桌面小组件（三种尺寸 / 配色 / 倒计时）
- [x] 课程自定义颜色、页面背景色、自定义上课时间
- [x] 适配器架构 + 正方（jwglxt）+ 通用自适应登录
- [ ] 青果 KINGOSOFT、新版 URP 移动端 API
- [ ] 粘贴 HTML/JSON、Excel/ICS 文件导入
- [ ] 自定义规则引擎（任意系统，规则可分享）
- [ ] 多张截图合并导入、CAS 学期选择
- [ ] 多学期、导出 ICS、分享长图
- [ ] iOS 小组件、云备份、多设备同步

---

## 贡献

欢迎 Issue / PR：

1. Fork 本仓库并新建分支（`feat/xxx`、`fix/xxx`）
2. 提交前跑通 `flutter analyze` 与 `flutter test`（CI 也会跑）
3. PR 描述里说明动机、改动点与验证方式

新增教务系统适配时，请把解析逻辑放进 `app/lib/services/jwxt/` 并补一套本地模拟服务 +
集成测试（参考 `test/mock_cas_urp.cjs`）。

---

## 免责声明

- 本项目仅用于**个人课表管理**，请遵守所在学校的相关规章制度与教务系统的使用条款
- 账号密码只在内存中用于一次登录请求，不写入本地存储、不打印、不上传
- 不提供任何绕过验证码 / 风控 / 权限校验的能力
- 仓库内不含任何真实学生账号、密码或抓取到的课表数据

---

## 许可

[MIT](LICENSE) © WakeClass contributors
