# ROSClaw 安装与配置备忘

本仓默认路径：**安装到仓库根目录 `.venv`**，工作区用 **`.rosclaw`**。  
正式文档见 `README.zh.md`、`QUICKSTART.md`、`docs/P0_AGENT_INTEGRATION.md`。

前提：已安装 [uv](https://github.com/astral-sh/uv)。  
请用项目 `.venv` 里的 CLI，不要依赖 PATH 上其它 `rosclaw`。

---

## 1. 安装到 `.venv`（唯一推荐）

在仓库根目录：

```bash
cd /path/to/rosclaw

# 创建环境并安装 rosclaw（editable）
uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -e .

# 运行时数据放在仓库内
export ROSCLAW_HOME="$PWD/.rosclaw"
export PATH="$PWD/.venv/bin:$PATH"

# 首次配置 + 健康检查
rosclaw firstboot --yes --dev --workspace "$ROSCLAW_HOME" \
  --profile offline --no-telemetry
rosclaw doctor --level verified
rosclaw --version
```

每次新开终端：

```bash
cd /path/to/rosclaw
source .venv/bin/activate
export ROSCLAW_HOME="$PWD/.rosclaw"
```

或不 activate：

```bash
export ROSCLAW_HOME="$PWD/.rosclaw"
.venv/bin/rosclaw doctor --json
```

说明：

- `uv pip install -e .` **就是安装 rosclaw**（得到 `.venv/bin/rosclaw`）。
- `firstboot` 是写工作区配置，不能代替安装。
- `ROSCLAW_HOME` 不设时，状态可能写到 `~/.rosclaw`。

---

## 2. 仿真冒烟

```bash
source .venv/bin/activate
export ROSCLAW_HOME="$PWD/.rosclaw"

rosclaw demo list
rosclaw demo run ur5e-reach
rosclaw explain latest
```

`ur5e-reach` 为 MuJoCo 无头仿真，产物在 `$ROSCLAW_HOME/runs/`，不经过 ROS / `rosclawd`。

---

## 3. ROS2 联合展示（同仓双环境：pixi + uv，无 Docker）

本仓库同时提供 **pixi（ROS 2 Jazzy）** 与 **uv `.venv`（ROSClaw）** 两套隔离环境，经 rosbridge 联合验证（无需第二个 checkout）：

| 环境 | 路径 | 职责 |
|------|------|------|
| pixi | 本仓根目录（`pixi.toml`） | `pixi run rosbridge` + `pixi run turtlesim`（GUI） |
| uv `.venv` | 本仓 `.venv/` | `rosclaw ros ping/discover/validate-capability` |

```bash
cd /path/to/rosclaw
pixi install                  # 首次：安装 ROS 2 Jazzy + rosbridge

# 终端 A / B（pixi，仍在同一仓库根目录）
pixi run rosbridge            # ws://127.0.0.1:9090
pixi run turtlesim            # 需 DISPLAY

# 终端 C（uv .venv，同一仓库根目录）
source .venv/bin/activate
export ROSCLAW_HOME="$PWD/.rosclaw"
bash scripts/showcase/ros2_turtlesim_demo.sh
# 可选：ALLOW 后发一帧可视化运动
SHOW_MOTION=1 bash scripts/showcase/ros2_turtlesim_demo.sh
```

完整说明：[docs/guides/ROS2_TURTLESIM_SHOWCASE.md](docs/guides/ROS2_TURTLESIM_SHOWCASE.md)。  
勿把本仓 pip 进 pixi；`execute-capability` 直连 rosbridge 为 fail-closed（生产走 `rosclawd`）。

---

## 4. Agent：Claude Code

```bash
source .venv/bin/activate
export ROSCLAW_HOME="$PWD/.rosclaw"

rosclaw agent install --project-root . --skip-secrets
rosclaw agent doctor universal --project-root .
rosclaw agent test universal --project-root . --quick --mcp-probe
```

然后用 Claude Code 打开仓库根目录，**手动批准** `.mcp.json` 中的 `rosclaw` MCP。

---

## 5. Agent：Cursor

配置 `.cursor/mcp.json`，`command` 指向本仓 `.venv`：

```json
{
  "mcpServers": {
    "rosclaw": {
      "command": "/ABS/PATH/TO/rosclaw/.venv/bin/python",
      "args": [
        "-m", "rosclaw.entrypoint", "mcp", "serve",
        "--profile", "default",
        "--project", "${workspaceFolder}",
        "--log-level", "ERROR"
      ],
      "env": {
        "ROSCLAW_HOME": "${workspaceFolder}/.rosclaw",
        "ROSCLAW_PROFILE": "default",
        "ROSCLAW_AGENT_CLIENT": "cursor",
        "ROSCLAW_MCP_AUDIT": "1"
      }
    }
  }
}
```

Settings → Tools & MCP 启用后，可用 `list_product_demos` / `run_product_demo` 验证。

---

## 6. 速查

```bash
source .venv/bin/activate
export ROSCLAW_HOME="$PWD/.rosclaw"

uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -e .
rosclaw firstboot --yes --dev --workspace "$ROSCLAW_HOME" --profile offline --no-telemetry
rosclaw doctor --level verified
rosclaw demo run ur5e-reach
rosclaw agent install --project-root . --skip-secrets
```

| 路径 | 作用 |
|------|------|
| `pixi.toml` | 同仓 ROS 2 Jazzy + rosbridge（`pixi run …`） |
| `.venv/` | Python 环境 + `rosclaw` CLI |
| `.rosclaw/` | firstboot / runs / MCP audit |
| `.mcp.json` | Claude Code MCP |
| `.cursor/mcp.json` | Cursor MCP |
| `docs/guides/ROS2_TURTLESIM_SHOWCASE.md` | pixi ROS2 + 本仓联合展示 |
| `scripts/showcase/ros2_turtlesim_demo.sh` | ping → ALLOW/BLOCK 一键检查 |

**`rosclaw：未找到命令`** → 先 `source .venv/bin/activate`，或用 `.venv/bin/rosclaw`。
