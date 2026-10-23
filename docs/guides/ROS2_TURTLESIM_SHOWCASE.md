# ROSClaw × pixi ROS2 turtlesim 展示指南

本指南演示 **同仓双环境联合验证**（不用 Docker、不用第二个 checkout）：

| 环境 | 路径 | 职责 |
|------|------|------|
| pixi（ROS 2 Jazzy） | 本仓库根目录（`pixi.toml`） | `rosbridge` + `turtlesim` GUI |
| uv `.venv` | 本仓库 `.venv/` | `rosclaw ros …` 经 WebSocket 连 rosbridge |

**不要**把本仓 `pip install` 进 pixi（conda numpy/CUDA 与本仓 MuJoCo/PyPI 易冲突）。Connector 设计为无 `rclpy`，只连 rosbridge。

```text
Operator / Agent（同一仓库根目录）
    → .venv：rosclaw ros ping | discover | validate-capability
    → ws://127.0.0.1:9090（rosbridge）
    → pixi：turtlesim 窗口 + ROS 2 图
```

对照：`rosclaw demo run ur5e-reach` 是 **MuJoCo Receipt**（无 ROS）；本指南是 **ROS2 rosbridge** 路径。

---

## 0. 前置

- 本仓已按 [README.NEW.md](../../README.NEW.md) 装好 `.venv`，并设置 `ROSCLAW_HOME=$PWD/.rosclaw`。
- 本仓根目录已 `pixi install`（含 `ros-jazzy-desktop`、`ros-jazzy-rosbridge-server`、`ros-jazzy-turtlesim`）。
- 本机有图形显示（`echo $DISPLAY` 非空），以便弹出 turtlesim 窗口。

---

## 1. 终端 A — pixi：rosbridge

```bash
cd /path/to/rosclaw   # 本仓库根目录
pixi run rosbridge
# 等价：pixi run -e default bash -lc \
#   'ros2 launch rosbridge_server rosbridge_websocket_launch.xml'
```

期望日志包含：`Rosbridge WebSocket server started on port 9090`。

---

## 2. 终端 B — pixi：turtlesim GUI

```bash
cd /path/to/rosclaw   # 同一仓库根目录
pixi run turtlesim
# 等价：pixi run -e default bash -lc 'ros2 run turtlesim turtlesim_node'
```

期望：弹出 turtlesim 窗口，日志含 `Spawning turtle [turtle1]`。

---

## 3. 终端 C — `.venv`：连通与发现

```bash
cd /path/to/rosclaw   # 同一仓库根目录
source .venv/bin/activate
export ROSCLAW_HOME="$PWD/.rosclaw"
EP=ws://127.0.0.1:9090

rosclaw ros ping --endpoint "$EP" --json
rosclaw ros discover --robot-id turtlesim --endpoint "$EP" --json | head
rosclaw ros compile --robot-id turtlesim --endpoint "$EP" \
  --output /tmp/turtlesim_manifest.json --json
rosclaw ros list-capabilities --robot-id turtlesim --endpoint "$EP" \
  --manifest /tmp/turtlesim_manifest.json
```

现场编译后，速度能力 ID 通常为：

- `turtlesim.base.velocity_command.turtle1` → `/turtle1/cmd_vel`（推荐做展示）
- `turtlesim.base.velocity_command.alt` → `/cmd_vel`

（历史示例里的裸 ID `turtlesim.base.velocity_command` 在 live compile 后会变成带后缀的 ID。）

---

## 4. 安全对照：ALLOW vs BLOCK

```bash
CAP=turtlesim.base.velocity_command.turtle1
MAN=/tmp/turtlesim_manifest.json

# 应 ALLOW（速度/时长在 embodiment 限制内）
rosclaw ros validate-capability "$CAP" \
  --endpoint "$EP" --robot-id turtlesim --manifest "$MAN" \
  --args '{"linear":{"x":0.1,"y":0.0,"z":0.0},"angular":{"x":0.0,"y":0.0,"z":0.0},"duration":0.5}' \
  --json

# 应 BLOCK（超速 + 超时）
rosclaw ros validate-capability "$CAP" \
  --endpoint "$EP" --robot-id turtlesim --manifest "$MAN" \
  --args '{"linear":{"x":1.0,"y":0.0,"z":0.0},"angular":{"x":0.0,"y":0.0,"z":1.0},"duration":2.0}' \
  --json
```

期望：

| 请求 | decision | 说明 |
|------|----------|------|
| safe | `ALLOW` | Within safety constraints |
| fast | `BLOCK` | duration / linear.x / angular.z 越界 |

这是 ROSClaw 相对「裸 `ros2 topic pub`」的价值：策略先于派发。

---

## 5. 可视化运动（展示用）

`rosclaw ros execute-capability` 对直连 rosbridge **fail-closed**（物理派发须经 `rosclawd` + 已验证 executor）。  
现场要在 turtlesim 窗口看到移动时，在 **validate ALLOW 之后**，用 pixi 侧短时发布（仅演示可视化，不是生产执行路径）：

```bash
# 终端 B 或新开 shell（仍在仓库根目录）
cd /path/to/rosclaw
pixi run -e default bash -lc '
  ros2 topic pub --once /turtle1/cmd_vel geometry_msgs/msg/Twist \
    "{linear: {x: 0.5, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.0}}"
'
```

窗口内海龟应沿 x 方向移动。也可用 `ros2 topic echo /turtle1/pose --once` 核对位姿变化。

一键脚本（假定 A/B 已启动）：

```bash
# 在本仓根目录
bash scripts/showcase/ros2_turtlesim_demo.sh
# 可选：顺带发一帧可视化运动
SHOW_MOTION=1 bash scripts/showcase/ros2_turtlesim_demo.sh
```

---

## 6. 与 MuJoCo demo 的对照话术

| | `demo run ur5e-reach` | 本展示 |
|--|----------------------|--------|
| 南向 | MuJoCo Sandbox | ROS 2 + rosbridge |
| 证据 | ExecutionReceipt / explain | validate ALLOW/BLOCK + 可选 GUI 运动 |
| 环境 | 仅本仓 `.venv` | 同仓 `.venv` + pixi |
| 真机 | 否 | 否（仿真） |

生产受控动作：MCP `request_action` → **rosclawd** → executor；本展示用 CLI connector 证明南向与策略，不宣称 Real Ready / H5 Agent 黑盒。

---

## 7. 排障

| 现象 | 处理 |
|------|------|
| `rosclaw：未找到命令` | `source .venv/bin/activate` 或用 `.venv/bin/rosclaw` |
| `pixi：未找到命令` | 安装 [pixi](https://pixi.sh)，在仓库根目录执行 `pixi install` |
| ping 失败 | 确认终端 A rosbridge 已监听 9090；`ss -ltnp \| rg 9090` |
| turtlesim 无窗口 | 检查 `echo $DISPLAY`；无桌面时无法弹窗，仍可用 `topic echo` 看 pose |
| validate 报 `missing_safety_rule` | 使用 compile 后的真实 ID（`.turtle1` / `.alt`），并传 `--manifest` |
| execute-capability 失败 | **预期**：直连执行已关闭；用 validate + 可选 pixi `topic pub` 做展示 |
| discover 里出现其它 `/rosclaw/*` topic | 本机若还跑着另一套 ROSClaw ROS2 包可忽略；turtlesim 相关 topic 仍可用 |

相关文档：[ROS_CONNECTOR.md](../ROS_CONNECTOR.md)、[ROS_INTEGRATION_TESTING.md](../ROS_INTEGRATION_TESTING.md)、embodiment [`src/rosclaw/connectors/ros/specs/turtlesim.yaml`](../../src/rosclaw/connectors/ros/specs/turtlesim.yaml)。
