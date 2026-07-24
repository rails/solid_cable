import { check, fail, sleep } from "k6";
import cable from "k6/x/cable";
import { Counter, Rate, Trend } from "k6/metrics";
import { textSummary } from "https://jslib.k6.io/k6-summary/0.0.4/index.js";

const WS_URL = __ENV.WS_URL || "wss://solid-cable.dev/cable";
const WS_COOKIE = __ENV.WS_COOKIE || "";
const ADAPTER = __ENV.ADAPTER || "unknown";
const TEST_ID = __ENV.TEST_ID || ADAPTER;

const MAX_VUS = intEnv("MAX", 20);
const TIME_SECONDS = intEnv("TIME", 90);
const MESSAGES_PER_ITERATION = intEnv("NUM", 5);
const PAYLOAD_BYTES = intEnv("PAYLOAD_BYTES", 64);
const RECEIVE_TIMEOUT_MS = intEnv("RECEIVE_TIMEOUT_MS", 60000);
const HANDSHAKE_TIMEOUT_SECONDS = intEnv("HANDSHAKE_TIMEOUT_SECONDS", 60);
const MIN_SLEEP_MS = intEnv("MIN_SLEEP_MS", 500);
const MAX_SLEEP_MS = intEnv("MAX_SLEEP_MS", 1000);
const CHURN_VUS = intEnv("CHURN_VUS", Math.max(1, Math.floor(MAX_VUS / 5)));
const CHURN_TIME_SECONDS = intEnv("CHURN_TIME", TIME_SECONDS);
const STORM_VUS = intEnv("STORM_VUS", MAX_VUS);
const STORM_TIME_SECONDS = intEnv("STORM_TIME", Math.max(15, Math.floor(TIME_SECONDS / 3)));
const STORM_ROUNDS = intEnv("STORM_ROUNDS", 5);
const STORM_SLEEP_MS = intEnv("STORM_SLEEP_MS", 100);
const FANOUT_VUS = intEnv("FANOUT_VUS", MAX_VUS);
const FANOUT_RATE = intEnv("FANOUT_RATE", 10);
const FANOUT_TIME_SECONDS = intEnv("FANOUT_TIME", TIME_SECONDS);
const FANOUT_WARMUP_SECONDS = intEnv("FANOUT_WARMUP", 15);
const FANOUT_DRAIN_SECONDS = intEnv("FANOUT_DRAIN", 10);
const FANOUT_STREAM = __ENV.FANOUT_STREAM || `${TEST_ID}-fanout`;
const RAMP_UP_SECONDS = Math.max(1, Math.floor(TIME_SECONDS / 3));
const RAMP_HOLD_SECONDS = Math.max(1, Math.floor((7 * TIME_SECONDS) / 12));
const RAMP_DOWN_SECONDS = Math.max(1, Math.floor(TIME_SECONDS / 12));
const RAMP_TOTAL_SECONDS = RAMP_UP_SECONDS + RAMP_HOLD_SECONDS + RAMP_DOWN_SECONDS;
const SCENARIOS = (__ENV.SCENARIOS || "ramp,steady,churn,storm")
  .split(",")
  .map((name) => name.trim())
  .filter(Boolean);

const metricTags = {
  adapter: ADAPTER,
  test_id: TEST_ID,
};

const connectionDuration = new Trend("cable_connection_duration", true);
const subscriptionDuration = new Trend("cable_subscription_duration", true);
const actionRtt = new Trend("cable_action_rtt", true);
const receiveDuration = new Trend("cable_receive_duration", true);
const iterationMessages = new Trend("cable_iteration_messages", false);
const connectionFailures = new Counter("cable_connection_failures");
const subscriptionFailures = new Counter("cable_subscription_failures");
const receiveFailures = new Counter("cable_receive_failures");
const invalidMessages = new Counter("cable_invalid_messages");
const messagesSent = new Counter("cable_messages_sent");
const messagesReceived = new Counter("cable_messages_received");
const successfulRoundTrips = new Rate("cable_round_trip_success");
const fanoutDeliveryLatency = new Trend("cable_fanout_delivery_latency", true);
const fanoutMessagesPublished = new Counter("cable_fanout_messages_published");
const fanoutDeliveriesReceived = new Counter("cable_fanout_deliveries_received");
const fanoutSequenceGaps = new Counter("cable_fanout_sequence_gaps");
const fanoutDuplicateDeliveries = new Counter("cable_fanout_duplicate_deliveries");
const fanoutOutOfOrderDeliveries = new Counter("cable_fanout_out_of_order_deliveries");
const fanoutSubscribersCompleted = new Counter("cable_fanout_subscribers_completed");

export const options = {
  scenarios: buildScenarios(),
};

export function ramp() {
  runPingIteration("ramp");
}

export function steady() {
  runPingIteration("steady");
}

export function churn() {
  const tags = scenarioTags("churn");
  const client = connectClient("churn");
  const channel = subscribe(client, "churn");
  const body = messageBody("churn", 0);
  const startedAt = Date.now();

  channel.perform("ping", { message: body });
  messagesSent.add(1, tags);

  const received = receive(channel, "churn");
  const rtt = Date.now() - startedAt;
  const ok = received && received.message === `pong ${body}`;

  actionRtt.add(rtt, tags);
  successfulRoundTrips.add(Boolean(ok), tags);
  if (!ok) {
    invalidMessages.add(1, tags);
    client.disconnect();
    fail("expected churn ping response was not received");
  }

  messagesReceived.add(1, tags);
  client.disconnect();
}

export function storm() {
  const tags = scenarioTags("storm");

  for (let i = 0; i < STORM_ROUNDS; i++) {
    const client = connectClient("storm");
    const channel = subscribe(client, "storm");
    const body = messageBody("storm", i);
    const startedAt = Date.now();

    channel.perform("ping", { message: body });
    messagesSent.add(1, tags);

    const received = receive(channel, "storm");
    const rtt = Date.now() - startedAt;
    const ok = received && received.message === `pong ${body}`;

    actionRtt.add(rtt, tags);
    successfulRoundTrips.add(Boolean(ok), tags);

    if (!ok) {
      invalidMessages.add(1, tags);
      client.disconnect();
      fail(`expected storm ping response for ${body}`);
    }

    messagesReceived.add(1, tags);
    client.disconnect();
    sleep(STORM_SLEEP_MS / 1000);
  }
}

export function fanoutSubscriber() {
  const tags = scenarioTags("fanout");
  const client = connectClient("fanout");
  const channel = subscribeTo(client, "fanout", "FanoutChannel", { stream: FANOUT_STREAM });
  const seenSequences = {};
  let highestSequence = -1;

  while (true) {
    const message = channel.receive();
    if (!message) continue;

    if (message.complete) {
      const expectedMessages = Number(message.expected_messages);
      let missingMessages = 0;

      for (let sequence = 0; sequence < expectedMessages; sequence++) {
        if (seenSequences[sequence] !== true) missingMessages += 1;
      }

      if (missingMessages > 0) fanoutSequenceGaps.add(missingMessages, tags);
      fanoutSubscribersCompleted.add(1, tags);
      break;
    }

    const sequence = Number(message.sequence);
    const sentAt = Number(message.sent_at);

    if (!Number.isInteger(sequence) || sequence < 0 || !Number.isFinite(sentAt)) {
      invalidMessages.add(1, tags);
      continue;
    }

    if (seenSequences[sequence] === true) {
      fanoutDuplicateDeliveries.add(1, tags);
      continue;
    }

    if (sequence < highestSequence) fanoutOutOfOrderDeliveries.add(1, tags);

    seenSequences[sequence] = true;
    highestSequence = Math.max(highestSequence, sequence);
    fanoutDeliveryLatency.add(Date.now() - sentAt, tags);
    fanoutDeliveriesReceived.add(1, tags);
  }

  client.disconnect();
}

export function fanoutPublisher() {
  const tags = scenarioTags("fanout");
  const client = connectClient("fanout");
  const channel = subscribeTo(client, "fanout", "FanoutChannel", { stream: FANOUT_STREAM });
  const messageCount = FANOUT_RATE * FANOUT_TIME_SECONDS;

  for (let sequence = 0; sequence < messageCount; sequence++) {
    channel.perform("publish", {
      sequence,
      sent_at: Date.now(),
      message: messageBody("fanout", sequence),
    });
    fanoutMessagesPublished.add(1, tags);

    if (sequence < messageCount - 1) sleep(1 / FANOUT_RATE);
  }

  sleep(1);
  channel.perform("publish", { complete: true, expected_messages: messageCount });
  sleep(1);
  client.disconnect();
}

function runPingIteration(workload) {
  const tags = scenarioTags(workload);
  const client = connectClient(workload);
  const channel = subscribe(client, workload);
  let receivedCount = 0;

  for (let i = 0; i < MESSAGES_PER_ITERATION; i++) {
    const body = messageBody(workload, i);
    const startedAt = Date.now();

    channel.perform("ping", { message: body });
    messagesSent.add(1, tags);

    const message = receive(channel, workload);
    const rtt = Date.now() - startedAt;
    const ok = message && message.message === `pong ${body}`;

    actionRtt.add(rtt, tags);
    successfulRoundTrips.add(Boolean(ok), tags);

    if (!ok) {
      invalidMessages.add(1, tags);
      client.disconnect();
      fail(`expected pong response for ${body}`);
    }

    receivedCount += 1;
    messagesReceived.add(1, tags);
    sleep(randomSleepSeconds());
  }

  iterationMessages.add(receivedCount, tags);
  client.disconnect();
}

function connectClient(workload, receiveTimeoutMs) {
  const tags = scenarioTags(workload);
  const startedAt = Date.now();
  const client = cable.connect(WS_URL, {
    cookies: WS_COOKIE,
    receiveTimeoutMs: receiveTimeoutMs || RECEIVE_TIMEOUT_MS,
    handshakeTimeoutS: HANDSHAKE_TIMEOUT_SECONDS,
    tags,
  });

  connectionDuration.add(Date.now() - startedAt, tags);

  if (!check(client, { "successful connection": (obj) => Boolean(obj) }, tags)) {
    connectionFailures.add(1, tags);
    fail("connection failed");
  }

  return client;
}

function subscribe(client, workload) {
  return subscribeTo(client, workload, "BroadcastChannel", {});
}

function subscribeTo(client, workload, channelName, params) {
  const tags = scenarioTags(workload);
  const startedAt = Date.now();
  const channel = client.subscribe(channelName, params);

  subscriptionDuration.add(Date.now() - startedAt, tags);

  if (!check(channel, { "successful subscription": (obj) => Boolean(obj) }, tags)) {
    subscriptionFailures.add(1, tags);
    fail("failed to subscribe");
  }

  return channel;
}

function receive(channel, workload) {
  const tags = scenarioTags(workload);
  const startedAt = Date.now();
  const message = channel.receive();

  receiveDuration.add(Date.now() - startedAt, tags);

  if (!message) {
    receiveFailures.add(1, tags);
  }

  return message;
}

function buildScenarios() {
  const scenarios = {};
  let startAfterSeconds = 0;

  if (SCENARIOS.includes("ramp")) {
    scenarios.ramp = {
      exec: "ramp",
      executor: "ramping-vus",
      startTime: scenarioStartTime(startAfterSeconds),
      startVUs: Math.max(1, Math.floor(MAX_VUS / 10)),
      stages: [
        { duration: `${RAMP_UP_SECONDS}s`, target: Math.max(1, Math.floor(MAX_VUS / 4)) },
        { duration: `${RAMP_HOLD_SECONDS}s`, target: MAX_VUS },
        { duration: `${RAMP_DOWN_SECONDS}s`, target: 0 },
      ],
      tags: scenarioTags("ramp"),
    };
    startAfterSeconds += RAMP_TOTAL_SECONDS;
  }

  if (SCENARIOS.includes("steady")) {
    scenarios.steady = {
      exec: "steady",
      executor: "constant-vus",
      vus: MAX_VUS,
      duration: `${TIME_SECONDS}s`,
      startTime: scenarioStartTime(startAfterSeconds),
      tags: scenarioTags("steady"),
    };
    startAfterSeconds += TIME_SECONDS;
  }

  if (SCENARIOS.includes("churn")) {
    scenarios.churn = {
      exec: "churn",
      executor: "constant-vus",
      vus: CHURN_VUS,
      duration: `${CHURN_TIME_SECONDS}s`,
      startTime: scenarioStartTime(startAfterSeconds),
      tags: scenarioTags("churn"),
    };
    startAfterSeconds += CHURN_TIME_SECONDS;
  }

  if (SCENARIOS.includes("storm")) {
    scenarios.storm = {
      exec: "storm",
      executor: "per-vu-iterations",
      vus: STORM_VUS,
      iterations: 1,
      maxDuration: `${Math.max(STORM_TIME_SECONDS, HANDSHAKE_TIMEOUT_SECONDS + 5)}s`,
      startTime: scenarioStartTime(startAfterSeconds),
      tags: scenarioTags("storm"),
    };
    startAfterSeconds += STORM_TIME_SECONDS;
  }

  if (SCENARIOS.includes("fanout")) {
    const fanoutStartTime = startAfterSeconds;

    scenarios.fanout_subscribers = {
      exec: "fanoutSubscriber",
      executor: "per-vu-iterations",
      vus: FANOUT_VUS,
      iterations: 1,
      maxDuration: `${FANOUT_WARMUP_SECONDS + FANOUT_TIME_SECONDS + FANOUT_DRAIN_SECONDS}s`,
      startTime: scenarioStartTime(fanoutStartTime),
      tags: scenarioTags("fanout"),
    };

    scenarios.fanout_publisher = {
      exec: "fanoutPublisher",
      executor: "per-vu-iterations",
      vus: 1,
      iterations: 1,
      maxDuration: `${FANOUT_TIME_SECONDS + HANDSHAKE_TIMEOUT_SECONDS}s`,
      startTime: scenarioStartTime(fanoutStartTime + FANOUT_WARMUP_SECONDS),
      tags: scenarioTags("fanout"),
    };
  }

  return scenarios;
}

export function handleSummary(data) {
  const output = {
    stdout: textSummary(data, { indent: " ", enableColors: true }),
  };

  if (__ENV.SUMMARY_PATH) {
    output[__ENV.SUMMARY_PATH] = JSON.stringify({
      adapter: ADAPTER,
      test_id: TEST_ID,
      ws_url: WS_URL,
      scenarios: SCENARIOS,
      metrics: data.metrics,
      root_group: data.root_group,
    }, null, 2);
  }

  return output;
}

function scenarioStartTime(seconds) {
  return seconds === 0 ? "0s" : `${seconds}s`;
}

function scenarioTags(workload) {
  return Object.assign({}, metricTags, { workload: workload });
}

function messageBody(workload, index) {
  const prefix = `${TEST_ID}:${workload}:vu-${__VU}:iter-${__ITER}:msg-${index}:`;
  if (PAYLOAD_BYTES <= prefix.length) return prefix;

  return `${prefix}${"x".repeat(PAYLOAD_BYTES - prefix.length)}`;
}

function randomSleepSeconds() {
  if (MAX_SLEEP_MS <= MIN_SLEEP_MS) return MIN_SLEEP_MS / 1000;

  return randomIntBetween(MIN_SLEEP_MS, MAX_SLEEP_MS) / 1000;
}

function randomIntBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function intEnv(name, defaultValue) {
  const value = parseInt(__ENV[name] || `${defaultValue}`, 10);
  return Number.isNaN(value) ? defaultValue : value;
}
