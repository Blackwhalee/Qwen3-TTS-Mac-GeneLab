随 App Store 分发用的「环境与源码」归档放置于此目录（上架构建前生成）。

生成方式（在 GeneLab 仓库根目录）：
  bash packaging/phase2/scripts/build_env_pack.sh

打包进 App（在包含本 Xcode 工程的目录执行）：
  bash packaging/phase2/YujieTTS/prepare_bootstrap_resources.sh

成功后此处应有：
  yujie-python-env.tar.gz
  yujie-project-src.tar.gz

再从 Xcode 执行 Product → Archive。商店用户首启将从本机应用包解压安装，无需从 GitHub 下载上述两包。

注意：大文件不应提交到 Git（见仓库 .gitignore）。Mach-O 分发签名见 packaging/phase2/scripts/sign_python_env_for_appstore.sh
