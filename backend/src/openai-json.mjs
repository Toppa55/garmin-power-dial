const OPENAI_URL = "https://api.openai.com/v1/responses";

function extractText(response) {
  for (const item of response.output ?? []) {
    for (const content of item.content ?? []) {
      if (content.type === "output_text" && content.text) return content.text;
    }
  }
  throw new Error("OpenAI returned no structured result");
}

export async function openAiJson({ instructions, input, schema, name, apiKey = process.env.OPENAI_API_KEY, model = process.env.OPENAI_MODEL ?? "gpt-5.6-luna", fetchImpl = fetch }) {
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured");
  const response = await fetchImpl(OPENAI_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      store: false,
      instructions,
      input: JSON.stringify(input),
      text: { format: { type: "json_schema", name, strict: true, schema } }
    })
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message ?? `OpenAI request failed (${response.status})`);
  return JSON.parse(extractText(data));
}
