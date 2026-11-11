# 电视更新自动发布

在 GitHub 发布 Release 时附上一个 ARMv7 安装包，文件名以 `-armeabi-v7a.apk` 结尾。Release 标签使用 `1.0.32` 或 `v1.0.32` 这样的版本号，APK 的版本名称须与标签版本一致。上传同一个电视独立版的包名和签名，供现有安装覆盖升级。

发布后，Actions 中的 **Deploy TV update** 会下载 APK，验证签名、架构、包名和版本，再通过专用 SSH 账号上传。需要重试时，可在该工作流手动填写已发布的标签并运行。

VPS 通过 Caddy 提供 `/srv/blt-updates/`。部署脚本先验证完整文件和 SHA-256，再替换 `latest.json`，随后按 APK 内的 Android 版本号仅保留最新和次新。电视继续通过应用内「检查更新」读取清单。已安装的应用数据随系统覆盖安装保留。

服务器入口是 `/usr/local/bin/blt-publish`，由 `blt-deploy` 专用账号的 SSH 强制命令调用。脚本源码在 `scripts/publish_tv_update.py`。临时文件和版本记录在 `/srv/blt-update-staging/`，位于下载目录外。Actions 使用仓库 Secret `BLT_VPS_DEPLOY_KEY` 和 `BLT_VPS_KNOWN_HOSTS`。
