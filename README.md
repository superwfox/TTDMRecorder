# TTDMRecorder

自动记录 Titan Team Deathmatch (TTDM) 对局数据并上传至 [ttdm-review](https://ttdm-review.pages.dev) 的 Northstar 客户端 Mod。

Automatically records Titan Team Deathmatch (TTDM) match data and uploads it to [ttdm-review](https://ttdm-review.pages.dev). A client-side Northstar mod.

![screenshot](screenshot.png)

---

## 功能 / Features

- 自动检测 TTDM 模式，进入对局后开始录制
- 每 500ms 采样一次玩家血量和泰坦类型，生成 timeline CSV
- 对局结束时收集所有玩家的击杀、死亡、伤害数据，生成 players CSV
- 对局结束后自动上传两份 CSV 至远程服务器，上传成功后删除本地文件
- 上传失败自动重试，最多 5 次
- 启动时自动扫描上次未上传成功的残留文件并补传，残缺文件自动清理
- HUD 通知上传结果

---

- Automatically detects TTDM game mode and starts recording on match start
- Samples player health and titan type every 500ms into a timeline CSV
- Collects all players' kills, deaths, and damage at match end into a players CSV
- Auto-uploads both CSVs to the remote server after match ends; deletes local files on success
- Auto-retries on upload failure, up to 5 attempts
- On startup, scans for leftover files from previous failed uploads and re-uploads them; orphaned files are cleaned up
- HUD notification for upload results

## 安装 / Installation

1. 确保已安装 [`Northstar`](https://northstar.tf) 客户端 | 该Mod已针对 `NorthstarCN` 完成适配
2. 将 `TTDMRecorder` 文件夹放入 `R2Northstar/mods/` 目录
3. 启动游戏，加入 TTDM 模式即可自动工作

---

1. Make sure you have the [Northstar](https://northstar.tf) client installed | This mod has adapted to `NorthstarCN`
2. Place the `BeijiFox.TTDMRecorder` folder into `R2Northstar/mods/`
3. Launch the game and join a TTDM match — the mod works automatically

## 数据文件 / Data Files

对局数据保存在 `R2Northstar/save_data/` 目录下，文件名格式：

Match data is saved under `R2Northstar/save_data/`, filename format:

```
{玩家名}_{时间戳}_players.csv    — 所有玩家结算数据 / all players' end-game stats
{玩家名}_{时间戳}_timeline.csv   — 血量与泰坦采样 / health & titan type samples
```

### Players CSV

```csv
name,kills,deaths,damage
SudarkO,6,3,81776
Player2,8,2,30981
```

### Timeline CSV

```csv
SampleNum,health,titanType
1,25,pilot
30,25,legion
36,12500,legion
```

## 上传 API / Upload API

数据自动上传至 `https://ttdm-review.pages.dev/api/upload`。

可通过 `https://ttdm-review.pages.dev/api/query?name={玩家名}` 查询历史对局。

---

Data is auto-uploaded to `https://ttdm-review.pages.dev/api/upload`.

Query match history at `https://ttdm-review.pages.dev/api/query?name={playerName}`.

## 依赖 / Requirements

- [Northstar](https://northstar.tf) v1.9.0+
- 游戏模式：TTDM / Game mode: TTDM

## 许可 / License

MIT
