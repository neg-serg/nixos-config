// dsh-gui-tweaks client half — browser GUI behavior tweaks for the dsh web
// profile. Pure DOM behavior on top of the stock UI; no upstream bundles are
// touched (the @deepseek-ai store is immutable, so this lives in a plain
// profile plugin, same as dsh-terminal-ui).
//
//   1) Question dialogs with numbered options answer on the digit keys, from
//      anywhere in the page — no focus inside the dialog needed. The dialog
//      shows numbers 1..N next to single-select options; pressing the digit
//      activates that option immediately (the flow auto-advances/submits).
//      Enter confirms the current selection the same way: it clicks the
//      primary footer action (Next/Submit), which stays disabled until a
//      question is answered, so Enter without a selection does nothing.
//   2) Bash tool rows expand by default: each bash call renders as a
//      collapsed one-line row and opens on click; every expandable bash row
//      is clicked once when it first appears. Rows the user later collapses
//      by hand stay collapsed (same element is remembered, only fresh mounts
//      are re-expanded).
//   3) The bash terminal output height cap (224px, internal scroll) is
//      removed, so the whole command output is visible in the card.
//
// All selectors use stable data attributes stamped by the upstream
// components, so they survive bundle upgrades (unlike CSS-module hashes).
window.__ModuleLoader__.load({
  id: "dsh-gui-tweaks",
  factory: (require) => {
    const inject = [];

    // ---- 1) digit keys answer numbered question dialogs ----
    // Ask-user questions render one option button per entry, numbered 1..N.
    // The dialog frame is stamped `data-question-key`; multi-select questions
    // show checkboxes without numbers and are intentionally not bound.
    const DIGIT_OPTION_INDEX = Object.freeze({
      1: 0,
      2: 1,
      3: 2,
      4: 3,
      5: 4,
      6: 5,
      7: 6,
      8: 7,
      9: 8,
    });

    function onQuestionKeyDown(event) {
      if (event.altKey || event.ctrlKey || event.metaKey || event.isComposing) return;
      const target = event.target;
      if (target instanceof HTMLElement) {
        const tag = target.tagName;
        // Never hijack digits while the user is typing (composer, custom input).
        if (tag === "INPUT" || tag === "TEXTAREA" || target.isContentEditable) return;
      }
      const frame = document.querySelector("[data-question-key]");
      if (frame === null) return;

      // Enter confirms the current selection by clicking the primary footer
      // action (Next/Submit). It is disabled until the question is answered,
      // so Enter without a selection is a no-op. stopPropagation keeps the
      // event from also reaching an option button (whose own Enter handler
      // would submit again) when focus happens to sit on one.
      if (event.key === "Enter") {
        // Primary footer action (Next/Submit): structurally the last button
        // of the footer actions row; fall back to the last button in the
        // dialog DOM, which is the same Submit in the stock layout.
        const submit = frame.querySelector(
          "footer > div:last-child > button:last-child"
        ) ?? Array.from(frame.querySelectorAll("button")).at(-1);
        if (submit === null || submit.disabled) return;
        event.preventDefault();
        event.stopPropagation();
        submit.click();
        return;
      }

      const index = DIGIT_OPTION_INDEX[event.key];
      if (index === undefined) return;
      const option = frame.querySelectorAll('button[role="radio"]')[index];
      if (option === undefined || option.disabled) return;
      event.preventDefault();
      option.click();
    }

    // ---- 2) bash tool rows expand by default ----
    const BASH_ROW_SELECTOR = '[data-sample="bash"][data-expandable][aria-expanded="false"]';
    const handledRows = new WeakSet();

    function expandBashRows() {
      for (const row of document.querySelectorAll(BASH_ROW_SELECTOR)) {
        if (handledRows.has(row)) continue;
        handledRows.add(row);
        row.click();
      }
    }

    // ---- 3) bash terminal output uncapped ----
    // The bash sample stylesheet caps the terminal output at 224px via
    // --dsl-terminal-output-max-height on the terminal block. Drop the cap
    // for terminals inside a bash card so the full output is visible.
    const BASH_OUTPUT_CAP_CSS = `
      div:has(> [data-sample="bash"]) [data-terminal] {
        --dsl-terminal-output-max-height: none !important;
      }
    `;

    function apply(ctx) {
      ctx.effect(() => {
        window.addEventListener("keydown", onQuestionKeyDown, true);

        const observer = new MutationObserver(expandBashRows);
        observer.observe(document.body, { childList: true, subtree: true });
        expandBashRows(); // catch rows already mounted before the observer

        const style = document.createElement("style");
        style.setAttribute("data-plugin", "dsh-gui-tweaks");
        style.textContent = BASH_OUTPUT_CAP_CSS;
        document.head.appendChild(style);

        return () => {
          window.removeEventListener("keydown", onQuestionKeyDown, true);
          observer.disconnect();
          style.remove();
        };
      });
    }

    return { apply, inject };
  },
});
