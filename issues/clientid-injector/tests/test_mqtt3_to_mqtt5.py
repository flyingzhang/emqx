#!/usr/bin/env python3
"""测试 MQTT 3.x 客户端发布消息，MQTT 5.0 客户端订阅接收"""
import paho.mqtt.client as mqtt
import time

BROKER = "localhost"
PORT = 1883
TOPIC = "test/mqtt3/to/mqtt5"

# 使用 MQTT 3.1 的发布者
MQTT3_PUBLISHER_ID = "mqtt3_publisher_device"
# 使用 MQTT 5.0 的订阅者
MQTT5_SUBSCRIBER_ID = "mqtt5_subscriber_platform"

received_clientid = None
message_received = False

def on_connect_subscriber(client, userdata, flags, rc, properties=None):
    print(f"[MQTT5 Subscriber] Connected with result code {rc}")
    client.subscribe(TOPIC, qos=0)

def on_message_subscriber(client, userdata, msg):
    global received_clientid, message_received
    print(f"\n[MQTT5 Subscriber] ========== 收到消息 ==========")
    print(f"[MQTT5 Subscriber] Topic: {msg.topic}")
    print(f"[MQTT5 Subscriber] Payload: {msg.payload.decode()}")
    print(f"[MQTT5 Subscriber] QoS: {msg.qos}")

    # 检查 MQTT 5.0 User Properties
    if hasattr(msg, 'properties') and msg.properties:
        print(f"[MQTT5 Subscriber] Properties object exists: {type(msg.properties)}")

        user_properties = msg.properties.UserProperty
        if user_properties:
            print(f"[MQTT5 Subscriber] User Properties found:")
            for key, value in user_properties:
                print(f"    {key} = {value}")
                if key == "x-emqx-clientid":
                    received_clientid = value
                    print(f"    >>>>> ClientId 提取成功: {value} <<<<<")
        else:
            print(f"[MQTT5 Subscriber] No User Properties in message")
    else:
        print(f"[MQTT5 Subscriber] No properties object")

    message_received = True

def on_connect_publisher(client, userdata, flags, rc):
    print(f"[MQTT3 Publisher] Connected with result code {rc}")

def on_publish_publisher(client, userdata, mid):
    print(f"[MQTT3 Publisher] Message {mid} published successfully")

def main():
    global message_received

    print("=" * 70)
    print("MQTT 3.x -> MQTT 5.0 跨版本 ClientId 注入测试")
    print("=" * 70)
    print()
    print("测试场景:")
    print("  发布者: MQTT 3.1 协议 (模拟物联网设备)")
    print("  订阅者: MQTT 5.0 协议 (模拟IoT平台)")
    print("  目标: 验证 MQTT 3 消息能否被注入 ClientId 到 User Properties")
    print()
    print("=" * 70)

    # 1. 创建 MQTT 5.0 订阅者
    print("\n[步骤 1] 启动 MQTT 5.0 订阅者...")
    subscriber = mqtt.Client(client_id=MQTT5_SUBSCRIBER_ID, protocol=mqtt.MQTTv5)
    subscriber.on_connect = on_connect_subscriber
    subscriber.on_message = on_message_subscriber

    print(f"[MQTT5 Subscriber] 连接到 {BROKER}:{PORT} (MQTT 5.0)...")
    subscriber.connect(BROKER, PORT, 60)
    subscriber.loop_start()

    time.sleep(2)

    # 2. 创建 MQTT 3.1 发布者
    print("\n[步骤 2] 启动 MQTT 3.1 发布者...")
    publisher = mqtt.Client(client_id=MQTT3_PUBLISHER_ID, protocol=mqtt.MQTTv311)
    publisher.on_connect = on_connect_publisher
    publisher.on_publish = on_publish_publisher

    print(f"[MQTT3 Publisher] 连接到 {BROKER}:{PORT} (MQTT 3.1)...")
    publisher.connect(BROKER, PORT, 60)
    publisher.loop_start()

    time.sleep(1)

    # 3. MQTT 3.1 发布者发送消息
    test_payload = '{"device":"sensor001","temperature":25.5,"timestamp":' + str(time.time()) + '}'

    print(f"\n[步骤 3] MQTT 3.1 发布者发送消息...")
    print(f"[MQTT3 Publisher] Client ID: {MQTT3_PUBLISHER_ID}")
    print(f"[MQTT3 Publisher] Protocol: MQTT 3.1")
    print(f"[MQTT3 Publisher] Topic: {TOPIC}")
    print(f"[MQTT3 Publisher] Payload: {test_payload}")
    print(f"[MQTT3 Publisher] 注意: MQTT 3.1 消息本身不包含 User Properties")

    result = publisher.publish(TOPIC, test_payload, qos=0)
    print(f"[MQTT3 Publisher] Publish result: {result}")

    # 等待消息接收
    print(f"\n[步骤 4] 等待 MQTT 5.0 订阅者接收消息...")
    timeout = 10
    start_time = time.time()
    while not message_received and (time.time() - start_time) < timeout:
        time.sleep(0.5)

    # 清理
    publisher.loop_stop()
    publisher.disconnect()
    subscriber.loop_stop()
    subscriber.disconnect()

    time.sleep(1)

    # 分析结果
    print("\n" + "=" * 70)
    print("测试结果分析")
    print("=" * 70)

    if message_received:
        print(f"[OK] MQTT 5.0 subscriber received message")
        if received_clientid:
            print(f"[OK] ClientId found in User Properties")
            print(f"[OK] ClientId value: {received_clientid}")
            if received_clientid == MQTT3_PUBLISHER_ID:
                print(f"\n[SUCCESS] Cross-version ClientId injection successful!")
                print(f"     MQTT 3.1 Publisher: {MQTT3_PUBLISHER_ID}")
                print(f"     User Properties: x-emqx-clientid = {received_clientid}")
                print(f"\n     Plugin successfully converted MQTT 3.x to MQTT 5.0!")
                return 0
            else:
                print(f"\n[FAIL] ClientId mismatch!")
                print(f"     Expected: {MQTT3_PUBLISHER_ID}")
                print(f"     Received: {received_clientid}")
                return 1
        else:
            print(f"\n[FAIL] No ClientId in User Properties")
            print(f"     Plugin may not be working")
            print(f"     Or MQTT 3.x -> MQTT 5.0 conversion has issues")
            return 1
    else:
        print(f"[FAIL] No message received")
        print(f"     Please check network and EMQX status")
        return 1

if __name__ == "__main__":
    exit(main())
