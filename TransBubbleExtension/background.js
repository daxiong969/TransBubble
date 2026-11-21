// TransBubble Safari 扩展 - 后台翻译请求（避免页面端 CORS 限制）
const ENDPOINT = "https://translate.googleapis.com/translate_a/single";
const CHUNK_LIMIT = 1400;
const MAX_TEXT_LENGTH = 20000;

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg && msg.type === "translate" && msg.text) {
    translateText(msg.text)
      .then((r) => sendResponse({ ok: true, translated: r.translated, detected: r.detected }))
      .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e) }));
    return true; // 异步响应
  }
  if (msg && msg.type === "ping") {
    sendResponse({ ok: true, pong: true });
    return false;
  }
});

async function translateText(text) {
  const trimmed = String(text || "").trim().slice(0, MAX_TEXT_LENGTH);
  if (!trimmed) throw new Error("没有可翻译的内容");
  const chunks = splitChunks(trimmed, CHUNK_LIMIT);
  let detected = "";
  const outputs = [];
  for (const chunk of chunks) {
    const url = ENDPOINT +
      "?client=gtx&sl=auto&tl=" + encodeURIComponent("zh-CN") +
      "&dt=t&q=" + encodeURIComponent(chunk);
    const res = await fetch(url);
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json();
    if (!Array.isArray(data) || !Array.isArray(data[0])) throw new Error("翻译结果解析失败");
    outputs.push(data[0].map((seg) => (Array.isArray(seg) && seg[0]) || "").join(""));
    if (!detected && typeof data[2] === "string") detected = data[2];
  }
  return { detected, translated: outputs.join("\n\n") };
}

function splitChunks(text, limit) {
  const chunks = [];
  let current = "";
  const paragraphs = text.split("\n");
  for (const para of paragraphs) {
    if (!current) {
      current = para;
    } else if (current.length + para.length + 1 <= limit) {
      current += "\n" + para;
    } else {
      chunks.push(current);
      current = para;
    }
    while (current.length > limit) {
      chunks.push(current.slice(0, limit));
      current = current.slice(limit);
    }
  }
  if (current) chunks.push(current);
  return chunks;
}
