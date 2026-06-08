import assert from "node:assert/strict";
import test from "node:test";
import { createEvidenceRubricServer, evaluateRubric } from "./server.js";

test("evaluateRubric returns normalized Gemini JSON verdict", async () => {
  const verdict = await evaluateRubric(
    {
      candidate: {
        name: "Utopia Euro Caffe",
        address: "2489 Park Ave, Tustin",
      },
    },
    {
      geminiKey: "test-key",
      model: "test-model",
      fetchImpl: async (_url, init) => {
        assert.match(String(_url), /^https:\/\/generativelanguage\.googleapis\.com\/v1beta\/models\/test-model:generateContent\?key=/);
        assert.equal(init.method, "POST");
        const body = JSON.parse(init.body);
        assert.equal(body.generationConfig.responseMimeType, "application/json");
        assert.equal(body.generationConfig.responseSchema.type, "object");
        return new Response(JSON.stringify({
          candidates: [
            {
              content: {
                parts: [{
                  text: JSON.stringify({
                    evidence_tier: "likely",
                    confidence_reason: "Source and media evidence cite the same venue and address.",
                    missing_info: ["Verified coordinates", "User confirmation before saving as Map Stamp"],
                  }),
                }],
              },
            },
          ],
        }), { status: 200 });
      },
    },
  );

  assert.deepEqual(verdict, {
    evidence_tier: "likely",
    confidence_reason: "Source and media evidence cite the same venue and address.",
    missing_info: ["Verified coordinates", "User confirmation before saving as Map Stamp"],
  });
});

test("server requires bearer token for rubric route", async () => {
  const server = createEvidenceRubricServer({
    SAVE_EVIDENCE_RUBRIC_TOKEN: "secret-token",
    GEMINI_API_KEY: "test-key",
  }, async () => {
    throw new Error("fetch should not be called");
  });

  await usingServer(server, async (url) => {
    const response = await fetch(`${url}/rubric`, {
      method: "POST",
      body: JSON.stringify({}),
    });
    assert.equal(response.status, 401);
  });
});

test("health reports readiness without exposing secrets", async () => {
  const server = createEvidenceRubricServer({
    SAVE_EVIDENCE_RUBRIC_TOKEN: "secret-token",
    GEMINI_API_KEY: "test-key",
    GEMINI_MODEL: "test-model",
  });

  await usingServer(server, async (url) => {
    const response = await fetch(`${url}/health`);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.deepEqual(body, {
      ready: true,
      tokenConfigured: true,
      geminiConfigured: true,
      model: "test-model",
    });
    assert.ok(!JSON.stringify(body).includes("secret-token"));
    assert.ok(!JSON.stringify(body).includes("test-key"));
  });
});

async function usingServer(server, callback) {
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.ok(address && typeof address === "object");
  try {
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }
}
