# Project Context

## Purpose
EMQX is the world's most scalable open-source MQTT broker designed for IoT, IIoT, and connected vehicle scenarios. Key goals:
- Connect 100M+ IoT devices in a single cluster
- Maintain 1M message/second throughput with sub-millisecond latency
- Provide 100% compliance with MQTT 5.0 and 3.x standards
- Enable real-time IoT data processing via SQL-based rules engine

## Tech Stack
- **Primary Language**: Erlang/OTP 26.2.5
- **Secondary Language**: Elixir 1.15.7 (for mix-based builds)
- **Build System**: Rebar3 (Erlang) / Mix (Elixir)
- **Configuration**: HOCON format
- **Storage Backend**: RocksDB (for durable storage)
- **Clustering**: Ekka (mnesia-based auto-clustering)
- **RPC**: gen_rpc for distributed communication
- **HTTP Server**: Cowboy + MiniRest for REST APIs
- **Protocols**: MQTT, MQTT-SN, CoAP, LwM2M, STOMP, HTTP, WebSocket, QUIC

## Project Conventions

### Code Style
- Use **erlfmt** for Erlang code formatting (`make fmt`)
- Erlang modules follow `emqx_*` naming convention
- Hook-based extension pattern for plugins and integrations
- Use `snabbkaffe` for trace-based testing

### Architecture Patterns
- **Microkernel Architecture**: Core `emqx` app with 105+ pluggable application modules under `apps/`
- **Masterless Distributed Cluster**: No single point of failure, horizontal scaling
- **Hook System**: Event-driven extensibility via `emqx_hooks`
- **Resource Abstraction**: `emqx_resource` for connectors and bridges
- **Rule Engine**: SQL-based data transformation pipeline
- **Durable Storage (DS)**: Pluggable backends via `emqx_durable_storage` and `emqx_ds_backends`

### Testing Strategy
- **Unit Tests**: `make eunit` with EUnit framework
- **Integration Tests**: `make ct` with Common Test (CT) framework
- **Property Testing**: `make proper` with PropEr
- **Static Analysis**: xref, dialyzer, elvis for code quality
- **Coverage**: Export with `--cover` flag
- **Test Node**: Uses `test@127.0.0.1` as CT node name

### Git Workflow
- **Branching**: `master` branch tracks latest v5.x
- **Commit Format**: `<type>(<scope>): <subject>` (Conventional Commits)
  - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `chore`, `perf`, `test`, `build`, `ci`, `revert`
- **Changelog**: Separate markdown files under `changes/(ce|ee)/(feat|perf|fix)-<PR-id>.en.md`
- **PR References**: Footer should close related issues

## Domain Context
- **MQTT Protocol**: Publish/Subscribe messaging for IoT (QoS 0/1/2, Retained Messages, Last Will)
- **Session Management**: Clean/Persistent sessions with durable storage option
- **Client Types**: Publishers, Subscribers, Gateways, Bridges
- **Topic Semantics**: Hierarchical topics with wildcards (`+`, `#`)
- **Authentication/Authorization**: Multiple backends (JWT, LDAP, HTTP, Database-based)
- **Data Integration**: 40+ bridges to external systems (Kafka, Redis, PostgreSQL, etc.)

## Important Constraints
- **License**: Apache 2.0 (open source) / BSL 1.1 (enterprise features under `apps/emqx_enterprise`)
- **OTP Version**: Requires OTP 25 or 26 for v5.4+
- **Mnesia Restrictions**: Direct mnesia calls are forbidden (use Mria/Ekka abstractions)
- **Backward Compatibility**: MQTT 3.1, 3.1.1, 5.0 all supported
- **Relup Support**: Hot upgrade via relup instructions

## External Dependencies
- **Ekka**: Autoscaling, auto-cluster formation for Erlang clusters
- **Mria**: Distributed database with async replication (fork of Mnesia)
- **RocksDB**: Embedded key-value store for durable sessions
- **QUIC**: Optional QUIC protocol support via `quicer`
- **Dashboard**: Separate repository `emqx-dashboard5` (embedded as static assets)
- **EIP Repository**: Enhancement proposals at github.com/emqx/eip
