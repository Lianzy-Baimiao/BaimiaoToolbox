# Localization / 本地化

Each language has its own Lua catalog: `enUS.lua`, `zhCN.lua`, `zhTW.lua`, `koKR.lua`.
`Locale.lua` runs first, then the complete English catalog, then the matching
locale overlay. `enGB` and unsupported client locales use English. Selection is
fixed at addon load; there is no SavedVariables migration or external library.

Supported clients: Simplified Chinese (`zhCN`), Traditional Chinese (`zhTW`),
Korean (`koKR`), and English (`enUS` / `enGB`). Only official game-client locale
codes are supported; no Japanese catalog or manual language override is added.
Other client languages continue to fall back to English.

## Editing translations

- Keep message keys unchanged; edit only values in your language's file.
- Preserve printf placeholders (`%s`, `%d`, `%.1f`, `%%`), WoW color/link markup,
  and template variables such as `{target}` and `{coord}`.
- Preserve spaces around sentence fragments and intentional `\n` line breaks.
- Use concise button labels. Test the settings pages and runtime panels in game;
  strings with the same meaning still need to fit their actual controls.
- All catalogs use the same stable Simplified Chinese source keys. Display text
  may be shortened or split into lines without changing those lookup keys.

## Adding a language

Copy a catalog to `<locale>.lua`, change its `GetLocaleTable` argument, register
that client code in `Locale.lua`, and add the file after English in the TOC.
Missing translations inherit English. Module code uses `local T = ns.L` and
`T["source message"]`; no global `SetText`, chat, or API hooks are installed.

Localize presentation and new defaults only. Never translate saved user text,
command grammar, IDs, API/event names, or wire-protocol fields. Auction category
IDs and stat tokens remain stable and are translated at the UI boundary. Obtain
item, spell, mount, class, specialization, and dungeon names from client APIs.

每种语言单独维护一个 Lua 文件；只改等号右侧译文，保留格式参数、颜色码和模板变量。
新增语言需同时更新加载入口和 TOC；用户已有文本、命令与存档标识不得被翻译或覆盖。

韩语使用独立的 `koKR.lua`，随韩语客户端自动加载。仅支持官方客户端语言类型；不增加日语或手动语言切换。其他尚未翻译的客户端语言继续回退英文。
