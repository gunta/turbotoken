(ns turbotoken.core-test
  (:require [clojure.test :refer :all]
            [turbotoken.core :as tt]
            [turbotoken.registry :as registry]
            [turbotoken.chat :as chat]))

;; ── Registry tests ───────────────────────────────────────────────────

(deftest list-encoding-names-test
  (let [names (registry/list-encoding-names)]
    (is (= 7 (count names)))
    (is (= names (sort names)))
    (is (some #{"o200k_base"} names))
    (is (some #{"cl100k_base"} names))
    (is (some #{"p50k_base"} names))
    (is (some #{"r50k_base"} names))
    (is (some #{"gpt2"} names))
    (is (some #{"p50k_edit"} names))
    (is (some #{"o200k_harmony"} names))))

(deftest get-encoding-spec-o200k-test
  (let [spec (registry/get-encoding-spec "o200k_base")]
    (is (= "o200k_base" (:name spec)))
    (is (= 200019 (:n-vocab spec)))
    (is (= 199999 (get (:special-tokens spec) "<|endoftext|>")))
    (is (= 200018 (get (:special-tokens spec) "<|endofprompt|>")))))

(deftest get-encoding-spec-cl100k-test
  (let [spec (registry/get-encoding-spec "cl100k_base")]
    (is (= "cl100k_base" (:name spec)))
    (is (= 100277 (:n-vocab spec)))
    (is (= 5 (count (:special-tokens spec))))
    (is (= 100257 (get (:special-tokens spec) "<|endoftext|>")))
    (is (= 100258 (get (:special-tokens spec) "<|fim_prefix|>")))
    (is (= 100259 (get (:special-tokens spec) "<|fim_middle|>")))
    (is (= 100260 (get (:special-tokens spec) "<|fim_suffix|>")))
    (is (= 100276 (get (:special-tokens spec) "<|endofprompt|>")))))

(deftest get-encoding-spec-p50k-test
  (let [spec (registry/get-encoding-spec "p50k_base")]
    (is (= 50281 (:n-vocab spec)))
    (is (= 50256 (get (:special-tokens spec) "<|endoftext|>")))))

(deftest get-encoding-spec-r50k-test
  (let [spec (registry/get-encoding-spec "r50k_base")]
    (is (= 50257 (:n-vocab spec)))))

(deftest get-encoding-spec-gpt2-test
  (let [spec (registry/get-encoding-spec "gpt2")]
    (is (= 50257 (:n-vocab spec)))
    (is (clojure.string/includes? (:rank-file-url spec) "r50k_base"))))

(deftest get-encoding-spec-p50k-edit-test
  (let [spec (registry/get-encoding-spec "p50k_edit")]
    (is (= 50281 (:n-vocab spec)))
    (is (clojure.string/includes? (:rank-file-url spec) "p50k_base"))))

(deftest get-encoding-spec-o200k-harmony-test
  (let [spec (registry/get-encoding-spec "o200k_harmony")]
    (is (= 200019 (:n-vocab spec)))
    (is (clojure.string/includes? (:rank-file-url spec) "o200k_base"))))

(deftest get-encoding-spec-unknown-test
  (is (thrown-with-msg? clojure.lang.ExceptionInfo #"Unknown encoding"
        (registry/get-encoding-spec "nonexistent"))))

;; ── Model resolution tests ───────────────────────────────────────────

(deftest model-to-encoding-exact-test
  (is (= "o200k_base"    (registry/model->encoding "gpt-4o")))
  (is (= "cl100k_base"   (registry/model->encoding "gpt-4")))
  (is (= "cl100k_base"   (registry/model->encoding "gpt-3.5-turbo")))
  (is (= "p50k_base"     (registry/model->encoding "text-davinci-003")))
  (is (= "r50k_base"     (registry/model->encoding "davinci")))
  (is (= "gpt2"          (registry/model->encoding "gpt2")))
  (is (= "o200k_harmony" (registry/model->encoding "gpt-oss-120b"))))

(deftest model-to-encoding-prefix-test
  (is (= "o200k_base"    (registry/model->encoding "gpt-4o-2024-05-13")))
  (is (= "cl100k_base"   (registry/model->encoding "gpt-4-0613")))
  (is (= "cl100k_base"   (registry/model->encoding "gpt-3.5-turbo-0125")))
  (is (= "o200k_base"    (registry/model->encoding "o1-preview")))
  (is (= "o200k_base"    (registry/model->encoding "o3-mini")))
  (is (= "o200k_harmony" (registry/model->encoding "gpt-oss-beta"))))

(deftest model-to-encoding-finetune-test
  (is (= "o200k_base"  (registry/model->encoding "ft:gpt-4o:myorg")))
  (is (= "cl100k_base" (registry/model->encoding "ft:gpt-4:myorg")))
  (is (= "cl100k_base" (registry/model->encoding "ft:gpt-3.5-turbo:myorg")))
  (is (= "cl100k_base" (registry/model->encoding "ft:davinci-002:myorg")))
  (is (= "cl100k_base" (registry/model->encoding "ft:babbage-002:myorg"))))

(deftest model-to-encoding-unknown-test
  (is (thrown-with-msg? clojure.lang.ExceptionInfo #"Could not automatically map"
        (registry/model->encoding "completely-unknown-model"))))

;; ── Chat template tests ──────────────────────────────────────────────

(deftest resolve-chat-template-v1-test
  (let [tmpl (chat/resolve-chat-template :turbotoken-v1)]
    (is (= "<|im_start|>" (:message-prefix tmpl)))
    (is (= "<|im_end|>\n" (:message-suffix tmpl)))
    (is (= "<|im_start|>assistant\n" (:assistant-prefix tmpl)))))

(deftest resolve-chat-template-im-tokens-test
  (let [tmpl (chat/resolve-chat-template :im-tokens)]
    (is (= "<|im_start|>" (:message-prefix tmpl)))
    (is (= "<|im_end|>\n" (:message-suffix tmpl)))
    (is (= "<|im_start|>assistant\n" (:assistant-prefix tmpl)))))

(deftest format-messages-test
  (let [messages [{:role "user" :content "hello"}
                  {:role "assistant" :content "hi there"}]
        formatted (chat/format-messages messages)]
    (is (clojure.string/includes? formatted "<|im_start|>user\nhello<|im_end|>"))
    (is (clojure.string/includes? formatted "<|im_start|>assistant\nhi there<|im_end|>"))
    (is (clojure.string/ends-with? formatted "<|im_start|>assistant\n"))))

(deftest format-messages-with-name-test
  (let [messages [{:role "user" :name "alice" :content "hello"}]
        formatted (chat/format-messages messages)]
    (is (clojure.string/includes? formatted "user name=alice"))))

(deftest format-messages-no-prime-test
  (let [messages [{:role "user" :content "hello"}]
        formatted (chat/format-messages messages {:prime false})]
    (is (not (clojure.string/ends-with? formatted "<|im_start|>assistant\n")))))
