class SharePreprocessor {
  run(args) {
    args.completionFunction({
      url: document.URL,
      title: document.title,
      html: document.documentElement.outerHTML,
      // Pre-extract JSON-LD for fast-path (skip Readability if available)
      jsonLd: Array.from(document.querySelectorAll('script[type="application/ld+json"]'))
        .map(s => s.textContent)
    });
  }
}
var ExtensionPreprocessingJS = new SharePreprocessor();
