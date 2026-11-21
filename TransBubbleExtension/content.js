// TransBubble Safari 扩展 - 内容脚本：注入悬浮球与翻译结果面板
(function () {
  if (window.__transBubbleInjected) return;
  window.__transBubbleInjected = true;

  const FAB_ID = "transbubble-fab";
  const PANEL_ID = "transbubble-panel";
  const STYLE_ID = "transbubble-style";

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      #${FAB_ID} {
        position: fixed; right: 18px; top: 62vh; z-index: 2147483647;
        width: 52px; height: 52px; border-radius: 50%;
        background: linear-gradient(135deg, #3285fa, #1f5cd9);
        color: #fff; font: bold 22px/52px -apple-system, "PingFang SC", sans-serif;
        text-align: center; cursor: pointer; user-select: none;
        box-shadow: 0 3px 10px rgba(0,0,0,.3); opacity: .92;
      }
      #${FAB_ID}:hover { opacity: 1; transform: scale(1.05); }
      #${FAB_ID}.__busy::before {
        content: ""; display: block; margin: 16px auto;
        width: 20px; height: 20px; border-radius: 50%;
        border: 3px solid rgba(255,255,255,.35); border-top-color: #fff;
        animation: __tb_spin .8s linear infinite;
      }
      @keyframes __tb_spin { to { transform: rotate(360deg); } }
      #${PANEL_ID} {
        position: fixed; left: 12px; right: 12px; bottom: 12px; z-index: 2147483647;
        max-height: 55vh; overflow-y: auto; display: none;
        background: rgba(250,250,252,.97); color: #1c1c1e;
        border-radius: 16px; padding: 16px;
        font: 15px/1.7 -apple-system, "PingFang SC", sans-serif;
        box-shadow: 0 8px 30px rgba(0,0,0,.25);
        white-space: pre-wrap; word-break: break-word;
      }
      #${PANEL_ID} .__tb-close {
        position: sticky; top: 0; float: right; cursor: pointer;
        background: #e5e5ea; color: #555; border: 0; border-radius: 12px;
        padding: 3px 12px; font-size: 13px;
      }
      #${PANEL_ID} .__tb-detected { color: #666; font-size: 12px; margin-top: 10px; }
      #${PANEL_ID} .__tb-copy {
        margin-top: 12px; cursor: pointer; background: #3285fa; color: #fff;
        border: 0; border-radius: 10px; padding: 6px 16px; font-size: 13px;
      }
    `;
    document.documentElement.appendChild(style);
  }

  function createFab() {
    if (document.getElementById(FAB_ID)) return;
    const fab = document.createElement("div");
    fab.id = FAB_ID;
    fab.textContent = "译";
    fab.title = "TransBubble：翻译本页为中文（拖不动，点它就行）";
    fab.addEventListener("click", onFabClick);
    document.documentElement.appendChild(fab);
  }

  function setBusy(busy) {
    const fab = document.getElementById(FAB_ID);
    if (!fab) return;
    if (busy) {
      fab.classList.add("__busy");
      fab.textContent = "";
    } else {
      fab.classList.remove("__busy");
      fab.textContent = "译";
    }
  }

  async function onFabClick() {
    const selection = String(window.getSelection() || "").trim();
    const text = selection || getPageText();
    if (!text) {
      showPanel("没有找到可翻译的内容");
      return;
    }
    setBusy(true);
    showPanel("正在翻译当前页面…");
    try {
      const resp = await chrome.runtime.sendMessage({ type: "translate", text });
      if (resp && resp.ok) {
        showPanel(resp.translated, resp.detected);
      } else {
        showPanel("翻译失败：" + ((resp && resp.error) || "未知错误"));
      }
    } catch (e) {
      showPanel("翻译失败：" + String((e && e.message) || e));
    } finally {
      setBusy(false);
    }
  }

  function getPageText() {
    const clone = document.body.cloneNode(true);
    clone.querySelectorAll("script,style,noscript,svg,canvas,iframe")
      .forEach((n) => n.remove());
    const raw = (clone.innerText || clone.textContent || "")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
    return raw.slice(0, 20000);
  }

  function showPanel(text, detected) {
    ensureStyle();
    let panel = document.getElementById(PANEL_ID);
    if (!panel) {
      panel = document.createElement("div");
      panel.id = PANEL_ID;
      document.documentElement.appendChild(panel);
    }
    panel.innerHTML = "";

    const closeBtn = document.createElement("button");
    closeBtn.className = "__tb-close";
    closeBtn.textContent = "关闭";
    closeBtn.onclick = () => { panel.style.display = "none"; };

    const body = document.createElement("div");
    body.textContent = text;

    panel.appendChild(closeBtn);
    panel.appendChild(body);

    if (detected) {
      const tag = document.createElement("div");
      tag.className = "__tb-detected";
      tag.textContent = "检测语言：" + detected + " → 中文";
      panel.appendChild(tag);
    }

    const copy = document.createElement("button");
    copy.className = "__tb-copy";
    copy.textContent = "复制译文";
    copy.onclick = () => navigator.clipboard.writeText(text).catch(() => {});
    panel.appendChild(copy);

    panel.style.display = "block";
    panel.scrollTop = 0;
  }

  // 供扩展弹窗（popup）触发整页翻译
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg && msg.type === "translateActive") {
      onFabClick();
    }
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => { ensureStyle(); createFab(); });
  } else {
    ensureStyle();
    createFab();
  }
})();
