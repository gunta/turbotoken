(ns turbotoken.encoding
  "Encoding wrapper -- provides Clojure-idiomatic access to the Java Encoding."
  (:require [turbotoken.chat :as chat])
  (:import [com.turbotoken Encoding]))

(defrecord TurboEncoding [^Encoding java-encoding name spec rank-payload])

(defn encode
  "Encodes text into a vector of BPE token IDs."
  [^TurboEncoding enc ^String text]
  (vec (.encode ^Encoding (:java-encoding enc) text)))

(defn decode
  "Decodes a sequence of BPE token IDs back to a string."
  [^TurboEncoding enc tokens]
  (.decode ^Encoding (:java-encoding enc) (int-array tokens)))

(defn count-tokens
  "Counts the number of tokens in the given text."
  [^TurboEncoding enc ^String text]
  (.count ^Encoding (:java-encoding enc) text))

(defn within-token-limit?
  "Checks if the text is within the given token limit.
   Returns the token count if within the limit, or nil if exceeded."
  [^TurboEncoding enc ^String text ^long limit]
  (let [result (.isWithinTokenLimit ^Encoding (:java-encoding enc) text (int limit))]
    (when (.isPresent result)
      (.getAsInt result))))

;; ── Chat operations ──────────────────────────────────────────────────

(defn encode-chat
  "Encodes a sequence of chat messages into a vector of token IDs.
   Messages are maps with :role, :content, and optional :name keys.
   Options: :template (:turbotoken-v1 or :im-tokens), :prime (boolean)."
  [enc messages & {:as opts}]
  (let [formatted (chat/format-messages messages (or opts {}))]
    (encode enc formatted)))

(defn count-chat
  "Counts tokens in a sequence of chat messages."
  [enc messages & {:as opts}]
  (let [formatted (chat/format-messages messages (or opts {}))]
    (count-tokens enc formatted)))

(defn chat-within-token-limit?
  "Checks if a chat conversation is within the token limit.
   Returns the token count if within the limit, or nil if exceeded."
  [enc messages limit & {:as opts}]
  (let [formatted (chat/format-messages messages (or opts {}))]
    (within-token-limit? enc formatted limit)))

;; ── File operations ──────────────────────────────────────────────────

(defn encode-file-path
  "Encodes the contents of a file into a vector of BPE token IDs."
  [^TurboEncoding enc ^String path]
  (vec (.encodeFilePath ^Encoding (:java-encoding enc) path)))

(defn count-file-path
  "Counts tokens in a file."
  [^TurboEncoding enc ^String path]
  (.countFilePath ^Encoding (:java-encoding enc) path))

(defn file-path-within-token-limit?
  "Checks if a file's contents are within the token limit.
   Returns the token count if within the limit, or nil if exceeded."
  [^TurboEncoding enc ^String path ^long limit]
  (let [result (.isFilePathWithinTokenLimit ^Encoding (:java-encoding enc) path (int limit))]
    (when (.isPresent result)
      (.getAsInt result))))
