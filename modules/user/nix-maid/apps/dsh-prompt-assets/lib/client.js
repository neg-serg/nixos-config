// dsh-prompt client half — browser placeholder tweak for the dsh web profile.
// Replaces the stock composer placeholder ("Message the agent" / "给智能体发消息")
// with a terminal-style "❯_" prompt. Pure browser-side override; no upstream
// bundles are touched (the @deepseek-ai store is immutable, so this lives in a
// plain profile plugin, same as dsh-gui-tweaks).
//
// Two layers, so the placeholder is right in every render path:
//   1) The locale service's `translate` is wrapped: any future
//      `conversation.placeholder.default` lookup returns "❯_" at the source,
//      so React renders the glyph directly. The glyph is locale-independent,
//      so the same value serves the en and zh dictionaries.
//   2) A MutationObserver rewrites the textarea's placeholder attribute when
//      it still carries a stock default string — catching the composer that
//      was already mounted before this plugin activated, and any render path
//      that sets the attribute without going through the locale service.
window.__ModuleLoader__.load({
  id: "dsh-prompt",
  factory: (require) => {
    const name = "dsh-prompt";
    const inject = ["locale"];

    // Placeholder text of the default (idle) composer state, per locale.
    const STOCK_PLACEHOLDER_DEFAULT = new Set(["Message the agent", "给智能体发消息"]);
    const PROMPT = "❯_";

    function apply(ctx) {
      ctx.effect(() => {
        const locale = ctx.locale;
        const originalTranslate = locale.translate.bind(locale);
        locale.translate = function (ns, key, params) {
          if (ns === "conversation" && key === "placeholder.default") return PROMPT;
          return originalTranslate(ns, key, params);
        };

        const fix = () => {
          for (const el of document.querySelectorAll("textarea")) {
            if (STOCK_PLACEHOLDER_DEFAULT.has(el.placeholder)) el.placeholder = PROMPT;
          }
        };
        const observer = new MutationObserver(fix);
        observer.observe(document.body, {
          subtree: true,
          childList: true,
          attributes: true,
          attributeFilter: ["placeholder"],
        });
        fix(); // composer already mounted before this plugin activated

        return () => {
          locale.translate = originalTranslate;
          observer.disconnect();
        };
      });
    }

    return { apply, inject, name };
  },
});
