#!/usr/bin/env python3
"""Foreground rosclawd with turtlesim SHADOW executor (no pytest).

Mirrors the live wiring in
``tests/simforge/test_guarded_base_ros_integration.py``:

  MCP / CLI ``request_action``
    → this daemon (Unix socket)
    → ``mobile_base.guarded_move`` SHADOW executor
    → rosbridge ``/turtle1/cmd_vel``

Prerequisites (other terminals)::

  pixi run rosbridge
  pixi run turtlesim

Usage (repo root)::

  export ROSCLAW_HOME="$PWD/.rosclaw"
  .venv/bin/python scripts/showcase/serve_turtlesim_guarded_daemon.py

  # one SHADOW move then exit
  .venv/bin/python scripts/showcase/serve_turtlesim_guarded_daemon.py --smoke

Cursor MCP (``.cursor/mcp.json``) already uses ``ROSCLAW_HOME=${workspaceFolder}/.rosclaw``.
Keep this process running, then call MCP ``request_action`` with::

  capability_id=mobile_base.guarded_move
  execution_mode=SHADOW
  body_id=sim_mobile_base
  arguments={linear_x_mps, angular_z_radps: 0, duration_sec}
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import signal
import sys
import time
from pathlib import Path


def _pose_message_type(transport) -> str:
    result = transport.call_service("/rosapi/topics", {})
    if result.ok and isinstance(result.data, dict):
        values = result.data.get("values", {})
        if isinstance(values, dict):
            topics = values.get("topics", [])
            types = values.get("types", [])
            for topic, message_type in zip(topics, types, strict=False):
                if topic == "/turtle1/pose" and isinstance(message_type, str):
                    return message_type
    return "turtlesim/msg/Pose"


def _require_rosbridge(endpoint: str) -> None:
    from rosclaw.connectors.ros.transport import RosbridgeEndpoint, RosbridgeTransport

    transport = RosbridgeTransport(
        endpoint=RosbridgeEndpoint.from_url(endpoint),
        max_retries=0,
    )
    try:
        if not transport.call_service("/rosapi/topics", {}).ok:
            raise SystemExit(f"rosbridge reachable but /rosapi/topics failed at {endpoint}")
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"rosbridge unreachable at {endpoint}: {exc}") from exc
    finally:
        transport.close()


def _build_stack(
    *,
    endpoint: str,
    robot_id: str,
    daemon_id: str,
    command_topic: str,
    pose_topic: str,
    socket_path: Path,
    reset: bool,
):
    from rosclaw.connectors.ros.transport import RosbridgeEndpoint, RosbridgeTransport
    from rosclaw.core.runtime import Runtime, RuntimeConfig
    from rosclaw.daemon.server import RosclawDaemon
    from rosclaw.daemon.service import DaemonControlPlane
    from rosclaw.kernel import ExecutionMode
    from rosclaw.simforge.tasks.guarded_base import (
        GenericMobileBaseSimulationExecutor,
        RosbridgeMobileBaseSink,
    )

    transport = RosbridgeTransport(endpoint=RosbridgeEndpoint.from_url(endpoint))
    if reset:
        reset_result = transport.call_service("/reset", {})
        if not reset_result.ok:
            transport.close()
            raise SystemExit(f"turtlesim /reset failed: {reset_result.error}")

    pose_type = _pose_message_type(transport)
    sink = RosbridgeMobileBaseSink(
        transport,
        daemon_owner_id=daemon_id,
        command_topic=command_topic,
        pose_topic=pose_topic,
        pose_message_type=pose_type,
    )
    runtime = Runtime(
        RuntimeConfig(
            robot_id=robot_id,
            enable_firewall=False,
            enable_memory=False,
            enable_practice=False,
            enable_skill_manager=False,
            enable_knowledge=False,
            enable_how=False,
            enable_auto=False,
            enable_provider=False,
            enable_sense=False,
            enable_event_persistence=False,
            enable_tracing=False,
        )
    )
    runtime.action_gateway.register_executor(
        GenericMobileBaseSimulationExecutor.capability_id,
        ExecutionMode.SHADOW,
        GenericMobileBaseSimulationExecutor(sink, daemon_instance_id=daemon_id),
    )
    daemon = RosclawDaemon(
        service=DaemonControlPlane(runtime=runtime),
        socket_path=socket_path,
    )
    return transport, sink, daemon


async def _smoke(
    *,
    socket_path: Path,
    robot_id: str,
    linear_x_mps: float,
    duration_sec: float,
    wait_timeout_sec: float,
) -> dict:
    from rosclaw.daemon.client import DaemonClient
    from rosclaw.mcp.adapters.runtime_client import RuntimeClient

    mcp = RuntimeClient(
        project_root=Path.cwd(),
        robot_id=robot_id,
        runtime_profile={},
        daemon_client=DaemonClient(socket_path=socket_path, timeout_sec=10),
    )
    return await mcp.request_action(
        capability_id="mobile_base.guarded_move",
        arguments={
            "linear_x_mps": linear_x_mps,
            "angular_z_radps": 0.0,
            "duration_sec": duration_sec,
        },
        execution_mode="SHADOW",
        body_snapshot_hash="sha256:" + "a" * 64,
        body_id=robot_id,
        action_id=f"turtlesim-smoke-{int(time.time())}",
        required_evidence="TASK_VERIFIED",
        wait_timeout_sec=wait_timeout_sec,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Serve rosclawd with turtlesim mobile_base.guarded_move SHADOW executor",
    )
    parser.add_argument(
        "--endpoint",
        default=os.environ.get("ROSCLAW_ROS_ENDPOINT", "ws://127.0.0.1:9090"),
        help="rosbridge WebSocket URL",
    )
    parser.add_argument(
        "--robot-id",
        default="sim_mobile_base",
        help="body_id / robot_id for ActionEnvelope (default: sim_mobile_base)",
    )
    parser.add_argument(
        "--daemon-id",
        default="daemon_turtlesim_showcase",
        help="must start with daemon_; binds sink ownership",
    )
    parser.add_argument("--command-topic", default="/turtle1/cmd_vel")
    parser.add_argument("--pose-topic", default="/turtle1/pose")
    parser.add_argument(
        "--socket",
        default=None,
        help="Unix socket path (default: $ROSCLAW_HOME/run/rosclawd.sock)",
    )
    parser.add_argument(
        "--no-reset",
        action="store_true",
        help="do not call turtlesim /reset on startup",
    )
    parser.add_argument(
        "--smoke",
        action="store_true",
        help="after start, run one SHADOW request_action then exit",
    )
    parser.add_argument("--smoke-linear", type=float, default=0.2)
    parser.add_argument("--smoke-duration", type=float, default=0.5)
    parser.add_argument("--smoke-wait", type=float, default=10.0)
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
    )
    args = parser.parse_args(argv)

    if not args.daemon_id.startswith("daemon_"):
        print("ERROR: --daemon-id must start with 'daemon_'", file=sys.stderr)
        return 2

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        stream=sys.stderr,
    )

    from rosclaw.daemon.client import get_daemon_socket_path

    socket_path = get_daemon_socket_path(args.socket)
    if socket_path.exists():
        print(
            f"ERROR: socket already exists: {socket_path}\n"
            "Stop the other rosclawd, or pass --socket / a dedicated ROSCLAW_HOME.",
            file=sys.stderr,
        )
        return 1

    print(f"Checking rosbridge at {args.endpoint} …", flush=True)
    _require_rosbridge(args.endpoint)

    transport, sink, daemon = _build_stack(
        endpoint=args.endpoint,
        robot_id=args.robot_id,
        daemon_id=args.daemon_id,
        command_topic=args.command_topic,
        pose_topic=args.pose_topic,
        socket_path=socket_path,
        reset=not args.no_reset,
    )

    daemon.start()
    print(
        "\n".join(
            [
                "════════════════════════════════════════════════════════",
                " turtlesim guarded daemon READY",
                "════════════════════════════════════════════════════════",
                f" socket={socket_path}",
                f" ROSCLAW_HOME={os.environ.get('ROSCLAW_HOME', '(unset → default home)')}",
                f" endpoint={args.endpoint}",
                f" robot_id={args.robot_id}",
                " capability=mobile_base.guarded_move (SHADOW only)",
                f" command_topic={args.command_topic}",
                "",
                " Cursor MCP: keep this process running, then:",
                "   request_action(",
                "     capability_id='mobile_base.guarded_move',",
                "     execution_mode='SHADOW',",
                f"     body_id='{args.robot_id}',",
                "     arguments={'linear_x_mps': 0.2, 'angular_z_radps': 0.0, 'duration_sec': 0.5},",
                "     body_snapshot_hash='sha256:' + 'a'*64,",
                "   )",
                " Ctrl+C to stop.",
                "",
            ]
        ),
        flush=True,
    )

    exit_code = 0
    try:
        if args.smoke:
            print("▶ smoke: request_action SHADOW …", flush=True)
            result = asyncio.run(
                _smoke(
                    socket_path=socket_path,
                    robot_id=args.robot_id,
                    linear_x_mps=args.smoke_linear,
                    duration_sec=args.smoke_duration,
                    wait_timeout_sec=args.smoke_wait,
                )
            )
            print(json.dumps(result, indent=2, sort_keys=True, default=str))
            receipt = result.get("receipt") if isinstance(result, dict) else None
            if not (
                isinstance(result, dict)
                and result.get("state") == "FINISHED"
                and isinstance(receipt, dict)
                and receipt.get("final_state") == "COMPLETED"
            ):
                print("ERROR: smoke did not COMPLETE", file=sys.stderr)
                exit_code = 1
            else:
                print("smoke OK — turtlesim should have moved", flush=True)
        else:
            stop = {"flag": False}

            def _request_shutdown(_signum: int, _frame: object) -> None:
                stop["flag"] = True
                daemon.request_shutdown()

            previous = {
                signal.SIGINT: signal.getsignal(signal.SIGINT),
                signal.SIGTERM: signal.getsignal(signal.SIGTERM),
            }
            for signum in (signal.SIGINT, signal.SIGTERM):
                signal.signal(signum, _request_shutdown)
            try:
                while not stop["flag"]:
                    time.sleep(0.25)
            finally:
                for signum, handler in previous.items():
                    signal.signal(signum, handler)
    except KeyboardInterrupt:
        pass
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        exit_code = 1
    finally:
        daemon.stop()
        sink.stop()
        transport.close()
        print("daemon stopped.", flush=True)

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
