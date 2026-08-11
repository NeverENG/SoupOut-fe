# SoupOut 视觉升级(2.5D + 胡闹厨房风格)

> 2026-08-08 · 表现层整体改版:2D 俯视 → **3D 世界 + 55° 倾斜正交相机**(逃跑吧少年式 2.5D),
> 全部 UI 页面按胡闹厨房式卡通风格重做。核心层 / 网络层 / 协议**零改动**。

## 改了什么

### 世界层(src/world/,全部重写)
| 文件 | 说明 |
|---|---|
| `battle_camera.gd` | Camera3D 正交 + 俯角 55°,视野仍走 `Sim.camera_view_diameter_for_area`,对外 API 不变 |
| `character.gd` | Kenney Mini Characters 动画模型(32 套剪辑:idle/sprint/die/jump/attack…)。**普通 Node 包装器**,自定义 `position: Vector2` / `rotation: float`,battle_root 原有读写零改动 |
| `territory_renderer.gd` + `territory_3d.gdshader` | 地盘场移植为 48×48 PlaneMesh + spatial shader,数据契约(96×96 RGBA 覆盖度、150ms 漫开、原汤全零)不变;`get_texture()` 继续喂小地图 |
| `wall.gd` | 食材墙:白菜/萝卜/玉米/奶酪(冻豆腐)模型阵列 + 深色基座,`collides_with` 逻辑逐行保留 |
| `pallet.gd` `vault.gd` `drop.gd` `stir.gd` | 菜板 / 藕环窗 / 食材道具 / 巨型汤勺,全部保留原 API 与状态机 |
| `env_builder.gd`(新) | 红珐琅大汤锅 + 巨物厨房背景 + 暖色打光 + 汤面蒸汽粒子 |
| `fx3d.gd`(新) | 贴地环/扇形/柔影 shader 工厂、GLB 缓存、模型规格化(防薄片模型缩放爆炸) |
| `poly_outline.gd` | 已不再使用(2D 假体积工具),可手动删除 |

### UI(src/ui/,全部重做)
- `ui_kit.gd`:设计系统(暖厨房色板 + 厚底卡通按钮 + 弹性 hover/press 动画 + 全局 Theme)
- `kitchen_bg.gd`(新):flow 页面共用动态背景(渐变 + 漂浮食材剪影)
- flow 10 个页面全部重做视觉;回调契约 / SettingsDb 键 / 注入属性不变
- HUD 9 个组件重做;新增 `death_overlay.gd`(阵亡遮罩)、`minimap.gdshader`(小地图调色)
- 小地图改为正确调色 + 圆形锅遮罩;罗盘改用 `Camera3D.unproject_position` 真投影
- 摇杆改为锚点定位(任意分辨率),中心坐标 bug 顺带修复(原来钉死 1080p)

### 工程配置
- `project.godot`:`stretch/scale_mode` integer → fractional(3D 下整数缩放会让 HUD 跳档);
  `gui/theme/custom` 指向生成的 `assets/ui/soup_theme.tres`(UI 大量挂在 CanvasLayer 下,
  窗口主题沿 Control 链够不到,必须项目级兜底);新增 MSAA 3D 2x 与软阴影设置
- `src/app/battle.tscn` 根节点 Node2D → Node3D;`app.gd` 两处小改(battle_root 类型放宽 + 挂主题)
- `battle_root.gd` 三处小改:`extends Node3D`、汤底占位改为 `EnvBuilder.build(self)`、vault 传 angle

### 资产(assets/,全部 CC0 / OFL 免费商用)
| 目录 | 来源 | 许可 |
|---|---|---|
| `chars/` 8 个角色 GLB(32 动画) | [Kenney Mini Characters](https://kenney.nl/assets/mini-characters) | CC0 |
| `props/` 食材模型 | [Kenney Food Kit](https://kenney.nl/assets/food-kit) | CC0 |
| `kitchen/` 厨房背景模型 | [KayKit Restaurant Bits](https://kaylousberg.itch.io/restaurant-bits) | CC0 |
| `fonts/zcool_kuaile.ttf` | 站酷快乐体(中文 + 拉丁) | SIL OFL |
| `fonts/baloo2.ttf` | Baloo 2(数字兜底) | SIL OFL |

## 验证方式
```bash
# 视觉冒烟(无需联网,假数据搭整场,截图到 user://probe_*.png)
godot --path . res://tests/visual_probe.tscn
# 无头单测(原有)
godot --headless -s res://tests/test_runner.gd
```
容器内已通过:项目导入零新增报错、视觉冒烟三视角截图、UI 六页面截图、
flow 全流程运行冒烟(login→menu→练习房→选材→设置→匹配→结算→断线→重连)。

## 已知事项
- `Anim.SWING` 现在真正生效(原 2D 版被 `_update_anim` 覆盖,从未播出)
- 名牌/提示为屏幕空间 Control,每帧 `unproject_position` 跟随头顶
- 手机端表现未实测;Compatibility 渲染器下 3D 全特性可用(粒子/辉光/软阴影)
- 首次打开 Godot 会为新文件生成 `.uid` 与导入缓存,属正常现象

## v2(瓦罐汤改版)
- **角色 = 食材本体**:番茄/青菜/玉米/甜菜头(紫芋)+ Q 版大眼睛,程序化动画
  (位移驱动蹦跳/压扁拉伸/充能鼓胀/挥击前倾/死亡翻倒半沉/复活弹出/随机眨眼)
- **瓦罐汤色板**(battle_root · ui_kit · territory_3d · minimap 四处同步,改色请四处一起改):
  原汤 (0.545,0.386,0.212) · 番茄 (0.72,0.30,0.20) · 青菜 (0.44,0.55,0.25)
  · 玉米 (0.84,0.63,0.25) · 紫芋 (0.50,0.36,0.53)
- 锅体红珐琅 → **陶土瓦罐**;地面亮格砖 → 深色木板;灯光压暗调暖(昏黄灶灯),
  降饱和 0.92,辉光 0.12;蒸汽粒子加软边纹理
- **修复**:HUD 全量组件不显示(`set_anchors_preset` 只改锚点不改尺寸,
  已全部换成 `set_anchors_and_offsets_preset`);阵亡横幅居中;蒸汽硬边方块
