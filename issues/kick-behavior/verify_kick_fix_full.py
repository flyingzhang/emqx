
import paho.mqtt.client as mqtt
from paho.mqtt.properties import Properties
from paho.mqtt.packettypes import PacketTypes
import time
import subprocess
import threading
import sys

BROKER = "localhost"
PORT = 1883
CONTAINER_NAME = "emqx-verify"

def run_test_case(case_name, use_retain_option, expect_session_present, expect_msg):
    client_id = f"kick-test-{int(time.time())}-{case_name}"
    topic = f"test/kick/{case_name}"
    
    state = {
        "connected_once": False,
        "reconnected": False,
        "session_present_on_reconnect": None,
        "msg_received": False,
        "kicked": False
    }

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=client_id, protocol=mqtt.MQTTv5)

    def on_connect(client, userdata, flags, reason_code, properties=None):
        if not state["connected_once"]:
            print(f"[{case_name}] 首次连接成功")
            state["connected_once"] = True
            client.subscribe(topic, qos=1)
        else:
            print(f"[{case_name}] 重连成功. Session Present: {flags.session_present}, Reason: {reason_code}")
            state["reconnected"] = True
            state["session_present_on_reconnect"] = flags.session_present

    def on_disconnect(client, userdata, flags, reason_code, properties=None):
        # 只要连接过一次，不管什么原因断开，都可能是 kick 造成的
        if state["connected_once"] and not state["reconnected"]:
             print(f"[{case_name}] 客户端断开")
            
    def on_message(client, userdata, msg):
        print(f"[{case_name}] 收到消息: {msg.payload}")
        state["msg_received"] = True

    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message

    props = Properties(PacketTypes.CONNECT)
    props.SessionExpiryInterval = 300 

    print(f"[{case_name}] 连接...")
    client.connect(BROKER, PORT, 60, clean_start=False, properties=props)
    client.loop_start()

    # 等待首次连接
    time.sleep(2)
    if not state["connected_once"]:
        print(f"[{case_name}] 连接超时")
        client.loop_stop()
        return False

    # 执行 Kick
    cmd = ["docker", "exec", CONTAINER_NAME, "emqx", "ctl", "clients", "kick", client_id]
    if use_retain_option:
        cmd.append("--retain-session")
    
    print(f"[{case_name}] 执行命令: {' '.join(cmd)}")
    subprocess.run(cmd, check=False)
    
    # 等待重连
    print(f"[{case_name}] 等待重连...")
    for _ in range(10):
        if state["reconnected"]:
            break
        time.sleep(1)
        
    if not state["reconnected"]:
        print(f"[{case_name}] 重连超时")
        client.loop_stop()
        return False

    # 验证 Session Present
    sp = state["session_present_on_reconnect"]
    print(f"[{case_name}] 期望 Session Present: {expect_session_present}, 实际: {sp}")
    
    sp_ok = (sp == expect_session_present)

    # 发布消息验证订阅 (只有当 Session 存在且期望消息时才验证)
    msg_ok = True
    if expect_msg:
        print(f"[{case_name}] 发布消息验证订阅...")
        # 使用另一个客户端发布
        pub = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, protocol=mqtt.MQTTv5)
        pub.connect(BROKER, PORT, 60)
        pub.publish(topic, "hello", qos=1)
        pub.disconnect()
        
        time.sleep(2)
        print(f"[{case_name}] 期望收到消息: {expect_msg}, 实际: {state['msg_received']}")
        msg_ok = state["msg_received"]
    
    client.loop_stop()
    client.disconnect()
    
    if sp_ok and msg_ok:
        print(f"[{case_name}] -> 测试通过")
        return True
    else:
        print(f"[{case_name}] -> 测试失败")
        return False

print("开始验证...")
print("-" * 30)

# Case 1: 默认 Kick -> 应该销毁会话 (Session Present = False)
# 如果修复生效，race condition 消除，session destroy 应该彻底执行
pass1 = run_test_case("default_kick", False, False, False)

print("-" * 30)

# Case 2: Kick with --retain-session -> 应该保留会话 (SP=True) 且 收到消息
pass2 = run_test_case("retain_kick", True, True, True)

print("-" * 30)
if pass1 and pass2:
    print("SUCCESS: 所有验证通过！修复生效。")
else:
    print("FAILURE: 验证失败！")
