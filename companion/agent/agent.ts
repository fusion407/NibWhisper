import { defineAgent } from "eve";
import { defineDynamic } from "eve/models";
import { loadProviderSettings } from "../lib/providers.mjs";
import { selectNibModel } from "./lib/provider-model";

export default defineAgent({
  model: defineDynamic(async () => selectNibModel(await loadProviderSettings())),
  defaultTools: false,
  tool: false,
  limits: {
    sessionTimeoutMs: 10 * 60 * 1000,
    sessionUsage: ({ window }) => window.inputTokens - window.cacheReadTokens > 45000 || window.outputTokens > 9000,
  },
});
