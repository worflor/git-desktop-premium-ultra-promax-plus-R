import { createEffect, createSignal, onCleanup, onMount, For, Show } from "solid-js";
import { Portal } from "solid-js/web";

export interface SelectOption {
  id: string;
  label: string;
  description?: string;
}

interface SelectProps {
  value: string;
  options: readonly SelectOption[];
  onChange: (value: string) => void;
  ariaLabel?: string;
  class?: string;
}

export function Select(props: SelectProps) {
  const [isOpen, setIsOpen] = createSignal(false);
  let triggerRef: HTMLButtonElement | undefined;
  let popupRef: HTMLDivElement | undefined;

  const activeOption = () => props.options.find((o) => o.id === props.value);

  const closePopup = () => {
    setIsOpen(false);
  };

  const handlePointerDownOutside = (event: PointerEvent) => {
    if (
      isOpen() &&
      triggerRef &&
      !triggerRef.contains(event.target as Node) &&
      popupRef &&
      !popupRef.contains(event.target as Node)
    ) {
      closePopup();
    }
  };

  const handleKeyDown = (event: KeyboardEvent) => {
    if (event.key === "Escape" && isOpen()) {
      event.preventDefault();
      closePopup();
      triggerRef?.focus();
    }
  };

  onMount(() => {
    document.addEventListener("pointerdown", handlePointerDownOutside);
    document.addEventListener("keydown", handleKeyDown);
    onCleanup(() => {
      document.removeEventListener("pointerdown", handlePointerDownOutside);
      document.removeEventListener("keydown", handleKeyDown);
    });
  });

  const toggleOpen = () => setIsOpen(!isOpen());

  const handleSelect = (id: string) => {
    closePopup();
    props.onChange(id);
  };

  // Re-calculate position on scroll/resize for the Portal
  const [coords, setCoords] = createSignal({ top: 0, left: 0, width: 0 });

  const updateCoords = () => {
    if (triggerRef) {
      const rect = triggerRef.getBoundingClientRect();
      setCoords({
        top: rect.bottom + window.scrollY,
        left: rect.left + window.scrollX,
        width: rect.width,
      });
    }
  };

  createEffect(() => {
    if (isOpen()) {
      updateCoords();
      window.addEventListener("scroll", updateCoords, true);
      window.addEventListener("resize", updateCoords);
    } else {
      window.removeEventListener("scroll", updateCoords, true);
      window.removeEventListener("resize", updateCoords);
    }
  });

  onCleanup(() => {
    window.removeEventListener("scroll", updateCoords, true);
    window.removeEventListener("resize", updateCoords);
  });

  return (
    <div class={`custom-select-container ${props.class ?? ""}`}>
      <button
        ref={triggerRef}
        type="button"
        class="custom-select-trigger"
        onClick={() => {
          updateCoords();
          toggleOpen();
        }}
        aria-haspopup="listbox"
        aria-expanded={isOpen()}
        aria-label={props.ariaLabel}
      >
        <span class="custom-select-value">
          {activeOption()?.label ?? props.value}
        </span>
        <svg
          class="custom-select-chevron"
          classList={{ "is-open": isOpen() }}
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <polyline points="6 9 12 15 18 9" />
        </svg>
      </button>

      <Show when={isOpen()}>
        <Portal>
          <div
            ref={popupRef}
            class="custom-select-popup"
            onKeyDown={handleKeyDown}
            style={{
              top: `${coords().top + 4}px`,
              left: `${coords().left}px`,
              width: `${coords().width}px`,
            }}
          >
            <ul class="custom-select-list" role="listbox">
              <For each={props.options}>
                {(option) => (
                  <li
                    class="custom-select-option"
                    classList={{ "is-active": option.id === props.value }}
                    onClick={() => handleSelect(option.id)}
                    role="option"
                    aria-selected={option.id === props.value}
                  >
                    <div class="custom-select-option-label">{option.label}</div>
                    <Show when={option.description}>
                      <div class="custom-select-option-description">
                        {option.description}
                      </div>
                    </Show>
                  </li>
                )}
              </For>
            </ul>
          </div>
        </Portal>
      </Show>
    </div>
  );
}
