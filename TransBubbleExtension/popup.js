document.getElementById("go").addEventListener("click", async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab && tab.id) {
    try {
      await chrome.tabs.sendMessage(tab.id, { type: "translateActive" });
      window.close();
    } catch (e) {
      alert("无法连接页面，请刷新后重试");
    }
  }
});
