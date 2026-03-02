(ns turbotoken.core
  "Main entry point for the turbotoken Clojure API.

   Usage:
     (require '[turbotoken.core :as tt])
     (require '[turbotoken.encoding :as enc])

     (def e (tt/get-encoding \"cl100k_base\"))
     (enc/encode e \"hello world\")
     ;; => [15339 1917]

     ;; Or by model name:
     (def e2 (tt/get-encoding-for-model \"gpt-4o\"))
  "
  (:require [turbotoken.registry :as registry]
            [turbotoken.encoding :as encoding])
  (:import [com.turbotoken TurboToken Encoding]))

(defonce ^:private encoding-cache (atom {}))

(defn version
  "Returns the native library version string."
  []
  (TurboToken/version))

(defn get-encoding
  "Returns a TurboEncoding for the given encoding name (e.g. \"cl100k_base\", \"o200k_base\").
   Encoding instances are cached and reused."
  [name]
  (or (get @encoding-cache name)
      (let [spec      (registry/get-encoding-spec name)
            java-enc  (TurboToken/getEncoding name)
            enc       (encoding/->TurboEncoding java-enc name spec nil)]
        (swap! encoding-cache assoc name enc)
        enc)))

(defn get-encoding-for-model
  "Returns a TurboEncoding for the given model name (e.g. \"gpt-4o\", \"gpt-3.5-turbo\")."
  [model]
  (let [encoding-name (registry/model->encoding model)]
    (get-encoding encoding-name)))

(defn list-encoding-names
  "Returns a sorted sequence of all supported encoding names."
  []
  (registry/list-encoding-names))
