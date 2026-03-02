(ns turbotoken.chat
  "Chat message formatting for token counting and encoding.")

;; ── Chat template modes ──────────────────────────────────────────────

(defn resolve-chat-template
  "Resolves a chat template mode keyword to a template map.
   Supported modes: :turbotoken-v1, :im-tokens"
  [mode]
  (case mode
    :turbotoken-v1
    {:message-prefix   "<|im_start|>"
     :message-suffix   "<|im_end|>\n"
     :assistant-prefix "<|im_start|>assistant\n"}

    :im-tokens
    {:message-prefix   "<|im_start|>"
     :message-suffix   "<|im_end|>\n"
     :assistant-prefix "<|im_start|>assistant\n"}

    (throw (ex-info (str "Unknown chat template mode: " mode)
                    {:type :unknown-template-mode :mode mode}))))

(defn format-messages
  "Formats a sequence of chat message maps into a single string for tokenization.

   Each message is a map with keys:
     :role    - string (required)
     :content - string (required)
     :name    - string (optional)

   Options:
     :template  - :turbotoken-v1 (default) or :im-tokens
     :prime     - truthy to append assistant prefix (default true)"
  ([messages]
   (format-messages messages {}))
  ([messages {:keys [template prime] :or {template :turbotoken-v1 prime true}}]
   (let [tmpl (resolve-chat-template template)
         sb   (StringBuilder.)]
     (doseq [{:keys [role content name]} messages]
       (.append sb (:message-prefix tmpl))
       (.append sb role)
       (when name
         (.append sb (str " name=" name)))
       (.append sb \newline)
       (.append sb (or content ""))
       (.append sb (:message-suffix tmpl)))
     (when prime
       (.append sb (:assistant-prefix tmpl)))
     (.toString sb))))
