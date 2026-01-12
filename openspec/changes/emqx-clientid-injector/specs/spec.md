## ADDED Requirements

### Requirement: ClientId Injection via User Properties

插件必须在消息发布时自动注入发布者的连接元数据到 MQTT 5.0 User Properties 中。

#### Scenario: MQTT 3.x Device Publishing

- **WHEN** a device connects using MQTT 3.1.1 protocol
- **AND** the device publishes a message to topic `neat/device-001/up`
- **AND** the message has no User Properties (MQTT 3.x limitation)
- **THEN** the plugin SHALL inject `x-emqx-clientid` User Property with the device's ClientId
- **AND** the modified message SHALL be delivered to MQTT 5.0 subscribers
- **AND** the MQTT 5.0 subscriber SHALL receive the message with `x-emqx-clientid=device-001`

#### Scenario: MQTT 5.0 Device Publishing

- **WHEN** a device connects using MQTT 5.0 protocol
- **AND** the device publishes a message with existing User Properties `{"custom-key": "custom-value"}`
- **THEN** the plugin SHALL append (NOT replace) `x-emqx-clientid` to User Properties
- **AND** the original `custom-key` property SHALL be preserved

#### Scenario: System Message Skip

- **WHEN** a message is published to topic starting with `$SYS/`
- **OR** topic starting with `$share/`
- **THEN** the plugin SHALL NOT modify the message
- **AND** the message SHALL be forwarded unchanged

---

### Requirement: Configurable Property Injection

插件应支持可配置的属性注入，包括可选的 Username 和 PeerName。

#### Scenario: Username Injection Enabled

- **GIVEN** configuration `inject_username = true`
- **WHEN** a device with username `user123` publishes a message
- **THEN** the plugin SHALL inject both:
  - `x-emqx-clientid` with ClientId value
  - `x-emqx-username` with `user123` value

#### Scenario: PeerName Injection Enabled

- **GIVEN** configuration `inject_peername = true`
- **WHEN** a device connecting from `192.168.1.100:54321` publishes a message
- **THEN** the plugin SHALL inject `x-emqx-peername` with value `192.168.1.100:54321`

#### Scenario: Custom Property Keys

- **GIVEN** configuration `clientid_key = "device-id"`
- **WHEN** a device publishes a message
- **THEN** the plugin SHALL inject User Property with key `device-id` (not `x-emqx-clientid`)

---

### Requirement: Topic Filtering

插件应支持基于 Topic 前缀的过滤规则。

#### Scenario: Exclude Prefixes

- **GIVEN** configuration `exclude_prefixes = ["$SYS/", "$share/", "internal/"]`
- **WHEN** a message is published to topic `internal/heartbeat`
- **THEN** the plugin SHALL NOT process this message

#### Scenario: Include Prefixes Only

- **GIVEN** configuration `include_prefixes = ["neat/", "guhe/"]`
- **WHEN** a message is published to topic `other/device/data`
- **THEN** the plugin SHALL NOT process this message
- **AND** when a message is published to topic `neat/device/data`
- **THEN** the plugin SHALL process this message

---

### Requirement: Plugin Lifecycle

插件必须支持标准的 EMQX 插件生命周期管理。

#### Scenario: Hot Loading

- **WHEN** the plugin is installed via EMQX Dashboard or CLI
- **AND** the plugin is started
- **THEN** the plugin SHALL immediately begin processing messages
- **AND** no EMQX restart SHALL be required

#### Scenario: Hot Unloading

- **WHEN** the plugin is stopped via Dashboard or CLI
- **THEN** the plugin SHALL immediately stop processing messages
- **AND** messages SHALL be forwarded unchanged
- **AND** no EMQX restart SHALL be required

#### Scenario: Configuration Hot Reload

- **WHEN** the plugin configuration is updated via API
- **THEN** the new configuration SHALL take effect immediately
- **AND** no plugin restart SHALL be required

---

### Requirement: Performance Constraints

插件必须满足性能约束条件。

#### Scenario: Low Latency

- **WHEN** processing 10,000 messages per second
- **THEN** the average additional latency per message SHALL be less than 0.1 milliseconds

#### Scenario: Low Memory Overhead

- **WHEN** the plugin is active
- **THEN** the additional memory consumption per message SHALL be less than 100 bytes

---

## Platform Integration Requirements

### Requirement: MqttClientEndpoint Compatibility

平台侧 MqttClientEndpoint 必须兼容 User Properties 方式获取 ClientId。

#### Scenario: User Properties Priority

- **WHEN** `MqttUpstreamListener.messageArrived` is invoked
- **AND** the message contains `x-emqx-clientid` User Property
- **THEN** the ClientId SHALL be extracted from User Property first
- **AND** topic parsing SHALL be used as fallback only

#### Scenario: Backward Compatibility

- **WHEN** `MqttUpstreamListener.messageArrived` is invoked
- **AND** the message does NOT contain `x-emqx-clientid` User Property
- **THEN** the existing `tryParseClientIdFromTopic()` method SHALL be used
- **AND** existing protocol bindings SHALL continue to work without modification

---

## REMOVED Requirements

(None)

## MODIFIED Requirements

(None)
