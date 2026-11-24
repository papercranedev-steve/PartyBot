# PartyBot

[EternityCore](https://github.com/papercranedev-steve/EternityCore) 服务器的伙伴插件，用于 1.14.2 Classic 客户端：招募伙伴、和他们交谈，查看他们的背包、资料、天赋和任务。

Companion addon for the [EternityCore](https://github.com/papercranedev-steve/EternityCore) server (1.14.2 Classic client): recruit companions, talk to them, and manage their bags, character sheet, talents and quests.

## 安装 / Install

把 `PartyBot` 和 `PartyBot_Language` 两个文件夹复制到 `World of Warcraft\_classic_era_\Interface\AddOns\`。客户端要通过 [EternalProxy](https://github.com/papercranedev-steve/EternalProxy) 连接 EternityCore 服务器。

Copy the `PartyBot` and `PartyBot_Language` folders into `World of Warcraft\_classic_era_\Interface\AddOns\`. The client connects to an EternityCore server through [EternalProxy](https://github.com/papercranedev-steve/EternalProxy).

## 文案 / Text

所有文案都在 `i18n/PartyBot/<语言>.json`，`zh.json` 是基准。改完后运行：

All text lives in `i18n/PartyBot/<lang>.json` (`zh.json` is the base). After editing, run:

```
node tools/i18n.mjs build    # 生成 PartyBot/Locales/*.lua / write PartyBot/Locales/*.lua
node tools/i18n.mjs check    # 检查 / check
```
