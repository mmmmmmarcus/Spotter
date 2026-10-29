import { pathToFileURL } from "node:url";
import { bootConfig, createHarness } from "./test.mjs";

// Adapted from Tinycast #1679; Spotter validates callbacks natively and returns a structured result.
export async function runOAuthFixtures(check) {
  const calls = [];
  const harness = createHarness({
    stubs: {
      "oauth.authorize": ([url, state]) => {
        calls.push({ url, state });
        return { authorizationCode: "relayed", state };
      },
    },
  });
  harness.boot(bootConfig());
  harness.start("oauth-contract", `
    const { OAuth, AI, Icon } = require("@raycast/api");
    module.exports.default = () => {
      globalThis.prepare = async (method, extraParameters, clientId = "fixture") => {
        globalThis.client = new OAuth.PKCEClient({ redirectMethod: OAuth.RedirectMethod[method], providerName: "Café & Bar #2 + 東京", providerId: "spotter-fixture" });
        globalThis.request = await client.authorizationRequest({ endpoint: "https://auth.example.test/authorize", clientId, scope: "repo", extraParameters });
        return { state: request.state, verifier: request.codeVerifier, url: request.toURL(), clientId: request.clientId };
      };
      globalThis.signIn = async () => {
        const targets = [request, { url: request.toURL(), state: "not-sent" }, request.toURL()];
        return Promise.all(targets.map(target => client.authorize(target)));
      };
      globalThis.apiCompatibility = async () => {
        const errors = [];
        for (const name of ["ask", "experimental_decide", "refreshModels"]) {
          try { await AI[name]("fixture"); } catch (error) { errors.push(error.message); }
        }
        return { errors, icon: Icon.Quicklink };
      };
    };`, "/oauth.js", "/", "no-view", {});
  await new Promise((resolve) => setTimeout(resolve, 20));
  try {
    const web = await harness.call('prepare("Web")');
    const envelope = JSON.parse(Buffer.from(web.state, "base64url").toString());
    check("web relay keeps Spotter's callback scheme", envelope.scheme === "tinycast");
    check("web state preserves Unicode provider metadata", envelope.providerName === "Café & Bar #2 + 東京" && envelope.providerId === "spotter-fixture");
    check("web state carries a fresh nonce", /^[\w-]{22}$/.test(envelope.token));
    const relayed = await harness.call("signIn()");
    check("request, custom URL and string URL return native authorization results", relayed.every(result => result.authorizationCode === "relayed"));
    check("all URL forms send the actual state to native validation", calls.every(call => call.state === new URL(call.url).searchParams.get("state")));
    const next = await harness.call('prepare("Web")');
    check("new requests have independent states and PKCE verifiers", next.state !== web.state && next.verifier !== web.verifier);

    for (const [method, redirect] of [
      ["App", "raycast://oauth?package_name=Extension"],
      ["AppURI", "com.raycast:/oauth?package_name=Extension"],
      ["ClientIdMetadataDocument", "com.raycast:/oauth"],
    ]) {
      const prepared = await harness.call(`prepare("${method}")`);
      check(`${method} sends an opaque state`, /^[\w-]{22}$/.test(prepared.state));
      check(`${method} uses its registered redirect URI`, new URL(prepared.url).searchParams.get("redirect_uri") === redirect);
      calls.length = 0;
      await harness.call("signIn()");
      check(`${method} validates the state from every URL form`, calls.length === 3 && calls.every(call => call.state === prepared.state));
    }
    const metadata = await harness.call('prepare("ClientIdMetadataDocument", undefined, null)');
    check("metadata clients can omit clientId", metadata.clientId === "https://www.raycast.com/.well-known/oauth-client-metadata/raycast.json");
    for (const state of ["custom-state + & 東京", ""]) {
      await harness.call(`prepare("App", { state: ${JSON.stringify(state)}, redirect_uri: "spotter://oauth" })`);
      calls.length = 0;
      await harness.call("signIn()");
      check(`extraParameters state is validated verbatim (${state ? "custom" : "empty"})`, calls.length === 3 && calls.every(call => call.state === state));
      check("custom redirect URI remains supported", new URL(calls[0].url).searchParams.get("redirect_uri") === "spotter://oauth");
    }
    calls.length = 0;
    await harness.call('client.authorize({ url: "https://auth.example.test/authorize", state: "not-sent" })');
    check("a stateless custom URL does not invent a state", calls[0].state === null);

    const api = await harness.call("apiCompatibility()");
    check("API 2.8.2 exports Icon.Quicklink", api.icon === "quicklink-16");
    check("unsupported AI calls report their API name instead of TypeError", api.errors.length === 3 && ["AI.ask", "AI.experimental_decide", "AI.refreshModels"].every((name, index) => api.errors[index].includes(name)));
  } finally {
    harness.stop("oauth-contract");
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  let failures = 0;
  await runOAuthFixtures((label, condition) => {
    console.log(`${condition ? "✓" : "✗"} ${label}`);
    if (!condition) failures++;
  });
  process.exitCode = failures ? 1 : 0;
}
