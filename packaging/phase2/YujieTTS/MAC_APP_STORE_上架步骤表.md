# Mac App Store 上架步骤表（黑鲸自定义克隆 TTS / YujieTTS）

> 用法：按序号做，做完一项在前面打 `[x]`。无法由 AI 代劳的步骤已标注 **（须本人）**。

## 阶段 A：账号与 App Store Connect

- [ ] **1** — **（须本人）** 已加入 [Apple Developer Program](https://developer.apple.com/programs/)（年费约 $99），并能用该 Apple ID 登录 [developer.apple.com](https://developer.apple.com) 与 [App Store Connect](https://appstoreconnect.apple.com）。  
  - **当前：** 若已付款但账号尚未生效，通常 **24～48 小时内** 会开通；生效前无法创建分发证书与在 Connect 中完成全部操作，可先完成本仓库 **阶段 B 冷启动测试**、**启用 GitHub Pages（见文末）** 与 **截图**。

- [ ] **2** — **（须本人）** 在 App Store Connect →「App」→「+」新建 **Mac App**：名称、主要语言、Bundle ID 选 **`com.blackwhale.YujieTTS`**（须与 Xcode 一致）。若 ID 未出现，先在 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) 注册该 App ID 并勾选 **Mac**。

- [ ] **3** — **（须本人）** 若含 **付费 App / 内购**：在 App Store Connect 完成 **协议、税务、银行账户**（付费应用相关协议）。

- [ ] **4** — **（须本人）** 在 App Store Connect → 该 App →「App 内购买项目」创建与代码一致的商品：
  - 消耗型：`com.blackwhale.YujieTTS.genpack10`
  - 非消耗型：`com.blackwhale.YujieTTS.lifetime`  
  填好参考名称、审核备注（说明首次免费 + 次数包 + 永久），提交商品供审核（可与 App 首审一起或先行）。

## 阶段 B：可下载资源（否则用户无法完成首次引导）

- [ ] **5** — 在本机用仓库脚本打出两个包（需已配置好 conda 环境 `qwen3-tts-mac-genelab`）：
  ```bash
  cd /path/to/Qwen3-TTS-Mac-GeneLab
  bash packaging/phase2/scripts/build_env_pack.sh
  ```
  得到 `dist/yujie-python-env.tar.gz` 与 `dist/yujie-project-src.tar.gz`。

- [ ] **5b** — **（App Store 必做）** 将上述两包 **打进 App 资源**，随商店安装一并下发（**消除用户首启从 GitHub 拉环境**）：
  ```bash
  cd /path/to/Qwen3-TTS-Mac-GeneLab/packaging/phase2/YujieTTS
  bash prepare_bootstrap_resources.sh
  ```
  成功后 `YujieTTS/Resources/bootstrap/` 下有两枚 `.tar.gz`，再 **Clean + Archive**。大包已 `.gitignore`，勿提交进 Git。

- [x] **6** — **商店用户：** 优先使用 **`Contents/Resources/bootstrap/`** 内归档（与 Apple CDN 同步到达）。**GitHub Release** [`Blackwhalee/-tts` · `v1.0`](https://github.com/Blackwhalee/-tts/releases/tag/v1.0) 仅作 **开发与包内缺失时的回退**。

- [ ] **7** — **（建议）** 在 **Apple Silicon** Mac 上删除应用容器数据后冷启动，验证：**解压引导包 → 拉模型 → 进入主界面**。  
  - **环境与源码：** 正式包从 **应用内 `bootstrap`** 安装，不经外网（见 5b）。**语音模型** 仍约 **2.9GB**，需访问 **Hugging Face**（与 App Store CDN 无关；国内仍可能慢，审核备注中说明）。若将来要把模型也放进包内，体积会再增数 GB，需单独评估。  
  - **开发调试：** 可将 `dist/yujie-*.tar.gz` 放 **`~/Qwen3-TTS-Mac-GeneLab/dist/`** 或未打 bootstrap 时使用 GitHub 回退。  
  - **清除半装状态：** 退出 App，删掉沙盒内 **`Application Support/YujieTTS`**（访达可搜 `YujieTTS`）。

## 阶段 C：Xcode 工程与签名

- [ ] **8** — 打开 `packaging/phase2/YujieTTS/YujieTTS.xcodeproj`，在 Target「YujieTTS」→ **Signing & Capabilities**：
  - Team 选你的开发者团队；
  - **Automatically manage signing** 勾选；
  - Bundle Identifier = `com.blackwhale.YujieTTS`。

- [ ] **9** — 确认 **Release** 配置可编译：`Product → Scheme → Edit Scheme → Run/Archive 的 Build Configuration` 在归档时用 **Release**。

- [ ] **10** — **（上架前）** 若把 `python-env` 打进用户数据或包内：对其中 Mach-O 执行分发签名（见 `packaging/phase2/scripts/sign_python_env_for_appstore.sh` 说明），避免 Upload 校验失败。

## 阶段 D：归档、校验、上传

- [ ] **11** — 菜单 **Product → Archive**，等待归档完成。

- [ ] **12** — 在 Organizer 中选该归档 → **Validate App**，按提示修复错误直至通过。

- [ ] **13** — **Distribute App** → **App Store Connect** → Upload，等待处理完成（App Store Connect 中构建显示「处理完成」）。

## 阶段 E：商店页与审核材料

- [ ] **14** — **（须本人）** 在 App Store Connect 填写：副标题、描述、关键词、**隐私政策 URL**、支持 URL、分类、年龄分级、**App 隐私**问卷、截图（Mac 窗口尺寸按苹果要求）。

- [ ] **15** — 选择刚上传的构建版本，关联内购商品（若适用法律），填写 **审核备注**：**Python 环境与源码已内置在 App 包内**；首次使用需 **联网下载 HF 模型**（约 2.9GB）；测试账号若有请附上。

- [ ] **16** — 点击 **提交以供审核**，等待结果；被拒后按 Resolution Center 修改再传构建。

---

## 当前进度（手写更新）

- 进行到哪一步：第 ___ 步  
- 日期：______

---

## 并行准备（会员未生效时也可做）

| 项目 | 状态 | 说明 |
|------|------|------|
| Xcode Release 编译 | ✅ 已在 CI/本机验证通过 | `Release` 配置可 `Archive` |
| `build_env_pack.sh` 打出 dist 两包 | ✅ 已在仓库机器跑通 | 产物：`dist/yujie-python-env.tar.gz`、`dist/yujie-project-src.tar.gz`；脚本已加 `--ignore-missing-files`；请用 **conda 环境里的** `python -m pip install .` |
| 环境与源码进 App 包（bootstrap） | ✅ 流程已接入 | **上架前**执行 `prepare_bootstrap_resources.sh`；用户从商店安装即可本地解压，**不依赖 GitHub 速度** |
| HTTPS 回退（GitHub） | ✅ 已配置 | 仅包内缺失时使用；见 `EnvironmentManager` |
| `main` 推送到远端 | ✅ 已做 | 远端：`https://github.com/Blackwhalee/Qwen3-TTS-Mac-GeneLab`（与 `hiroki-abe-58` 无关；引导包 Release 仍在 [`Blackwhalee/-tts` · v1.0](https://github.com/Blackwhalee/-tts/releases/tag/v1.0)） |
| 隐私政策 / 支持页 URL | ✅ 草案已提交仓库 | 源文件：`docs/privacy-policy.html`、`docs/support.html`；**对外 URL** 须在 GitHub 启用 Pages 后填入 Connect（见下方「上架用静态页」） |
| 冷启动全流程实测 | ⬜ 待做 | 配好 URL 或把 tar 放 `~/.../dist/` 测首次引导 |

---

## 上架用静态页（隐私政策 / 支持 URL）

仓库已包含可公开托管的 HTML（`docs/`）。**开发者计划生效后**，在 GitHub 打开 **`Blackwhalee/Qwen3-TTS-Mac-GeneLab`** → **Settings** → **Pages** → **Build and deployment**：Source 选 **Deploy from a branch**，Branch 选 **`main`**，文件夹选 **`/docs`** → Save。

约 1～2 分钟后可访问（将下面 `你的用户名` 若为组织则替换）：

- 隐私政策 URL（填 App Store Connect）：`https://blackwhalee.github.io/Qwen3-TTS-Mac-GeneLab/privacy-policy.html`
- 支持 URL：`https://blackwhalee.github.io/Qwen3-TTS-Mac-GeneLab/support.html`

若 Pages 使用自定义域名，把上述域名换成你的域名即可。
