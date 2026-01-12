#!/usr/bin/env python3
"""Test script for EMQX ClientId Injector plugin - MQTT 5.0 User Properties"""
import paho.mqtt.client as mqtt
import time
import json

# Test configuration
BROKER = "localhost"
PORT = 1883
TOPIC = "test/clientid/inject"
CLIENT_ID_PUB = "test_publisher_123"
CLIENT_ID_SUB = "test_subscriber_456"

received_clientid = None
message_received = False

def on_connect(client, userdata, flags, rc, properties=None):
    print(f"[Subscriber] Connected with result code {rc}")
    client.subscribe(TOPIC, qos=0)

def on_message(client, userdata, msg):
    global received_clientid, message_received
    print(f"\n[Subscriber] Received message on topic: {msg.topic}")
    print(f"[Subscriber] Payload: {msg.payload.decode()}")

    # Check MQTT 5.0 User Properties
    if hasattr(msg, 'properties') and msg.properties:
        user_properties = msg.properties.UserProperty
        if user_properties:
            print(f"[Subscriber] User Properties:")
            for key, value in user_properties:
                print(f"  {key} = {value}")
                if key == "x-emqx-clientid":
                    received_clientid = value
        else:
            print("[Subscriber] No User Properties found!")
    else:
        print("[Subscriber] No properties in message!")

    message_received = True

def on_publish(client, userdata, mid, rc, properties=None):
    print(f"[Publisher] Message {mid} published")

def main():
    global message_received

    print("=" * 60)
    print("EMQX ClientId Injector Plugin Test - MQTT 5.0")
    print("=" * 60)

    # Create subscriber (MQTT 5.0)
    subscriber = mqtt.Client(client_id=CLIENT_ID_SUB, protocol=mqtt.MQTTv5)
    subscriber.on_connect = on_connect
    subscriber.on_message = on_message

    print(f"\n[Subscriber] Connecting to {BROKER}:{PORT}...")
    subscriber.connect(BROKER, PORT, 60)
    subscriber.loop_start()

    time.sleep(2)  # Wait for subscription

    # Create publisher (MQTT 5.0)
    publisher = mqtt.Client(client_id=CLIENT_ID_PUB, protocol=mqtt.MQTTv5)
    publisher.on_publish = on_publish

    print(f"[Publisher] Connecting to {BROKER}:{PORT}...")
    publisher.connect(BROKER, PORT, 60)
    publisher.loop_start()

    time.sleep(1)

    # Publish test message
    test_payload = json.dumps({"test": "data", "timestamp": time.time()})
    print(f"\n[Publisherr] Publishing to {TOPIC}...")
    print(f"[Publisher] Client ID: {CLIENT_ID_PUB}")
    print(f"[Publisher] Payload: {test_payload}")

    result = publisher.publish(TOPIC, test_payload, qos=0)

    # Wait for message
    timeout = 10
    start_time = time.time()
    while not message_received and (time.time() - start_time) < timeout:
        time.sleep(0.5)

    publisher.loop_stop()
    publisher.disconnect()
    subscriber.loop_stop()
    subscriber.disconnect()

    # Check results
    print("\n" + "=" * 60)
    print("Test Results:")
    print("=" * 60)

    if message_received:
        print("[OK] Message was received by subscriber")
        if received_clientid:
            print(f"[OK] ClientId injected: {received_clientid}")
            if received_clientid == CLIENT_ID_PUB:
                print(f"[SUCCESS] Plugin working correctly!")
                print(f"  Expected ClientId: {CLIENT_ID_PUB}")
                print(f"  Received ClientId: {received_clientid}")
                return 0
            else:
                print(f"[FAIL] ClientId mismatch!")
                print(f"  Expected: {CLIENT_ID_PUB}")
                print(f"  Received: {received_clientid}")
                return 1
        else:
            print("[FAIL] User Properties not found - plugin may not be working!")
            return 1
    else:
        print("[FAIL] No message received - check connection!")
        return 1

if __name__ == "__main__":
    exit(main())
