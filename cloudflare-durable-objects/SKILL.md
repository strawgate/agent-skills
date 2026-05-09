---
name: cloudflare-durable-objects
description: Patterns and guidance for building Cloudflare Durable Objects — SQLite storage, hibernation, WebSockets, migrations, and cost optimization.
allowed-tools: Read Grep Glob Bash Agent
metadata:
  argument-hint: "[topic e.g. 'SQLite migration', 'WebSocket hibernation', 'pricing']"
---

# Cloudflare Durable Objects Skill

## Overview

This skill provides comprehensive knowledge about Cloudflare Durable Objects for building stateful applications on Cloudflare's edge network. It synthesizes official documentation with battle-tested patterns from production deployments.

## When to Use This Skill

Use this knowledge when:
- Building stateful applications on Cloudflare Workers
- Pricing questions for Durable Objects
- Architectural decisions about persistence
- Understanding storage backends (SQLite vs Key-Value)
- WebSocket, Alarms, or RPC patterns
- Performance and cost optimization
- DO migration and lifecycle management

---

## Core Concepts

### What Are Durable Objects

Durable Objects provide **single-instance stateful objects** that:
- Run in a single location closest to your users
- Have **transactional SQLite storage** (up to 10 GB per object)
- Provide **strong consistency** within an instance
- Bill per actual memory/CPU used, not requests handled

### Design Around Your "Atom" of Coordination

Create one Durable Object per logical unit:
- Chat rooms → one DO per room
- Game sessions → one DO per session
- Per-user data → one DO per user
- Multi-tenant SaaS → one DO per tenant

**Avoid**: Global singleton DOs that become bottlenecks. Each logical unit should be its own DO.

---

## Storage Backends

### SQLite (Recommended - GA as of April 2025)

Cloudflare recommends all new Durable Object namespaces use SQLite storage:

```typescript
// Enable in wrangler.toml
new_sqlite_classes = ["ClassName"]
```

**Features:**
- Transactional ACID guarantees
- Up to **10 GB per object** (Paid plan)
- Point-in-time recovery (PITR) for last 30 days
- Standard SQL with indexes
- Write-Ahead Log (WAL) streaming to R2

```typescript
// SQL API (synchronous, blocking)
const result = this.ctx.storage.sql.exec(
  "SELECT * FROM agents WHERE id = ?",
  [agentId]
).toArray();

// KV API still available alongside SQL
await this.ctx.storage.put("key", value);
const value = await this.ctx.storage.get("key");
```

**Transaction Patterns:**

```typescript
// Consecutive sync writes (no await between) are auto-coalesced into one txn
this.ctx.storage.sql.exec("INSERT INTO ...", [args1]);
this.ctx.storage.sql.exec("INSERT INTO ...", [args2]);

// Explicit transaction (async, for KV operations)
await this.ctx.storage.transaction(async (txn) => {
  await txn.put("key1", value1);
  await txn.put("key2", value2);
});

// Synchronous transaction (for SQL)
this.ctx.storage.transactionSync(() => {
  this.ctx.storage.sql.exec("INSERT INTO ...", [args]);
});
```

**Note**: With SQLite backend, consecutive synchronous `sql.exec` calls are auto-coalesced. Use `transactionSync` for explicit transaction boundaries.

### Key-Value (Legacy)

Simple get/put operations for backward compatibility. New projects should use SQLite.

---

## WebSocket Hibernation API (Recommended)

The Hibernation API allows DOs to sleep while maintaining WebSocket connections, dramatically reducing costs.

### Why Hibernation?

- Duration charges **stop accruing** when DO is hibernated
- WebSocket clients remain connected to Cloudflare network
- DO re-initializes on next message (constructor runs again)
- After 10 seconds of inactivity, DO becomes eligible for hibernation

### Hibernation Conditions

A DO can hibernate only when ALL are true:
- No `setTimeout`/`setInterval` scheduled
- No in-progress awaited `fetch()`
- No WebSocket Standard API used
- No request/event still being processed

### Implementation Pattern

```typescript
export class ChatRoom extends DurableObject {
  sessions: Map<WebSocket, SessionState>;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sessions = new Map();
    
    // Restore from hibernation
    this.ctx.getWebSockets().forEach((ws) => {
      const attachment = ws.deserializeAttachment();
      if (attachment) {
        this.sessions.set(ws, attachment);
      }
    });

    // Auto-response without waking DO
    this.ctx.setWebSocketAutoResponse(
      new WebSocketRequestResponsePair("ping", "pong")
    );
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected WebSocket", { status: 400 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ id: crypto.randomUUID() });
    this.sessions.set(server, { id: crypto.randomUUID() });

    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    const data = typeof message === "string" ? message : "binary data";
    
    // Broadcast to all connected clients
    for (const client of this.ctx.getWebSockets()) {
      if (client !== ws && client.readyState === WebSocket.OPEN) {
        client.send(data);
      }
    }
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean) {
    // With compat date >= 2026-04-07, auto-reply is handled
    this.sessions.delete(ws);
  }

  async webSocketError(ws: WebSocket, error: unknown) {
    console.error("WebSocket error:", error);
  }
}
```

### Message Batching for High-Frequency Data

For sensor readings or game state updates:

```typescript
// Batch every 50-100ms or 50-100 messages
const BATCH_SIZE = 100;
const BATCH_TIMEOUT_MS = 50;

let messageBuffer: Message[] = [];
let batchTimeout: number | null = null;

async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
  const msg = JSON.parse(message as string);
  messageBuffer.push(msg);

  if (messageBuffer.length >= BATCH_SIZE) {
    this.flushBatch();
  } else if (!batchTimeout) {
    batchTimeout = setTimeout(() => this.flushBatch(), BATCH_TIMEOUT_MS) as unknown as number;
  }
}

flushBatch() {
  if (messageBuffer.length === 0) return;
  const batch = messageBuffer.splice(0);
  // Broadcast batch as single message
  for (const client of this.ctx.getWebSockets()) {
    client.send(JSON.stringify({ type: "batch", messages: batch }));
  }
  batchTimeout = null;
}
```

### serializeAttachment for State Persistence

Maximum 2,048 bytes. For larger data, use Storage API:

```typescript
// Before hibernation - persist small state
ws.serializeAttachment({ sessionId, lastSeq });

// On reconnect - restore state
const state = ws.deserializeAttachment();
if (state) {
  this.sessions.set(ws, state);
}
```

---

## RPC Methods

Type-safe method calls between Workers and DOs:

```typescript
// DO class defines RPC methods
export class ConfigDO implements DurableObject {
  async getAgentState(agentId: string): Promise<AgentState | null> {
    return this.storage.sql.exec(
      "SELECT * FROM agents WHERE id = ?",
      [agentId]
    ).toArray()[0] ?? null;
  }

  async updateAgentState(agentId: string, updates: Partial<AgentState>): Promise<void> {
    // Atomic update with validation
    await this.storage.sql.exec(
      "UPDATE agents SET ... WHERE id = ?",
      [agentId, ...]
    );
  }

  // Fire-and-forget for non-critical updates
  async logMetrics(agentId: string, metrics: Metrics): Promise<void> {
    this.storage.sql.exec(
      "INSERT INTO metrics (agent_id, data) VALUES (?, ?)",
      [agentId, JSON.stringify(metrics)]
    );
  }
}

// Caller in Worker
const stub = env.CONFIG_DO.get(idFromStorage);
const state = await stub.getAgentState(agentId);
await stub.updateAgentState(agentId, { status: "connected" });
```

---

## DO Lifecycle

### States

| State | Description | Billing |
|-------|-------------|---------|
| Active, in-memory | Running, handling requests | Yes |
| Idle, in-memory (non-hibernateable) | Waiting, doesn't meet hibernation criteria | Yes |
| Idle, in-memory (hibernateable) | Waiting, meets hibernation criteria | Yes |
| Hibernated | Removed from memory, WebSockets stay connected | No |
| Inactive | Removed from host process, may cold start | No |

### Constructor Best Practices

Minimize work in constructor when using hibernation:

```typescript
constructor(ctx: DurableObjectState, env: Env) {
  super(ctx, env);
  
  // Only restore essential state from WebSocket attachments
  // Don't load full state from SQLite here
}

// Lazy load on first request
async fetch(request: Request): Promise<Response> {
  if (!this.initialized) {
    await this.initialize();
  }
  // Handle request
}
```

### Shutdown Handling

**No shutdown hooks provided.** Design for incremental state persistence:

```typescript
// DON'T: Wait to persist until end
async processStream(data: StreamData) {
  const results = [];
  for (const chunk of data) {
    results.push(process(chunk));
  }
  await this.storage.put("results", results); // Lost if shutdown mid-stream
});

// DO: Persist incrementally
async processStream(data: StreamData) {
  for (const chunk of data) {
    const result = process(chunk);
    await this.storage.put("lastResult", result);
    await this.storage.put("lastIndex", currentIndex);
  }
}
```

---

## Migration Patterns

Multi-step migrations require careful sequencing:

```typescript
export class ConfigDO implements DurableObject {
  private async ensureSchemaVersion(version: number): Promise<void> {
    const current = await this.getSchemaVersion();
    
    if (current < 2) {
      await this.migrateToV2();
    }
    if (current < 3) {
      await this.migrateToV3();
    }
  }

  private async getSchemaVersion(): Promise<number> {
    const v = await this.storage.get("schema_version");
    return typeof v === "number" ? v : 1;
  }

  private async migrateToV2(): Promise<void> {
    await this.storage.transaction(async (txn) => {
      await txn.sql.exec(`
        CREATE TABLE IF NOT EXISTS new_table (
          id TEXT PRIMARY KEY,
          data TEXT
        )
      `);
      // Migrate data
      await txn.sql.exec(`
        INSERT INTO new_table (id, data)
        SELECT id, old_data FROM old_table
      `);
      await txn.put("schema_version", 2);
    });
  }

  private async migrateToV3(): Promise<void> {
    // Next migration...
  }
}
```

---

## Pricing (Updated January 2026)

### Compute (Wall-Clock Time)

| Metric | Workers Free | Workers Paid |
|--------|-------------|--------------|
| Requests | 100K/day | 1M/month + $0.15/million |
| Duration | 13,000 GB-s/day | 400,000 GB-s/month + $12.50/million GB-s |

### SQLite Storage (Enabled January 2026)

| Metric | Free | Paid |
|--------|-------|------|
| Rows read | 5M/day | 25B/month + $0.001/million |
| Rows written | 100K/day | 50M/month + $1.00/million |
| Stored data | 5 GB | 5 GB + $0.20/GB-month |

### WebSocket Billing

- **20:1 ratio**: 100 incoming messages = 5 billing requests
- Auto-response messages via `setWebSocketAutoResponse()` don't incur duration
- `acceptWebSocket()` incurs duration for entire connection time
- Hibernation dramatically reduces costs for sparse connections

### Cost Example: WebSocket Chat

Moderate traffic (100 DOs, 100 connections each, 1 msg/min):

| Without Hibernation | With Hibernation |
|---------------------|------------------|
| ~$3.09 requests | Minimal |
| ~$1.91 duration | Minimal |
| **Total: ~$5.00+/mo** | **Total: <$1/mo** |

---

## Limits

- Memory: 128 MB per DO instance
- Storage: 10 GB SQLite per DO (Paid), 1 GB (Free)
- WebSocket connections: 32,768 per DO (CPU/memory may limit further)
- No cross-DO transactions
- PITR: 30 days

---

## Common Patterns

### Rate Limiting
```typescript
export class RateLimiter {
  async fetch(request: Request) {
    const windowMs = 60000;
    const limit = 100;
    
    const now = Date.now();
    await this.storage.sql.exec(
      `DELETE FROM requests WHERE ts < ?`,
      [now - windowMs]
    );
    
    const count = this.storage.sql.exec(
      `SELECT count(*) as cnt FROM requests`
    ).toArray()[0]?.cnt ?? 0;
    
    if (count >= limit) {
      return new Response("Rate limited", { status: 429 });
    }
    
    await this.storage.sql.exec(
      `INSERT INTO requests (ts) VALUES (?)`,
      [now]
    );
    
    return next();
  }
}
```

### Scheduled Work with Alarms
```typescript
export class Scheduler {
  async alarm() {
    // Runs at scheduled time
    await this.doPeriodicWork();
    // Reschedule
    await this.ctx.storage.setAlarm(Date.now() + this.intervalMs);
  }
  
  // NOTE: Alarms prevent hibernation - budget duration accordingly
}
```

### State Machine in DO
```typescript
type State = "pending" | "active" | "draining" | "drained";

export class AgentSession {
  private state: State = "pending";
  
  async transition(newState: State): Promise<void> {
    const valid = this.validTransitions[this.state]?.includes(newState);
    if (!valid) {
      throw new Error(`Invalid transition: ${this.state} -> ${newState}`);
    }
    this.state = newState;
    await this.persistState();
  }
  
  private validTransitions: Record<State, State[]> = {
    pending: ["active"],
    active: ["draining"],
    draining: ["drained"],
    drained: [],
  };
}
```

---

## Important Rules

1. **Design around your atom** — One DO per logical unit, not global singletons
2. **SQLite is transactional** — Auto-coalescing, but use explicit txn for complex ops
3. **Hibernation saves costs** — Use WebSocket Hibernation API
4. **No shutdown hooks** — Write state incrementally
5. **Alarms prevent hibernation** — Budget accordingly
6. **Maximize batch** — Batch messages, batch writes
7. **Use indexes** — For read-heavy queries, indexes offset write cost

## When NOT to Use DOs

- Simple key-value caching → Workers KV
- Global counters → Rethink architecture
- Heavy computation → Plain Workers
- Large file storage → R2

---

## Resources

- Docs: https://developers.cloudflare.com/durable-objects/
- Pricing: https://developers.cloudflare.com/durable-objects/platform/pricing
- SQLite GA: https://blog.cloudflare.com/en-us/sqlite-in-durable-objects/
- Best Practices: https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/
