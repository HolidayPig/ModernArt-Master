# 现代艺术（Modern Art）- Godot 单机人机对战（Windows）

## 运行环境
- **Godot**：4.6（本项目基于 `project.godot` 的 4.6 配置）
- **系统**：Windows 10/11

## 一键下载素材（可选但推荐）
本项目优先使用可下载的 **CC0 像素风 UI/卡牌素材** + **中文字体**；若未下载或下载失败，游戏仍可运行（会使用纯色占位）。

在 PowerShell 中进入项目目录后执行：

```powershell
cd "e:\AI\ModernArt-Master\modern-art"
PowerShell -ExecutionPolicy Bypass -File ".\tools\download_assets.ps1"
```

下载结果：
- `assets/downloaded/`：Kenney CC0 的像素 UI 与卡牌 PNG（首版先作为基础资源储备）
- `assets/fonts/NotoSansCJKsc-Regular.otf`：中文字体（用于确保中文可显示）

## 启动游戏
用 Godot 打开 `modern-art/project.godot`，点击运行（F5）。

## 当前玩法（首版）
- **模式**：你 vs 电脑（2人）本机对战
- **出牌**：在你的回合点击下方手牌按钮即可出牌发起拍卖
- **拍卖交互**：
  - 电脑为卖家时：你会在“拍卖区”面板里输入你的出价/选择买或不买
  - 你为卖家时：除“定价出售”需要你输入定价外，其它拍卖由电脑作为买家自动响应
- **轮次**：4轮；当本轮任一艺术家“售出数量达到5”即触发本轮结算
- **胜负**：第4轮结算后现金更多者获胜

## 代码入口
- 主菜单入口场景：`scenes/Main.tscn`
- 牌桌场景：`scenes/TableScene.tscn`
- 规则层（核心逻辑）：`scripts/core/`
  - `GameState.gd`（回合/状态机/结算）
  - `AuctionEngine.gd`（5种拍卖结算函数）
  - `ScoringEngine.gd`（每轮计分）
  - `CardDefs.gd`（艺术家/拍卖类型/卡牌生成）
- AI：`scripts/ai/AiPlayer.gd`
- 资源回退：`scripts/assets/AssetResolver.gd`

## 已知限制（后续可增强）
- 规则数据为“可玩近似版”：牌堆中拍卖类型分布做了均衡近似，未逐张复刻原作符号分布。
- 2人局发牌采用“每轮每人10张”的稳定配置（原作主要面向3-5人）。
- 当前卡牌动画为轻量 Tween（出牌飞向拍卖区）；后续可继续加入翻面、抓牌、结算飞回收藏区等。
