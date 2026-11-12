import { defineTool } from "eve/tools";
import { z } from "zod";
import { searchGameKnowledge } from "../../lib/lookup.mjs";

const calls = new Map<string, number>();

export default defineTool({
  description: "Find cited public facts only about World of Warcraft Forever and explicitly labeled comparable Classic data. Searches Wowhead and official Warcraft/Blizzard sites. No arbitrary URL fetching or code execution. Use at most twice per turn; the private guide excerpts are already provided in client context.",
  inputSchema: z.object({ query: z.string().min(1).max(500) }).strict(),
  async execute({ query }, ctx) {
    const key = ctx.session.id;
    const count = calls.get(key) ?? 0;
    if (count >= 2) return { text: "Lookup limit reached. Explain the evidence gap instead of guessing.", sources: [], kind: "lookup-limit" };
    if (calls.size > 100) calls.delete(calls.keys().next().value!);
    calls.set(key, count + 1);
    return searchGameKnowledge(query, { signal: ctx.abortSignal });
  },
});
