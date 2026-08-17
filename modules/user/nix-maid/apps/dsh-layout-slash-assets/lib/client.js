/**
 * dsh-layout-slash, browser half.
 *
 * In the composer (the chat input), when the very first character typed is
 * "." — which is what the "/" key produces under the Russian layout — replace
 * it with "/" and ask the host to switch the keyboard layout to English (us).
 * A "." typed later in the text (normal Russian punctuation) is left alone.
 *
 * Implementation notes:
 *  - The composer textarea is a React-controlled input (`value: draft`,
 *    `onChange`), so the value is written through the native prototype
 *    setter followed by a bubbling `input` event — the stock onChange reads
 *    `e.target.value` and updates the draft state.
 *  - `beforeinput` fires before React ever sees the change; preventDefault
 *    swallows the dot, so the draft never contains a transient ".".
 *  - Only direct text insertion of a single "." is intercepted: pastes and
 *    IME composition pass through untouched.
 */

window.__ModuleLoader__.load({
  id: "dsh-layout-slash",
  factory: (require) => {
    const inject = [];

    const SWITCH_ENDPOINT = "/hypr-layout/switch";

    function isComposer(target) {
      return (
        target instanceof HTMLTextAreaElement &&
        target.closest("[data-composer-card]") !== null
      );
    }

    // React-controlled textarea: native setter + bubbling input event, so the
    // app's onChange (e.target.value) updates its draft state.
    function setComposerValue(el, text) {
      const setter = Object.getOwnPropertyDescriptor(
        window.HTMLTextAreaElement.prototype,
        "value",
      ).set;
      setter.call(el, text);
      el.dispatchEvent(new Event("input", { bubbles: true }));
    }

    // Fire-and-forget: the host flips the layout to us for the next keys.
    function switchLayoutToUs() {
      fetch(SWITCH_ENDPOINT, { method: "POST", cache: "no-store" }).catch(() => {});
    }

    function onBeforeInput(event) {
      if (event.isComposing) return;
      const el = event.target;
      if (!isComposer(el)) return;
      // Only a literal "." being typed (pastes / other input types pass).
      if (event.data !== ".") return;
      // Only as the very first character of a fresh message.
      if (el.value !== "") return;
      if (el.selectionStart !== 0 || el.selectionEnd !== 0) return;

      event.preventDefault();
      setComposerValue(el, "/");
      switchLayoutToUs();
    }

    function apply(ctx) {
      ctx.effect(() => {
        document.addEventListener("beforeinput", onBeforeInput, true);
        return () => {
          document.removeEventListener("beforeinput", onBeforeInput, true);
        };
      });
    }

    return { apply, inject, name: "dsh-layout-slash" };
  },
});
