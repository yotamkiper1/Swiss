// Right-click → Save to Swiss Recent.
// Pictures, videos and sounds are downloaded into Downloads/Swiss, which Swiss watches
// (in Swiss, turn on Downloads in Recent, or Settings → Capture → Capture downloads).
// Links, pages and selected words go straight to Recent through a swiss:// link.

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: "swiss-media", title: "Save to Swiss Recent", contexts: ["image", "video", "audio"] });
  chrome.contextMenus.create({ id: "swiss-link", title: "Add Link to Swiss Recent", contexts: ["link"] });
  chrome.contextMenus.create({ id: "swiss-text", title: "Add Text to Swiss Recent", contexts: ["selection"] });
  chrome.contextMenus.create({ id: "swiss-page", title: "Add Page to Swiss Recent", contexts: ["page"] });
});

// A safe file name from the address (pictures embedded as data: get one from their type).
function fileName(src) {
  if (src.startsWith("data:")) {
    const type = (src.slice(5).split(";")[0] || "image/png").split("/")[1] || "png";
    return "picture." + type.replace("jpeg", "jpg").replace("svg+xml", "svg");
  }
  try {
    const last = decodeURIComponent(new URL(src).pathname.split("/").pop() || "");
    const clean = last.replace(/[\\/:*?"<>|]/g, "-").slice(0, 120);
    return clean || "download";
  } catch (e) {
    return "download";
  }
}

// Opens swiss://recent?text=… in the current tab: Chrome hands it to Swiss and the page stays as it is.
// (The first time, Chrome asks whether to open Swiss — tick "Always allow".)
function sendToSwiss(text, tab) {
  if (!text) return;
  const url = "swiss://recent?text=" + encodeURIComponent(text.slice(0, 20000));
  if (tab && tab.id !== undefined) chrome.tabs.update(tab.id, { url });
  else chrome.tabs.create({ url });
}

chrome.contextMenus.onClicked.addListener((info, tab) => {
  switch (info.menuItemId) {
    case "swiss-media":
      if (info.srcUrl) {
        chrome.downloads.download({ url: info.srcUrl, filename: "Swiss/" + fileName(info.srcUrl), conflictAction: "uniquify", saveAs: false });
      }
      break;
    case "swiss-link":
      sendToSwiss(info.linkUrl, tab);
      break;
    case "swiss-text":
      sendToSwiss(info.selectionText, tab);
      break;
    case "swiss-page":
      sendToSwiss(info.pageUrl, tab);
      break;
  }
});
