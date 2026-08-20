/*
 * MIRADOR UI helpers — small, dependency-free utilities shared across
 * pages for accessibility and link-safety. Additive only: nothing here
 * replaces or depends on page-specific dashboard/auth logic, so it is
 * safe to include on any page independently.
 */
(() => {
  "use strict";

  /**
   * Traps Tab/Shift+Tab focus inside `container` (a modal or drawer) and
   * calls `onEscape` when Escape is pressed. Returns a cleanup function
   * that removes the listeners — call it when the dialog closes.
   */
  function miradorTrapFocus(container, onEscape) {
    if (!container) {
      return () => {};
    }

    const focusableSelector = [
      "a[href]",
      "button:not([disabled])",
      "textarea:not([disabled])",
      "input:not([disabled])",
      "select:not([disabled])",
      '[tabindex]:not([tabindex="-1"])',
    ].join(",");

    function handleKeydown(event) {
      if (event.key === "Escape") {
        if (typeof onEscape === "function") {
          onEscape(event);
        }
        return;
      }

      if (event.key !== "Tab") {
        return;
      }

      const focusable = Array.from(
        container.querySelectorAll(focusableSelector),
      ).filter((el) => el.offsetParent !== null);

      if (focusable.length === 0) {
        return;
      }

      const first = focusable[0];
      const last = focusable[focusable.length - 1];

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }

    container.addEventListener("keydown", handleKeydown);

    return () => {
      container.removeEventListener("keydown", handleKeydown);
    };
  }

  /**
   * Moves focus into `container` (first focusable element, or the
   * container itself) and returns the element that had focus before,
   * so the caller can restore it on close.
   */
  function miradorFocusDialog(container) {
    const previouslyFocused = document.activeElement;

    if (container) {
      const target =
        container.querySelector(
          '[autofocus], a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ) || container;

      if (typeof target.focus === "function") {
        target.focus();
      }
    }

    return previouslyFocused;
  }

  /**
   * Ensures an anchor that opens in a new tab cannot use
   * window.opener to navigate the original tab (reverse tabnabbing),
   * and does not leak the referrer. Safe to call on any anchor.
   */
  function miradorHardenExternalLink(anchor) {
    if (!anchor || anchor.tagName !== "A") {
      return;
    }

    if (anchor.getAttribute("target") === "_blank") {
      const rel = new Set(
        (anchor.getAttribute("rel") || "").split(/\s+/).filter(Boolean),
      );
      rel.add("noopener");
      rel.add("noreferrer");
      anchor.setAttribute("rel", Array.from(rel).join(" "));
    }
  }

  /** Hardens every target="_blank" anchor currently in the document. */
  function miradorHardenExternalLinksIn(root) {
    const scope = root || document;
    scope
      .querySelectorAll('a[target="_blank"]')
      .forEach(miradorHardenExternalLink);
  }

  function miradorPrefersReducedMotion() {
    return (
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    );
  }

  window.MiradorUI = {
    trapFocus: miradorTrapFocus,
    focusDialog: miradorFocusDialog,
    hardenExternalLink: miradorHardenExternalLink,
    hardenExternalLinksIn: miradorHardenExternalLinksIn,
    prefersReducedMotion: miradorPrefersReducedMotion,
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () =>
      miradorHardenExternalLinksIn(document),
    );
  } else {
    miradorHardenExternalLinksIn(document);
  }
})();
