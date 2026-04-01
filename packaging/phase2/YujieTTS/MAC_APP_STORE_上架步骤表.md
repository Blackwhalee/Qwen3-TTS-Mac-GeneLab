# Mac App Store 上架步骤表（黑鲸自定义 TTS / YujieTTS）

> 用法：按序号做，做完一项在前面打 `[x]`。无法由 AI 代劳的步骤已标注 **（须本人）**。

## 阶段 A：账号与 App Store Connect

- [ ] **1** — **（须本人）** 已加入 [Apple Developer Program](https://developer.apple.com/programs/)（年费约 $99），并能用该 Apple ID 登录 [developer.apple.com](https://developer.apple.com) 与 [App Store Connect](https://appstoreconnect.apple.com)。

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

- [x] **6** — 已托管：**GitHub Release** [`Blackwhalee/-tts` · `v1.0`](https://github.com/Blackwhalee/-tts/releases/tag/v1.0)；`EnvironmentManager.swift` 已指向 `.../releases/download/v1.0/yujie-*.tar.gz`。

- [ ] **7** — **（建议）** 在一台 **仅 Apple Silicon** 的 Mac 上删除应用容器数据后冷启动，验证能 **自动下载 → 解压 → 拉模型 → 进入主界面**（模型需能访问 Hugging Face；国内网络需自备镜像或说明）。

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

- [ ] **15** — 选择刚上传的构建版本，关联内购商品（若适用），填写 **审核备注**（测试账号若有、如何触发首次下载、HF 需网络等）。

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
| HTTPS 托管两个 `.tar.gz` | ✅ 已做 | GitHub Releases `v1.0`；代码内直链已配置 |
| `main` 推送到远端 | ⬜ 待做 | 本机：`git push origin main`（需已登录 GitHub） |
| 隐私政策 / 支持页 URL | ⬜ 待做 | 上架必填 |
| 冷启动全流程实测 | ⬜ 待做 | 配好 URL 或把 tar 放 `~/.../dist/` 测首次引导 |
