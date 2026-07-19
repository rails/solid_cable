import { check, fail, sleep } from "k6";
import cable from "k6/x/cable";
import { Counter, Rate, Trend } from "k6/metrics";

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

export const options = {
  summaryTrendStats: ["avg", "min", "med", "p(90)", "p(95)", "p(99)", "max"],
  systemTags: ["status", "method", "url", "name", "scenario", "group", "check", "error"],
  thresholds: {
    checks: ["rate>0.99"],
    cable_connection_failures: ["count==0"],
    cable_subscription_failures: ["count==0"],
    cable_receive_failures: ["count==0"],
    cable_invalid_messages: ["count==0"],
    cable_round_trip_success: ["rate>0.99"],
    cable_connection_duration: ["p(95)<1000"],
    cable_subscription_duration: ["p(95)<1000"],
    cable_action_rtt: ["p(95)<500", "p(99)<1000"],
  },
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

function connectClient(workload) {
  const tags = scenarioTags(workload);
  const startedAt = Date.now();
  const client = cable.connect(WS_URL, {
    cookies: WS_COOKIE,
    receiveTimeoutMs: RECEIVE_TIMEOUT_MS,
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
  const tags = scenarioTags(workload);
  const startedAt = Date.now();
  const channel = client.subscribe("BroadcastChannel", {});

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
      executor: "constant-vus",
      vus: STORM_VUS,
      duration: `${STORM_TIME_SECONDS}s`,
      startTime: scenarioStartTime(startAfterSeconds),
      gracefulStop: "0s",
      tags: scenarioTags("storm"),
    };
  }

  return scenarios;
}

export function handleSummary(data) {
  const output = {
    stdout: summaryText(data),
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

function summaryText(data) {
  const lines = [
    "",
    `adapter=${ADAPTER} test_id=${TEST_ID} url=${WS_URL}`,
    `scenarios=${SCENARIOS.join(",")} max_vus=${MAX_VUS} messages_per_iteration=${MESSAGES_PER_ITERATION} storm_vus=${STORM_VUS}`,
    "",
    "Cable metrics:",
    metricLine(data, "cable_connection_duration", ["avg", "p(95)", "p(99)", "max"]),
    metricLine(data, "cable_subscription_duration", ["avg", "p(95)", "p(99)", "max"]),
    metricLine(data, "cable_action_rtt", ["avg", "p(95)", "p(99)", "max"]),
    metricLine(data, "cable_receive_duration", ["avg", "p(95)", "p(99)", "max"]),
    metricLine(data, "cable_round_trip_success", ["rate"]),
    metricLine(data, "cable_messages_sent", ["count", "rate"]),
    metricLine(data, "cable_messages_received", ["count", "rate"]),
    metricLine(data, "cable_connection_failures", ["count"]),
    metricLine(data, "cable_subscription_failures", ["count"]),
    metricLine(data, "cable_receive_failures", ["count"]),
    metricLine(data, "cable_invalid_messages", ["count"]),
    "",
  ];

  return `${lines.filter(Boolean).join("\n")}\n`;
}

function metricLine(data, name, fields) {
  const metric = data.metrics[name];
  if (!metric || !metric.values) return `${name}: missing`;

  const values = fields
    .filter((field) => metric.values[field] !== undefined)
    .map((field) => `${field}=${formatMetricValue(metric.values[field])}`)
    .join(" ");

  return `${name}: ${values}`;
}

function formatMetricValue(value) {
  if (typeof value !== "number") return `${value}`;
  if (Number.isInteger(value)) return `${value}`;

  return value.toFixed(2);
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
