import { check, sleep, fail } from "k6";
import cable from "k6/x/cable";
import { randomIntBetween } from "https://jslib.k6.io/k6-utils/1.1.0/index.js";
import { Trend } from "k6/metrics";

let rttTrend = new Trend("rtt", true);

const WS_URL = __ENV.WS_URL || "wss://felling.app/cable";
const WS_COOKIE = __ENV.WS_COOKIE; // we need a valid cookie to authorize request
const MAX = parseInt(__ENV.MAX || "20");
// Total test duration
const TIME = parseInt(__ENV.TIME || "90");
const MESSAGES_NUM = parseInt(__ENV.NUM || "5");

export let options = {
  thresholds: {
    checks: ["rate>0.9"],
  },
  scenarios: {
    ping: {
      // We use ramping executor to slowly increase the number of users during a test
      executor: "ramping-vus",
      startVUs: (MAX / 10 || 1) | 0,
      stages: [
        { duration: `${TIME / 3}s`, target: (MAX / 4) | 0 },
        { duration: `${(7 * TIME) / 12}s`, target: MAX },
        { duration: `${TIME / 12}s`, target: 0 },
      ],
    },
  },
};


export default function () {
  const client = cable.connect(WS_URL, { cookies: WS_COOKIE, receiveTimeoutMS: 60000 });

   if (!check(client, { "successful connection": (obj) => obj })) {
    fail("connection failed");
  }

  const channel = client.subscribe("BroadcastChannel", {});
  if (!check(channel, { "successful subscription": (obj) => obj })) {
    fail("failed to subscribe");
  }

  for (let i = 0; i < MESSAGES_NUM; i++) {
    let startMessage = Date.now();
    channel.perform("ping", { message: `Hello ${i}` });

    let message = channel.receive();
    if (!check(message, { "received res": (obj) => obj.message === `pong Hello ${i}` })) {
      fail("expected message hasn't been received");
    }

    let endMessage = Date.now();
    rttTrend.add(endMessage - startMessage);

    sleep(randomIntBetween(5, 10) / 10);
  }

  // Terminate the WS connection
  client.disconnect();
}
