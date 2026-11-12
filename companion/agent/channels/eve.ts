import { eveChannel } from "eve/channels/eve";
import { type AuthFn } from "eve/channels/auth";
import { timingSafeEqual } from "node:crypto";

const privateBridge: AuthFn<Request> = async (request) => {
  const expected = process.env.NIB_EVE_TOKEN;
  const token = request.headers.get("authorization")?.replace(/^Bearer /, "");
  if (!expected || !token || token.length !== expected.length) return null;
  if (!timingSafeEqual(Buffer.from(token), Buffer.from(expected))) return null;
  return { authenticator: "nib-local-bridge", principalId: "local-player", principalType: "service", attributes: {} };
};

export default eveChannel({
  auth: [privateBridge],
  turnPolicy: "queue",
});
